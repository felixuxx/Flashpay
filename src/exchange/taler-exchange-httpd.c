/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-exchange-httpd.c
 * @brief Serve the HTTP interface of the exchange
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include <sys/resource.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_deposit.h"
#include "taler-exchange-httpd_refund.h"
#include "taler-exchange-httpd_reserves_get.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler-exchange-httpd_recoup.h"
#include "taler-exchange-httpd_link.h"
#include "taler-exchange-httpd_melt.h"
#include "taler-exchange-httpd_refreshes_reveal.h"
#include "taler-exchange-httpd_terms.h"
#include "taler-exchange-httpd_transfers_get.h"
#include "taler-exchange-httpd_deposits_get.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_exchangedb_plugin.h"
#include "taler-exchange-httpd_validation.h"


/**
 * Backlog for listen operation on unix domain sockets.
 */
#define UNIX_BACKLOG 500


/**
 * Type of the closure associated with each HTTP request to the exchange.
 */
struct ExchangeHttpRequestClosure
{
  /**
   * Async Scope ID associated with this request.
   */
  struct GNUNET_AsyncScopeId async_scope_id;

  /**
   * Opaque parsing context.
   */
  void *opaque_post_parsing_context;

  /**
   * Cached request handler for this request (once we have found one).
   */
  struct TEH_RequestHandler *rh;
};


/**
 * Base directory of the exchange (global)
 */
char *TEH_exchange_directory;

/**
 * Directory where revocations are stored (global)
 */
char *TEH_revocation_directory;

/**
 * The exchange's configuration (global)
 */
struct GNUNET_CONFIGURATION_Handle *TEH_cfg;

/**
 * How long is caching /keys allowed at most? (global)
 */
struct GNUNET_TIME_Relative TEH_max_keys_caching;

/**
 * Master public key (according to the
 * configuration in the exchange directory).  (global)
 */
struct TALER_MasterPublicKeyP TEH_master_public_key;

/**
 * Our DB plugin.  (global)
 */
struct TALER_EXCHANGEDB_Plugin *TEH_plugin;

/**
 * Default timeout in seconds for HTTP requests.
 */
static unsigned int connection_timeout = 30;

/**
 * The HTTP Daemon.
 */
static struct MHD_Daemon *mhd;

/**
 * Port to run the daemon on.
 */
static uint16_t serve_port;

/**
 * Path for the unix domain-socket
 * to run the daemon on.
 */
static char *serve_unixpath;

/**
 * File mode for unix-domain socket.
 */
static mode_t unixpath_mode;

/**
 * Counter for the number of requests this HTTP has processed so far.
 */
static unsigned long long req_count;

/**
 * Limit for the number of requests this HTTP may process before restarting.
 * (This was added as one way of dealing with unavoidable memory fragmentation
 * happening slowly over time.)
 */
static unsigned long long req_max;


/**
 * Signature of functions that handle operations on coins.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub the public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
 */
typedef int
(*CoinOpHandler)(struct MHD_Connection *connection,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const json_t *root);


/**
 * Handle a "/coins/$COIN_PUB/$OP" POST request.  Parses the "coin_pub"
 * EdDSA key of the coin and demultiplexes based on $OP.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @param args array of additional options (first must be the
 *         reserve public key, the second one should be "withdraw")
 * @return MHD result code
 */
