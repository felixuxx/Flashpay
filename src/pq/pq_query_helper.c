/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016, 2021, 2022 Taler Systems SA

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

  (void) cls;
  (void) scratch;
  (void) scratch_length;
  GNUNET_assert (sizeof (struct TALER_AmountNBO) == data_len);
  GNUNET_assert (2 == param_length);
  param_values[off] = (void *) &amount->value;
  param_lengths[off] = sizeof (amount->value);
  param_formats[off] = 1;
  off++;
  param_values[off] = (void *) &amount->fraction;
  param_lengths[off] = sizeof (amount->fraction);
  param_formats[off] = 1;
  return 0;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount_nbo (const struct TALER_AmountNBO *x)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_amount_nbo,
    .data = x,
    .size = sizeof (*x),
    .num_params = 2
  };

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

  (void) cls;
  (void) scratch;
  (void) scratch_length;
  GNUNET_assert (2 == param_length);
  GNUNET_assert (sizeof (struct TALER_AmountNBO) == data_len);
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


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount (const struct TALER_Amount *x)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_amount,
    .data = x,
    .size = sizeof (*x),
    .num_params = 2
  };

  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via #GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_denom_pub (void *cls,
                 const void *data,
                 size_t data_len,
                 void *param_values[],
                 int param_lengths[],
                 int param_formats[],
                 unsigned int param_length,
                 void *scratch[],
                 unsigned int scratch_length)
{
  const struct TALER_DenominationPublicKey *denom_pub = data;
  size_t tlen;
  size_t len;
  uint32_t be[2];
  char *buf;
  void *tbuf;

  (void) cls;
  (void) data_len;
  GNUNET_assert (1 == param_length);
  GNUNET_assert (scratch_length > 0);
  GNUNET_break (NULL == cls);
  be[0] = htonl ((uint32_t) denom_pub->cipher);
  be[1] = htonl (denom_pub->age_mask.bits);
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_RSA:
    tlen = GNUNET_CRYPTO_rsa_public_key_encode (
      denom_pub->details.rsa_public_key,
      &tbuf);
    break;
  case TALER_DENOMINATION_CS:
    tlen = sizeof (denom_pub->details.cs_public_key);
    break;
  default:
    GNUNET_assert (0);
  }
  len = tlen + sizeof (be);
  buf = GNUNET_malloc (len);
  memcpy (buf,
          be,
          sizeof (be));
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_RSA:
    memcpy (&buf[sizeof (be)],
            tbuf,
            tlen);
    GNUNET_free (tbuf);
    break;
  case TALER_DENOMINATION_CS:
    memcpy (&buf[sizeof (be)],
            &denom_pub->details.cs_public_key,
            tlen);
    break;
  default:
    GNUNET_assert (0);
  }

  scratch[0] = buf;
  param_values[0] = (void *) buf;
  param_lengths[0] = len;
  param_formats[0] = 1;
  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_denom_pub (
  const struct TALER_DenominationPublicKey *denom_pub)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_denom_pub,
    .data = denom_pub,
    .num_params = 1
  };

  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via #GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_denom_sig (void *cls,
                 const void *data,
                 size_t data_len,
                 void *param_values[],
                 int param_lengths[],
                 int param_formats[],
                 unsigned int param_length,
                 void *scratch[],
                 unsigned int scratch_length)
{
  const struct TALER_DenominationSignature *denom_sig = data;
  size_t tlen;
  size_t len;
  uint32_t be[2];
  char *buf;
  void *tbuf;

  (void) cls;
  (void) data_len;
  GNUNET_assert (1 == param_length);
  GNUNET_assert (scratch_length > 0);
  GNUNET_break (NULL == cls);
  be[0] = htonl ((uint32_t) denom_sig->cipher);
  be[1] = htonl (0x00); /* magic marker: unblinded */
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    tlen = GNUNET_CRYPTO_rsa_signature_encode (
      denom_sig->details.rsa_signature,
      &tbuf);
    break;
  case TALER_DENOMINATION_CS:
    tlen = sizeof (denom_sig->details.cs_signature);
    break;
  default:
    GNUNET_assert (0);
  }
  len = tlen + sizeof (be);
  buf = GNUNET_malloc (len);
  memcpy (buf,
          &be,
          sizeof (be));
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    memcpy (&buf[sizeof (be)],
            tbuf,
            tlen);
    GNUNET_free (tbuf);
    break;
  case TALER_DENOMINATION_CS:
    memcpy (&buf[sizeof (be)],
            &denom_sig->details.cs_signature,
            tlen);
    break;
  default:
    GNUNET_assert (0);
  }

  scratch[0] = buf;
  param_values[0] = (void *) buf;
  param_lengths[0] = len;
  param_formats[0] = 1;
  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_denom_sig (
  const struct TALER_DenominationSignature *denom_sig)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_denom_sig,
    .data = denom_sig,
    .num_params = 1
  };

  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via #GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_blinded_denom_sig (void *cls,
                         const void *data,
                         size_t data_len,
                         void *param_values[],
                         int param_lengths[],
                         int param_formats[],
                         unsigned int param_length,
                         void *scratch[],
                         unsigned int scratch_length)
{
  const struct TALER_BlindedDenominationSignature *denom_sig = data;
  size_t tlen;
  size_t len;
  uint32_t be[2];
  char *buf;
  void *tbuf;

  (void) cls;
  (void) data_len;
  GNUNET_assert (1 == param_length);
  GNUNET_assert (scratch_length > 0);
  GNUNET_break (NULL == cls);
  be[0] = htonl ((uint32_t) denom_sig->cipher);
  be[1] = htonl (0x01); /* magic marker: blinded */
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    tlen = GNUNET_CRYPTO_rsa_signature_encode (
      denom_sig->details.blinded_rsa_signature,
      &tbuf);
    break;
  case TALER_DENOMINATION_CS:
    tlen = sizeof (denom_sig->details.blinded_cs_answer);
    break;
  default:
    GNUNET_assert (0);
  }
  len = tlen + sizeof (be);
  buf = GNUNET_malloc (len);
  memcpy (buf,
          &be,
          sizeof (be));
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    memcpy (&buf[sizeof (be)],
            tbuf,
            tlen);
    GNUNET_free (tbuf);
    break;
  case TALER_DENOMINATION_CS:
    memcpy (&buf[sizeof (be)],
            &denom_sig->details.blinded_cs_answer,
            tlen);
    break;
  default:
    GNUNET_assert (0);
  }

  scratch[0] = buf;
  param_values[0] = (void *) buf;
  param_lengths[0] = len;
  param_formats[0] = 1;
  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_blinded_denom_sig (
  const struct TALER_BlindedDenominationSignature *denom_sig)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_blinded_denom_sig,
    .data = denom_sig,
    .num_params = 1
  };

  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via #GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_blinded_planchet (void *cls,
                        const void *data,
                        size_t data_len,
                        void *param_values[],
                        int param_lengths[],
                        int param_formats[],
                        unsigned int param_length,
                        void *scratch[],
                        unsigned int scratch_length)
{
  const struct TALER_BlindedPlanchet *bp = data;
  size_t tlen;
  size_t len;
  uint32_t be[2];
  char *buf;

  (void) cls;
  (void) data_len;
  GNUNET_assert (1 == param_length);
  GNUNET_assert (scratch_length > 0);
  GNUNET_break (NULL == cls);
  be[0] = htonl ((uint32_t) bp->cipher);
  be[1] = htonl (0x0100); /* magic marker: blinded */
  switch (bp->cipher)
  {
  case TALER_DENOMINATION_RSA:
    tlen = bp->details.rsa_blinded_planchet.blinded_msg_size;
    break;
  case TALER_DENOMINATION_CS:
    tlen = sizeof (bp->details.cs_blinded_planchet);
    break;
  default:
    GNUNET_assert (0);
  }
  len = tlen + sizeof (be);
  buf = GNUNET_malloc (len);
  memcpy (buf,
          &be,
          sizeof (be));
  switch (bp->cipher)
  {
  case TALER_DENOMINATION_RSA:
    memcpy (&buf[sizeof (be)],
            bp->details.rsa_blinded_planchet.blinded_msg,
            tlen);
    break;
  case TALER_DENOMINATION_CS:
    memcpy (&buf[sizeof (be)],
            &bp->details.cs_blinded_planchet,
            tlen);
    break;
  default:
    GNUNET_assert (0);
  }
  scratch[0] = buf;
  param_values[0] = (void *) buf;
  param_lengths[0] = len;
  param_formats[0] = 1;
  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_blinded_planchet (
  const struct TALER_BlindedPlanchet *bp)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_blinded_planchet,
    .data = bp,
    .num_params = 1
  };

  return res;
}


