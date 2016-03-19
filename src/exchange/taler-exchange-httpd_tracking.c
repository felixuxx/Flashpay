/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * @file taler-exchange-httpd_tracking.c
 * @brief Handle wire transfer tracking-related requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_signatures.h"
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_tracking.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Handle a "/wire/deposits" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_TRACKING_handler_wire_deposits (struct TMH_RequestHandler *rh,
                                    struct MHD_Connection *connection,
                                    void **connection_cls,
                                    const char *upload_data,
                                    size_t *upload_data_size)
{
  struct TALER_WireTransferIdentifierRawP wtid;
  int res;

  res = TMH_PARSE_mhd_request_arg_data (connection,
                                        "wtid",
                                        &wtid,
                                        sizeof (struct TALER_WireTransferIdentifierRawP));
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* internal error */
  if (GNUNET_NO == res)
    return MHD_YES; /* parse error */
  return TMH_DB_execute_wire_deposits (connection,
                                       &wtid);
}


/**
 * Check the merchant signature, and if it is valid,
 * return the wire transfer identifier.
 *
 * @param connection the MHD connection to handle
 * @param tps signed request to execute
 * @param merchant_pub public key from the merchant
 * @param merchant_sig signature from the merchant (to be checked)
 * @param transaction_id transaction ID (in host byte order)
 * @return MHD result code
 */
static int
check_and_handle_deposit_wtid_request (struct MHD_Connection *connection,
				       const struct TALER_DepositTrackPS *tps,
				       struct TALER_MerchantPublicKeyP *merchant_pub,
				       struct TALER_MerchantSignatureP *merchant_sig,
				       uint64_t transaction_id)
{
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_DEPOSIT_WTID,
				  &tps->purpose,
				  &merchant_sig->eddsa_sig,
				  &merchant_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return TMH_RESPONSE_reply_signature_invalid (connection,
						 "merchant_sig");
  }
  return TMH_DB_execute_deposit_wtid (connection,
				      &tps->h_contract,
				      &tps->h_wire,
				      &tps->coin_pub,
				      merchant_pub,
				      transaction_id);
}


/**
 * Handle a "/deposit/wtid" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TMH_TRACKING_handler_deposit_wtid (struct TMH_RequestHandler *rh,
                                   struct MHD_Connection *connection,
                                   void **connection_cls,
                                   const char *upload_data,
                                   size_t *upload_data_size)
{
  int res;
  json_t *json;
  struct TALER_DepositTrackPS tps;
  uint64_t transaction_id;
  struct TALER_MerchantSignatureP merchant_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("H_wire", &tps.h_wire),
    GNUNET_JSON_spec_fixed_auto ("H_contract", &tps.h_contract),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &tps.coin_pub),
    GNUNET_JSON_spec_uint64 ("transaction_id", &transaction_id),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub", &tps.merchant),
    GNUNET_JSON_spec_fixed_auto ("merchant_sig", &merchant_sig),
    GNUNET_JSON_spec_end ()
  };

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TMH_PARSE_json_data (connection,
                             json,
                             spec);
  if (GNUNET_OK != res)
  {
    json_decref (json);
    return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  }
  tps.purpose.size = htonl (sizeof (struct TALER_DepositTrackPS));
  tps.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_DEPOSIT_WTID);
  tps.transaction_id = GNUNET_htonll (transaction_id);
  res = check_and_handle_deposit_wtid_request (connection,
					       &tps,
					       &tps.merchant,
					       &merchant_sig,
					       transaction_id);
  GNUNET_JSON_parse_free (spec);
  json_decref (json);
  return res;
}


/* end of taler-exchange-httpd_tracking.c */
