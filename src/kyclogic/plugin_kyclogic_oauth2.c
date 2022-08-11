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
 * @file plugin_kyclogic_oauth2.c
 * @brief oauth2.0 based authentication flow logic
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_kyclogic_plugin.h"
#include <taler/taler_mhd_lib.h>
#include <taler/taler_json_lib.h>
#include <regex.h>
#include "taler_util.h"


/**
 * Saves the state of a plugin.
 */
struct PluginState
{

  /**
   * Our global configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Our base URL.
   */
  char *exchange_base_url;

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
   * URL of the OAuth2.0 endpoint for KYC checks.
   * (token/auth)
   */
  char *auth_url;

  /**
   * URL of the OAuth2.0 endpoint for KYC checks.
   */
  char *login_url;

  /**
   * URL of the user info access endpoint.
   */
  char *info_url;

  /**
   * Our client ID for OAuth2.0.
   */
  char *client_id;

  /**
   * Our client secret for OAuth2.0.
   */
  char *client_secret;

  /**
   * Where to redirect clients after the
   * Web-based KYC process is done?
   */
  char *post_kyc_redirect_url;

  /**
   * Validity time for a successful KYC process.
   */
  struct GNUNET_TIME_Relative validity;

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
   * The task for asynchronous response generation.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Continuation to call.
   */
  TALER_KYCLOGIC_InitiateCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Handle for an KYC proof operation.
 */
struct TALER_KYCLOGIC_ProofHandle
{

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * HTTP connection we are processing.
   */
  struct MHD_Connection *connection;

  /**
   * Hash of the payto URI that this is about.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Continuation to call.
   */
  TALER_KYCLOGIC_ProofCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Curl request we are running to the OAuth 2.0 service.
   */
  CURL *eh;

  /**
   * Body for the @e eh POST request.
   */
  char *post_body;

  /**
   * Response to return.
   */
  struct MHD_Response *response;

  /**
   * The task for asynchronous response generation.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Handle for the OAuth 2.0 CURL request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * User ID to return, the 'id' from OAuth.
   */
  char *provider_user_id;

  /**
   * Legitimization ID to return, the 64-bit row ID
   * as a string.
   */
  char provider_legitimization_id[32];

  /**
   * KYC status to return.
   */
  enum TALER_KYCLOGIC_KycStatus status;

  /**
   * HTTP status to return.
   */
  unsigned int http_status;


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
};


/**
 * Release configuration resources previously loaded
 *
 * @param[in] pd configuration to release
 */
static void
oauth2_unload_configuration (struct TALER_KYCLOGIC_ProviderDetails *pd)
{
  GNUNET_free (pd->section);
  GNUNET_free (pd->auth_url);
  GNUNET_free (pd->login_url);
  GNUNET_free (pd->info_url);
  GNUNET_free (pd->client_id);
  GNUNET_free (pd->client_secret);
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
oauth2_load_configuration (void *cls,
                           const char *provider_section_name)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_ProviderDetails *pd;
  char *s;

  pd = GNUNET_new (struct TALER_KYCLOGIC_ProviderDetails);
  pd->ps = ps;
  pd->section = GNUNET_strdup (provider_section_name);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (ps->cfg,
                                           provider_section_name,
                                           "KYC_OAUTH2_VALIDITY",
                                           &pd->validity))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_VALIDITY");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_OAUTH2_AUTH_URL",
                                             &s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_AUTH_URL");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  if ( (! TALER_url_valid_charset (s)) ||
       ( (0 != strncasecmp (s,
                            "http://",
                            strlen ("http://"))) &&
         (0 != strncasecmp (s,
                            "https://",
                            strlen ("https://"))) ) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_AUTH_URL",
                               "not a valid URL");
    GNUNET_free (s);
    oauth2_unload_configuration (pd);
    return NULL;
  }
  pd->auth_url = s;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_OAUTH2_LOGIN_URL",
                                             &s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_LOGIN_URL");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  if ( (! TALER_url_valid_charset (s)) ||
       ( (0 != strncasecmp (s,
                            "http://",
                            strlen ("http://"))) &&
         (0 != strncasecmp (s,
                            "https://",
                            strlen ("https://"))) ) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_LOGIN_URL",
                               "not a valid URL");
    oauth2_unload_configuration (pd);
    GNUNET_free (s);
    return NULL;
  }
  pd->login_url = s;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_OAUTH2_INFO_URL",
                                             &s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_INFO_URL");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  if ( (! TALER_url_valid_charset (s)) ||
       ( (0 != strncasecmp (s,
                            "http://",
                            strlen ("http://"))) &&
         (0 != strncasecmp (s,
                            "https://",
                            strlen ("https://"))) ) )
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_INFO_URL",
                               "not a valid URL");
    GNUNET_free (s);
    oauth2_unload_configuration (pd);
    return NULL;
  }
  pd->info_url = s;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_OAUTH2_CLIENT_ID",
                                             &s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_CLIENT_ID");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  pd->client_id = s;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_OAUTH2_CLIENT_SECRET",
                                             &s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_CLIENT_SECRET");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  pd->client_secret = s;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ps->cfg,
                                             provider_section_name,
                                             "KYC_OAUTH2_POST_URL",
                                             &s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               provider_section_name,
                               "KYC_OAUTH2_POST_URL");
    oauth2_unload_configuration (pd);
    return NULL;
  }
  pd->post_kyc_redirect_url = s;

  return pd;
}


