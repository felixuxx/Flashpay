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
 * @file util/json.c
 * @brief helper functions for JSON processing using libjansson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */

#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"

/**
 * Shorthand for exit jumps.
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)

/**
 * Print JSON parsing related error information
 */
#define WARN_JSON(error)                                                \
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                              \
                "JSON parsing failed at %s:%u: %s (%s)",                \
                __FILE__, __LINE__, error.text, error.source)

/**
 * Shorthand for JSON parsing related exit jumps.
 */
#define UNPACK_EXITIF(cond)                                              \
  do {                                                                  \
    if (cond) { WARN_JSON(error); goto EXITIF_exit; }                   \
  } while (0)

/**
 * Convert a TALER amount to a JSON
 * object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount (struct TALER_Amount amount)
{
  json_t *j;
  j = json_pack ("{s: s, s:I, s:I}",
                 "currency", amount.currency,
                 "value", (json_int_t) amount.value,
                 "fraction", (json_int_t) amount.fraction);
  GNUNET_assert (NULL != j);
  return j;
}


/**
 * Convert absolute timestamp to a json string.
 *
 * @param the time stamp
 * @return a json string with the timestamp in @a stamp
 */
json_t *
TALER_JSON_from_abs (struct GNUNET_TIME_Absolute stamp)
{
  json_t *j;
  char *mystr;
  int ret;
  ret = GNUNET_asprintf (&mystr, "%llu",
                         (long long) (stamp.abs_value_us / (1000 * 1000)));
  GNUNET_assert (ret > 0);
  j = json_string (mystr);
  GNUNET_free (mystr);
  return j;
}


/**
 * Convert a signature (with purpose) to a JSON object representation.
 *
 * @param purpose purpose of the signature
 * @param signature the signature
 * @return the JSON reporesentation of the signature with purpose
 */
json_t *
TALER_JSON_from_sig (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                     const struct GNUNET_CRYPTO_EddsaSignature *signature)
{
  json_t *root;
  json_t *el;

  root = json_object ();

  el = json_integer ((json_int_t) ntohl (purpose->size));
  json_object_set_new (root, "size", el);

  el = json_integer ((json_int_t) ntohl (purpose->purpose));
  json_object_set_new (root, "purpose", el);

  el = TALER_JSON_from_data (signature, sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  json_object_set_new (root, "sig", el);

  return root;
}


/**
 * Convert binary data to a JSON string
 * with the base32crockford encoding.
 *
 * @param data binary data
 * @param size size of @a data in bytes
 * @return json string that encodes @a data
 */
json_t *
TALER_JSON_from_data (const void *data, size_t size)
{
  char *buf;
  json_t *json;
  buf = TALER_data_to_string_alloc (data, size);
  json = json_string (buf);
  GNUNET_free (buf);
  return json;
}


/**
 * Parse given JSON object to Amount
 *
 * @param json the json object representing Amount
 * @param r_amount where the amount has to be written
 * @return GNUNET_OK upon successful parsing; GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_amount (json_t *json,
                      struct TALER_Amount *r_amount)
{
  char *currency;
  json_int_t value;
  json_int_t fraction;
  json_error_t error;

  UNPACK_EXITIF (0 != json_unpack_ex (json, &error, JSON_STRICT,
                                      "{s:s, s:I, s:I}",
                                      "curreny", &currency,
                                      "value", &value,
                                      "fraction", &fraction));
  EXITIF (3 < strlen (currency));
  r_amount->value = (uint32_t) value;
  r_amount->fraction = (uint32_t) fraction;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}


/**
 * Parse given JSON object to Amount
 *
 * @param json the json object representing Amount
 * @param r_amount where the amount has to be written
 * @return GNUNET_OK upon successful parsing; GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_abs (json_t *json,
                   struct GNUNET_TIME_Absolute *abs)
{
  const char *str;
  unsigned long long abs_value_s;

  GNUNET_assert (NULL != abs);
  EXITIF (NULL == (str = json_string_value (json)));
  EXITIF (1 > sscanf (str, "%llu", &abs_value_s));
  abs->abs_value_us = abs_value_s * 1000 * 1000;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}

/**
 * Parse given JSON object to data
 *
 * @param json the json object representing data
 * @param out the pointer to hold the parsed data.
 * @param out_size the size of r_data.
 * @return GNUNET_OK upon successful parsing; GNUNET_SYSERR upon error
 */
int
TALER_JSON_to_data (json_t *json,
                    void *out,
                    size_t out_size)
{
  const char *enc;
  unsigned int len;

  EXITIF (NULL == (enc = json_string_value (json)));
  len = strlen (enc);
  EXITIF ((((len * 5) / 8) + ((((len * 5) % 8) == 0) ? 0 : 1)) == out_size);
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (enc, len, out, out_size));
  return GNUNET_OK;
 EXITIF_exit:
  return GNUNET_SYSERR;
}

/* End of util/json.c */
