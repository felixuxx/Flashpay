/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_db.c
 * @brief High-level (transactional-layer) database operations for the mint.
 * @author Christian Grothoff
 *
 * TODO:
 * - actually abstract DB implementation (i.e. via plugin logic)
 *   (this file should remain largely unchanged with the exception
 *    of the PQ-specific DB handle types)
 */
#include "platform.h"
#include <pthread.h>
#include <jansson.h>
#include "taler-mint-httpd_db.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_responses.h"
#include "mint_db.h"
#include "taler_util.h"
#include "taler-mint-httpd_keystate.h"


/**
 * Get an amount in the mint's currency that is zero.
 *
 * @return zero amount in the mint's currency
 */
static struct TALER_Amount
mint_amount_native_zero ()
{
  struct TALER_Amount amount;

  memset (&amount,
          0,
          sizeof (amount));
  memcpy (amount.currency,
          MINT_CURRENCY,
          strlen (MINT_CURRENCY) + 1);
  return amount;
}


/**
 * Execute a deposit.  The validity of the coin and signature
 * have already been checked.  The database must now check that
 * the coin is not (double or over) spent, and execute the
 * transaction (record details, generate success or failure response).
 *
 * @param connection the MHD connection to handle
 * @param deposit information about the deposit
 * @return MHD result code
 */
int
TALER_MINT_db_execute_deposit (struct MHD_Connection *connection,
                               const struct Deposit *deposit)
{
  PGconn *db_conn;
  struct TALER_MINT_DB_TransactionList *tl;
  struct TALER_MINT_DB_TransactionList *pos;
  struct TALER_Amount spent;
  struct TALER_Amount value;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_refresh;
  struct MintKeyState *mks;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  int ret;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection (GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_YES ==
      TALER_MINT_DB_have_deposit (db_conn,
                                  deposit))
  {
    return TALER_MINT_reply_deposit_success (connection,
                                             &deposit->coin.coin_pub,
                                             &deposit->h_wire,
                                             &deposit->h_contract,
                                             deposit->transaction_id,
                                             &deposit->merchant_pub,
                                             &deposit->amount);
  }
  mks = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (mks,
                                  deposit->coin.denom_pub);
  value = TALER_amount_ntoh (dki->issue.value);
  fee_deposit = TALER_amount_ntoh (dki->issue.fee_deposit);
  fee_refresh = TALER_amount_ntoh (dki->issue.fee_refresh);
  TALER_MINT_key_state_release (mks);

  if (GNUNET_OK !=
      TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  tl = TALER_MINT_DB_get_coin_transactions (db_conn,
                                            &deposit->coin.coin_pub);
  spent = fee_withdraw; /* fee for THIS transaction */
  /* FIXME: need to deal better with integer overflows
     in the logic that follows! (change amount.c API! -- #3637) */
  spent = TALER_amount_add (spent,
                            deposit->amount);

  for (pos = tl; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_MINT_DB_TT_DEPOSIT:
      spent = TALER_amount_add (spent,
                                pos->details.deposit->amount);
      spent = TALER_amount_add (spent,
                                fee_deposit);
      break;
    case TALER_MINT_DB_TT_REFRESH_MELT:
      spent = TALER_amount_add (spent,
                                pos->details.melt->amount);
      spent = TALER_amount_add (spent,
                                fee_refresh);
      break;
    case TALER_MINT_DB_TT_LOCK:
      /* should check if lock is still active,
         and if it is for THIS operation; if
         lock is inactive, delete it; if lock
         is for THIS operation, ignore it;
         if lock is for another operation,
         count it! */
      GNUNET_assert (0);  // FIXME: not implemented! (#3625)
      break;
    }
  }

  if (0 < TALER_amount_cmp (spent, value))
  {
    TALER_MINT_DB_rollback (db_conn);
    ret = TALER_MINT_reply_deposit_insufficient_funds (connection,
                                               tl);
    TALER_MINT_DB_free_coin_transaction_list (tl);
    return ret;
  }
  TALER_MINT_DB_free_coin_transaction_list (tl);

  if (GNUNET_OK !=
      TALER_MINT_DB_insert_deposit (db_conn,
                                    deposit))
  {
    LOG_WARNING ("Failed to store /deposit information in database\n");
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/deposit transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }
  return TALER_MINT_reply_deposit_success (connection,
                                           &deposit->coin.coin_pub,
                                           &deposit->h_wire,
                                           &deposit->h_contract,
                                           deposit->transaction_id,
                                           &deposit->merchant_pub,
                                           &deposit->amount);
}


