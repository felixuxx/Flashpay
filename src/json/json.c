/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * @file json/json.c
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Hash a JSON for binary signing.
 *
 * @param[in] json some JSON value
 * @param[out] hc resulting hash code
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_JSON_hash (const json_t *json,
                 struct GNUNET_HashCode *hc)
{
  char *wire_enc;
  size_t len;

  if (NULL == (wire_enc = json_dumps (json,
                                      JSON_COMPACT | JSON_SORT_KEYS)))
    return GNUNET_SYSERR;
  len = strlen (wire_enc) + 1;
  GNUNET_CRYPTO_hash (wire_enc,
                      len,
                      hc);
  free (wire_enc);
  return GNUNET_OK;
}


/* End of json/json.c */
