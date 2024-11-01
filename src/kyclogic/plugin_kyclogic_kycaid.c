/*
  This file is part of GNU Taler
  Copyright (C) 2022--2024 Taler Systems SA

  Taler is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  Taler is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  Taler; see the file COPYING.GPL.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file plugin_kyclogic_kycaid.c
 * @brief kycaid for an authentication flow logic
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_attributes.h"
#include "taler_kyclogic_lib.h"
#include "taler_kyclogic_plugin.h"
#include "taler_mhd_lib.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"
#include "taler_templating_lib.h"
#include <regex.h>
#include "taler_util.h"


/**
 * Saves the state of a plugin.
 */
struct PluginState
{

  /**
   * Our base URL.
   */
  char *exchange_base_url;

  /**
   * Our global configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Context for CURL operations (useful to the event loop)
   */
  struct GNUNET_CURL_Context *curl_ctx;

  /**
   * Context for integrating @e curl_ctx with the
   * GNUnet event loop.
   */
  struct GNUNET_CURL_RescheduleContext *curl_rc;

};


/**
 * Keeps the plugin-specific state for
 * a given configuration section.
 */
struct TALER_KYCLOGIC_ProviderDetails
{

  /**
   * Overall plugin state.
   */
  struct PluginState *ps;

  /**
   * Configuration section that configured us.
   */
  char *section;

  /**
   * Authorization token to use when talking
   * to the service.
   */
  char *auth_token;

  /**
   * Form ID for the KYC check to perform.
   */
  char *form_id;

  /**
   * Helper binary to convert attributes returned by
   * KYCAID into our internal format.
   */
  char *conversion_helper;

  /**
   * Validity time for a successful KYC process.
   */
  struct GNUNET_TIME_Relative validity;

  /**
   * Curl-ready authentication header to use.
   */
  struct curl_slist *slist;

};


/**
 * Handle for an initiation operation.
 */
struct TALER_KYCLOGIC_InitiateHandle
{

  /**
   * Hash of the payto:// URI we are initiating
   * the KYC for.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * UUID being checked.
   */
  uint64_t legitimization_uuid;

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Continuation to call.
   */
  TALER_KYCLOGIC_InitiateCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * URL of the cURL request.
   */
  char *url;

};


/**
 * Handle for an KYC proof operation.
 */
struct TALER_KYCLOGIC_ProofHandle
{

  /**
   * Overall plugin state.
   */
  struct PluginState *ps;

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Continuation to call.
   */
  TALER_KYCLOGIC_ProofCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * Task for asynchronous execution.
   */
  struct GNUNET_SCHEDULER_Task *task;
};


/**
 * Handle for an KYC Web hook operation.
 */
struct TALER_KYCLOGIC_WebhookHandle
{

  /**
   * Continuation to call when done.
   */
  TALER_KYCLOGIC_WebhookCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Task for asynchronous execution.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Overall plugin state.
   */
  struct PluginState *ps;

  /**
   * Handle to helper process to extract attributes
   * we care about.
   */
  struct TALER_JSON_ExternalConversion *econ;

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * JSON response we got back, or NULL for none.
   */
  json_t *json_response;

  /**
   * Verification ID from the service.
   */
  char *verification_id;

  /**
   * Applicant ID from the service.
   */
  char *applicant_id;

  /**
   * URL of the cURL request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Response to return asynchronously.
   */
  struct MHD_Response *resp;

  /**
   * Our account ID.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * Row in legitimizations for the given
   * @e verification_id.
   */
  uint64_t process_row;

  /**
   * HTTP response code we got from KYCAID.
   */
  unsigned int kycaid_response_code;

  /**
   * HTTP response code to return asynchronously.
   */
  unsigned int response_code;
};


/**
 * Release configuration resources previously loaded
 *
 * @param[in] pd configuration to release
 */
