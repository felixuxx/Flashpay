/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file pq/pq_result_helper.c
 * @brief functions to initialize parameter arrays
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "pq_common.h"
#include "taler_pq_lib.h"


/**
 * Extract an amount from a tuple from a Postgres database @a result at row @a row.
 *
 * @param cls closure, a `const char *` giving the currency
 * @param result where to extract data from
 * @param row row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
static enum GNUNET_GenericReturnValue
extract_amount_tuple (void *cls,
                      PGresult *result,
                      int row,
                      const char *fname,
                      size_t *dst_size,
                      void *dst)
{
  struct TALER_Amount *r_amount = dst;
  const char *currency = cls;
  int col;
  int len;

  if (sizeof (struct TALER_Amount) != *dst_size)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* Set return value to invalid in case we don't finish */
  memset (r_amount,
          0,
          sizeof (struct TALER_Amount));
  col = PQfnumber (result,
                   fname);
  if (col < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Field `%s' does not exist in result\n",
                fname);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   col))
  {
    return GNUNET_NO;
  }

  /* Parse the tuple */
  {
    char *in;
    uint32_t num;
    struct TALER_PQ_Amount_P ap;
    int size;
    const static int expected_size = sizeof(uint32_t) /* length */
                                     + sizeof(struct TALER_PQ_Amount_P);

    size = PQgetlength (result,
                        row,
                        col);

    if (expected_size != size)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Incorrect size of binary field `%s' (got %d, expected %d)\n",
                  fname,
                  size,
                  expected_size);
      return GNUNET_SYSERR;
    }

    in = PQgetvalue (result,
                     row,
                     col);

    num = ntohl (*(uint32_t *) in);
    if (2 != num)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Incorrect number of elements in tuple-field `%s'\n",
                  fname);
      return GNUNET_SYSERR;
    }
    in += sizeof(uint32_t);
    ap = *(struct TALER_PQ_Amount_P *) in;

    /* TODO[oec]: OID-checks? */

    r_amount->value = GNUNET_ntohll (ap.v);
    r_amount->fraction = ntohl (ap.f);
  }

  if (r_amount->value >= TALER_AMOUNT_MAX_VALUE)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Value in field `%s' exceeds legal range\n",
                fname);
    return GNUNET_SYSERR;
  }
  if (r_amount->fraction >= TALER_AMOUNT_FRAC_BASE)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fraction in field `%s' exceeds legal range\n",
                fname);
    return GNUNET_SYSERR;
  }

  len = GNUNET_MIN (TALER_CURRENCY_LEN - 1,
                    strlen (currency));

  GNUNET_memcpy (r_amount->currency,
                 currency,
                 len);
  return GNUNET_OK;
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_amount_tuple (const char *name,
                                   const char *currency,
                                   struct TALER_Amount *amount)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_amount_tuple,
    .cls = (void *) currency,
    .dst = (void *) amount,
    .dst_size = sizeof (*amount),
    .fname = name
  };

  return res;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
 *
 * @param cls closure
 * @param result where to extract data from
 * @param row row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
static enum GNUNET_GenericReturnValue
extract_json (void *cls,
              PGresult *result,
              int row,
              const char *fname,
              size_t *dst_size,
              void *dst)
{
  json_t **j_dst = dst;
  const char *res;
  int fnum;
  json_error_t json_error;
  size_t slen;

  (void) cls;
  (void) dst_size;
  fnum = PQfnumber (result,
                    fname);
  if (fnum < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Field `%s' does not exist in result\n",
                fname);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   fnum))
    return GNUNET_NO;
  slen = PQgetlength (result,
                      row,
                      fnum);
  res = (const char *) PQgetvalue (result,
                                   row,
                                   fnum);
  *j_dst = json_loadb (res,
                       slen,
                       JSON_REJECT_DUPLICATES,
                       &json_error);
  if (NULL == *j_dst)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse JSON result for field `%s': %s (%s)\n",
                fname,
                json_error.text,
                json_error.source);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called to clean up memory allocated
 * by a #GNUNET_PQ_ResultConverter.
 *
 * @param cls closure
 * @param rd result data to clean up
 */
static void
clean_json (void *cls,
            void *rd)
{
  json_t **dst = rd;

  (void) cls;
  if (NULL != *dst)
  {
    json_decref (*dst);
    *dst = NULL;
  }
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_json (const char *name,
                           json_t **jp)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_json,
    .cleaner = &clean_json,
    .dst = (void *) jp,
    .fname  = name
  };

  return res;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
 *
 * @param cls closure
 * @param result where to extract data from
 * @param row the row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static enum GNUNET_GenericReturnValue
extract_denom_pub (void *cls,
                   PGresult *result,
                   int row,
                   const char *fname,
                   size_t *dst_size,
                   void *dst)
{
  struct TALER_DenominationPublicKey *pk = dst;
  size_t len;
  const char *res;
  int fnum;
  uint32_t be[2];

  (void) cls;
  (void) dst_size;
  fnum = PQfnumber (result,
                    fname);
  if (fnum < 0)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   fnum))
    return GNUNET_NO;

  /* if a field is null, continue but
   * remember that we now return a different result */
  len = PQgetlength (result,
                     row,
                     fnum);
  res = PQgetvalue (result,
                    row,
                    fnum);
  if (len < sizeof (be))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_memcpy (be,
                 res,
                 sizeof (be));
  res += sizeof (be);
  len -= sizeof (be);
  pk->cipher = ntohl (be[0]);
  pk->age_mask.bits = ntohl (be[1]);
  switch (pk->cipher)
  {
  case TALER_DENOMINATION_RSA:
    pk->details.rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_decode (res,
                                             len);
    if (NULL == pk->details.rsa_public_key)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    if (sizeof (pk->details.cs_public_key) != len)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_memcpy (&pk->details.cs_public_key,
                   res,
                   len);
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


/**
 * Function called to clean up memory allocated
 * by a #GNUNET_PQ_ResultConverter.
 *
 * @param cls closure
 * @param rd result data to clean up
 */
static void
clean_denom_pub (void *cls,
                 void *rd)
{
  struct TALER_DenominationPublicKey *denom_pub = rd;

  (void) cls;
  TALER_denom_pub_free (denom_pub);
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_denom_pub (const char *name,
                                struct TALER_DenominationPublicKey *denom_pub)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_denom_pub,
    .cleaner = &clean_denom_pub,
    .dst = (void *) denom_pub,
    .fname = name
  };

  return res;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
 *
 * @param cls closure
 * @param result where to extract data from
 * @param row the row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static enum GNUNET_GenericReturnValue
extract_denom_sig (void *cls,
                   PGresult *result,
                   int row,
                   const char *fname,
                   size_t *dst_size,
                   void *dst)
{
  struct TALER_DenominationSignature *sig = dst;
  size_t len;
  const char *res;
  int fnum;
  uint32_t be[2];

  (void) cls;
  (void) dst_size;
  fnum = PQfnumber (result,
                    fname);
  if (fnum < 0)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   fnum))
    return GNUNET_NO;

  /* if a field is null, continue but
   * remember that we now return a different result */
  len = PQgetlength (result,
                     row,
                     fnum);
  res = PQgetvalue (result,
                    row,
                    fnum);
  if (len < sizeof (be))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_memcpy (&be,
                 res,
                 sizeof (be));
  if (0x00 != ntohl (be[1]))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  res += sizeof (be);
  len -= sizeof (be);
  sig->cipher = ntohl (be[0]);
  switch (sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    sig->details.rsa_signature
      = GNUNET_CRYPTO_rsa_signature_decode (res,
                                            len);
    if (NULL == sig->details.rsa_signature)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    if (sizeof (sig->details.cs_signature) != len)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_memcpy (&sig->details.cs_signature,
                   res,
                   len);
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


/**
 * Function called to clean up memory allocated
 * by a #GNUNET_PQ_ResultConverter.
 *
 * @param cls closure
 * @param rd result data to clean up
 */
static void
clean_denom_sig (void *cls,
                 void *rd)
{
  struct TALER_DenominationSignature *denom_sig = rd;

  (void) cls;
  TALER_denom_sig_free (denom_sig);
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_denom_sig (const char *name,
                                struct TALER_DenominationSignature *denom_sig)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_denom_sig,
    .cleaner = &clean_denom_sig,
    .dst = (void *) denom_sig,
    .fname = name
  };

  return res;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
 *
 * @param cls closure
 * @param result where to extract data from
 * @param row the row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static enum GNUNET_GenericReturnValue
extract_blinded_denom_sig (void *cls,
                           PGresult *result,
                           int row,
                           const char *fname,
                           size_t *dst_size,
                           void *dst)
{
  struct TALER_BlindedDenominationSignature *sig = dst;
  size_t len;
  const char *res;
  int fnum;
  uint32_t be[2];

  (void) cls;
  (void) dst_size;
  fnum = PQfnumber (result,
                    fname);
  if (fnum < 0)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   fnum))
    return GNUNET_NO;

  /* if a field is null, continue but
   * remember that we now return a different result */
  len = PQgetlength (result,
                     row,
                     fnum);
  res = PQgetvalue (result,
                    row,
                    fnum);
  if (len < sizeof (be))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_memcpy (&be,
                 res,
                 sizeof (be));
  if (0x01 != ntohl (be[1])) /* magic marker: blinded */
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  res += sizeof (be);
  len -= sizeof (be);
  sig->cipher = ntohl (be[0]);
  switch (sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    sig->details.blinded_rsa_signature
      = GNUNET_CRYPTO_rsa_signature_decode (res,
                                            len);
    if (NULL == sig->details.blinded_rsa_signature)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    if (sizeof (sig->details.blinded_cs_answer) != len)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_memcpy (&sig->details.blinded_cs_answer,
                   res,
                   len);
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


/**
 * Function called to clean up memory allocated
 * by a #GNUNET_PQ_ResultConverter.
 *
 * @param cls closure
 * @param rd result data to clean up
 */
static void
clean_blinded_denom_sig (void *cls,
                         void *rd)
{
  struct TALER_BlindedDenominationSignature *denom_sig = rd;

  (void) cls;
  TALER_blinded_denom_sig_free (denom_sig);
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_blinded_denom_sig (
  const char *name,
  struct TALER_BlindedDenominationSignature *denom_sig)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_blinded_denom_sig,
    .cleaner = &clean_blinded_denom_sig,
    .dst = (void *) denom_sig,
    .fname = name
  };

  return res;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
 *
 * @param cls closure
 * @param result where to extract data from
 * @param row the row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static enum GNUNET_GenericReturnValue
extract_blinded_planchet (void *cls,
                          PGresult *result,
                          int row,
                          const char *fname,
                          size_t *dst_size,
                          void *dst)
{
  struct TALER_BlindedPlanchet *bp = dst;
  size_t len;
  const char *res;
  int fnum;
  uint32_t be[2];

  (void) cls;
  (void) dst_size;
  fnum = PQfnumber (result,
                    fname);
  if (fnum < 0)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   fnum))
    return GNUNET_NO;

  /* if a field is null, continue but
   * remember that we now return a different result */
  len = PQgetlength (result,
                     row,
                     fnum);
  res = PQgetvalue (result,
                    row,
                    fnum);
  if (len < sizeof (be))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_memcpy (&be,
                 res,
                 sizeof (be));
  if (0x0100 != ntohl (be[1])) /* magic marker: blinded */
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  res += sizeof (be);
  len -= sizeof (be);
  bp->cipher = ntohl (be[0]);
  switch (bp->cipher)
  {
  case TALER_DENOMINATION_RSA:
    bp->details.rsa_blinded_planchet.blinded_msg_size
      = len;
    bp->details.rsa_blinded_planchet.blinded_msg
      = GNUNET_memdup (res,
                       len);
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    if (sizeof (bp->details.cs_blinded_planchet) != len)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_memcpy (&bp->details.cs_blinded_planchet,
                   res,
                   len);
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


/**
 * Function called to clean up memory allocated
 * by a #GNUNET_PQ_ResultConverter.
 *
 * @param cls closure
 * @param rd result data to clean up
 */
static void
clean_blinded_planchet (void *cls,
                        void *rd)
{
  struct TALER_BlindedPlanchet *bp = rd;

  (void) cls;
  TALER_blinded_planchet_free (bp);
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_blinded_planchet (
  const char *name,
  struct TALER_BlindedPlanchet *bp)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_blinded_planchet,
    .cleaner = &clean_blinded_planchet,
    .dst = (void *) bp,
    .fname = name
  };

  return res;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
 *
 * @param cls closure
 * @param result where to extract data from
 * @param row row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static enum GNUNET_GenericReturnValue
extract_exchange_withdraw_values (void *cls,
                                  PGresult *result,
                                  int row,
                                  const char *fname,
                                  size_t *dst_size,
                                  void *dst)
{
  struct TALER_ExchangeWithdrawValues *alg_values = dst;
  size_t len;
  const char *res;
  int fnum;
  uint32_t be[2];

  (void) cls;
  (void) dst_size;
  fnum = PQfnumber (result,
                    fname);
  if (fnum < 0)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (PQgetisnull (result,
                   row,
                   fnum))
    return GNUNET_NO;

  /* if a field is null, continue but
   * remember that we now return a different result */
  len = PQgetlength (result,
                     row,
                     fnum);
  res = PQgetvalue (result,
                    row,
                    fnum);
  if (len < sizeof (be))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_memcpy (&be,
                 res,
                 sizeof (be));
  if (0x010000 != ntohl (be[1])) /* magic marker: EWV */
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  res += sizeof (be);
  len -= sizeof (be);
  alg_values->cipher = ntohl (be[0]);
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_RSA:
    if (0 != len)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  case TALER_DENOMINATION_CS:
    if (sizeof (struct TALER_DenominationCSPublicRPairP) != len)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    GNUNET_memcpy (&alg_values->details.cs_values,
                   res,
                   len);
    return GNUNET_OK;
  default:
    GNUNET_break (0);
  }
  return GNUNET_SYSERR;
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_exchange_withdraw_values (
  const char *name,
  struct TALER_ExchangeWithdrawValues *ewv)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_exchange_withdraw_values,
    .dst = (void *) ewv,
    .fname = name
  };

  return res;
}


/**
 * Closure for the array result specifications.  Contains type information
 * for the generic parser extract_array_generic and out-pointers for the results.
 */
struct ArrayResultCls
{
  /* Oid of the expected type, must match the oid in the header of the PQResult struct */
  Oid oid;

  /* Target type */
  enum TALER_PQ_ArrayType typ;

  /* If not 0, defines the expected size of each entry */
  size_t same_size;

  /* Out-pointer to write the number of elements in the array */
  size_t *num;

  /* Out-pointer. If @a typ is TALER_PQ_array_of_byte and @a same_size is 0,
   * allocate and put the array of @a num sizes here. NULL otherwise */
  size_t **sizes;

  /* DB_connection, needed for OID-lookup for composite types */
  const struct GNUNET_PQ_Context *db;

  /* Currency information for amount composites */
  char currency[TALER_CURRENCY_LEN];
};

/**
 * Extract data from a Postgres database @a result as array of a specific type
 * from row @a row.  The type information and optionally additional
 * out-parameters are given in @a cls which is of type array_result_cls.
 *
 * @param cls closure of type array_result_cls
 * @param result where to extract data from
 * @param row row to extract data from
 * @param fname name (or prefix) of the fields to extract from
 * @param[in,out] dst_size where to store size of result, may be NULL
 * @param[out] dst where to store the result
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_SYSERR if a result was invalid (non-existing field or NULL)
 */
static enum GNUNET_GenericReturnValue
extract_array_generic (
  void *cls,
  PGresult *result,
  int row,
  const char *fname,
  size_t *dst_size,
  void *dst)
{
  const struct ArrayResultCls *info = cls;
  int data_sz;
  char *data;
  void *out = NULL;
  struct GNUNET_PQ_ArrayHeader_P header;
  int col_num;

  GNUNET_assert (NULL != dst);
  *((void **) dst) = NULL;

  #define FAIL_IF(cond) \
  do { \
    if ((cond)) \
    { \
      GNUNET_break (! (cond)); \
      goto FAIL; \
    } \
  } while(0)

  col_num = PQfnumber (result, fname);
  FAIL_IF (0 > col_num);

  data_sz = PQgetlength (result, row, col_num);
  FAIL_IF (0 > data_sz);
  FAIL_IF (sizeof(header) > (size_t) data_sz);

  data = PQgetvalue (result, row, col_num);
  FAIL_IF (NULL == data);

  {
    struct GNUNET_PQ_ArrayHeader_P *h =
      (struct GNUNET_PQ_ArrayHeader_P *) data;

    header.ndim = ntohl (h->ndim);
    header.has_null = ntohl (h->has_null);
    header.oid = ntohl (h->oid);
    header.dim = ntohl (h->dim);
    header.lbound = ntohl (h->lbound);

    FAIL_IF (1 != header.ndim);
    FAIL_IF (INT_MAX <= header.dim);
    FAIL_IF (0 != header.has_null);
    FAIL_IF (1 != header.lbound);
    FAIL_IF (info->oid != header.oid);
  }

  if (NULL != info->num)
    *info->num = header.dim;

  {
    char *in = data + sizeof(header);

    switch (info->typ)
    {
    case TALER_PQ_array_of_amount:
      {
        struct TALER_Amount *amounts;
        if (NULL != dst_size)
          *dst_size = sizeof(struct TALER_Amount) * (header.dim);

        amounts = GNUNET_new_array (header.dim, struct TALER_Amount);
        *((void **) dst) = amounts;

        for (uint32_t i = 0; i < header.dim; i++)
        {
          struct TALER_PQ_Amount_P ap;
          struct TALER_Amount *amount = &amounts[i];
          size_t sz = ntohl (*(uint32_t *) in);
          in += sizeof(uint32_t);

          /* total size for this array-entry */
          FAIL_IF ((sizeof(uint32_t)
                    + sizeof(struct TALER_PQ_Amount_P))
                   > sz);

          /* number of elements in composite type*/
          sz = ntohl (*(uint32_t *) in);
          in += sizeof(uint32_t);
          FAIL_IF (2 != sz);

          ap = *(struct TALER_PQ_Amount_P *) in;
          amount->value = GNUNET_ntohll (ap.v);
          amount->fraction = ntohl (ap.f);
          GNUNET_memcpy (amount->currency,
                         info->currency,
                         TALER_CURRENCY_LEN);

          in += sizeof(struct TALER_PQ_Amount_P);
        }
        return GNUNET_OK;
      }
    case TALER_PQ_array_of_denom_hash:
      if (NULL != dst_size)
        *dst_size = sizeof(struct TALER_DenominationHashP) * (header.dim);
      out = GNUNET_new_array (header.dim, struct TALER_DenominationHashP);
      *((void **) dst) = out;
      for (uint32_t i = 0; i < header.dim; i++)
      {
        size_t sz =  ntohl (*(uint32_t *) in);
        FAIL_IF (sz != sizeof(struct TALER_DenominationHashP));
        in += sizeof(uint32_t);
        *(struct TALER_DenominationHashP *) out =
          *(struct TALER_DenominationHashP *) in;
        in += sz;
        out += sz;
      }
      return GNUNET_OK;

    case TALER_PQ_array_of_blinded_coin_hash:
      if (NULL != dst_size)
        *dst_size = sizeof(struct TALER_BlindedCoinHashP) * (header.dim);
      out = GNUNET_new_array (header.dim, struct TALER_BlindedCoinHashP);
      *((void **) dst) = out;
      for (uint32_t i = 0; i < header.dim; i++)
      {
        size_t sz =  ntohl (*(uint32_t *) in);
        FAIL_IF (sz != sizeof(struct TALER_BlindedCoinHashP));
        in += sizeof(uint32_t);
        *(struct TALER_BlindedCoinHashP *) out =
          *(struct TALER_BlindedCoinHashP *) in;
        in += sz;
        out += sz;
      }
      return GNUNET_OK;

    case TALER_PQ_array_of_blinded_denom_sig:
      {
        struct TALER_BlindedDenominationSignature *denom_sigs;
        if (0 == header.dim)
        {
          if (NULL != dst_size)
            *dst_size = 0;
          break;
        }

        denom_sigs = GNUNET_new_array (header.dim,
                                       struct TALER_BlindedDenominationSignature);
        *((void **) dst) = denom_sigs;

        /* copy data */
        for (uint32_t i = 0; i < header.dim; i++)
        {
          struct TALER_BlindedDenominationSignature *denom_sig = &denom_sigs[i];
          uint32_t be[2];
          size_t sz =  ntohl (*(uint32_t *) in);
          in += sizeof(uint32_t);

          FAIL_IF (sizeof(be) > sz);
          GNUNET_memcpy (&be,
                         in,
                         sizeof(be));
          FAIL_IF (0x01 != ntohl (be[1]));  /* magic marker: blinded */

          in += sizeof(be);
          sz -= sizeof(be);

          denom_sig->cipher = ntohl (be[0]);
          switch (denom_sig->cipher)
          {
          case TALER_DENOMINATION_RSA:
            denom_sig->details.blinded_rsa_signature =
              GNUNET_CRYPTO_rsa_signature_decode (in,
                                                  sz);
            FAIL_IF (NULL == denom_sig->details.blinded_rsa_signature);
            break;

          case TALER_DENOMINATION_CS:
            FAIL_IF (sizeof(denom_sig->details.blinded_cs_answer) != sz);
            GNUNET_memcpy (&denom_sig->details.blinded_cs_answer,
                           in,
                           sz);
            break;

          default:
            FAIL_IF (true);
          }

          in += sz;
        }
        return GNUNET_OK;
      }
    default:
      FAIL_IF (true);
    }
  }

FAIL:
  GNUNET_free (*(void **) dst);
  return GNUNET_SYSERR;
  #undef FAIL_IF

}


/**
 * Cleanup of the data and closure of an array spec.
 */
static void
array_cleanup (void *cls,
               void *rd)
{

  struct ArrayResultCls *info = cls;
  void **dst = rd;

  if ((0 == info->same_size) &&
      (NULL != info->sizes))
    GNUNET_free (*(info->sizes));

  GNUNET_free (cls);
  GNUNET_free (*dst);
  *dst = NULL;
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_blinded_denom_sig (
  struct GNUNET_PQ_Context *db,
  const char *name,
  size_t *num,
  struct TALER_BlindedDenominationSignature **denom_sigs)
{
  struct ArrayResultCls *info = GNUNET_new (struct ArrayResultCls);

  info->num = num;
  info->typ = TALER_PQ_array_of_blinded_denom_sig;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db,
                                            "bytea",
                                            &info->oid));

  struct GNUNET_PQ_ResultSpec res = {
    .conv = extract_array_generic,
    .cleaner = array_cleanup,
    .dst = (void *) denom_sigs,
    .fname = name,
    .cls = info
  };
  return res;

};

struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_blinded_coin_hash (
  struct GNUNET_PQ_Context *db,
  const char *name,
  size_t *num,
  struct TALER_BlindedCoinHashP **h_coin_evs)
{
  struct ArrayResultCls *info = GNUNET_new (struct ArrayResultCls);

  info->num = num;
  info->typ = TALER_PQ_array_of_blinded_coin_hash;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db,
                                            "bytea",
                                            &info->oid));

  struct GNUNET_PQ_ResultSpec res = {
    .conv = extract_array_generic,
    .cleaner = array_cleanup,
    .dst = (void *) h_coin_evs,
    .fname = name,
    .cls = info
  };
  return res;

};

struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_denom_hash (
  struct GNUNET_PQ_Context *db,
  const char *name,
  size_t *num,
  struct TALER_DenominationHashP **denom_hs)
{
  struct ArrayResultCls *info = GNUNET_new (struct ArrayResultCls);

  info->num = num;
  info->typ = TALER_PQ_array_of_denom_hash;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db,
                                            "bytea",
                                            &info->oid));

  struct GNUNET_PQ_ResultSpec res = {
    .conv = extract_array_generic,
    .cleaner = array_cleanup,
    .dst = (void *) denom_hs,
    .fname = name,
    .cls = info
  };
  return res;

};

struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_array_amount (
  struct GNUNET_PQ_Context *db,
  const char *name,
  const char *currency,
  size_t *num,
  struct TALER_Amount **amounts)
{
  struct ArrayResultCls *info = GNUNET_new (struct ArrayResultCls);

  info->num = num;
  info->typ = TALER_PQ_array_of_amount;
  info->db = db;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_PQ_get_oid_by_name (db,
                                            "taler_amount",
                                            &info->oid));

  {
    size_t clen = GNUNET_MIN (TALER_CURRENCY_LEN - 1,
                              strlen (currency));
    GNUNET_memcpy (&info->currency,
                   currency,
                   clen);
  }

  struct GNUNET_PQ_ResultSpec res = {
    .conv = extract_array_generic,
    .cleaner = array_cleanup,
    .dst = (void *) amounts,
    .fname = name,
    .cls = info,
  };
  return res;


}


/* end of pq_result_helper.c */
