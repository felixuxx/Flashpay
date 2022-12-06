/*
  This file is part of TALER
  Copyright (C) 2021, 2022 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-wallet.c
 * @brief Handle request for wallet for KYC check.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the request.
 */
struct KycRequestContext
{
  /**
   * Public key of the reserve/wallet this is about.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * KYC status, with row with the legitimization requirement.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Balance threshold crossed by the wallet.
   */
  struct TALER_Amount balance;

  /**
   * Name of the required check.
   */
  const char *required;

};


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Returns the wallet balance.
 *
 * @param cls closure, a `struct KycRequestContext`
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 */
static void
balance_iterator (void *cls,
                  struct GNUNET_TIME_Absolute limit,
                  TALER_EXCHANGEDB_KycAmountCallback cb,
                  void *cb_cls)
{
  struct KycRequestContext *krc = cls;

  (void) limit;
  cb (cb_cls,
      &krc->balance,
      GNUNET_TIME_absolute_get ());
}


/**
 * Function implementing database transaction to check wallet's KYC status.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct KycRequestContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
wallet_kyc_check (void *cls,
                  struct MHD_Connection *connection,
                  MHD_RESULT *mhd_ret)
{
  struct KycRequestContext *krc = cls;
  enum GNUNET_DB_QueryStatus qs;

  krc->required = TALER_KYCLOGIC_kyc_test_required (
    TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE,
    &krc->h_payto,
    TEH_plugin->select_satisfied_kyc_processes,
    TEH_plugin->cls,
    &balance_iterator,
    krc);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC check required at %s is `%s'\n",
              TALER_amount2s (&krc->balance),
              krc->required);
  if (NULL == krc->required)
  {
    krc->kyc.ok = true;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  krc->kyc.ok = false;
  qs = TEH_plugin->insert_kyc_requirement_for_account (TEH_plugin->cls,
                                                       krc->required,
                                                       &krc->h_payto,
                                                       &krc->kyc.requirement_row);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "insert_kyc_requirement_for_account");
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC requirement inserted for wallet %s (%llu, %d)\n",
              TALER_B2S (&krc->h_payto),
              (unsigned long long) krc->kyc.requirement_row,
              qs);
  return qs;
}


MHD_RESULT
TEH_handler_kyc_wallet (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[])
{
  struct TALER_ReserveSignatureP reserve_sig;
  struct KycRequestContext krc;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &reserve_pub),
    TALER_JSON_spec_amount ("balance",
                            TEH_currency,
                            &krc.balance),
    GNUNET_JSON_spec_end ()
  };
  MHD_RESULT res;
  enum GNUNET_GenericReturnValue ret;

  (void) args;
  ret = TALER_MHD_parse_json_data (rc->connection,
                                   root,
                                   spec);
  if (GNUNET_SYSERR == ret)
    return MHD_NO;   /* hard failure */
  if (GNUNET_NO == ret)
    return MHD_YES;   /* failure */

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_account_setup_verify (&reserve_pub,
                                         &krc.balance,
                                         &reserve_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_KYC_WALLET_SIGNATURE_INVALID,
      NULL);
  }
  {
    char *payto_uri;

    payto_uri = TALER_reserve_make_payto (TEH_base_url,
                                          &reserve_pub);
    TALER_payto_hash (payto_uri,
                      &krc.h_payto);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "h_payto of wallet %s is %s\n",
                payto_uri,
                TALER_B2S (&krc.h_payto));
    GNUNET_free (payto_uri);
  }
  ret = TEH_DB_run_transaction (rc->connection,
                                "check wallet kyc",
                                TEH_MT_REQUEST_OTHER,
                                &res,
                                &wallet_kyc_check,
                                &krc);
  if (GNUNET_SYSERR == ret)
    return res;
  if (NULL == krc.required)
  {
    /* KYC not required or already satisfied */
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);
  }
  return TEH_RESPONSE_reply_kyc_required (rc->connection,
                                          &krc.h_payto,
                                          &krc.kyc);
}


/* end of taler-exchange-httpd_kyc-wallet.c */