static int
handle_post_coins (const struct TEH_RequestHandler *rh,
                   struct MHD_Connection *connection,
                   const json_t *root,
                   const char *const args[2])
{
  struct TALER_CoinSpendPublicKeyP coin_pub;
  static const struct
  {
    /**
     * Name of the operation (args[1])
     */
    const char *op;

    /**
     * Function to call to perform the operation.
     */
    CoinOpHandler handler;

  } h[] = {
    {
      .op = "deposit",
      .handler = &TEH_handler_deposit
    },
    {
      .op = "melt",
      .handler = &TEH_handler_melt
    },
    {
      .op = "recoup",
      .handler = &TEH_handler_recoup
    },
    {
      .op = "refund",
      .handler = &TEH_handler_refund
    },
    {
      .op = NULL,
      .handler = NULL
    },
  };

  (void) rh;
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &coin_pub,
                                     sizeof (coin_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_COINS_INVALID_COIN_PUB,
                                       "coin public key malformed");
  }
  for (unsigned int i = 0; NULL != h[i].op; i++)
    if (0 == strcmp (h[i].op,
                     args[1]))
      return h[i].handler (connection,
                           &coin_pub,
                           root);
  return TALER_MHD_reply_with_error (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     TALER_EC_OPERATION_INVALID,
                                     "requested operation on coin unknown");
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
  struct ExchangeHttpRequestClosure *ecls = *con_cls;

  (void) cls;
  (void) connection;
  (void) toe;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Request completed\n");
  if (NULL == ecls)
    return;
  TALER_MHD_parse_post_cleanup_callback (ecls->opaque_post_parsing_context);
  GNUNET_free (ecls);
  *con_cls = NULL;
  /* Sanity-check that we didn't leave any transactions hanging */
  /* NOTE: In high-performance production, we could consider
     removing this as it should not be needed and might be costly
     (to be benchmarked). */
  TEH_plugin->preflight (TEH_plugin->cls,
                         TEH_plugin->get_session (TEH_plugin->cls));
}


/**
 * We found @a rh responsible for handling a request. Parse the
 * @a upload_data (if applicable) and the @a url and call the
 * handler.
 *
 * @param rh request handler to call
 * @param connection connection being handled
 * @param url rest of the URL to parse
 * @param inner_cls closure for the handler, if needed
 * @param upload_data upload data to parse (if available)
 * @param[in,out] upload_data_size number of bytes in @a upload_data
 * @return MHD result code
 */
