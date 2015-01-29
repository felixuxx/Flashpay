/*
  This file is part of TALER
  (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * - /refresh/melt:
 *   + properly check all conditions and handle errors
 *   + properly check transaction logic
 *   + check for leaks
 *   + check low-level API
 * - /refresh/reveal:
 *   + properly check all conditions and handle errors
 *   + properly check transaction logic
 *   + check for leaks
 *   + check low-level API
 * - /refresh/link:
 *   + check low-level API
 *   + separate DB logic from response generation
 *   + check for leaks
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

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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
    ret = TALER_MINT_reply_insufficient_funds (connection,
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

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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

  /* FIXME: good place to assert deposit_total > withdraw_total... */
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

  // FIXME: can we avoid the cast?
  collectable.denom_pub = (struct GNUNET_CRYPTO_rsa_PublicKey *) denomination_pub;
  collectable.sig = sig;
  collectable.reserve_pub = *reserve;
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
 * Insert  all requested denominations  into the DB, and  compute the
 * required cost of the denominations, including fees.
 *
 * @param connection the connection to send an error response to
 * @param db_conn the database connection
 * @param key_state the mint's key state to use
 * @param session_pub the refresh session public key
 * @param denom_pubs_count number of entries in @a denom_pubs
 * @param denom_pubs array of public keys for the refresh
 * @return FIXME!
 */
static int
refresh_accept_denoms (struct MHD_Connection *connection,
                       PGconn *db_conn,
                       const struct MintKeyState *key_state,
                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                       unsigned int denom_pubs_count,
                       struct GNUNET_CRYPTO_rsa_PublicKey *const*denom_pubs)
{
  unsigned int i;
  int res;

  for (i = 0; i < denom_pubs_count; i++)
  {
    /* Insert the requested coin into the DB, so we'll know later
     * what denomination the request had */

    if (GNUNET_OK !=
        (res = TALER_MINT_DB_insert_refresh_order (db_conn,
                                                   i,
                                                   session_pub,
                                                   denom_pubs[i])))
      return res; // ???
  }
  return GNUNET_OK;
}




/**
 * Parse coin melt requests from a JSON object and write them to
 * the database.
 *
 * @param connection the connection to send errors to
 * @param db_conn the database connection
 * @param key_state the mint's key state
 * @param session_pub the refresh session's public key
 * @param coin_count number of coins in @a coin_public_infos to melt
 * @param coin_public_infos the coins to melt
 * @param r_melt_balance[OUT] FIXME (#3636: check earlier, pass expected value IN, not OUT!)
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if an error message was generated,
 *         #GNUNET_SYSERR on internal errors (no response generated)
 */
static int
refresh_accept_melts (struct MHD_Connection *connection,
                      PGconn *db_conn,
                      const struct MintKeyState *key_state,
                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                      unsigned int coin_count,
                      const struct TALER_CoinPublicInfo *coin_public_infos,
                      struct TALER_Amount *r_melt_balance)
{
  size_t i;

  memset (r_melt_balance, 0, sizeof (struct TALER_Amount));

  for (i = 0; i < coin_count; i++)
  {
    struct TALER_MINT_DenomKeyIssue *dki;
    struct TALER_MINT_DB_TransactionList *tl;
    // money the customer gets by melting the current coin
    struct TALER_Amount coin_gain;
    struct RefreshMelt melt;

    dki = &TALER_MINT_get_denom_key (key_state,
                                     coin_public_infos[i].denom_pub)->issue;

    if (NULL == dki)
      return (MHD_YES ==
              TALER_MINT_reply_json_pack (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          "{s:s}",
                                          "error",
                                          "denom not found"))
        ? GNUNET_NO : GNUNET_SYSERR;

    coin_gain = TALER_amount_ntoh (dki->value);
    tl = TALER_MINT_DB_get_coin_transactions (db_conn,
                                              &coin_public_infos[i].coin_pub);
    /* FIXME: compute how much value is left with this coin! */
    TALER_MINT_DB_free_coin_transaction_list (tl);

    melt.coin = coin_public_infos[i];
    melt.session_pub = *session_pub;
    // melt.coin_sig = FIXME;
    // melt.amount = FIXME;
    melt.oldcoin_index = i;
    if (GNUNET_OK !=
        TALER_MINT_DB_insert_refresh_melt (db_conn,
                                           &melt))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }


