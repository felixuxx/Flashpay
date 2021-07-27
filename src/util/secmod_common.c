/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file util/secmod_common.c
 * @brief Common functions for the exchange security modules
 * @author Florian Dold <dold@taler.net>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"

struct GNUNET_NETWORK_Handle *
TES_open_socket (const char *unixpath)
{
  int sock;

  sock = socket (PF_UNIX,
                 SOCK_DGRAM,
                 0);
  if (-1 == sock)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "socket");
    return NULL;
  }
  /* Change permissions so that group read/writes are allowed.
   * We need this for multi-user exchange deployment with privilege
   * separation, where taler-exchange-httpd is part of a group
   * that allows it to talk to secmod.
   *
   * Importantly, we do this before binding the socket.
   */
  GNUNET_assert (0 == fchmod (sock, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP));
  {
    struct sockaddr_un un;

    if (GNUNET_OK !=
        GNUNET_DISK_directory_create_for_file (unixpath))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                "mkdir(dirname)",
                                unixpath);
    }
    if (0 != unlink (unixpath))
    {
      if (ENOENT != errno)
        GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_WARNING,
                                  "unlink",
                                  unixpath);
    }
    memset (&un,
            0,
            sizeof (un));
    un.sun_family = AF_UNIX;
    strncpy (un.sun_path,
             unixpath,
             sizeof (un.sun_path) - 1);
    if (0 != bind (sock,
                   (const struct sockaddr *) &un,
                   sizeof (un)))
    {
      GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                                "bind",
                                unixpath);
      GNUNET_break (0 == close (sock));
      return NULL;
    }
  }
  return GNUNET_NETWORK_socket_box_native (sock);
}