static int
proceed_with_handler (const struct TEH_RequestHandler *rh,
                      struct MHD_Connection *connection,
                      const char *url,
                      void **inner_cls,
                      const char *upload_data,
                      size_t *upload_data_size)
{
  const char *args[rh->nargs + 1];
  size_t ulen = strlen (url) + 1;
  json_t *root = NULL;
  int ret;

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
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_URI_TOO_LONG,
                                       TALER_EC_URI_TOO_LONG,
                                       "The URI given is too long");
  }

  /* All POST endpoints come with a body in JSON format. So we parse
     the JSON here. */
  if (0 == strcasecmp (rh->method,
                       MHD_HTTP_METHOD_POST))
  {
    int res;

    res = TALER_MHD_parse_post_json (connection,
                                     inner_cls,
                                     upload_data,
                                     upload_data_size,
                                     &root);
    if (GNUNET_SYSERR == res)
      return MHD_NO;  /* bad upload, could not even generate error */
    if ( (GNUNET_NO == res) || (NULL == root) )
      return MHD_YES; /* so far incomplete upload or parser error */
  }

  {
    char d[ulen];

    /* Parse command-line arguments, if applicable */
    if (rh->nargs > 0)
    {
      unsigned int i;
      const char *fin;

      /* make a copy of 'url' because 'strtok()' will modify */
      memcpy (d,
              url,
              ulen);
      i = 0;
      args[i++] = strtok (d, "/");
      while ( (NULL != args[i - 1]) &&
              (i < rh->nargs) )
        args[i++] = strtok (NULL, "/");
      /* make sure above loop ran nicely until completion, and also
         that there is no excess data in 'd' afterwards */
      if ( (i != rh->nargs) ||
           (NULL == args[i - 1]) ||
           (NULL != (fin = strtok (NULL, "/"))) )
      {
        char emsg[128 + 512];

        GNUNET_snprintf (emsg,
                         sizeof (emsg),
                         "Got %u/%u segments for %s request ('%s')",
                         (NULL == args[i - 1])
                         ? i - 1
                         : i + ((NULL != fin) ? 1 : 0),
                         rh->nargs,
                         rh->url,
                         url);
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_WRONG_NUMBER_OF_SEGMENTS,
                                           emsg);
      }
    }

    /* just to be safe(r), we always terminate the array with a NULL
       (which handlers should not read, but at least if they do, they'll
       crash pretty reliably...) */
    args[rh->nargs] = NULL;

    /* Above logic ensures that 'root' is exactly non-NULL for POST operations,
       so we test for 'root' to decide which handler to invoke. */
    if (NULL != root)
      ret = rh->handler.post (rh,
                              connection,
                              root,
                              args);
    else /* We also only have "POST" or "GET" in the API for at this point
            (OPTIONS/HEAD are taken care of earlier) */
      ret = rh->handler.get (rh,
                             connection,
                             args);
  }
  if (NULL != root)
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
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  static struct TEH_RequestHandler handlers[] = {
    /* /robots.txt: disallow everything */
    {
      .url = "robots.txt",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_static_response,
      .mime_type = "text/plain",
      .data = "User-agent: *\nDisallow: /\n",
      .response_code = MHD_HTTP_OK
    },
    /* Landing page, tell humans to go away. */
    {
      .url = "",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = TEH_handler_static_response,
      .mime_type = "text/plain",
      .data =
        "Hello, I'm the Taler exchange. This HTTP server is not for humans.\n",
      .response_code = MHD_HTTP_OK
    },
    /* AGPL licensing page, redirect to source. As per the AGPL-license, every
       deployment is required to offer the user a download of the source of
       the actual deployment. We make this easy by including a redirect to the
       source here. */
    {
      .url = "agpl",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_agpl_redirect
    },
    /* Terms of service */
    {
      .url = "terms",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_terms
    },
    /* Privacy policy */
    {
      .url = "privacy",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_privacy
    },
    /* Return key material and fundamental properties for this exchange */
    {
      .url = "keys",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_keys,
    },
    /* Requests for wiring information */
    {
      .url = "wire",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_wire
    },
    /* Withdrawing coins / interaction with reserves */
    {
      .url = "reserves",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_reserves_get,
      .nargs = 1
    },
    {
      .url = "reserves",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_withdraw,
      .nargs = 2
    },
    /* coins */
    {
      .url = "coins",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &handle_post_coins,
      .nargs = 2
    },
    {
      .url = "coins",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = TEH_handler_link,
      .nargs = 2,
    },
    /* refreshes/$RCH/reveal */
    {
      .url = "refreshes",
      .method = MHD_HTTP_METHOD_POST,
      .handler.post = &TEH_handler_reveal,
      .nargs = 2
    },
    /* tracking transfers */
    {
      .url = "transfers",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_transfers_get,
      .nargs = 1
    },
    /* tracking deposits */
    {
      .url = "deposits",
      .method = MHD_HTTP_METHOD_GET,
      .handler.get = &TEH_handler_deposits_get,
      .nargs = 4
    },
    /* mark end of list */
    {
      .url = NULL
    }
  };
  struct ExchangeHttpRequestClosure *ecls = *con_cls;
  void **inner_cls;
  struct GNUNET_AsyncScopeSave old_scope;
  const char *correlation_id = NULL;

  (void) cls;
  (void) version;
  if (NULL == ecls)
  {
    unsigned long long cnt;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling new request\n");
    /* Atomic operation, no need for a lock ;-) */
    cnt = __sync_add_and_fetch (&req_count,
                                1LLU);
    if (req_max == cnt)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Restarting exchange service after %llu requests\n",
                  cnt);
      (void) kill (getpid (),
                   SIGHUP);
    }

    /* We're in a new async scope! */
    ecls = *con_cls = GNUNET_new (struct ExchangeHttpRequestClosure);
    GNUNET_async_scope_fresh (&ecls->async_scope_id);
    /* We only read the correlation ID on the first callback for every client */
    correlation_id = MHD_lookup_connection_value (connection,
                                                  MHD_HEADER_KIND,
                                                  "Taler-Correlation-Id");
    if ((NULL != correlation_id) &&
        (GNUNET_YES != GNUNET_CURL_is_valid_scope_id (correlation_id)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "illegal incoming correlation ID\n");
      correlation_id = NULL;
    }
  }

  inner_cls = &ecls->opaque_post_parsing_context;
  GNUNET_async_scope_enter (&ecls->async_scope_id,
                            &old_scope);
  if (NULL != correlation_id)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling request (%s) for URL '%s', correlation_id=%s\n",
                method,
                url,
                correlation_id);
  else
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling request (%s) for URL '%s'\n",
                method,
                url);
  /* on repeated requests, check our cache first */
  if (NULL != ecls->rh)
  {
    int ret;
    const char *start;

    if ('\0' == url[0])
      /* strange, should start with '/', treat as just "/" */
      url = "/";
    start = strchr (url + 1, '/');
    if (NULL == start)
      start = "";
    ret = proceed_with_handler (ecls->rh,
                                connection,
                                start,
                                inner_cls,
                                upload_data,
                                upload_data_size);
    GNUNET_async_scope_restore (&old_scope);
    return ret;
  }

  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET;   /* treat HEAD as GET here, MHD will do the rest */

  /* parse first part of URL */
  {
    int found = GNUNET_NO;
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
      struct TEH_RequestHandler *rh = &handlers[i];

      if (0 != strncmp (tok,
                        rh->url,
                        tok_size))
        continue;
      found = GNUNET_YES;
      /* The URL is a match!  What we now do depends on the method. */
      if (0 == strcasecmp (method, MHD_HTTP_METHOD_OPTIONS))
      {
        GNUNET_async_scope_restore (&old_scope);
        return TALER_MHD_reply_cors_preflight (connection);
      }
      GNUNET_assert (NULL != rh->method);
      if (0 == strcasecmp (method,
                           rh->method))
      {
        int ret;

        /* cache to avoid the loop next time */
        ecls->rh = rh;
        /* run handler */
        ret = proceed_with_handler (rh,
                                    connection,
                                    url + tok_size + 1,
                                    inner_cls,
                                    upload_data,
                                    upload_data_size);
        GNUNET_async_scope_restore (&old_scope);
        return ret;
      }
    }

    if (GNUNET_YES == found)
    {
      /* we found a matching address, but the method is wrong */
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_METHOD_NOT_ALLOWED,
                                         TALER_EC_METHOD_INVALID,
                                         "The HTTP method used is invalid for this URL");
    }
  }

  /* No handler matches, generate not found */
  {
    int ret;

    ret = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_NOT_FOUND,
                                      TALER_EC_ENDPOINT_UNKNOWN,
                                      "No handler found for the given URL");
    GNUNET_async_scope_restore (&old_scope);
    return ret;
  }
}


