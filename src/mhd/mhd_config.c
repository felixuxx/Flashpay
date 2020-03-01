/*
  This file is part of TALER
  Copyright (C) 2014--2019 Taler Systems SA

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
 * @file mhd_config.c
 * @brief functions to configure and setup MHD
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_mhd_lib.h"


/**
 * Backlog for listen operation on UNIX domain sockets.
 */
#define UNIX_BACKLOG 500


/**
 * Parse the configuration to determine on which port
 * or UNIX domain path we should run an HTTP service.
 *
 * @param cfg configuration to parse
 * @param section section of the configuration to parse (usually "exchange")
 * @param[out] rport set to the port number, or 0 for none
 * @param[out] unix_path set to the UNIX path, or NULL for none
 * @param[out] unix_mode set to the mode to be used for @a unix_path
 * @return #GNUNET_OK on success
 */
int
TALER_MHD_parse_config (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *section,
                        uint16_t *rport,
                        char **unix_path,
                        mode_t *unix_mode)
{
  const char *choices[] = {
    "tcp",
    "unix",
    NULL
  };
  const char *serve_type;
  unsigned long long port;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_choice (cfg,
                                             section,
                                             "SERVE",
                                             choices,
                                             &serve_type))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "SERVE",
                               "serve type (tcp or unix) required");
    return GNUNET_SYSERR;
  }

  if (0 == strcasecmp (serve_type,
                       "tcp"))
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_number (cfg,
                                               section,
                                               "port",
                                               &port))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "PORT",
                                 "port number required");
      return GNUNET_SYSERR;
    }

    if ( (0 == port) ||
         (port > UINT16_MAX) )
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "PORT",
                                 "port number not in [1,65535]");
      return GNUNET_SYSERR;
    }
    *rport = (uint16_t) port;
    *unix_path = NULL;
    return GNUNET_OK;
  }
  if (0 == strcmp (serve_type,
                   "unix"))
  {
    struct sockaddr_un s_un;
    char *modestring;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 section,
                                                 "UNIXPATH",
                                                 unix_path))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "UNIXPATH",
                                 "UNIXPATH value required");
      return GNUNET_SYSERR;
    }
    if (strlen (*unix_path) >= sizeof (s_un.sun_path))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "unixpath `%s' is too long\n",
                  *unix_path);
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
 * Function called for logging by MHD.
 *
 * @param cls closure, NULL
 * @param fm format string (`printf()`-style)
 * @param ap arguments to @a fm
 */
void
TALER_MHD_handle_logs (void *cls,
                       const char *fm,
                       va_list ap)
{
  static int cache;
  char buf[2048];

  (void) cls;
  if (-1 == cache)
    return;
  if (0 == cache)
  {
    if (0 ==
        GNUNET_get_log_call_status (GNUNET_ERROR_TYPE_INFO,
                                    "libmicrohttpd",
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
                           "libmicrohttpd",
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
int
TALER_MHD_open_unix_path (const char *unix_path,
                          mode_t unix_mode)
{
  struct GNUNET_NETWORK_Handle *nh;
  struct sockaddr_un *un;

  if (sizeof (un->sun_path) <= strlen (unix_path))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "unixpath `%s' is too long\n",
                unix_path);
    return -1;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
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
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "socket");
    GNUNET_free (un);
    return -1;
  }
  if (GNUNET_OK !=
      GNUNET_NETWORK_socket_bind (nh,
                                  (void *) un,
                                  sizeof (struct sockaddr_un)))
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "bind",
                              unix_path);
    GNUNET_free (un);
    GNUNET_NETWORK_socket_close (nh);
    return -1;
  }
  GNUNET_free (un);
  if (GNUNET_OK !=
      GNUNET_NETWORK_socket_listen (nh,
                                    UNIX_BACKLOG))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "listen");
    GNUNET_NETWORK_socket_close (nh);
    return -1;
  }

  if (0 != chmod (unix_path,
                  unix_mode))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "chmod");
    GNUNET_NETWORK_socket_close (nh);
    return -1;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "set socket '%s' to mode %o\n",
              unix_path,
              unix_mode);
  {
    int fd;

    fd = GNUNET_NETWORK_get_fd (nh);
    GNUNET_NETWORK_socket_free_memory_only_ (nh);
    return fd;
  }
}


/**
 * Bind a listen socket to the UNIX domain path or the TCP port and IP address
 * as specified in @a cfg in section @a section.  IF only a port was
 * specified, set @a port and return -1.  Otherwise, return the bound file
 * descriptor.
 *
 * @param cfg configuration to parse
 * @param section configuration section to use
 * @param[out] port port to set, if TCP without BINDTO
 * @return -1 and a port of zero on error, otherwise
 *    either -1 and a port, or a bound stream socket
 */
int
TALER_MHD_bind (const struct GNUNET_CONFIGURATION_Handle *cfg,
                const char *section,
                uint16_t *port)
{
  char *bind_to;
  char *serve_unixpath;
  mode_t unixpath_mode;
  char port_str[6];
  struct addrinfo hints;
  struct addrinfo *res;
  int ec;
  struct GNUNET_NETWORK_Handle *nh;

  *port = 0;
  if (GNUNET_OK !=
      TALER_MHD_parse_config (cfg,
                              section,
                              port,
                              &serve_unixpath,
                              &unixpath_mode))
    return -1;
  if (NULL != serve_unixpath)
    return TALER_MHD_open_unix_path (serve_unixpath,
                                     unixpath_mode);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "BIND_TO",
                                             &bind_to))
    return -1; /* only set port */
  /* let's have fun binding... */
  GNUNET_snprintf (port_str,
                   sizeof (port_str),
                   "%u",
                   (unsigned int) *port);
  *port = 0; /* do NOT return port in case of errors */
  memset (&hints, 0, sizeof (hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  hints.ai_flags = AI_PASSIVE
#ifdef AI_IDN
                   | AI_IDN
#endif
  ;
  if (0 !=
      (ec = getaddrinfo (bind_to,
                         port_str,
                         &hints,
                         &res)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to resolve BIND_TO address `%s': %s\n",
                bind_to,                  gai_strerror (ec));
    GNUNET_free (bind_to);
    return -1;
  }
  GNUNET_free (bind_to);

  if (NULL == (nh = GNUNET_NETWORK_socket_create (res->ai_family,
                                                  res->ai_socktype,
                                                  res->ai_protocol)))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "socket");
    freeaddrinfo (res);
    return -1;
  }
  if (GNUNET_OK !=
      GNUNET_NETWORK_socket_bind (nh,
                                  res->ai_addr,
                                  res->ai_addrlen))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "bind");
    freeaddrinfo (res);
    return -1;
  }
  freeaddrinfo (res);
  if (GNUNET_OK !=
      GNUNET_NETWORK_socket_listen (nh,
                                    UNIX_BACKLOG))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "listen");
    GNUNET_SCHEDULER_shutdown ();
    return -1;
  }
  {
    int fh;

    fh = GNUNET_NETWORK_get_fd (nh);
    GNUNET_NETWORK_socket_free_memory_only_ (nh);
    return fh;
  }
}
