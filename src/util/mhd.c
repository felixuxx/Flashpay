/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mhd.c
 * @brief MHD utility functions (used by the merchant backend)
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Find out if an MHD connection is using HTTPS (either
 * directly or via proxy).
 *
 * @param connection MHD connection
 * @returns #GNUNET_YES if the MHD connection is using https,
 *          #GNUNET_NO if the MHD connection is using http,
 *          #GNUNET_SYSERR if the connection type couldn't be determined
 */
int
TALER_mhd_is_https (struct MHD_Connection *connection)
{
  const union MHD_ConnectionInfo *ci;
  const union MHD_DaemonInfo *di;
  const char *forwarded_proto = MHD_lookup_connection_value (connection,
                                                             MHD_HEADER_KIND,
                                                             "X-Forwarded-Proto");

  if (NULL != forwarded_proto)
  {
    if (0 == strcmp (forwarded_proto,
                     "https"))
      return GNUNET_YES;
    if (0 == strcmp (forwarded_proto,
                     "http"))
      return GNUNET_NO;
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* likely not reverse proxy, figure out if we are
     http by asking MHD */
  ci = MHD_get_connection_info (connection,
                                MHD_CONNECTION_INFO_DAEMON);
  if (NULL == ci)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  di = MHD_get_daemon_info (ci->daemon,
                            MHD_DAEMON_INFO_FLAGS);
  if (NULL == di)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != (di->flags & MHD_USE_TLS))
    return GNUNET_YES;
  return GNUNET_NO;
}


/**
 * Make an absolute URL for a given MHD connection.
 *
 * @param connection the connection to get the URL for
 * @param path path of the url
 * @param ... NULL-terminated key-value pairs (char *) for query parameters,
 *        the value will be url-encoded
 * @returns the URL, must be freed with #GNUNET_free
 */
char *
TALER_url_absolute_mhd (struct MHD_Connection *connection,
                        const char *path,
                        ...)
{
  /* By default we assume we're running under HTTPS */
  const char *proto;
  const char *host;
  const char *forwarded_host;
  const char *prefix;
  va_list args;
  char *result;

  if (GNUNET_YES == TALER_mhd_is_https (connection))
    proto = "https";
  else
    proto = "http";

  host = MHD_lookup_connection_value (connection, MHD_HEADER_KIND, "Host");
  forwarded_host = MHD_lookup_connection_value (connection,
                                                MHD_HEADER_KIND,
                                                "X-Forwarded-Host");

  prefix = MHD_lookup_connection_value (connection,
                                        MHD_HEADER_KIND,
                                        "X-Forwarded-Prefix");
  if (NULL == prefix)
    prefix = "";

  if (NULL != forwarded_host)
    host = forwarded_host;

  if (NULL == host)
  {
    /* Should never happen, at last the host header should be defined */
    GNUNET_break (0);
    return NULL;
  }

  va_start (args,
            path);
  result = TALER_url_absolute_raw_va (proto,
                                      host,
                                      prefix,
                                      path,
                                      args);
  va_end (args);
  return result;
}