/**
 * Load configuration parameters for the exchange
 * server into the corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static int
exchange_serve_process_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (TEH_cfg,
                                             "exchange",
                                             "MAX_REQUESTS",
                                             &req_max))
  {
    req_max = ULONG_LONG_MAX;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           "exchange",
                                           "MAX_KEYS_CACHING",
                                           &TEH_max_keys_caching))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "MAX_KEYS_CACHING",
                               "valid relative time expected");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (TEH_cfg,
                                               "exchange",
                                               "KEYDIR",
                                               &TEH_exchange_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (TEH_cfg,
                                               "exchange",
                                               "REVOCATION_DIR",
                                               &TEH_revocation_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "REVOCATION_DIR");
    return GNUNET_SYSERR;
  }
  {
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "master_public_key");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (master_public_key_str,
                                                    strlen (
                                                      master_public_key_str),
                                                    &TEH_master_public_key.
                                                    eddsa_pub))
    {
      fprintf (stderr,
               "Invalid master public key given in exchange configuration.");
      GNUNET_free (master_public_key_str);
      return GNUNET_SYSERR;
    }
    GNUNET_free (master_public_key_str);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Launching exchange with public key `%s'...\n",
              GNUNET_p2s (&TEH_master_public_key.eddsa_pub));

  if ( (GNUNET_OK !=
        TEH_VALIDATION_init (TEH_cfg)) ||
       (GNUNET_OK !=
        TEH_WIRE_init ()) )
    return GNUNET_SYSERR;


  if (NULL ==
      (TEH_plugin = TALER_EXCHANGEDB_plugin_load (TEH_cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    TEH_VALIDATION_done ();
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_MHD_parse_config (TEH_cfg,
                              "exchange",
                              &serve_port,
                              &serve_unixpath,
                              &unixpath_mode))
  {
    TEH_VALIDATION_done ();
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Called when the main thread exits, writes out performance
 * stats if requested.
 */
