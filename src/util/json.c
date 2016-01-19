/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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

  GNUNET_assert (GNUNET_OK ==
                 TALER_round_abs_time (&stamp));
  if (stamp.abs_value_us == GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us)
    return json_string ("/never/");
  ret = GNUNET_asprintf (&mystr,
                         "/Date(%llu)/",
                         (unsigned long long) (stamp.abs_value_us / (1000LL * 1000LL)));
  GNUNET_assert (ret > 0);
  j = json_string (mystr);
  GNUNET_free (mystr);
  return j;
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
  json_int_t value;
  json_int_t fraction;
  const char *currency;

  memset (r_amount,
          0,
          sizeof (struct TALER_Amount));
  if (0 != json_unpack (json,
                        "{s:I, s:I, s:s}",
                        "value", &value,
                        "fraction", &fraction,
                        "currency", &currency))
  {
    char *json_enc;

    if (NULL == (json_enc = json_dumps (json,
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
 * Parse given JSON object to absolute time.
 *
 * @param json the json object representing Amount
 * @param[out] abs where the amount has to be written
 * @return #GNUNET_OK upon successful parsing; #GNUNET_SYSERR upon error
 */
int
TALER_json_to_abs (json_t *json,
                   struct GNUNET_TIME_Absolute *abs)
{
  const char *val;
  unsigned long long int tval;

  val = json_string_value (json);
  if (NULL == val)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if ( (0 == strcasecmp (val,
                         "/forever/")) ||
       (0 == strcasecmp (val,
                         "/never/")) )
  {
    *abs = GNUNET_TIME_UNIT_FOREVER_ABS;
    return GNUNET_OK;
  }
  if (1 != sscanf (val,
                   "/Date(%llu)/",
                   &tval))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* Time is in seconds in JSON, but in microseconds in GNUNET_TIME_Absolute */
  abs->abs_value_us = tval * 1000LL * 1000LL;
  if ( (abs->abs_value_us) / 1000LL / 1000LL != tval)
  {
    /* Integer overflow */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
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


/**
 * Hash a JSON for binary signing.
 *
 * @param[in] json some JSON value
 * @param[out] hc resulting hash code
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_hash_json (json_t *json,
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


/* End of util/json.c */
