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
  json_int_t value;
  json_int_t fraction;
  const char *currency;

  if (json_is_string (root))
  {
    if (GNUNET_OK !=
        TALER_string_to_amount (json_string_value (root), r_amount))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }

  /* Also allow the legacy { value, fraction, currency} format.
     This might be removed in the future. */

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
  struct TALER_Amount amount;
  json_int_t value;
  json_int_t fraction;
  const char *currency;

  if (json_is_string (root))
  {
    if (GNUNET_OK !=
        TALER_string_to_amount_nbo (json_string_value (root), r_amount))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }

  memset (&amount,
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
       (fraction > (json_int_t) UINT32_MAX) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (strlen (currency) >= TALER_CURRENCY_LEN)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  amount.value = (uint64_t) value;
  amount.fraction = (uint32_t) fraction;
  strcpy (amount.currency, currency);
  (void) TALER_amount_normalize (&amount);
  TALER_amount_hton (r_amount,
		     &amount);
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
