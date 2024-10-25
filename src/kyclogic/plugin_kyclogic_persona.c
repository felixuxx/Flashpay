/*
  This file is part of GNU Taler
  Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file plugin_kyclogic_persona.c
 * @brief persona for an authentication flow logic
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_attributes.h"
#include "taler_kyclogic_plugin.h"
#include "taler_mhd_lib.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_templating_lib.h"
#include <regex.h>
#include "taler_util.h"


/**
 * Which version of the persona API are we implementing?
 */
#define PERSONA_VERSION "2021-07-05"

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

  /**
   * Authorization token to use when receiving webhooks from the Persona
   * service.  Optional.  Note that webhooks are *global* and not per
   * template.
   */
  char *webhook_token;


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
   * Salt to use for idempotency.
   */
  char *salt;

  /**
   * Authorization token to use when talking
   * to the service.
   */
  char *auth_token;

  /**
   * Template ID for the KYC check to perform.
   */
  char *template_id;

  /**
   * Subdomain to use.
   */
  char *subdomain;

  /**
   * Name of the program we use to convert outputs
   * from Persona into our JSON inputs.
   */
  char *conversion_binary;

  /**
   * Where to redirect the client upon completion.
   */
  char *post_kyc_redirect_url;

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
   * Hash of the payto:// URI we are initiating the KYC for.
   */
  struct TALER_PaytoHashP h_payto;

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

  /**
   * Request-specific headers to use.
   */
  struct curl_slist *slist;

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

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * URL of the cURL request.
   */
  char *url;

  /**
   * Handle to an external process that converts the
   * Persona response to our internal format.
   */
  struct TALER_JSON_ExternalConversion *ec;

  /**
   * Hash of the payto:// URI we are checking the KYC for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Row in the legitimization processes of the
   * legitimization proof that is being checked.
   */
  uint64_t process_row;

  /**
   * Account ID at the provider.
   */
  char *provider_user_id;

  /**
   * Account ID from the service.
   */
  char *account_id;

  /**
   * Inquiry ID at the provider.
   */
  char *inquiry_id;
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
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * Verification ID from the service.
   */
  char *inquiry_id;

  /**
   * Account ID from the service.
   */
  char *account_id;

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
   * ID of the template the webhook is about,
   * according to the service.
   */
  const char *template_id;

  /**
   * Handle to an external process that converts the
   * Persona response to our internal format.
   */
  struct TALER_JSON_ExternalConversion *ec;

  /**
   * Our account ID.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * UUID being checked.
   */
  uint64_t process_row;

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
persona_unload_configuration (struct TALER_KYCLOGIC_ProviderDetails *pd)
{
  curl_slist_free_all (pd->slist);
  GNUNET_free (pd->auth_token);
  GNUNET_free (pd->template_id);
  GNUNET_free (pd->subdomain);
  GNUNET_free (pd->conversion_binary);
  GNUNET_free (pd->salt);
  GNUNET_free (pd->section);
  GNUNET_free (pd->post_kyc_redirect_url);
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
persona_load_configuration (void *cls,
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
                                           "KYC_PERSONA_VALIDITY",
                                           &pd->validity))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_PERSONA_VALIDITY");
    persona_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_PERSONA_AUTH_TOKEN",
                                             &pd->auth_token))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_PERSONA_AUTH_TOKEN");
    persona_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_PERSONA_SALT",
                                             &pd->salt))
  {
    uint32_t salt[8];

    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                salt,
                                sizeof (salt));
    pd->salt = GNUNET_STRINGS_data_to_string_alloc (salt,
                                                    sizeof (salt));
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_PERSONA_SUBDOMAIN",
                                             &pd->subdomain))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_PERSONA_SUBDOMAIN");
    persona_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_PERSONA_CONVERTER_HELPER",
                                             &pd->conversion_binary))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_PERSONA_CONVERTER_HELPER");
    persona_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_PERSONA_POST_URL",
                                             &pd->post_kyc_redirect_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_PERSONA_POST_URL");
    persona_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_PERSONA_TEMPLATE_ID",
                                             &pd->template_id))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_PERSONA_TEMPLATE_ID");
    persona_unload_configuration (pd);
    return NULL;
  }
  {
    char *auth;

    GNUNET_asprintf (&auth,
                     "%s: Bearer %s",
                     MHD_HTTP_HEADER_AUTHORIZATION,
                     pd->auth_token);
    pd->slist = curl_slist_append (NULL,
                                   auth);
    GNUNET_free (auth);
    GNUNET_asprintf (&auth,
                     "%s: %s",
                     MHD_HTTP_HEADER_ACCEPT,
                     "application/json");
    pd->slist = curl_slist_append (pd->slist,
                                   "Persona-Version: "
                                   PERSONA_VERSION);
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
persona_initiate_cancel (struct TALER_KYCLOGIC_InitiateHandle *ih)
{
  if (NULL != ih->job)
  {
    GNUNET_CURL_job_cancel (ih->job);
    ih->job = NULL;
  }
  GNUNET_free (ih->url);
  TALER_curl_easy_post_finished (&ih->ctx);
  curl_slist_free_all (ih->slist);
  GNUNET_free (ih);
}


/**
 * Function called when we're done processing the
 * HTTP POST "/api/v1/inquiries" request.
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
  const struct TALER_KYCLOGIC_ProviderDetails *pd = ih->pd;
  const json_t *j = response;
  char *url;
  json_t *data;
  const char *type;
  const char *inquiry_id;
  const char *persona_account_id;
  const char *ename;
  unsigned int eline;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("type",
                             &type),
    GNUNET_JSON_spec_string ("id",
                             &inquiry_id),
    GNUNET_JSON_spec_end ()
  };

  ih->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_CREATED:
    /* handled below */
    break;
  case MHD_HTTP_UNAUTHORIZED:
  case MHD_HTTP_FORBIDDEN:
    {
      const char *msg;

      msg = json_string_value (
        json_object_get (
          json_array_get (
            json_object_get (j,
                             "errors"),
            0),
          "title"));

      ih->cb (ih->cb_cls,
              TALER_EC_EXCHANGE_KYC_CHECK_AUTHORIZATION_FAILED,
              NULL,
              NULL,
              NULL,
              msg);
      persona_initiate_cancel (ih);
      return;
    }
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
    {
      const char *msg;

      msg = json_string_value (
        json_object_get (
          json_array_get (
            json_object_get (j,
                             "errors"),
            0),
          "title"));

      ih->cb (ih->cb_cls,
              TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
              NULL,
              NULL,
              NULL,
              msg);
      persona_initiate_cancel (ih);
      return;
    }
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_UNPROCESSABLE_ENTITY:
    {
      const char *msg;

      GNUNET_break (0);
      json_dumpf (j,
                  stderr,
                  JSON_INDENT (2));
      msg = json_string_value (
        json_object_get (
          json_array_get (
            json_object_get (j,
                             "errors"),
            0),
          "title"));

      ih->cb (ih->cb_cls,
              TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_BUG,
              NULL,
              NULL,
              NULL,
              msg);
      persona_initiate_cancel (ih);
      return;
    }
  case MHD_HTTP_TOO_MANY_REQUESTS:
    {
      const char *msg;

      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Rate limiting requested:\n");
      json_dumpf (j,
                  stderr,
                  JSON_INDENT (2));
      msg = json_string_value (
        json_object_get (
          json_array_get (
            json_object_get (j,
                             "errors"),
            0),
          "title"));
      ih->cb (ih->cb_cls,
              TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_RATE_LIMIT_EXCEEDED,
              NULL,
              NULL,
              NULL,
              msg);
      persona_initiate_cancel (ih);
      return;
    }
  default:
    {
      char *err;

      GNUNET_break_op (0);
      json_dumpf (j,
                  stderr,
                  JSON_INDENT (2));
      GNUNET_asprintf (&err,
                       "Unexpected HTTP status %u from Persona\n",
                       (unsigned int) response_code);
      ih->cb (ih->cb_cls,
              TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY,
              NULL,
              NULL,
              NULL,
              err);
      GNUNET_free (err);
      persona_initiate_cancel (ih);
      return;
    }
  }
  data = json_object_get (j,
                          "data");
  if (NULL == data)
  {
    GNUNET_break_op (0);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    persona_initiate_cancel (ih);
    return;
  }

  if (GNUNET_OK !=
      GNUNET_JSON_parse (data,
                         spec,
                         &ename,
                         &eline))
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
            ename);
    persona_initiate_cancel (ih);
    return;
  }
  persona_account_id
    = json_string_value (
        json_object_get (
          json_object_get (
            json_object_get (
              json_object_get (data,
                               "relationships"),
              "account"),
            "data"),
          "id"));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting inquiry %s for Persona account %s\n",
              inquiry_id,
              persona_account_id);
  GNUNET_asprintf (&url,
                   "https://%s.withpersona.com/verify"
                   "?inquiry-id=%s",
                   pd->subdomain,
                   inquiry_id);
  ih->cb (ih->cb_cls,
          TALER_EC_NONE,
          url,
          persona_account_id,
          inquiry_id,
          NULL);
  GNUNET_free (url);
  persona_initiate_cancel (ih);
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
persona_initiate (void *cls,
                  const struct TALER_KYCLOGIC_ProviderDetails *pd,
                  const struct TALER_PaytoHashP *account_id,
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
                   "https://withpersona.com/api/v1/inquiries");
  {
    char *payto_s;
    char *proof_url;
    char ref_s[24];

    GNUNET_snprintf (ref_s,
                     sizeof (ref_s),
                     "%llu",
                     (unsigned long long) ih->legitimization_uuid);
    payto_s = GNUNET_STRINGS_data_to_string_alloc (&ih->h_payto,
                                                   sizeof (ih->h_payto));
    GNUNET_break ('/' ==
                  pd->ps->exchange_base_url[strlen (
                                              pd->ps->exchange_base_url) - 1]);
    GNUNET_asprintf (&proof_url,
                     "%skyc-proof/%s?state=%s",
                     pd->ps->exchange_base_url,
                     &pd->section[strlen ("kyc-provider-")],
                     payto_s);
    body = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_object_steal (
        "data",
        GNUNET_JSON_PACK (
          GNUNET_JSON_pack_object_steal (
            "attributes",
            GNUNET_JSON_PACK (
              GNUNET_JSON_pack_string ("inquiry_template_id",
                                       pd->template_id),
              GNUNET_JSON_pack_string ("reference_id",
                                       ref_s),
              GNUNET_JSON_pack_string ("redirect_uri",
                                       proof_url)
              )))));
    GNUNET_assert (NULL != body);
    GNUNET_free (payto_s);
    GNUNET_free (proof_url);
  }
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
  ih->ctx.disable_compression = true;
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
  {
    char *ikh;

    GNUNET_asprintf (&ikh,
                     "Idempotency-Key: %llu-%s",
                     (unsigned long long) ih->legitimization_uuid,
                     pd->salt);
    ih->slist = curl_slist_append (NULL,
                                   ikh);
    GNUNET_free (ikh);
  }
  GNUNET_CURL_extend_headers (ih->job,
                              ih->slist);
  return ih;
}


