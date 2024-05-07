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
 * @file taler-exchange-kyc-tester.c
 * @brief tool to test KYC integrations
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <sched.h>
#include <sys/resource.h>
#include <limits.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_templating_lib.h"
#include "taler_util.h"
#include "taler_kyclogic_lib.h"
#include "taler_kyclogic_plugin.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * @brief Context in which the exchange is processing
 *        all requests
 */
struct TEKT_RequestContext
{

  /**
   * Opaque parsing context.
   */
  void *opaque_post_parsing_context;

  /**
   * Request handler responsible for this request.
   */
  const struct TEKT_RequestHandler *rh;

  /**
   * Request URL (for logging).
   */
  const char *url;

  /**
   * Connection we are processing.
   */
  struct MHD_Connection *connection;

  /**
   * HTTP response to return (or NULL).
   */
  struct MHD_Response *response;

  /**
   * @e rh-specific cleanup routine. Function called
   * upon completion of the request that should
   * clean up @a rh_ctx. Can be NULL.
   */
  void
  (*rh_cleaner)(struct TEKT_RequestContext *rc);

  /**
   * @e rh-specific context. Place where the request
   * handler can associate state with this request.
   * Can be NULL.
   */
  void *rh_ctx;

  /**
   * Uploaded JSON body, if any.
   */
  json_t *root;

  /**
   * HTTP status to return upon resume if @e response
   * is non-NULL.
   */
  unsigned int http_status;

};


/**
 * @brief Struct describing an URL and the handler for it.
 */
struct TEKT_RequestHandler
{

  /**
   * URL the handler is for (first part only).
   */
  const char *url;

  /**
   * Method the handler is for.
   */
  const char *method;

  /**
   * Callbacks for handling of the request. Which one is used
   * depends on @e method.
   */
  union
  {
    /**
     * Function to call to handle a GET requests (and those
     * with @e method NULL).
     *
     * @param rc context for the request
     * @param mime_type the @e mime_type for the reply (hint, can be NULL)
     * @param args array of arguments, needs to be of length @e args_expected
     * @return MHD result code
     */
    MHD_RESULT
    (*get)(struct TEKT_RequestContext *rc,
           const char *const args[]);


    /**
     * Function to call to handle a POST request.
     *
     * @param rc context for the request
     * @param json uploaded JSON data
     * @param args array of arguments, needs to be of length @e args_expected
     * @return MHD result code
     */
    MHD_RESULT
    (*post)(struct TEKT_RequestContext *rc,
            const json_t *root,
            const char *const args[]);

  } handler;

  /**
   * Number of arguments this handler expects in the @a args array.
   */
  unsigned int nargs;

  /**
   * Is the number of arguments given in @e nargs only an upper bound,
   * and calling with fewer arguments could be OK?
   */
  bool nargs_is_upper_bound;

  /**
   * Mime type to use in reply (hint, can be NULL).
   */
  const char *mime_type;

  /**
   * Raw data for the @e handler, can be NULL for none provided.
   */
  const void *data;

  /**
   * Number of bytes in @e data, 0 for data is 0-terminated (!).
   */
  size_t data_size;

  /**
   * Default response code. 0 for none provided.
   */
  unsigned int response_code;
};


/**
 * Information we track per ongoing kyc-proof request.
 */
struct ProofRequestState
{
  /**
   * Kept in a DLL.
   */
  struct ProofRequestState *next;

  /**
   * Kept in a DLL.
   */
  struct ProofRequestState *prev;

  /**
   * Handle for operation with the plugin.
   */
  struct TALER_KYCLOGIC_ProofHandle *ph;

  /**
   * Logic plugin we are using.
   */
  struct TALER_KYCLOGIC_Plugin *logic;

  /**
   * HTTP request details.
   */
  struct TEKT_RequestContext *rc;

};

/**
 * Head of DLL.
 */
static struct ProofRequestState *rs_head;

/**
 * Tail of DLL.
 */
static struct ProofRequestState *rs_tail;

/**
 * The exchange's configuration (global)
 */
static const struct GNUNET_CONFIGURATION_Handle *TEKT_cfg;

