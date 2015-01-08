/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_withdraw.c
 * @brief Handle /withdraw/ requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <libpq-fe.h>
#include <pthread.h>
#include "mint.h"
#include "mint_db.h"
#include "taler_types.h"
#include "taler_signatures.h"
#include "taler_rsa.h"
#include "taler_json_lib.h"
#include "taler_microhttpd_lib.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_mhd.h"
#include "taler-mint-httpd_withdraw.h"


/**
 * Convert a signature (with purpose) to
 * a JSON object representation.
 *
 * @param purpose purpose of the signature
 * @param signature the signature
 * @return the JSON reporesentation of the signature with purpose
 */
static json_t *
sig_to_json (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
             const struct GNUNET_CRYPTO_EddsaSignature *signature)
{
  json_t *root;
  json_t *el;

  root = json_object ();

  el = json_integer ((json_int_t) ntohl (purpose->size));
  json_object_set_new (root, "size", el);

  el = json_integer ((json_int_t) ntohl (purpose->purpose));
  json_object_set_new (root, "purpose", el);

  el = TALER_JSON_from_data (signature, sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  json_object_set_new (root, "sig", el);

  return root;
}


/**
 * Sign a reserve's status with the current signing key.
 *
 * @param reserve the reserve to sign
 * @param key_state the key state containing the current
 *                  signing private key
 */
static void
sign_reserve (struct Reserve *reserve,
              struct MintKeyState *key_state)
{
  reserve->status_sign_pub = key_state->current_sign_key_issue.signkey_pub;
  reserve->status_sig_purpose.purpose = htonl (TALER_SIGNATURE_RESERVE_STATUS);
  reserve->status_sig_purpose.size = htonl (sizeof (struct Reserve) -
                                          offsetof (struct Reserve, status_sig_purpose));
  GNUNET_CRYPTO_eddsa_sign (&key_state->current_sign_key_issue.signkey_priv,
                            &reserve->status_sig_purpose,
                            &reserve->status_sig);
}


/**
 * Handle a "/withdraw/status" request
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_withdraw_status (struct RequestHandler *rh,
                                    struct MHD_Connection *connection,
                                    void **connection_cls,
                                    const char *upload_data,
                                    size_t *upload_data_size)
{
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;
  PGconn *db_conn;
  int res;
  struct Reserve reserve;
  struct MintKeyState *key_state;
  int must_update = GNUNET_NO;
  json_t *json;

  res = TALER_MINT_mhd_request_arg_data (connection,
                                  "reserve_pub",
                                  &reserve_pub,
                                  sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_OK != res)
    return MHD_YES;
  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  res = TALER_MINT_DB_get_reserve (db_conn,
                                   &reserve_pub,
                                   &reserve);
  if (GNUNET_SYSERR == res)
    return TALER_MINT_helper_send_json_pack (rh,
                                  connection,
                                  connection_cls,
                                  0 /* no caching */,
                                  MHD_HTTP_NOT_FOUND,
                                  "{s:s}",
                                  "error",
                                  "Reserve not found");
  if (GNUNET_OK != res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  key_state = TALER_MINT_key_state_acquire ();
  if (0 != memcmp (&key_state->current_sign_key_issue.signkey_pub,
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

  /* Convert the public information of a reserve (i.e.
     excluding private key) to a JSON object. */
  json = json_object ();
  json_object_set_new (json,
                       "balance",
                       TALER_JSON_from_amount (TALER_amount_ntoh (reserve.balance)));
  json_object_set_new (json,
                       "expiration",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (reserve.expiration)));
  json_object_set_new (json,
                       "signature",
                       sig_to_json (&reserve.status_sig_purpose,
                                    &reserve.status_sig));

  return send_response_json (connection,
                             json,
                             MHD_HTTP_OK);
}


/**
 * Send positive, normal response for "/withdraw/sign".
 *
 * @param connection the connection to send the response to
 * @param collectable the collectable blindcoin (i.e. the blindly signed coin)
 * @return a MHD result code
 */
static int
helper_withdraw_sign_send_reply (struct MHD_Connection *connection,
                                 const struct CollectableBlindcoin *collectable)
{
  json_t *root = json_object ();

  json_object_set_new (root, "ev_sig",
                       TALER_JSON_from_data (&collectable->ev_sig,
                                             sizeof (struct TALER_RSA_Signature)));
  return send_response_json (connection,
                             root,
                             MHD_HTTP_OK);
}


/**
 * Handle a "/withdraw/sign" request
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_withdraw_sign (struct RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  struct TALER_WithdrawRequest wsrd;
  int res;
  PGconn *db_conn;
  struct Reserve reserve;
  struct MintKeyState *key_state;
  struct CollectableBlindcoin collectable;
  struct TALER_MINT_DenomKeyIssue *dki;
  struct TALER_RSA_Signature ev_sig;
  struct TALER_Amount amount_required;

  memset (&wsrd,
          0,
          sizeof (struct TALER_WithdrawRequest));
  res = TALER_MINT_mhd_request_arg_data (connection,
                                  "reserve_pub",
                                  &wsrd.reserve_pub,
                                  sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_OK != res)
    return MHD_YES;
  res = TALER_MINT_mhd_request_arg_data (connection,
                                  "denom_pub",
                                  &wsrd.denomination_pub,
                                  sizeof (struct TALER_RSA_PublicKeyBinaryEncoded));
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_OK != res)
    return MHD_YES;
  res = TALER_MINT_mhd_request_arg_data (connection,
                                  "coin_ev",
                                  &wsrd.coin_envelope,
                                  sizeof (struct TALER_RSA_Signature));
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_OK != res)
    return MHD_YES;
  res = TALER_MINT_mhd_request_arg_data (connection,
                                  "reserve_sig",
                                  &wsrd.sig,
                                  sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_OK != res)
    return MHD_YES;

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
    return helper_withdraw_sign_send_reply (connection,
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
    return request_send_json_pack (connection,
                                   MHD_HTTP_NOT_FOUND,
                                   "{s:s}",
                                   "error", "Reserve not found");

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
    return request_send_json_pack (connection,
                                   MHD_HTTP_UNAUTHORIZED,
                                   "{s:s}",
                                   "error", "Invalid Signature");

  key_state = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (key_state,
                       &wsrd.denomination_pub);
  TALER_MINT_key_state_release (key_state);
  if (NULL == dki)
    return request_send_json_pack (connection, MHD_HTTP_NOT_FOUND,
                                   "{s:s}",
                                   "error", "Denomination not found");

  amount_required = TALER_amount_ntoh (dki->value);
  amount_required = TALER_amount_add (amount_required,
                                      TALER_amount_ntoh (dki->fee_withdraw));

  if (0 < TALER_amount_cmp (amount_required,
                            TALER_amount_ntoh (reserve.balance)))
    return request_send_json_pack (connection,
                                   MHD_HTTP_PAYMENT_REQUIRED,
                                   "{s:s}",
                                   "error", "Insufficient funds");
  if (GNUNET_OK != TALER_RSA_sign (dki->denom_priv,
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
  return helper_withdraw_sign_send_reply (connection,
                                          &collectable);
}

/* end of taler-mint-httpd_withdraw.c */
