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
#include "taler_auditordb_lib.h"
#include "taler-auditor-httpd_parsing.h"
#include "taler-auditor-httpd_mhd.h"
#include "taler-auditor-httpd.h"


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
  TAH_PARSE_post_cleanup_callback (*con_cls);
  *con_cls = NULL;
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
  static struct TAH_RequestHandler handlers[] =
    {
      /* Landing page, tell humans to go away. */
      { "/", MHD_HTTP_METHOD_GET, "text/plain",
        "Hello, I'm the Taler auditor. This HTTP server is not for humans.\n", 0,
        &TAH_MHD_handler_static_response, MHD_HTTP_OK },
      /* /robots.txt: disallow everything */
      { "/robots.txt", MHD_HTTP_METHOD_GET, "text/plain",
        "User-agent: *\nDisallow: /\n", 0,
        &TAH_MHD_handler_static_response, MHD_HTTP_OK },
      /* AGPL licensing page, redirect to source. As per the AGPL-license,
         every deployment is required to offer the user a download of the
         source. We make this easy by including a redirect to the source
         here. */
      { "/agpl", MHD_HTTP_METHOD_GET, "text/plain",
        NULL, 0,
        &TAH_MHD_handler_agpl_redirect, MHD_HTTP_FOUND },

      { NULL, NULL, NULL, NULL, 0, 0 }
    };
  static struct TAH_RequestHandler h404 =
    {
      "", NULL, "text/html",
      "<html><title>404: not found</title></html>", 0,
      &TAH_MHD_handler_static_response, MHD_HTTP_NOT_FOUND
    };
  struct TAH_RequestHandler *rh;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for URL '%s'\n",
              url);
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET; /* treat HEAD as GET here, MHD will do the rest */
  for (unsigned int i=0;NULL != handlers[i].url;i++)
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
  return TAH_MHD_handler_static_response (&h404,
                                          connection,
                                          con_cls,
                                          upload_data,
                                          upload_data_size);
}


/**
 * Parse the configuration to determine on which port
 * or UNIX domain path we should run an HTTP service.
 *
 * @param section section of the configuration to parse ("auditor" or "auditor-admin")
 * @param[out] rport set to the port number, or 0 for none
 * @param[out] unix_path set to the UNIX path, or NULL for none
 * @param[out] unix_mode set to the mode to be used for @a unix_path
 * @return #GNUNET_OK on success
 */
