/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
#if HAVE_GNUNET_GNUNET_UTIL_TALER_WALLET_LIB_H
#include <gnunet/gnunet_util_taler_wallet_lib.h>
#endif
#if HAVE_GNUNET_GNUNET_UTIL_LIB_H
#include <gnunet/gnunet_util_lib.h>
#endif
#include "taler_util.h"

/**
 * Shorthand for exit jumps.
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)

/**
 * Shorthand for JSON parsing related exit jumps.
 */
#define UNPACK_EXITIF(cond)                                             \
  do {                                                                  \
    if (cond) { TALER_json_warn (error); goto EXITIF_exit; }            \
  } while (0)


/**
 * Convert a TALER amount to a JSON
 * object.
 *
 * @param amount the amount
 * @return a json object describing the amount
 */
json_t *
TALER_json_from_amount (const struct TALER_Amount *amount)
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
 * Convert absolute timestamp to a json string.
 *
 * @param stamp the time stamp
 * @return a json string with the timestamp in @a stamp
 */
json_t *
TALER_json_from_abs (struct GNUNET_TIME_Absolute stamp)
{
  json_t *j;
  char *mystr;
  int ret;

  if (stamp.abs_value_us == GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us)
    return json_string ("never");
  ret = GNUNET_asprintf (&mystr,
                         "/%llu/",
                         (long long) (stamp.abs_value_us / (1000LL * 1000LL)));
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
TALER_json_from_eddsa_sig (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                           const struct GNUNET_CRYPTO_EddsaSignature *signature)
{
  json_t *root;
  json_t *el;

  root = json_object ();

  el = json_integer ((json_int_t) ntohl (purpose->size));
  json_object_set_new (root, "size", el);

  el = json_integer ((json_int_t) ntohl (purpose->purpose));
  json_object_set_new (root, "purpose", el);

  el = TALER_json_from_data (purpose,
                             ntohl (purpose->size));
  json_object_set_new (root, "eddsa_val", el);

  el = TALER_json_from_data (signature,
                             sizeof (struct GNUNET_CRYPTO_EddsaSignature));
  json_object_set_new (root, "eddsa_sig", el);

  return root;
}


/**
 * Convert RSA public key to JSON.
 *
 * @param pk public key to convert
 * @return corresponding JSON encoding
 */
json_t *
TALER_json_from_rsa_public_key (struct GNUNET_CRYPTO_rsa_PublicKey *pk)
{
  char *buf;
  size_t buf_len;
  json_t *ret;

  buf_len = GNUNET_CRYPTO_rsa_public_key_encode (pk,
                                                 &buf);
  ret = TALER_json_from_data (buf,
                              buf_len);
  GNUNET_free (buf);
  return ret;
}


/**
 * Convert JSON to RSA public key.
 *
 * @param json JSON encoding to convert
 * @return corresponding public key
 */
struct GNUNET_CRYPTO_rsa_PublicKey *
TALER_json_to_rsa_public_key (json_t *json)
{
  const char *enc;
  char *buf;
  size_t len;
  size_t buf_len;
  struct GNUNET_CRYPTO_rsa_PublicKey *pk;

  buf = NULL;
  EXITIF (NULL == (enc = json_string_value (json)));
  len = strlen (enc);
  buf_len =  (len * 5) / 8;
  buf = GNUNET_malloc (buf_len);
  EXITIF (GNUNET_OK !=
	  GNUNET_STRINGS_string_to_data (enc,
					 len,
					 buf,
					 buf_len));
  EXITIF (NULL == (pk = GNUNET_CRYPTO_rsa_public_key_decode (buf,
							     buf_len)));
  GNUNET_free (buf);
  return pk;
 EXITIF_exit:
  GNUNET_free_non_null (buf);
  return NULL;
}


/**
 * Convert JSON to RSA signature.
 *
 * @param json JSON encoding to convert
 * @return corresponding signature
 */
struct GNUNET_CRYPTO_rsa_Signature *
TALER_json_to_rsa_signature (json_t *json)
{
  const char *enc;
  char *buf;
  size_t len;
  size_t buf_len;
  struct GNUNET_CRYPTO_rsa_Signature *sig;

  buf = NULL;
  EXITIF (NULL == (enc = json_string_value (json)));
  len = strlen (enc);
  buf_len =  (len * 5) / 8;
  buf = GNUNET_malloc (buf_len);
  EXITIF (GNUNET_OK !=
	  GNUNET_STRINGS_string_to_data (enc,
					 len,
					 buf,
					 buf_len));
  EXITIF (NULL == (sig = GNUNET_CRYPTO_rsa_signature_decode (buf,
							     buf_len)));
  GNUNET_free (buf);
  return sig;
 EXITIF_exit:
  GNUNET_free_non_null (buf);
  return NULL;
}


/**
 * Convert RSA signature to JSON.
 *
 * @param sig signature to convert
 * @return corresponding JSON encoding
 */
json_t *
TALER_json_from_rsa_signature (struct GNUNET_CRYPTO_rsa_Signature *sig)
{
  char *buf;
  size_t buf_len;
  json_t *ret;

  buf_len = GNUNET_CRYPTO_rsa_signature_encode (sig,
                                                &buf);
  ret = TALER_json_from_data (buf,
                              buf_len);
  GNUNET_free (buf);
  return ret;
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
TALER_json_from_data (const void *data,
                      size_t size)
{
  char *buf;
  json_t *json;

  buf = GNUNET_STRINGS_data_to_string_alloc (data, size);
  json = json_string (buf);
  GNUNET_free (buf);
  return json;
}


/**
 * Parse given JSON object to Amount
 *
 * @param json the json object representing Amount
 * @param[out] r_amount where the amount has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_json_to_amount (json_t *json,
                      struct TALER_Amount *r_amount)
{
  char *currency;
  json_int_t value;
  json_int_t fraction;
  json_error_t error;

  UNPACK_EXITIF (0 != json_unpack_ex (json,
                                      &error,
                                      JSON_STRICT,
                                      "{s:s, s:I, s:I}",
                                      "currency", &currency,
                                      "value", &value,
                                      "fraction", &fraction));
  EXITIF (3 < strlen (currency));
  EXITIF (TALER_CURRENCY_LEN <= strlen (currency));
  strcpy (r_amount->currency,
	  currency);
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
 * @param[out] abs where the amount has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_json_to_abs (json_t *json,
                   struct GNUNET_TIME_Absolute *abs)
{
  const char *str;
  unsigned long long abs_value_s;

  GNUNET_assert (NULL != abs);
  EXITIF (NULL == (str = json_string_value (json)));
  if (0 == strcasecmp (str,
		       "never"))
  {
    *abs = GNUNET_TIME_UNIT_FOREVER_ABS;
    return GNUNET_OK;
  }
  EXITIF (1 > sscanf (str, "%llu", &abs_value_s));
  abs->abs_value_us = abs_value_s * 1000LL * 1000LL;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}

/**
 * Parse given JSON object to data
 *
 * @param json the json object representing data
 * @param out the pointer to hold the parsed data.
 * @param out_size the size of @a out
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_json_to_data (json_t *json,
                    void *out,
                    size_t out_size)
{
  const char *enc;
  unsigned int len;

  EXITIF (NULL == (enc = json_string_value (json)));
  len = strlen (enc);
  EXITIF (((len * 5) / 8) != out_size);
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (enc, len, out, out_size));
  return GNUNET_OK;
 EXITIF_exit:
  return GNUNET_SYSERR;
}

/* End of util/json.c */