/**
 * Cancel KYC proof.
 *
 * @param[in] ph handle of operation to cancel
 */
static void
persona_proof_cancel (struct TALER_KYCLOGIC_ProofHandle *ph)
{
  if (NULL != ph->job)
  {
    GNUNET_CURL_job_cancel (ph->job);
    ph->job = NULL;
  }
  if (NULL != ph->ec)
  {
    TALER_JSON_external_conversion_stop (ph->ec);
    ph->ec = NULL;
  }
  GNUNET_free (ph->url);
  GNUNET_free (ph->provider_user_id);
  GNUNET_free (ph->account_id);
  GNUNET_free (ph->inquiry_id);
  GNUNET_free (ph);
}


/**
 * Call @a ph callback with the operation result.
 *
 * @param ph proof handle to generate reply for
 * @param status status to return
 * @param account_id account to return
 * @param inquiry_id inquiry ID to supply
 * @param http_status HTTP status to use
 * @param template template to instantiate
 * @param[in] body body for the template to use (reference
 *         is consumed)
 */
static void
proof_generic_reply (struct TALER_KYCLOGIC_ProofHandle *ph,
                     enum TALER_KYCLOGIC_KycStatus status,
                     const char *account_id,
                     const char *inquiry_id,
                     unsigned int http_status,
                     const char *template,
                     json_t *body)
{
  struct MHD_Response *resp;
  enum GNUNET_GenericReturnValue ret;

  /* This API is not usable for successful replies */
  GNUNET_assert (TALER_KYCLOGIC_STATUS_SUCCESS != status);
  ret = TALER_TEMPLATING_build (ph->connection,
                                &http_status,
                                template,
                                NULL,
                                NULL,
                                body,
                                &resp);
  json_decref (body);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    resp = NULL; /* good luck */
  }
  ph->cb (ph->cb_cls,
          status,
          account_id,
          inquiry_id,
          GNUNET_TIME_UNIT_ZERO_ABS,
          NULL,
          http_status,
          resp);
}


