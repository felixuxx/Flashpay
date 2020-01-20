/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2019 Taler Systems SA

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
#include "taler-exchange-httpd_reserve_status.h"
#include "taler-exchange-httpd_reserve_withdraw.h"
#include "taler-exchange-httpd_recoup.h"
#include "taler-exchange-httpd_refresh_link.h"
#include "taler-exchange-httpd_refresh_melt.h"
#include "taler-exchange-httpd_refresh_reveal.h"
#include "taler-exchange-httpd_terms.h"
#include "taler-exchange-httpd_track_transfer.h"
#include "taler-exchange-httpd_track_transaction.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_exchangedb_plugin.h"
#include "taler-exchange-httpd_validation.h"


/**
 * Backlog for listen operation on unix
 * domain sockets.
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
struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * How long is caching /keys allowed at most?
 */
struct GNUNET_TIME_Relative TEH_max_keys_caching;

/**
 * Master public key (according to the
 * configuration in the exchange directory).
 */
struct TALER_MasterPublicKeyP TEH_master_public_key;

/**
 * Our DB plugin.
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
 * Initialize the database by creating tables and indices.
 */
static int init_db;

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
 */
static unsigned long long req_max;


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
  /* check that we didn't leave any transactions hanging */
  /* NOTE: In high-performance production, we might want to
     remove this. */
  TEH_plugin->preflight (TEH_plugin->cls,
                         TEH_plugin->get_session (TEH_plugin->cls));
}


/**
 * Return GNUNET_YES if given a valid correlation ID and
 * GNUNET_NO otherwise.
 *
 * @returns #GNUNET_YES iff given a valid correlation ID
 */