static void
write_stats (void)
{
  struct GNUNET_DISK_FileHandle *fh;
  pid_t pid = getpid ();
  char *benchmark_dir;
  char *s;
  struct rusage usage;

  benchmark_dir = getenv ("GNUNET_BENCHMARK_DIR");
  if (NULL == benchmark_dir)
    return;
  GNUNET_asprintf (&s,
                   "%s/taler-exchange-%llu-%llu.txt",
                   benchmark_dir,
                   (unsigned long long) pid);
  fh = GNUNET_DISK_file_open (s,
                              (GNUNET_DISK_OPEN_WRITE
                               | GNUNET_DISK_OPEN_TRUNCATE
                               | GNUNET_DISK_OPEN_CREATE),
                              (GNUNET_DISK_PERM_USER_READ
                               | GNUNET_DISK_PERM_USER_WRITE));
  GNUNET_free (s);
  if (NULL == fh)
    return; /* permission denied? */

  /* Collect stats, summed up for all threads */
  GNUNET_assert (0 ==
                 getrusage (RUSAGE_SELF,
                            &usage));
  GNUNET_asprintf (&s,
                   "time_exchange sys %llu user %llu\n",
                   (unsigned long long) (usage.ru_stime.tv_sec * 1000 * 1000
                                         + usage.ru_stime.tv_usec),
                   (unsigned long long) (usage.ru_utime.tv_sec * 1000 * 1000
                                         + usage.ru_utime.tv_usec));
  GNUNET_assert (GNUNET_SYSERR !=
                 GNUNET_DISK_file_write_blocking (fh,
                                                  s,
                                                  strlen (s)));
  GNUNET_free (s);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_DISK_file_close (fh));
}


/* Developer logic for supporting the `-f' option. */
#if HAVE_DEVELOPER


/**
 * Option `-f' (specifies an input file to give to the HTTP server).
 */
static char *input_filename;

/**
 * We finished handling the request and should now terminate.
 */
static int do_terminate;

/**
 * Run 'nc' or 'ncat' as a fake HTTP client using #input_filename
 * as the input for the request.  If launching the client worked,
 * run the #TEH_KS_loop() event loop as usual.
 *
 * @return child pid
 */
static pid_t
run_fake_client (void)
{
  pid_t cld;
  char ports[6];
  int fd;

  if (0 == strcmp (input_filename,
                   "-"))
    fd = STDIN_FILENO;
  else
    fd = open (input_filename, O_RDONLY);
  if (-1 == fd)
  {
    fprintf (stderr,
             "Failed to open `%s': %s\n",
             input_filename,
             strerror (errno));
    return -1;
  }
  /* Fake HTTP client request with #input_filename as input.
     We do this using the nc tool. */
  GNUNET_snprintf (ports,
                   sizeof (ports),
                   "%u",
                   serve_port);
  if (0 == (cld = fork ()))
  {
    GNUNET_break (0 == close (0));
    GNUNET_break (0 == dup2 (fd, 0));
    GNUNET_break (0 == close (fd));
    if ( (0 != execlp ("nc",
                       "nc",
                       "localhost",
                       ports,
                       "-w", "30",
                       NULL)) &&
         (0 != execlp ("ncat",
                       "ncat",
                       "localhost",
                       ports,
                       "-i", "30",
                       NULL)) )
    {
      fprintf (stderr,
               "Failed to run both `nc' and `ncat': %s\n",
               strerror (errno));
    }
    _exit (1);
  }
  /* parent process */
  if (0 != strcmp (input_filename,
                   "-"))
    GNUNET_break (0 == close (fd));
  return cld;
}


