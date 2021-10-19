/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-proof.c
 * @brief Handle request for proof for KYC check.
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
#include "taler-exchange-httpd_kyc-proof.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the proof.
 */
struct KycProofContext
{

  /**
   * Kept in a DLL while suspended.
   */
  struct KycProofContext *next;

  /**
   * Kept in a DLL while suspended.
   */
  struct KycProofContext *prev;

  /**
   * Details about the connection we are processing.
   */
  struct TEH_RequestContext *rc;

  /**
   * Handle for the OAuth 2.0 CURL request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * OAuth 2.0 authorization code.
   */
  const char *authorization_code;

  /**
   * OAuth 2.0 token URL we are using for the
   * request.
   */
  char *token_url;

  /**
   * Body of the POST request.
   */
  char *post_body;

  /**
   * Payment target this is about.
   */
  unsigned long long payment_target_uuid;

  /**
   * HTTP response to return.
   */
  struct MHD_Response *response;

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
static struct KycProofContext *kpc_head;

/**
 * Contexts are kept in a DLL while suspended.
 */
static struct KycProofContext *kpc_tail;


void
TEH_kyc_proof_cleanup (void)
{
  struct KycProofContext *kpc;

  while (NULL != (kpc = kpc_head))
  {
    if (NULL != kpc->job)
    {
      GNUNET_CURL_job_cancel (kpc->job);
      kpc->job = NULL;
    }
    GNUNET_CONTAINER_DLL_remove (kpc_head,
                                 kpc_tail,
                                 kpc);
    kpc->suspended = GNUNET_NO;
    MHD_resume_connection (kpc->rc->connection);
  }
}


/**
 * Function implementing database transaction to check proof's KYC status.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct KycProofContext *`
 * @param connection MHD proof which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
persist_kyc_ok (void *cls,
                struct MHD_Connection *connection,
                MHD_RESULT *mhd_ret)
{
  struct KycProofContext *kpc = cls;

  return TEH_plugin->set_kyc_ok (TEH_plugin->cls,
                                 kpc->payment_target_uuid);
}


/**
 * After we are done with the CURL interaction we
 * need to update our database state.
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
  struct KycProofContext *kpc = cls;
  const json_t *j = response;

  kpc->job = NULL;
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
          kpc->response
            = TALER_MHD_make_error (
                TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
                "Unexpected response from KYC gateway");
          kpc->response_code
            = MHD_HTTP_BAD_GATEWAY;
          MHD_resume_connection (kpc->rc->connection);
          TALER_MHD_daemon_trigger ();
          return;
        }
      }
      if (0 != strcasecmp (token_type,
                           "bearer"))
      {
        GNUNET_break_op (0);
        kpc->response
          = TALER_MHD_make_error (
              TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
              "Unexpected token type in response from KYC gateway");
        kpc->response_code
          = MHD_HTTP_BAD_GATEWAY;
        MHD_resume_connection (kpc->rc->connection);
        TALER_MHD_daemon_trigger ();
        return;
      }

      /* TODO: Here we might want to keep something to persist in the DB, and
         possibly use the access_token to download information we should
         persist; then continue! */

      MHD_resume_connection (kpc->rc->connection);
      TALER_MHD_daemon_trigger ();
      return;
    }
  default:
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
          kpc->response
            = TALER_MHD_make_error (
                TALER_EC_EXCHANGE_KYC_PROOF_BACKEND_INVALID_RESPONSE,
                "Unexpected response from KYC gateway");
          kpc->response_code
            = MHD_HTTP_BAD_GATEWAY;
          MHD_resume_connection (kpc->rc->connection);
          TALER_MHD_daemon_trigger ();
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
        kpc->response
          = MHD_create_response_from_buffer (strlen (reply),
                                             reply,
                                             MHD_RESPMEM_MUST_COPY);
        GNUNET_assert (NULL != kpc->response);
        GNUNET_free (reply);
      }
      kpc->response_code = MHD_HTTP_FORBIDDEN;
      MHD_resume_connection (kpc->rc->connection);
      TALER_MHD_daemon_trigger ();
    }
    break;
  }
}


/**
 * Function called to clean up a context.
 *
 * @param rc request context
 */
static void
clean_kpc (struct TEH_RequestContext *rc)
{
  struct KycProofContext *kpc = rc->rh_ctx;

  if (NULL != kpc->job)
  {
    GNUNET_CURL_job_cancel (kpc->job);
    kpc->job = NULL;
  }
  if (NULL != kpc->response)
  {
    MHD_destroy_response (kpc->response);
    kpc->response = NULL;
  }
  GNUNET_free (kpc->post_body);
  GNUNET_free (kpc->token_url);
  GNUNET_free (kpc);
}