static int
is_valid_correlation_id (const char *correlation_id)
{
  if (strlen (correlation_id) >= 64)
    return GNUNET_NO;
  for (size_t i = 0; i < strlen (correlation_id); i++)
    if (! (isalnum (correlation_id[i]) || (correlation_id[i] == '-')))
      return GNUNET_NO;
  return GNUNET_YES;
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
    /* Landing page, tell humans to go away. */
    { "/", MHD_HTTP_METHOD_GET, "text/plain",
      "Hello, I'm the Taler exchange. This HTTP server is not for humans.\n", 0,
      &TEH_MHD_handler_static_response, MHD_HTTP_OK },
    /* /robots.txt: disallow everything */
    { "/robots.txt", MHD_HTTP_METHOD_GET, "text/plain",
      "User-agent: *\nDisallow: /\n", 0,
      &TEH_MHD_handler_static_response, MHD_HTTP_OK },
    /* AGPL licensing page, redirect to source. As per the AGPL-license,
       every deployment is required to offer the user a download of the
       source. We make this easy by including a redirect to the source
       here. */
    { "/agpl", MHD_HTTP_METHOD_GET, "text/plain",
      NULL, 0,
      &TEH_MHD_handler_agpl_redirect, MHD_HTTP_FOUND },
    /* Terms of service */
    { "/terms", MHD_HTTP_METHOD_GET, NULL,
      NULL, 0,
      &TEH_handler_terms, MHD_HTTP_OK },
    /* Privacy policy */
    { "/privacy", MHD_HTTP_METHOD_GET, NULL,
      NULL, 0,
      &TEH_handler_privacy, MHD_HTTP_OK },
    /* Return key material and fundamental properties for this exchange */
    { "/keys", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TEH_KS_handler_keys, MHD_HTTP_OK },
    { "/keys", NULL, "text/plain",
      "Only GET is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    /* Requests for wiring information */
    { "/wire", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TEH_WIRE_handler_wire, MHD_HTTP_OK },
    { "/wire", NULL, "text/plain",
      "Only GET is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    /* Withdrawing coins / interaction with reserves */
    { "/reserve/status", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TEH_RESERVE_handler_reserve_status, MHD_HTTP_OK },
    { "/reserve/status", NULL, "text/plain",
      "Only GET is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { "/reserve/withdraw", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_RESERVE_handler_reserve_withdraw, MHD_HTTP_OK },
    { "/reserve/withdraw", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    /* Depositing coins */
    { "/deposit", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_DEPOSIT_handler_deposit, MHD_HTTP_OK },
    { "/deposit", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    /* Refunding coins */
    { "/refund", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_REFUND_handler_refund, MHD_HTTP_OK },
    { "/refund", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    /* Dealing with change */
    { "/refresh/melt", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_REFRESH_handler_refresh_melt, MHD_HTTP_OK },
    { "/refresh/melt", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { "/refresh/reveal", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_REFRESH_handler_refresh_reveal, MHD_HTTP_OK },
    { "/refresh/reveal", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { "/refresh/reveal", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_REFRESH_handler_refresh_reveal, MHD_HTTP_OK },
    { "/refresh/reveal", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { "/refresh/link", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TEH_REFRESH_handler_refresh_link, MHD_HTTP_OK },
    { "/refresh/link", NULL, "text/plain",
      "Only GET is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { "/track/transfer", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TEH_TRACKING_handler_track_transfer, MHD_HTTP_OK },
    { "/track/transfer", NULL, "text/plain",
      "Only GET is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },
    { "/track/transaction", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_TRACKING_handler_track_transaction, MHD_HTTP_OK },
    { "/track/transaction", NULL, "text/plain",
      "Only POST is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { "/recoup", MHD_HTTP_METHOD_POST, "application/json",
      NULL, 0,
      &TEH_RECOUP_handler_recoup, MHD_HTTP_OK },
    { "/refresh/link", NULL, "text/plain",
      "Only GET is allowed", 0,
      &TEH_MHD_handler_send_json_pack_error, MHD_HTTP_METHOD_NOT_ALLOWED },

    { NULL, NULL, NULL, NULL, 0, NULL, 0 }
  };
  static struct TEH_RequestHandler h404 = {
    "", NULL, "text/html",
    "<html><title>404: not found</title></html>", 0,
    &TEH_MHD_handler_static_response, MHD_HTTP_NOT_FOUND
  };
  struct ExchangeHttpRequestClosure *ecls = *con_cls;
  int ret;
  void **inner_cls;
  struct GNUNET_AsyncScopeSave old_scope;
  const char *correlation_id = NULL;

  (void) cls;
  (void) version;
  if (NULL == ecls)
  {
    unsigned long long cnt;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO, "Handling new request\n");
    cnt = __sync_add_and_fetch (&req_count, 1LLU);
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
        (GNUNET_YES != is_valid_correlation_id (correlation_id)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "illegal incoming correlation ID\n");
      correlation_id = NULL;
    }
  }

  inner_cls = &ecls->opaque_post_parsing_context;
  GNUNET_async_scope_enter (&ecls->async_scope_id, &old_scope);
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
    ret = ecls->rh->handler (ecls->rh,
                             connection,
                             inner_cls,
                             upload_data,
                             upload_data_size);
    GNUNET_async_scope_restore (&old_scope);
    return ret;
  }
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */
  for (unsigned int i = 0; NULL != handlers[i].url; i++)
  {
    struct TEH_RequestHandler *rh = &handlers[i];

    if (0 != strcmp (url, rh->url))
      continue;

    /* The URL is a match!  What we now do depends on the method. */
    if (0 == strcasecmp (method, MHD_HTTP_METHOD_OPTIONS))
    {
      GNUNET_async_scope_restore (&old_scope);
      return TALER_MHD_reply_cors_preflight (connection);
    }

    if ( (NULL == rh->method) ||
         (0 == strcasecmp (method,
                           rh->method)) )
    {
      /* cache to avoid the loop next time */
      ecls->rh = rh;
      /* run handler */
      ret = rh->handler (rh,
                         connection,
                         inner_cls,
                         upload_data,
                         upload_data_size);
      GNUNET_async_scope_restore (&old_scope);
      return ret;
    }
  }
  /* No handler matches, generate not found */
  ret = TEH_MHD_handler_static_response (&h404,
                                         connection,
                                         inner_cls,
                                         upload_data,
                                         upload_data_size);
  GNUNET_async_scope_restore (&old_scope);
  return ret;
}


/**
 * Load configuration parameters for the exchange
 * server into the corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static int
exchange_serve_process_config ()
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "exchange",
                                             "MAX_REQUESTS",
                                             &req_max))
  {
    req_max = ULONG_LONG_MAX;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
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
      GNUNET_CONFIGURATION_get_value_filename (cfg,
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
      GNUNET_CONFIGURATION_get_value_filename (cfg,
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
    char *currency_string;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "taler",
                                               "CURRENCY",
                                               &currency_string))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "taler",
                                 "CURRENCY");
      return GNUNET_SYSERR;
    }
    if (strlen (currency_string) >= TALER_CURRENCY_LEN)
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 "taler",
                                 "CURRENCY",
                                 "Value is too long");
      GNUNET_free (currency_string);
      return GNUNET_SYSERR;
    }
    GNUNET_free (currency_string);
  }
  {
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
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
        TEH_VALIDATION_init (cfg)) ||
       (GNUNET_OK !=
        TEH_WIRE_init ()) )
    return GNUNET_SYSERR;


  if (NULL ==
      (TEH_plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    TEH_VALIDATION_done ();
    return GNUNET_SYSERR;
  }
  if (0 != init_db)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Ensuring that tables and indices are created!\n");
    TEH_plugin->create_tables (TEH_plugin->cls);
  }

  if (GNUNET_OK !=
      TALER_MHD_parse_config (cfg,
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
write_stats ()
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
run_fake_client ()
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
run_single_request ()
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
    GNUNET_GETOPT_option_flag ('i',
                               "init-db",
                               "create database tables and indicies if necessary",
                               &init_db),
    GNUNET_GETOPT_option_uint ('t',
                               "timeout",
                               "SECONDS",
                               "after how long do connections timeout by default (in seconds)",
                               &connection_timeout),
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
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_load (cfg, cfgfile))
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
  TEH_load_terms (cfg);

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
  if (GNUNET_OK ==
      TEH_KS_init ())
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