/**
 * Signature of the callback used by MHD to notify the application
 * about completed connections.  If we are running in test-mode with
 * an #input_filename, this function is used to terminate the HTTPD
 * after the first request has been processed.
 *
 * @param cls client-defined closure, NULL
 * @param connection connection handle (ignored)
 * @param socket_context socket-specific pointer (ignored)
 * @param toe reason for connection notification
 */
static void
connection_done (void *cls,
                 struct MHD_Connection *connection,
                 void **socket_context,
                 enum MHD_ConnectionNotificationCode toe)
{
  (void) cls;
  (void) connection;
  (void) socket_context;
  /* We only act if the connection is closed. */
  if (MHD_CONNECTION_NOTIFY_CLOSED != toe)
    return;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Connection done!\n");
  do_terminate = GNUNET_YES;
}


/**
 * Run the exchange to serve a single request only, without threads.
 *
 * @return #GNUNET_OK on success
 */
static int
run_single_request (void)
{
  pid_t cld;
  int status;

  /* run only the testfile input, then terminate */
  mhd
    = MHD_start_daemon (MHD_USE_PIPE_FOR_SHUTDOWN
                        | MHD_USE_DEBUG | MHD_USE_DUAL_STACK
                        | MHD_USE_TCP_FASTOPEN,
                        0, /* pick free port */
                        NULL, NULL,
                        &handle_mhd_request, NULL,
                        MHD_OPTION_LISTEN_BACKLOG_SIZE, (unsigned int) 10,
                        MHD_OPTION_EXTERNAL_LOGGER, &TALER_MHD_handle_logs,
                        NULL,
                        MHD_OPTION_NOTIFY_COMPLETED,
                        &handle_mhd_completion_callback, NULL,
                        MHD_OPTION_CONNECTION_TIMEOUT, connection_timeout,
                        MHD_OPTION_NOTIFY_CONNECTION, &connection_done, NULL,
                        MHD_OPTION_END);
  if (NULL == mhd)
  {
    fprintf (stderr,
             "Failed to start HTTP server.\n");
    return GNUNET_SYSERR;
  }
  serve_port = MHD_get_daemon_info (mhd,
                                    MHD_DAEMON_INFO_BIND_PORT)->port;
  cld = run_fake_client ();
  if (-1 == cld)
    return GNUNET_SYSERR;
  /* run the event loop until #connection_done() was called */
  while (GNUNET_NO == do_terminate)
  {
    fd_set rs;
    fd_set ws;
    fd_set es;
    struct timeval tv;
    MHD_UNSIGNED_LONG_LONG timeout;
    int maxsock = -1;
    int have_tv;

    FD_ZERO (&rs);
    FD_ZERO (&ws);
    FD_ZERO (&es);
    if (MHD_YES !=
        MHD_get_fdset (mhd,
                       &rs,
                       &ws,
                       &es,
                       &maxsock))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    have_tv = MHD_get_timeout (mhd,
                               &timeout);
    tv.tv_sec = timeout / 1000;
    tv.tv_usec = 1000 * (timeout % 1000);
    if (-1 == select (maxsock + 1,
                      &rs,
                      &ws,
                      &es,
                      have_tv ? &tv : NULL))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    MHD_run (mhd);
  }
  MHD_stop_daemon (mhd);
  mhd = NULL;
  if (cld != waitpid (cld,
                      &status,
                      0))
    fprintf (stderr,
             "Waiting for `nc' child failed: %s\n",
             strerror (errno));
  return GNUNET_OK;
}


