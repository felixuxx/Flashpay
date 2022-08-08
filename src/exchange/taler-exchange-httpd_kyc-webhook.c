/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_kyclogic_lib.h"
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
   * Plugin responsible for the webhook.
   */
  struct TALER_KYCLOGIC_Plugin *plugin;

  /**
   * Configuration for the specific action.
   */
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Webhook activity.
   */
  struct TALER_KYCLOGIC_WebhookHandle *wh;

  /**
   * HTTP response to return.
   */
  struct MHD_Response *response;

  /**
   * Logic the request is for. Name of the configuration
   * section defining the KYC logic.
   */
  char *logic;

  /**
   * HTTP response code to return.
   */
  unsigned int response_code;

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
 * Function called with the result of a webhook
 * operation.
 *
 * Note that the "decref" for the @a response
 * will be done by the plugin.
 *
 * @param cls closure
 * @param legi_row legitimization request the webhook was about
 * @param account_id account the webhook was about
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param status KYC status
 * @param expiration until when is the KYC check valid
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 */
static void
webhook_finished_cb (
  void *cls,
  uint64_t legi_row,
  const struct TALER_PaytoHashP *account_id,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  enum TALER_KYCLOGIC_KycStatus status,
  struct GNUNET_TIME_Absolute expiration,
  unsigned int http_status,
  struct MHD_Response *response)
{
  struct KycWebhookContext *kwh = cls;

  kwh->wh = NULL;
  switch (status)
  {
  case TALER_KYCLOGIC_STATUS_SUCCESS:
    /* _successfully_ resumed case */
    {
      enum GNUNET_DB_QueryStatus qs;

      qs = TEH_plugin->update_kyc_requirement_by_row (TEH_plugin->cls,
                                                      legi_row,
                                                      kwh->logic,
                                                      account_id,
                                                      provider_user_id,
                                                      provider_legitimization_id,
                                                      expiration);
      if (qs < 0)
      {
        GNUNET_break (0);
        kwh->response = TALER_MHD_make_error (TALER_EC_GENERIC_DB_STORE_FAILED,
                                              "set_kyc_ok");
        kwh->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
        kwh_resume (kwh);
        return;
      }
    }
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC status of %s/%s (Row #%llu) is %d\n",
                provider_user_id,
                provider_legitimization_id,
                (unsigned long long) legi_row,
                status);
    break;
  }
  kwh->response = response;
  kwh->response_code = http_status;
  kwh_resume (kwh);
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
  if (NULL != kwh->response)
  {
    MHD_destroy_response (kwh->response);
    kwh->response = NULL;
  }
  GNUNET_free (kwh->logic);
  GNUNET_free (kwh);
}


/**
 * Handle a (GET or POST) "/kyc-webhook" request.
 *
 * @param rc request to handle
 * @param method HTTP request method used by the client
 * @param root uploaded JSON body (can be NULL)
 * @param args one argument with the payment_target_uuid
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
    kwh->logic = GNUNET_strdup (args[0]);
    kwh->rc = rc;
    rc->rh_ctx = kwh;
    rc->rh_cleaner = &clean_kwh;

    if (GNUNET_OK !=
        TALER_KYCLOGIC_kyc_get_logic (kwh->logic,
                                      &kwh->plugin,
                                      &kwh->pd))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "KYC logic `%s' unknown (check KYC provider configuration)\n",
                  kwh->logic);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_KYC_WEBHOOK_LOGIC_UNKNOWN,
                                         "$LOGIC");
    }
    kwh->wh = kwh->plugin->webhook (kwh->plugin->cls,
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
      return TALER_MHD_reply_with_error (rc->connection,
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

  if (NULL != kwh->response)
  {
    /* handle _failed_ resumed cases */
    return MHD_queue_response (rc->connection,
                               kwh->response_code,
                               kwh->response);
  }

  /* We resumed, but got no response? This should
     not happen. */
  GNUNET_break (0);
  return TALER_MHD_reply_with_error (rc->connection,
                                     MHD_HTTP_INTERNAL_SERVER_ERROR,
                                     TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                     "resumed without response");
}


MHD_RESULT
TEH_handler_kyc_webhook_get (
  struct TEH_RequestContext *rc,
  const char *const args[])
{
  return handler_kyc_webhook_generic (rc,
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
  return handler_kyc_webhook_generic (rc,
                                      MHD_HTTP_METHOD_POST,
                                      root,
                                      args);
}


/* end of taler-exchange-httpd_kyc-webhook.c */
