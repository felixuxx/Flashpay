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
 * @file taler-mint-httpd_deposit.c
 * @brief Handle /deposit requests
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
#include "taler_signatures.h"
#include "taler_rsa.h"
#include "taler_json_lib.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_deposit.h"
#include "taler-mint-httpd_responses.h"


/**
 * Send confirmation of deposit success to client.
 *
 * @param connection connection to the client
 * @param deposit deposit request to confirm
 * @return MHD result code
 */
static int
helper_deposit_send_response_success (struct MHD_Connection *connection,
                                      struct Deposit *deposit)
{
  // FIXME: return more information here
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_OK,
                                     "{s:s}",
                                     "status",
                                     "DEPOSIT_OK");
}


/**
 * Handle a "/deposit" request
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TALER_MINT_handler_deposit (struct RequestHandler *rh,
                            struct MHD_Connection *connection,
                            void **connection_cls,
                            const char *upload_data,
                            size_t *upload_data_size)
{
  json_t *json;
  struct Deposit *deposit;
  json_t *wire;
  json_t *resp;
  char *wire_enc = NULL;
  const char *deposit_type;
  struct MintKeyState *key_state;
  struct TALER_CoinPublicInfo coin_info;
  struct TALER_RSA_Signature ubsig;
  size_t len;
  int resp_code;
  PGconn *db_conn;
  int res;

  res = TALER_MINT_parse_post_json (connection,
                           connection_cls,
                           upload_data, upload_data_size,
                           &json);
  if (GNUNET_SYSERR == res)
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_NO == res)
    return MHD_YES;
  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  deposit = NULL;
  wire = NULL;
  resp = NULL;
  if (-1 == json_unpack (json,
                         "{s:s s:o}",
                         "type", &deposit_type,
                         "wire", &wire))
  {
    GNUNET_break_op (0);
    resp = json_pack ("{s:s}", "error", "Bad format");
    resp_code = MHD_HTTP_BAD_REQUEST;
    goto EXITIF_exit;
  }
  if (NULL == (wire_enc = json_dumps (wire, JSON_COMPACT|JSON_SORT_KEYS)))
  {
    GNUNET_break_op (0);
    resp = json_pack ("{s:s}", "error", "Bad format");
    resp_code = MHD_HTTP_BAD_REQUEST;
    goto EXITIF_exit;
  }
  len = strlen (wire_enc) + 1;
  deposit = GNUNET_malloc (sizeof (struct Deposit) + len);
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)
#define PARSE_DATA(field, addr)                                         \
  EXITIF (GNUNET_OK != request_json_require_nav                         \
          (connection, json,                                            \
           JNAV_FIELD, field, JNAV_RET_DATA, addr, sizeof (*addr)))
  PARSE_DATA ("coin_pub", &deposit->coin_pub);
  PARSE_DATA ("denom_pub", &deposit->denom_pub);
  PARSE_DATA ("ubsig", &ubsig);
  PARSE_DATA ("merchant_pub", &deposit->merchant_pub);
  PARSE_DATA ("H_a", &deposit->h_contract);
  PARSE_DATA ("H_wire", &deposit->h_wire);
  PARSE_DATA ("csig", &deposit->coin_sig);
  PARSE_DATA ("transaction_id", &deposit->transaction_id);
#undef PARSE_DATA
  if (0 == strcmp ("DIRECT_DEPOSIT", deposit_type))
    deposit->purpose.purpose = htonl (TALER_SIGNATURE_DEPOSIT);
  else if (0 == strcmp ("INCREMENTAL_DEPOSIT", deposit_type))
    deposit->purpose.purpose = htonl (TALER_SIGNATURE_INCREMENTAL_DEPOSIT);
  else
  {
    GNUNET_break_op (0);
    resp = json_pack ("{s:s}", "error", "Bad format");
    resp_code = MHD_HTTP_BAD_REQUEST;
    goto EXITIF_exit;
  }
  deposit->purpose.size = htonl (sizeof (struct Deposit)
                                 - offsetof (struct Deposit, purpose));
  memcpy (&coin_info.coin_pub,
          &deposit->coin_pub,
          sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));
  coin_info.denom_pub = deposit->denom_pub;
  coin_info.denom_sig = ubsig;
  key_state = TALER_MINT_key_state_acquire ();
  if (GNUNET_YES != TALER_MINT_test_coin_valid (key_state,
                                &coin_info))
  {
    TALER_MINT_key_state_release (key_state);
    resp = json_pack ("{s:s}", "error", "Coin is not valid");
    resp_code = MHD_HTTP_NOT_FOUND;
    goto EXITIF_exit;
  }
  TALER_MINT_key_state_release (key_state);
  /*
  if (GNUNET_OK != GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_DEPOSIT,
                                                      &deposit->purpose,
                                                      &deposit->coin_sig,
                                                      &deposit->coin_pub))
  {
    resp = json_pack ("{s:s}", "error", "Signature verfication failed");
    resp_code = MHD_HTTP_NOT_FOUND;
    goto EXITIF_exit;
  }
  */

  /* Check if we already received the same deposit permission,
   * or the coin was already deposited */

  {
    struct Deposit *existing_deposit;
    int res;

    res = TALER_MINT_DB_get_deposit (db_conn,
                                     &deposit->coin_pub,
                                     &existing_deposit);
    if (GNUNET_YES == res)
    {
      // FIXME: memory leak
      if (0 == memcmp (existing_deposit, deposit, sizeof (struct Deposit)))
        return helper_deposit_send_response_success (connection, deposit);
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
      return GNUNET_SYSERR;
    }
  }

  {
    struct KnownCoin known_coin;
    int res;

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
      return GNUNET_SYSERR;
    }

    /* coin valid but not known => insert into DB */
    known_coin.is_refreshed = GNUNET_NO;
    known_coin.expended_balance = TALER_amount_ntoh (deposit->amount);
    known_coin.public_info = coin_info;

    if (GNUNET_OK != TALER_MINT_DB_insert_known_coin (db_conn, &known_coin))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }

  if (GNUNET_OK != TALER_MINT_DB_insert_deposit (db_conn, deposit))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return helper_deposit_send_response_success (connection, deposit);

 EXITIF_exit:
  if (NULL != resp)
    res = TALER_MINT_reply_json (connection,
                                 resp,
                                 resp_code);
  else
    res = MHD_NO;
  if (NULL != wire)
    json_decref (wire);
  if (NULL != deposit)
    GNUNET_free (deposit);
  if (NULL != wire_enc)
    GNUNET_free (wire_enc);
  return res;
#undef EXITIF
#undef PARSE_DATA
}

/* end of taler-mint-httpd_deposit.c */