/**
 * Call @a ph callback with HTTP error response.
 *
 * @param ph proof handle to generate reply for
 * @param inquiry_id inquiry ID to supply
 * @param http_status HTTP status to use
 * @param template template to instantiate
 * @param[in] body body for the template to use (reference
 *         is consumed)
 */
static void
proof_reply_error (struct TALER_KYCLOGIC_ProofHandle *ph,
                   const char *inquiry_id,
                   unsigned int http_status,
                   const char *template,
                   json_t *body)
{
  proof_generic_reply (ph,
                       TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
                       NULL, /* user id */
                       inquiry_id,
                       http_status,
                       template,
                       body);
}


/**
 * Return a response for the @a ph request indicating a
 * protocol violation by the Persona server.
 *
 * @param[in,out] ph request we are processing
 * @param response_code HTTP status returned by Persona
 * @param inquiry_id ID of the inquiry this is about
 * @param detail where the response was wrong
 * @param data full response data to output
 */
static void
return_invalid_response (struct TALER_KYCLOGIC_ProofHandle *ph,
                         unsigned int response_code,
                         const char *inquiry_id,
                         const char *detail,
                         const json_t *data)
{
  proof_reply_error (
    ph,
    inquiry_id,
    MHD_HTTP_BAD_GATEWAY,
    "persona-invalid-response",
    GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("persona_http_status",
                               response_code),
      GNUNET_JSON_pack_string ("persona_inquiry_id",
                               inquiry_id),
      TALER_JSON_pack_ec (
        TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY),
      GNUNET_JSON_pack_string ("detail",
                               detail),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("data",
                                        (json_t *)
                                        data))));
}


/**
 * Start the external conversion helper.
 *
 * @param pd configuration details
 * @param attr attributes to give to the helper
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle for the helper
 */
