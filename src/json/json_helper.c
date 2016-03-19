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
 * @file json/json_helper.c
 * @brief helper functions to generate specifications to parse
 *        Taler-specific JSON objects with libgnunetjson
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Convert a TALER amount to a JSON object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount (const struct TALER_Amount *amount)
{
  json_t *j;

  if ( (amount->value != (uint64_t) ((json_int_t) amount->value)) ||
       (0 > ((json_int_t) amount->value)) )
  {
    /* Theoretically, json_int_t can be a 32-bit "long", or we might
       have a 64-bit value which converted to a 63-bit signed long
       long causes problems here.  So we check.  Note that depending
       on the platform, the compiler may be able to statically tell
       that at least the first check is always false. */
    GNUNET_break (0);
    return NULL;
  }
  j = json_pack ("{s:s, s:I, s:I}",
                 "currency", amount->currency,
                 "value", (json_int_t) amount->value,
                 "fraction", (json_int_t) amount->fraction);
  GNUNET_assert (NULL != j);
  return j;
}


/**
 * Parse given JSON object to Amount
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_amount (void *cls,
              json_t *root,
              struct GNUNET_JSON_Specification *spec)
{
  struct TALER_Amount *r_amount = spec->ptr;
  json_int_t value;
  json_int_t fraction;
  const char *currency;

  memset (r_amount,
          0,
          sizeof (struct TALER_Amount));
  if (0 != json_unpack (root,
                        "{s:I, s:I, s:s}",
                        "value", &value,
                        "fraction", &fraction,
                        "currency", &currency))
  {
    char *json_enc;

    if (NULL == (json_enc = json_dumps (root,
                                        JSON_COMPACT | JSON_ENCODE_ANY)))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Malformed JSON amount: %s\n",
                json_enc);
    free (json_enc);
    return GNUNET_SYSERR;
  }
  if ( (value < 0) ||
       (fraction < 0) ||
       (value > UINT64_MAX) ||
       (fraction > UINT32_MAX) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (strlen (currency) >= TALER_CURRENCY_LEN)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  r_amount->value = (uint64_t) value;
  r_amount->fraction = (uint32_t) fraction;
  strcpy (r_amount->currency, currency);
  (void) TALER_amount_normalize (r_amount);
  return GNUNET_OK;
}



/**
 * Provide specification to parse given JSON object to an amount.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount (const char *name,
                        struct TALER_Amount *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };
  return ret;
}


/* end of json/json_helper.c */
