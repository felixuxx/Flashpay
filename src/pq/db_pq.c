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
 * @file pq/db_pq.c
 * @brief helper functions for libpq (PostGres) interactions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_pq_lib.h"


/**
 * Execute a prepared statement.
 *
 * @param db_conn database connection
 * @param name name of the prepared statement
 * @param params parameters to the statement
 * @return postgres result
 */
PGresult *
TALER_PQ_exec_prepared (PGconn *db_conn,
                        const char *name,
                        const struct TALER_PQ_QueryParam *params)
{
  unsigned int len;
  unsigned int i;

  /* count the number of parameters */
  i = 0;
  len = 0;
  while (TALER_PQ_QF_END != params[i].format)
  {
    const struct TALER_PQ_QueryParam *x = &params[i];

    switch (x->format)
    {
    case TALER_PQ_QF_FIXED_BLOB:
    case TALER_PQ_QF_VARSIZE_BLOB:
      len++;
      break;
    case TALER_PQ_QF_AMOUNT_NBO:
    case TALER_PQ_QF_AMOUNT:
      len += 3;
      break;
    case TALER_PQ_QF_RSA_PUBLIC_KEY:
    case TALER_PQ_QF_RSA_SIGNATURE:
    case TALER_PQ_QF_TIME_ABSOLUTE:
      len++;
      break;
    default:
      /* format not supported */
      GNUNET_assert (0);
      break;
    }
    i++;
  }

  /* new scope to allow stack allocation without alloca */
  {
    /* Scratch buffer for temporary storage */
    void *scratch[len];
    /* Parameter array we are building for the query */
    void *param_values[len];
    int param_lengths[len];
    int param_formats[len];
    unsigned int off;
    /* How many entries in the scratch buffer are in use? */
    unsigned int soff;
    PGresult *res;

    i = 0;
    off = 0;
    soff = 0;
    while (TALER_PQ_QF_END != params[i].format)
    {
      const struct TALER_PQ_QueryParam *x = &params[i];

      switch (x->format)
      {
      case TALER_PQ_QF_FIXED_BLOB:
      case TALER_PQ_QF_VARSIZE_BLOB:
        param_values[off] = (void *) x->data;
        param_lengths[off] = x->size;
        param_formats[off] = 1;
        off++;
        break;
      case TALER_PQ_QF_AMOUNT_NBO:
        {
          const struct TALER_Amount *amount = x->data;

          param_values[off] = (void *) &amount->value;
          param_lengths[off] = sizeof (amount->value);
          param_formats[off] = 1;
          off++;
          param_values[off] = (void *) &amount->fraction;
          param_lengths[off] = sizeof (amount->fraction);
          param_formats[off] = 1;
          off++;
          param_values[off] = (void *) amount->currency;
          param_lengths[off] = strlen (amount->currency) + 1;
          param_formats[off] = 1;
          off++;
        }
        break;
      case TALER_PQ_QF_AMOUNT:
        {
          const struct TALER_Amount *amount_hbo = x->data;
          struct TALER_AmountNBO *amount;

          amount = GNUNET_new (struct TALER_AmountNBO);
          scratch[soff++] = amount;
          TALER_amount_hton (amount,
                             amount_hbo);
          param_values[off] = (void *) &amount->value;
          param_lengths[off] = sizeof (amount->value);
          param_formats[off] = 1;
          off++;
          param_values[off] = (void *) &amount->fraction;
          param_lengths[off] = sizeof (amount->fraction);
          param_formats[off] = 1;
          off++;
          param_values[off] = (void *) amount->currency;
          param_lengths[off] = strlen (amount->currency) + 1;
          param_formats[off] = 1;
          off++;
        }
        break;
      case TALER_PQ_QF_RSA_PUBLIC_KEY:
        {
          const struct GNUNET_CRYPTO_rsa_PublicKey *rsa = x->data;
          char *buf;
          size_t buf_size;

          buf_size = GNUNET_CRYPTO_rsa_public_key_encode (rsa,
                                                          &buf);
          scratch[soff++] = buf;
          param_values[off] = (void *) buf;
          param_lengths[off] = buf_size - 1; /* DB doesn't like the trailing \0 */
          param_formats[off] = 1;
          off++;
        }
        break;
      case TALER_PQ_QF_RSA_SIGNATURE:
        {
          const struct GNUNET_CRYPTO_rsa_Signature *sig = x->data;
          char *buf;
          size_t buf_size;

          buf_size = GNUNET_CRYPTO_rsa_signature_encode (sig,
                                                         &buf);
          scratch[soff++] = buf;
          param_values[off] = (void *) buf;
          param_lengths[off] = buf_size - 1; /* DB doesn't like the trailing \0 */
          param_formats[off] = 1;
          off++;
        }
        break;
      case TALER_PQ_QF_TIME_ABSOLUTE:
        {
          const struct GNUNET_TIME_Absolute *at_hbo = x->data;
          struct GNUNET_TIME_AbsoluteNBO *at_nbo;
	  
          at_nbo = GNUNET_new (struct GNUNET_TIME_AbsoluteNBO);
          scratch[soff++] = at_nbo;
	  /* FIXME: this does not work for 'forever' as PQ uses 63-bit integers;
	     should check and handle! (Need testcase!) */
          *at_nbo = GNUNET_TIME_absolute_hton (*at_hbo);
          param_values[off] = (void *) at_nbo;
          param_lengths[off] = sizeof (struct GNUNET_TIME_AbsoluteNBO);
          param_formats[off] = 1;
          off++;
        }
        break;
      default:
        /* format not supported */
        GNUNET_assert (0);
        break;
      }
      i++;
    }
    GNUNET_assert (off == len);
    res = PQexecPrepared (db_conn,
                          name,
                          len,
                          (const char **) param_values,
                          param_lengths,
                          param_formats,
                          1);
    for (off = 0; off < soff; off++)
      GNUNET_free (scratch[off]);
    return res;
  }
}


