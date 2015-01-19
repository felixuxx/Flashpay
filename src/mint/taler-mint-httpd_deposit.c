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
 * @brief Handle /deposit requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 *
 * TODO:
 * - actually verify coin signature
 * - revisit `struct Deposit` parsing once the struct
 *   has been finalized
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
#include "taler-mint-httpd_db.h"
#include "taler-mint-httpd_deposit.h"
#include "taler-mint-httpd_responses.h"


/**
 * We have parsed the JSON information about the deposit, do some
 * basic sanity checks (especially that the signature on the coin is
 * valid, and that this type of coin exists) and then execute the
 * deposit.
 *
 * @param connection the MHD connection to handle
 * @param deposit information about the deposit
 * @return MHD result code
 */
static int
verify_and_execute_deposit (struct MHD_Connection *connection,
                            const struct Deposit *deposit)
{
  struct MintKeyState *key_state;
  struct TALER_CoinPublicInfo coin_info;

  memcpy (&coin_info.coin_pub,
          &deposit->coin_pub,
          sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));
  coin_info.denom_pub = deposit->denom_pub;
  coin_info.denom_sig = deposit->ubsig;

  key_state = TALER_MINT_key_state_acquire ();
  if (GNUNET_YES !=
      TALER_MINT_test_coin_valid (key_state,
                                  &coin_info))
  {
    TALER_MINT_key_state_release (key_state);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error", "Coin is not valid");
  }
  TALER_MINT_key_state_release (key_state);

  /* FIXME: verify coin signature! */
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

  return TALER_MINT_db_execute_deposit (connection,
                                        deposit);
}


/**
 * Handle a "/deposit" request.  This function parses the
 * JSON information and then calls #verify_and_execute_deposit()
 * to verify the data and execute the deposit.
 *
 * @param connection the MHD connection to handle
 * @param root root of the posted JSON
 * @param purpose is this a #TALER_SIGNATURE_DEPOSIT or
 *           #TALER_SIGNATURE_INCREMENTAL_DEPOSIT
 * @param wire json describing the wire details (?)
 * @return MHD result code
  */
static int
parse_and_handle_deposit_request (struct MHD_Connection *connection,
                                  const json_t *root,
                                  uint32_t purpose,
                                  const json_t *wire)
{
  struct Deposit *deposit;
  char *wire_enc;
  size_t len;
  int res;

  // FIXME: `struct Deposit` is clearly ill-defined, we should
  // not have to do this...
  if (NULL == (wire_enc = json_dumps (wire, JSON_COMPACT | JSON_SORT_KEYS)))
  {
    GNUNET_break_op (0);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error", "Bad format");

  }
  len = strlen (wire_enc) + 1;
  GNUNET_free (wire_enc);

  deposit = GNUNET_malloc (sizeof (struct Deposit) + len);
  {
    struct GNUNET_MINT_ParseFieldSpec spec[] =
      {
        TALER_MINT_PARSE_FIXED ("coin_pub", &deposit->coin_pub),
        TALER_MINT_PARSE_FIXED ("denom_pub", &deposit->denom_pub),
        TALER_MINT_PARSE_FIXED ("ubsig", &deposit->ubsig),
        TALER_MINT_PARSE_FIXED ("merchant_pub", &deposit->merchant_pub),
        TALER_MINT_PARSE_FIXED ("H_a", &deposit->h_contract),
        TALER_MINT_PARSE_FIXED ("H_wire", &deposit->h_wire),
        TALER_MINT_PARSE_FIXED ("csig", &deposit->coin_sig),
        TALER_MINT_PARSE_FIXED ("transaction_id", &deposit->transaction_id),
        TALER_MINT_PARSE_END
      };
    res = TALER_MINT_parse_json_data (connection,
                                      wire, /* FIXME: wire or root here? */
                                      spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */

    deposit->purpose.purpose = htonl (purpose);
    deposit->purpose.size = htonl (sizeof (struct Deposit)
                                   - offsetof (struct Deposit, purpose));
    res = verify_and_execute_deposit (connection,
                                      deposit);
    TALER_MINT_release_parsed_data (spec);
  }
  GNUNET_free (deposit);
  return res;
}


/**
 * Handle a "/deposit" request.  Parses the JSON in the post and, if
 * successful, passes the JSON data to
 * #parse_and_handle_deposit_request().
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
  json_t *wire;
  const char *deposit_type;
  int res;
  uint32_t purpose;

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  if (-1 == json_unpack (json,
                         "{s:s, s:o}",
                         "type", &deposit_type,
                         "wire", &wire))
  {
    GNUNET_break_op (0);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error", "Bad format");
  }
  if (0 == strcmp ("DIRECT_DEPOSIT", deposit_type))
    purpose = TALER_SIGNATURE_DEPOSIT;
  else if (0 == strcmp ("INCREMENTAL_DEPOSIT", deposit_type))
    purpose = TALER_SIGNATURE_INCREMENTAL_DEPOSIT;
  else
  {
    GNUNET_break_op (0);
    json_decref (wire);
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error", "Bad format");
  }
  res = parse_and_handle_deposit_request (connection,
                                          json,
                                          purpose,
                                          wire);
  json_decref (wire);
  return res;
}


/* end of taler-mint-httpd_deposit.c */