static struct TALER_JSON_ExternalConversion *
start_conversion (const struct TALER_KYCLOGIC_ProviderDetails *pd,
                  const json_t *attr,
                  TALER_JSON_JsonCallback cb,
                  void *cb_cls)
{
  const char *argv[] = {
    pd->conversion_binary,
    "-a",
    pd->auth_token,
    NULL,
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Calling converter `%s' with JSON\n",
              pd->conversion_binary);
  json_dumpf (attr,
              stderr,
              JSON_INDENT (2));
  return TALER_JSON_external_conversion_start (
    attr,
    cb,
    cb_cls,
    pd->conversion_binary,
    argv);
}


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure with a `struct TALER_KYCLOGIC_ProofHandle *`
 * @param status_type how did the process die
 * @param code termination status code from the process
 * @param attr result some JSON result, NULL if we failed to get an JSON output
 */
static void
proof_post_conversion_cb (void *cls,
                          enum GNUNET_OS_ProcessStatusType status_type,
                          unsigned long code,
                          const json_t *attr)
{
  struct TALER_KYCLOGIC_ProofHandle *ph = cls;
  struct MHD_Response *resp;
  struct GNUNET_TIME_Absolute expiration;

  ph->ec = NULL;
  if ( (NULL == attr) ||
       (0 != code) )
  {
    GNUNET_break_op (0);
    return_invalid_response (ph,
                             MHD_HTTP_OK,
                             ph->inquiry_id,
                             "converter",
                             NULL);
    persona_proof_cancel (ph);
    return;
  }
  expiration = GNUNET_TIME_relative_to_absolute (ph->pd->validity);
  resp = MHD_create_response_from_buffer_static (0,
                                                 "");
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_LOCATION,
                                         ph->pd->post_kyc_redirect_url));
  TALER_MHD_add_global_headers (resp);
  ph->cb (ph->cb_cls,
          TALER_KYCLOGIC_STATUS_SUCCESS,
          ph->account_id,
          ph->inquiry_id,
          expiration,
          attr,
          MHD_HTTP_SEE_OTHER,
          resp);
  persona_proof_cancel (ph);
}


/**
 * Function called when we're done processing the
 * HTTP "/api/v1/inquiries/{inquiry-id}" request.
 *
 * @param cls the `struct TALER_KYCLOGIC_InitiateHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_proof_finished (void *cls,
                       long response_code,
                       const void *response)
{
  struct TALER_KYCLOGIC_ProofHandle *ph = cls;
  const json_t *j = response;
  const json_t *data = json_object_get (j,
                                        "data");

  ph->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *inquiry_id;
      const char *account_id;
      const char *type = NULL;
      const json_t *attributes;
      const json_t *relationships;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("type",
                                 &type),
        GNUNET_JSON_spec_string ("id",
                                 &inquiry_id),
        GNUNET_JSON_spec_object_const ("attributes",
                                       &attributes),
        GNUNET_JSON_spec_object_const ("relationships",
                                       &relationships),
        GNUNET_JSON_spec_end ()
      };

      if ( (NULL == data) ||
           (GNUNET_OK !=
            GNUNET_JSON_parse (data,
                               spec,
                               NULL, NULL)) ||
           (0 != strcasecmp (type,
                             "inquiry")) )
      {
        GNUNET_break_op (0);
        return_invalid_response (ph,
                                 response_code,
                                 inquiry_id,
                                 "data",
                                 data);
        break;
      }

      {
        const char *status; /* "completed", what else? */
        const char *reference_id; /* or legitimization number */
        const char *expired_at = NULL; /* often 'null' format: "2022-08-18T10:14:26.000Z" */
        struct GNUNET_JSON_Specification ispec[] = {
          GNUNET_JSON_spec_string ("status",
                                   &status),
          GNUNET_JSON_spec_string ("reference-id",
                                   &reference_id),
          GNUNET_JSON_spec_mark_optional (
            GNUNET_JSON_spec_string ("expired-at",
                                     &expired_at),
            NULL),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (attributes,
                               ispec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          return_invalid_response (ph,
                                   response_code,
                                   inquiry_id,
                                   "data-attributes",
                                   data);
          break;
        }
        {
          unsigned long long idr;
          char dummy;

          if ( (1 != sscanf (reference_id,
                             "%llu%c",
                             &idr,
                             &dummy)) ||
               (idr != ph->process_row) )
          {
            GNUNET_break_op (0);
            return_invalid_response (ph,
                                     response_code,
                                     inquiry_id,
                                     "data-attributes-reference_id",
                                     data);
            break;
          }
        }

        if (0 != strcmp (inquiry_id,
                         ph->inquiry_id))
        {
          GNUNET_break_op (0);
          return_invalid_response (ph,
                                   response_code,
                                   inquiry_id,
                                   "data-id",
                                   data);
          break;
        }

        account_id = json_string_value (
          json_object_get (
            json_object_get (
              json_object_get (
                relationships,
                "account"),
              "data"),
            "id"));

        if (0 != strcasecmp (status,
                             "completed"))
        {
          proof_generic_reply (
            ph,
            TALER_KYCLOGIC_STATUS_FAILED,
            account_id,
            inquiry_id,
            MHD_HTTP_OK,
            "persona-kyc-failed",
            GNUNET_JSON_PACK (
              GNUNET_JSON_pack_uint64 ("persona_http_status",
                                       response_code),
              GNUNET_JSON_pack_string ("persona_inquiry_id",
                                       inquiry_id),
              GNUNET_JSON_pack_allow_null (
                GNUNET_JSON_pack_object_incref ("data",
                                                (json_t *)
                                                data))));
          break;
        }

        if (NULL == account_id)
        {
          GNUNET_break_op (0);
          return_invalid_response (ph,
                                   response_code,
                                   inquiry_id,
                                   "data-relationships-account-data-id",
                                   data);
          break;
        }
        ph->account_id = GNUNET_strdup (account_id);
        ph->ec = start_conversion (ph->pd,
                                   j,
                                   &proof_post_conversion_cb,
                                   ph);
        if (NULL == ph->ec)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Failed to start Persona conversion helper\n");
          proof_reply_error (
            ph,
            ph->inquiry_id,
            MHD_HTTP_BAD_GATEWAY,
            "persona-logic-failure",
            GNUNET_JSON_PACK (
              TALER_JSON_pack_ec (
                TALER_EC_EXCHANGE_GENERIC_KYC_CONVERTER_FAILED)));
          break;
        }
      }
      return; /* continued in proof_post_conversion_cb */
    }
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
  case MHD_HTTP_UNPROCESSABLE_ENTITY:
    /* These are errors with this code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_BAD_GATEWAY,
      "persona-logic-failure",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY),

        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* These are failures of the exchange operator */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Refused access with HTTP status code %u\n",
                (unsigned int) response_code);
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_BAD_GATEWAY,
      "persona-exchange-unauthorized",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_ACCESS_REFUSED),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  case MHD_HTTP_PAYMENT_REQUIRED:
    /* These are failures of the exchange operator */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Refused access with HTTP status code %u\n",
                (unsigned int) response_code);
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_SERVICE_UNAVAILABLE,
      "persona-exchange-unpaid",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_ACCESS_REFUSED),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  case MHD_HTTP_REQUEST_TIMEOUT:
    /* These are networking issues */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_GATEWAY_TIMEOUT,
      "persona-network-timeout",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_TIMEOUT),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  case MHD_HTTP_TOO_MANY_REQUESTS:
    /* This is a load issue */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_SERVICE_UNAVAILABLE,
      "persona-load-failure",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_RATE_LIMIT_EXCEEDED),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* This is an issue with Persona */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_BAD_GATEWAY,
      "persona-provider-failure",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_ERROR),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  default:
    /* This is an issue with Persona */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    proof_reply_error (
      ph,
      ph->inquiry_id,
      MHD_HTTP_BAD_GATEWAY,
      "persona-invalid-response",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("persona_http_status",
                                 response_code),
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("data",
                                          (json_t *)
                                          data))));
    break;
  }
  persona_proof_cancel (ph);
}


