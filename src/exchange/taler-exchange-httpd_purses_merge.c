/*
  This file is part of TALER
  Copyright (C) 2022-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_purses_merge.c
 * @brief Handle /purses/$PID/merge requests; parses the POST and JSON and
 *        verifies the reserve signature before handing things off
 *        to the database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_dbevents.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_purses_merge.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for #merge_transaction.
 */
struct PurseMergeContext
{

  /**
   * Kept in a DLL.
   */
  struct PurseMergeContext *next;

  /**
   * Kept in a DLL.
   */
  struct PurseMergeContext *prev;

  /**
   * Our request.
   */
  struct TEH_RequestContext *rc;

  /**
   * Handle for the legitimization check.
   */
  struct TEH_LegitimizationCheckHandle *lch;

  /**
   * Fees that apply to this operation.
   */
  const struct TALER_WireFeeSet *wf;

  /**
   * Base URL of the exchange provider hosting the reserve.
   */
  char *provider_url;

  /**
   * URI of the account the purse is to be merged into.
   * Must be of the form 'payto://taler-reserve/$EXCHANGE_URL/RESERVE_PUB'.
   */
  const char *payto_uri;

  /**
   * Response to return, if set.
   */
  struct MHD_Response *response;

  /**
   * Public key of the purse we are creating.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Total amount to be put into the purse.
   */
  struct TALER_Amount target_amount;

  /**
   * Current amount in the purse.
   */
  struct TALER_Amount balance;

  /**
   * When should the purse expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * When the client signed the merge.
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * Our current time.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Merge key for the purse.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Signature of the reservce affiming this request.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Signature of the client affiming the merge.
   */
  struct TALER_PurseMergeSignatureP merge_sig;

  /**
   * Public key of the reserve (account), as extracted from @e payto_uri.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Hash of the contract terms of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Hash of the @e payto_uri.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * KYC status of the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * HTTP status to return with @e response, or 0.
   */
  unsigned int http_status;

  /**
   * Minimum age for deposits into this purse.
   */
  uint32_t min_age;

  /**
   * Set to true if this request was suspended.
   */
  bool suspended;
};


/**
 * Kept in a DLL.
 */
static struct PurseMergeContext *pmc_head;

/**
 * Kept in a DLL.
 */
static struct PurseMergeContext *pmc_tail;


void
TEH_purses_merge_cleanup ()
{
  struct PurseMergeContext *pmc;

  while (NULL != (pmc = pmc_head))
  {
    GNUNET_CONTAINER_DLL_remove (pmc_head,
                                 pmc_tail,
                                 pmc);
    MHD_resume_connection (pmc->rc->connection);
  }
}


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls closure
 * @param lcr legitimization check result
 */
static void
legi_result_cb (
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr)
{
  struct PurseMergeContext *pmc = cls;

  pmc->lch = NULL;
  MHD_resume_connection (pmc->rc->connection);
  GNUNET_CONTAINER_DLL_remove (pmc_head,
                               pmc_tail,
                               pmc);
  TALER_MHD_daemon_trigger ();
  if (NULL != lcr->response)
  {
    pmc->response = lcr->response;
    pmc->http_status = lcr->http_status;
    return;
  }
  pmc->kyc = lcr->kyc;
}


/**
 * Send confirmation of purse creation success to client.
 *
 * @param pmc details about the request that succeeded
 * @return MHD result code
 */
static MHD_RESULT
reply_merge_success (const struct PurseMergeContext *pmc)
{
  struct MHD_Connection *connection = pmc->rc->connection;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;
  struct TALER_Amount merge_amount;

  if (0 <
      TALER_amount_cmp (&pmc->balance,
                        &pmc->target_amount))
  {
    GNUNET_break (0);
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_JSON_pack_amount ("balance",
                              &pmc->balance),
      TALER_JSON_pack_amount ("target_amount",
                              &pmc->target_amount));
  }
  if ( (NULL == pmc->provider_url) ||
       (0 == strcmp (pmc->provider_url,
                     TEH_base_url)) )
  {
    /* wad fee is always zero if we stay at our own exchange */
    merge_amount = pmc->target_amount;
  }
  else
  {
#if WAD_NOT_IMPLEMENTED
    /* FIXME: figure out partner, lookup wad fee by partner! #7271 */
    if (0 >
        TALER_amount_subtract (&merge_amount,
                               &pmc->target_amount,
                               &wad_fee))
    {
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_set_zero (TEH_currency,
                                            &merge_amount));
    }
