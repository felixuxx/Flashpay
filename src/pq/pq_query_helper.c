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
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_pq_lib.h>
#include "taler_pq_lib.h"
#include "pq_common.h"


/**
 * Function called to convert input amount into SQL parameter as tuple.
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
qconv_amount_tuple (void *cls,
                    const void *data,
                    size_t data_len,
                    void *param_values[],
                    int param_lengths[],
                    int param_formats[],
                    unsigned int param_length,
                    void *scratch[],
                    unsigned int scratch_length)
{
  struct GNUNET_PQ_Context *db = cls;
  const struct TALER_Amount *amount = data;
  size_t sz;

  GNUNET_assert (NULL != db);
  GNUNET_assert (NULL != amount);
  GNUNET_assert (1 == param_length);
  GNUNET_assert (1 <= scratch_length);
  GNUNET_assert (sizeof (struct TALER_Amount) == data_len);
  GNUNET_static_assert (sizeof(uint32_t) == sizeof(Oid));
  {
    char *out;
    Oid oid_v;
    Oid oid_f;

    GNUNET_assert (GNUNET_OK ==
                   GNUNET_PQ_get_oid_by_name (db,
                                              "int8",
                                              &oid_v));
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_PQ_get_oid_by_name (db,
                                              "int4",
                                              &oid_f));

    {
      struct TALER_PQ_Amount_P d
        = MAKE_TALER_PQ_AMOUNT_P (db,
                                  amount,
                                  oid_v,
                                  oid_f);
      sz = sizeof(uint32_t); /* number of elements in tuple */
      sz += sizeof(d);
      out = GNUNET_malloc (sz);
      scratch[0] = out;
      *(uint32_t *) out = htonl (2);
      out += sizeof(uint32_t);
      *(struct TALER_PQ_Amount_P*) out = d;
    }
  }

  param_values[0] = scratch[0];
  param_lengths[0] = sz;
  param_formats[0] = 1;

  return 1;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_amount_tuple (
  const struct GNUNET_PQ_Context *db,
  const struct TALER_Amount *amount)
{
  struct GNUNET_PQ_QueryParam res = {
    .conv_cls = (void *) db,
    .conv = &qconv_amount_tuple,
    .data = amount,
    .size = sizeof (*amount),
    .num_params = 1,
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
  GNUNET_memcpy (buf,
                 be,
                 sizeof (be));
  switch (denom_pub->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_memcpy (&buf[sizeof (be)],
                   tbuf,
                   tlen);
    GNUNET_free (tbuf);
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_memcpy (&buf[sizeof (be)],
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
  GNUNET_memcpy (buf,
                 &be,
                 sizeof (be));
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_memcpy (&buf[sizeof (be)],
                   tbuf,
                   tlen);
    GNUNET_free (tbuf);
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_memcpy (&buf[sizeof (be)],
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
  GNUNET_memcpy (buf,
                 &be,
                 sizeof (be));
  switch (denom_sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_memcpy (&buf[sizeof (be)],
                   tbuf,
                   tlen);
    GNUNET_free (tbuf);
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_memcpy (&buf[sizeof (be)],
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
  GNUNET_memcpy (buf,
                 &be,
                 sizeof (be));
  switch (bp->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_memcpy (&buf[sizeof (be)],
                   bp->details.rsa_blinded_planchet.blinded_msg,
                   tlen);
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_memcpy (&buf[sizeof (be)],
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
  GNUNET_memcpy (buf,
                 &be,
                 sizeof (be));
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_RSA:
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_memcpy (&buf[sizeof (be)],
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


/** ------------------- Array support  -----------------------------------**/

/**
 * Closure for the array type handlers.
 *
 * May contain sizes information for the data, given (and handled) by the
 * caller.
 */
struct qconv_array_cls
{
  /**
   * If not null, contains the array of sizes (the size of the array is the
   * .size field in the ambient GNUNET_PQ_QueryParam struct). We do not free
   * this memory.
   *
   * If not null, this value has precedence over @a sizes, which MUST be NULL */
  const size_t *sizes;

  /**
   * If @a size and @a c_sizes are NULL, this field defines the same size
   * for each element in the array.
   */
  size_t same_size;

  /**
   * If true, the array parameter to the data pointer to the qconv_array is a
   * continuous byte array of data, either with @a same_size each or sizes
   * provided bytes by @a sizes;
   */
  bool continuous;

  /**
   * Type of the array elements
   */
  enum TALER_PQ_ArrayType typ;

  /**
   * Oid of the array elements
   */
  Oid oid;

  /**
   * db context, needed for OID-lookup of basis-types
   */
  struct GNUNET_PQ_Context *db;
};

/**
 * Callback to cleanup a qconv_array_cls to be used during
 * GNUNET_PQ_cleanup_query_params_closures
 */
static void
qconv_array_cls_cleanup (void *cls)
{
  GNUNET_free (cls);
}


/**
 * Function called to convert input argument into SQL parameters for arrays
 *
 * Note: the format for the encoding of arrays for libpq is not very well
 * documented.  We peeked into various sources (postgresql and libpqtypes) for
 * guidance.
 *
 * @param cls Closure of type struct qconv_array_cls*
 * @param data Pointer to first element in the array
 * @param data_len Number of _elements_ in array @a data (if applicable)
 * @param[out] param_values SQL data to set
 * @param[out] param_lengths SQL length data to set
 * @param[out] param_formats SQL format data to set
 * @param param_length number of entries available in the @a param_values, @a param_lengths and @a param_formats arrays
 * @param[out] scratch buffer for dynamic allocations (to be done via #GNUNET_malloc()
 * @param scratch_length number of entries left in @a scratch
 * @return -1 on error, number of offsets used in @a scratch otherwise
 */
static int
qconv_array (
  void *cls,
  const void *data,
  size_t data_len,
  void *param_values[],
  int param_lengths[],
  int param_formats[],
  unsigned int param_length,
  void *scratch[],
  unsigned int scratch_length)
{
  struct qconv_array_cls *meta = cls;
  size_t num = data_len;
  size_t total_size;
  const size_t *sizes;
  bool same_sized;
  void *elements = NULL;
  bool noerror = true;
  /* needed to capture the encoded rsa signatures */
  void **buffers = NULL;
  size_t *buffer_lengths = NULL;

  (void) (param_length);
  (void) (scratch_length);

  GNUNET_assert (NULL != meta);
  GNUNET_assert (num < INT_MAX);

  sizes = meta->sizes;
  same_sized = (0 != meta->same_size);

#define RETURN_UNLESS(cond) \
  do { \
    if (! (cond)) \
    { \
      GNUNET_break ((cond)); \
      noerror = false; \
      goto DONE; \
    } \
  } while(0)

  /* Calculate sizes and check bounds */
  {
    /* num * length-field */
    size_t x = sizeof(uint32_t);
    size_t y = x * num;
    RETURN_UNLESS ((0 == num) || (y / num == x));

    /* size of header */
    total_size  = x = sizeof(struct GNUNET_PQ_ArrayHeader_P);
    total_size += y;
    RETURN_UNLESS (total_size >= x);

    /* sizes of elements */
    if (same_sized)
    {
      x = num * meta->same_size;
      RETURN_UNLESS ((0 == num) || (x / num == meta->same_size));

      y = total_size;
      total_size += x;
      RETURN_UNLESS (total_size >= y);
    }
    else  /* sizes are different per element */
    {

      switch (meta->typ)
      {
      case TALER_PQ_array_of_blinded_denom_sig:
        {
          const struct TALER_BlindedDenominationSignature *denom_sigs = data;
          size_t len;

          buffers  = GNUNET_new_array (num, void *);
          buffer_lengths  = GNUNET_new_array (num, size_t);

          for (size_t i = 0; i<num; i++)
          {
            switch (denom_sigs[i].cipher)
            {
            case TALER_DENOMINATION_RSA:
              len = GNUNET_CRYPTO_rsa_signature_encode (
                denom_sigs[i].details.blinded_rsa_signature,
                &buffers[i]);
              RETURN_UNLESS (len != 0);
              break;
            case TALER_DENOMINATION_CS:
              len = sizeof (denom_sigs[i].details.blinded_cs_answer);
              break;
            default:
              GNUNET_assert (0);
            }

            /* for the cipher and marker */
            len += 2 * sizeof(uint32_t);
            buffer_lengths[i] = len;

            y = total_size;
            total_size += len;
            RETURN_UNLESS (total_size >= y);
          }
          sizes = buffer_lengths;
          break;
        }
      default:
        GNUNET_assert (0);
      }
    }

    RETURN_UNLESS (INT_MAX > total_size);
    RETURN_UNLESS (0 != total_size);

    elements = GNUNET_malloc (total_size);
  }

  /* Write data */
  {
    char *out = elements;
    struct GNUNET_PQ_ArrayHeader_P h = {
      .ndim = htonl (1),        /* We only support one-dimensional arrays */
      .has_null = htonl (0),    /* We do not support NULL entries in arrays */
      .lbound = htonl (1),      /* Default start index value */
      .dim = htonl (num),
      .oid = htonl (meta->oid),
    };

    /* Write header */
    GNUNET_memcpy (out, &h, sizeof(h));
    out += sizeof(h);


    /* Write elements */
    for (size_t i = 0; i < num; i++)
    {
      size_t sz = same_sized ? meta->same_size : sizes[i];

      *(uint32_t *) out = htonl (sz);
      out += sizeof(uint32_t);

      switch (meta->typ)
      {
      case TALER_PQ_array_of_amount:
        {
          const struct TALER_Amount *amounts = data;
          Oid oid_v, oid_f;
          GNUNET_assert (GNUNET_OK ==
                         GNUNET_PQ_get_oid_by_name (meta->db,
                                                    "int8",
                                                    &oid_v));
          GNUNET_assert (GNUNET_OK ==
                         GNUNET_PQ_get_oid_by_name (meta->db,
                                                    "int4",
                                                    &oid_f));
          {
            struct TALER_PQ_Amount_P am = MAKE_TALER_PQ_AMOUNT_P (meta->db,
                                                                  &amounts[i],
                                                                  oid_v,
                                                                  oid_f);

            *(uint32_t *) out = htonl (2); /* number of elements in tuple */
            out += sizeof(uint32_t);
            sz -= sizeof(uint32_t);
            GNUNET_memcpy (out,
                           &am,
                           sizeof(am));
          }
          break;
        }
      case TALER_PQ_array_of_blinded_denom_sig:
        {
          const struct TALER_BlindedDenominationSignature *denom_sigs = data;

          uint32_t be[2];
          be[0] = htonl ((uint32_t) denom_sigs[i].cipher);
          be[1] = htonl (0x01);     /* magic margker: blinded */
          GNUNET_memcpy (out,
                         &be,
                         sizeof(be));
          out += sizeof(be);
          sz -= sizeof(be);

          switch (denom_sigs[i].cipher)
          {
          case TALER_DENOMINATION_RSA:
            {
              void *buf = buffers[i];

              GNUNET_memcpy (out,
                             buf,
                             sz);
              break;
            }
          case TALER_DENOMINATION_CS:
            GNUNET_memcpy (out,
                           &denom_sigs[i].details.blinded_cs_answer,
                           sz);
            break;
          default:
            GNUNET_assert (0);
          }
          break;
        }
      case TALER_PQ_array_of_blinded_coin_hash:
        {
          const struct TALER_BlindedCoinHashP *coin_hs = data;
          GNUNET_memcpy (out,
                         &coin_hs[i],
                         sizeof(struct TALER_BlindedCoinHashP));

          break;
        }
      case TALER_PQ_array_of_denom_hash:
        {
          const struct TALER_DenominationHashP *denom_hs = data;
          GNUNET_memcpy (out,
                         &denom_hs[i],
                         sizeof(struct TALER_DenominationHashP));
          break;
        }
      default:
        {
          GNUNET_assert (0);
          break;
        }
      }
      out += sz;
    }
  }

  param_values[0] = elements;
  param_lengths[0] = total_size;
  param_formats[0] = 1;
  scratch[0] = elements;

DONE:
  if (NULL != buffers)
  {
    for (size_t i = 0; i<num; i++)
      GNUNET_free (buffers[i]);
    GNUNET_free (buffers);
  }
  GNUNET_free (buffer_lengths);

  if (noerror)
    return 1;

  return -1;
}


/**
 * Function to generate a typ specific query parameter and corresponding closure
 *
 * @param num Number of elements in @a elements
 * @param continuous If true, @a elements is an continuous array of data
 * @param elements Array of @a num elements, either continuous or pointers
 * @param sizes Array of @a num sizes, one per element, may be NULL
 * @param same_size If not 0, all elements in @a elements have this size
 * @param typ Supported internal type of each element in @a elements
 * @param oid Oid of the type to be used in Postgres
 * @return Query parameter
 */
static struct GNUNET_PQ_QueryParam
query_param_array_generic (
  unsigned int num,
  bool continuous,
  const void *elements,
  const size_t *sizes,
  size_t same_size,
  enum TALER_PQ_ArrayType typ,
  Oid oid,
  struct GNUNET_PQ_Context *db)
{
  struct qconv_array_cls *meta = GNUNET_new (struct qconv_array_cls);
  meta->typ = typ;
  meta->oid = oid;
  meta->sizes = sizes;
  meta->same_size = same_size;
  meta->continuous = continuous;
  meta->db = db;

  struct GNUNET_PQ_QueryParam res = {
    .conv = qconv_array,
    .conv_cls = meta,
    .conv_cls_cleanup = qconv_array_cls_cleanup,
    .data = elements,
    .size = num,
    .num_params = 1,
  };

  return res;
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_array_blinded_denom_sig (
  size_t num,
  const struct TALER_BlindedDenominationSignature *denom_sigs,
  struct GNUNET_PQ_Context *db)
{
  Oid oid;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db, "bytea", &oid));
  return query_param_array_generic (num,
                                    true,
                                    denom_sigs,
                                    NULL,
                                    0,
                                    TALER_PQ_array_of_blinded_denom_sig,
                                    oid,
                                    NULL);
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_array_blinded_coin_hash (
  size_t num,
  const struct TALER_BlindedCoinHashP *coin_hs,
  struct GNUNET_PQ_Context *db)
{
  Oid oid;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db, "bytea", &oid));
  return query_param_array_generic (num,
                                    true,
                                    coin_hs,
                                    NULL,
                                    sizeof(struct TALER_BlindedCoinHashP),
                                    TALER_PQ_array_of_blinded_coin_hash,
                                    oid,
                                    NULL);
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_array_denom_hash (
  size_t num,
  const struct TALER_DenominationHashP *denom_hs,
  struct GNUNET_PQ_Context *db)
{
  Oid oid;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db, "bytea", &oid));
  return query_param_array_generic (num,
                                    true,
                                    denom_hs,
                                    NULL,
                                    sizeof(struct TALER_DenominationHashP),
                                    TALER_PQ_array_of_denom_hash,
                                    oid,
                                    NULL);
}


struct GNUNET_PQ_QueryParam
TALER_PQ_query_param_array_amount (
  size_t num,
  const struct TALER_Amount *amounts,
  struct GNUNET_PQ_Context *db)
{
  Oid oid;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db, "taler_amount", &oid));
  return query_param_array_generic (
    num,
    true,
    amounts,
    NULL,
    sizeof(uint32_t) + sizeof(struct TALER_PQ_Amount_P),
    TALER_PQ_array_of_amount,
    oid,
    db);
}


/* end of pq/pq_query_helper.c */