/**
 * Check KYC status and return final result to human.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param connection MHD connection object (for HTTP headers)
 * @param account_id which account to trigger process for
 * @param process_row row in the legitimization processes table the legitimization is for
 * @param provider_user_id user ID (or NULL) the proof is for
 * @param inquiry_id legitimization ID the proof is for
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_ProofHandle *
persona_proof (void *cls,
               const struct TALER_KYCLOGIC_ProviderDetails *pd,
               struct MHD_Connection *connection,
               const struct TALER_PaytoHashP *account_id,
               uint64_t process_row,
               const char *provider_user_id,
               const char *inquiry_id,
               TALER_KYCLOGIC_ProofCallback cb,
               void *cb_cls)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_ProofHandle *ph;
  CURL *eh;

  eh = curl_easy_init ();
  if (NULL == eh)
  {
    GNUNET_break (0);
    return NULL;
  }
  ph = GNUNET_new (struct TALER_KYCLOGIC_ProofHandle);
  ph->ps = ps;
  ph->pd = pd;
  ph->cb = cb;
  ph->cb_cls = cb_cls;
  ph->connection = connection;
  ph->process_row = process_row;
  ph->h_payto = *account_id;
  /* Note: we do not expect this to be non-NULL */
  if (NULL != provider_user_id)
    ph->provider_user_id = GNUNET_strdup (provider_user_id);
  if (NULL != inquiry_id)
    ph->inquiry_id = GNUNET_strdup (inquiry_id);
  GNUNET_asprintf (&ph->url,
                   "https://withpersona.com/api/v1/inquiries/%s",
                   inquiry_id);
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
                                  ph->url));
  ph->job = GNUNET_CURL_job_add2 (ps->curl_ctx,
                                  eh,
                                  pd->slist,
                                  &handle_proof_finished,
                                  ph);
  return ph;
}


/**
 * Cancel KYC webhook execution.
 *
 * @param[in] wh handle of operation to cancel
 */