#else
    merge_amount = pmc->target_amount;
#endif
  }
  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_purse_merged_sign (
         &TEH_keys_exchange_sign_,
         pmc->exchange_timestamp,
         pmc->purse_expiration,
         &merge_amount,
         &pmc->purse_pub,
         &pmc->h_contract_terms,
         &pmc->account_pub.reserve_pub,
         (NULL != pmc->provider_url)
         ? pmc->provider_url
         : TEH_base_url,
         &pub,
         &sig)))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("merge_amount",
                            &merge_amount),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                pmc->exchange_timestamp),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls a `struct PurseMergeContext`
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
amount_iterator (void *cls,
                 struct GNUNET_TIME_Absolute limit,
                 TALER_EXCHANGEDB_KycAmountCallback cb,
                 void *cb_cls)
{
  struct PurseMergeContext *pmc = cls;
  enum GNUNET_GenericReturnValue ret;
  enum GNUNET_DB_QueryStatus qs;

  ret = cb (cb_cls,
            &pmc->target_amount,
            GNUNET_TIME_absolute_get ());
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  qs = TEH_plugin->select_merge_amounts_for_kyc_check (
    TEH_plugin->cls,
    &pmc->h_payto,
    limit,
    cb,
    cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this merge and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
  return qs;
}


/**
 * Execute database transaction for /purses/$PID/merge.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST NOT queue
 * a MHD response.  IF it returns an hard error, the transaction logic MUST
 * queue a MHD response and set @a mhd_ret.  IF it returns the soft error
 * code, the function MAY be called again to retry and MUST not queue a MHD
 * response.
 *
 * @param cls a `struct PurseMergeContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
merge_transaction (void *cls,
                   struct MHD_Connection *connection,
                   MHD_RESULT *mhd_ret)
{
  struct PurseMergeContext *pmc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool in_conflict = true;
  bool no_balance = true;
  bool no_partner = true;

  qs = TEH_plugin->do_purse_merge (
    TEH_plugin->cls,
    &pmc->purse_pub,
    &pmc->merge_sig,
    pmc->merge_timestamp,
    &pmc->reserve_sig,
    pmc->provider_url,
    &pmc->account_pub.reserve_pub,
    &no_partner,
    &no_balance,
    &in_conflict);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_INTERNAL_SERVER_ERROR,
                                  TALER_EC_GENERIC_DB_STORE_FAILED,
                                  "purse merge");
    return qs;
  }
  if (no_partner)
  {
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_NOT_FOUND,
                                  TALER_EC_EXCHANGE_MERGE_PURSE_PARTNER_UNKNOWN,
                                  pmc->provider_url);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (no_balance)
  {
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_PAYMENT_REQUIRED,
                                  TALER_EC_EXCHANGE_PURSE_NOT_FULL,
                                  NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (in_conflict)
  {
    struct TALER_PurseMergeSignatureP merge_sig;
    struct GNUNET_TIME_Timestamp merge_timestamp;
    char *partner_url = NULL;
    struct TALER_ReservePublicKeyP reserve_pub;
    bool refunded;

    qs = TEH_plugin->select_purse_merge (TEH_plugin->cls,
                                         &pmc->purse_pub,
                                         &merge_sig,
                                         &merge_timestamp,
                                         &partner_url,
                                         &reserve_pub,
                                         &refunded);
    if (qs <= 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to fetch merge purse information from database\n");
      *mhd_ret =
        TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "select purse merge");
      return qs;
    }
    if (refunded)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Purse was already refunded\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_GONE,
                                             TALER_EC_EXCHANGE_GENERIC_PURSE_EXPIRED,
                                             NULL);
      GNUNET_free (partner_url);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (0 !=
        GNUNET_memcmp (&merge_sig,
                       &pmc->merge_sig))
    {
      *mhd_ret = TALER_MHD_REPLY_JSON_PACK (
        connection,
        MHD_HTTP_CONFLICT,
        GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                    merge_timestamp),
        GNUNET_JSON_pack_data_auto ("merge_sig",
                                    &merge_sig),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_string ("partner_url",
                                   partner_url)),
        GNUNET_JSON_pack_data_auto ("reserve_pub",
                                    &reserve_pub));
      GNUNET_free (partner_url);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* idempotent! */
    *mhd_ret = reply_merge_success (pmc);
    GNUNET_free (partner_url);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  return qs;
}