static void
kycaid_unload_configuration (struct TALER_KYCLOGIC_ProviderDetails *pd)
{
  curl_slist_free_all (pd->slist);
  GNUNET_free (pd->conversion_helper);
  GNUNET_free (pd->auth_token);
  GNUNET_free (pd->form_id);
  GNUNET_free (pd->section);
  GNUNET_free (pd);
}


/**
 * Load the configuration of the KYC provider.
 *
 * @param cls closure
 * @param provider_section_name configuration section to parse
 * @return NULL if configuration is invalid
 */
static struct TALER_KYCLOGIC_ProviderDetails *
kycaid_load_configuration (void *cls,
                           const char *provider_section_name)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  pd = GNUNET_new (struct TALER_KYCLOGIC_ProviderDetails);
  pd->ps = ps;
  pd->section = GNUNET_strdup (provider_section_name);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (ps->cfg,
                                           provider_section_name,
                                           "KYC_KYCAID_VALIDITY",
                                           &pd->validity))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_KYCAID_VALIDITY");
    kycaid_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_KYCAID_AUTH_TOKEN",
                                             &pd->auth_token))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_KYCAID_AUTH_TOKEN");
    kycaid_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_KYCAID_FORM_ID",
                                             &pd->form_id))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_KYCAID_FORM_ID");
    kycaid_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_KYCAID_CONVERTER_HELPER",
                                             &pd->conversion_helper))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_KYCAID_CONVERTER_HELPER");
    kycaid_unload_configuration (pd);
    return NULL;
  }
  {
    char *auth;

    GNUNET_asprintf (&auth,
                     "%s: Token %s",
                     MHD_HTTP_HEADER_AUTHORIZATION,
                     pd->auth_token);
    pd->slist = curl_slist_append (NULL,
                                   auth);
    GNUNET_free (auth);
  }
  return pd;
}


/**
 * Cancel KYC check initiation.
 *
 * @param[in] ih handle of operation to cancel
 */
static void
kycaid_initiate_cancel (struct TALER_KYCLOGIC_InitiateHandle *ih)
{
  if (NULL != ih->job)
  {
    GNUNET_CURL_job_cancel (ih->job);
    ih->job = NULL;
  }
  GNUNET_free (ih->url);
  TALER_curl_easy_post_finished (&ih->ctx);
  GNUNET_free (ih);
}


/**
 * Function called when we're done processing the
 * HTTP "/forms/{form_id}/urls" request.
 *
 * @param cls the `struct TALER_KYCLOGIC_InitiateHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_initiate_finished (void *cls,
                          long response_code,
                          const void *response)
{
  struct TALER_KYCLOGIC_InitiateHandle *ih = cls;
  const json_t *j = response;

  ih->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *verification_id;
      const char *form_url;
      const char *form_id;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("verification_id",
                                 &verification_id),
        GNUNET_JSON_spec_string ("form_url",
                                 &form_url),
        GNUNET_JSON_spec_string ("form_id",
                                 &form_id),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        json_dumpf (j,
                    stderr,
                    JSON_INDENT (2));
        ih->cb (ih->cb_cls,
                TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
                NULL,
                NULL,
                NULL,
                json_string_value (json_object_get (j,
                                                    "type")));
        break;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Started new verification `%s' using form %s\n",
                  verification_id,
                  form_id);
      ih->cb (ih->cb_cls,
              TALER_EC_NONE,
              form_url,
              NULL, /* no provider_user_id */
              verification_id,
              NULL /* no error */);
      GNUNET_JSON_parse_free (spec);
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYCAID failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_BUG,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  case MHD_HTTP_UNAUTHORIZED:
  case MHD_HTTP_PAYMENT_REQUIRED:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Refused access with HTTP status code %u\n",
                (unsigned int) response_code);
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_ACCESS_REFUSED,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  case MHD_HTTP_REQUEST_TIMEOUT:
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_TIMEOUT,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  case MHD_HTTP_UNPROCESSABLE_ENTITY: /* validation */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYCAID failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  case MHD_HTTP_TOO_MANY_REQUESTS:
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_RATE_LIMIT_EXCEEDED,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected KYCAID response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    ih->cb (ih->cb_cls,
            TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
            NULL,
            NULL,
            NULL,
            json_string_value (json_object_get (j,
                                                "type")));
    break;
  }
  kycaid_initiate_cancel (ih);
}