static void
persona_webhook_cancel (struct TALER_KYCLOGIC_WebhookHandle *wh)
{
  if (NULL != wh->task)
  {
    GNUNET_SCHEDULER_cancel (wh->task);
    wh->task = NULL;
  }
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  if (NULL != wh->ec)
  {
    TALER_JSON_external_conversion_stop (wh->ec);
    wh->ec = NULL;
  }
  GNUNET_free (wh->account_id);
  GNUNET_free (wh->inquiry_id);
  GNUNET_free (wh->url);
  GNUNET_free (wh);
}


/**
 * Call @a wh callback with the operation result.
 *
 * @param wh proof handle to generate reply for
 * @param status status to return
 * @param account_id account to return
 * @param inquiry_id inquiry ID to supply
 * @param attr KYC attribute data for the client
 * @param http_status HTTP status to use
 */
static void
webhook_generic_reply (struct TALER_KYCLOGIC_WebhookHandle *wh,
                       enum TALER_KYCLOGIC_KycStatus status,
                       const char *account_id,
                       const char *inquiry_id,
                       const json_t *attr,
                       unsigned int http_status)
{
  struct MHD_Response *resp;
  struct GNUNET_TIME_Absolute expiration;

  if (TALER_KYCLOGIC_STATUS_SUCCESS == status)
    expiration = GNUNET_TIME_relative_to_absolute (wh->pd->validity);
  else
    expiration = GNUNET_TIME_UNIT_ZERO_ABS;
  resp = MHD_create_response_from_buffer_static (0,
                                                 "");
  TALER_MHD_add_global_headers (resp);
  wh->cb (wh->cb_cls,
          wh->process_row,
          &wh->h_payto,
          wh->pd->section,
          account_id,
          inquiry_id,
          status,
          expiration,
          attr,
          http_status,
          resp);
}


/**
 * Call @a wh callback with HTTP error response.
 *
 * @param wh proof handle to generate reply for
 * @param inquiry_id inquiry ID to supply
 * @param http_status HTTP status to use
 */
static void
webhook_reply_error (struct TALER_KYCLOGIC_WebhookHandle *wh,
                     const char *inquiry_id,
                     unsigned int http_status)
{
  webhook_generic_reply (wh,
                         TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
                         NULL, /* user id */
                         inquiry_id,
                         NULL, /* attributes */
                         http_status);
}


/**
 * Type of a callback that receives a JSON @a result.
 *
 * @param cls closure with a `struct TALER_KYCLOGIC_WebhookHandle *`
 * @param status_type how did the process die
 * @param code termination status code from the process
 * @param attr some JSON result, NULL if we failed to get an JSON output
 */
static void
webhook_post_conversion_cb (void *cls,
                            enum GNUNET_OS_ProcessStatusType status_type,
                            unsigned long code,
                            const json_t *attr)
{
  struct TALER_KYCLOGIC_WebhookHandle *wh = cls;

  wh->ec = NULL;
  webhook_generic_reply (wh,
                         TALER_KYCLOGIC_STATUS_SUCCESS,
                         wh->account_id,
                         wh->inquiry_id,
                         attr,
                         MHD_HTTP_OK);
}


