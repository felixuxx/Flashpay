/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file exchangedb/pg_select_similar_kyc_attributes.c
 * @brief Implementation of the select_similar_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_similar_kyc_attributes.h"
#include "pg_helper.h"


/**
 * Closure for #get_similar_attributes_cb().
 */
struct GetAttributesContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_AttributeCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Flag set to #GNUNET_OK as long as everything is fine.
   */
  enum GNUNET_GenericReturnValue status;

};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct GetAttributesContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_attributes_cb (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct GetAttributesContext *ctx = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_PaytoHashP h_payto;
    struct GNUNET_TIME_Timestamp collection_time;
    struct GNUNET_TIME_Timestamp expiration_time;
    size_t enc_attributes_size;
    void *enc_attributes;
    char *provider;
    char *birthdate = NULL;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                            &h_payto),
      GNUNET_PQ_result_spec_string ("provider",
                                    &provider),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("birthdate",
                                      &birthdate),
        NULL),
      GNUNET_PQ_result_spec_timestamp ("collection_time",
                                       &collection_time),
      GNUNET_PQ_result_spec_timestamp ("expiration_time",
                                       &expiration_time),
      GNUNET_PQ_result_spec_variable_size ("encrypted_attributes",
                                           &enc_attributes,
                                           &enc_attributes_size),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ctx->cb (ctx->cb_cls,
             &h_payto,
             provider,
             birthdate,
             collection_time,
             expiration_time,
             enc_attributes_size,
             enc_attributes);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_similar_kyc_attributes (
  void *cls,
  const struct GNUNET_ShortHashCode *kyc_prox,
  TALER_EXCHANGEDB_AttributeCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (kyc_prox),
    GNUNET_PQ_query_param_end
  };
  struct GetAttributesContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "select_similar_kyc_attributes",
           "SELECT "
           " h_payto"
           ",provider"
           ",birthdate"
           ",collection_time"
           ",expiration_time"
           ",encrypted_attributes"
           " FROM kyc_attributes"
           " WHERE kyc_prox=$1");
  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "select_similar_kyc_attributes",
    params,
    &get_attributes_cb,
    &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
