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
 * @file taler-exchange-httpd_kyc-webhook.c
 * @brief Handle notification of KYC completion via webhook.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_attributes.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_kyc-webhook.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the webhook.
 */
struct KycWebhookContext
{

  /**
   * Kept in a DLL while suspended.
   */
  struct KycWebhookContext *next;

  /**
   * Kept in a DLL while suspended.
   */
  struct KycWebhookContext *prev;

  /**
   * Details about the connection we are processing.
   */
  struct TEH_RequestContext *rc;

  /**
   * Handle for the KYC-AML trigger interaction.
   */
  struct TEH_KycMeasureRunContext *kat;

  /**
   * Plugin responsible for the webhook.
   */
  struct TALER_KYCLOGIC_Plugin *plugin;

  /**
   * Name of the KYC provider (suffix of the
   * section name in the configuration).
   */
  const char *provider_name;

  /**
   * Configuration for the specific action.
   */
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Webhook activity.
   */
  struct TALER_KYCLOGIC_WebhookHandle *wh;

  /**
   * Final HTTP response to return.
   */
  struct MHD_Response *response;

  /**
   * Final HTTP response code to return.
   */
  unsigned int response_code;

  /**
   * Response from the webhook plugin.
   *
   * Will become the final response on successfully
   * running the measure with the new attributes.
   */
  struct MHD_Response *webhook_response;

  /**
   * Response code to return for the webhook plugin
   * response.
   */
  unsigned int webhook_response_code;

  /**
   * #GNUNET_YES if we are suspended,
   * #GNUNET_NO if not.
   * #GNUNET_SYSERR if we had some error.
   */
  enum GNUNET_GenericReturnValue suspended;

};


/**
 * Contexts are kept in a DLL while suspended.
 */
static struct KycWebhookContext *kwh_head;

/**
 * Contexts are kept in a DLL while suspended.
 */
static struct KycWebhookContext *kwh_tail;


/**
 * Resume processing the @a kwh request.
 *
 * @param kwh request to resume
 */
static void
kwh_resume (struct KycWebhookContext *kwh)
{
  GNUNET_assert (GNUNET_YES == kwh->suspended);
  kwh->suspended = GNUNET_NO;
  GNUNET_CONTAINER_DLL_remove (kwh_head,
                               kwh_tail,
                               kwh);
  MHD_resume_connection (kwh->rc->connection);
  TALER_MHD_daemon_trigger ();
}


void
TEH_kyc_webhook_cleanup (void)
{
  struct KycWebhookContext *kwh;

  while (NULL != (kwh = kwh_head))
  {
    if (NULL != kwh->wh)
    {
      kwh->plugin->webhook_cancel (kwh->wh);
      kwh->wh = NULL;
    }
    kwh_resume (kwh);
  }
}


/**
 * Function called after the KYC-AML trigger is done.
 *
 * @param cls closure with a `struct KycWebhookContext *`
 * @param ec error code or 0 on success
 * @param detail error message or NULL on success / no info
 */
static void
kyc_aml_webhook_finished (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *detail)
{
  struct KycWebhookContext *kwh = cls;

  kwh->kat = NULL;
  GNUNET_assert (NULL == kwh->response);
  if (TALER_EC_NONE != ec)
  {
    kwh->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
    kwh->response = TALER_MHD_make_error (
      ec,
      detail
      );
  }
  else
  {
    GNUNET_assert (NULL != kwh->webhook_response);
    kwh->response_code = kwh->webhook_response_code;
    kwh->response = kwh->webhook_response;
    kwh->webhook_response = NULL;
    kwh->webhook_response_code = 0;
  }
  kwh_resume (kwh);
}


/**
 * Function called with the result of a KYC webhook operation.
 *
 * Note that the "decref" for the @a response
 * will be done by the plugin.
 *
 * @param cls closure
 * @param process_row legitimization process the webhook was about
 * @param account_id account the webhook was about
 * @param provider_name name of the KYC provider that was run
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param status KYC status
 * @param expiration until when is the KYC check valid
 * @param attributes user attributes returned by the provider
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 */
static void
webhook_finished_cb (
  void *cls,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const char *provider_name,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  enum TALER_KYCLOGIC_KycStatus status,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *attributes,
  unsigned int http_status,
  struct MHD_Response *response)
{
  struct KycWebhookContext *kwh = cls;

  kwh->wh = NULL;
  kwh->webhook_response = response;
  kwh->webhook_response_code = http_status;

