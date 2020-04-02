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
 * @file util.c
 * @brief Common utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Convert a buffer to an 8-character string representative of the
 * contents. This is used for logging binary data when debugging.
 *
 * @param buf buffer to log
 * @param buf_size number of bytes in @a buf
 * @return text representation of buf, valid until next
 *         call to this function
 */
const char *
TALER_b2s (const void *buf,
           size_t buf_size)
{
  static GNUNET_THREAD_LOCAL char ret[9];
  struct GNUNET_HashCode hc;
  char *tmp;

  GNUNET_CRYPTO_hash (buf,
                      buf_size,
                      &hc);
  tmp = GNUNET_STRINGS_data_to_string_alloc (&hc,
                                             sizeof (hc));
  memcpy (ret,
          tmp,
          8);
  GNUNET_free (tmp);
  ret[8] = '\0';
  return ret;
}


/* end of util.c */