/**
 * Initiate KYC check.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param account_id which account to trigger process for
 * @param legitimization_uuid unique ID for the legitimization process
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_InitiateHandle *
kycaid_initiate (void *cls,
                 const struct TALER_KYCLOGIC_ProviderDetails *pd,
                 const struct TALER_NormalizedPaytoHashP *account_id,
                 uint64_t legitimization_uuid,
                 TALER_KYCLOGIC_InitiateCallback cb,
                 void *cb_cls)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_InitiateHandle *ih;
  json_t *body;
  CURL *eh;

  eh = curl_easy_init ();
  if (NULL == eh)
  {
    GNUNET_break (0);
    return NULL;
  }
  ih = GNUNET_new (struct TALER_KYCLOGIC_InitiateHandle);
  ih->legitimization_uuid = legitimization_uuid;
  ih->cb = cb;
  ih->cb_cls = cb_cls;
  ih->h_payto = *account_id;
  ih->pd = pd;
  GNUNET_asprintf (&ih->url,
                   "https://api.kycaid.com/forms/%s/urls",
                   pd->form_id);
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data64_auto ("external_applicant_id",
                                  account_id)
    );
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  0));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_MAXREDIRS,
                                   1L));
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_URL,
                                  ih->url));
  if (GNUNET_OK !=
      TALER_curl_easy_post (&ih->ctx,
                            eh,
                            body))
  {
    GNUNET_break (0);
    GNUNET_free (ih->url);
    GNUNET_free (ih);
    curl_easy_cleanup (eh);
    json_decref (body);
    return NULL;
  }
  json_decref (body);
  ih->job = GNUNET_CURL_job_add2 (ps->curl_ctx,
                                  eh,
                                  ih->ctx.headers,
                                  &handle_initiate_finished,
                                  ih);
  GNUNET_CURL_extend_headers (ih->job,
                              pd->slist);
  return ih;
}


/**
 * Cancel KYC proof.
 *
 * @param[in] ph handle of operation to cancel
 */
static void
kycaid_proof_cancel (struct TALER_KYCLOGIC_ProofHandle *ph)
{
  if (NULL != ph->task)
  {
    GNUNET_SCHEDULER_cancel (ph->task);
    ph->task = NULL;
  }
  GNUNET_free (ph);
}


/**
 * Call @a ph callback with HTTP error response.
 *
 * @param cls proof handle to generate reply for
 */
static void
proof_reply (void *cls)
{
  struct TALER_KYCLOGIC_ProofHandle *ph = cls;
  struct MHD_Response *resp;
  enum GNUNET_GenericReturnValue ret;
  json_t *body;
  unsigned int http_status;

  http_status = MHD_HTTP_BAD_REQUEST;
  body = GNUNET_JSON_PACK (
    TALER_JSON_pack_ec (TALER_EC_GENERIC_ENDPOINT_UNKNOWN));
  GNUNET_assert (NULL != body);
  ret = TALER_TEMPLATING_build (ph->connection,
                                &http_status,
                                "kycaid-invalid-request",
                                NULL,
                                NULL,
                                body,
                                &resp);
  json_decref (body);
  GNUNET_break (GNUNET_SYSERR != ret);
  ph->cb (ph->cb_cls,
          TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
          NULL, /* user id */
          NULL, /* provider legi ID */
          GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
          NULL, /* attributes */
          http_status,
          resp);
}