/**
 * Handle to the HTTP server.
 */
static struct MHD_Daemon *mhd;

/**
 * Our base URL.
 */
static char *TEKT_base_url;

/**
 * Payto set via command-line (or otherwise random).
 */
static struct TALER_PaytoHashP cmd_line_h_payto;

/**
 * Provider user ID to use.
 */
static char *cmd_provider_user_id;

/**
 * Provider legitimization ID to use.
 */
static char *cmd_provider_legitimization_id;

/**
 * Name of the configuration section with the
 * configuration data of the selected provider.
 */
static const char *provider_section_name;

/**
 * Row ID to use, override with '-r'
 */
static unsigned int kyc_row_id = 42;

/**
 * -P command-line option.
 */
static int print_h_payto;

/**
 * -w command-line option.
 */
static int run_webservice;

/**
 * Value to return from main()
 */
static int global_ret;

/**
 * -m command-line flag.
 */
static char *measure;

/**
 * Handle for ongoing initiation operation.
 */
static struct TALER_KYCLOGIC_InitiateHandle *ih;

/**
 * KYC logic running for @e ih.
 */
static struct TALER_KYCLOGIC_Plugin *ih_logic;

/**
 * Port to run the daemon on.
 */
static uint16_t serve_port;

/**
 * Context for all CURL operations (useful to the event loop)
 */
static struct GNUNET_CURL_Context *TEKT_curl_ctx;

/**
 * Context for integrating #TEKT_curl_ctx with the
 * GNUnet event loop.
 */
static struct GNUNET_CURL_RescheduleContext *exchange_curl_rc;


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
  struct TEKT_RequestContext *rc;

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
   * Name of the configuration
   * section defining the KYC logic.
   */
  const char *section_name;

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
}


static void
kyc_webhook_cleanup (void)
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
 * @param process_row legitimization process request the webhook was about
 * @param account_id account the webhook was about
 * @param provider_section configuration section of the logic
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
  const struct TALER_PaytoHashP *account_id,
  const char *provider_section,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  enum TALER_KYCLOGIC_KycStatus status,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *attributes,
  unsigned int http_status,
  struct MHD_Response *response)
{
  struct KycWebhookContext *kwh = cls;

  (void) expiration;
  (void) provider_section;
  kwh->wh = NULL;
  if ( (NULL != account_id) &&
       (0 != GNUNET_memcmp (account_id,
                            &cmd_line_h_payto)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Received webhook for unexpected account\n");
  }
  if ( (NULL != provider_user_id) &&
       (NULL != cmd_provider_user_id) &&
       (0 != strcmp (provider_user_id,
                     cmd_provider_user_id)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Received webhook for unexpected provider user ID (%s)\n",
                provider_user_id);
  }
  if ( (NULL != provider_legitimization_id) &&
       (NULL != cmd_provider_legitimization_id) &&
       (0 != strcmp (provider_legitimization_id,
                     cmd_provider_legitimization_id)) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Received webhook for unexpected provider legitimization ID (%s)\n",
                provider_legitimization_id);
  }
  switch (status)
  {
  case TALER_KYCLOGIC_STATUS_SUCCESS:
    /* _successfully_ resumed case */
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "KYC successful for user `%s' (legi: %s)\n",
                provider_user_id,
                provider_legitimization_id);
    GNUNET_break (NULL != attributes);
    fprintf (stderr,
             "Extracted attributes:\n");
    json_dumpf (attributes,
                stderr,
                JSON_INDENT (2));
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC status of %s/%s (process #%llu) is %d\n",
                provider_user_id,
                provider_legitimization_id,
                (unsigned long long) process_row,
                status);
    break;
  }
  kwh->response = response;
  kwh->response_code = http_status;
  kwh_resume (kwh);
  TALER_MHD_daemon_trigger ();
}


/**
 * Function called to clean up a context.
 *
 * @param rc request context
 */
static void
clean_kwh (struct TEKT_RequestContext *rc)
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
  GNUNET_free (kwh);
}