/* end of HAVE_DEVELOPER */
#endif


/**
 * Run the ordinary multi-threaded main loop and the logic to
 * wait for CTRL-C.
 *
 * @param fh listen socket
 * @param argv command line arguments
 * @return #GNUNET_OK on success
 */
static int
run_main_loop (int fh,
               char *const *argv)
{
  int ret;

  mhd
    = MHD_start_daemon (MHD_USE_SELECT_INTERNALLY | MHD_USE_PIPE_FOR_SHUTDOWN
                        | MHD_USE_DEBUG | MHD_USE_DUAL_STACK
                        | MHD_USE_INTERNAL_POLLING_THREAD
                        | MHD_USE_TCP_FASTOPEN,
                        (-1 == fh) ? serve_port : 0,
                        NULL, NULL,
                        &handle_mhd_request, NULL,
                        MHD_OPTION_THREAD_POOL_SIZE, (unsigned int) 32,
                        MHD_OPTION_LISTEN_BACKLOG_SIZE, (unsigned int) 1024,
                        MHD_OPTION_LISTEN_SOCKET, fh,
                        MHD_OPTION_EXTERNAL_LOGGER, &TALER_MHD_handle_logs,
                        NULL,
                        MHD_OPTION_NOTIFY_COMPLETED,
                        &handle_mhd_completion_callback, NULL,
                        MHD_OPTION_CONNECTION_TIMEOUT, connection_timeout,
                        MHD_OPTION_END);
  if (NULL == mhd)
  {
    fprintf (stderr,
             "Failed to start HTTP server.\n");
    return GNUNET_SYSERR;
  }

  atexit (&write_stats);
  ret = TEH_KS_loop ();
  switch (ret)
  {
  case GNUNET_OK:
  case GNUNET_SYSERR:
    MHD_stop_daemon (mhd);
    break;
  case GNUNET_NO:
    {
      MHD_socket sock = MHD_quiesce_daemon (mhd);
      pid_t chld;
      int flags;

      /* Set flags to make 'sock' inherited by child */
      flags = fcntl (sock, F_GETFD);
      GNUNET_assert (-1 != flags);
      flags &= ~FD_CLOEXEC;
      GNUNET_assert (-1 != fcntl (sock, F_SETFD, flags));
      chld = fork ();
      if (-1 == chld)
      {
        /* fork() failed, continue clean up, unhappily */
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                             "fork");
      }
      if (0 == chld)
      {
        char pids[12];

        /* exec another taler-exchange-httpd, passing on the listen socket;
           as in systemd it is expected to be on FD #3 */
        if (3 != dup2 (sock, 3))
        {
          GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                               "dup2");
          _exit (1);
        }
        /* Tell the child that it is the desired recipient for FD #3 */
        GNUNET_snprintf (pids,
                         sizeof (pids),
                         "%u",
                         getpid ());
        setenv ("LISTEN_PID", pids, 1);
        setenv ("LISTEN_FDS", "1", 1);
        /* Finally, exec the (presumably) more recent exchange binary */
        execvp ("taler-exchange-httpd",
                argv);
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                             "execvp");
        _exit (1);
      }
      /* we're the original process, handle remaining contextions
         before exiting; as the listen socket is no longer used,
         close it here */
      GNUNET_break (0 == close (sock));
      while (0 != MHD_get_daemon_info (mhd,
                                       MHD_DAEMON_INFO_CURRENT_CONNECTIONS)->
             num_connections)
        sleep (1);
      /* Now we're really done, practice clean shutdown */
      MHD_stop_daemon (mhd);
    }
    break;
  default:
    GNUNET_break (0);
    MHD_stop_daemon (mhd);
    break;
  }

  return ret;
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
  char *cfgfile = NULL;
  char *loglev = NULL;
  char *logfile = NULL;
  int connection_close = GNUNET_NO;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('C',
                               "connection-close",
                               "force HTTP connections to be closed after each request",
                               &connection_close),
    GNUNET_GETOPT_option_cfgfile (&cfgfile),
    GNUNET_GETOPT_option_uint ('t',
                               "timeout",
                               "SECONDS",
                               "after how long do connections timeout by default (in seconds)",
                               &connection_timeout),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
