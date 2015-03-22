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
 */
#include "platform.h"
#include <pthread.h>
#include <jansson.h>
#include "taler-mint-httpd_db.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_responses.h"
#include "taler_util.h"
#include "taler-mint-httpd_keystate.h"
#include "plugin.h"


/**
 * Calculate the total value of all transactions performed.
 * Stores @a off plus the cost of all transactions in @a tl
 * in @a ret.
 *
 * @param pos transaction list to process
 * @param off offset to use as the starting value
 * @param ret where the resulting total is to be stored
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
calculate_transaction_list_totals (struct TALER_MINT_DB_TransactionList *tl,
                                   const struct TALER_Amount *off,
                                   struct TALER_Amount *ret)
{
  struct TALER_Amount spent = *off;
  struct TALER_MINT_DB_TransactionList *pos;

  for (pos = tl; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_MINT_DB_TT_DEPOSIT:
      if (GNUNET_OK !=
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.deposit->amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_MINT_DB_TT_REFRESH_MELT:
      if (GNUNET_OK !=
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.melt->amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_MINT_DB_TT_LOCK:
      /* should check if lock is still active,
         and if it is for THIS operation; if
         lock is inactive, delete it; if lock
         is for THIS operation, ignore it;
         if lock is for another operation,
         count it! */
      GNUNET_assert (0);  // FIXME: not implemented! (#3625)
      return GNUNET_SYSERR;
    }
  }
  *ret = spent;
  return GNUNET_OK;
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
  struct TALER_MINTDB_Session *session;
  struct TALER_MINT_DB_TransactionList *tl;
  struct TALER_Amount spent;
  struct TALER_Amount value;
  struct TALER_Amount fee_deposit;
  struct MintKeyState *mks;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  int ret;

  if (NULL == (session = plugin->get_session (plugin->cls,
                                              GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_YES ==
      plugin->have_deposit (plugin->cls,
                            session,
                            deposit))
  {
    return TALER_MINT_reply_deposit_success (connection,
                                             &deposit->coin.coin_pub,
                                             &deposit->h_wire,
                                             &deposit->h_contract,
                                             deposit->transaction_id,
                                             &deposit->merchant_pub,
                                             &deposit->amount_with_fee);
  }
  mks = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (mks,
                                  deposit->coin.denom_pub);
  TALER_amount_ntoh (&value,
                     &dki->issue.value);
  TALER_amount_ntoh (&fee_deposit,
                     &dki->issue.fee_deposit);
  TALER_MINT_key_state_release (mks);

  if (GNUNET_OK !=
      plugin->start (plugin->cls,
                     session))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  /* fee for THIS transaction */
  spent = deposit->amount_with_fee;
  if (TALER_amount_cmp (&fee_deposit,
                        &spent) < 0)
  {
    return (MHD_YES ==
            TALER_MINT_reply_external_error (connection,
                                             "deposited amount smaller than depositing fee"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  /* add cost of all previous transactions */
  tl = plugin->get_coin_transactions (plugin->cls,
                                      session,
                                      &deposit->coin.coin_pub);
  if (GNUNET_OK !=
      calculate_transaction_list_totals (tl,
                                         &spent,
                                         &spent))
  {
    plugin->free_coin_transaction_list (plugin->cls,
                                        tl);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (0 < TALER_amount_cmp (&spent,
                            &value))
  {
    plugin->rollback (plugin->cls,
                      session);
    ret = TALER_MINT_reply_deposit_insufficient_funds (connection,
                                                       tl);
    plugin->free_coin_transaction_list (plugin->cls,
                                        tl);
    return ret;
  }
  plugin->free_coin_transaction_list (plugin->cls,
                                      tl);

  if (GNUNET_OK !=
      plugin->insert_deposit (plugin->cls,
                              session,
                              deposit))
  {
    LOG_WARNING ("Failed to store /deposit information in database\n");
    plugin->rollback (plugin->cls,
                      session);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  if (GNUNET_OK !=
      plugin->commit (plugin->cls,
                      session))
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
                                           &deposit->amount_with_fee);
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
  struct TALER_MINTDB_Session *session;
  struct ReserveHistory *rh;
  int res;

  if (NULL == (session = plugin->get_session (plugin->cls,
                                              GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  rh = plugin->get_reserve_history (plugin->cls,
                                    session,
                                    reserve_pub);
  if (NULL == rh)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error", "Reserve not found");
  res = TALER_MINT_reply_withdraw_status_success (connection,
                                                  rh);
  plugin->free_reserve_history (plugin->cls,
                                rh);
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
  struct TALER_MINTDB_Session *session;
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
  struct TALER_Amount fee_withdraw;
  struct GNUNET_HashCode h_blind;
  int res;

  GNUNET_CRYPTO_hash (blinded_msg,
                      blinded_msg_len,
                      &h_blind);

  if (NULL == (session = plugin->get_session (plugin->cls,
                                              GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = plugin->get_collectable_blindcoin (plugin->cls,
                                           session,
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
      plugin->start (plugin->cls,
                     session))
  {
    GNUNET_break (0);
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  rh = plugin->get_reserve_history (plugin->cls,
                                    session,
                                    reserve);
  if (NULL == rh)
  {
    plugin->rollback (plugin->cls,
                      session);
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Reserve not found");
  }

  /* calculate amount required including fees */
  TALER_amount_ntoh (&value,
                     &dki->issue.value);
  TALER_amount_ntoh (&fee_withdraw,
                     &dki->issue.fee_withdraw);

  if (GNUNET_OK !=
      TALER_amount_add (&amount_required,
                        &value,
                        &fee_withdraw))
  {
    plugin->rollback (plugin->cls,
                      session);
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_internal_db_error (connection);
  }

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
        if (GNUNET_OK !=
            TALER_amount_add (&deposit_total,
                              &deposit_total,
                              &pos->details.bank->amount))
        {
          plugin->rollback (plugin->cls,
                            session);
          TALER_MINT_key_state_release (key_state);
          return TALER_MINT_reply_internal_db_error (connection);
        }
      res |= 1;
      break;
    case TALER_MINT_DB_RO_WITHDRAW_COIN:
      tdki = TALER_MINT_get_denom_key (key_state,
                                       pos->details.withdraw->denom_pub);
      TALER_amount_ntoh (&value,
                         &tdki->issue.value);
      if (0 == (res & 2))
        withdraw_total = value;
      else
        if (GNUNET_OK !=
            TALER_amount_add (&withdraw_total,
                              &withdraw_total,
                              &value))
        {
          plugin->rollback (plugin->cls,
                            session);
          TALER_MINT_key_state_release (key_state);
          return TALER_MINT_reply_internal_db_error (connection);
        }
      res |= 2;
      break;
    }
  }
  /* All reserve balances should be non-negative */
  GNUNET_break (GNUNET_SYSERR !=
                TALER_amount_subtract (&balance,
                                       &deposit_total,
                                       &withdraw_total));
  if (0 < TALER_amount_cmp (&amount_required,
                            &balance))
  {
    TALER_MINT_key_state_release (key_state);
    plugin->rollback (plugin->cls,
                      session);
    res = TALER_MINT_reply_withdraw_sign_insufficient_funds (connection,
                                                             rh);
    plugin->free_reserve_history (plugin->cls,
                                  rh);
    return res;
  }
  plugin->free_reserve_history (plugin->cls,
                                rh);

  /* Balance is good, sign the coin! */
  sig = GNUNET_CRYPTO_rsa_sign (dki->denom_priv,
                                blinded_msg,
                                blinded_msg_len);
  TALER_MINT_key_state_release (key_state);
  if (NULL == sig)
  {
    GNUNET_break (0);
    plugin->rollback (plugin->cls,
                      session);
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
      plugin->insert_collectable_blindcoin (plugin->cls,
                                            session,
                                            &h_blind,
                                            amount_required,
                                            &collectable))
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_signature_free (sig);
    plugin->rollback (plugin->cls,
                      session);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_OK !=
      plugin->commit (plugin->cls,
                      session))
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
 * @param session the database connection
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
                      struct TALER_MINTDB_Session *session,
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
  struct TALER_Amount spent;
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

  TALER_amount_ntoh (&coin_value,
                     &dki->value);
  /* fee for THIS transaction; the melt amount includes the fee! */
  spent = coin_details->melt_amount_with_fee;
  /* add historic transaction costs of this coin */
  tl = plugin->get_coin_transactions (plugin->cls,
                                      session,
                                      &coin_public_info->coin_pub);
  if (GNUNET_OK !=
      calculate_transaction_list_totals (tl,
                                         &spent,
                                         &spent))
  {
    GNUNET_break (0);
    plugin->free_coin_transaction_list (plugin->cls,
                                        tl);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  /* Refuse to refresh when the coin's value is insufficient
     for the cost of all transactions. */
  if (TALER_amount_cmp (&coin_value,
                        &spent) < 0)
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_subtract (&coin_residual,
                                          &spent,
                                          &coin_details->melt_amount_with_fee));
    res = (MHD_YES ==
           TALER_MINT_reply_refresh_melt_insufficient_funds (connection,
                                                             &coin_public_info->coin_pub,
                                                             coin_value,
                                                             tl,
                                                             coin_details->melt_amount_with_fee,
                                                             coin_residual))
      ? GNUNET_NO : GNUNET_SYSERR;
    plugin->free_coin_transaction_list (plugin->cls,
                                        tl);
    return res;
  }
  plugin->free_coin_transaction_list (plugin->cls,
                                      tl);

  melt.coin = *coin_public_info;
  melt.coin_sig = coin_details->melt_sig;
  melt.melt_hash = *melt_hash;
  melt.amount_with_fee = coin_details->melt_amount_with_fee;
  if (GNUNET_OK !=
      plugin->insert_refresh_melt (plugin->cls,
                                   session,
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
  struct RefreshSession refresh_session;
  struct TALER_MINTDB_Session *session;
  int res;
  unsigned int i;

  if (NULL == (session = plugin->get_session (plugin->cls,
                                              GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_OK !=
      plugin->start (plugin->cls,
                     session))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = plugin->get_refresh_session (plugin->cls,
                                     session,
                                     refresh_session_pub,
                                     &refresh_session);
  if (GNUNET_YES == res)
  {
    plugin->rollback (plugin->cls,
                      session);
    res = TALER_MINT_reply_refresh_melt_success (connection,
                                                 &refresh_session.session_hash,
                                                 refresh_session.noreveal_index);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  if (GNUNET_SYSERR == res)
  {
    plugin->rollback (plugin->cls,
                      session);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  /* Melt old coins and check that they had enough residual value */
  key_state = TALER_MINT_key_state_acquire ();
  for (i=0;i<coin_count;i++)
  {
    if (GNUNET_OK !=
        (res = refresh_accept_melts (connection,
                                     session,
                                     key_state,
                                     melt_hash,
                                     refresh_session_pub,
                                     &coin_public_infos[i],
                                     &coin_melt_details[i],
                                     i)))
    {
      TALER_MINT_key_state_release (key_state);
      plugin->rollback (plugin->cls,
                        session);
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
    }
  }
  TALER_MINT_key_state_release (key_state);

  /* store requested new denominations */
  if (GNUNET_OK !=
      plugin->insert_refresh_order (plugin->cls,
                                    session,
                                    refresh_session_pub,
                                    num_new_denoms,
                                    denom_pubs))
  {
    plugin->rollback (plugin->cls,
                      session);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  for (i = 0; i < kappa; i++)
  {
    if (GNUNET_OK !=
        plugin->insert_refresh_commit_coins (plugin->cls,
                                             session,
                                             refresh_session_pub,
                                             i,
                                             num_new_denoms,
                                             commit_coin[i]))
    {
      plugin->rollback (plugin->cls,
                        session);
      return TALER_MINT_reply_internal_db_error (connection);
    }
  }
  for (i = 0; i < kappa; i++)
  {
    if (GNUNET_OK !=
        plugin->insert_refresh_commit_links (plugin->cls,
                                             session,
                                             refresh_session_pub,
                                             i,
                                             coin_count,
                                             commit_link[i]))
    {
      plugin->rollback (plugin->cls,
                        session);
      return TALER_MINT_reply_internal_db_error (connection);
    }
  }


  /* store 'global' session data */
  refresh_session.melt_sig = *client_signature;
  refresh_session.session_hash = *melt_hash;
  refresh_session.num_oldcoins = coin_count;
  refresh_session.num_newcoins = num_new_denoms;
  refresh_session.kappa = KAPPA; // FIXME...
  refresh_session.noreveal_index
    = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
                                refresh_session.kappa);
  if (GNUNET_OK !=
      (res = plugin->create_refresh_session (plugin->cls,
                                             session,
                                             refresh_session_pub,
                                             &refresh_session)))
  {
    plugin->rollback (plugin->cls,
                      session);
    return TALER_MINT_reply_internal_db_error (connection);
  }



  if (GNUNET_OK !=
      plugin->commit (plugin->cls,
                      session))
  {
    LOG_WARNING ("/refresh/melt transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }
  return TALER_MINT_reply_refresh_melt_success (connection,
                                                &refresh_session.session_hash,
                                                refresh_session.noreveal_index);
}


/**
 * Check if the given @a transfer_privs correspond to an honest
 * commitment for the given session.
 * Checks that the transfer private keys match their commitments.
 * Then derives the shared secret for each kappa, and check that they match.
 *
 * @param connection the MHD connection to handle
 * @param session database connection to use
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
                  struct TALER_MINTDB_Session *session,
                  const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session,
                  unsigned int off,
                  unsigned int num_oldcoins,
                  const struct GNUNET_CRYPTO_EcdsaPrivateKey *transfer_privs,
                  const struct RefreshMelt *melts,
                  unsigned int num_newcoins,
                  struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs)
{
  unsigned int j;
  struct TALER_LinkSecret last_shared_secret;
  int secret_initialized = GNUNET_NO;
  struct GNUNET_CRYPTO_EcdhePublicKey coin_ecdhe;
  struct GNUNET_CRYPTO_EcdhePrivateKey transfer_ecdhe;
  struct RefreshCommitLink *commit_links;
  struct RefreshCommitCoin *commit_coins;

  commit_links = GNUNET_malloc (num_oldcoins *
                                sizeof (struct RefreshCommitLink));
  if (GNUNET_OK !=
      plugin->get_refresh_commit_links (plugin->cls,
                                        session,
                                        refresh_session,
                                        off,
                                        num_oldcoins,
                                        commit_links))
  {
    GNUNET_break (0);
    GNUNET_free (commit_links);
    return (MHD_YES == TALER_MINT_reply_internal_db_error (connection))
      ? GNUNET_NO : GNUNET_SYSERR;
  }

  for (j = 0; j < num_oldcoins; j++)
  {
    struct TALER_TransferSecret transfer_secret;
    struct TALER_LinkSecret shared_secret;
    struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub_check;

    GNUNET_CRYPTO_ecdsa_key_get_public (&transfer_privs[j],
                                        &transfer_pub_check);
    if (0 !=
        memcmp (&transfer_pub_check,
                &commit_links[j].transfer_pub,
                sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "transfer keys do not match\n");
      GNUNET_free (commit_links);
      /* FIXME: return more specific error with original signature (#3712) */
      return (MHD_YES ==
	      TALER_MINT_reply_refresh_reveal_missmatch (connection,
							 off,
							 j,
							 "transfer key"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    /* We're converting key types here, which is not very nice
     * but necessary and harmless (keys will be thrown away later). */
    GNUNET_CRYPTO_ecdsa_public_to_ecdhe (&melts[j].coin.coin_pub,
                                         &coin_ecdhe);
    GNUNET_CRYPTO_ecdsa_private_to_ecdhe (&transfer_privs[j],
                                          &transfer_ecdhe);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_ecc_ecdh (&transfer_ecdhe,
                                &coin_ecdhe,
                                &transfer_secret.key))
    {
      GNUNET_break (0);
      GNUNET_CRYPTO_ecdhe_key_clear (&transfer_ecdhe);
      GNUNET_free (commit_links);
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "ECDH error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_ecdhe_key_clear (&transfer_ecdhe);
    if (GNUNET_OK !=
        TALER_transfer_decrypt (&commit_links[j].shared_secret_enc,
                                &transfer_secret,
                                &shared_secret))
    {
      GNUNET_break (0);
      GNUNET_free (commit_links);
      return (MHD_YES ==
	      TALER_MINT_reply_internal_error (connection,
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
      GNUNET_free (commit_links);
      /* FIXME: return more specific error with original signature (#3712) */
      return (MHD_YES ==
	      TALER_MINT_reply_refresh_reveal_missmatch (connection,
							 off,
							 j,
							 "transfer secret"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
  }
  GNUNET_break (GNUNET_YES == secret_initialized);
  GNUNET_free (commit_links);

  /* Check that the commitments for all new coins were correct */
  commit_coins = GNUNET_malloc (num_newcoins *
                                sizeof (struct RefreshCommitCoin));

  if (GNUNET_OK !=
      plugin->get_refresh_commit_coins (plugin->cls,
                                        session,
                                        refresh_session,
                                        off,
                                        num_newcoins,
                                        commit_coins))
  {
    GNUNET_break (0);
    GNUNET_free (commit_coins);
    return (MHD_YES == TALER_MINT_reply_internal_db_error (connection))
      ? GNUNET_NO : GNUNET_SYSERR;
  }

  for (j = 0; j < num_newcoins; j++)
  {
    struct TALER_RefreshLinkDecrypted *link_data;
    struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
    struct GNUNET_HashCode h_msg;
    char *buf;
    size_t buf_len;

    link_data = TALER_refresh_decrypt (commit_coins[j].refresh_link,
                                       &last_shared_secret);
    if (NULL == link_data)
    {
      GNUNET_break (0);
      GNUNET_free (commit_coins);
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "Decryption error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    GNUNET_CRYPTO_ecdsa_key_get_public (&link_data->coin_priv,
                                        &coin_pub);
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
      GNUNET_free (commit_coins);
      return (MHD_YES == TALER_MINT_reply_internal_error (connection,
                                                          "Blinding error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }

    if ( (buf_len != commit_coins[j].coin_ev_size) ||
         (0 != memcmp (buf,
                       commit_coins[j].coin_ev,
                       buf_len)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "blind envelope does not match for kappa=%u, old=%d\n",
                  off,
                  (int) j);
      /* FIXME: return more specific error with original signature (#3712) */
      GNUNET_free (commit_coins);
      return (MHD_YES ==
	      TALER_MINT_reply_refresh_reveal_missmatch (connection,
							 off,
							 j,
							 "envelope"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
    GNUNET_free (buf);
  }
  GNUNET_free (commit_coins);

  return GNUNET_OK;
}


/**
 * Mint a coin as part of a refresh operation.  Obtains the
 * envelope from the database and performs the signing operation.
 *
 * @param connection the MHD connection to handle
 * @param session database connection to use
 * @param refresh_session session to query
 * @param key_state key state to lookup denomination pubs
 * @param denom_pub denomination key for the coin to create
 * @param commit_coin the coin that was committed
 * @param coin_off number of the coin
 * @return NULL on error, otherwise signature over the coin
 */
static struct GNUNET_CRYPTO_rsa_Signature *
refresh_mint_coin (struct MHD_Connection *connection,
                   struct TALER_MINTDB_Session *session,
                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session,
                   struct MintKeyState *key_state,
                   const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub,
                   const struct RefreshCommitCoin *commit_coin,
                   unsigned int coin_off)
{
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct GNUNET_CRYPTO_rsa_Signature *ev_sig;

  dki = TALER_MINT_get_denom_key (key_state, denom_pub);
  if (NULL == dki)
  {
    GNUNET_break (0);
    return NULL;
  }
  ev_sig = GNUNET_CRYPTO_rsa_sign (dki->denom_priv,
                                   commit_coin->coin_ev,
                                   commit_coin->coin_ev_size);
  if (NULL == ev_sig)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_OK !=
      plugin->insert_refresh_collectable (plugin->cls,
                                          session,
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
  struct TALER_MINTDB_Session *session;
  struct RefreshSession refresh_session;
  struct MintKeyState *key_state;
  struct RefreshMelt *melts;
  struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs;
  struct GNUNET_CRYPTO_rsa_Signature **ev_sigs;
  struct RefreshCommitCoin *commit_coins;
  unsigned int i;
  unsigned int j;
  unsigned int off;

  if (NULL == (session = plugin->get_session (plugin->cls,
                                              GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  res = plugin->get_refresh_session (plugin->cls,
                                     session,
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
        plugin->get_refresh_melt (plugin->cls,
                                  session,
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
  if (GNUNET_OK !=
      plugin->get_refresh_order (plugin->cls,
                                 session,
                                 refresh_session_pub,
                                 refresh_session.num_newcoins,
                                 denom_pubs))
  {
    GNUNET_break (0);
    GNUNET_free (denom_pubs);
    GNUNET_free (melts);
    return (MHD_YES == TALER_MINT_reply_internal_db_error (connection))
      ? GNUNET_NO : GNUNET_SYSERR;
  }


  off = 0;
  for (i=0;i<refresh_session.kappa - 1;i++)
  {
    if (i == refresh_session.noreveal_index)
      off = 1;
    if (GNUNET_OK !=
        (res = check_commitment (connection,
                                 session,
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
      plugin->start (plugin->cls,
                     session))
  {
    GNUNET_break (0);
    for (j=0;j<refresh_session.num_newcoins;j++)
      GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
    GNUNET_free (denom_pubs);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  commit_coins = GNUNET_malloc (refresh_session.num_newcoins *
                                sizeof (struct RefreshCommitCoin));
  if (GNUNET_OK !=
      plugin->get_refresh_commit_coins (plugin->cls,
                                        session,
                                        refresh_session_pub,
                                        refresh_session.noreveal_index,
                                        refresh_session.num_newcoins,
                                        commit_coins))
  {
    GNUNET_break (0);
    GNUNET_free (commit_coins);
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
                                    session,
                                    refresh_session_pub,
                                    key_state,
                                    denom_pubs[j],
                                    &commit_coins[j],
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
      GNUNET_free (commit_coins);
      return TALER_MINT_reply_internal_db_error (connection);
    }
  }
  TALER_MINT_key_state_release (key_state);
  for (j=0;j<refresh_session.num_newcoins;j++)
    GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
  GNUNET_free (denom_pubs);
  GNUNET_free (commit_coins);

  if (GNUNET_OK !=
      plugin->commit (plugin->cls,
                      session))
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
  struct TALER_MINTDB_Session *session;
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;
  struct TALER_EncryptedLinkSecret shared_secret_enc;
  struct LinkDataList *ldl;

  if (NULL == (session = plugin->get_session (plugin->cls,
                                              GNUNET_NO)))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = plugin->get_transfer (plugin->cls,
                              session,
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

  ldl = plugin->get_link_data_list (plugin->cls,
                                    session,
                                    coin_pub);
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
  plugin->free_link_data_list (plugin->cls,
                               ldl);
  return res;
}


/* end of taler-mint-httpd_db.c */