/**
 * Function the plugin can use to lookup an
 * @a h_payto by @a provider_legitimization_id.
 *
 * @param cls closure, NULL
 * @param provider_section
 * @param provider_legitimization_id legi to look up
 * @param[out] h_payto where to write the result
 * @param[out] legi_row where to write the row ID for the legitimization ID
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
kyc_provider_account_lookup (
  void *cls,
  const char *provider_section,
  const char *provider_legitimization_id,
  struct TALER_PaytoHashP *h_payto,
  uint64_t *legi_row)
{
  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Simulated account lookup using `%s/%s'\n",
              provider_section,
              provider_legitimization_id);
  *h_payto = cmd_line_h_payto;
  *legi_row = kyc_row_id;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
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
  struct TEKT_RequestContext *rc,
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
          TALER_KYCLOGIC_lookup_logic (args[0],
                                       &kwh->plugin,
                                       &kwh->pd,
                                       &kwh->section_name)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "KYC logic `%s' unknown (check KYC provider configuration)\n",
                  args[0]);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN,
                                         args[0]);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Calling KYC provider specific webhook\n");
    kwh->wh = kwh->plugin->webhook (kwh->plugin->cls,
                                    kwh->pd,
                                    &kyc_provider_account_lookup,
                                    NULL,
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
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning queued reply for KWH\n");
    /* handle _failed_ resumed cases */
    return MHD_queue_response (rc->connection,
                               kwh->response_code,
                               kwh->response);
  }

  /* We resumed, but got no response? This should
     not happen. */
  GNUNET_assert (0);
  return TALER_MHD_reply_with_error (rc->connection,
                                     MHD_HTTP_INTERNAL_SERVER_ERROR,
                                     TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                     "resumed without response");
}


/**
 * Handle a GET "/kyc-webhook" request.
 *
 * @param rc request to handle
 * @param args one argument with the legitimization_uuid
 * @return MHD result code
 */
static MHD_RESULT
handler_kyc_webhook_get (
  struct TEKT_RequestContext *rc,
  const char *const args[])
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Webhook GET triggered\n");
  return handler_kyc_webhook_generic (rc,
                                      MHD_HTTP_METHOD_GET,
                                      NULL,
                                      args);
}


/**
 * Handle a POST "/kyc-webhook" request.
 *
 * @param rc request to handle
 * @param root uploaded JSON body (can be NULL)
 * @param args one argument with the legitimization_uuid
 * @return MHD result code
 */
static MHD_RESULT
handler_kyc_webhook_post (
  struct TEKT_RequestContext *rc,
  const json_t *root,
  const char *const args[])
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Webhook POST triggered\n");
  return handler_kyc_webhook_generic (rc,
                                      MHD_HTTP_METHOD_POST,
                                      root,
                                      args);
}


/**
 * Function called with the result of a proof check operation.
 *
 * Note that the "decref" for the @a response
 * will be done by the callee and MUST NOT be done by the plugin.
 *
 * @param cls closure with the `struct ProofRequestState`
 * @param status KYC status
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param expiration until when is the KYC check valid
 * @param attributes attributes about the user
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 */
static void
proof_cb (
  void *cls,
  enum TALER_KYCLOGIC_KycStatus status,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration,
  const json_t *attributes,
  unsigned int http_status,
  struct MHD_Response *response)
{
  struct ProofRequestState *rs = cls;

  (void) expiration;
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "KYC legitimization %s completed with status %d (%u) for %s\n",
              provider_legitimization_id,
              status,
              http_status,
              provider_user_id);
  if (TALER_KYCLOGIC_STATUS_SUCCESS == status)
  {
    GNUNET_break (NULL != attributes);
    fprintf (stderr,
             "Extracted attributes:\n");
    json_dumpf (attributes,
                stderr,
                JSON_INDENT (2));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Returning response %p with status %u\n",
              response,
              http_status);
  rs->rc->response = response;
  rs->rc->http_status = http_status;
  GNUNET_CONTAINER_DLL_remove (rs_head,
                               rs_tail,
                               rs);
  MHD_resume_connection (rs->rc->connection);
  TALER_MHD_daemon_trigger ();
  GNUNET_free (rs);
}


/**
 * Function called when we receive a 'GET' to the
 * '/kyc-proof' endpoint.
 *
 * @param rc request context
 * @param args remaining URL arguments;
 *        args[0] should be the logic plugin name
 */