/**
 * Check KYC status and return status to human. Not
 * used by KYC AID!
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param connection MHD connection object (for HTTP headers)
 * @param account_id which account to trigger process for
 * @param process_row row in the legitimization processes table the legitimization is for
 * @param provider_user_id user ID (or NULL) the proof is for
 * @param provider_legitimization_id legitimization ID the proof is for
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_ProofHandle *
kycaid_proof (void *cls,
              const struct TALER_KYCLOGIC_ProviderDetails *pd,
              struct MHD_Connection *connection,
              const struct TALER_NormalizedPaytoHashP *account_id,
              uint64_t process_row,
              const char *provider_user_id,
              const char *provider_legitimization_id,
              TALER_KYCLOGIC_ProofCallback cb,
              void *cb_cls)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_ProofHandle *ph;

  ph = GNUNET_new (struct TALER_KYCLOGIC_ProofHandle);
  ph->ps = ps;
  ph->pd = pd;
  ph->cb = cb;
  ph->cb_cls = cb_cls;
  ph->connection = connection;
  ph->task = GNUNET_SCHEDULER_add_now (&proof_reply,
                                       ph);
  return ph;
}


/**
 * Cancel KYC webhook execution.
 *
 * @param[in] wh handle of operation to cancel
 */
static void
kycaid_webhook_cancel (struct TALER_KYCLOGIC_WebhookHandle *wh)
{
  if (NULL != wh->task)
  {
    GNUNET_SCHEDULER_cancel (wh->task);
    wh->task = NULL;
  }
  if (NULL != wh->econ)
  {
    TALER_JSON_external_conversion_stop (wh->econ);
    wh->econ = NULL;
  }
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  if (NULL != wh->json_response)
  {
    json_decref (wh->json_response);
    wh->json_response = NULL;
  }
  GNUNET_free (wh->verification_id);
  GNUNET_free (wh->applicant_id);
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}


/**
 * Extract KYC failure reasons and log those
 *
 * @param verifications JSON object with failure details
 */
