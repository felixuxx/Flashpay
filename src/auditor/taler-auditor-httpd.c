/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file taler-auditor-httpd.c
 * @brief Serve the HTTP interface of the auditor
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
#include "taler_auditordb_lib.h"
#include "taler_exchangedb_lib.h"
#include "taler-auditor-httpd_deposit-confirmation.h"
#include "taler-auditor-httpd_exchanges.h"
#include "taler-auditor-httpd_mhd.h"
#include "taler-auditor-httpd.h"

/**
 * Auditor protocol version string.
 *
 * Taler protocol version in the format CURRENT:REVISION:AGE
 * as used by GNU libtool.  See
 * https://www.gnu.org/software/libtool/manual/html_node/Libtool-versioning.html
 *
 * Please be very careful when updating and follow
 * https://www.gnu.org/software/libtool/manual/html_node/Updating-version-info.html#Updating-version-info
 * precisely.  Note that this version has NOTHING to do with the
 * release version, and the format is NOT the same that semantic
 * versioning uses either.
 */
#define AUDITOR_PROTOCOL_VERSION "0:0:0"

/**
 * Backlog for listen operation on unix domain sockets.
 */
#define UNIX_BACKLOG 500

/**
 * Should we return "Connection: close" in each response?
 */
static int auditor_connection_close;

/**
 * The auditor's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
struct TALER_AUDITORDB_Plugin *TAH_plugin;

/**
 * Our DB plugin to talk to the *exchange* database.
 */
struct TALER_EXCHANGEDB_Plugin *TAH_eplugin;

/**
 * Public key of this auditor.
 */
static struct TALER_AuditorPublicKeyP auditor_pub;

/**
 * Default timeout in seconds for HTTP requests.
 */
static unsigned int connection_timeout = 30;

/**
 * Return value from main()
 */
static int global_ret;

/**
 * Port to run the daemon on.
 */
static uint16_t serve_port;

/**
 * Our currency.
 */
char *TAH_currency;


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
  (void) cls;
  (void) connection;
  (void) toe;
  if (NULL == *con_cls)
    return;
  TALER_MHD_parse_post_cleanup_callback (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle a "/config" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
static MHD_RESULT
handle_config (struct TAH_RequestHandler *rh,
               struct MHD_Connection *connection,
               void **connection_cls,
               const char *upload_data,
               size_t *upload_data_size)
{
  static json_t *ver; /* we build the response only once, keep around for next query! */

  (void) rh;
  (void) upload_data;
  (void) upload_data_size;
  (void) connection_cls;
  if (NULL == ver)
  {
    ver = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("name",
                               "taler-auditor"),
      GNUNET_JSON_pack_string ("version",
                               AUDITOR_PROTOCOL_VERSION),
      GNUNET_JSON_pack_string ("currency",
                               TAH_currency),
      GNUNET_JSON_pack_data_auto ("auditor_public_key",
                                  &auditor_pub));
  }
  if (NULL == ver)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  return TALER_MHD_reply_json (connection,
                               ver,
                               MHD_HTTP_OK);
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
  static struct TAH_RequestHandler handlers[] = {
    /* Our most popular handler (thus first!), used by merchants to
       probabilistically report us their deposit confirmations. */
    { "/deposit-confirmation", MHD_HTTP_METHOD_PUT, "application/json",
      NULL, 0,
      &TAH_DEPOSIT_CONFIRMATION_handler, MHD_HTTP_OK },
    { "/exchanges", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TAH_EXCHANGES_handler, MHD_HTTP_OK },
    { "/config", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &handle_config, MHD_HTTP_OK },
    /* Landing page, for now tells humans to go away
     * (NOTE: ideally, the reverse proxy will respond with a nicer page) */
    { "/", MHD_HTTP_METHOD_GET, "text/plain",
      "Hello, I'm the Taler auditor. This HTTP server is not for humans.\n", 0,
      &TAH_MHD_handler_static_response, MHD_HTTP_OK },
    /* /robots.txt: disallow everything */
    { "/robots.txt", MHD_HTTP_METHOD_GET, "text/plain",
      "User-agent: *\nDisallow: /\n", 0,
      &TAH_MHD_handler_static_response, MHD_HTTP_OK },
    /* AGPL licensing page, redirect to source. As per the AGPL-license,
       every deployment is required to offer the user a download of the
       source. We make this easy by including a redirect t the source
       here. */
    { "/agpl", MHD_HTTP_METHOD_GET, "text/plain",
      NULL, 0,
      &TAH_MHD_handler_agpl_redirect, MHD_HTTP_FOUND },
    { NULL, NULL, NULL, NULL, 0, NULL, 0 }
  };

  (void) cls;
  (void) version;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for URL '%s'\n",
              url);
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */
  for (unsigned int i = 0; NULL != handlers[i].url; i++)
  {
    struct TAH_RequestHandler *rh = &handlers[i];

    if ( (0 == strcasecmp (url,
                           rh->url)) &&
         ( (NULL == rh->method) ||
           (0 == strcasecmp (method,
                             rh->method)) ) )
      return rh->handler (rh,
                          connection,
                          con_cls,
                          upload_data,
                          upload_data_size);
  }
