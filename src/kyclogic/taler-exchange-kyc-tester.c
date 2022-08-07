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
#include "taler_crypto_lib.h"
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
 * The exchange's configuration (global)
 */
static const struct GNUNET_CONFIGURATION_Handle *TEKT_cfg;

/**
 * Handle to the HTTP server.
 */
static struct MHD_Daemon *mhd;

/**
 * Our currency.
 */
static char *TEKT_currency;

/**
 * Our base URL.
 */
static char *TEKT_base_url;

/**
 * Value to return from main()
 */
static int global_ret;

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
 * Generate a 404 "not found" reply on @a connection with
 * the hint @a details.
 *
 * @param connection where to send the reply on
 * @param details details for the error message, can be NULL
 */
static MHD_RESULT
r404 (struct MHD_Connection *connection,
      const char *details)
{
  return TALER_MHD_reply_with_error (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                     details);
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
  // FIXME: handle '-1 == rh->nargs'!!!
  const char *args[rh->nargs + 2];
  size_t ulen = strlen (url) + 1;
  json_t *root = NULL;
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
  if (0 == strcasecmp (rh->method,
                       MHD_HTTP_METHOD_POST))
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_post_json (rc->connection,
                                     &rc->opaque_post_parsing_context,
                                     upload_data,
                                     upload_data_size,
                                     &root);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_assert (NULL == root);
      return MHD_NO; /* bad upload, could not even generate error */
    }
    if ( (GNUNET_NO == res) ||
         (NULL == root) )
    {
      GNUNET_assert (NULL == root);
      return MHD_YES; /* so far incomplete upload or parser error */
    }
  }

  {
    char d[ulen];
    unsigned int i;
    char *sp;

    /* Parse command-line arguments */
    /* make a copy of 'url' because 'strtok_r()' will modify */
    memcpy (d,
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
      json_decref (root);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_WRONG_NUMBER_OF_SEGMENTS,
                                         emsg);
    }
    GNUNET_assert (NULL == args[i - 1]);

    /* Above logic ensures that 'root' is exactly non-NULL for POST operations,
       so we test for 'root' to decide which handler to invoke. */
    if (NULL != root)
      ret = rh->handler.post (rc,
                              root,
                              args);
    else /* We also only have "POST" or "GET" in the API for at this point
      (OPTIONS/HEAD are taken care of earlier) */
      ret = rh->handler.get (rc,
                             args);
  }
  json_decref (root);
  return ret;
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
#if FIXME
    /* KYC endpoints */
    {
      .url = "kyc-check",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEKT_handler_kyc_check,
      .nargs = 1
    },
    {
      .url = "kyc-proof",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEKT_handler_kyc_proof,
      .nargs = 1
    },
    {
      .url = "kyc-wallet",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEKT_handler_kyc_wallet,
      .nargs = 0
    },
    {
      .url = "kyc-webhook",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEKT_handler_kyc_webhook_post,
      .nargs = -1
    },
    {
      .url = "kyc-webhook",
      .method = MHD_HTTP_METHOD_GET,
      .handler.post = &TEKT_handler_kyc_webhook_get,
      .nargs = -1
    },
#endif
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
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request (%s) for URL '%s'\n",
              method,
              url);
  /* on repeated requests, check our cache first */
  if (NULL != rc->rh)
  {
    MHD_RESULT ret;
    const char *start;

    if ('\0' == url[0])
      /* strange, should start with '/', treat as just "/" */
      url = "/";
    start = strchr (url + 1, '/');
    if (NULL == start)
      start = "";
    ret = proceed_with_handler (rc,
                                start,
                                upload_data,
                                upload_data_size);
    return ret;
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
      if (0 == strcasecmp (method, MHD_HTTP_METHOD_OPTIONS))
      {
        return TALER_MHD_reply_cors_preflight (connection);
      }
      GNUNET_assert (NULL != rh->method);
      if (0 == strcasecmp (method,
                           rh->method))
      {
        MHD_RESULT ret;

        /* cache to avoid the loop next time */
        rc->rh = rh;
        /* run handler */
        ret = proceed_with_handler (rc,
                                    url + tok_size + 1,
                                    upload_data,
                                    upload_data_size);
        return ret;
      }
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
  {
    MHD_RESULT ret;

    ret = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_NOT_FOUND,
                                      TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                      url);
    return ret;
  }
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
  (void) cls;

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
  TALER_MHD_setup (TALER_MHD_GO_NONE);
  TEKT_cfg = config;

  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  fh = TALER_MHD_bind (TEKT_cfg,
                       "exchange",
                       &serve_port);
  if ( (0 == serve_port) &&
       (-1 == fh) )
  {
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  global_ret = EXIT_SUCCESS;
  TALER_MHD_daemon_start (mhd);
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
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  TALER_OS_init ();
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