/**
 * Execute a /withdraw/status.  Given the public key of a reserve,
 * return the associated transaction history.
 *
 * @param connection the MHD connection to handle
 * @param reserve_pub public key of the reserve to check
 * @return MHD result code
 */
int
TALER_MINT_db_execute_withdraw_status (struct MHD_Connection *connection,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub)
{
  PGconn *db_conn;
  struct ReserveHistory *rh;
  int res;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection (GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  rh = TALER_MINT_DB_get_reserve_history (db_conn,
                                          reserve_pub);
  if (NULL == rh)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error", "Reserve not found");
  res = TALER_MINT_reply_withdraw_status_success (connection,
                                                  rh);
  TALER_MINT_DB_free_reserve_history (rh);
  return res;
}


/**
 * Execute a "/withdraw/sign". Given a reserve and a properly signed
 * request to withdraw a coin, check the balance of the reserve and
 * if it is sufficient, store the request and return the signed
 * blinded envelope.
 *
 * @param connection the MHD connection to handle
 * @param reserve public key of the reserve
 * @param denomination_pub public key of the denomination requested
 * @param blinded_msg blinded message to be signed
 * @param blinded_msg_len number of bytes in @a blinded_msg
 * @param signature signature over the withdraw request, to be stored in DB
 * @return MHD result code
 */
int
TALER_MINT_db_execute_withdraw_sign (struct MHD_Connection *connection,
                                     const struct GNUNET_CRYPTO_EddsaPublicKey *reserve,
                                     const struct GNUNET_CRYPTO_rsa_PublicKey *denomination_pub,
                                     const char *blinded_msg,
                                     size_t blinded_msg_len,
                                     const struct GNUNET_CRYPTO_EddsaSignature *signature)
{
  PGconn *db_conn;
  struct ReserveHistory *rh;
  const struct ReserveHistory *pos;
  struct MintKeyState *key_state;
  struct CollectableBlindcoin collectable;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct TALER_MINT_DenomKeyIssuePriv *tdki;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct TALER_Amount amount_required;
  struct TALER_Amount deposit_total;
  struct TALER_Amount withdraw_total;
  struct TALER_Amount balance;
  struct TALER_Amount value;
  struct GNUNET_HashCode h_blind;
  int res;

  GNUNET_CRYPTO_hash (blinded_msg,
                      blinded_msg_len,
                      &h_blind);

  if (NULL == (db_conn = TALER_MINT_DB_get_connection (GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = TALER_MINT_DB_get_collectable_blindcoin (db_conn,
                                                 &h_blind,
                                                 &collectable);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  /* Don't sign again if we have already signed the coin */
  if (GNUNET_YES == res)
  {
    res = TALER_MINT_reply_withdraw_sign_success (connection,
                                                  &collectable);
    GNUNET_CRYPTO_rsa_signature_free (collectable.sig);
    GNUNET_CRYPTO_rsa_public_key_free (collectable.denom_pub);
    return res;
  }
  GNUNET_assert (GNUNET_NO == res);

  /* Check if balance is sufficient */
  key_state = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (key_state,
                                  denomination_pub);
  if (NULL == dki)
  {
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Denomination not found");
  }
  if (GNUNET_OK !=
      TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  rh = TALER_MINT_DB_get_reserve_history (db_conn,
                                          reserve);
  if (NULL == rh)
  {
    TALER_MINT_DB_rollback (db_conn);
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Reserve not found");
  }

  /* calculate amount required including fees */
  amount_required = TALER_amount_add (TALER_amount_ntoh (dki->issue.value),
                                      TALER_amount_ntoh (dki->issue.fee_withdraw));

  /* calculate balance of the reserve */
  res = 0;
  for (pos = rh; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_MINT_DB_RO_BANK_TO_MINT:
      if (0 == (res & 1))
        deposit_total = pos->details.bank->amount;
      else
        deposit_total = TALER_amount_add (deposit_total,
                                          pos->details.bank->amount);
      res |= 1;
      break;
    case TALER_MINT_DB_RO_WITHDRAW_COIN:
      tdki = TALER_MINT_get_denom_key (key_state,
                                       pos->details.withdraw->denom_pub);
      value = TALER_amount_ntoh (tdki->issue.value);
      if (0 == (res & 2))
        withdraw_total = value;
      else
        withdraw_total = TALER_amount_add (withdraw_total,
                                           value);
      res |= 2;
      break;
    }
  }
  GNUNET_break (0 > TALER_amount_cmp (withdraw_total,
                                      deposit_total));
  balance = TALER_amount_subtract (deposit_total,
                                   withdraw_total);
  if (0 < TALER_amount_cmp (amount_required,
                            balance))
  {
    TALER_MINT_key_state_release (key_state);
    TALER_MINT_DB_rollback (db_conn);
    res = TALER_MINT_reply_withdraw_sign_insufficient_funds (connection,
                                                             rh);
    TALER_MINT_DB_free_reserve_history (rh);
    return res;
  }
  TALER_MINT_DB_free_reserve_history (rh);

  /* Balance is good, sign the coin! */
  sig = GNUNET_CRYPTO_rsa_sign (dki->denom_priv,
                                blinded_msg,
                                blinded_msg_len);
  TALER_MINT_key_state_release (key_state);
  if (NULL == sig)
  {
    GNUNET_break (0);
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_error (connection,
                                            "Internal error");
  }
  collectable.sig = sig;
  collectable.denom_pub = (struct GNUNET_CRYPTO_rsa_PublicKey *) denomination_pub;
  collectable.reserve_pub = *reserve;
  GNUNET_CRYPTO_hash (blinded_msg,
                      blinded_msg_len,
                      &collectable.h_coin_envelope);
  collectable.reserve_sig = *signature;
  if (GNUNET_OK !=
      TALER_MINT_DB_insert_collectable_blindcoin (db_conn,
                                                  &h_blind,
                                                  &collectable))
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_signature_free (sig);
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/withdraw/sign transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }
  res = TALER_MINT_reply_withdraw_sign_success (connection,
                                                &collectable);
  GNUNET_CRYPTO_rsa_signature_free (sig);
  return res;
}


/**
 * Parse coin melt requests from a JSON object and write them to
 * the database.
 *
 * @param connection the connection to send errors to
 * @param db_conn the database connection
 * @param key_state the mint's key state
 * @param session_pub the refresh session's public key
 * @param coin_public_info the coin to melt
 * @param coin_details details about the coin being melted
 * @param oldcoin_index what is the number assigned to this coin
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if an error message was generated,
 *         #GNUNET_SYSERR on internal errors (no response generated)
 */
static int
refresh_accept_melts (struct MHD_Connection *connection,
                      PGconn *db_conn,
                      const struct MintKeyState *key_state,
                      const struct GNUNET_HashCode *melt_hash,
                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                      const struct TALER_CoinPublicInfo *coin_public_info,
                      const struct MeltDetails *coin_details,
                      uint16_t oldcoin_index)
{
  struct TALER_MINT_DenomKeyIssue *dki;
  struct TALER_MINT_DB_TransactionList *tl;
  struct TALER_Amount coin_value;
  struct TALER_Amount coin_residual;
  struct RefreshMelt melt;
  int res;

  dki = &TALER_MINT_get_denom_key (key_state,
                                   coin_public_info->denom_pub)->issue;

  if (NULL == dki)
    return (MHD_YES ==
            TALER_MINT_reply_json_pack (connection,
                                        MHD_HTTP_NOT_FOUND,
                                        "{s:s}",
                                        "error",
                                        "denom not found"))
      ? GNUNET_NO : GNUNET_SYSERR;

  coin_value = TALER_amount_ntoh (dki->value);
  tl = TALER_MINT_DB_get_coin_transactions (db_conn,
                                            &coin_public_info->coin_pub);
  /* FIXME: #3636: compute how much value is left with this coin and
     compare to `expected_value`! (subtract from "coin_value") */
  coin_residual = coin_value;
  /* Refuse to refresh when the coin does not have enough money left to
   * pay the refreshing fees of the coin. */

  if (TALER_amount_cmp (coin_residual,
                        coin_details->melt_amount) < 0)
  {
    res = (MHD_YES ==
           TALER_MINT_reply_refresh_melt_insufficient_funds (connection,
                                                             &coin_public_info->coin_pub,
                                                             coin_value,
                                                             tl,
                                                             coin_details->melt_amount,
                                                             coin_residual))
      ? GNUNET_NO : GNUNET_SYSERR;
    TALER_MINT_DB_free_coin_transaction_list (tl);
    return res;
  }
  TALER_MINT_DB_free_coin_transaction_list (tl);

  melt.coin = *coin_public_info;
  melt.coin_sig = coin_details->melt_sig;
  melt.melt_hash = *melt_hash;
  melt.amount = coin_details->melt_amount;
  if (GNUNET_OK !=
      TALER_MINT_DB_insert_refresh_melt (db_conn,
                                         session_pub,
                                         oldcoin_index,
                                         &melt))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Execute a "/refresh/melt".  We have been given a list of valid
 * coins and a request to melt them into the given
 * @a refresh_session_pub.  Check that the coins all have the
 * required value left and if so, store that they have been
 * melted and confirm the melting operation to the client.
 *
 * FIXME: some arguments are redundant here...
 *
 * @param connection the MHD connection to handle
 * @param melt_hash hash code of the session the coins are melted into
 * @param refresh_session_pub public key of the refresh session
 * @param client_signature signature of the client (matching @a refresh_session_pub)
 *         over the melting request
 * @param num_new_denoms number of entries in @a denom_pubs, size of y-dimension of @commit_coin array
 * @param denum_pubs public keys of the coins we want to withdraw in the end
 * @param coin_count number of entries in @a coin_public_infos and @a coin_melt_details, size of y-dimension of @commit_link array
 * @param coin_public_infos information about the coins to melt
 * @param coin_melt_details signatures and (residual) value of the respective coin should be melted
 * @param kappa size of x-dimension of @commit_coin and @commit_link arrays
 * @param commit_coin 2d array of coin commitments (what the mint is to sign
 *                    once the "/refres/reveal" of cut and choose is done)
 * @param commit_link 2d array of coin link commitments (what the mint is
 *                    to return via "/refresh/link" to enable linkage in the
 *                    future)
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_melt (struct MHD_Connection *connection,
                                    const struct GNUNET_HashCode *melt_hash,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                    const struct GNUNET_CRYPTO_EddsaSignature *client_signature,
                                    unsigned int num_new_denoms,
                                    struct GNUNET_CRYPTO_rsa_PublicKey *const*denom_pubs,
                                    unsigned int coin_count,
                                    const struct TALER_CoinPublicInfo *coin_public_infos,
                                    const struct MeltDetails *coin_melt_details,
                                    unsigned int kappa,
                                    struct RefreshCommitCoin *const* commit_coin,
                                    struct RefreshCommitLink *const* commit_link)
{
  struct MintKeyState *key_state;
  struct RefreshSession session;
  PGconn *db_conn;
  int res;
  unsigned int i;
  unsigned int j;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection (GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_OK !=
      TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           &session);
  if (GNUNET_YES == res)
  {
    TALER_MINT_DB_rollback (db_conn);
    res = TALER_MINT_reply_refresh_melt_success (connection,
                                                 &session.session_hash,
                                                 session.noreveal_index);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  if (GNUNET_SYSERR == res)
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  /* Melt old coins and check that they had enough residual value */
  key_state = TALER_MINT_key_state_acquire ();
  for (i=0;i<coin_count;i++)
  {
    if (GNUNET_OK !=
        (res = refresh_accept_melts (connection,
                                     db_conn,
                                     key_state,
                                     melt_hash,
                                     refresh_session_pub,
                                     &coin_public_infos[i],
                                     &coin_melt_details[i],
                                     i)))
    {
      TALER_MINT_key_state_release (key_state);
      TALER_MINT_DB_rollback (db_conn);
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
    }
  }
  TALER_MINT_key_state_release (key_state);

  /* store requested new denominations */
  for (i=0;i<num_new_denoms;i++)
  {
    if (GNUNET_OK !=
        TALER_MINT_DB_insert_refresh_order (db_conn,
                                            refresh_session_pub,
                                            i,
                                            denom_pubs[i]))
    {
      TALER_MINT_DB_rollback (db_conn);
      return TALER_MINT_reply_internal_db_error (connection);
    }
  }

  for (i = 0; i < kappa; i++)
  {
    for (j = 0; j < num_new_denoms; j++)
    {
      if (GNUNET_OK !=
          TALER_MINT_DB_insert_refresh_commit_coin (db_conn,
                                                    refresh_session_pub,
                                                    i,
                                                    j,
                                                    &commit_coin[i][j]))
      {
        TALER_MINT_DB_rollback (db_conn);
        return TALER_MINT_reply_internal_db_error (connection);
      }
    }
  }
  for (i = 0; i < kappa; i++)
  {
    for (j = 0; j < coin_count; j++)
    {
      if (GNUNET_OK !=
          TALER_MINT_DB_insert_refresh_commit_link (db_conn,
                                                    refresh_session_pub,
                                                    i,
                                                    j,
                                                    &commit_link[i][j]))
      {
        TALER_MINT_DB_rollback (db_conn);
        return TALER_MINT_reply_internal_db_error (connection);
      }
    }
  }


  /* store 'global' session data */
  session.melt_sig = *client_signature;
  session.session_hash = *melt_hash;
  session.num_oldcoins = coin_count;
  session.num_newcoins = num_new_denoms;
  session.kappa = KAPPA; // FIXME...
  session.noreveal_index
    = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
                                session.kappa);
  if (GNUNET_OK !=
      (res = TALER_MINT_DB_create_refresh_session (db_conn,
                                                   refresh_session_pub,
                                                   &session)))
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }



  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/refresh/melt transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }
  return TALER_MINT_reply_refresh_melt_success (connection,
                                                &session.session_hash,
                                                session.noreveal_index);
}


/**
 * Check if the given @a transfer_privs correspond to an honest
 * commitment for the given session.
 * Checks that the transfer private keys match their commitments.
 * Then derives the shared secret for each kappa, and check that they match.
 *
 * @param connection the MHD connection to handle
 * @param db_conn database connection to use
 * @param refresh_session session to query
 * @param off commitment offset to check
 * @param num_oldcoins size of the @a transfer_privs and @a melts arrays
 * @param transfer_privs private transfer keys
 * @param melts array of melted coins
 * @param num_newcoins number of newcoins being generated
 * @param denom_pub array of @a num_newcoins keys for the new coins
 * @return #GNUNET_OK if the committment was honest,
 *         #GNUNET_NO if there was a problem and we generated an error message
 *         #GNUNET_SYSERR if we could not even generate an error message
 */
static int
check_commitment (struct MHD_Connection *connection,
                  PGconn *db_conn,
                  const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session,
                  unsigned int off,
                  unsigned int num_oldcoins,
                  const struct GNUNET_CRYPTO_EcdsaPrivateKey *transfer_privs,
                  const struct RefreshMelt *melts,
                  unsigned int num_newcoins,
                  struct GNUNET_CRYPTO_rsa_PublicKey *const*denom_pubs)
{
  unsigned int j;
  int res;
  struct TALER_LinkSecret last_shared_secret;
  int secret_initialized = GNUNET_NO;

  for (j = 0; j < num_oldcoins; j++)
  {
    struct RefreshCommitLink commit_link;
    struct TALER_TransferSecret transfer_secret;
    struct TALER_LinkSecret shared_secret;
    struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub_check;

    res = TALER_MINT_DB_get_refresh_commit_link (db_conn,
                                                 refresh_session,
                                                 off,
                                                 j,
                                                 &commit_link);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
      return (MHD_YES == TALER_MINT_reply_internal_db_error (connection))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    GNUNET_CRYPTO_ecdsa_key_get_public (&transfer_privs[j],
                                        &transfer_pub_check);
    if (0 !=
        memcmp (&transfer_pub_check,
                &commit_link.transfer_pub,
                sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "transfer keys do not match\n");
      return (MHD_YES == TALER_MINT_reply_external_error (connection,
                                                          "Transfer private key missmatch"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    /* We're converting key types here, which is not very nice
     * but necessary and harmless (keys will be thrown away later). */
    /* FIXME: ECDHE/ECDSA-key type confusion! Can we reduce/avoid this? */
    if (GNUNET_OK !=
        GNUNET_CRYPTO_ecc_ecdh ((const struct GNUNET_CRYPTO_EcdhePrivateKey *) &transfer_privs[j],
                                (const struct GNUNET_CRYPTO_EcdhePublicKey *) &melts[j].coin.coin_pub,
                                &transfer_secret.key))
    {
      GNUNET_break (0);
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "ECDH error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    if (GNUNET_OK !=
        TALER_transfer_decrypt (&commit_link.shared_secret_enc,
                                &transfer_secret,
                                &shared_secret))
    {
      GNUNET_break (0);
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "Decryption error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    if (GNUNET_NO == secret_initialized)
    {
      secret_initialized = GNUNET_YES;
      last_shared_secret = shared_secret;
    }
    else if (0 != memcmp (&shared_secret,
                          &last_shared_secret,
                          sizeof (struct GNUNET_HashCode)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "shared secrets do not match\n");
      return (MHD_YES == TALER_MINT_reply_external_error (connection,
                                                          "Shared secret missmatch"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
  }
  GNUNET_break (GNUNET_YES == secret_initialized);


  /* Check that the commitments for all new coins were correct */
  for (j = 0; j < num_newcoins; j++)
  {
    struct RefreshCommitCoin commit_coin;
    struct TALER_RefreshLinkDecrypted *link_data;
    struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
    struct GNUNET_HashCode h_msg;
    char *buf;
    size_t buf_len;

    res = TALER_MINT_DB_get_refresh_commit_coin (db_conn,
                                                 refresh_session,
                                                 off,
                                                 j,
                                                 &commit_coin);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
      return (MHD_YES == TALER_MINT_reply_internal_db_error (connection))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    link_data = TALER_refresh_decrypt (commit_coin.refresh_link,
                                       &last_shared_secret);
    if (NULL == link_data)
    {
      GNUNET_break (0);
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "Decryption error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    GNUNET_CRYPTO_ecdsa_key_get_public (&link_data->coin_priv,
                                        &coin_pub);
    /* FIXME: we had envisioned a more complex scheme to derive
       the message to sign for a blinded coin...
       FIXME: we should have a function in util/ to do this! */
    GNUNET_CRYPTO_hash (&coin_pub,
                        sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                        &h_msg);
    if (0 == (buf_len =
              GNUNET_CRYPTO_rsa_blind (&h_msg,
                                       link_data->blinding_key,
                                       denom_pubs[j],
                                       &buf)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "blind failed\n");
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "Blinding error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    if ( (buf_len != commit_coin.coin_ev_size) ||
         (0 != memcmp (buf,
                       commit_coin.coin_ev,
                       buf_len)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "blind envelope does not match for kappa=%u, old=%d\n",
                  off,
                  (int) j);
      /* FIXME: return more specific error with exact offset */
      return (MHD_YES == TALER_MINT_reply_external_error (connection,
                                                          "Envelope missmatch"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
    GNUNET_free (buf);
  }

  return GNUNET_OK;
}


/**
 * Mint a coin as part of a refresh operation.  Obtains the
 * envelope from the database and performs the signing operation.
 *
 * @param connection the MHD connection to handle
 * @param db_conn database connection to use
 * @param refresh_session session to query
 * @param key_state key state to lookup denomination pubs
 * @param denom_pub denomination key for the coin to create
 * @param noreveal_index which index should we use to obtain the
 *                  envelope for the coin, based on cut-and-choose
 * @param coin_off number of the coin
 * @return NULL on error, otherwise signature over the coin
 */
static struct GNUNET_CRYPTO_rsa_Signature *
refresh_mint_coin (struct MHD_Connection *connection,
                   PGconn *db_conn,
                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session,
                   struct MintKeyState *key_state,
                   const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub,
                   unsigned int noreveal_index,
                   unsigned int coin_off)
{
  struct RefreshCommitCoin commit_coin;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct GNUNET_CRYPTO_rsa_Signature *ev_sig;
  int res;

  res = TALER_MINT_DB_get_refresh_commit_coin (db_conn,
                                               refresh_session,
                                               noreveal_index,
                                               coin_off,
                                               &commit_coin);
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    return NULL;
  }
  dki = TALER_MINT_get_denom_key (key_state, denom_pub);
  if (NULL == dki)
  {
    GNUNET_break (0);
    return NULL;
  }
  ev_sig = GNUNET_CRYPTO_rsa_sign (dki->denom_priv,
                                   commit_coin.coin_ev,
                                   commit_coin.coin_ev_size);
  if (NULL == ev_sig)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_OK !=
      TALER_MINT_DB_insert_refresh_collectable (db_conn,
                                                refresh_session,
                                                coin_off,
                                                ev_sig))
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_signature_free (ev_sig);
    return NULL;
  }
  return ev_sig;
}


/**
 * Execute a "/refresh/reveal".  The client is revealing to us the
 * transfer keys for @a kappa-1 sets of coins.  Verify that the
 * revealed transfer keys would allow linkage to the blinded coins,
 * and if so, return the signed coins for corresponding to the set of
 * coins that was not chosen.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the refresh session
 * @param kappa size of x-dimension of @transfer_privs array plus one (!)
 * @param num_oldcoins size of y-dimension of @transfer_privs array
 * @param transfer_pubs array with the revealed transfer keys
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_reveal (struct MHD_Connection *connection,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                      unsigned int kappa,
                                      unsigned int num_oldcoins,
                                      struct GNUNET_CRYPTO_EcdsaPrivateKey *const*transfer_privs)
{
  int res;
  PGconn *db_conn;
  struct RefreshSession refresh_session;
  struct MintKeyState *key_state;
  struct RefreshMelt *melts;
  struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs;
  struct GNUNET_CRYPTO_rsa_Signature **ev_sigs;
  unsigned int i;
  unsigned int j;
  unsigned int off;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection (GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           &refresh_session);
  if (GNUNET_NO == res)
    return TALER_MINT_reply_arg_invalid (connection,
                                         "session_pub");
  if (GNUNET_SYSERR == res)
    return TALER_MINT_reply_internal_db_error (connection);
  if (0 == refresh_session.num_oldcoins)
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  melts = GNUNET_malloc (refresh_session.num_oldcoins *
                         sizeof (struct RefreshMelt));
  for (j=0;j<refresh_session.num_oldcoins;j++)
  {
    if (GNUNET_OK !=
        TALER_MINT_DB_get_refresh_melt (db_conn,
                                        refresh_session_pub,
                                        j,
                                        &melts[j]))
    {
      GNUNET_break (0);
      GNUNET_free (melts);
      return TALER_MINT_reply_internal_db_error (connection);
    }
  }
  denom_pubs = GNUNET_malloc (refresh_session.num_newcoins *
                              sizeof (struct GNUNET_CRYPTO_rsa_PublicKey *));
  for (j=0;j<refresh_session.num_newcoins;j++)
  {
    denom_pubs[j] = TALER_MINT_DB_get_refresh_order (db_conn,
                                                     refresh_session_pub,
                                                     j);
    if (NULL == denom_pubs[j])
    {
      GNUNET_break (0);
      for (i=0;i<j;i++)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[i]);
      GNUNET_free (denom_pubs);
      GNUNET_free (melts);
      return (MHD_YES == TALER_MINT_reply_internal_db_error (connection))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
  }


  off = 0;
  for (i=0;i<refresh_session.kappa - 1;i++)
  {
    if (i == refresh_session.noreveal_index)
      off = 1;
    if (GNUNET_OK !=
        (res = check_commitment (connection,
                                 db_conn,
                                 refresh_session_pub,
                                 i + off,
                                 refresh_session.num_oldcoins,
                                 transfer_privs[i + off],
                                 melts,
                                 refresh_session.num_newcoins,
                                 denom_pubs)))
    {
      for (j=0;j<refresh_session.num_newcoins;j++)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
      GNUNET_free (denom_pubs);
      GNUNET_free (melts);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
  }
  GNUNET_free (melts);

  /* Client request OK, start transaction */
  if (GNUNET_OK !=
      TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
    for (j=0;j<refresh_session.num_newcoins;j++)
      GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
    GNUNET_free (denom_pubs);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  ev_sigs = GNUNET_malloc (refresh_session.num_newcoins *
                           sizeof (struct GNUNET_CRYPTO_rsa_Signature *));
  key_state = TALER_MINT_key_state_acquire ();
  for (j=0;j<refresh_session.num_newcoins;j++)
  {
    ev_sigs[j] = refresh_mint_coin (connection,
                                    db_conn,
                                    refresh_session_pub,
                                    key_state,
                                    denom_pubs[j],
                                    refresh_session.noreveal_index,
                                    j);
    if (NULL == ev_sigs[j])
    {
      TALER_MINT_key_state_release (key_state);
      for (i=0;i<j;i++)
        GNUNET_CRYPTO_rsa_signature_free (ev_sigs[i]);
      GNUNET_free (ev_sigs);
      for (j=0;j<refresh_session.num_newcoins;j++)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
      GNUNET_free (denom_pubs);
      return TALER_MINT_reply_internal_db_error (connection);
    }
  }
  TALER_MINT_key_state_release (key_state);
  for (j=0;j<refresh_session.num_newcoins;j++)
    GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
  GNUNET_free (denom_pubs);

  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/refresh/reveal transaction commit failed\n");
    for (i=0;i<refresh_session.num_newcoins;i++)
      GNUNET_CRYPTO_rsa_signature_free (ev_sigs[i]);
    GNUNET_free (ev_sigs);
    return TALER_MINT_reply_commit_error (connection);
  }

  res = TALER_MINT_reply_refresh_reveal_success (connection,
                                                 refresh_session.num_newcoins,
                                                 ev_sigs);
  for (i=0;i<refresh_session.num_newcoins;i++)
    GNUNET_CRYPTO_rsa_signature_free (ev_sigs[i]);
  GNUNET_free (ev_sigs);
  return res;
}


/**
 * Execute a "/refresh/link".  Returns the linkage information that
 * will allow the owner of a coin to follow the refresh trail to
 * the refreshed coin.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin to link
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_link (struct MHD_Connection *connection,
                                    const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub)
{
  int res;
  PGconn *db_conn;
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;
  struct TALER_EncryptedLinkSecret shared_secret_enc;
  struct LinkDataList *ldl;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection (GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = TALER_db_get_transfer (db_conn,
                               coin_pub,
                               &transfer_pub,
                               &shared_secret_enc);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_NO == res)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "link data not found (transfer)");
  }
  GNUNET_assert (GNUNET_OK == res);

  ldl = TALER_db_get_link (db_conn, coin_pub);
  if (NULL == ldl)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "link data not found (link)");
  }
  res = TALER_MINT_reply_refresh_link_success (connection,
                                               &transfer_pub,
                                               &shared_secret_enc,
                                               ldl);
  TALER_db_link_data_list_free (ldl);
  return res;
}


/* end of taler-mint-httpd_db.c */