MHD_RESULT
TEH_handler_kyc_proof (
  struct TEH_RequestContext *rc,
  const char *const args[])
{
  struct KycProofContext *kpc = rc->rh_ctx;

  if (NULL == kpc)
  { /* first time */
    char dummy;

    kpc = GNUNET_new (struct KycProofContext);
    kpc->rc = rc;
    rc->rh_ctx = kpc;
    rc->rh_cleaner = &clean_kpc;

    if (1 !=
        sscanf (args[0],
                "%llu%c",
                &kpc->payment_target_uuid,
                &dummy))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         "payment_target_uuid");
    }
    kpc->authorization_code
      = MHD_lookup_connection_value (rc->connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "code");
    if (NULL == kpc->authorization_code)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         "code");
    }
    if (TEH_KYC_NONE == TEH_kyc_config.mode)
      return TALER_MHD_reply_static (
        rc->connection,
        MHD_HTTP_NO_CONTENT,
        NULL,
        NULL,
        0);

    {
      CURL *eh;

      eh = curl_easy_init ();
      if (NULL == eh)
      {
        GNUNET_break (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_ALLOCATION_FAILURE,
                                           "curl_easy_init");
      }
      GNUNET_asprintf (&kpc->token_url,
                       "%s/token",
                       TEH_kyc_config.details.oauth2.url);
      GNUNET_assert (CURLE_OK ==
                     curl_easy_setopt (eh,
                                       CURLOPT_URL,
                                       kpc->token_url));
      GNUNET_assert (CURLE_OK ==
                     curl_easy_setopt (eh,
                                       CURLOPT_POST,
                                       1));
      {
        char *client_id;
        char *redirect_uri;
        char *client_secret;
        char *authorization_code;

        client_id = curl_easy_escape (eh,
                                      TEH_kyc_config.details.oauth2.client_id,
                                      0);
        GNUNET_assert (NULL != client_id);
        {
          char *request_uri;

          GNUNET_asprintf (&request_uri,
                           "%s/login?client_id=%s",
                           TEH_kyc_config.details.oauth2.url,
                           TEH_kyc_config.details.oauth2.client_id);
          redirect_uri = curl_easy_escape (eh,
                                           request_uri,
                                           0);
          GNUNET_free (request_uri);
        }
        GNUNET_assert (NULL != redirect_uri);
        client_secret = curl_easy_escape (eh,
                                          TEH_kyc_config.details.oauth2.
                                          client_secret,
                                          0);
        GNUNET_assert (NULL != client_secret);
        authorization_code = curl_easy_escape (eh,
                                               kpc->authorization_code,
                                               0);
        GNUNET_assert (NULL != authorization_code);
        GNUNET_asprintf (&kpc->post_body,
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
                     curl_easy_setopt (eh,
                                       CURLOPT_POSTFIELDS,
                                       kpc->post_body));
      GNUNET_assert (CURLE_OK ==
                     curl_easy_setopt (eh,
                                       CURLOPT_FOLLOWLOCATION,
                                       1L));
      /* limit MAXREDIRS to 5 as a simple security measure against
         a potential infinite loop caused by a malicious target */
      GNUNET_assert (CURLE_OK ==
                     curl_easy_setopt (eh,
                                       CURLOPT_MAXREDIRS,
                                       5L));

      kpc->job = GNUNET_CURL_job_add (TEH_curl_ctx,
                                      eh,
                                      &handle_curl_login_finished,
                                      kpc);
      kpc->suspended = GNUNET_YES;
      GNUNET_CONTAINER_DLL_insert (kpc_head,
                                   kpc_tail,
                                   kpc);
      MHD_suspend_connection (rc->connection);
      return MHD_YES;
    }
  }

  if (NULL != kpc->response)
  {
    /* handle _failed_ resumed cases */
    return MHD_queue_response (rc->connection,
                               kpc->response_code,
                               kpc->response);
  }

  /* _successfully_ resumed case */
  {
    MHD_RESULT res;
    enum GNUNET_GenericReturnValue ret;

    ret = TEH_DB_run_transaction (kpc->rc->connection,
                                  "check proof kyc",
                                  &res,
                                  &persist_kyc_ok,
                                  kpc);
    if (GNUNET_SYSERR == ret)
      return res;
  }

  {
    struct MHD_Response *response;
    MHD_RESULT res;

    response = MHD_create_response_from_buffer (0,
                                                "",
                                                MHD_RESPMEM_PERSISTENT);
    if (NULL == response)
    {
      GNUNET_break (0);
      return MHD_NO;
    }
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (
                    response,
                    MHD_HTTP_HEADER_LOCATION,
                    TEH_kyc_config.details.oauth2.post_kyc_redirect_url));
    res = MHD_queue_response (rc->connection,
                              MHD_HTTP_SEE_OTHER,
                              response);
    MHD_destroy_response (response);
    return res;
  }
}


/* end of taler-exchange-httpd_kyc-proof.c */