/**
 * Function called to convert input argument into SQL parameters.
 *
 * @param cls closure
 * @param data pointer to input argument
 * @param data_len number of bytes in @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via #GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_exchange_withdraw_values (void *cls,
                                const void *data,
                                size_t data_len,
                                void *param_values[],
                                int param_lengths[],
                                int param_formats[],
                                unsigned int param_length,
                                void *scratch[],
                                unsigned int scratch_length)
{
  const struct TALER_ExchangeWithdrawValues *alg_values = data;
  size_t tlen;
  size_t len;
  uint32_t be[2];
  char *buf;

  (void) cls;
  (void) data_len;
  GNUNET_assert (1 == param_length);
  GNUNET_assert (scratch_length > 0);
  GNUNET_break (NULL == cls);
  be[0] = htonl ((uint32_t) alg_values->cipher);
  be[1] = htonl (0x010000); /* magic marker: EWV */
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_RSA:
    tlen = 0;
    break;
  case TALER_DENOMINATION_CS:
    tlen = sizeof (struct TALER_DenominationCSPublicRPairP);
    break;
  default:
    GNUNET_assert (0);
  }
  len = tlen + sizeof (be);
  buf = GNUNET_malloc (len);
  memcpy (buf,
          &be,
          sizeof (be));
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_RSA:
    break;
  case TALER_DENOMINATION_CS:
    memcpy (&buf[sizeof (be)],
            &alg_values->details.cs_values,
            tlen);
    break;
  default:
    GNUNET_assert (0);
  }
  scratch[0] = buf;
  param_values[0] = (void *) buf;
  param_lengths[0] = len;
  param_formats[0] = 1;
  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_exchange_withdraw_values (
  const struct TALER_ExchangeWithdrawValues *alg_values)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_exchange_withdraw_values,
    .data = alg_values,
    .num_params = 1
  };

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

  (void) cls;
  (void) data_len;
  GNUNET_assert (1 == param_length);
  GNUNET_assert (scratch_length > 0);
  str = json_dumps (json, JSON_COMPACT);
  if (NULL == str)
    return -1;
  scratch[0] = str;
  param_values[0] = (void *) str;
  param_lengths[0] = strlen (str);
  param_formats[0] = 1;
  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_json (const json_t *x)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv = &qconv_json,
    .data = x,
    .num_params = 1
  };

  return res;
}


/* end of pq/pq_query_helper.c */