static MHD_RESULT
handler_kyc_proof_get (
  struct TEKT_RequestContext *rc,
  const char *const args[1])
{
  struct TALER_PaytoHashP h_payto;
  struct TALER_KYCLOGIC_ProviderDetails *pd;
  struct TALER_KYCLOGIC_Plugin *logic;
  struct ProofRequestState *rs;
  const char *section_name;
  const char *h_paytos;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "GET /kyc-proof triggered\n");
  if (NULL == args[0])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       "'/kyc-proof/$PROVIDER_SECTION?state=$H_PAYTO' required");
  }
  h_paytos = MHD_lookup_connection_value (rc->connection,
                                          MHD_GET_ARGUMENT_KIND,
                                          "state");
  if (NULL == h_paytos)
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MISSING,
                                       "h_payto");
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (h_paytos,
                                     strlen (h_paytos),
                                     &h_payto,
                                     sizeof (h_payto)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "h_payto");
  }
  if (0 !=
      GNUNET_memcmp (&h_payto,
                     &cmd_line_h_payto))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_KYC_PROOF_REQUEST_UNKNOWN,
                                       "h_payto");
  }

  if (GNUNET_OK !=
      TALER_KYCLOGIC_lookup_logic (args[0],
                                   &logic,
                                   &pd,
                                   &section_name))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not initiate KYC with provider `%s' (configuration error?)\n",
                args[0]);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_UNKNOWN,
                                       args[0]);
  }
  rs = GNUNET_new (struct ProofRequestState);
  rs->rc = rc;
  rs->logic = logic;
  MHD_suspend_connection (rc->connection);
  GNUNET_CONTAINER_DLL_insert (rs_head,
                               rs_tail,
                               rs);
  rs->ph = logic->proof (logic->cls,
                         pd,
                         rc->connection,
                         &h_payto,
                         kyc_row_id,
                         cmd_provider_user_id,
                         cmd_provider_legitimization_id,
                         &proof_cb,
                         rs);
  GNUNET_assert (NULL != rs->ph);
  return MHD_YES;
}


/**
 * Function called whenever MHD is done with a request.  If the
 * request was a POST, we may have stored a `struct Buffer *` in the
 * @a con_cls that might still need to be cleaned up.  Call the
 * respective function to free the memory.
 *
 * @param cls client-defined closure
 * @param connection connection handle
 * @param con_cls value as set by the last call to
 *        the #MHD_AccessHandlerCallback
 * @param toe reason for request termination
 * @see #MHD_OPTION_NOTIFY_COMPLETED
 * @ingroup request
 */
static void
handle_mhd_completion_callback (void *cls,
                                struct MHD_Connection *connection,
                                void **con_cls,
                                enum MHD_RequestTerminationCode toe)
{
  struct TEKT_RequestContext *rc = *con_cls;

  (void) cls;
  if (NULL == rc)
    return;
  if (NULL != rc->rh_cleaner)
    rc->rh_cleaner (rc);
  {
#if MHD_VERSION >= 0x00097304
    const union MHD_ConnectionInfo *ci;
    unsigned int http_status = 0;

    ci = MHD_get_connection_info (connection,
                                  MHD_CONNECTION_INFO_HTTP_STATUS);
    if (NULL != ci)
      http_status = ci->http_status;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Request for `%s' completed with HTTP status %u (%d)\n",
                rc->url,
                http_status,
                toe);