#if HAVE_DEVELOPER
    GNUNET_GETOPT_option_filename ('f',
                                   "file-input",
                                   "FILENAME",
                                   "run in test-mode using FILENAME as the HTTP request to process, use '-' to read from stdin",
                                   &input_filename),
#endif
    GNUNET_GETOPT_option_help (
      "HTTP server providing a RESTful API to access a Taler exchange"),
    GNUNET_GETOPT_option_loglevel (&loglev),
    GNUNET_GETOPT_option_logfile (&logfile),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;
  const char *listen_pid;
  const char *listen_fds;
  int fh = -1;
  enum TALER_MHD_GlobalOptions go;

  if (0 >=
      GNUNET_GETOPT_run ("taler-exchange-httpd",
                         options,
                         argc, argv))
    return 1;
  go = TALER_MHD_GO_NONE;
  if (connection_close)
    go |= TALER_MHD_GO_FORCE_CONNECTION_CLOSE;
  TALER_MHD_setup (go);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-httpd",
                                   (NULL == loglev) ? "INFO" : loglev,
                                   logfile));
  if (NULL == cfgfile)
    cfgfile = GNUNET_strdup (GNUNET_OS_project_data_get ()->user_config_file);
  TEH_cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_load (TEH_cfg,
                                 cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _ ("Malformed configuration file `%s', exit ...\n"),
                cfgfile);
    GNUNET_free_non_null (cfgfile);
    return 1;
  }
  GNUNET_free_non_null (cfgfile);
  if (GNUNET_OK !=
      exchange_serve_process_config ())
    return 1;
  TEH_load_terms (TEH_cfg);

  /* check for systemd-style FD passing */
  listen_pid = getenv ("LISTEN_PID");
  listen_fds = getenv ("LISTEN_FDS");
  if ( (NULL != listen_pid) &&
       (NULL != listen_fds) &&
       (getpid () == strtol (listen_pid,
                             NULL,
                             10)) &&
       (1 == strtoul (listen_fds,
                      NULL,
                      10)) )
  {
    int flags;

    fh = 3;
    flags = fcntl (fh,
                   F_GETFD);
    if ( (-1 == flags) &&
         (EBADF == errno) )
    {
      fprintf (stderr,
               "Bad listen socket passed, ignored\n");
      fh = -1;
    }
    flags |= FD_CLOEXEC;
    if ( (-1 != fh) &&
         (0 != fcntl (fh,
                      F_SETFD,
                      flags)) )
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "fcntl");
  }

  /* initialize #internal_key_state with an RC of 1 */
  ret = TEH_KS_init ();
  if (GNUNET_OK == ret)
  {
#if HAVE_DEVELOPER
    if (NULL != input_filename)
    {
      ret = run_single_request ();
    }
    else
#endif
    {
      /* consider unix path */
      if ( (-1 == fh) &&
           (NULL != serve_unixpath) )
      {
        fh = TALER_MHD_open_unix_path (serve_unixpath,
                                       unixpath_mode);
        if (-1 == fh)
          return 1;
      }
      ret = run_main_loop (fh,
                           argv);
    }
    /* release #internal_key_state */
    TEH_KS_free ();
  }
  TALER_EXCHANGEDB_plugin_unload (TEH_plugin);
  TEH_VALIDATION_done ();
  return (GNUNET_SYSERR == ret) ? 1 : 0;
}


/* end of taler-exchange-httpd.c */
