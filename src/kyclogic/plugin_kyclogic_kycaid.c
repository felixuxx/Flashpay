/*
  This file is part of GNU Taler
  Copyright (C) 2022 Taler Systems SA

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
   * Hash of the payto:// URI we are initiating
   * the KYC for.
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * URL of the cURL request.
   */
  char *url;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;
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
  struct TALER_PaytoHashP h_payto;

  /**
   * Row in legitimizations for the given
   * @e verification_id.
   */
  uint64_t legi_row;

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
  GNUNET_free (pd->auth_token);
  GNUNET_free (pd->form_id);
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
                                             "KYC_KYCAID_POST_URL",
                                             &pd->post_kyc_redirect_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_KYCAID_POST_URL");
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
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("verification_id",
                                 &verification_id),
        GNUNET_JSON_spec_string ("form_url",
                                 &form_url),
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
                   "https://api.kycaid.com/forms/%s/urls",
                   pd->form_id);
  body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("redirect_url",
                             pd->post_kyc_redirect_url),
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
  if (NULL != ph->job)
  {
    GNUNET_CURL_job_cancel (ph->job);
    ph->job = NULL;
  }
  GNUNET_free (ph->url);
  GNUNET_free (ph);
}


/**
 * Call @a ph callback with HTTP response generated
 * from @a template_name using the given @a template_data.
 *
 * @param ph proof handle to generate reply for
 * @param http_status http response status to use
 * @param template_name template to load and return
 * @param[in] template_data data for the template, freed by this function!
 */
static void
proof_reply_with_template (struct TALER_KYCLOGIC_ProofHandle *ph,
                           unsigned int http_status,
                           const char *template_name,
                           json_t *template_data)
{
  enum GNUNET_GenericReturnValue ret;
  struct MHD_Response *resp;

  ret = TALER_TEMPLATING_build (ph->connection,
                                &http_status,
                                template_name,
                                NULL, /* no instance */
                                NULL, /* no Taler URI */
                                template_data,
                                &resp);
  json_decref (template_data);
  if (GNUNET_SYSERR == ret)
    http_status = 0;
  ph->cb (ph->cb_cls,
          TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
          NULL, /* user id */
          NULL, /* provider legi ID */
          GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
          http_status,
          resp);
}