#else
    (void) connection;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Request for `%s' completed (%d)\n",
                rc->url,
                toe);
#endif
  }

  TALER_MHD_parse_post_cleanup_callback (rc->opaque_post_parsing_context);
  /* Sanity-check that we didn't leave any transactions hanging */
  if (NULL != rc->root)
    json_decref (rc->root);
  GNUNET_free (rc);
  *con_cls = NULL;
}


/**
 * We found a request handler responsible for handling a request. Parse the
 * @a upload_data (if applicable) and the @a url and call the
 * handler.
 *
 * @param rc request context
 * @param url rest of the URL to parse
 * @param upload_data upload data to parse (if available)
 * @param[in,out] upload_data_size number of bytes in @a upload_data
 * @return MHD result code
 */
static MHD_RESULT
proceed_with_handler (struct TEKT_RequestContext *rc,
                      const char *url,
                      const char *upload_data,
                      size_t *upload_data_size)
{
  const struct TEKT_RequestHandler *rh = rc->rh;
  const char *args[rh->nargs + 2];
  size_t ulen = strlen (url) + 1;
  MHD_RESULT ret;

  /* We do check for "ulen" here, because we'll later stack-allocate a buffer
     of that size and don't want to enable malicious clients to cause us
     huge stack allocations. */
  if (ulen > 512)
  {
    /* 512 is simply "big enough", as it is bigger than "6 * 54",
       which is the longest URL format we ever get (for
       /deposits/).  The value should be adjusted if we ever define protocol
       endpoints with plausibly longer inputs.  */
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_URI_TOO_LONG,
                                       TALER_EC_GENERIC_URI_TOO_LONG,
                                       url);
  }

  /* All POST endpoints come with a body in JSON format. So we parse
     the JSON here. */
  if ( (NULL == rc->root) &&
       (0 == strcasecmp (rh->method,
                         MHD_HTTP_METHOD_POST)) )
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_post_json (rc->connection,
                                     &rc->opaque_post_parsing_context,
                                     upload_data,
                                     upload_data_size,
                                     &rc->root);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_assert (NULL == rc->root);
      GNUNET_break (0);
      return MHD_NO; /* bad upload, could not even generate error */
    }
    if ( (GNUNET_NO == res) ||
         (NULL == rc->root) )
    {
      GNUNET_assert (NULL == rc->root);
      return MHD_YES; /* so far incomplete upload or parser error */
    }
  }

  {
    char d[ulen];
    unsigned int i;
    char *sp;

    /* Parse command-line arguments */
    /* make a copy of 'url' because 'strtok_r()' will modify */
    GNUNET_memcpy (d,
                   url,
                   ulen);
    i = 0;
    args[i++] = strtok_r (d, "/", &sp);
    while ( (NULL != args[i - 1]) &&
            (i <= rh->nargs + 1) )
      args[i++] = strtok_r (NULL, "/", &sp);
    /* make sure above loop ran nicely until completion, and also
       that there is no excess data in 'd' afterwards */
    if ( ( (rh->nargs_is_upper_bound) &&
           (i - 1 > rh->nargs) ) ||
         ( (! rh->nargs_is_upper_bound) &&
           (i - 1 != rh->nargs) ) )
    {
      char emsg[128 + 512];

      GNUNET_snprintf (emsg,
                       sizeof (emsg),
                       "Got %u+/%u segments for `%s' request (`%s')",
                       i - 1,
                       rh->nargs,
                       rh->url,
                       url);
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_WRONG_NUMBER_OF_SEGMENTS,
                                         emsg);
    }
    GNUNET_assert (NULL == args[i - 1]);

    /* Above logic ensures that 'root' is exactly non-NULL for POST operations,
       so we test for 'root' to decide which handler to invoke. */
    if (NULL != rc->root)
      ret = rh->handler.post (rc,
                              rc->root,
                              args);
    else /* We also only have "POST" or "GET" in the API for at this point
      (OPTIONS/HEAD are taken care of earlier) */
      ret = rh->handler.get (rc,
                             args);
  }
  return ret;
}


static void
rh_cleaner_cb (struct TEKT_RequestContext *rc)
{
  if (NULL != rc->response)
  {
    MHD_destroy_response (rc->response);
    rc->response = NULL;
  }
  if (NULL != rc->root)
  {
    json_decref (rc->root);
    rc->root = NULL;
  }
}


/**
 * Handle incoming HTTP request.
 *
 * @param cls closure for MHD daemon (unused)
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param version HTTP version (ignored)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct TEKT_RequestContext *`)
 * @return MHD result code
 */