    /* Refuse to refresh when the coin does not have enough money left to
     * pay the refreshing fees of the coin. */

    if (TALER_amount_cmp (coin_gain,
                          TALER_amount_ntoh (dki->fee_refresh)) < 0)
      return (MHD_YES ==
              TALER_MINT_reply_json_pack (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          "{s:s}",
                                          "error", "depleted")) ? GNUNET_NO : GNUNET_SYSERR;

    coin_gain = TALER_amount_subtract (coin_gain,
                                       TALER_amount_ntoh (dki->fee_refresh));
    *r_melt_balance = TALER_amount_add (*r_melt_balance,
                                        coin_gain);
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
 * @param refresh_session_pub public key of the refresh session
 * @param client_signature signature of the client (matching @a refresh_session_pub)
 *         over the melting request
 * @param num_new_denoms number of entries in @a denom_pubs
 * @param denum_pubs public keys of the coins we want to withdraw in the end
 * @param coin_count number of entries in @a coin_public_infos
 * @param coin_public_infos information about the coins to melt
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_melt (struct MHD_Connection *connection,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                    const struct GNUNET_CRYPTO_EddsaSignature *client_signature,
                                    unsigned int num_new_denoms,
                                    struct GNUNET_CRYPTO_rsa_PublicKey *const*denom_pubs,
                                    unsigned int coin_count,
                                    const struct TALER_CoinPublicInfo *coin_public_infos)
{
  struct TALER_Amount melt_balance;
  struct MintKeyState *key_state;
  struct RefreshSession session;
  PGconn *db_conn;
  int res;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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
    return TALER_MINT_reply_refresh_melt_success (connection,
                                                  &session.melt_sig,
                                                  refresh_session_pub,
                                                  session.kappa);
  }
  if (GNUNET_SYSERR == res)
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  session.melt_sig = *client_signature;
  session.num_oldcoins = coin_count;
  session.num_newcoins = num_new_denoms;
  session.kappa = KAPPA;
  session.noreveal_index = UINT16_MAX;
  session.has_commit_sig = GNUNET_NO;
  if (GNUNET_OK !=
      (res = TALER_MINT_DB_create_refresh_session (db_conn,
                                                   refresh_session_pub,
                                                   &session)))
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  /* The next two operations must see the same key state,
   * thus we acquire it here. */

