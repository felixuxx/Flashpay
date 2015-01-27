/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @brief Database access abstraction for the mint.
 * @author Christian Grothoff
 *
 * TODO:
 * - actually abstract DB implementation (i.e. via plugin logic)
 * - /deposit: properly check existing deposits
 * - /deposit: properly perform commit (check return value)
 * - /deposit: check for leaks
 * - ALL: check API: given structs are usually not perfect, as they
 *        often contain too many fields for the context
 * - ALL: check transactional behavior
 */
#include "platform.h"
#include <pthread.h>
#include <jansson.h>
#include "taler-mint-httpd_db.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_responses.h"
#include "mint_db.h"
#include "mint.h"
#include "taler_json_lib.h"


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
  struct Deposit *existing_deposit;
  int res;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = TALER_MINT_DB_get_deposit (db_conn,
                                   &deposit->coin_pub,
                                   &existing_deposit);
  if (GNUNET_YES == res)
  {
    // FIXME: memory leak
    // FIXME: memcmp will not actually work here
    if (0 == memcmp (existing_deposit, deposit, sizeof (struct Deposit)))
      return TALER_MINT_reply_deposit_success (connection, deposit);
    // FIXME: in the future, check if there's enough credits
    // left on the coin. For now: refuse
    // FIXME: return more information here
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s}",
                                       "error",
                                       "double spending");
  }

  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
    return MHD_NO;
  }

  {
    struct KnownCoin known_coin;
    int res;
    struct TALER_CoinPublicInfo coin_info;

    res = TALER_MINT_DB_get_known_coin (db_conn, &coin_info.coin_pub, &known_coin);
    if (GNUNET_YES == res)
    {
      // coin must have been refreshed
      // FIXME: check
      // FIXME: return more information here
      return TALER_MINT_reply_json_pack (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         "{s:s}",
                                         "error", "coin was refreshed");
    }
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
      return MHD_NO;
    }

    /* coin valid but not known => insert into DB */
    known_coin.is_refreshed = GNUNET_NO;
    known_coin.expended_balance = TALER_amount_ntoh (deposit->amount);
    known_coin.public_info = coin_info;

    if (GNUNET_OK != TALER_MINT_DB_insert_known_coin (db_conn, &known_coin))
    {
      GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
      return MHD_NO;
    }
  }

  if (GNUNET_OK != TALER_MINT_DB_insert_deposit (db_conn, deposit))
  {
    GNUNET_break (0);
    /* FIXME: return error message to client via MHD! */
    return MHD_NO;
  }
  // FIXME: check commit return value!
  TALER_MINT_DB_commit (db_conn);
  return TALER_MINT_reply_deposit_success (connection, deposit);
}


/**
 * Sign a reserve's status with the current signing key.
 * FIXME: not sure why we do this.  Should just return
 * existing list of operations on the reserve.
 *
 * @param reserve the reserve to sign
 * @param key_state the key state containing the current
 *                  signing private key
 */
static void
sign_reserve (struct Reserve *reserve,
              struct MintKeyState *key_state)
{
  reserve->status_sign_pub = key_state->current_sign_key_issue.issue.signkey_pub;
  reserve->status_sig_purpose.purpose = htonl (TALER_SIGNATURE_RESERVE_STATUS);
  reserve->status_sig_purpose.size = htonl (sizeof (struct Reserve) -
                                          offsetof (struct Reserve, status_sig_purpose));
  GNUNET_CRYPTO_eddsa_sign (&key_state->current_sign_key_issue.signkey_priv,
                            &reserve->status_sig_purpose,
                            &reserve->status_sig);
}


