/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_select_aml_attributes.c
 * @brief Implementation of the select_aml_attributes function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_aml_attributes.h"
#include "pg_helper.h"


/**
 * Closure for #handle_aml_result.
 */
struct AmlAttributeResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AmlAttributeCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #TEH_PG_select_aml_process().
 *
 * @param cls closure of type `struct AmlAttributeResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_aml_attributes (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct AmlAttributeResultContext *ctx = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    char *provider_name;
    struct GNUNET_TIME_Timestamp collection_time;
    size_t enc_attributes_size;
    void *enc_attributes;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("kyc_attributes_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("provider",
                                      &provider_name),
        NULL),
      GNUNET_PQ_result_spec_timestamp ("collection_time",
                                       &collection_time),
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
             rowid,
             provider_name,
             collection_time,
             enc_attributes_size,
             enc_attributes);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_attributes (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t offset,
  int64_t limit,
  TALER_EXCHANGEDB_AmlAttributeCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  uint64_t ulimit = (limit > 0) ? limit : -limit;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint64 (&offset),
    GNUNET_PQ_query_param_uint64 (&ulimit),
    GNUNET_PQ_query_param_end
  };
  struct AmlAttributeResultContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
  const char *stmt = (limit > 0)
    ? "select_aml_attributes_inc"
    : "select_aml_attributes_dec";

  PREPARE (pg,
           "select_aml_attributes_inc",
           "SELECT"
           " kyc_attributes_serial_id"
           ",provider"
           ",collection_time"
           ",encrypted_attributes"
           " FROM kyc_attributes"
           " WHERE h_payto=$1"
           "   AND kyc_attributes_serial_id > $2"
           " ORDER BY kyc_attributes_serial_id ASC"
           " LIMIT $3");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             stmt,
                                             params,
                                             &handle_aml_attributes,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
