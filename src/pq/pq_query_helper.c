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
 * @file pq/pq_query_helper.c
 * @brief helper functions for Taler-specific libpq (PostGres) interactions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_pq_lib.h>
#include "taler_pq_lib.h"


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument, here a `struct TALER_AmountNBO`
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_amount_nbo (void *cls,
		  const void *data,
		  size_t data_len,
		  void *param_values[],
		  int param_lengths[],
		  int param_formats[],
		  unsigned int param_length,
		  void *scratch[],
		  unsigned int scratch_length)
{
  const struct TALER_AmountNBO *amount = data;
  unsigned int off = 0;

  GNUNET_assert (3 == param_length);
  param_values[off] = (void *) &amount->value;
  param_lengths[off] = sizeof (amount->value);
  param_formats[off] = 1;
  off++;
  param_values[off] = (void *) &amount->fraction;
  param_lengths[off] = sizeof (amount->fraction);
  param_formats[off] = 1;
  off++;
  param_values[off] = (void *) amount->currency;
  param_lengths[off] = strlen (amount->currency);
  param_formats[off] = 1;
  return 0;
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
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount_nbo (const struct TALER_AmountNBO *x)
{
  struct GNUNET_PQ_QueryParam res =
    { &qconv_amount_nbo, NULL, x, sizeof (*x), 3 };
  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument, here a `struct TALER_Amount`
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_amount (void *cls,
	      const void *data,
	      size_t data_len,
	      void *param_values[],
	      int param_lengths[],
	      int param_formats[],
	      unsigned int param_length,
	      void *scratch[],
	      unsigned int scratch_length)
{
  const struct TALER_Amount *amount_hbo = data;
  struct TALER_AmountNBO *amount;

  amount = GNUNET_new (struct TALER_AmountNBO);
  scratch[0] = amount;
  TALER_amount_hton (amount,
		     amount_hbo);
  qconv_amount_nbo (cls,
		    amount,
		    sizeof (struct TALER_AmountNBO),
		    param_values,
		    param_lengths,
		    param_formats,
		    param_length,
		    &scratch[1],
		    scratch_length - 1);
  return 1;
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
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount (const struct TALER_Amount *x)
{
  struct GNUNET_PQ_QueryParam res =
    { &qconv_amount, NULL, x, sizeof (*x), 3 };
  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument, here a `json_t *`
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_json (void *cls,
	    const void *data,
	    size_t data_len,
	    void *param_values[],
	    int param_lengths[],
	    int param_formats[],
	    unsigned int param_length,
	    void *scratch[],
	    unsigned int scratch_length)
{
  const json_t *json = data;
  char *str;

  str = json_dumps (json, JSON_COMPACT);
  if (NULL == str)
    return -1;
  scratch[0] = str;
  param_values[0] = (void *) str;
  param_lengths[0] = strlen (str);
  param_formats[0] = 1;
  return 1;
}


/**
 * Generate query parameter for a JSON object (stored as a string
 * in the DB).
 *
 * @param x pointer to the json object to pass
 */
struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_json (const json_t *x)
{
  struct GNUNET_PQ_QueryParam res =
    { &qconv_json, NULL, x, 0, 1 };
  return res;
}


/* end of pq/pq_query_helper.c */
