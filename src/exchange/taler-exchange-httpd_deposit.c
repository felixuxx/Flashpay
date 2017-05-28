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
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_deposit.c
 * @brief Handle /deposit requests; parses the POST and JSON and
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
#include "taler-exchange-httpd_deposit.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_validation.h"


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
			    const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct TALER_DepositRequestPS dr;

  dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
  dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
  dr.h_contract_terms = deposit->h_contract_terms;
  dr.h_wire = deposit->h_wire;
  dr.timestamp = GNUNET_TIME_absolute_hton (deposit->timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (deposit->refund_deadline);
  TALER_amount_hton (&dr.amount_with_fee,
                     &deposit->amount_with_fee);
  TALER_amount_hton (&dr.deposit_fee,
                     &deposit->deposit_fee);
  dr.merchant = deposit->merchant_pub;
  dr.coin_pub = deposit->coin.coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr.purpose,
                                  &deposit->csig.eddsa_signature,
                                  &deposit->coin.coin_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on /deposit request\n");
    return TEH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_DEPOSIT_COIN_SIGNATURE_INVALID,
                                                 "coin_sig");
  }

  return TEH_DB_execute_deposit (connection,
                                 deposit);
}


/**
 * Handle a "/deposit" request.  Parses the JSON, and, if successful,
 * passes the JSON data to #verify_and_execute_deposit() to further
 * check the details of the operation specified.  If everything checks
 * out, this will ultimately lead to the "/deposit" being executed, or
 * rejected.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_DEPOSIT_handler_deposit (struct TEH_RequestHandler *rh,
                             struct MHD_Connection *connection,
                             void **connection_cls,
                             const char *upload_data,
                             size_t *upload_data_size)
{
  json_t *json;
  int res;
  json_t *wire;
  char *emsg;
  enum TALER_ErrorCode ec;
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TEH_KS_StateHandle *key_state;
  struct GNUNET_HashCode my_h_wire;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("wire", &wire),
    TALER_JSON_spec_amount ("f", &deposit.amount_with_fee),
    TALER_JSON_spec_denomination_public_key ("denom_pub", &deposit.coin.denom_pub),
    TALER_JSON_spec_denomination_signature ("ub_sig", &deposit.coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &deposit.coin.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub", &deposit.merchant_pub),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms", &deposit.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("H_wire", &deposit.h_wire),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",  &deposit.csig),
    GNUNET_JSON_spec_absolute_time ("timestamp", &deposit.timestamp),
    GNUNET_JSON_spec_absolute_time ("refund_deadline", &deposit.refund_deadline),
    GNUNET_JSON_spec_absolute_time ("wire_transfer_deadline", &deposit.wire_deadline),
    GNUNET_JSON_spec_end ()
  };

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  memset (&deposit, 0, sizeof (deposit));
  res = TEH_PARSE_json_data (connection,
                             json,
                             spec);
  json_decref (json);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == res)
    return MHD_YES; /* failure */

  deposit.receiver_wire_account = wire;
  if (deposit.refund_deadline.abs_value_us > deposit.wire_deadline.abs_value_us)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE,
                                           "refund_deadline");
  }

  if (TALER_EC_NONE !=
      (ec = TEH_json_validate_wireformat (wire,
                                          GNUNET_NO,
                                          &emsg)))
  {
    GNUNET_JSON_parse_free (spec);
    res = TEH_RESPONSE_reply_external_error (connection,
                                             ec,
                                             emsg);
    GNUNET_free (emsg);
    return res;
  }
  if (GNUNET_OK !=
      TALER_JSON_hash (wire,
                       &my_h_wire))
  {
    TALER_LOG_WARNING ("Failed to parse JSON wire format specification for /deposit request\n");
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_JSON,
                                           "wire");
  }
  if (0 != memcmp (&deposit.h_wire,
		   &my_h_wire,
		   sizeof (struct GNUNET_HashCode)))
  {
    /* Client hashed contract differently than we did, reject */
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_CONTRACT_HASH_CONFLICT,
                                           "H_wire");
  }

  /* check denomination exists and is valid */
  key_state = TEH_KS_acquire ();
  dki = TEH_KS_denomination_key_lookup (key_state,
                                        &deposit.coin.denom_pub,
					TEH_KS_DKU_DEPOSIT);
  if (NULL == dki)
  {
    /* FIXME: #3887: if DK was revoked, we might want to give a 403 and not a 404! */
    TEH_KS_release (key_state);
    TALER_LOG_WARNING ("Unknown denomination key in /deposit request\n");
    return TEH_RESPONSE_reply_arg_unknown (connection,
					   TALER_EC_DEPOSIT_DENOMINATION_KEY_UNKNOWN,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&deposit.deposit_fee,
                     &dki->issue.properties.fee_deposit);
  /* check coin signature */
  if (GNUNET_YES !=
      TALER_test_coin_valid (&deposit.coin))
  {
    TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
    TEH_KS_release (key_state);
    return TEH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_DEPOSIT_DENOMINATION_SIGNATURE_INVALID,
                                                 "ub_sig");
  }
  TALER_amount_ntoh (&deposit.deposit_fee,
                     &dki->issue.properties.fee_deposit);
  TEH_KS_release (key_state);

  if (0 < TALER_amount_cmp (&deposit.deposit_fee,
                            &deposit.amount_with_fee))
  {
    GNUNET_break_op (0);
    return TEH_RESPONSE_reply_external_error (connection,
					      TALER_EC_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE,
                                              "deposited amount smaller than depositing fee");
  }

  res = verify_and_execute_deposit (connection,
                                    &deposit);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_deposit.c */