static int
parse_port_config (const char *section,
                   uint16_t *rport,
                   char **unix_path,
                   mode_t *unix_mode)
{
  const char *choices[] = {"tcp", "unix"};
  const char *serve_type;
  unsigned long long port;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_choice (cfg,
                                             section,
                                             "serve",
                                             choices,
                                             &serve_type))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "serve",
                               "serve type required");
    return GNUNET_SYSERR;
  }

  if (0 == strcmp (serve_type, "tcp"))
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_number (cfg,
                                               section,
                                               "port",
                                               &port))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "port",
                                 "port number required");
      return GNUNET_SYSERR;
    }

    if ( (0 == port) ||
         (port > UINT16_MAX) )
    {
      fprintf (stderr,
               "Invalid configuration (value out of range): %llu is not a valid port\n",
               port);
      return GNUNET_SYSERR;
    }
    *rport = (uint16_t) port;
    *unix_path = NULL;
    return GNUNET_OK;
  }
  if (0 == strcmp (serve_type, "unix"))
  {
    struct sockaddr_un s_un;
    char *modestring;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 section,
                                                 "unixpath",
                                                 unix_path))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "unixpath",
                                 "unixpath required");
      return GNUNET_SYSERR;
    }
    if (strlen (*unix_path) >= sizeof (s_un.sun_path))
    {
      fprintf (stderr,
               "Invalid configuration: unix path too long\n");
      return GNUNET_SYSERR;
    }

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               section,
                                               "UNIXPATH_MODE",
                                               &modestring))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "UNIXPATH_MODE");
      return GNUNET_SYSERR;
    }
    errno = 0;
    *unix_mode = (mode_t) strtoul (modestring, NULL, 8);
    if (0 != errno)
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "UNIXPATH_MODE",
                                 "must be octal number");
      GNUNET_free (modestring);
      return GNUNET_SYSERR;
    }
    GNUNET_free (modestring);
    return GNUNET_OK;
  }
  /* not reached */
  GNUNET_assert (0);
  return GNUNET_SYSERR;
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
  if (NULL ==
      (TAH_plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      parse_port_config ("auditor",
                         &serve_port,
                         &serve_unixpath,
                         &unixpath_mode))
  {
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called for logging by MHD.
 *
 * @param cls closure, NULL
 * @param fm format string (`printf()`-style)
 * @param ap arguments to @a fm
 */
static void
handle_mhd_logs (void *cls,
                 const char *fm,
                 va_list ap)
{
  static int cache;
  char buf[2048];

  if (-1 == cache)
    return;
  if (0 == cache)
  {
    if (0 ==
        GNUNET_get_log_call_status (GNUNET_ERROR_TYPE_INFO,
                                    "auditor-httpd",
                                    __FILE__,
                                    __FUNCTION__,
                                    __LINE__))
    {
      cache = -1;
      return;
    }
  }
  cache = 1;
  vsnprintf (buf,
             sizeof (buf),
             fm,
             ap);
  GNUNET_log_from_nocheck (GNUNET_ERROR_TYPE_INFO,
                           "auditor-httpd",
                           "%s",
                           buf);
}


/**
 * Open UNIX domain socket for listining at @a unix_path with
 * permissions @a unix_mode.
 *
 * @param unix_path where to listen
 * @param unix_mode access permissions to set
 * @return -1 on error, otherwise the listen socket
 */
static int
open_unix_path (const char *unix_path,
                mode_t unix_mode)
{
  struct GNUNET_NETWORK_Handle *nh;
  struct sockaddr_un *un;
  int fd;

  if (sizeof (un->sun_path) <= strlen (unix_path))
  {
    fprintf (stderr,
             "unixpath `%s' too long\n",
             unix_path);
    return -1;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Creating listen socket '%s' with mode %o\n",
              unix_path,
              unix_mode);

  if (GNUNET_OK !=
      GNUNET_DISK_directory_create_for_file (unix_path))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "mkdir",
                              unix_path);
  }

  un = GNUNET_new (struct sockaddr_un);
  un->sun_family = AF_UNIX;
  strncpy (un->sun_path,
           unix_path,
           sizeof (un->sun_path) - 1);
  GNUNET_NETWORK_unix_precheck (un);

  if (NULL == (nh = GNUNET_NETWORK_socket_create (AF_UNIX,
                                                  SOCK_STREAM,
                                                  0)))
  {
    fprintf (stderr,
             "create failed for AF_UNIX\n");
    GNUNET_free (un);
    return -1;
  }
  if (GNUNET_OK !=
      GNUNET_NETWORK_socket_bind (nh,
                                  (void *) un,
                                  sizeof (struct sockaddr_un)))
  {
    fprintf (stderr,
             "bind failed for AF_UNIX\n");
    GNUNET_free (un);
    GNUNET_NETWORK_socket_close (nh);
    return -1;
  }
  GNUNET_free (un);
  if (GNUNET_OK !=
      GNUNET_NETWORK_socket_listen (nh,
                                    UNIX_BACKLOG))
  {
    fprintf (stderr,
             "listen failed for AF_UNIX\n");
    GNUNET_NETWORK_socket_close (nh);
    return -1;
  }

  if (0 != chmod (unix_path,
                  unix_mode))
  {
    fprintf (stderr,
             "chmod failed: %s\n",
             strerror (errno));
    GNUNET_NETWORK_socket_close (nh);
    return -1;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "set socket '%s' to mode %o\n",
              unix_path,
              unix_mode);
  fd = GNUNET_NETWORK_get_fd (nh);
  GNUNET_NETWORK_socket_free_memory_only_ (nh);
  return fd;
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
    GNUNET_GETOPT_option_help ("HTTP server providing a RESTful API to access a Taler auditor"),
    GNUNET_GETOPT_option_loglevel (&loglev),
    GNUNET_GETOPT_option_logfile (&logfile),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;
  const char *listen_pid;
  const char *listen_fds;
  int fh = -1;

  if (0 >=
      GNUNET_GETOPT_run ("taler-auditor-httpd",
                         options,
                         argc, argv))
    return 1;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor-httpd",
                                   (NULL == loglev) ? "INFO" : loglev,
                                   logfile));
  if (NULL == cfgfile)
    cfgfile = GNUNET_strdup (GNUNET_OS_project_data_get ()->user_config_file);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_load (cfg, cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _("Malformed configuration file `%s', exit ...\n"),
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
       (getpid() == strtol (listen_pid,
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
    fh = open_unix_path (serve_unixpath,
                         unixpath_mode);
    if (-1 == fh)
      return 1;
  }

  mhd
    = MHD_start_daemon (MHD_USE_SELECT_INTERNALLY | MHD_USE_PIPE_FOR_SHUTDOWN | MHD_USE_DEBUG | MHD_USE_DUAL_STACK | MHD_USE_INTERNAL_POLLING_THREAD | MHD_USE_TCP_FASTOPEN,
                        (-1 == fh) ? serve_port : 0,
                        NULL, NULL,
                        &handle_mhd_request, NULL,
                        MHD_OPTION_THREAD_POOL_SIZE, (unsigned int) 32,
                        MHD_OPTION_LISTEN_BACKLOG_SIZE, (unsigned int) 1024,
                        MHD_OPTION_LISTEN_SOCKET, fh,
                        MHD_OPTION_EXTERNAL_LOGGER, &handle_mhd_logs, NULL,
                        MHD_OPTION_NOTIFY_COMPLETED, &handle_mhd_completion_callback, NULL,
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
                                       MHD_DAEMON_INFO_CURRENT_CONNECTIONS)->num_connections)
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