static MHD_RESULT
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  static struct TEKT_RequestHandler handlers[] = {
    /* simulated KYC endpoints */
    {
      .url = "kyc-proof",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &handler_kyc_proof_get,
      .nargs = 1
    },
    {
      .url = "kyc-webhook",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handler_kyc_webhook_post,
      .nargs = 128,
      .nargs_is_upper_bound = true
    },
    {
      .url = "kyc-webhook",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &handler_kyc_webhook_get,
      .nargs = 128,
      .nargs_is_upper_bound = true
    },
    /* mark end of list */
    {
      .url = NULL
    }
  };
  struct TEKT_RequestContext *rc = *con_cls;

  (void) cls;
  (void) version;
  if (NULL == rc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling new request\n");
    /* We're in a new async scope! */
    rc = *con_cls = GNUNET_new (struct TEKT_RequestContext);
    rc->url = url;
    rc->connection = connection;
    rc->rh_cleaner = &rh_cleaner_cb;
  }
  if (NULL != rc->response)
  {
    return MHD_queue_response (rc->connection,
                               rc->http_status,
                               rc->response);
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request (%s) for URL '%s'\n",
              method,
              url);
  /* on repeated requests, check our cache first */
  if (NULL != rc->rh)
  {
    const char *start;

    if ('\0' == url[0])
      /* strange, should start with '/', treat as just "/" */
      url = "/";
    start = strchr (url + 1, '/');
    if (NULL == start)
      start = "";
    return proceed_with_handler (rc,
                                 start,
                                 upload_data,
                                 upload_data_size);
  }
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */

  /* parse first part of URL */
  {
    bool found = false;
    size_t tok_size;
    const char *tok;
    const char *rest;

    if ('\0' == url[0])
      /* strange, should start with '/', treat as just "/" */
      url = "/";
    tok = url + 1;
    rest = strchr (tok, '/');
    if (NULL == rest)
    {
      tok_size = strlen (tok);
    }
    else
    {
      tok_size = rest - tok;
      rest++; /* skip over '/' */
    }
    for (unsigned int i = 0; NULL != handlers[i].url; i++)
    {
      struct TEKT_RequestHandler *rh = &handlers[i];

      if ( (0 != strncmp (tok,
                          rh->url,
                          tok_size)) ||
           (tok_size != strlen (rh->url) ) )
        continue;
      found = true;
      /* The URL is a match!  What we now do depends on the method. */
      if (0 == strcasecmp (method,
                           MHD_HTTP_METHOD_OPTIONS))
      {
        return TALER_MHD_reply_cors_preflight (connection);
      }
      GNUNET_assert (NULL != rh->method);
      if (0 != strcasecmp (method,
                           rh->method))
      {
        found = true;
        continue;
      }
      /* cache to avoid the loop next time */
      rc->rh = rh;
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Handler found for %s '%s'\n",
                  method,
                  url);
      return MHD_YES;
    }

    if (found)
    {
      /* we found a matching address, but the method is wrong */
      struct MHD_Response *reply;
      MHD_RESULT ret;
      char *allowed = NULL;

      GNUNET_break_op (0);
      for (unsigned int i = 0; NULL != handlers[i].url; i++)
      {
        struct TEKT_RequestHandler *rh = &handlers[i];

        if ( (0 != strncmp (tok,
                            rh->url,
                            tok_size)) ||
             (tok_size != strlen (rh->url) ) )
          continue;
        if (NULL == allowed)
        {
          allowed = GNUNET_strdup (rh->method);
        }
        else
        {
          char *tmp;

          GNUNET_asprintf (&tmp,
                           "%s, %s",
                           allowed,
                           rh->method);
          GNUNET_free (allowed);
          allowed = tmp;
        }
        if (0 == strcasecmp (rh->method,
                             MHD_HTTP_METHOD_GET))
        {
          char *tmp;

          GNUNET_asprintf (&tmp,
                           "%s, %s",
                           allowed,
                           MHD_HTTP_METHOD_HEAD);
          GNUNET_free (allowed);
          allowed = tmp;
        }
      }
      reply = TALER_MHD_make_error (TALER_EC_GENERIC_METHOD_INVALID,
                                    method);
      GNUNET_break (MHD_YES ==
                    MHD_add_response_header (reply,
                                             MHD_HTTP_HEADER_ALLOW,
                                             allowed));
      GNUNET_free (allowed);
      ret = MHD_queue_response (connection,
                                MHD_HTTP_METHOD_NOT_ALLOWED,
                                reply);
      MHD_destroy_response (reply);
      return ret;
    }
  }

  /* No handler matches, generate not found */
  return TALER_MHD_reply_with_error (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                     url);
}