/**
 * Execute a /withdraw/status.
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
  int res;
  struct Reserve reserve;
  struct MintKeyState *key_state;
  int must_update = GNUNET_NO;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = TALER_MINT_DB_get_reserve (db_conn,
                                   reserve_pub,
                                   &reserve);
  /* check if these are really the matching error codes,
     seems odd... */
  if (GNUNET_SYSERR == res)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Reserve not found");
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_error (connection,
                                            "Internal error");
  }
  key_state = TALER_MINT_key_state_acquire ();
  if (0 != memcmp (&key_state->current_sign_key_issue.issue.signkey_pub,
                   &reserve.status_sign_pub,
                   sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)))
  {
    sign_reserve (&reserve, key_state);
    must_update = GNUNET_YES;
  }
  if ((GNUNET_YES == must_update) &&
      (GNUNET_OK != TALER_MINT_DB_update_reserve (db_conn, &reserve, !must_update)))
  {
    GNUNET_break (0);
    return MHD_YES;
  }
  return TALER_MINT_reply_withdraw_status_success (connection,
                                                   &reserve);
}


/**
 * Execute a /withdraw/sign.
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
  struct Reserve db_reserve;
  struct MintKeyState *key_state;
  struct CollectableBlindcoin collectable;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct TALER_Amount amount_required;
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
  res = TALER_MINT_DB_get_reserve (db_conn,
                                   reserve,
                                   &db_reserve);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  if (GNUNET_NO == res)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Reserve not found");

  key_state = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (key_state,
                                  denomination_pub);
  TALER_MINT_key_state_release (key_state);
  if (NULL == dki)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Denomination not found");

  amount_required = TALER_amount_add (TALER_amount_ntoh (dki->issue.value),
                                      TALER_amount_ntoh (dki->issue.fee_withdraw));
  if (0 < TALER_amount_cmp (amount_required,
                            TALER_amount_ntoh (db_reserve.balance)))
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_PAYMENT_REQUIRED,
                                       "{s:s}",
                                       "error",
                                       "Insufficient funds");

  db_reserve.balance = TALER_amount_hton
    (TALER_amount_subtract (TALER_amount_ntoh (db_reserve.balance),
                            amount_required));

  sig = GNUNET_CRYPTO_rsa_sign (dki->denom_priv,
                                blinded_msg,
                                blinded_msg_len);
  if (NULL == sig)
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_error (connection,
                                            "Internal error");
  }

  /* transaction start */
  if (GNUNET_OK !=
      TALER_MINT_DB_update_reserve (db_conn,
                                    &db_reserve,
                                    GNUNET_YES))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
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
    return TALER_MINT_reply_internal_db_error (connection);
  }
  /* transaction end */
  GNUNET_CRYPTO_rsa_signature_free (sig);
  return TALER_MINT_reply_withdraw_sign_success (connection,
                                                 &collectable);
}


/**
 * Insert  all requested denominations  into the  db, and  compute the
 * required cost of the denominations, including fees.
 *
 * @param connection the connection to send an error response to
 * @param db_conn the database connection
 * @param key_state the mint's key state to use
 * @param session_pub the refresh session public key
 * @param denom_pubs_count number of entries in @a denom_pubs
 * @param denom_pubs array of public keys for the refresh
 * @param r_amount the sum of the cost (value+fee) for
 *        all requested coins
 * @return FIXME!
 */
static int
refresh_accept_denoms (struct MHD_Connection *connection,
                       PGconn *db_conn,
                       const struct MintKeyState *key_state,
                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                       unsigned int denom_pubs_count,
                       const struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs,
                       struct TALER_Amount *r_amount)
{
  unsigned int i;
  int res;
  struct TALER_MINT_DenomKeyIssue *dki;
  struct TALER_Amount cost;