/**
 * Logic to asynchronously return the response for
 * how to begin the OAuth2.0 checking process to
 * the client.
 *
 * @param cls a `struct TALER_KYCLOGIC_InitiateHandle *`
 */
static void
initiate_task (void *cls)
{
  struct TALER_KYCLOGIC_InitiateHandle *ih = cls;
  const struct TALER_KYCLOGIC_ProviderDetails *pd = ih->pd;
  struct PluginState *ps = pd->ps;
  char *hps;
  char *url;
  char *redirect_uri;
  char *redirect_uri_encoded;
  char legi_s[42];

  ih->task = NULL;
  GNUNET_snprintf (legi_s,
                   sizeof (legi_s),
                   "%llu",
                   (unsigned long long) ih->legitimization_uuid);
  hps = GNUNET_STRINGS_data_to_string_alloc (&ih->h_payto,
                                             sizeof (ih->h_payto));
  GNUNET_asprintf (&redirect_uri,
                   "%s/kyc-proof/%s/%s/%s",
                   ps->exchange_base_url,
                   hps,
                   pd->section,
                   legi_s);
  redirect_uri_encoded = TALER_urlencode (redirect_uri);
  GNUNET_free (redirect_uri);
  GNUNET_asprintf (&url,
                   "%s?client_id=%s&redirect_uri=%s",
                   pd->login_url,
                   pd->client_id,
                   redirect_uri_encoded);
  GNUNET_free (redirect_uri_encoded);
  ih->cb (ih->cb_cls,
          TALER_EC_NONE,
          url,
          NULL /* unknown user_id here */,
          legi_s,
          NULL /* no error */);
  GNUNET_free (url);
  GNUNET_free (hps);
  GNUNET_free (ih);
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
oauth2_initiate (void *cls,
                 const struct TALER_KYCLOGIC_ProviderDetails *pd,
                 const struct TALER_PaytoHashP *account_id,
                 uint64_t legitimization_uuid,
                 TALER_KYCLOGIC_InitiateCallback cb,
                 void *cb_cls)
{
  struct TALER_KYCLOGIC_InitiateHandle *ih;

  ih = GNUNET_new (struct TALER_KYCLOGIC_InitiateHandle);
  ih->legitimization_uuid = legitimization_uuid;
  ih->cb = cb;
  ih->cb_cls = cb_cls;
  ih->h_payto = *account_id;
  ih->pd = pd;
  ih->task = GNUNET_SCHEDULER_add_now (&initiate_task,
                                       ih);
  return ih;
}


/**
 * Cancel KYC check initiation.
 *
 * @param[in] ih handle of operation to cancel
 */
static void
oauth2_initiate_cancel (struct TALER_KYCLOGIC_InitiateHandle *ih)
{
  if (NULL != ih->task)
  {
    GNUNET_SCHEDULER_cancel (ih->task);
    ih->task = NULL;
  }
  GNUNET_free (ih);
}


/**
 * Function called to asynchronously return the final
 * result to the callback.
 *
 * @param cls a `struct TALER_KYCLOGIC_ProofHandle`
 */
static void
return_proof_response (void *cls)
{
  struct TALER_KYCLOGIC_ProofHandle *ph = cls;

  ph->task = NULL;
  ph->cb (ph->cb_cls,
          ph->status,
          ph->provider_user_id,
          ph->provider_legitimization_id,
          GNUNET_TIME_relative_to_absolute (ph->pd->validity),
          ph->http_status,
          ph->response);
  GNUNET_free (ph->provider_user_id);
  GNUNET_free (ph);
}


/**
 * The request for @a ph failed. We may have gotten a useful error
 * message in @a j. Generate a failure response.
 *
 * @param[in,out] ph request that failed
 * @param j reply from the server (or NULL)
 */
static void
handle_proof_error (struct TALER_KYCLOGIC_ProofHandle *ph,
                    const json_t *j)
{
  const char *msg;
  const char *desc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("error",
                             &msg),
    GNUNET_JSON_spec_string ("error_description",
                             &desc),
    GNUNET_JSON_spec_end ()
  };

  {
    enum GNUNET_GenericReturnValue res;
    const char *emsg;
    unsigned int line;

    res = GNUNET_JSON_parse (j,
                             spec,
                             &emsg,
                             &line);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      ph->status = TALER_KYCLOGIC_STATUS_PROVIDER_FAILED;
      ph->response
        = TALER_MHD_make_error (
            TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
            "Unexpected response from KYC gateway");
      ph->http_status
        = MHD_HTTP_BAD_GATEWAY;
      return;
    }
  }
  /* case TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_AUTHORZATION_FAILED,
     we MAY want to in the future look at the requested content type
     and possibly respond in JSON if indicated. */
  {
    char *reply;

    GNUNET_asprintf (&reply,
                     "<html><head><title>%s</title></head><body><h1>%s</h1><p>%s</p></body></html>",
                     msg,
                     msg,
                     desc);
    ph->status = TALER_KYCLOGIC_STATUS_USER_ABORTED;
    ph->response
      = MHD_create_response_from_buffer (strlen (reply),
                                         reply,
                                         MHD_RESPMEM_MUST_COPY);
    GNUNET_assert (NULL != ph->response);
    GNUNET_free (reply);
  }
  ph->status = TALER_KYCLOGIC_STATUS_USER_ABORTED;
  ph->http_status = MHD_HTTP_FORBIDDEN;
}