static void
log_failure (const json_t *verifications)
{
  const json_t *member;
  const char *name;

  json_object_foreach ((json_t *) verifications, name, member)
  {
    bool iverified;
    const char *comment;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_bool ("verified",
                             &iverified),
      GNUNET_JSON_spec_string ("comment",
                               &comment),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (member,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      json_dumpf (member,
                  stderr,
                  JSON_INDENT (2));
      continue;
    }
    if (iverified)
      continue;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC verification of attribute `%s' failed: %s\n",
                name,
                comment);
  }
}


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure our `struct TALER_KYCLOGIC_WebhookHandle *`
 * @param status_type how did the process die
 * @param code termination status code from the process
 * @param result converted attribute data, NULL on failure
 */
static void
webhook_conversion_cb (void *cls,
                       enum GNUNET_OS_ProcessStatusType status_type,
                       unsigned long code,
                       const json_t *result)
{
  struct TALER_KYCLOGIC_WebhookHandle *wh = cls;
  struct GNUNET_TIME_Absolute expiration;
  struct MHD_Response *resp;

  wh->econ = NULL;
  if ( (0 == code) &&
       (NULL == result) )
  {
    /* No result, but *our helper* was OK => bad input */
    GNUNET_break_op (0);
    json_dumpf (wh->json_response,
                stderr,
                JSON_INDENT (2));
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               wh->kycaid_response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) wh->json_response));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_BAD_GATEWAY,
            resp);
    kycaid_webhook_cancel (wh);
    return;
  }
  if (NULL == result)
  {
    /* Failure in our helper */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Helper exited with status code %d\n",
                (int) code);
    json_dumpf (wh->json_response,
                stderr,
                JSON_INDENT (2));
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               wh->kycaid_response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) wh->json_response));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_BAD_GATEWAY,
            resp);
    kycaid_webhook_cancel (wh);
    return;
  }
  expiration = GNUNET_TIME_relative_to_absolute (wh->pd->validity);
  resp = MHD_create_response_from_buffer_static (0,
                                                 "");
  wh->cb (wh->cb_cls,
          wh->process_row,
          &wh->h_payto,
          wh->pd->section,
          wh->applicant_id,
          wh->verification_id,
          TALER_KYCLOGIC_STATUS_SUCCESS,
          expiration,
          result,
          MHD_HTTP_NO_CONTENT,
          resp);
  kycaid_webhook_cancel (wh);
}


/**
 * Function called when we're done processing the
 * HTTP "/applicants/{verification_id}" request.
 *
 * @param cls the `struct TALER_KYCLOGIC_WebhookHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_webhook_finished (void *cls,
                         long response_code,
                         const void *response)
{
  struct TALER_KYCLOGIC_WebhookHandle *wh = cls;
  const json_t *j = response;
  struct MHD_Response *resp;

  wh->job = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Webhook returned with HTTP status %u\n",
              (unsigned int) response_code);
  wh->kycaid_response_code = response_code;
  wh->json_response = json_incref ((json_t *) j);
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *profile_status;

      profile_status = json_string_value (
        json_object_get (
          j,
          "profile_status"));
      if (0 != strcasecmp ("valid",
                           profile_status))
      {
        enum TALER_KYCLOGIC_KycStatus ks;

        ks = (0 == strcasecmp ("pending",
                               profile_status))
          ? TALER_KYCLOGIC_STATUS_PENDING
          : TALER_KYCLOGIC_STATUS_USER_ABORTED;
        resp = MHD_create_response_from_buffer_static (0,
                                                       "");
        wh->cb (wh->cb_cls,
                wh->process_row,
                &wh->h_payto,
                wh->pd->section,
                wh->applicant_id,
                wh->verification_id,
                ks,
                GNUNET_TIME_UNIT_ZERO_ABS,
                NULL,
                MHD_HTTP_NO_CONTENT,
                resp);
        break;
      }
      {
        const char *argv[] = {
          wh->pd->conversion_helper,
          "-a",
          wh->pd->auth_token,
          NULL,
        };

        wh->econ
          = TALER_JSON_external_conversion_start (
              j,
              &webhook_conversion_cb,
              wh,
              wh->pd->conversion_helper,
              argv);
      }
      if (NULL == wh->econ)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to start KYCAID conversion helper `%s'\n",
                    wh->pd->conversion_helper);
        resp = TALER_MHD_make_error (
          TALER_EC_EXCHANGE_GENERIC_KYC_CONVERTER_FAILED,
          NULL);
        wh->cb (wh->cb_cls,
                wh->process_row,
                &wh->h_payto,
                wh->pd->section,
                wh->applicant_id,
                wh->verification_id,
                TALER_KYCLOGIC_STATUS_INTERNAL_ERROR,
                GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
                NULL,
                MHD_HTTP_INTERNAL_SERVER_ERROR,
                resp);
        break;
      }
      return;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYCAID failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_INTERNAL_SERVER_ERROR,
            resp);
    break;
  case MHD_HTTP_UNAUTHORIZED:
  case MHD_HTTP_PAYMENT_REQUIRED:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Refused access with HTTP status code %u\n",
                (unsigned int) response_code);
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) j));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_NETWORK_AUTHENTICATION_REQUIRED,
            resp);
    break;
  case MHD_HTTP_REQUEST_TIMEOUT:
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) j));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_GATEWAY_TIMEOUT,
            resp);
    break;
  case MHD_HTTP_UNPROCESSABLE_ENTITY: /* validation */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYCAID failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) j));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_BAD_GATEWAY,
            resp);
    break;
  case MHD_HTTP_TOO_MANY_REQUESTS:
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) j));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_SERVICE_UNAVAILABLE,
            resp);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) j));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_BAD_GATEWAY,
            resp);
    break;
  default:
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code),
      GNUNET_JSON_pack_object_incref ("kycaid_body",
                                      (json_t *) j));
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected KYCAID response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    wh->cb (wh->cb_cls,
            wh->process_row,
            &wh->h_payto,
            wh->pd->section,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
            NULL,
            MHD_HTTP_BAD_GATEWAY,
            resp);
    break;
  }
  kycaid_webhook_cancel (wh);
}


/**
 * Asynchronously return a reply for the webhook.
 *
 * @param cls a `struct TALER_KYCLOGIC_WebhookHandle *`
 */
static void
async_webhook_reply (void *cls)
{
  struct TALER_KYCLOGIC_WebhookHandle *wh = cls;

  wh->task = NULL;
  wh->cb (wh->cb_cls,
          wh->process_row,
          (0 == wh->process_row)
          ? NULL
          : &wh->h_payto,
          wh->pd->section,
          wh->applicant_id, /* provider user ID */
          wh->verification_id, /* provider legi ID */
          TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
          GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
          NULL,
          wh->response_code,
          wh->resp);
  kycaid_webhook_cancel (wh);
}


/**
 * Check KYC status and return result for Webhook.  We do NOT implement the
 * authentication check proposed by the KYCAID documentation, as it would
 * allow an attacker who learns the access token to easily bypass the KYC
 * checks. Instead, we insist on explicitly requesting the KYC status from the
 * provider (at least on success).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param plc callback to lookup accounts with
 * @param plc_cls closure for @a plc
 * @param http_method HTTP method used for the webhook
 * @param url_path rest of the URL after `/kyc-webhook/`
 * @param connection MHD connection object (for HTTP headers)
 * @param body HTTP request body
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_WebhookHandle *
kycaid_webhook (void *cls,
                const struct TALER_KYCLOGIC_ProviderDetails *pd,
                TALER_KYCLOGIC_ProviderLookupCallback plc,
                void *plc_cls,
                const char *http_method,
                const char *const url_path[],
                struct MHD_Connection *connection,
                const json_t *body,
                TALER_KYCLOGIC_WebhookCallback cb,
                void *cb_cls)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_WebhookHandle *wh;
  CURL *eh;
  const char *request_id;
  const char *type;
  const char *verification_id; /* = provider_legitimization_id */
  const char *applicant_id;
  const char *form_id;
  const char *status = NULL;
  bool verified = false;
  bool no_verified = true;
  const json_t *verifications = NULL;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("request_id",
                             &request_id),
    GNUNET_JSON_spec_string ("type",
                             &type),
    GNUNET_JSON_spec_string ("verification_id",
                             &verification_id),
    GNUNET_JSON_spec_string ("applicant_id",
                             &applicant_id),
    GNUNET_JSON_spec_string ("form_id",
                             &form_id),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string ("status",
                               &status),
      NULL),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_bool ("verified",
                             &verified),
      &no_verified),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("verifications",
                                     &verifications),
      NULL),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;

  wh = GNUNET_new (struct TALER_KYCLOGIC_WebhookHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ps = ps;
  wh->pd = pd;
  wh->connection = connection;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYCAID webhook of `%s' triggered with %s\n",
              pd->section,
              http_method);
#if 1
  if (NULL != body)
    json_dumpf (body,
                stderr,
                JSON_INDENT (2));
#endif
  if (NULL == pd)
  {
    GNUNET_break_op (0);
    json_dumpf (body,
                stderr,
                JSON_INDENT (2));
    wh->resp = TALER_MHD_make_error (
      TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN,
      "kycaid");
    wh->response_code = MHD_HTTP_NOT_FOUND;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }

  if (GNUNET_OK !=
      GNUNET_JSON_parse (body,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    json_dumpf (body,
                stderr,
                JSON_INDENT (2));
    wh->resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_object_incref ("webhook_body",
                                      (json_t *) body));
    wh->response_code = MHD_HTTP_BAD_REQUEST;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }
  qs = plc (plc_cls,
            pd->section,
            verification_id,
            &wh->h_payto,
            &wh->process_row);
  if (qs < 0)
  {
    wh->resp = TALER_MHD_make_error (TALER_EC_GENERIC_DB_FETCH_FAILED,
                                     "provider-legitimization-lookup");
    wh->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Received webhook for unknown verification ID `%s' and section `%s'\n",
                verification_id,
                pd->section);
    wh->resp = TALER_MHD_make_error (
      TALER_EC_EXCHANGE_KYC_PROOF_REQUEST_UNKNOWN,
      verification_id);
    wh->response_code = MHD_HTTP_NOT_FOUND;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }
  wh->verification_id = GNUNET_strdup (verification_id);
  wh->applicant_id = GNUNET_strdup (applicant_id);
  if ( (0 != strcasecmp (type,
                         "VERIFICATION_COMPLETED")) ||
       (no_verified) ||
       (! verified) )
  {
    /* We don't need to re-confirm the failure by
       asking the API again. */
    log_failure (verifications);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Webhook called with non-completion status: %s\n",
                type);
    wh->response_code = MHD_HTTP_NO_CONTENT;
    wh->resp = MHD_create_response_from_buffer_static (0,
                                                       "");
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }

  eh = curl_easy_init ();
  if (NULL == eh)
  {
    GNUNET_break (0);
    wh->resp = TALER_MHD_make_error (
      TALER_EC_GENERIC_ALLOCATION_FAILURE,
      NULL);
    wh->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }

  GNUNET_asprintf (&wh->url,
                   "https://api.kycaid.com/applicants/%s",
                   applicant_id);
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  0));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_MAXREDIRS,
                                   1L));
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_URL,
                                  wh->url));
  wh->job = GNUNET_CURL_job_add2 (ps->curl_ctx,
                                  eh,
                                  pd->slist,
                                  &handle_webhook_finished,
                                  wh);
  return wh;
}


