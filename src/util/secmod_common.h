/*
  This file is part of GNU Taler
  Copyright (C) 2021 Taler Systems SA

  GNU Taler is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  GNU Taler is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file util/secmod_common.h
 * @brief Common functions for the exchange security modules
 * @author Florian Dold <dold@taler.net>
 */
#ifndef SECMOD_COMMON_H
#define SECMOD_COMMON_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_network_lib.h>

/**
 * Create the listen socket for a secmod daemon.
 *
 * This function is not thread-safe, as it changes and
 * restores the process umask.
 *
 * @param unixpath socket path
 */
struct GNUNET_NETWORK_Handle *
TES_open_socket (const char *unixpath);

#endif