/**
 * The request for @a ph succeeded (presumably).
 * Call continuation with the result.
 *
 * @param[in,out] ph request that succeeded
 * @param j reply from the server
 */
static void
parse_proof_success_reply (struct TALER_KYCLOGIC_ProofHandle *ph,
                           const json_t *j)
{
  const char *state;
  json_t *data;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("status",
                             &state),
    GNUNET_JSON_spec_json ("data",
                           &data),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_GenericReturnValue res;
  const char *emsg;
  unsigned int line;

  res = GNUNET_JSON_parse (j,
                           spec,
                           &emsg,
                           &line);
  if (GNUNET_OK != res)
  {
    GNUNET_break_op (0);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    ph->status = TALER_KYCLOGIC_STATUS_PROVIDER_FAILED;
    ph->response
      = TALER_MHD_make_error (
          TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
          "Unexpected response from KYC gateway");
    ph->http_status
      = MHD_HTTP_BAD_GATEWAY;
    return;
  }
  if (0 != strcasecmp (state,
                       "success"))
  {
    GNUNET_break_op (0);
    handle_proof_error (ph,
                        j);
    return;
  }
  {
    const char *id;
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_string ("id",
                               &id),
      GNUNET_JSON_spec_end ()
    };

    res = GNUNET_JSON_parse (data,
                             ispec,
                             &emsg,
                             &line);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      json_dumpf (data,
                  stderr,
                  JSON_INDENT (2));
      ph->status = TALER_KYCLOGIC_STATUS_PROVIDER_FAILED;
      ph->response
        = TALER_MHD_make_error (
            TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
            "Unexpected response from KYC gateway");
      ph->http_status
        = MHD_HTTP_BAD_GATEWAY;
      return;
    }
    ph->status = TALER_KYCLOGIC_STATUS_SUCCESS;
    ph->response = MHD_create_response_from_buffer (0,
                                                    "",
                                                    MHD_RESPMEM_PERSISTENT);
    GNUNET_assert (NULL != ph->response);
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (
                    ph->response,
                    MHD_HTTP_HEADER_LOCATION,
                    ph->pd->post_kyc_redirect_url));
    ph->http_status = MHD_HTTP_SEE_OTHER;
    ph->provider_user_id = GNUNET_strdup (id);
  }
}