  key_state = TALER_MINT_key_state_acquire ();
  if (GNUNET_OK !=
      (res = refresh_accept_denoms (connection, db_conn, key_state,
                                    refresh_session_pub,
                                    num_new_denoms,
                                    denom_pubs)))
  {
    TALER_MINT_key_state_release (key_state);
    TALER_MINT_DB_rollback (db_conn);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  /* Write old coins to db and sum their value */
  if (GNUNET_OK !=
      (res = refresh_accept_melts (connection, db_conn, key_state,
                                   refresh_session_pub,
                                   coin_count,
                                   coin_public_infos,
                                   &melt_balance)))
  {
    TALER_MINT_key_state_release (key_state);
    TALER_MINT_DB_rollback (db_conn);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  TALER_MINT_key_state_release (key_state);


  /* Request is only ok if cost of requested coins
   * does not exceed value of melted coins. */

  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/refresh/melt transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }
  if (GNUNET_OK !=
      (res = TALER_MINT_DB_get_refresh_session (db_conn,
                                                refresh_session_pub,
                                                &session)))
  {
    // FIXME: send internal error
    GNUNET_break (0);
    return MHD_NO;
  }
  return TALER_MINT_reply_refresh_melt_success (connection,
                                                client_signature,
                                                refresh_session_pub,
                                                session.kappa);


}


/**
 * Execute a "/refresh/commit".  The client is committing to @a kappa
 * sets of transfer keys, and linkage information for a refresh
 * operation.  Confirm that the commit matches the melts of an
 * existing @a refresh_session_pub, store the refresh session commit
 * data and then return the client a challenge specifying which of the
 * @a kappa sets of private transfer keys should not be revealed.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session public key of the session
 * @param commit_client_sig signature of the client over this commitment
 * @param kappa size of x-dimension of @commit_coin and @commit_link arrays
 * @param num_oldcoins size of y-dimension of @commit_link array
 * @param num_newcoins size of y-dimension of @commit_coin array
 * @param commit_coin 2d array of coin commitments (what the mint is to sign
 *                    once the "/refres/reveal" of cut and choose is done)
 * @param commit_link 2d array of coin link commitments (what the mint is
 *                    to return via "/refresh/link" to enable linkage in the
 *                    future)
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_commit (struct MHD_Connection *connection,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                      const struct GNUNET_CRYPTO_EddsaSignature *commit_client_sig,
                                      unsigned int kappa,
                                      unsigned int num_oldcoins,
                                      unsigned int num_newcoins,
                                      struct RefreshCommitCoin *const*commit_coin,
                                      struct RefreshCommitLink *const*commit_link)

{
  PGconn *db_conn;
  struct RefreshSession refresh_session;
  unsigned int i;
  unsigned int j;
  int res;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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
                                           &refresh_session);
  if (GNUNET_SYSERR == res)
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_NO == res)
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_arg_invalid (connection,
                                         "session_pub");
  }
  if ( (refresh_session.kappa != kappa) ||
       (refresh_session.num_newcoins != num_newcoins) ||
       (refresh_session.num_oldcoins != num_oldcoins) )
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_arg_invalid (connection,
                                         "dimensions");
  }
  if (GNUNET_YES == refresh_session.has_commit_sig)
  {
    TALER_MINT_DB_rollback (db_conn);
    res = TALER_MINT_reply_refresh_commit_success (connection,
                                                   &refresh_session);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  for (i = 0; i < kappa; i++)
  {
    for (j = 0; j < num_newcoins; j++)
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
    for (j = 0; j < num_oldcoins; j++)
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

  refresh_session.noreveal_index
    = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
                                refresh_session.kappa);

  if (GNUNET_OK !=
      (res = TALER_MINT_DB_update_refresh_session (db_conn,
                                                   refresh_session_pub,
                                                   refresh_session.noreveal_index,
                                                   commit_client_sig)))
  {
    TALER_MINT_DB_rollback (db_conn);
    return TALER_MINT_reply_internal_db_error (connection);
  }


  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/refresh/commit transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }

  return TALER_MINT_reply_refresh_commit_success (connection, &refresh_session);
}


/**
 * Send response for "/refresh/reveal".
 *
 * @param connection the MHD connection
 * @param db_conn the connection to the mint's db
 * @param refresh_session_pub the refresh session's public key
 * @return a MHD result code
 */
static int
helper_refresh_reveal_send_response (struct MHD_Connection *connection,
                                     PGconn *db_conn,
                                     const struct RefreshSession *refresh_session,
                                     const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub)
{
  int res;
  unsigned int newcoin_index;
  struct GNUNET_CRYPTO_rsa_Signature **sigs;

  sigs = GNUNET_malloc (refresh_session->num_newcoins *
                        sizeof (struct GNUNET_CRYPTO_rsa_Signature *));
  for (newcoin_index = 0; newcoin_index < refresh_session->num_newcoins; newcoin_index++)
  {
    sigs[newcoin_index] = TALER_MINT_DB_get_refresh_collectable (db_conn,
                                                                 newcoin_index,
                                                                 refresh_session_pub);
    if (NULL == sigs[newcoin_index])
    {
      // FIXME: return 'internal error'
      GNUNET_break (0);
      GNUNET_free (sigs);
      return MHD_NO;
    }
  }
  res = TALER_MINT_reply_refresh_reveal_success (connection,
                                                 refresh_session->num_newcoins,
                                                 sigs);
  GNUNET_free (sigs);
  return res;
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
  unsigned int i;
  unsigned int j;
  unsigned int off;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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

  /* Check that the transfer private keys match their commitments.
   * Then derive the shared secret for each kappa, and check that they match. */

  off = 0;
  for (i = 0; i < refresh_session.kappa - 1; i++)
  {
    struct TALER_LinkSecret last_shared_secret;
    int secret_initialized = GNUNET_NO;

    if (i == refresh_session.noreveal_index)
      off = 1;

    for (j = 0; j < refresh_session.num_oldcoins; j++)
    {
      struct RefreshCommitLink commit_link;
      struct TALER_TransferSecret transfer_secret;
      struct TALER_LinkSecret shared_secret;
      struct RefreshMelt melt;

      res = TALER_MINT_DB_get_refresh_commit_link (db_conn,
                                                   refresh_session_pub,
                                                   i + off, j,
                                                   &commit_link);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
            // FIXME: return 'internal error'?
        return MHD_NO;
      }

      res = TALER_MINT_DB_get_refresh_melt (db_conn,
                                            refresh_session_pub,
                                            j,
                                            &melt);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
        // FIXME: return 'internal error'?
        return MHD_NO;
      }

      /* We're converting key types here, which is not very nice
       * but necessary and harmless (keys will be thrown away later). */
      /* FIXME: ECDHE/ECDSA-key type confusion! Can we reduce/avoid this? */
      if (GNUNET_OK !=
          GNUNET_CRYPTO_ecc_ecdh ((const struct GNUNET_CRYPTO_EcdhePrivateKey *) &transfer_privs[i+off][j],
                                  (const struct GNUNET_CRYPTO_EcdhePublicKey *) &melt.coin.coin_pub,
                                  &transfer_secret.key))
      {
        GNUNET_break (0);
        // FIXME: return 'internal error'?
        return MHD_NO;
      }

      if (GNUNET_OK !=
          TALER_transfer_decrypt (&commit_link.shared_secret_enc,
                                  &transfer_secret,
                                  &shared_secret))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "decryption failed\n");
        // FIXME: return 'internal error'?
        return MHD_NO;
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
        // FIXME: return error code!
        return MHD_NO;
      }

      {
        struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub_check;

        GNUNET_CRYPTO_ecdsa_key_get_public (&transfer_privs[i+off][j],
                                            &transfer_pub_check);
        if (0 !=
            memcmp (&transfer_pub_check,
                    &commit_link.transfer_pub,
                    sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey)))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "transfer keys do not match\n");
          // FIXME: return error code!
          return MHD_NO;
        }
      }
    }

    /* Check that the commitments for all new coins were correct */
    for (j = 0; j < refresh_session.num_newcoins; j++)
    {
      struct RefreshCommitCoin commit_coin;
      struct TALER_RefreshLinkDecrypted *link_data;
      // struct BlindedSignaturePurpose *coin_ev_check;
      struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
      struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
      struct GNUNET_HashCode h_msg;
      char *buf;
      size_t buf_len;

      res = TALER_MINT_DB_get_refresh_commit_coin (db_conn,
                                                   refresh_session_pub,
                                                   i+off, j,
                                                   &commit_coin);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
        // FIXME: return error code!
        return MHD_NO;
      }

      link_data = TALER_refresh_decrypt (commit_coin.refresh_link,
                                         &last_shared_secret);
      if (NULL == link_data)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "decryption failed\n");
        // FIXME: return error code!
        return MHD_NO;
      }

      GNUNET_CRYPTO_ecdsa_key_get_public (&link_data->coin_priv,
                                          &coin_pub);
      denom_pub = TALER_MINT_DB_get_refresh_order (db_conn,
                                                   j,
                                                   refresh_session_pub);
      if (NULL == denom_pub)
      {
        GNUNET_break (0);
          // FIXME: return error code!
        return MHD_NO;
      }
      /* FIXME: we had envisioned a more complex scheme to derive
         the message to sign for a blinded coin... */
      GNUNET_CRYPTO_hash (&coin_pub,
                          sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                          &h_msg);
      if (0 == (buf_len =
                GNUNET_CRYPTO_rsa_blind (&h_msg,
                                         link_data->blinding_key,
                                         denom_pub,
                                         &buf)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "blind failed\n");
          // FIXME: return error code!
        return MHD_NO;
      }

      if ( (buf_len != commit_coin.coin_ev_size) ||
           (0 != memcmp (buf,
                         commit_coin.coin_ev,
                         buf_len)) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "blind envelope does not match for kappa=%d, old=%d\n",
                    (int) (i+off), (int) j);
        // FIXME: return error code!
        GNUNET_free (buf);
        return MHD_NO;
      }
      GNUNET_free (buf);

    }
  }


  if (GNUNET_OK !=
      TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }

  for (j = 0; j < refresh_session.num_newcoins; j++)
  {
    struct RefreshCommitCoin commit_coin;
    struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
    struct TALER_MINT_DenomKeyIssuePriv *dki;
    struct GNUNET_CRYPTO_rsa_Signature *ev_sig;

    res = TALER_MINT_DB_get_refresh_commit_coin (db_conn,
                                                 refresh_session_pub,
                                                 refresh_session.noreveal_index % refresh_session.kappa,
                                                 j,
                                                 &commit_coin);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
              // FIXME: return error code!
      return MHD_NO;
    }
    denom_pub = TALER_MINT_DB_get_refresh_order (db_conn, j, refresh_session_pub);
    if (NULL == denom_pub)
    {
      GNUNET_break (0);
                    // FIXME: return error code!
      return MHD_NO;
    }


    key_state = TALER_MINT_key_state_acquire ();
    dki = TALER_MINT_get_denom_key (key_state, denom_pub);
    TALER_MINT_key_state_release (key_state);
    if (NULL == dki)
    {
      GNUNET_break (0);
                    // FIXME: return error code!
      return MHD_NO;
    }
    ev_sig = GNUNET_CRYPTO_rsa_sign (dki->denom_priv,
                                     commit_coin.coin_ev,
                                     commit_coin.coin_ev_size);
    if (NULL == ev_sig)
    {
      GNUNET_break (0);
                    // FIXME: return error code!
      return MHD_NO;
    }

    res = TALER_MINT_DB_insert_refresh_collectable (db_conn,
                                                    j,
                                                    refresh_session_pub,
                                                    ev_sig);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
                          // FIXME: return error code!
      return MHD_NO;
    }
  }
  /* mark that reveal was successful */

  res = TALER_MINT_DB_set_reveal_ok (db_conn, refresh_session_pub);
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    // FIXME: return error code!
    return MHD_NO;
  }

  if (GNUNET_OK !=
      TALER_MINT_DB_commit (db_conn))
  {
    LOG_WARNING ("/refresh/reveal transaction commit failed\n");
    return TALER_MINT_reply_commit_error (connection);
  }

  return helper_refresh_reveal_send_response (connection,
                                              db_conn,
                                              &refresh_session,
                                              refresh_session_pub);
}



