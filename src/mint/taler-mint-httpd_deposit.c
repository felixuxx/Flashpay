/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * - missing 'wire' format check (well-formed SEPA-details)
 * - ugliy if-construction for deposit type
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_mintdb_plugin.h"
#include "taler_signatures.h"
#include "taler_util.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_db.h"
#include "taler-mint-httpd_deposit.h"
#include "taler-mint-httpd_responses.h"
#include "taler-mint-httpd_keystate.h"


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
                            const struct TALER_MINTDB_Deposit *deposit)
{
  struct TMH_KS_StateHandle *key_state;
  struct TALER_DepositRequestPS dr;
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki;
  struct TALER_Amount fee_deposit;

  dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
  dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
  dr.h_contract = deposit->h_contract;
  dr.h_wire = deposit->h_wire;
  dr.timestamp = GNUNET_TIME_absolute_hton (deposit->timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (deposit->refund_deadline);
  dr.transaction_id = GNUNET_htonll (deposit->transaction_id);
  TALER_amount_hton (&dr.amount_with_fee,
                     &deposit->amount_with_fee);
  TALER_amount_hton (&dr.deposit_fee,
                     &deposit->deposit_fee);
  dr.merchant = deposit->merchant_pub;
  dr.coin_pub = deposit->coin.coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr.purpose,
                                  &deposit->csig.ecdsa_signature,
                                  &deposit->coin.coin_pub.ecdsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on /deposit request\n");
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                         "csig");
  }
  /* check denomination exists and is valid */
  key_state = TMH_KS_acquire ();
  dki = TMH_KS_denomination_key_lookup (key_state,
                                  &deposit->coin.denom_pub);
  if (NULL == dki)
  {
    TMH_KS_release (key_state);
    TALER_LOG_WARNING ("Unknown denomination key in /deposit request\n");
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                         "denom_pub");
  }
  /* check coin signature */
  if (GNUNET_YES !=
      TALER_test_coin_valid (&deposit->coin))
  {
    TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
    TMH_KS_release (key_state);
    return TMH_RESPONSE_reply_coin_invalid (connection);
  }
  TALER_amount_ntoh (&fee_deposit,
                     &dki->issue.fee_deposit);
  if (TALER_amount_cmp (&fee_deposit,
                        &deposit->amount_with_fee) < 0)
  {
    TMH_KS_release (key_state);
    return (MHD_YES ==
            TMH_RESPONSE_reply_external_error (connection,
                                             "deposited amount smaller than depositing fee"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  TMH_KS_release (key_state);

  return TMH_DB_execute_deposit (connection,
                                        deposit);
}


/**
 * Handle a "/deposit" request.  This function parses the
 * JSON information and then calls #verify_and_execute_deposit()
 * to verify the signatures and execute the deposit.
 *
 * @param connection the MHD connection to handle
 * @param root root of the posted JSON
 * @param amount how much should be deposited
 * @param wire json describing the wire details (?)
 * @return MHD result code
  */
static int
parse_and_handle_deposit_request (struct MHD_Connection *connection,
                                  const json_t *root,
                                  const struct TALER_Amount *amount,
                                  json_t *wire)
{
  int res;
  struct TALER_MINTDB_Deposit deposit;
  char *wire_enc;
  size_t len;
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki;
  struct TMH_KS_StateHandle *ks;
  struct TMH_PARSE_FieldSpecification spec[] = {
    TMH_PARSE_MEMBER_DENOMINATION_PUBLIC_KEY ("denom_pub", &deposit.coin.denom_pub),
    TMH_PARSE_MEMBER_DENOMINATION_SIGNATURE ("ubsig", &deposit.coin.denom_sig),
    TMH_PARSE_MEMBER_FIXED ("coin_pub", &deposit.coin.coin_pub),
    TMH_PARSE_MEMBER_FIXED ("merchant_pub", &deposit.merchant_pub),
    TMH_PARSE_MEMBER_FIXED ("H_a", &deposit.h_contract),
    TMH_PARSE_MEMBER_FIXED ("H_wire", &deposit.h_wire),
    TMH_PARSE_MEMBER_FIXED ("csig",  &deposit.csig),
    TMH_PARSE_MEMBER_FIXED ("transaction_id", &deposit.transaction_id),
    TMH_PARSE_MEMBER_TIME_ABS ("timestamp", &deposit.timestamp),
    TMH_PARSE_MEMBER_TIME_ABS ("refund_deadline", &deposit.refund_deadline),
    TMH_PARSE_MEMBER_END
  };

  memset (&deposit, 0, sizeof (deposit));
  res = TMH_PARSE_json_data (connection,
                             root,
                             spec);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == res)
    return MHD_YES; /* failure */
  if (GNUNET_YES !=
      TALER_json_validate_wireformat (TMH_expected_wire_format,
				      wire))
  {
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                           "wire");
  }
  if (NULL == (wire_enc = json_dumps (wire, JSON_COMPACT | JSON_SORT_KEYS)))
  {
    TALER_LOG_WARNING ("Failed to parse JSON wire format specification for /deposit request\n");
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                           "wire");
  }
  len = strlen (wire_enc) + 1;
  GNUNET_CRYPTO_hash (wire_enc,
                      len,
                      &deposit.h_wire);
  GNUNET_free (wire_enc);
  ks = TMH_KS_acquire ();
  dki = TMH_KS_denomination_key_lookup (ks,
                                        &deposit.coin.denom_pub);
  if (NULL == dki)
  {
    TMH_KS_release (ks);
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&deposit.deposit_fee,
                     &dki->issue.fee_deposit);
  TMH_KS_release (ks);
  deposit.wire = wire;
  deposit.amount_with_fee = *amount;
  if (-1 == TALER_amount_cmp (&deposit.amount_with_fee,
                              &deposit.deposit_fee))
  {
    /* Total amount smaller than fee, invalid */
    TMH_PARSE_release_data (spec);
    return TMH_RESPONSE_reply_arg_invalid (connection,
                                           "f");
  }
  res = verify_and_execute_deposit (connection,
                                    &deposit);
  TMH_PARSE_release_data (spec);
  return res;
}