/**
 * Load configuration parameters for the exchange
 * server into the corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
exchange_serve_process_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (TEKT_cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &TEKT_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (! TALER_url_valid_charset (TEKT_base_url))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL",
                               "invalid URL");
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Function run on shutdown.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  struct MHD_Daemon *mhd;
  struct ProofRequestState *rs;

  (void) cls;
  while (NULL != (rs = rs_head))
  {
    GNUNET_CONTAINER_DLL_remove (rs_head,
                                 rs_tail,
                                 rs);
    rs->logic->proof_cancel (rs->ph);
    MHD_resume_connection (rs->rc->connection);
    GNUNET_free (rs);
  }
  if (NULL != ih)
  {
    ih_logic->initiate_cancel (ih);
    ih = NULL;
  }
  kyc_webhook_cleanup ();
  TALER_KYCLOGIC_kyc_done ();
  mhd = TALER_MHD_daemon_stop ();
  if (NULL != mhd)
    MHD_stop_daemon (mhd);
  if (NULL != TEKT_curl_ctx)
  {
    GNUNET_CURL_fini (TEKT_curl_ctx);
    TEKT_curl_ctx = NULL;
  }
  if (NULL != exchange_curl_rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (exchange_curl_rc);
    exchange_curl_rc = NULL;
  }
  TALER_TEMPLATING_done ();
}


/**
 * Function called with the result of a KYC initiation
 * operation.
 *
 * @param cls closure
 * @param ec #TALER_EC_NONE on success
 * @param redirect_url set to where to redirect the user on success, NULL on failure
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param error_msg_hint set to additional details to return to user, NULL on success
 */