/**
 * Function called when we're done processing the
 * HTTP "/verifications/{verification_id}" request.
 *
 * @param cls the `struct TALER_KYCLOGIC_ProofHandle`
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
  struct MHD_Response *resp;

  ph->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *applicant_id;
      const char *verification_id;
      bool verified;
      json_t *verifications;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("applicant_id",
                                 &applicant_id),
        GNUNET_JSON_spec_string ("verification_id",
                                 &verification_id),
        GNUNET_JSON_spec_bool ("verified",
                               &verified),
        GNUNET_JSON_spec_json ("verifications",
                               &verifications),
        GNUNET_JSON_spec_end ()
      };
      struct GNUNET_TIME_Absolute expiration;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        json_t *template_data;

        GNUNET_break_op (0);
        json_dumpf (j,
                    stderr,
                    JSON_INDENT (2));
        template_data = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                          (json_t *) j));
        proof_reply_with_template (ph,
                                   MHD_HTTP_BAD_GATEWAY,
                                   "bad_gateway",
                                   template_data);
        break;
      }
      /* FIXME: comment out, unless debugging ... */
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "The provider returned the following verifications:\n");
      json_dumpf (verifications,
                  stderr,
                  JSON_INDENT (2));
      if (verified)
      {
        // FIXME: or should we return an empty body? Redirect?
        resp = TALER_MHD_make_json_steal (json_object ());
        // FIXME: setup redirect?
        expiration = GNUNET_TIME_relative_to_absolute (ph->pd->validity);
        ph->cb (ph->cb_cls,
                TALER_KYCLOGIC_STATUS_SUCCESS,
                applicant_id,
                verification_id,
                expiration,
                MHD_HTTP_OK, // OK, or redirect???
                resp);
      }
      else
      {
        json_t *template_data;

        GNUNET_break_op (0);
        json_dumpf (j,
                    stderr,
                    JSON_INDENT (2));
        template_data = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_string ("kyc_logic",
                                   "kycaid"),
          GNUNET_JSON_pack_object_incref ("verifiations",
                                          (json_t *) verifications));
        proof_reply_with_template (ph,
                                   MHD_HTTP_OK,
                                   "kyc_user_failed",
                                   template_data);
      }
      GNUNET_JSON_parse_free (spec);
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_NOT_FOUND:
  case MHD_HTTP_CONFLICT:
  case MHD_HTTP_UNPROCESSABLE_ENTITY: /* validation */
    {
      json_t *template_data;

      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "KYCAID failed with response %u:\n",
                  (unsigned int) response_code);
      json_dumpf (j,
                  stderr,
                  JSON_INDENT (2));
      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_interaction_failed",
                                 template_data);
      break;
    }
  case MHD_HTTP_UNAUTHORIZED:
    {
      json_t *template_data;

      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_provider_unauthorized",
                                 template_data);
      break;
    }
  case MHD_HTTP_PAYMENT_REQUIRED:
    {
      json_t *template_data;

      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_provider_unpaid",
                                 template_data);
      break;
    }
  case MHD_HTTP_REQUEST_TIMEOUT:
    {
      json_t *template_data;

      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_provider_timeout",
                                 template_data);
      break;
    }
  case MHD_HTTP_TOO_MANY_REQUESTS:
    {
      json_t *template_data;

      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_provider_ratelimit",
                                 template_data);
      break;
    }
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    {
      json_t *template_data;

      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_provider_internal_error",
                                 template_data);
      break;
    }
  default:
    {
      json_t *template_data;

      template_data = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_uint64 ("kyc_http_status",
                                 response_code),
        GNUNET_JSON_pack_string ("kyc_logic",
                                 "kycaid"),
        GNUNET_JSON_pack_object_incref ("kyc_server_reply",
                                        (json_t *) j));
      proof_reply_with_template (ph,
                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                 "kyc_provider_unexpected_reply",
                                 template_data);
      break;
    }
  }
  kycaid_proof_cancel (ph);
}


