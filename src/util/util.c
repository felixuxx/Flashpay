/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
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
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_util_lib.h>
#include <gcrypt.h>

/**
 * Return the base32crockford encoding of the given buffer.
 *
 * The returned string will be freshly allocated, and must be free'd
 * with GNUNET_free().
 *
 * @param buffer with data
 * @param size size of the buffer
 * @return freshly allocated, null-terminated string
 */
char *
TALER_data_to_string_alloc (const void *buf, size_t size)
{
  char *str_buf;
  size_t len = size * 8;
  char *end;

  if (len % 5 > 0)
    len += 5 - len % 5;
  len /= 5;
  str_buf = GNUNET_malloc (len + 1);
  end = GNUNET_STRINGS_data_to_string (buf, size, str_buf, len);
  if (NULL == end)
  {
    GNUNET_free (str_buf);
    return NULL;
  }
  *end = '\0';
  return str_buf;
}


/* end of util.c */
