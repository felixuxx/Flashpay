/*
  This file is part of TALER
  Copyright (C) 2014-2018 Inria and GNUnet e.V.

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
 * @file taler-auditor-httpd_deposit-confirmation.c
 * @brief Handle /deposit-confirmation requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler-auditor-httpd.h"
#include "taler-auditor-httpd_db.h"
#include "taler-auditor-httpd_deposit-confirmation.h"
#include "taler-auditor-httpd_parsing.h"
#include "taler-auditor-httpd_responses.h"


/**
 * Send confirmation of deposit-confirmation success to client.
 *
 * @param connection connection to the client
 * @return MHD result code
 */
static int
reply_deposit_confirmation_success (struct MHD_Connection *connection)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:s}",
                                       "status", "DEPOSIT_CONFIRMATION_OK");
}


/**
 * Store exchange's signing key information in the database.
 *
 * @param cls a `struct TALER_AUDITORDB_ExchangeSigningKey *`
 * @param connection MHD request context
 * @param session database session and transaction to use
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
store_exchange_signing_key_transaction (void *cls,
                                        struct MHD_Connection *connection,
                                        struct TALER_AUDITORDB_Session *session,
                                        int *mhd_ret)
{
  const struct TALER_AUDITORDB_ExchangeSigningKey *es = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TAH_plugin->insert_exchange_signkey (TAH_plugin->cls,
                                            session,
                                            es);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    TALER_LOG_WARNING ("Failed to store exchange signing key in database\n");
    *mhd_ret = TAH_RESPONSE_reply_internal_db_error (connection,
						     TALER_EC_AUDITOR_EXCHANGE_STORE_DB_ERROR);
  }
  return qs;
}


/**
 * Execute database transaction for /deposit-confirmation.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct DepositConfirmation *`
 * @param connection MHD request context
 * @param session database session and transaction to use -- FIXME: needed?
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
deposit_confirmation_transaction (void *cls,
                                  struct MHD_Connection *connection,
                                  struct TALER_AUDITORDB_Session *session,
                                  int *mhd_ret)
{
  const struct TALER_AUDITORDB_DepositConfirmation *dc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TAH_plugin->insert_deposit_confirmation (TAH_plugin->cls,
                                                session,
                                                dc);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    TALER_LOG_WARNING ("Failed to store /deposit-confirmation information in database\n");
    *mhd_ret = TAH_RESPONSE_reply_internal_db_error (connection,
						     TALER_EC_DEPOSIT_CONFIRMATION_STORE_DB_ERROR);
  }
  return qs;
}


/**
 * We have parsed the JSON information about the deposit, do some
 * basic sanity checks (especially that the signature on the coin is
 * valid, and that this type of coin exists) and then execute the
 * deposit.
 *
 * @param connection the MHD connection to handle
 * @param dc information about the deposit confirmation
 * @param es information about the exchange's signing key
 * @return MHD result code
 */
static int
verify_and_execute_deposit_confirmation (struct MHD_Connection *connection,
                                         const struct TALER_AUDITORDB_DepositConfirmation *dc,
                                         const struct TALER_AUDITORDB_ExchangeSigningKey *es)
{
  struct TALER_ExchangeSigningKeyValidityPS skv;
  struct TALER_DepositConfirmationPS dcs;
  int mhd_ret;

  /* check exchange signing key signature */
  skv.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  skv.purpose.size = htonl (sizeof (struct TALER_ExchangeSigningKeyValidityPS));
  skv.master_public_key = es->master_public_key;
  skv.start = GNUNET_TIME_absolute_hton (es->ep_start);
  skv.expire = GNUNET_TIME_absolute_hton (es->ep_expire);
  skv.end = GNUNET_TIME_absolute_hton (es->ep_end);
  skv.signkey_pub = es->exchange_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                  &skv.purpose,
                                  &es->master_sig.eddsa_signature,
                                  &es->master_public_key.eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on exchange signing key\n");
    return TAH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID,
                                                 "master_sig");
  }

  /* execute transaction */
  if (GNUNET_OK !=
      TAH_DB_run_transaction (connection,
                              "persist exchange signing key",
			      &mhd_ret,
			      &store_exchange_signing_key_transaction,
			      (void *) es))
    return mhd_ret;

  /* check deposit confirmation signature */
  dcs.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT);
  dcs.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS));
  dcs.h_contract_terms = dc->h_contract_terms;
  dcs.h_wire = dc->h_wire;
  dcs.timestamp = GNUNET_TIME_absolute_hton (dc->timestamp);
  dcs.refund_deadline = GNUNET_TIME_absolute_hton (dc->refund_deadline);
  TALER_amount_hton (&dcs.amount_without_fee,
                     &dc->amount_without_fee);
  dcs.coin_pub = dc->coin_pub;
  dcs.merchant = dc->merchant;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT,
                                  &dcs.purpose,
                                  &dc->exchange_sig.eddsa_signature,
                                  &dc->exchange_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on /deposit-confirmation request\n");
    return TAH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_DEPOSIT_CONFIRMATION_SIGNATURE_INVALID,
                                                 "exchange_sig");
  }

  /* execute transaction */
  if (GNUNET_OK !=
      TAH_DB_run_transaction (connection,
                              "store deposit confirmation",
			      &mhd_ret,
			      &deposit_confirmation_transaction,
			      (void *) dc))
    return mhd_ret;
  return reply_deposit_confirmation_success (connection);
}


/**
 * Handle a "/deposit-confirmation" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #verify_and_execute_deposit_confirmation()
 * to further check the details of the operation specified.  If
 * everything checks out, this will ultimately lead to the "/deposit-confirmation"
 * being stored in the database.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TAH_DEPOSIT_CONFIRMATION_handler (struct TAH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct TALER_AUDITORDB_DepositConfirmation dc;
  struct TALER_AUDITORDB_ExchangeSigningKey es;

  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms", &dc.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("h_wire", &dc.h_wire),
    GNUNET_JSON_spec_absolute_time ("timestamp", &dc.timestamp),
    GNUNET_JSON_spec_absolute_time ("refund_deadline", &dc.refund_deadline),
    TALER_JSON_spec_amount ("amount_without_fee", &dc.amount_without_fee),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &dc.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub", &dc.merchant),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",  &dc.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",  &dc.exchange_pub),
    GNUNET_JSON_spec_fixed_auto ("master_pub",  &es.master_public_key),
    GNUNET_JSON_spec_absolute_time ("ep_start",  &es.ep_start),
    GNUNET_JSON_spec_absolute_time ("ep_expire",  &es.ep_expire),
    GNUNET_JSON_spec_absolute_time ("ep_end",  &es.ep_end),
    GNUNET_JSON_spec_fixed_auto ("master_sig",  &es.master_sig),
    GNUNET_JSON_spec_end ()
  };

  res = TAH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) ||
       (NULL == json) )
    return MHD_YES;
  res = TAH_PARSE_json_data (connection,
                             json,
                             spec);
  json_decref (json);
  es.exchange_pub = dc.exchange_pub; /* used twice! */
  dc.master_public_key = es.master_public_key;

  if (GNUNET_SYSERR == res)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == res)
    return MHD_YES; /* failure */

  res = verify_and_execute_deposit_confirmation (connection,
                                                 &dc,
                                                 &es);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-auditor-httpd_deposit-confirmation.c */