/**
 * Check KYC status and return status to human.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param url_path rest of the URL after `/kyc-webhook/`
 * @param connection MHD connection object (for HTTP headers)
 * @param account_id which account to trigger process for
 * @param legi_row row in the table the legitimization is for
 * @param provider_user_id user ID (or NULL) the proof is for
 * @param provider_legitimization_id legitimization ID the proof is for
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_ProofHandle *
kycaid_proof (void *cls,
              const struct TALER_KYCLOGIC_ProviderDetails *pd,
              const char *const url_path[],
              struct MHD_Connection *connection,
              const struct TALER_PaytoHashP *account_id,
              uint64_t legi_row,
              const char *provider_user_id,
              const char *provider_legitimization_id,
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
  GNUNET_asprintf (&ph->url,
                   "https://api.kycaid.com/verifications/%s",
                   provider_legitimization_id);
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  1));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_MAXREDIRS,
                                   1L));
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_URL,
                                  ph->url));
  ph->job = GNUNET_CURL_job_add (ps->curl_ctx,
                                 eh,
                                 &handle_proof_finished,
                                 ph);
  GNUNET_CURL_extend_headers (ph->job,
                              pd->slist);
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
  if (NULL != wh->job)
  {
    GNUNET_CURL_job_cancel (wh->job);
    wh->job = NULL;
  }
  GNUNET_free (wh->verification_id);
  GNUNET_free (wh->applicant_id);
  GNUNET_free (wh);
}


/**
 * Function called when we're done processing the
 * HTTP "/verifications/{verification_id}" request.
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
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *applicant_id;
      const char *verification_id;
      bool verified;
      json_t *verifications;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("applicant_id",
                                 &applicant_id),
        GNUNET_JSON_spec_string ("verification_id",
                                 &verification_id),
        GNUNET_JSON_spec_bool ("verified",
                               &verified),
        GNUNET_JSON_spec_json ("verifications",
                               &verifications),
        GNUNET_JSON_spec_end ()
      };
      struct GNUNET_TIME_Absolute expiration;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        json_dumpf (j,
                    stderr,
                    JSON_INDENT (2));
        resp = TALER_MHD_MAKE_JSON_PACK (
          GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                                   response_code),
          GNUNET_JSON_pack_object_incref ("kycaid_body",
                                          (json_t *) j));
        wh->cb (wh->cb_cls,
                wh->legi_row,
                &wh->h_payto,
                wh->applicant_id,
                wh->verification_id,
                TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
                GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
                MHD_HTTP_BAD_GATEWAY,
                resp);
        break;
      }
      /* FIXME: comment out, unless debugging ... */
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "The provider returned the following verifications:\n");
      json_dumpf (verifications,
                  stderr,
                  JSON_INDENT (2));
      if (verified)
      {
        resp = TALER_MHD_make_json_steal (json_object ());
        expiration = GNUNET_TIME_relative_to_absolute (wh->pd->validity);
        wh->cb (wh->cb_cls,
                wh->legi_row,
                &wh->h_payto,
                wh->applicant_id,
                wh->verification_id,
                TALER_KYCLOGIC_STATUS_SUCCESS,
                expiration,
                MHD_HTTP_OK,
                resp);
      }
      else
      {
        resp = TALER_MHD_make_json_steal (json_object ());
        wh->cb (wh->cb_cls,
                wh->legi_row,
                &wh->h_payto,
                wh->applicant_id,
                wh->verification_id,
                TALER_KYCLOGIC_STATUS_USER_ABORTED,
                GNUNET_TIME_UNIT_ZERO_ABS,
                MHD_HTTP_OK,
                resp);
      }
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
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("kycaid_http_status",
                               response_code));
    wh->cb (wh->cb_cls,
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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
            wh->legi_row,
            &wh->h_payto,
            wh->applicant_id,
            wh->verification_id,
            TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
            GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
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

  wh->cb (wh->cb_cls,
          0LLU, /* legitimization row ID (unknown) */
          NULL, /* our account ID */
          NULL, /* provider user ID */
          NULL, /* provider legi ID */
          TALER_KYCLOGIC_STATUS_PROVIDER_FAILED,
          GNUNET_TIME_UNIT_ZERO_ABS, /* expiration */
          wh->response_code,
          wh->resp);
  kycaid_webhook_cancel (wh);
}


/**
 * Check KYC status and return result for Webhook.
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
  const char *verification_id;
  const char *applicant_id;
  const char *status;
  bool verified;
  json_t *verifications;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("request_id",
                             &request_id),
    GNUNET_JSON_spec_string ("type",
                             &type),
    GNUNET_JSON_spec_string ("verification_id",
                             &verification_id),
    GNUNET_JSON_spec_string ("applicant_id",
                             &applicant_id),
    GNUNET_JSON_spec_string ("status",
                             &status),
    GNUNET_JSON_spec_bool ("verified",
                           &verified),
    GNUNET_JSON_spec_json ("verifications",
                           &verifications),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;

  wh = GNUNET_new (struct TALER_KYCLOGIC_WebhookHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ps = ps;
  wh->pd = pd;
  wh->connection = connection;

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
            &wh->legi_row);
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
                "Received webhook for unknown verification ID `%s'\n",
                verification_id);
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

  eh = curl_easy_init ();
  if (NULL == eh)
  {
    GNUNET_break (0);
    wh->resp = TALER_MHD_make_error (
      TALER_EC_GENERIC_ALLOCATION_FAILURE,
      verification_id);
    wh->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
    wh->task = GNUNET_SCHEDULER_add_now (&async_webhook_reply,
                                         wh);
    return wh;
  }

  GNUNET_asprintf (&wh->url,
                   "https://api.kycaid.com/verifications/%s",
                   verification_id);
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  1));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_MAXREDIRS,
                                   1L));
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_URL,
                                  wh->url));
  wh->job = GNUNET_CURL_job_add (ps->curl_ctx,
                                 eh,
                                 &handle_webhook_finished,
                                 wh);
  GNUNET_CURL_extend_headers (wh->job,
                              pd->slist);
  return wh;
}


/**
 * Initialize Kycaid.0 KYC logic plugin
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_KYCLOGIC_Plugin`
 */
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
