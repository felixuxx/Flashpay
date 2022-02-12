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
#include "taler_pq_lib.h"


/**
 * Extract a currency amount from a query result according to the
 * given specification.
 *
 * @param result the result to extract the amount from
 * @param row which row of the result to extract the amount from (needed as results can have multiple rows)
 * @param currency currency to use for @a r_amount_nbo
 * @param val_name name of the column with the amount's "value", must include the substring "_val".
 * @param frac_name name of the column with the amount's "fractional" value, must include the substring "_frac".
 * @param[out] r_amount_nbo where to store the amount, in network byte order
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
static enum GNUNET_GenericReturnValue
extract_amount_nbo_helper (PGresult *result,
                           int row,
                           const char *currency,
                           const char *val_name,
                           const char *frac_name,
                           struct TALER_AmountNBO *r_amount_nbo)
{
  int val_num;
  int frac_num;
  int len;

  /* These checks are simply to check that clients obey by our naming
     conventions, and not for any functional reason */
  GNUNET_assert (NULL !=
                 strstr (val_name,
                         "_val"));
  GNUNET_assert (NULL !=
                 strstr (frac_name,
                         "_frac"));
  /* Set return value to invalid in case we don't finish */
  memset (r_amount_nbo,
          0,
          sizeof (struct TALER_AmountNBO));
  val_num = PQfnumber (result,
                       val_name);
  frac_num = PQfnumber (result,
                        frac_name);
  if (val_num < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Field `%s' does not exist in result\n",
                val_name);
    return GNUNET_SYSERR;
  }
  if (frac_num < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Field `%s' does not exist in result\n",
                frac_name);
    return GNUNET_SYSERR;
  }
  if ( (PQgetisnull (result,
                     row,
                     val_num)) ||
       (PQgetisnull (result,
                     row,
                     frac_num)) )
  {
    return GNUNET_NO;
  }
  /* Note that Postgres stores value in NBO internally,
     so no conversion needed in this case */
  r_amount_nbo->value = *(uint64_t *) PQgetvalue (result,
                                                  row,
                                                  val_num);
  r_amount_nbo->fraction = *(uint32_t *) PQgetvalue (result,
                                                     row,
                                                     frac_num);
  len = GNUNET_MIN (TALER_CURRENCY_LEN - 1,
                    strlen (currency));
  memcpy (r_amount_nbo->currency,
          currency,
          len);
  return GNUNET_OK;
}


/**
 * Extract data from a Postgres database @a result at row @a row.
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
extract_amount_nbo (void *cls,
                    PGresult *result,
                    int row,
                    const char *fname,
                    size_t *dst_size,
                    void *dst)
{
  const char *currency = cls;
  char *val_name;
  char *frac_name;
  enum GNUNET_GenericReturnValue ret;

  if (sizeof (struct TALER_AmountNBO) != *dst_size)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_asprintf (&val_name,
                   "%s_val",
                   fname);
  GNUNET_asprintf (&frac_name,
                   "%s_frac",
                   fname);
  ret = extract_amount_nbo_helper (result,
                                   row,
                                   currency,
                                   val_name,
                                   frac_name,
                                   dst);
  GNUNET_free (val_name);
  GNUNET_free (frac_name);
  return ret;
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_amount_nbo (const char *name,
                                 const char *currency,
                                 struct TALER_AmountNBO *amount)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_amount_nbo,
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
extract_amount (void *cls,
                PGresult *result,
                int row,
                const char *fname,
                size_t *dst_size,
                void *dst)
{
  const char *currency = cls;
  struct TALER_Amount *r_amount = dst;
  char *val_name;
  char *frac_name;
  struct TALER_AmountNBO amount_nbo;
  enum GNUNET_GenericReturnValue ret;

  if (sizeof (struct TALER_AmountNBO) != *dst_size)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_asprintf (&val_name,
                   "%s_val",
                   fname);
  GNUNET_asprintf (&frac_name,
                   "%s_frac",
                   fname);
  ret = extract_amount_nbo_helper (result,
                                   row,
                                   currency,
                                   val_name,
                                   frac_name,
                                   &amount_nbo);
  if (GNUNET_OK == ret)
    TALER_amount_ntoh (r_amount,
                       &amount_nbo);
  else
    memset (r_amount,
            0,
            sizeof (struct TALER_Amount));
  GNUNET_free (val_name);
  GNUNET_free (frac_name);
  return ret;
}


struct GNUNET_PQ_ResultSpec
TALER_PQ_result_spec_amount (const char *name,
                             const char *currency,
                             struct TALER_Amount *amount)
{
  struct GNUNET_PQ_ResultSpec res = {
    .conv = &extract_amount,
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
  memcpy (be,
          res,
          sizeof (be));
  res += sizeof (be);
  len -= sizeof (be);
  pk->cipher = ntohl (be[0]);
  pk->age_mask.mask = ntohl (be[1]);
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
    memcpy (&pk->details.cs_public_key,
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
  memcpy (&be,
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
    memcpy (&sig->details.cs_signature,
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
  memcpy (&be,
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
    memcpy (&sig->details.blinded_cs_answer,
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
  memcpy (&be,
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
    memcpy (&bp->details.cs_blinded_planchet,
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
  memcpy (&be,
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
    memcpy (&alg_values->details.cs_values,
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


/* end of pq_result_helper.c */
