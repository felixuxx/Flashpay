/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Inria and GNUnet e.V.

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
 * @file taler-exchange-httpd_refund.c
 * @brief Handle /refund requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_refund.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_validation.h"


/**
 * We have parsed the JSON information about the refund, do some basic
 * sanity checks (especially that the signature on the coin is valid)
 * and then execute the refund.  Note that we need the DB to check
 * the fee structure, so this is not done here.
 *
 * @param connection the MHD connection to handle
 * @param refund information about the refund
 * @return MHD result code
 */
static int
verify_and_execute_refund (struct MHD_Connection *connection,
			   const struct TALER_EXCHANGEDB_Refund *refund)
{
  struct TALER_RefundRequestPS rr;

  rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
  rr.purpose.size = htonl (sizeof (struct TALER_RefundRequestPS));
  rr.h_contract = refund->h_contract;
  rr.transaction_id = GNUNET_htonll (refund->transaction_id);
  rr.coin_pub = refund->coin.coin_pub;
  rr.merchant = refund->merchant_pub;
  rr.rtransaction_id = GNUNET_htonll (refund->rtransaction_id);
  TALER_amount_hton (&rr.refund_amount,
                     &refund->refund_amount);
  TALER_amount_hton (&rr.refund_fee,
                     &refund->refund_fee);
  if (GNUNET_YES !=
      TALER_amount_cmp_currency (&refund->refund_amount,
                                 &refund->refund_fee) )
  {
    GNUNET_break_op (0);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                           "refund_fee");
  }
  if (-1 == TALER_amount_cmp (&refund->refund_amount,
                              &refund->refund_fee) )
  {
    GNUNET_break_op (0);
    return TMH_RESPONSE_reply_signature_invalid (connection,
                                                 "refund_amount");
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                  &rr.purpose,
                                  &refund->merchant_sig.eddsa_sig,
                                  &refund->merchant_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on /refund request\n");
    return TMH_RESPONSE_reply_signature_invalid (connection,
                                                 "merchant_sig");
  }
  return TMH_DB_execute_refund (connection,
				refund);
}


/**
 * Handle a "/refund" request.  Parses the JSON, and, if successful,
 * passes the JSON data to #parse_and_handle_refund_request() to
 * further check the details of the operation specified.  If
 * everything checks out, this will ultimately lead to the "/refund"
 * being executed, or rejected.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_REFUND_handler_refund (struct TMH_RequestHandler *rh,
			   struct MHD_Connection *connection,
			   void **connection_cls,
			   const char *upload_data,
			   size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct TALER_EXCHANGEDB_Refund refund;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("refund_amount", &refund.refund_amount),
    TALER_JSON_spec_amount ("refund_fee", &refund.refund_fee),
    GNUNET_JSON_spec_fixed_auto ("H_contract", &refund.h_contract),
    GNUNET_JSON_spec_uint64 ("transaction_id", &refund.transaction_id),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &refund.coin.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub", &refund.merchant_pub),
    GNUNET_JSON_spec_uint64 ("rtransaction_id", &refund.rtransaction_id),
    GNUNET_JSON_spec_fixed_auto ("merchant_sig", &refund.merchant_sig),
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
  json_decref (json);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == res)
    return MHD_YES; /* failure */
  res = verify_and_execute_refund (connection,
				   &refund);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_refund.c */
