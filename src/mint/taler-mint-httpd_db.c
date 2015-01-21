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
    return TALER_MINT_reply_internal_error (connection,
                                            "Failed to connect to database");
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
    return TALER_MINT_reply_internal_error (connection,
                                            "Failed to connect to database");
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
 * @param wsrd_ro details about the withdraw request
 * @return MHD result code
 */
int
TALER_MINT_db_execute_withdraw_sign (struct MHD_Connection *connection,
                                     const struct TALER_WithdrawRequest *wsrd_ro)
{
  PGconn *db_conn;
  struct Reserve reserve;
  struct MintKeyState *key_state;
  struct CollectableBlindcoin collectable;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct TALER_RSA_Signature ev_sig;
  struct TALER_Amount amount_required;
  /* FIXME: the fact that we do this here is a sign that we
     need to have different versions of this struct for
     the different places it is used! */
  struct TALER_WithdrawRequest wsrd = *wsrd_ro;
  int res;

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }


  res = TALER_MINT_DB_get_collectable_blindcoin (db_conn,
                                                 &wsrd.coin_envelope,
                                                 &collectable);
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }

  /* Don't sign again if we have already signed the coin */
  if (GNUNET_YES == res)
    return TALER_MINT_reply_withdraw_sign_success (connection,
                                                   &collectable);
  GNUNET_assert (GNUNET_NO == res);
  res = TALER_MINT_DB_get_reserve (db_conn,
                                   &wsrd.reserve_pub,
                                   &reserve);
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_NO == res)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Reserve not found");

  // fill out all the missing info in the request before
  // we can check the signature on the request

  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_WITHDRAW);
  wsrd.purpose.size = htonl (sizeof (struct TALER_WithdrawRequest) -
                              offsetof (struct TALER_WithdrawRequest, purpose));

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WITHDRAW,
                                  &wsrd.purpose,
                                  &wsrd.sig,
                                  &wsrd.reserve_pub))
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       "{s:s}",
                                       "error", "Invalid Signature");

  key_state = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (key_state,
                                  &wsrd.denomination_pub);
  TALER_MINT_key_state_release (key_state);
  if (NULL == dki)
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "Denomination not found");

  amount_required = TALER_amount_ntoh (dki->issue.value);
  amount_required = TALER_amount_add (amount_required,
                                      TALER_amount_ntoh (dki->issue.fee_withdraw));

  if (0 < TALER_amount_cmp (amount_required,
                            TALER_amount_ntoh (reserve.balance)))
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_PAYMENT_REQUIRED,
                                       "{s:s}",
                                       "error",
                                       "Insufficient funds");
  if (GNUNET_OK !=
      TALER_RSA_sign (dki->denom_priv,
                      &wsrd.coin_envelope,
                      sizeof (struct TALER_RSA_BlindedSignaturePurpose),
                      &ev_sig))
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }

  reserve.balance = TALER_amount_hton (TALER_amount_subtract (TALER_amount_ntoh (reserve.balance),
                                                              amount_required));
  if (GNUNET_OK !=
      TALER_MINT_DB_update_reserve (db_conn,
                                    &reserve,
                                    GNUNET_YES))
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }

  collectable.ev = wsrd.coin_envelope;
  collectable.ev_sig = ev_sig;
  collectable.reserve_pub = wsrd.reserve_pub;
  collectable.reserve_sig = wsrd.sig;
  if (GNUNET_OK !=
      TALER_MINT_DB_insert_collectable_blindcoin (db_conn,
                                                  &collectable))
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return GNUNET_NO;;
  }
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
                       const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pubs,
                       struct TALER_Amount *r_amount)
{
  unsigned int i;
  int res;
  struct TALER_MINT_DenomKeyIssue *dki;
  struct TALER_Amount cost;

  memset (r_amount, 0, sizeof (struct TALER_Amount));
  for (i = 0; i < denom_pubs_count; i++)
  {
    dki = &(TALER_MINT_get_denom_key (key_state, &denom_pubs[i])->issue);
    cost = TALER_amount_add (TALER_amount_ntoh (dki->value),
                             TALER_amount_ntoh (dki->fee_withdraw));
    *r_amount = TALER_amount_add (cost, *r_amount);


    /* Insert the requested coin into the DB, so we'll know later
     * what denomination the request had */

    if (GNUNET_OK !=
        (res = TALER_MINT_DB_insert_refresh_order (db_conn,
                                                   i,
                                                   session_pub,
                                                   &denom_pubs[i])))
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

    dki = &(TALER_MINT_get_denom_key (key_state, &coin_public_infos[i].denom_pub)->issue);

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

    if (GNUNET_OK != TALER_MINT_DB_insert_refresh_melt (db_conn, session_pub, i,
                                                        &coin_public_infos[i].coin_pub,
                                                        &coin_public_infos[i].denom_pub))
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
                                    const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pubs,
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
    /* FIXME: return error code to MHD! */
    return MHD_NO;
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
 * @param num_oldcoins size of y-dimension of @commit_coin and @commit_link arrays
 * @param num_newcoins size of y-dimension of @commit_coin and @commit_link arrays
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
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
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
                                                    &commit_coin[i][j]))
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_break (GNUNET_OK == TALER_MINT_DB_rollback (db_conn));
        return MHD_NO;
      }

      if (GNUNET_OK !=
          TALER_MINT_DB_insert_refresh_commit_link (db_conn, &commit_link[i][j]))
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