/**
 * Function called when we're done processing the
 * HTTP "/api/v1/inquiries/{inquiry_id}" request.
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
  const json_t *data = json_object_get (j,
                                        "data");

  wh->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *inquiry_id;
      const char *account_id;
      const char *type = NULL;
      const json_t *attributes;
      const json_t *relationships;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("type",
                                 &type),
        GNUNET_JSON_spec_string ("id",
                                 &inquiry_id),
        GNUNET_JSON_spec_object_const ("attributes",
                                       &attributes),
        GNUNET_JSON_spec_object_const ("relationships",
                                       &relationships),
        GNUNET_JSON_spec_end ()
      };

      if ( (NULL == data) ||
           (GNUNET_OK !=
            GNUNET_JSON_parse (data,
                               spec,
                               NULL, NULL)) ||
           (0 != strcasecmp (type,
                             "inquiry")) )
      {
        GNUNET_break_op (0);
        json_dumpf (j,
                    stderr,
                    JSON_INDENT (2));
        webhook_reply_error (wh,
                             inquiry_id,
                             MHD_HTTP_BAD_GATEWAY);
        break;
      }

      {
        const char *status; /* "completed", what else? */
        const char *reference_id; /* or legitimization number */
        const char *expired_at = NULL; /* often 'null' format: "2022-08-18T10:14:26.000Z" */
        struct GNUNET_JSON_Specification ispec[] = {
          GNUNET_JSON_spec_string ("status",
                                   &status),
          GNUNET_JSON_spec_string ("reference-id",
                                   &reference_id),
          GNUNET_JSON_spec_mark_optional (
            GNUNET_JSON_spec_string ("expired-at",
                                     &expired_at),
            NULL),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (attributes,
                               ispec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          json_dumpf (j,
                      stderr,
                      JSON_INDENT (2));
          webhook_reply_error (wh,
                               inquiry_id,
                               MHD_HTTP_BAD_GATEWAY);
          break;
        }
        {
          unsigned long long idr;
          char dummy;

          if ( (1 != sscanf (reference_id,
                             "%llu%c",
                             &idr,
                             &dummy)) ||
               (idr != wh->process_row) )
          {
            GNUNET_break_op (0);
            webhook_reply_error (wh,
                                 inquiry_id,
                                 MHD_HTTP_BAD_GATEWAY);
            break;
          }
        }

        if (0 != strcmp (inquiry_id,
                         wh->inquiry_id))
        {
          GNUNET_break_op (0);
          webhook_reply_error (wh,
                               inquiry_id,
                               MHD_HTTP_BAD_GATEWAY);
          break;
        }

        account_id = json_string_value (
          json_object_get (
            json_object_get (
              json_object_get (
                relationships,
                "account"),
              "data"),
            "id"));

        if (0 != strcasecmp (status,
                             "completed"))
        {
          webhook_generic_reply (wh,
                                 TALER_KYCLOGIC_STATUS_FAILED,
                                 account_id,
                                 inquiry_id,
                                 NULL,
                                 MHD_HTTP_OK);
          break;
        }

        if (NULL == account_id)
        {
          GNUNET_break_op (0);
          json_dumpf (data,
                      stderr,
                      JSON_INDENT (2));
          webhook_reply_error (wh,
                               inquiry_id,
                               MHD_HTTP_BAD_GATEWAY);
          break;
        }
        wh->account_id = GNUNET_strdup (account_id);
        wh->ec = start_conversion (wh->pd,
                                   j,
                                   &webhook_post_conversion_cb,
                                   wh);
        if (NULL == wh->ec)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Failed to start Persona conversion helper\n");
          webhook_reply_error (wh,
                               inquiry_id,
                               MHD_HTTP_INTERNAL_SERVER_ERROR);
          break;
        }
      }
      return; /* continued in webhook_post_conversion_cb */
    }
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
  case MHD_HTTP_UNPROCESSABLE_ENTITY:
    /* These are errors with this code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_BAD_GATEWAY);
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* These are failures of the exchange operator */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Refused access with HTTP status code %u\n",
                (unsigned int) response_code);
    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_INTERNAL_SERVER_ERROR);
    break;
  case MHD_HTTP_PAYMENT_REQUIRED:
    /* These are failures of the exchange operator */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Refused access with HTTP status code %u\n",
                (unsigned int) response_code);

    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_INTERNAL_SERVER_ERROR);
    break;
  case MHD_HTTP_REQUEST_TIMEOUT:
    /* These are networking issues */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_GATEWAY_TIMEOUT);
    break;
  case MHD_HTTP_TOO_MANY_REQUESTS:
    /* This is a load issue */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_SERVICE_UNAVAILABLE);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* This is an issue with Persona */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_BAD_GATEWAY);
    break;
  default:
    /* This is an issue with Persona */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "PERSONA failed with response %u:\n",
                (unsigned int) response_code);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    webhook_reply_error (wh,
                         wh->inquiry_id,
                         MHD_HTTP_BAD_GATEWAY);
    break;
  }

  persona_webhook_cancel (wh);
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
          NULL,
          wh->inquiry_id, /* provider legi ID */
          TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
          GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
          NULL,
          wh->response_code,
          wh->resp);
  persona_webhook_cancel (wh);
}


/**
 * Function called with the provider details and
 * associated plugin closures for matching logics.
 *
 * @param cls closure
 * @param pd provider details of a matching logic
 * @param plugin_cls closure of the plugin
 * @return #GNUNET_OK to continue to iterate
 */