/**
 * FIXME: move into response generation logic!
 * FIXME: need to separate this from DB logic!
 */
static int
link_iter (void *cls,
           const struct TALER_RefreshLinkEncrypted *link_data_enc,
           const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub,
           const struct GNUNET_CRYPTO_rsa_Signature *ev_sig)
{
  json_t *list = cls;
  json_t *obj = json_object ();
  char *buf;
  size_t buf_len;


  json_array_append_new (list, obj);

  json_object_set_new (obj, "link_enc",
                       TALER_JSON_from_data (link_data_enc->coin_priv_enc,
                                             sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey) +
                                             link_data_enc->blinding_key_enc_size));

  buf_len = GNUNET_CRYPTO_rsa_public_key_encode (denom_pub,
                                                 &buf);
  json_object_set_new (obj, "denom_pub",
                       TALER_JSON_from_data (buf,
                                             buf_len));
  GNUNET_free (buf);
  buf_len = GNUNET_CRYPTO_rsa_signature_encode (ev_sig,
                                                &buf);
  json_object_set_new (obj, "ev_sig",
                       TALER_JSON_from_data (buf,
                                             buf_len));
  GNUNET_free (buf);

  return GNUNET_OK;
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
  json_t *root;
  json_t *list;
  PGconn *db_conn;
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;
  struct GNUNET_HashCode shared_secret_enc;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
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

  /* FIXME: separate out response generation logic! */

  list = json_array ();
  root = json_object ();
  json_object_set_new (root, "new_coins", list);

  res = TALER_db_get_link (db_conn, coin_pub,
                           &link_iter, list);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    // FIXME: return error code!
    return MHD_NO;
  }
  if (GNUNET_NO == res)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "link data not found (link)");
  }
  GNUNET_assert (GNUNET_OK == res);
  json_object_set_new (root, "transfer_pub",
                       TALER_JSON_from_data (&transfer_pub,
                                             sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)));
  json_object_set_new (root, "secret_enc",
                       TALER_JSON_from_data (&shared_secret_enc,
                                             sizeof (struct GNUNET_HashCode)));
  res = TALER_MINT_reply_json (connection,
                               root,
                               MHD_HTTP_OK);
  json_decref (root);
  return res;
}


/* end of taler-mint-httpd_db.c */