  switch (status)
  {
  case TALER_KYCLOGIC_STATUS_SUCCESS:
    kwh->kat = TEH_kyc_run_measure_for_attributes (
      &kwh->rc->async_scope_id,
      process_row,
      account_id,
      provider_name,
      provider_user_id,
      provider_legitimization_id,
      expiration,
      attributes,
      &kyc_aml_webhook_finished,
      kwh
      );
    if (NULL == kwh->kat)
    {
      kyc_aml_webhook_finished (kwh,
                                TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                                "[exchange] AML_KYC_TRIGGER");
    }
    break;
  case TALER_KYCLOGIC_STATUS_FAILED:
  case TALER_KYCLOGIC_STATUS_PROVIDER_FAILED:
  case TALER_KYCLOGIC_STATUS_USER_ABORTED:
  case TALER_KYCLOGIC_STATUS_ABORTED:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC process %s/%s (Row #%llu) failed: %d\n",
                provider_user_id,
                provider_legitimization_id,
                (unsigned long long) process_row,
                status);
    if (! TEH_kyc_failed (
          process_row,
          account_id,
          provider_name,
          provider_user_id,
          provider_legitimization_id,
          TALER_KYCLOGIC_status2s (status),
          TALER_EC_EXCHANGE_GENERIC_KYC_FAILED))
    {
      GNUNET_break (0);
      kyc_aml_webhook_finished (kwh,
                                TALER_EC_GENERIC_DB_STORE_FAILED,
                                "insert_kyc_failure");
    }
    break;
  default:
    GNUNET_log (
      GNUNET_ERROR_TYPE_INFO,
      "KYC status of %s/%s (Row #%llu) is %d\n",
      provider_user_id,
      provider_legitimization_id,
      (unsigned long long) process_row,
      (int) status);
    kyc_aml_webhook_finished (kwh,
                              TALER_EC_NONE,
                              NULL);
    break;
  }
}


/**
 * Function called to clean up a context.
 *
 * @param rc request context
 */
static void
clean_kwh (struct TEH_RequestContext *rc)
{
  struct KycWebhookContext *kwh = rc->rh_ctx;

  if (NULL != kwh->wh)
  {
    kwh->plugin->webhook_cancel (kwh->wh);
    kwh->wh = NULL;
  }
  if (NULL != kwh->kat)
  {
    TEH_kyc_run_measure_cancel (kwh->kat);
    kwh->kat = NULL;
  }
  if (NULL != kwh->response)
  {
    MHD_destroy_response (kwh->response);
    kwh->response = NULL;
  }
  if (NULL != kwh->webhook_response)
  {
    MHD_destroy_response (kwh->response);
    kwh->webhook_response = NULL;
  }
  GNUNET_free (kwh);
}


/**
 * Handle a (GET or POST) "/kyc-webhook" request.
 *
 * @param rc request to handle
 * @param method HTTP request method used by the client
 * @param root uploaded JSON body (can be NULL)
 * @param args one argument with the legitimization_uuid
 * @return MHD result code
 */
static MHD_RESULT
handler_kyc_webhook_generic (
  struct TEH_RequestContext *rc,
  const char *method,
  const json_t *root,
  const char *const args[])
{
  struct KycWebhookContext *kwh = rc->rh_ctx;

  if (NULL == kwh)
  { /* first time */
    kwh = GNUNET_new (struct KycWebhookContext);
    kwh->rc = rc;
    rc->rh_ctx = kwh;
    rc->rh_cleaner = &clean_kwh;

    if ( (NULL == args[0]) ||
         (GNUNET_OK !=
          TALER_KYCLOGIC_lookup_logic (
            args[0],
            &kwh->plugin,
            &kwh->pd,
            &kwh->provider_name)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "KYC logic `%s' unknown (check KYC provider configuration)\n",
                  args[0]);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN,
        args[0]);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC logic `%s' mapped to section %s\n",
                args[0],
                kwh->provider_name);
    kwh->wh = kwh->plugin->webhook (
      kwh->plugin->cls,
      kwh->pd,
      TEH_plugin->kyc_provider_account_lookup,
      TEH_plugin->cls,
      method,
      &args[1],
      rc->connection,
      root,
      &webhook_finished_cb,
      kwh);
    if (NULL == kwh->wh)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
        "failed to run webhook logic");
    }
    kwh->suspended = GNUNET_YES;
    GNUNET_CONTAINER_DLL_insert (kwh_head,
                                 kwh_tail,
                                 kwh);
    MHD_suspend_connection (rc->connection);
    return MHD_YES;
  }
  GNUNET_break (GNUNET_NO == kwh->suspended);

  if (NULL != kwh->response)
  {
    MHD_RESULT res;

    res = MHD_queue_response (rc->connection,
                              kwh->response_code,
                              kwh->response);
    GNUNET_break (MHD_YES == res);
    return res;
  }

  /* We resumed, but got no response? This should
     not happen. */
  GNUNET_break (0);
  return TALER_MHD_reply_with_error (
    rc->connection,
    MHD_HTTP_INTERNAL_SERVER_ERROR,
    TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
    "resumed without response");
}


MHD_RESULT
TEH_handler_kyc_webhook_get (
  struct TEH_RequestContext *rc,
  const char *const args[])
{
  return handler_kyc_webhook_generic (
    rc,
    MHD_HTTP_METHOD_GET,
    NULL,
    args);
}


MHD_RESULT
TEH_handler_kyc_webhook_post (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[])
{
  return handler_kyc_webhook_generic (
    rc,
    MHD_HTTP_METHOD_POST,
    root,
    args);
}


/* end of taler-exchange-httpd_kyc-webhook.c */
