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
 * @file util/crypto_helper_common.h
 * @brief Common functions for the exchange security modules
 * @author Florian Dold <dold@taler.net>
 */
#ifndef CRYPTO_HELPER_COMMON_H
#define CRYPTO_HELPER_COMMON_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_network_lib.h>

/**
 * Send all @a buf_size bytes from @a buf to @a sock.
 *
 * @param sock socket to send on
 * @param buf data to send
 * @param buf_size number of bytes in @a buf
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_crypto_helper_send_all (int sock,
                              const void *buf,
                              size_t buf_size);

#endif