#define NOT_FOUND "<html><title>404: not found</title></html>"
  return TALER_MHD_reply_static (connection,
                                 MHD_HTTP_NOT_FOUND,
                                 "text/html",
                                 NOT_FOUND,
                                 strlen (NOT_FOUND));
#undef NOT_FOUND
}


/**
 * Load configuration parameters for the auditor
 * server into the corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
auditor_serve_process_config (void)
{
  if (NULL ==
      (TAH_plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem to interact with auditor database\n");
    return GNUNET_SYSERR;
  }
  if (NULL ==
      (TAH_eplugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem to query exchange database\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      TAH_eplugin->preflight (TAH_eplugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem to query exchange database\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &TAH_currency))
  {
    return GNUNET_SYSERR;
  }
  {
    char *pub;

    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "AUDITOR",
                                               "PUBLIC_KEY",
                                               &pub))
    {
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_public_key_from_string (pub,
                                                      strlen (pub),
                                                      &auditor_pub.eddsa_pub))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Invalid public key given in auditor configuration.");
        GNUNET_free (pub);
        return GNUNET_SYSERR;
      }
      GNUNET_free (pub);
      return GNUNET_OK;
    }
  }

  {
    /* Fall back to trying to read private key */
    char *auditor_key_file;
    struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "auditor",
                                                 "AUDITOR_PRIV_FILE",
                                                 &auditor_key_file))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "PUBLIC_KEY");
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "AUDITOR_PRIV_FILE");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_key_from_file (auditor_key_file,
                                           GNUNET_NO,
                                           &eddsa_priv))
    {
      /* Both failed, complain! */
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "PUBLIC_KEY");
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to initialize auditor key from file `%s'\n",
                  auditor_key_file);
      GNUNET_free (auditor_key_file);
      return 1;
    }
    GNUNET_free (auditor_key_file);
    GNUNET_CRYPTO_eddsa_key_get_public (&eddsa_priv,
                                        &auditor_pub.eddsa_pub);
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
  TEAH_DEPOSIT_CONFIRMATION_done ();
  if (NULL != mhd)
    MHD_stop_daemon (mhd);
  if (NULL != TAH_plugin)
  {
    TALER_AUDITORDB_plugin_unload (TAH_plugin);
    TAH_plugin = NULL;
  }
  if (NULL != TAH_eplugin)
  {
    TALER_EXCHANGEDB_plugin_unload (TAH_eplugin);
    TAH_eplugin = NULL;
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
  enum TALER_MHD_GlobalOptions go;
  int fh;

  (void) cls;
  (void) args;
  (void) cfgfile;
  go = TALER_MHD_GO_NONE;
  if (auditor_connection_close)
    go |= TALER_MHD_GO_FORCE_CONNECTION_CLOSE;
  TALER_MHD_setup (go);
  cfg = config;

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  if (GNUNET_OK !=
      auditor_serve_process_config ())
  {
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  TEAH_DEPOSIT_CONFIRMATION_init ();
  fh = TALER_MHD_bind (cfg,
                       "auditor",
                       &serve_port);
  if ( (0 == serve_port) &&
       (-1 == fh) )
  {
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  {
    struct MHD_Daemon *mhd;

    mhd = MHD_start_daemon (MHD_USE_SUSPEND_RESUME
                            | MHD_USE_PIPE_FOR_SHUTDOWN
                            | MHD_USE_DEBUG | MHD_USE_DUAL_STACK
                            | MHD_USE_TCP_FASTOPEN,
                            (-1 == fh) ? serve_port : 0,
                            NULL, NULL,
                            &handle_mhd_request, NULL,
                            MHD_OPTION_LISTEN_BACKLOG_SIZE,
                            (unsigned int) 1024,
                            MHD_OPTION_LISTEN_SOCKET,
                            fh,
                            MHD_OPTION_EXTERNAL_LOGGER,
                            &TALER_MHD_handle_logs,
                            NULL,
                            MHD_OPTION_NOTIFY_COMPLETED,
                            &handle_mhd_completion_callback,
                            NULL,
                            MHD_OPTION_CONNECTION_TIMEOUT,
                            connection_timeout,
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
}


/**
 * The main function of the taler-auditor-httpd server ("the auditor").
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
    GNUNET_GETOPT_option_flag ('C',
                               "connection-close",
                               "force HTTP connections to be closed after each request",
                               &auditor_connection_close),
    GNUNET_GETOPT_option_uint ('t',
                               "timeout",
                               "SECONDS",
                               "after how long do connections timeout by default (in seconds)",
                               &connection_timeout),
    GNUNET_GETOPT_option_help (
      "HTTP server providing a RESTful API to access a Taler auditor"),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-auditor-httpd",
                            "Taler auditor HTTP service",
                            options,
                            &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-auditor-httpd.c */