static void
initiate_cb (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *redirect_url,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_msg_hint)
{
  (void) cls;
  ih = NULL;
  if (TALER_EC_NONE != ec)
  {
    fprintf (stderr,
             "Failed to start KYC process: %s (#%d)\n",
             error_msg_hint,
             ec);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  {
    char *s;

    s = GNUNET_STRINGS_data_to_string_alloc (&cmd_line_h_payto,
                                             sizeof (cmd_line_h_payto));
    if (NULL != provider_user_id)
    {
      fprintf (stdout,
               "Visit `%s' to begin KYC process.\nAlso use: taler-exchange-kyc-tester -w -u '%s' -U '%s' -p %s\n",
               redirect_url,
               provider_user_id,
               provider_legitimization_id,
               s);
    }
    else
    {
      fprintf (stdout,
               "Visit `%s' to begin KYC process.\nAlso use: taler-exchange-kyc-tester -w -U '%s' -p %s\n",
               redirect_url,
               provider_legitimization_id,
               s);
    }
    GNUNET_free (s);
  }
  GNUNET_free (cmd_provider_user_id);
  GNUNET_free (cmd_provider_legitimization_id);
  if (NULL != provider_user_id)
    cmd_provider_user_id = GNUNET_strdup (provider_user_id);
  if (NULL != provider_legitimization_id)
    cmd_provider_legitimization_id = GNUNET_strdup (provider_legitimization_id);
  if (! run_webservice)
    GNUNET_SCHEDULER_shutdown ();
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be
 *        NULL!)
 * @param config configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *config)
{
  int fh;

  (void) cls;
  (void) args;
  (void ) cfgfile;
  if (GNUNET_OK !=
      TALER_TEMPLATING_init ("exchange"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not load templates. Installation broken.\n");
    return;
  }
  if (print_h_payto)
  {
    char *s;

    s = GNUNET_STRINGS_data_to_string_alloc (&cmd_line_h_payto,
                                             sizeof (cmd_line_h_payto));
    fprintf (stdout,
             "%s\n",
             s);
    GNUNET_free (s);
  }
  TALER_MHD_setup (TALER_MHD_GO_NONE);
  TEKT_cfg = config;
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  if (GNUNET_OK !=
      TALER_KYCLOGIC_kyc_init (config))
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  global_ret = EXIT_SUCCESS;
  if (NULL != measure)
  {
    struct TALER_KYCLOGIC_ProviderDetails *pd;

    if (GNUNET_OK !=
        TALER_KYCLOGIC_requirements_to_logic (NULL, /* FIXME! */
                                              NULL, /* FIXME! */
                                              measure,
                                              &ih_logic,
                                              &pd,
                                              &provider_section_name))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not initiate KYC for measure `%s' (configuration error?)\n",
                  measure);
      global_ret = EXIT_NOTCONFIGURED;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    ih = ih_logic->initiate (ih_logic->cls,
                             pd,
                             &cmd_line_h_payto,
                             kyc_row_id,
                             &initiate_cb,
                             NULL);
    GNUNET_break (NULL != ih);
  }
  if (run_webservice)
  {
    TEKT_curl_ctx
      = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &exchange_curl_rc);
    if (NULL == TEKT_curl_ctx)
    {
      GNUNET_break (0);
      global_ret = EXIT_FAILURE;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    exchange_curl_rc = GNUNET_CURL_gnunet_rc_create (TEKT_curl_ctx);
    fh = TALER_MHD_bind (TEKT_cfg,
                         "exchange",
                         &serve_port);
    if ( (0 == serve_port) &&
         (-1 == fh) )
    {
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Starting daemon on port %u\n",
                (unsigned int) serve_port);
    mhd = MHD_start_daemon (MHD_USE_SUSPEND_RESUME
                            | MHD_USE_PIPE_FOR_SHUTDOWN
                            | MHD_USE_DEBUG | MHD_USE_DUAL_STACK
                            | MHD_USE_TCP_FASTOPEN,
                            (-1 == fh) ? serve_port : 0,
                            NULL, NULL,
                            &handle_mhd_request, NULL,
                            MHD_OPTION_LISTEN_SOCKET,
                            fh,
                            MHD_OPTION_EXTERNAL_LOGGER,
                            &TALER_MHD_handle_logs,
                            NULL,
                            MHD_OPTION_NOTIFY_COMPLETED,
                            &handle_mhd_completion_callback,
                            NULL,
                            MHD_OPTION_END);
    if (NULL == mhd)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to launch HTTP service. Is the port in use?\n");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    TALER_MHD_daemon_start (mhd);
  }
}


/**
 * The main function of the taler-exchange-httpd server ("the exchange").
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_help (
      "tool to test KYC provider integrations"),
    GNUNET_GETOPT_option_flag (
      'P',
      "print-payto-hash",
      "output the hash of the payto://-URI",
      &print_h_payto),
    GNUNET_GETOPT_option_uint (
      'r',
      "rowid",
      "NUMBER",
      "override row ID to use in simulation (default: 42)",
      &kyc_row_id),
    GNUNET_GETOPT_option_flag (
      'w',
      "run-webservice",
      "run the integrated HTTP service",
      &run_webservice),
    GNUNET_GETOPT_option_string (
      'm',
      "measure",
      "MEASURE_NAME",
      "initiate KYC check for the selected measure",
      &measure),
    GNUNET_GETOPT_option_string (
      'u',
      "user",
      "ID",
      "use the given provider user ID (overridden if -i is also used)",
      &cmd_provider_user_id),
    GNUNET_GETOPT_option_string (
      'U',
      "legitimization",
      "ID",
      "use the given provider legitimization ID (overridden if -i is also used)",
      &cmd_provider_legitimization_id),
    GNUNET_GETOPT_option_base32_fixed_size (
      'p',
      "payto-hash",
      "HASH",
      "base32 encoding of the hash of a payto://-URI to use for the account (otherwise a random value will be used)",
      &cmd_line_h_payto,
      sizeof (cmd_line_h_payto)),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  TALER_OS_init ();
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &cmd_line_h_payto,
                              sizeof (cmd_line_h_payto));
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-exchange-kyc-tester",
                            "tool to test KYC provider integrations",
                            options,
                            &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-kyc-tester.c */