/**
 * After we are done with the CURL interaction we
 * need to update our database state with the information
 * retrieved.
 *
 * @param cls our `struct TALER_KYCLOGIC_ProofHandle`
 * @param response_code HTTP response code from server, 0 on hard error
 * @param response in JSON, NULL if response was not in JSON format
 */
static void
handle_curl_proof_finished (void *cls,
                            long response_code,
                            const void *response)
{
  struct TALER_KYCLOGIC_ProofHandle *ph = cls;
  const json_t *j = response;

  ph->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    parse_proof_success_reply (ph,
                               j);
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "OAuth2.0 info URL returned HTTP status %u\n",
                (unsigned int) response_code);
    handle_proof_error (ph,
                        j);
    break;
  }
  ph->task = GNUNET_SCHEDULER_add_now (&return_proof_response,
                                       ph);
}


/**
 * After we are done with the CURL interaction we
 * need to fetch the user's account details.
 *
 * @param cls our `struct KycProofContext`
 * @param response_code HTTP response code from server, 0 on hard error
 * @param response in JSON, NULL if response was not in JSON format
 */
static void
handle_curl_login_finished (void *cls,
                            long response_code,
                            const void *response)
{
  struct TALER_KYCLOGIC_ProofHandle *ph = cls;
  const json_t *j = response;

  ph->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    {
      const char *access_token;
      const char *token_type;
      uint64_t expires_in_s;
      const char *refresh_token;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_string ("access_token",
                                 &access_token),
        GNUNET_JSON_spec_string ("token_type",
                                 &token_type),
        GNUNET_JSON_spec_uint64 ("expires_in",
                                 &expires_in_s),
        GNUNET_JSON_spec_string ("refresh_token",
                                 &refresh_token),
        GNUNET_JSON_spec_end ()
      };
      CURL *eh;

      {
        enum GNUNET_GenericReturnValue res;
        const char *emsg;
        unsigned int line;

        res = GNUNET_JSON_parse (j,
                                 spec,
                                 &emsg,
                                 &line);
        if (GNUNET_OK != res)
        {
          GNUNET_break_op (0);
          ph->response
            = TALER_MHD_make_error (
                TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
                "Unexpected response from KYC gateway");
          ph->http_status
            = MHD_HTTP_BAD_GATEWAY;
          break;
        }
      }
      if (0 != strcasecmp (token_type,
                           "bearer"))
      {
        GNUNET_break_op (0);
        ph->response
          = TALER_MHD_make_error (
              TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
              "Unexpected token type in response from KYC gateway");
        ph->http_status
          = MHD_HTTP_BAD_GATEWAY;
        break;
      }

      /* We guard against a few characters that could
         conceivably be abused to mess with the HTTP header */
      if ( (NULL != strchr (access_token,
                            '\n')) ||
           (NULL != strchr (access_token,
                            '\r')) ||
           (NULL != strchr (access_token,
                            ' ')) ||
           (NULL != strchr (access_token,
                            ';')) )
      {
        GNUNET_break_op (0);
        ph->response
          = TALER_MHD_make_error (
              TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
              "Illegal character in access token");
        ph->http_status
          = MHD_HTTP_BAD_GATEWAY;
        break;
      }

      eh = curl_easy_init ();
      if (NULL == eh)
      {
        GNUNET_break_op (0);
        ph->response
          = TALER_MHD_make_error (
              TALER_EC_GENERIC_ALLOCATION_FAILURE,
              "curl_easy_init");
        ph->http_status
          = MHD_HTTP_INTERNAL_SERVER_ERROR;
        break;
      }
      GNUNET_assert (CURLE_OK ==
                     curl_easy_setopt (eh,
                                       CURLOPT_URL,
                                       ph->pd->info_url));
      {
        char *hdr;
        struct curl_slist *slist;

        GNUNET_asprintf (&hdr,
                         "%s: Bearer %s",
                         MHD_HTTP_HEADER_AUTHORIZATION,
                         access_token);
        slist = curl_slist_append (NULL,
                                   hdr);
        ph->job = GNUNET_CURL_job_add2 (ph->pd->ps->curl_ctx,
                                        eh,
                                        slist,
                                        &handle_curl_proof_finished,
                                        ph);
        curl_slist_free_all (slist);
        GNUNET_free (hdr);
      }
      return;
    }
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "OAuth2.0 login URL returned HTTP status %u\n",
                (unsigned int) response_code);
    handle_proof_error (ph,
                        j);
    break;
  }
  return_proof_response (ph);
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
oauth2_proof (void *cls,
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
  const char *code;

  GNUNET_break (NULL == provider_user_id);
  ph = GNUNET_new (struct TALER_KYCLOGIC_ProofHandle);
  GNUNET_snprintf (ph->provider_legitimization_id,
                   sizeof (ph->provider_legitimization_id),
                   "%llu",
                   (unsigned long long) legi_row);
  if ( (NULL != provider_legitimization_id) &&
       (0 != strcmp (provider_legitimization_id,
                     ph->provider_legitimization_id)))
  {
    GNUNET_break (0);
    GNUNET_free (ph);
    return NULL;
  }
  ph->pd = pd;
  ph->connection = connection;
  ph->h_payto = *account_id;
  ph->cb = cb;
  ph->cb_cls = cb_cls;
  code = MHD_lookup_connection_value (connection,
                                      MHD_GET_ARGUMENT_KIND,
                                      "code");
  if (NULL == code)
  {
    GNUNET_break_op (0);
    ph->status = TALER_KYCLOGIC_STATUS_USER_PENDING;
    ph->http_status = MHD_HTTP_BAD_REQUEST;
    ph->response = TALER_MHD_make_error (
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "code");
    ph->task = GNUNET_SCHEDULER_add_now (&return_proof_response,
                                         ph);
    return ph;
  }

  ph->eh = curl_easy_init ();
  if (NULL == ph->eh)
  {
    GNUNET_break (0);
    ph->status = TALER_KYCLOGIC_STATUS_USER_PENDING;
    ph->http_status = MHD_HTTP_INTERNAL_SERVER_ERROR;
    ph->response = TALER_MHD_make_error (
      TALER_EC_GENERIC_ALLOCATION_FAILURE,
      "curl_easy_init");
    ph->task = GNUNET_SCHEDULER_add_now (&return_proof_response,
                                         ph);
    return ph;
  }

  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (ph->eh,
                                   CURLOPT_URL,
                                   pd->auth_url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (ph->eh,
                                   CURLOPT_POST,
                                   1));
  {
    char *client_id;
    char *redirect_uri;
    char *client_secret;
    char *authorization_code;

    client_id = curl_easy_escape (ph->eh,
                                  pd->client_id,
                                  0);
    GNUNET_assert (NULL != client_id);
    {
      char *request_uri;

      GNUNET_asprintf (&request_uri,
                       "%s?client_id=%s",
                       pd->login_url,
                       pd->client_id);
      redirect_uri = curl_easy_escape (ph->eh,
                                       request_uri,
                                       0);
      GNUNET_free (request_uri);
    }
    GNUNET_assert (NULL != redirect_uri);
    client_secret = curl_easy_escape (ph->eh,
                                      pd->client_secret,
                                      0);
    GNUNET_assert (NULL != client_secret);
    authorization_code = curl_easy_escape (ph->eh,
                                           code,
                                           0);
    GNUNET_assert (NULL != authorization_code);
    GNUNET_asprintf (&ph->post_body,
                     "client_id=%s&redirect_uri=%s&client_secret=%s&code=%s&grant_type=authorization_code",
                     client_id,
                     redirect_uri,
                     client_secret,
                     authorization_code);
    curl_free (authorization_code);
    curl_free (client_secret);
    curl_free (redirect_uri);
    curl_free (client_id);
  }
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (ph->eh,
                                   CURLOPT_POSTFIELDS,
                                   ph->post_body));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (ph->eh,
                                   CURLOPT_FOLLOWLOCATION,
                                   1L));
  /* limit MAXREDIRS to 5 as a simple security measure against
     a potential infinite loop caused by a malicious target */
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (ph->eh,
                                   CURLOPT_MAXREDIRS,
                                   5L));

  ph->job = GNUNET_CURL_job_add (ps->curl_ctx,
                                 ph->eh,
                                 &handle_curl_login_finished,
                                 ph);
  return ph;
}