  memset (r_amount, 0, sizeof (struct TALER_Amount));
  for (i = 0; i < denom_pubs_count; i++)
  {
    dki = &(TALER_MINT_get_denom_key (key_state,
                                      denom_pubs[i])->issue);
    cost = TALER_amount_add (TALER_amount_ntoh (dki->value),
                             TALER_amount_ntoh (dki->fee_withdraw));
    *r_amount = TALER_amount_add (cost, *r_amount);


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
 * Get an amount in the mint's currency that is zero.
 *
 * @return zero amount in the mint's currency
 */
static struct TALER_Amount
mint_amount_native_zero ()
{
  struct TALER_Amount amount;

  memset (&amount, 0, sizeof (amount));
  // FIXME: load from config
  memcpy (amount.currency, "EUR", 3);

  return amount;
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
 * @param r_melt_balance FIXME
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
  int res;

  memset (r_melt_balance, 0, sizeof (struct TALER_Amount));

  for (i = 0; i < coin_count; i++)
  {
    struct TALER_MINT_DenomKeyIssue *dki;
    struct KnownCoin known_coin;
    // money the customer gets by melting the current coin
    struct TALER_Amount coin_gain;

    dki = &(TALER_MINT_get_denom_key (key_state,
                                      coin_public_infos[i].denom_pub)->issue);

    if (NULL == dki)
      return (MHD_YES ==
              TALER_MINT_reply_json_pack (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          "{s:s}",
                                          "error", "denom not found"))
        ? GNUNET_NO : GNUNET_SYSERR;


    res = TALER_MINT_DB_get_known_coin (db_conn,
                                        &coin_public_infos[i].coin_pub,
                                        &known_coin);

    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    if (GNUNET_YES == res)
    {
      if (GNUNET_YES == known_coin.is_refreshed)
        return (MHD_YES ==
                TALER_MINT_reply_json_pack (connection,
                                            MHD_HTTP_NOT_FOUND,
                                            "{s:s}",
                                            "error",
                                            "coin already refreshed"))
          ? GNUNET_NO : GNUNET_SYSERR;
    }
    else
    {
      known_coin.expended_balance = mint_amount_native_zero ();
      known_coin.public_info = coin_public_infos[i];
    }

    known_coin.is_refreshed = GNUNET_YES;
    known_coin.refresh_session_pub = *session_pub;

    if (GNUNET_OK != TALER_MINT_DB_upsert_known_coin (db_conn, &known_coin))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    if (GNUNET_OK !=
        TALER_MINT_DB_insert_refresh_melt (db_conn, session_pub, i,
                                           &coin_public_infos[i].coin_pub,
                                           coin_public_infos[i].denom_pub))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    coin_gain = TALER_amount_ntoh (dki->value);
    coin_gain = TALER_amount_subtract (coin_gain, known_coin.expended_balance);

    /* Refuse to refresh when the coin does not have enough money left to
     * pay the refreshing fees of the coin. */

    if (TALER_amount_cmp (coin_gain, TALER_amount_ntoh (dki->fee_refresh)) < 0)
      return (MHD_YES ==
              TALER_MINT_reply_json_pack (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          "{s:s}",
                                          "error", "depleted")) ? GNUNET_NO : GNUNET_SYSERR;

    coin_gain = TALER_amount_subtract (coin_gain, TALER_amount_ntoh (dki->fee_refresh));

    *r_melt_balance = TALER_amount_add (*r_melt_balance, coin_gain);
  }
  return GNUNET_OK;
}


/**
 * Execute a /refresh/melt.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the refresh session
 * @param num_new_denoms number of entries in @a denom_pubs
 * @param denum_pubs ???
 * @param coin_count number of entries in @a coin_public_infos
 * @param coin_public_infos information about the coins to melt
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_melt (struct MHD_Connection *connection,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                    unsigned int num_new_denoms,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs,
                                    unsigned int coin_count,
                                    const struct TALER_CoinPublicInfo *coin_public_infos)
{
  struct TALER_Amount requested_cost;
  struct TALER_Amount melt_balance;
  struct MintKeyState *key_state;
  struct RefreshSession session;
  PGconn *db_conn;
  int res;

  /* We incrementally update the db with other parameters in a transaction.
   * The transaction is aborted if some parameter does not validate. */

  /* Send response immediately if we already know the session.
   * Do _not_ care about fields other than session_pub in this case. */

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    return TALER_MINT_reply_internal_db_error (connection);
  }
  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           NULL);
  if (GNUNET_YES == res)
  {
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
                                                  &session,
                                                  refresh_session_pub);
  }
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }


  if (GNUNET_OK != TALER_MINT_DB_transaction (db_conn))
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }

  if (GNUNET_OK != TALER_MINT_DB_create_refresh_session (db_conn,
                                                         refresh_session_pub))
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    TALER_MINT_DB_rollback (db_conn);
    return MHD_NO;
  }

  /* The next two operations must see the same key state,
   * thus we acquire it here. */

  key_state = TALER_MINT_key_state_acquire ();
  if (GNUNET_OK !=
      (res = refresh_accept_denoms (connection, db_conn, key_state,
                                    refresh_session_pub,
                                    num_new_denoms,
                                    denom_pubs,
                                    &requested_cost)))
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
    GNUNET_break (GNUNET_OK == TALER_MINT_DB_rollback (db_conn));
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  TALER_MINT_key_state_release (key_state);


  /* Request is only ok if cost of requested coins
   * does not exceed value of melted coins. */

  // FIXME: also, consider fees?
  if (TALER_amount_cmp (melt_balance, requested_cost) < 0)
  {
    GNUNET_break (GNUNET_OK == TALER_MINT_DB_rollback (db_conn));

    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s}",
                                       "error",
                                       "not enough coins melted");
  }

  if (GNUNET_OK != TALER_MINT_DB_commit (db_conn))
  {
    GNUNET_break (0);
    return MHD_NO;
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
                                                &session,
                                                refresh_session_pub);


}