/**
 * Free all memory that was allocated in @a rs during
 * #TALER_PQ_extract_result().
 *
 * @param rs reult specification to clean up
 */
void
TALER_PQ_cleanup_result (struct TALER_PQ_ResultSpec *rs)
{
  unsigned int i;

  for (i=0; TALER_PQ_RF_END != rs[i].format; i++)
  {
    switch (rs[i].format)
    {
    case TALER_PQ_RF_VARSIZE_BLOB:
      if (NULL != rs[i].dst)
      {
        GNUNET_free (rs[i].dst);
        rs[i].dst = NULL;
        *rs[i].result_size = 0;
      }
      break;
    case TALER_PQ_RF_RSA_PUBLIC_KEY:
      if (NULL != rs[i].dst)
      {
        GNUNET_CRYPTO_rsa_public_key_free (rs[i].dst);
        rs[i].dst = NULL;
      }
      break;
    case TALER_PQ_RF_RSA_SIGNATURE:
      if (NULL != rs[i].dst)
      {
        GNUNET_CRYPTO_rsa_signature_free (rs[i].dst);
        rs[i].dst = NULL;
      }
      break;
    default:
      break;
    }
  }
}


/**
 * Extract results from a query result according to the given specification.
 * If colums are NULL, the destination is not modified, and #GNUNET_NO
 * is returned.
 *
 * @param result result to process
 * @param[in|out] rs result specification to extract for
 * @param row row from the result to extract
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_PQ_extract_result (PGresult *result,
                         struct TALER_PQ_ResultSpec *rs,
                         int row)
{
  unsigned int i;
  int had_null = GNUNET_NO;

  for (i=0; TALER_PQ_RF_END != rs[i].format; i++)
  {
    struct TALER_PQ_ResultSpec *spec;

    spec = &rs[i];
    switch (spec->format)
    {
    case TALER_PQ_RF_FIXED_BLOB:
    case TALER_PQ_RF_VARSIZE_BLOB:
      {
        size_t len;
        const char *res;
        void *dst;
        int fnum;

        fnum = PQfnumber (result,
                          spec->fname);
        if (fnum < 0)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' does not exist in result\n",
                      spec->fname);
          return GNUNET_SYSERR;
        }
        if (PQgetisnull (result,
                         row,
                         fnum))
        {
          had_null = GNUNET_YES;
          continue;
        }

        /* if a field is null, continue but
         * remember that we now return a different result */
        len = PQgetlength (result,
                           row,
                           fnum);
        if ( (0 != spec->dst_size) &&
             (spec->dst_size != len) )
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' has wrong size (got %u, expected %u)\n",
                      spec->fname,
                      (unsigned int) len,
                      (unsigned int) spec->dst_size);
          TALER_PQ_cleanup_result (rs);
          return GNUNET_SYSERR;
        }
        res = PQgetvalue (result,
                          row,
                          fnum);
        GNUNET_assert (NULL != res);
        if (0 == spec->dst_size)
        {
          if (NULL != spec->result_size)
            *spec->result_size = len;
          spec->dst_size = len;
          dst = GNUNET_malloc (len);
          *((void **) spec->dst) = dst;
        }
        else
          dst = spec->dst;
        memcpy (dst,
                res,
                len);
        break;
      }
    case TALER_PQ_RF_AMOUNT_NBO:
      {
        char *val_name;
        char *frac_name;
        char *curr_name;
        const char *name = spec->fname;
        int ret;

        GNUNET_assert (NULL != spec->dst);
        GNUNET_assert (sizeof (struct TALER_AmountNBO) ==
                       spec->dst_size);
        GNUNET_asprintf (&val_name,
                         "%s_val",
                         name);
        GNUNET_asprintf (&frac_name,
                         "%s_frac",
                         name);
        GNUNET_asprintf (&curr_name,
                         "%s_curr",
                         name);
        ret = TALER_PQ_extract_amount_nbo (result,
                                           row,
                                           val_name,
                                           frac_name,
                                           curr_name,
                                           spec->dst);
        GNUNET_free (val_name);
        GNUNET_free (frac_name);
        GNUNET_free (curr_name);
        if (GNUNET_SYSERR == ret)
          return GNUNET_SYSERR;
        if (GNUNET_OK != ret)
          had_null = GNUNET_YES;
        break;
      }
    case TALER_PQ_RF_AMOUNT:
      {
        char *val_name;
        char *frac_name;
        char *curr_name;
        const char *name = spec->fname;
        int ret;

        GNUNET_assert (NULL != spec->dst);
        GNUNET_assert (sizeof (struct TALER_Amount) ==
                       spec->dst_size);
        GNUNET_asprintf (&val_name,
                         "%s_val",
                         name);
        GNUNET_asprintf (&frac_name,
                         "%s_frac",
                         name);
        GNUNET_asprintf (&curr_name,
                         "%s_curr",
                         name);
        ret = TALER_PQ_extract_amount (result,
                                       row,
                                       val_name,
                                       frac_name,
                                       curr_name,
                                       spec->dst);
        GNUNET_free (val_name);
        GNUNET_free (frac_name);
        GNUNET_free (curr_name);
        if (GNUNET_SYSERR == ret)
          return GNUNET_SYSERR;
        if (GNUNET_OK != ret)
          had_null = GNUNET_YES;
        break;
      }
    case TALER_PQ_RF_RSA_PUBLIC_KEY:
      {
        struct GNUNET_CRYPTO_rsa_PublicKey **pk = spec->dst;
        size_t len;
        const char *res;
        int fnum;

	*pk = NULL;
        fnum = PQfnumber (result,
                          spec->fname);
        if (fnum < 0)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' does not exist in result\n",
                      spec->fname);
          return GNUNET_SYSERR;
        }
        if (PQgetisnull (result,
                         row,
                         fnum))
        {
          had_null = GNUNET_YES;
          continue;
        }

        /* if a field is null, continue but
         * remember that we now return a different result */
        len = PQgetlength (result,
                           row,
                           fnum);
        res = PQgetvalue (result,
                          row,
                          fnum);
        *pk = GNUNET_CRYPTO_rsa_public_key_decode (res,
                                                   len);
        if (NULL == *pk)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' contains bogus value (fails to decode)\n",
                      spec->fname);
          return GNUNET_SYSERR;
        }
        break;
      }
    case TALER_PQ_RF_RSA_SIGNATURE:
      {
        struct GNUNET_CRYPTO_rsa_Signature **sig = spec->dst;
        size_t len;
        const char *res;
        int fnum;

	*sig = NULL;
        fnum = PQfnumber (result,
                          spec->fname);
        if (fnum < 0)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' does not exist in result\n",
                      spec->fname);
          return GNUNET_SYSERR;
        }
        if (PQgetisnull (result,
                         row,
                         fnum))
        {
          had_null = GNUNET_YES;
          continue;
        }

        /* if a field is null, continue but
         * remember that we now return a different result */
        len = PQgetlength (result,
                           row,
                           fnum);
        res = PQgetvalue (result,
                          row,
                          fnum);
        *sig = GNUNET_CRYPTO_rsa_signature_decode (res,
                                                   len);
        if (NULL == *sig)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' contains bogus value (fails to decode)\n",
                      spec->fname);
          return GNUNET_SYSERR;
        }
        break;
      }
    case TALER_PQ_RF_TIME_ABSOLUTE:
      {
        struct GNUNET_TIME_Absolute *dst = spec->dst;
	const struct GNUNET_TIME_AbsoluteNBO *res;
	int fnum;

        fnum = PQfnumber (result,
                          spec->fname);
        if (fnum < 0)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Field `%s' does not exist in result\n",
                      spec->fname);
          return GNUNET_SYSERR;
        }
        if (PQgetisnull (result,
                         row,
                         fnum))
        {
          had_null = GNUNET_YES;
          continue;
        }
        GNUNET_assert (NULL != dst);
        GNUNET_assert (sizeof (struct GNUNET_TIME_AbsoluteNBO) ==
                       spec->dst_size);
        res = (const struct GNUNET_TIME_AbsoluteNBO *)
	  PQgetvalue (result,
		      row,
		      fnum);
	/* FIXME: this does not work for 'forever' as PQ uses 63-bit integers;
	   should check and handle! (Need testcase!) */
	*dst = GNUNET_TIME_absolute_ntoh (*res);
        break;
      }

    default:
      GNUNET_assert (0);
      break;
    }
  }
  if (GNUNET_YES == had_null)
    return GNUNET_NO;
  return GNUNET_YES;
}


/**
 * Extract a currency amount from a query result according to the
 * given specification.
 *
 * @param result the result to extract the amount from
 * @param row which row of the result to extract the amount from (needed as results can have multiple rows)
 * @param val_name name of the column with the amount's "value", must include the substring "_val".
 * @param frac_name name of the column with the amount's "fractional" value, must include the substring "_frac".
 * @param curr_name name of the column with the amount's currency name, must include the substring "_curr".
 * @param[out] r_amount_nbo where to store the amount, in network byte order
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_PQ_extract_amount_nbo (PGresult *result,
                             int row,
                             const char *val_name,
                             const char *frac_name,
                             const char *curr_name,
                             struct TALER_AmountNBO *r_amount_nbo)
{
  int val_num;
  int frac_num;
  int curr_num;
  int len;

  /* These checks are simply to check that clients obey by our naming
     conventions, and not for any functional reason */
  GNUNET_assert (NULL !=
                 strstr (val_name,
                         "_val"));
  GNUNET_assert (NULL !=
                 strstr (frac_name,
                         "_frac"));
  GNUNET_assert (NULL !=
                 strstr (curr_name,
                         "_curr"));
  /* Set return value to invalid in case we don't finish */
  memset (r_amount_nbo,
          0,
          sizeof (struct TALER_AmountNBO));
  val_num = PQfnumber (result,
                       val_name);
  frac_num = PQfnumber (result,
                        frac_name);
  curr_num = PQfnumber (result,
                        curr_name);
  if ( (val_num < 0) ||
       (frac_num < 0) ||
       (curr_num < 0) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if ( (PQgetisnull (result,
                     row,
                     val_num)) ||
       (PQgetisnull (result,
                     row,
                     frac_num)) ||
       (PQgetisnull (result,
                     row,
                     curr_num)) )
  {
    GNUNET_break (0);
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
                    PQgetlength (result,
                                 row,
                                 curr_num));
  memcpy (r_amount_nbo->currency,
          PQgetvalue (result,
                      row,
                      curr_num),
          len);
  return GNUNET_OK;
}


/**
 * Extract a currency amount from a query result according to the
 * given specification.
 *
 * @param result the result to extract the amount from
 * @param row which row of the result to extract the amount from (needed as
 *          results can have multiple rows)
 * @param val_name name of the column with the amount's "value", must include
 *          the substring "_val".
 * @param frac_name name of the column with the amount's "fractional" value,
 *          must include the substring "_frac".
 * @param curr_name name of the column with the amount's currency name, must
 *          include the substring "_curr".
 * @param[out] r_amount where to store the amount, in host byte order
 * @return
 *   #GNUNET_YES if all results could be extracted
 *   #GNUNET_NO if at least one result was NULL
 *   #GNUNET_SYSERR if a result was invalid (non-existing field)
 */
int
TALER_PQ_extract_amount (PGresult *result,
                         int row,
                         const char *val_name,
                         const char *frac_name,
                         const char *curr_name,
                         struct TALER_Amount *r_amount)
{
  struct TALER_AmountNBO amount_nbo;
  int ret;

  ret = TALER_PQ_extract_amount_nbo (result,
                                     row,
                                     val_name,
                                     frac_name,
                                     curr_name,
                                     &amount_nbo);
  TALER_amount_ntoh (r_amount,
                     &amount_nbo);
  return ret;
}


/* end of pq/db_pq.c */