/**
 * Cancel KYC proof.
 *
 * @param[in] ph handle of operation to cancel
 */
static void
oauth2_proof_cancel (struct TALER_KYCLOGIC_ProofHandle *ph)
{
  if (NULL != ph->task)
  {
    GNUNET_SCHEDULER_cancel (ph->task);
    ph->task = NULL;
  }
  if (NULL != ph->job)
  {
    GNUNET_CURL_job_cancel (ph->job);
    ph->job = NULL;
  }
  if (NULL != ph->response)
  {
    MHD_destroy_response (ph->response);
    ph->response = NULL;
  }
  GNUNET_free (ph->post_body);
  GNUNET_free (ph);
}


/**
 * Function to asynchronously return the 404 not found
 * page for the webhook.
 *
 * @param cls the `struct TALER_KYCLOGIC_WebhookHandle *`
 */
static void
wh_return_not_found (void *cls)
{
  struct TALER_KYCLOGIC_WebhookHandle *wh = cls;
  struct MHD_Response *response;

  wh->task = NULL;
  response = MHD_create_response_from_buffer (0,
                                              "",
                                              MHD_RESPMEM_PERSISTENT);
  wh->cb (wh->cb_cls,
          0LLU,
          NULL,
          NULL,
          NULL,
          TALER_KYCLOGIC_STATUS_KEEP,
          GNUNET_TIME_UNIT_ZERO_ABS,
          MHD_HTTP_NOT_FOUND,
          response);
  GNUNET_free (wh);
}


