/*
  This file is part of TALER
  Copyright (C) 2020, 2021 Taler Systems SA

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
 * @file util/crypto_helper_common.c
 * @brief Common functions for the exchange security modules
 * @author Florian Dold <dold@taler.net>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


enum GNUNET_GenericReturnValue
TALER_crypto_helper_send_all (int sock,
                              const void *buf,
                              size_t buf_size)
{
  size_t off = 0;

  while (off < buf_size)
  {
    ssize_t ret;

    ret = send (sock,
                buf + off,
                buf_size - off,
                0);
    if (ret < 0)
    {
      if (EINTR == errno)
        continue;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (ret > 0);
    off += ret;
  }
  return GNUNET_OK;
}
