/*
  This file is part of TALER
  Copyright (C) 2014,2015 GNUnet e.V.

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
#include "taler-mint-httpd_withdraw.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_responses.h"
#include "taler-mint-httpd_keystate.h"


/**
 * Handle a "/withdraw/status" request.  Parses the
 * given "reserve_pub" argument (which should contain the
 * EdDSA public key of a reserve) and then respond with the
 * status of the reserve.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_WITHDRAW_handler_withdraw_status (struct TMH_RequestHandler *rh,
                                    struct MHD_Connection *connection,
                                    void **connection_cls,
                                    const char *upload_data,
                                    size_t *upload_data_size)
{
  struct TALER_ReservePublicKeyP reserve_pub;
  int res;

  res = TMH_PARSE_mhd_request_arg_data (connection,
                                         "reserve_pub",
                                         &reserve_pub,
                                         sizeof (struct TALER_ReservePublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* parse error */
  return TMH_DB_execute_withdraw_status (connection,
                                                &reserve_pub);
}


/**
 * Handle a "/withdraw/sign" request.  Parses the "reserve_pub"
 * EdDSA key of the reserve and the requested "denom_pub" which
 * specifies the key/value of the coin to be withdrawn, and checks
 * that the signature "reserve_sig" makes this a valid withdrawl
 * request from the specified reserve.  If so, the envelope
 * with the blinded coin "coin_ev" is passed down to execute the
 * withdrawl operation.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_WITHDRAW_handler_withdraw_sign (struct TMH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  struct TALER_WithdrawRequestPS wsrd;
  int res;
  struct TALER_DenominationPublicKey denomination_pub;
  char *denomination_pub_data;
  size_t denomination_pub_data_size;
  char *blinded_msg;
  size_t blinded_msg_len;
  struct TALER_ReserveSignatureP signature;

  res = TMH_PARSE_mhd_request_arg_data (connection,
                                         "reserve_pub",
                                         &wsrd.reserve_pub,
                                         sizeof (struct TALER_ReservePublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */
  res = TMH_PARSE_mhd_request_arg_data (connection,
                                         "reserve_sig",
                                         &signature,
                                         sizeof (struct TALER_ReserveSignatureP));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */
  res = TMH_PARSE_mhd_request_var_arg_data (connection,
                                             "denom_pub",
                                             (void **) &denomination_pub_data,
                                             &denomination_pub_data_size);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* invalid request */
  res = TMH_PARSE_mhd_request_var_arg_data (connection,
                                             "coin_ev",
                                             (void **) &blinded_msg,
                                             &blinded_msg_len);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_free (denomination_pub_data);
    return MHD_NO; /* internal error */
  }
  if (GNUNET_NO == res)
  {
    GNUNET_free (denomination_pub_data);
    return MHD_YES; /* invalid request */
  }

  /* verify signature! */
  wsrd.purpose.size = htonl (sizeof (struct TALER_WithdrawRequestPS));
  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_RESERVE_WITHDRAW_REQUEST);
  GNUNET_CRYPTO_hash (denomination_pub_data,
                      denomination_pub_data_size,
                      &wsrd.h_denomination_pub);
  GNUNET_CRYPTO_hash (blinded_msg,
                      blinded_msg_len,
                      &wsrd.h_coin_envelope);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_RESERVE_WITHDRAW_REQUEST,
                                  &wsrd.purpose,
                                  &signature.eddsa_signature,
                                  &wsrd.reserve_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Client supplied invalid signature for /withdraw/sign request\n");
    GNUNET_free (denomination_pub_data);
    GNUNET_free (blinded_msg);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                         "reserve_sig");
  }
  denomination_pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_decode (denomination_pub_data,
                                           denomination_pub_data_size);
  GNUNET_free (denomination_pub_data);
  if (NULL == denomination_pub.rsa_public_key)
  {
    TALER_LOG_WARNING ("Client supplied ill-formed denomination public key for /withdraw/sign request\n");
    GNUNET_free (blinded_msg);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                         "denom_pub");
  }
  res = TMH_DB_execute_withdraw_sign (connection,
                                             &wsrd.reserve_pub,
                                             &denomination_pub,
                                             blinded_msg,
                                             blinded_msg_len,
                                             &signature);
  GNUNET_free (blinded_msg);
  GNUNET_CRYPTO_rsa_public_key_free (denomination_pub.rsa_public_key);
  return res;
}

/* end of taler-mint-httpd_withdraw.c */
