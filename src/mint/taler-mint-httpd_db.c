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