/**
 * Handle a "/deposit" request.  Parses the JSON in the post to find
 * the "type" (either DIRECT_DEPOSIT or INCREMENTAL_DEPOSIT), and, if
 * successful, passes the JSON data to
 * #parse_and_handle_deposit_request() to further check the details
 * of the operation specified in the "wire" field of the JSON data.
 * If everything checks out, this will ultimately lead to the
 * "/deposit" being executed, or rejected.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TMH_DEPOSIT_handler_deposit (struct TMH_RequestHandler *rh,
                             struct MHD_Connection *connection,
                             void **connection_cls,
                             const char *upload_data,
                             size_t *upload_data_size)
{
  json_t *json;
  json_t *wire;
  int res;
  struct TALER_Amount amount;
  json_t *f;

  res = TMH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  if (-1 == json_unpack (json,
                         "{s:s, s:o, f:o}",
                         "wire", &wire,
                         "f", &f))
  {
    GNUNET_break_op (0);
    json_decref (json);
    return TMH_RESPONSE_reply_json_pack (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         "{s:s}",
                                         "error", "Bad format");
  }
  res = TMH_PARSE_amount_json (connection,
                               f,
                               &amount);
  json_decref (f);
  if (GNUNET_SYSERR == res)
  {
    json_decref (wire);
    json_decref (json);
    return MHD_NO;
  }
  if (GNUNET_NO == res)
  {
    json_decref (wire);
    json_decref (json);
    return MHD_YES;
  }
  res = parse_and_handle_deposit_request (connection,
                                          json,
                                          &amount,
                                          wire);
  json_decref (wire);
  json_decref (json);
  return res;
}


/* end of taler-mint-httpd_deposit.c */