/**
 * Check KYC status and return result for Webhook.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param plc callback to lookup accounts with
 * @param plc_cls closure for @a plc
 * @param http_method HTTP method used for the webhook
 * @param url_path rest of the URL after `/kyc-webhook/$LOGIC/`, as NULL-terminated array
 * @param connection MHD connection object (for HTTP headers)
 * @param body HTTP request body, or NULL if not available
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_WebhookHandle *
oauth2_webhook (void *cls,
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

  wh = GNUNET_new (struct TALER_KYCLOGIC_WebhookHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ps = ps;
  wh->task = GNUNET_SCHEDULER_add_now (&wh_return_not_found,
                                       wh);
  return wh;
}


/**
 * Cancel KYC webhook execution.
 *
 * @param[in] wh handle of operation to cancel
 */
static void
oauth2_webhook_cancel (struct TALER_KYCLOGIC_WebhookHandle *wh)
{
  GNUNET_SCHEDULER_cancel (wh->task);
  GNUNET_free (wh);
}


/**
 * Initialize OAuth2.0 KYC logic plugin
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_KYCLOGIC_Plugin`
 */
void *
libtaler_plugin_kyclogic_oauth2_init (void *cls)
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
    = &oauth2_load_configuration;
  plugin->unload_configuration
    = &oauth2_unload_configuration;
  plugin->initiate
    = &oauth2_initiate;
  plugin->initiate_cancel
    = &oauth2_initiate_cancel;
  plugin->proof
    = &oauth2_proof;
  plugin->proof_cancel
    = &oauth2_proof_cancel;
  plugin->webhook
    = &oauth2_webhook;
  plugin->webhook_cancel
    = &oauth2_webhook_cancel;
  return plugin;
}


/**
 * Unload authorization plugin
 *
 * @param cls a `struct TALER_KYCLOGIC_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_kyclogic_oauth2_done (void *cls)
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
