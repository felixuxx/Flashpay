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
  char *amount_str = TALER_amount_to_string (amount);

  GNUNET_assert (NULL != amount_str);
  {
    json_t *j = json_string (amount_str);

    GNUNET_free (amount_str);
    return j;
  }
}


/**
 * Convert a TALER amount to a JSON object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_JSON_from_amount_nbo (const struct TALER_AmountNBO *amount)
{
  struct TALER_Amount a;

  TALER_amount_ntoh (&a,
                     amount);
  return TALER_JSON_from_amount (&a);
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

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount (json_string_value (root),
                              r_amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
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


/**
 * Parse given JSON object to Amount in NBO.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_amount_nbo (void *cls,
                  json_t *root,
                  struct GNUNET_JSON_Specification *spec)
{
  struct TALER_AmountNBO *r_amount = spec->ptr;

  (void) cls;
  if (! json_is_string (root))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount_nbo (json_string_value (root),
                                  r_amount))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Provide specification to parse given JSON object to an amount.
 *
 * @param name name of the amount field in the JSON
 * @param[out] r_amount where the amount has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_amount_nbo (const char *name,
                            struct TALER_AmountNBO *r_amount)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_amount_nbo,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_amount,
    .ptr_size = 0,
    .size_ptr = NULL
  };
  return ret;
}


/**
 * Parse given JSON object to *rounded* absolute time.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_abs_time (void *cls,
                json_t *root,
                struct GNUNET_JSON_Specification *spec)
{
  struct GNUNET_TIME_Absolute *abs = spec->ptr;
  json_t *json_t_ms;
  unsigned long long int tval;

  if (! json_is_object (root))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  json_t_ms = json_object_get (root, "t_ms");
  if (json_is_integer (json_t_ms))
  {
    tval = json_integer_value (json_t_ms);
    /* Time is in milliseconds in JSON, but in microseconds in GNUNET_TIME_Absolute */
    abs->abs_value_us = tval * 1000LL;
    if ((abs->abs_value_us) / 1000LL != tval)
    {
      /* Integer overflow */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_TIME_round_abs (abs))
    {
      /* time not rounded */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }
  if (json_is_string (json_t_ms))
  {
    const char *val;
    val = json_string_value (json_t_ms);
    if ((0 == strcasecmp (val, "never")))
    {
      *abs = GNUNET_TIME_UNIT_FOREVER_ABS;
      return GNUNET_OK;
    }
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_break_op (0);
  return GNUNET_SYSERR;
}


/**
 * Provide specification to parse given JSON object to an absolute time.
 * The absolute time value is expected to be already rounded.
 *
 * @param name name of the time field in the JSON
 * @param[out] r_time where the time has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time (const char *name,
                               struct GNUNET_TIME_Absolute *r_time)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_abs_time,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_time,
    .ptr_size = sizeof(uint64_t),
    .size_ptr = NULL
  };

  return ret;
}


/**
 * Parse given JSON object to absolute time.
 *
 * @param cls closure, NULL
 * @param root the json object representing data
 * @param[out] spec where to write the data
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
static int
parse_abs_time_nbo (void *cls,
                    json_t *root,
                    struct GNUNET_JSON_Specification *spec)
{
  struct GNUNET_TIME_AbsoluteNBO *abs = spec->ptr;
  struct GNUNET_TIME_Absolute a;
  struct GNUNET_JSON_Specification ispec;

  ispec = *spec;
  ispec.parser = &parse_abs_time;
  ispec.ptr = &a;
  if (GNUNET_OK !=
      parse_abs_time (NULL,
                      root,
                      &ispec))
    return GNUNET_SYSERR;
  *abs = GNUNET_TIME_absolute_hton (a);
  return GNUNET_OK;
}


/**
 * Provide specification to parse given JSON object to an absolute time
 * in network byte order.
 * The absolute time value is expected to be already rounded.
 *
 * @param name name of the time field in the JSON
 * @param[out] r_time where the time has to be written
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_absolute_time_nbo (const char *name,
                                   struct GNUNET_TIME_AbsoluteNBO *r_time)
{
  struct GNUNET_JSON_Specification ret = {
    .parser = &parse_abs_time_nbo,
    .cleaner = NULL,
    .cls = NULL,
    .field = name,
    .ptr = r_time,
    .ptr_size = sizeof(uint64_t),
    .size_ptr = NULL
  };

  return ret;
}


/**
 * Generate line in parser specification for denomination public key.
 *
 * @param field name of the field
 * @param[out] pk key to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_public_key (const char *field,
                                         struct TALER_DenominationPublicKey *pk)
{
  return GNUNET_JSON_spec_rsa_public_key (field,
                                          &pk->rsa_public_key);
}


/**
 * Generate line in parser specification for denomination signature.
 *
 * @param field name of the field
 * @param sig the signature to initialize
 * @return corresponding field spec
 */
struct GNUNET_JSON_Specification
TALER_JSON_spec_denomination_signature (const char *field,
                                        struct TALER_DenominationSignature *sig)
{
  return GNUNET_JSON_spec_rsa_signature (field,
                                         &sig->rsa_signature);
}


/* end of json/json_helper.c */
