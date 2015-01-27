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
 *
 * TODO:
 * - support variable-size RSA keys
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
#include "taler_json_lib.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_db.h"
#include "taler-mint-httpd_mhd.h"
#include "taler-mint-httpd_withdraw.h"
#include "taler-mint-httpd_responses.h"


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
  int res;

  res = TALER_MINT_mhd_request_arg_data (connection,
                                         "reserve_pub",
                                         &reserve_pub,
                                         sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* parse error */
  return TALER_MINT_db_execute_withdraw_status (connection,
                                                &reserve_pub);
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
  struct GNUNET_CRYPTO_rsa_PublicKey *denomination_pub;
  char *denomination_pub_data;
  size_t denomination_pub_data_size;
  char *blinded_msg;
  size_t blinded_msg_len;
  struct GNUNET_CRYPTO_EddsaSignature signature;

  res = TALER_MINT_mhd_request_arg_data (connection,
                                         "reserve_pub",
                                         &wsrd.reserve_pub,
                                         sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */

  /* FIXME: handle variable-size signing keys! */
  res = TALER_MINT_mhd_request_var_arg_data (connection,
                                             "denom_pub",
                                             (void **) &denomination_pub_data,
                                             &denomination_pub_data_size);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */
  res = TALER_MINT_mhd_request_var_arg_data (connection,
                                             "coin_ev",
                                             (void **) &blinded_msg,
                                             &blinded_msg_len);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */
  res = TALER_MINT_mhd_request_arg_data (connection,
                                         "reserve_sig",
                                         &signature,
                                         sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */

  /* verify signature! */
  wsrd.purpose.size = htonl (sizeof (struct TALER_WithdrawRequest));
  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_WITHDRAW);
  GNUNET_CRYPTO_hash (denomination_pub_data,
                      denomination_pub_data_size,
                      &wsrd.h_denomination_pub);
  GNUNET_CRYPTO_hash (blinded_msg,
                      blinded_msg_len,
                      &wsrd.h_coin_envelope);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WITHDRAW,
                                  &wsrd.purpose,
                                  &signature,
                                  &wsrd.reserve_pub))
  {
    return 42; // FIXME: generate error reply
  }
  denomination_pub = GNUNET_CRYPTO_rsa_public_key_decode (denomination_pub_data,
                                                          denomination_pub_data_size);
  if (NULL == denomination_pub)
  {
    GNUNET_free (denomination_pub_data);
    GNUNET_free (blinded_msg);
    return 42; // FIXME: generate error reply
  }
  res = TALER_MINT_db_execute_withdraw_sign (connection,
                                             &wsrd.reserve_pub,
                                             denomination_pub,
                                             blinded_msg,
                                             blinded_msg_len,
                                             &signature);
  GNUNET_free (denomination_pub_data);
  GNUNET_free (blinded_msg);
  GNUNET_CRYPTO_rsa_public_key_free (denomination_pub);
  return res;
}

/* end of taler-mint-httpd_withdraw.c */
