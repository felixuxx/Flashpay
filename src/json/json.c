/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Taler Systems SA

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
 * @file json/json.c
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Hash a JSON object for binary signing.
 *
 * See https://tools.ietf.org/html/draft-rundgren-json-canonicalization-scheme-15
 * for fun JSON canonicalization problems.  Callers must ensure that
 * those are avoided in the input. We will use libjanson's "JSON_COMPACT"
 * encoding for whitespace and "JSON_SORT_KEYS" to canonicalize as best
 * as we can.
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
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  len = strlen (wire_enc) + 1;
  GNUNET_CRYPTO_hash (wire_enc,
                      len,
                      hc);
  free (wire_enc);
  return GNUNET_OK;
}


/**
 * Extract the Taler error code from the given @a json object.
 * Note that #TALER_EC_NONE is returned if no "code" is present.
 *
 * @param json response to extract the error code from
 * @return the "code" value from @a json
 */
enum TALER_ErrorCode
TALER_JSON_get_error_code (const json_t *json)
{
  const json_t *jc;

  if (NULL == json)
  {
    GNUNET_break_op (0);
    return TALER_EC_INVALID_RESPONSE;
  }
  jc = json_object_get (json, "code");
  /* The caller already knows that the JSON represents an error,
     so we are dealing with a missing error code here.  */
  if (NULL == jc)
  {
    GNUNET_break_op (0);
    return TALER_EC_INVALID;
  }
  if (json_is_integer (jc))
    return (enum TALER_ErrorCode) json_integer_value (jc);
  GNUNET_break_op (0);
  return TALER_EC_INVALID;
}


/**
 * Extract the Taler error code from the given @a data object, which is expected to be in JSON.
 * Note that #TALER_EC_INVALID is returned if no "code" is present or if @a data is not in JSON.
 *
 * @param data response to extract the error code from
 * @param data_size number of bytes in @a data
 * @return the "code" value from @a json
 */
enum TALER_ErrorCode
TALER_JSON_get_error_code2 (const void *data,
                            size_t data_size)
{
  json_t *json;
  enum TALER_ErrorCode ec;
  json_error_t err;

  json = json_loads (data,
                     data_size,
                     &err);
  if (NULL == json)
    return TALER_EC_INVALID;
  ec = TALER_JSON_get_error_code (json);
  json_decref (json);
  if (ec == TALER_EC_NONE)
    return TALER_EC_INVALID;
  return ec;
}


/* End of json/json.c */