/**
 * Execute a /refresh/commit.
 *
 * @param connection the MHD connection to handle
 * @param kappa size of x-dimension of @commit_coin and @commit_link arrays
 * @param num_oldcoins size of y-dimension of @commit_link array
 * @param num_newcoins size of y-dimension of @commit_coin array
 * @param commit_coin
 * @param commit_link
 * @return MHD result code
 */
int
TALER_MINT_db_execute_refresh_commit (struct MHD_Connection *connection,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
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

  /* Send response immediately if we already know the session.
   * Do _not_ care about fields other than session_pub in this case. */

  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           &refresh_session);
  // FIXME: this should check that kappa and num_newcoins match
  // our expectations from refresh_session!

  for (i = 0; i < refresh_session.kappa; i++)
  {
    for (j = 0; j < refresh_session.num_newcoins; j++)
    {
      if (GNUNET_OK !=
          TALER_MINT_DB_insert_refresh_commit_coin (db_conn,
                                                    refresh_session_pub,
                                                    i,
                                                    j,
                                                    &commit_coin[i][j]))
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_break (GNUNET_OK == TALER_MINT_DB_rollback (db_conn));
        return MHD_NO;
      }

      if (GNUNET_OK !=
          TALER_MINT_DB_insert_refresh_commit_link (db_conn,
                                                    refresh_session_pub,
                                                    i,
                                                    j,
                                                    &commit_link[i][j]))
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_break (GNUNET_OK == TALER_MINT_DB_rollback (db_conn));
        return MHD_NO;
      }
    }
  }





  if ( (GNUNET_YES == res) &&
       (GNUNET_YES == refresh_session.has_commit_sig) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "sending cached commit response\n");
    res = TALER_MINT_reply_refresh_commit_success (connection,
                                                   &refresh_session);
    GNUNET_break (res != GNUNET_SYSERR);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }

  if (GNUNET_OK != TALER_MINT_DB_transaction (db_conn))
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }

  /* Re-fetch the session information from the database,
   * in case a concurrent transaction modified it. */

  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           &refresh_session);
  if (GNUNET_OK != res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (GNUNET_SYSERR != res);
    GNUNET_break (GNUNET_OK == TALER_MINT_DB_rollback (db_conn));
    return MHD_NO;
  }

  if (GNUNET_OK != TALER_MINT_DB_commit (db_conn))
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
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
 * Execute a /refresh/reveal.
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

  /* Send response immediately if we already know the session,
   * and the session commited already.
   * Do _not_ care about fields other than session_pub in this case. */

  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           &refresh_session);
  if (GNUNET_YES == res && 0 != refresh_session.reveal_ok)
    return helper_refresh_reveal_send_response (connection,
                                                db_conn,
                                                &refresh_session,
                                                refresh_session_pub);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    // FIXME: return 'internal error'?
    return MHD_NO;
  }

  /* Check that the transfer private keys match their commitments.
   * Then derive the shared secret for each kappa, and check that they match. */

  off = 0;
  for (i = 0; i < refresh_session.kappa - 1; i++)
  {
    struct GNUNET_HashCode last_shared_secret;
    int secret_initialized = GNUNET_NO;

    if (i == refresh_session.noreveal_index)
      off = 1;

    for (j = 0; j < refresh_session.num_oldcoins; j++)
    {
      struct RefreshCommitLink commit_link;
      struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
      struct GNUNET_HashCode transfer_secret;
      struct GNUNET_HashCode shared_secret;

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

      res = TALER_MINT_DB_get_refresh_melt (db_conn, refresh_session_pub, j, &coin_pub);
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
                                  (const struct GNUNET_CRYPTO_EcdhePublicKey *) &coin_pub,
                                  &transfer_secret))
      {
        GNUNET_break (0);
        // FIXME: return 'internal error'?
        return MHD_NO;
      }

      if (0 >= TALER_refresh_decrypt (commit_link.shared_secret_enc,
                                      TALER_REFRESH_SHARED_SECRET_LENGTH,
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
      struct LinkData link_data;
      // struct BlindedSignaturePurpose *coin_ev_check;
      struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
      struct GNUNET_CRYPTO_rsa_BlindingKey *bkey;
      struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
      struct GNUNET_HashCode h_msg;
      char *buf;
      size_t buf_len;

      bkey = NULL;
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


      if (0 >= TALER_refresh_decrypt (commit_coin.link_enc,
                                      sizeof (struct LinkData),
                                      &last_shared_secret,
                                      &link_data))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "decryption failed\n");
        // FIXME: return error code!
        return MHD_NO;
      }

      GNUNET_CRYPTO_ecdsa_key_get_public (&link_data.coin_priv,
                                          &coin_pub);
      if (NULL == (bkey = GNUNET_CRYPTO_rsa_blinding_key_decode (link_data.bkey_enc,
                                                                 link_data.bkey_enc_size)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Invalid blinding key\n");
        // FIXME: return error code!
        return MHD_NO;
      }
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
                                         bkey,
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


  if (GNUNET_OK != TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
            // FIXME: return error code!
    return MHD_NO;
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
                                     commit_coin.coin_ev_len);
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

  if (GNUNET_OK != TALER_MINT_DB_commit (db_conn))
  {
    GNUNET_break (0);
    return MHD_NO;
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
           const struct LinkDataEnc *link_data_enc,
           const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub,
           const struct GNUNET_CRYPTO_rsa_Signature *ev_sig)
{
  json_t *list = cls;
  json_t *obj = json_object ();
  char *buf;
  size_t buf_len;


  json_array_append_new (list, obj);

  json_object_set_new (obj, "link_enc",
                       TALER_JSON_from_data (link_data_enc,
                                             sizeof (struct LinkDataEnc)));

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
 * Execute a /refresh/link.
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
  struct SharedSecretEnc shared_secret_enc;

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
        // FIXME: return error code!
    return MHD_NO;
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
                                             sizeof (struct SharedSecretEnc)));
  return TALER_MINT_reply_json (connection,
                                root,
                                MHD_HTTP_OK);
}
