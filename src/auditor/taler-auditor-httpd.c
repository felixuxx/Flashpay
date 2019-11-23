/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2018 Inria and GNUnet e.V.

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
#include "taler-auditor-httpd_deposit-confirmation.h"
#include "taler-auditor-httpd_exchanges.h"
#include "taler-auditor-httpd_responses.h"
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
int TAH_auditor_connection_close;

/**
 * The auditor's configuration (global)
 */
struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
struct TALER_AUDITORDB_Plugin *TAH_plugin;

/**
 * Public key of this auditor.
 */
static struct TALER_AuditorPublicKeyP auditor_pub;

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
 * Path for the unix domain-socket to run the daemon on.
 */
static char *serve_unixpath;

/**
 * File mode for unix-domain socket.
 */
static mode_t unixpath_mode;

/**
 * Our currency.
 */
static char *currency;

/**
 * Pipe used for signaling reloading of our key state.
 */
static int reload_pipe[2];


/**
 * Handle a signal, writing relevant signal numbers to the pipe.
 *
 * @param signal_number the signal number
 */
static void
handle_signal (int signal_number)
{
  ssize_t res;
  char c = signal_number;

  res = write (reload_pipe[1],
               &c,
               1);
  if ( (res < 0) &&
       (EINTR != errno) )
  {
    GNUNET_break (0);
    return;
  }
  if (0 == res)
  {
    GNUNET_break (0);
    return;
  }
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigint ()
{
  handle_signal (SIGINT);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigterm ()
{
  handle_signal (SIGTERM);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sighup ()
{
  handle_signal (SIGHUP);
}


/**
 * Call #handle_signal() to pass the received signal via
 * the control pipe.
 */
static void
handle_sigchld ()
{
  handle_signal (SIGCHLD);
}


/**
 * Read signals from a pipe in a loop, and reload keys from disk if
 * SIGUSR1 is received, terminate if SIGTERM/SIGINT is received, and
 * restart if SIGHUP is received.
 *
 * @return #GNUNET_SYSERR on errors,
 *         #GNUNET_OK to terminate normally
 *         #GNUNET_NO to restart an update version of the binary
 */
static int
signal_loop (void)
{
  struct GNUNET_SIGNAL_Context *sigterm;
  struct GNUNET_SIGNAL_Context *sigint;
  struct GNUNET_SIGNAL_Context *sighup;
  struct GNUNET_SIGNAL_Context *sigchld;
  int ret;
  char c;
  ssize_t res;

  if (0 != pipe (reload_pipe))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "pipe");
    return GNUNET_SYSERR;
  }
  sigterm = GNUNET_SIGNAL_handler_install (SIGTERM,
                                           &handle_sigterm);
  sigint = GNUNET_SIGNAL_handler_install (SIGINT,
                                          &handle_sigint);
  sighup = GNUNET_SIGNAL_handler_install (SIGHUP,
                                          &handle_sighup);
  sigchld = GNUNET_SIGNAL_handler_install (SIGCHLD,
                                           &handle_sigchld);

  ret = 2;
  while (2 == ret)
  {
    errno = 0;
    res = read (reload_pipe[0],
                &c,
                1);
    if ((res < 0) && (EINTR != errno))
    {
      GNUNET_break (0);
      ret = GNUNET_SYSERR;
      break;
    }
    if (EINTR == errno)
    {
      ret = 2;
      continue;
    }
    switch (c)
    {
    case SIGTERM:
    case SIGINT:
      /* terminate */
      ret = GNUNET_OK;
      break;
    case SIGHUP:
      /* restart updated binary */
      ret = GNUNET_NO;
      break;
#if HAVE_DEVELOPER
    case SIGCHLD:
      /* running in test-mode, test finished, terminate */
      ret = GNUNET_OK;
      break;
#endif
    default:
      /* unexpected character */
      GNUNET_break (0);
      break;
    }
  }
  GNUNET_SIGNAL_handler_uninstall (sigterm);
  GNUNET_SIGNAL_handler_uninstall (sigint);
  GNUNET_SIGNAL_handler_uninstall (sighup);
  GNUNET_SIGNAL_handler_uninstall (sigchld);
  GNUNET_break (0 == close (reload_pipe[0]));
  GNUNET_break (0 == close (reload_pipe[1]));
  return ret;
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
  if (NULL == *con_cls)
    return;
  TALER_MHD_parse_post_cleanup_callback (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle a "/version" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
static int
handle_version (struct TAH_RequestHandler *rh,
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
    ver = json_pack ("{s:s, s:s, s:o}",
                     "version", AUDITOR_PROTOCOL_VERSION,
                     "currency", currency,
                     "auditor_public_key", GNUNET_JSON_from_data_auto (
                       &auditor_pub));
  }
  if (NULL == ver)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  return TAH_RESPONSE_reply_json (connection,
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
  static struct TAH_RequestHandler handlers[] = {
    /* Our most popular handler (thus first!), used by merchants to
       probabilistically report us their deposit confirmations. */
    { "/deposit-confirmation", MHD_HTTP_METHOD_PUT, "application/json",
      NULL, 0,
      &TAH_DEPOSIT_CONFIRMATION_handler, MHD_HTTP_OK },
    { "/exchanges", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &TAH_EXCHANGES_handler, MHD_HTTP_OK },
    { "/version", MHD_HTTP_METHOD_GET, "application/json",
      NULL, 0,
      &handle_version, MHD_HTTP_OK },
    /* Landing page, for now tells humans to go away (FIXME: replace
       with auditor's welcome page!) */
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

    { NULL, NULL, NULL, NULL, 0, 0 }
  };
  struct TAH_RequestHandler *rh;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for URL '%s'\n",
              url);
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */
  for (unsigned int i = 0; NULL != handlers[i].url; i++)
  {
    rh = &handlers[i];
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
static int
auditor_serve_process_config ()
{
  char *pub;

  if (NULL ==
      (TAH_plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_MHD_parse_config (cfg,
                              "auditor",
                              &serve_port,
                              &serve_unixpath,
                              &unixpath_mode))
  {
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "TALER",
                                             "CURRENCY",
                                             &currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "TALER",
                               "CURRENCY");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "AUDITOR",
                                             "PUBLIC_KEY",
                                             &pub))
  {
    /* Fall back to trying to read private key */
    char *auditor_key_file;
    struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;

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
    eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (auditor_key_file);
    if (NULL == eddsa_priv)
    {
      /* Both failed, complain! */
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "AUDITOR",
                                 "PUBLIC_KEY");
      fprintf (stderr,
               "Failed to initialize auditor key from file `%s'\n",
               auditor_key_file);
      GNUNET_free (auditor_key_file);
      return 1;
    }
    GNUNET_free (auditor_key_file);
    GNUNET_CRYPTO_eddsa_key_get_public (eddsa_priv,
                                        &auditor_pub.eddsa_pub);
    GNUNET_free (eddsa_priv);
  }
  else
  {
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (pub,
                                                    strlen (pub),
                                                    &auditor_pub.eddsa_pub))
    {
      fprintf (stderr,
               "Invalid public key given in auditor configuration.");
      GNUNET_free (pub);
      return GNUNET_SYSERR;
    }
    GNUNET_free (pub);
  }
  return GNUNET_OK;
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
  char *cfgfile = NULL;
  char *loglev = NULL;
  char *logfile = NULL;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('C',
                               "connection-close",
                               "force HTTP connections to be closed after each request",
                               &TAH_auditor_connection_close),
    GNUNET_GETOPT_option_cfgfile (&cfgfile),
    GNUNET_GETOPT_option_uint ('t',
                               "timeout",
                               "SECONDS",
                               "after how long do connections timeout by default (in seconds)",
                               &connection_timeout),
    GNUNET_GETOPT_option_help (
      "HTTP server providing a RESTful API to access a Taler auditor"),
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
      GNUNET_GETOPT_run ("taler-auditor-httpd",
                         options,
                         argc, argv))
    return 1;
  go = TALER_MHD_GO_NONE;
  if (TAH_auditor_connection_close)
    go |= TALER_MHD_GO_FORCE_CONNECTION_CLOSE;
  TALER_MHD_setup (go);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor-httpd",
                                   (NULL == loglev) ? "INFO" : loglev,
                                   logfile));
  if (NULL == cfgfile)
    cfgfile = GNUNET_strdup (GNUNET_OS_project_data_get ()->user_config_file);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_load (cfg,
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
      auditor_serve_process_config ())
    return 1;

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

  /* consider unix path */
  if ( (-1 == fh) &&
       (NULL != serve_unixpath) )
  {
    fh = TALER_MHD_open_unix_path (serve_unixpath,
                                   unixpath_mode);
    if (-1 == fh)
      return 1;
  }

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
    return 1;
  }

  /* normal behavior */
  ret = signal_loop ();
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

        /* exec another taler-auditor-httpd, passing on the listen socket;
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
        /* Finally, exec the (presumably) more recent auditor binary */
        execvp ("taler-auditor-httpd",
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
  TALER_AUDITORDB_plugin_unload (TAH_plugin);
  return (GNUNET_SYSERR == ret) ? 1 : 0;
}


/* end of taler-auditor-httpd.c */
