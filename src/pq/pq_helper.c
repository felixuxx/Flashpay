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
 * @file pq/pq_helper.c
 * @brief functions to initialize parameter arrays
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_pq_lib.h"


/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" and "currency" in this order. The
 * types must be a 64-bit integer, 32-bit integer and a
 * #TALER_CURRENCY_LEN-sized BLOB/VARCHAR respectively.
 *
 * @param x pointer to the query parameter to pass
 * @return array entry for the query parameters to use
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_amount_nbo (const struct TALER_AmountNBO *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_AMOUNT_NBO, x, sizeof (*x) };
  return res;
}


/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" and "currency" in this order. The
 * types must be a 64-bit integer, 32-bit integer and a
 * #TALER_CURRENCY_LEN-sized BLOB/VARCHAR respectively.
 *
 * @param x pointer to the query parameter to pass
 * @return array entry for the query parameters to use
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_amount (const struct TALER_Amount *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_AMOUNT, x, sizeof (*x) };
  return res;
}


/**
 * Generate query parameter for an RSA public key.  The
 * database must contain a BLOB type in the respective position.
 *
 * @param x the query parameter to pass
 * @return array entry for the query parameters to use
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_rsa_public_key (const struct GNUNET_CRYPTO_rsa_PublicKey *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_RSA_PUBLIC_KEY, (x), 0 };
  return res;
}


/**
 * Generate query parameter for an RSA signature.  The
 * database must contain a BLOB type in the respective position.
 *
 * @param x the query parameter to pass
 * @return array entry for the query parameters to use
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_rsa_signature (const struct GNUNET_CRYPTO_rsa_Signature *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_RSA_SIGNATURE, (x), 0 };
  return res;
}


/**
 * Generate query parameter for an absolute time value.
 * The database must store a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 * @return array entry for the query parameters to use
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_absolute_time (const struct GNUNET_TIME_Absolute *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_TIME_ABSOLUTE, x, sizeof (*x) };
  return res;
}


/**
 * Generate query parameter for an uint16_t in host byte order.
 *
 * @param x pointer to the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_uint16 (const uint16_t *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_UINT16, x, sizeof (*x) };
  return res;
}


/**
 * Generate query parameter for an uint32_t in host byte order.
 *
 * @param x pointer to the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_uint32 (const uint32_t *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_UINT32, x, sizeof (*x) };
  return res;
}


/**
 * Generate query parameter for an uint16_t in host byte order.
 *
 * @param x pointer to the query parameter to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_uint64 (const uint64_t *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_UINT64, x, sizeof (*x) };
  return res;
}


/**
 * Generate query parameter for a JSON object (stored as a string
 * in the DB).
 *
 * @param x pointer to the json object to pass
 */
struct TALER_PQ_QueryParam
TALER_PQ_query_param_json (const json_t *x)
{
  struct TALER_PQ_QueryParam res =
    { TALER_PQ_QF_JSON, x, 0 };
  return res;
}


/**
 * Variable-size result expected.
 *
 * @param name name of the field in the table
 * @param[out] dst where to store the result, allocated
 * @param[out] sptr where to store the size of @a dst
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_variable_size (const char *name,
			  void **dst,
			  size_t *sptr)
{
  struct TALER_PQ_ResultSpec res =
    { TALER_PQ_RF_VARSIZE_BLOB, (void *) (dst), 0, name, sptr };
  return res;
}


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_amount_nbo (const char *name,
				 struct TALER_AmountNBO *amount)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_AMOUNT_NBO, (void *) amount, sizeof (*amount), name, NULL };
  return res;
}


/**
 * Currency amount expected.
 *
 * @param name name of the field in the table
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_amount (const char *name,
			     struct TALER_Amount *amount)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_AMOUNT, (void *) amount, sizeof (*amount), name, NULL };
  return res;
}


/**
 * RSA public key expected.
 *
 * @param name name of the field in the table
 * @param[out] rsa where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_rsa_public_key (const char *name,
				     struct GNUNET_CRYPTO_rsa_PublicKey **rsa)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_RSA_PUBLIC_KEY, (void *) rsa, 0, name, NULL };
  return res;
}


/**
 * RSA signature expected.
 *
 * @param name name of the field in the table
 * @param[out] sig where to store the result;
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_rsa_signature (const char *name,
				    struct GNUNET_CRYPTO_rsa_Signature **sig)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_RSA_SIGNATURE, (void *) sig, 0, (name), NULL };
  return res;
}


/**
 * Absolute time expected.
 *
 * @param name name of the field in the table
 * @param[out] at where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_absolute_time (const char *name,
				    struct GNUNET_TIME_Absolute *at)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_TIME_ABSOLUTE, (void *) at, sizeof (*at), (name), NULL };
  return res;
}


/**
 * uint16_t expected.
 *
 * @param name name of the field in the table
 * @param[out] u16 where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_uint16 (const char *name,
                             uint16_t *u16)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_UINT16, (void *) u16, sizeof (*u16), (name), NULL };
  return res;
}


/**
 * uint32_t expected.
 *
 * @param name name of the field in the table
 * @param[out] u32 where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_uint32 (const char *name,
                             uint32_t *u32)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_UINT32, (void *) u32, sizeof (*u32), (name), NULL };
  return res;
}


/**
 * uint64_t expected.
 *
 * @param name name of the field in the table
 * @param[out] u64 where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_uint64 (const char *name,
                             uint64_t *u64)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_UINT64, (void *) u64, sizeof (*u64), (name), NULL };
  return res;
}


/**
 * json_t expected.
 *
 * @param name name of the field in the table
 * @param[out] jp where to store the result
 * @return array entry for the result specification to use
 */
struct TALER_PQ_ResultSpec
TALER_PQ_result_spec_json (const char *name,
                           json_t **jp)
{
  struct TALER_PQ_ResultSpec res =
    {TALER_PQ_RF_JSON, (void *) jp, 0, (name), NULL };
  return res;
}

/* end of pq_helper.c */
