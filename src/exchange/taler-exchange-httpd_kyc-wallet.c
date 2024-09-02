/*
  This file is part of TALER
  Copyright (C) 2021, 2022, 2024 Taler Systems SA

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
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_withdraw.h"


/**
 * Context for the request.
 */
struct KycRequestContext
{

  /**
   * Kept in a DLL.
   */
  struct KycRequestContext *next;

  /**
   * Kept in a DLL.
   */
  struct KycRequestContext *prev;

  /**
   * Handle for legitimization check.
   */
  struct TEH_LegitimizationCheckHandle *lch;

  /**
   * Payto URI of the reserve.
   */
  char *payto_uri;

  /**
   * Request context.
   */
  struct TEH_RequestContext *rc;

  /**
   * Response to return. Note that the response must
   * be queued or destroyed by the callee.  NULL
   * if the legitimization check was successful and the handler should return
   * a handler-specific result.
   */
  struct MHD_Response *response;

  /**
   * Public key of the reserve/wallet this is about.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * The wallet's public key
   */
  union TALER_AccountPublicKeyP wallet_pub;

  /**
   * Balance threshold crossed by the wallet.
   */
  struct TALER_Amount balance;

  /**
   * KYC status, with row with the legitimization requirement.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Smallest amount (over any timeframe) that may
   * require additional KYC checks (if @a kyc.ok).
   */
  struct TALER_Amount next_threshold;

  /**
   * When do the current KYC rules possibly expire.
   * Only valid if @a kyc.ok.
   */
  struct GNUNET_TIME_Timestamp expiration_date;

  /**
   * HTTP status code for @a response, or 0
   */
  unsigned int http_status;

};


/**
 * Kept in a DLL.
 */
static struct KycRequestContext *krc_head;

/**
 * Kept in a DLL.
 */
static struct KycRequestContext *krc_tail;


void
TEH_kyc_wallet_cleanup ()
{
  struct KycRequestContext *krc;

  while (NULL != (krc = krc_head))
  {
    GNUNET_CONTAINER_DLL_remove (krc_head,
                                 krc_tail,
                                 krc);
    MHD_resume_connection (krc->rc->connection);
  }
}


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
static enum GNUNET_DB_QueryStatus
balance_iterator (void *cls,
                  struct GNUNET_TIME_Absolute limit,
                  TALER_EXCHANGEDB_KycAmountCallback cb,
                  void *cb_cls)
{
  struct KycRequestContext *krc = cls;
  enum GNUNET_GenericReturnValue ret;

  (void) limit;
  ret = cb (cb_cls,
            &krc->balance,
            GNUNET_TIME_absolute_get ());
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls must be a `struct KycRequestContext *`
 * @param lcr legitimization check result
 */
static void
legi_result_cb (
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr)
{
  struct KycRequestContext *krc = cls;

  krc->lch = NULL;
  krc->http_status = lcr->http_status;
  krc->response = lcr->response;
  krc->kyc = lcr->kyc;
  krc->next_threshold = lcr->next_threshold;
  krc->expiration_date = lcr->expiration_date;
  GNUNET_CONTAINER_DLL_remove (krc_head,
                               krc_tail,
                               krc);
  MHD_resume_connection (krc->rc->connection);
  TALER_MHD_daemon_trigger ();
}


/**
 * Function to clean up our rh_ctx in @a rc
 *
 * @param[in,out] rc context to clean up
 */
static void
krc_cleaner (struct TEH_RequestContext *rc)
{
  struct KycRequestContext *krc = rc->rh_ctx;

  if (NULL != krc->lch)
  {
    TEH_legitimization_check_cancel (krc->lch);
    krc->lch = NULL;
  }
  GNUNET_free (krc->payto_uri);
  GNUNET_free (krc);
}


MHD_RESULT
TEH_handler_kyc_wallet (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[])
{
  struct KycRequestContext *krc = rc->rh_ctx;

  if (NULL == krc)
  {
    krc = GNUNET_new (struct KycRequestContext);
    krc->rc = rc;
    rc->rh_ctx = krc;
    rc->rh_cleaner = &krc_cleaner;
    {
      struct TALER_ReserveSignatureP reserve_sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &reserve_sig),
        GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                     &krc->wallet_pub.reserve_pub),
        TALER_JSON_spec_amount ("balance",
                                TEH_currency,
                                &krc->balance),
        GNUNET_JSON_spec_end ()
      };
      enum GNUNET_GenericReturnValue ret;

      (void) args;
      ret = TALER_MHD_parse_json_data (rc->connection,
                                       root,
                                       spec);
      if (GNUNET_SYSERR == ret)
        return MHD_NO; /* hard failure */
      if (GNUNET_NO == ret)
        return MHD_YES; /* failure */

      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
      if (GNUNET_OK !=
          TALER_wallet_account_setup_verify (
            &krc->wallet_pub.reserve_pub,
            &krc->balance,
            &reserve_sig))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_FORBIDDEN,
          TALER_EC_EXCHANGE_KYC_WALLET_SIGNATURE_INVALID,
          NULL);
      }
    }
    krc->payto_uri
      = TALER_reserve_make_payto (TEH_base_url,
                                  &krc->wallet_pub.reserve_pub);
    TALER_payto_hash (krc->payto_uri,
                      &krc->h_payto);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "h_payto of wallet %s is %s\n",
                krc->payto_uri,
                TALER_B2S (&krc->h_payto));
    krc->lch = TEH_legitimization_check (
      &rc->async_scope_id,
      TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE,
      krc->payto_uri,
      &krc->h_payto,
      &krc->wallet_pub,
      &balance_iterator,
      krc,
      &legi_result_cb,
      krc);
    GNUNET_assert (NULL != krc->lch);
    MHD_suspend_connection (rc->connection);
    GNUNET_CONTAINER_DLL_insert (krc_head,
                                 krc_tail,
                                 krc);
    return MHD_YES;
  }
  if (NULL != krc->response)
    return MHD_queue_response (rc->connection,
                               krc->http_status,
                               krc->response);
  if (krc->kyc.ok)
  {
    bool have_ts
      = TALER_amount_is_valid (&krc->next_threshold);


    /* KYC not required or already satisfied */
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_timestamp ("expiration_time",
                                  krc->expiration_date),
      GNUNET_JSON_pack_allow_null (
        TALER_JSON_pack_amount ("next_threshold",
                                have_ts
                              ? &krc->next_threshold
                              : NULL)));
  }
  return TEH_RESPONSE_reply_kyc_required (rc->connection,
                                          &krc->h_payto,
                                          &krc->kyc,
                                          false);
}


/* end of taler-exchange-httpd_kyc-wallet.c */