static enum GNUNET_GenericReturnValue
locate_details_cb (
  void *cls,
  const struct TALER_KYCLOGIC_ProviderDetails *pd,
  void *plugin_cls)
{
  struct TALER_KYCLOGIC_WebhookHandle *wh = cls;

  /* This type-checks 'pd' */
  GNUNET_assert (plugin_cls == wh->ps);
  if (0 == strcmp (pd->template_id,
                   wh->template_id))
  {
    wh->pd = pd;
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Check KYC status and return result for Webhook.  We do NOT implement the
 * authentication check proposed by the PERSONA documentation, as it would
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
persona_webhook (void *cls,
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
  enum GNUNET_DB_QueryStatus qs;
  const char *persona_inquiry_id;
  const char *auth_header;

  /* Persona webhooks are expected by logic, not by template */
  GNUNET_break_op (NULL == pd);
  wh = GNUNET_new (struct TALER_KYCLOGIC_WebhookHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ps = ps;
  wh->connection = connection;
  wh->pd = pd;
  auth_header = MHD_lookup_connection_value (connection,
                                             MHD_HEADER_KIND,
                                             MHD_HTTP_HEADER_AUTHORIZATION);
  if ( (NULL != ps->webhook_token) &&
       ( (NULL == auth_header) ||
         (0 != strcmp (ps->webhook_token,
                       auth_header)) ) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Invalid authorization header `%s' received for Persona webhook\n",
                auth_header);
    wh->resp = TALER_MHD_MAKE_JSON_PACK (
      TALER_JSON_pack_ec (
        TALER_EC_EXCHANGE_KYC_WEBHOOK_UNAUTHORIZED),
      GNUNET_JSON_pack_string ("detail",
                               "unexpected 'Authorization' header"));
    wh->response_code = MHD_HTTP_UNAUTHORIZED;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }

  wh->template_id
    = json_string_value (
        json_object_get (
          json_object_get (
            json_object_get (
              json_object_get (
                json_object_get (
                  json_object_get (
                    json_object_get (
                      json_object_get (
                        body,
                        "data"),
                      "attributes"),
                    "payload"),
                  "data"),
                "relationships"),
              "inquiry-template"),
            "data"),
          "id"));
  if (NULL == wh->template_id)
  {
    GNUNET_break_op (0);
    json_dumpf (body,
                stderr,
                JSON_INDENT (2));
    wh->resp = TALER_MHD_MAKE_JSON_PACK (
      TALER_JSON_pack_ec (
        TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY),
      GNUNET_JSON_pack_string ("detail",
                               "data-attributes-payload-data-id"),
      GNUNET_JSON_pack_object_incref ("webhook_body",
                                      (json_t *) body));
    wh->response_code = MHD_HTTP_BAD_REQUEST;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }
  TALER_KYCLOGIC_kyc_get_details ("persona",
                                  &locate_details_cb,
                                  wh);
  if (NULL == wh->pd)
  {
    GNUNET_break_op (0);
    json_dumpf (body,
                stderr,
                JSON_INDENT (2));
    wh->resp = TALER_MHD_MAKE_JSON_PACK (
      TALER_JSON_pack_ec (
        TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN),
      GNUNET_JSON_pack_string ("detail",
                               wh->template_id),
      GNUNET_JSON_pack_object_incref ("webhook_body",
                                      (json_t *) body));
    wh->response_code = MHD_HTTP_BAD_REQUEST;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }

  persona_inquiry_id
    = json_string_value (
        json_object_get (
          json_object_get (
            json_object_get (
              json_object_get (
                json_object_get (
                  body,
                  "data"),
                "attributes"),
              "payload"),
            "data"),
          "id"));
  if (NULL == persona_inquiry_id)
  {
    GNUNET_break_op (0);
    json_dumpf (body,
                stderr,
                JSON_INDENT (2));
    wh->resp = TALER_MHD_MAKE_JSON_PACK (
      TALER_JSON_pack_ec (
        TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_UNEXPECTED_REPLY),
      GNUNET_JSON_pack_string ("detail",
                               "data-attributes-payload-data-id"),
      GNUNET_JSON_pack_object_incref ("webhook_body",
                                      (json_t *) body));
    wh->response_code = MHD_HTTP_BAD_REQUEST;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }
  qs = plc (plc_cls,
            wh->pd->section,
            persona_inquiry_id,
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
                "Received Persona kyc-webhook for unknown verification ID `%s'\n",
                persona_inquiry_id);
    wh->resp = TALER_MHD_make_error (
      TALER_EC_EXCHANGE_KYC_PROOF_REQUEST_UNKNOWN,
      persona_inquiry_id);
    wh->response_code = MHD_HTTP_NOT_FOUND;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }
  wh->inquiry_id = GNUNET_strdup (persona_inquiry_id);

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
                   "https://withpersona.com/api/v1/inquiries/%s",
                   persona_inquiry_id);
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
                                  wh->pd->slist,
                                  &handle_webhook_finished,
                                  wh);
  return wh;
}


/**
 * Initialize persona logic plugin
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_KYCLOGIC_Plugin`
 */
void *
libtaler_plugin_kyclogic_persona_init (void *cls);

/* declaration to avoid compiler warning */
void *
libtaler_plugin_kyclogic_persona_init (void *cls)
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
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             "kyclogic-persona",
                                             "WEBHOOK_AUTH_TOKEN",
                                             &ps->webhook_token))
  {
    /* optional */
    ps->webhook_token = NULL;
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
    = &persona_load_configuration;
  plugin->unload_configuration
    = &persona_unload_configuration;
  plugin->initiate
    = &persona_initiate;
  plugin->initiate_cancel
    = &persona_initiate_cancel;
  plugin->proof
    = &persona_proof;
  plugin->proof_cancel
    = &persona_proof_cancel;
  plugin->webhook
    = &persona_webhook;
  plugin->webhook_cancel
    = &persona_webhook_cancel;
  return plugin;
}


/**
 * Unload authorization plugin
 *
 * @param cls a `struct TALER_KYCLOGIC_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_kyclogic_persona_done (void *cls);

/* declaration to avoid compiler warning */

void *
libtaler_plugin_kyclogic_persona_done (void *cls)
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
  GNUNET_free (ps->webhook_token);
  GNUNET_free (ps);
  GNUNET_free (plugin);
  return NULL;
}


/* end of plugin_kyclogic_persona.c */