/**
 * Initialize kycaid logic plugin
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_KYCLOGIC_Plugin`
 */
void *
libtaler_plugin_kyclogic_kycaid_init (void *cls);

/* declaration to avoid compiler warning */
void *
libtaler_plugin_kyclogic_kycaid_init (void *cls)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_KYCLOGIC_Plugin *plugin;
  struct PluginState *ps;

  ps = GNUNET_new (struct PluginState);
  ps->cfg = cfg;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &ps->exchange_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    GNUNET_free (ps);
    return NULL;
  }

  ps->curl_ctx
    = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                        &ps->curl_rc);
  if (NULL == ps->curl_ctx)
  {
    GNUNET_break (0);
    GNUNET_free (ps->exchange_base_url);
    GNUNET_free (ps);
    return NULL;
  }
  ps->curl_rc = GNUNET_CURL_gnunet_rc_create (ps->curl_ctx);

  plugin = GNUNET_new (struct TALER_KYCLOGIC_Plugin);
  plugin->cls = ps;
  plugin->load_configuration
    = &kycaid_load_configuration;
  plugin->unload_configuration
    = &kycaid_unload_configuration;
  plugin->initiate
    = &kycaid_initiate;
  plugin->initiate_cancel
    = &kycaid_initiate_cancel;
  plugin->proof
    = &kycaid_proof;
  plugin->proof_cancel
    = &kycaid_proof_cancel;
  plugin->webhook
    = &kycaid_webhook;
  plugin->webhook_cancel
    = &kycaid_webhook_cancel;
  return plugin;
}


/**
 * Unload authorization plugin
 *
 * @param cls a `struct TALER_KYCLOGIC_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_kyclogic_kycaid_done (void *cls);

/* declaration to avoid compiler warning */
void *
libtaler_plugin_kyclogic_kycaid_done (void *cls)
{
  struct TALER_KYCLOGIC_Plugin *plugin = cls;
  struct PluginState *ps = plugin->cls;

  if (NULL != ps->curl_ctx)
  {
    GNUNET_CURL_fini (ps->curl_ctx);
    ps->curl_ctx = NULL;
  }
  if (NULL != ps->curl_rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (ps->curl_rc);
    ps->curl_rc = NULL;
  }
  GNUNET_free (ps->exchange_base_url);
  GNUNET_free (ps);
  GNUNET_free (plugin);
  return NULL;
}