/**
 * Purse-merge-specific cleanup routine. Function called
 * upon completion of the request that should
 * clean up @a rh_ctx. Can be NULL.
 *
 * @param rc request context to clean up
 */
static void
clean_purse_merge_rc (struct TEH_RequestContext *rc)
{
  struct PurseMergeContext *pmc = rc->rh_ctx;

  if (NULL != pmc->lch)
  {
    TEH_legitimization_check_cancel (pmc->lch);
    pmc->lch = NULL;
  }
  GNUNET_free (pmc->provider_url);
  GNUNET_free (pmc);
}


MHD_RESULT
TEH_handler_purses_merge (
  struct TEH_RequestContext *rc,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *root)
{
  struct PurseMergeContext *pmc = rc->rh_ctx;

  if (NULL == pmc)
  {
    pmc = GNUNET_new (struct PurseMergeContext);
    rc->rh_ctx = pmc;
    rc->rh_cleaner = &clean_purse_merge_rc;
    pmc->rc = rc;
    pmc->purse_pub = *purse_pub;
    pmc->exchange_timestamp
      = GNUNET_TIME_timestamp_get ();

    {
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_payto_uri ("payto_uri",
                                   &pmc->payto_uri),
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &pmc->reserve_sig),
        GNUNET_JSON_spec_fixed_auto ("merge_sig",
                                     &pmc->merge_sig),
        GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                    &pmc->merge_timestamp),
        GNUNET_JSON_spec_end ()
      };
      enum GNUNET_GenericReturnValue res;

      res = TALER_MHD_parse_json_data (rc->connection,
                                       root,
                                       spec);
      if (GNUNET_SYSERR == res)
      {
        GNUNET_break (0);
        return MHD_NO; /* hard failure */
      }
      if (GNUNET_NO == res)
      {
        GNUNET_break_op (0);
        return MHD_YES; /* failure */
      }
    }

    {
      struct TALER_PurseContractSignatureP purse_sig;
      enum GNUNET_DB_QueryStatus qs;

      /* Fetch purse details */
      qs = TEH_plugin->get_purse_request (
        TEH_plugin->cls,
        &pmc->purse_pub,
        &pmc->merge_pub,
        &pmc->purse_expiration,
        &pmc->h_contract_terms,
        &pmc->min_age,
        &pmc->target_amount,
        &pmc->balance,
        &purse_sig);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          "select purse request");
      case GNUNET_DB_STATUS_SOFT_ERROR:
        GNUNET_break (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          "select purse request");
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_NOT_FOUND,
          TALER_EC_EXCHANGE_GENERIC_PURSE_UNKNOWN,
          NULL);
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        /* continued below */
        break;
      }
    }

    /* check signatures */
    if (GNUNET_OK !=
        TALER_wallet_purse_merge_verify (
          pmc->payto_uri,
          pmc->merge_timestamp,
          &pmc->purse_pub,
          &pmc->merge_pub,
          &pmc->merge_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_PURSE_MERGE_INVALID_MERGE_SIGNATURE,
        NULL);
    }

    /* parse 'payto_uri' into pmc->account_pub and provider_url */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Received payto: `%s'\n",
                pmc->payto_uri);
    if ( (0 != strncmp (pmc->payto_uri,
                        "payto://taler-reserve/",
                        strlen ("payto://taler-reserve/"))) &&
         (0 != strncmp (pmc->payto_uri,
                        "payto://taler-reserve-http/",
                        strlen ("payto://taler-reserve+http/"))) )
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "payto_uri");
    }

    {
      bool http;
      const char *host;
      const char *slash;

      http = (0 == strncmp (pmc->payto_uri,
                            "payto://taler-reserve-http/",
                            strlen ("payto://taler-reserve-http/")));
      host = &pmc->payto_uri[http
                            ? strlen ("payto://taler-reserve-http/")
                            : strlen ("payto://taler-reserve/")];
      slash = strchr (host,
                      '/');
      if (NULL == slash)
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_BAD_REQUEST,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "payto_uri");
      }
      GNUNET_asprintf (&pmc->provider_url,
                       "%s://%.*s/",
                       http ? "http" : "https",
                       (int) (slash - host),
                       host);
      slash++;
      if (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (
            slash,
            strlen (slash),
            &pmc->account_pub.reserve_pub,
            sizeof (pmc->account_pub.reserve_pub)))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_BAD_REQUEST,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "payto_uri");
      }
    }
    TALER_payto_hash (pmc->payto_uri,
                      &pmc->h_payto);
    if (0 == strcmp (pmc->provider_url,
                     TEH_base_url))
    {
      /* we use NULL to represent 'self' as the provider */
      GNUNET_free (pmc->provider_url);
    }
    else
    {
      char *method = GNUNET_strdup ("FIXME-WAD #7271");

      /* FIXME-#7271: lookup wire method by pmc.provider_url! */
      pmc->wf = TEH_wire_fees_by_time (pmc->exchange_timestamp,
                                       method);
      if (NULL == pmc->wf)
      {
        MHD_RESULT res;

        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Cannot merge purse: wire fees not configured!\n");
        res = TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_EXCHANGE_GENERIC_WIRE_FEES_MISSING,
          method);
        GNUNET_free (method);
        return res;
      }
      GNUNET_free (method);
    }

    {
      struct TALER_Amount zero_purse_fee;

      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_set_zero (
                       pmc->target_amount.currency,
                       &zero_purse_fee));
      if (GNUNET_OK !=
          TALER_wallet_account_merge_verify (
            pmc->merge_timestamp,
            &pmc->purse_pub,
            pmc->purse_expiration,
            &pmc->h_contract_terms,
            &pmc->target_amount,
            &zero_purse_fee,
            pmc->min_age,
            TALER_WAMF_MODE_MERGE_FULLY_PAID_PURSE,
            &pmc->account_pub.reserve_pub,
            &pmc->reserve_sig))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (
          rc->connection,
          MHD_HTTP_FORBIDDEN,
          TALER_EC_EXCHANGE_PURSE_MERGE_INVALID_RESERVE_SIGNATURE,
          NULL);
      }
    }
    pmc->lch = TEH_legitimization_check (
      &rc->async_scope_id,
      TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE,
      pmc->payto_uri,
      &pmc->h_payto,
      &pmc->account_pub,
      &amount_iterator,
      pmc,
      &legi_result_cb,
      pmc);
    GNUNET_assert (NULL != pmc->lch);
    MHD_suspend_connection (rc->connection);
    GNUNET_CONTAINER_DLL_insert (pmc_head,
                                 pmc_tail,
                                 pmc);
    return MHD_YES;
  }
  if (NULL != pmc->response)
  {
    return MHD_queue_response (rc->connection,
                               pmc->http_status,
                               pmc->response);
  }
  if (! pmc->kyc.ok)
    return TEH_RESPONSE_reply_kyc_required (
      rc->connection,
      &pmc->h_payto,
      &pmc->kyc,
      false);

  /* execute merge transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "execute purse merge",
                                TEH_MT_REQUEST_PURSE_MERGE,
                                &mhd_ret,
                                &merge_transaction,
                                pmc))
    {
      return mhd_ret;
    }
  }

  {
    struct TALER_PurseEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_PURSE_MERGED),
      .purse_pub = pmc->purse_pub
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Notifying about purse merge\n");
    TEH_plugin->event_notify (TEH_plugin->cls,
                              &rep.header,
                              NULL,
                              0);
  }

  /* generate regular response */
  return reply_merge_success (pmc);
}


/* end of taler-exchange-httpd_purses_merge.c */
