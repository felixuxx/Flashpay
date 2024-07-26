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
 * @file exchangedb/pg_lookup_kyc_history.c
 * @brief Implementation of the lookup_kyc_history function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_kyc_history.h"
#include "pg_helper.h"

/**
 * Closure for callbacks called from #TEH_PG_lookup_kyc_history()
 */
struct KycHistoryContext
{

  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_KycHistoryCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to 'true' if the transaction failed.
   */
  bool failed;

};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct KycHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_kyc_entry (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct KycHistoryContext *khc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    char *provider_name = NULL;
    bool finished;
    uint32_t error_code;
    char *error_message = NULL;
    char *provider_user_id = NULL;
    char *provider_legitimization_id = NULL;
    struct GNUNET_TIME_Timestamp collection_time;
    struct GNUNET_TIME_Absolute expiration_time
      = GNUNET_TIME_UNIT_ZERO_ABS;
    void *encrypted_attributes;
    size_t encrypted_attributes_len;

    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("provider_name",
                                      &provider_name),
        NULL),
      GNUNET_PQ_result_spec_bool ("finished",
                                  &finished),
      GNUNET_PQ_result_spec_uint32 ("error_code",
                                    &error_code),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("error_message",
                                      &error_message),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("provider_user_id",
                                      &provider_user_id),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("provider_legitimization_id",
                                      &provider_legitimization_id),
        NULL),
      GNUNET_PQ_result_spec_timestamp ("collection_time",
                                       &collection_time),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_absolute_time ("expiration_time",
                                             &expiration_time),
        NULL),
      GNUNET_PQ_result_spec_variable_size ("encrypted_attributes",
                                           &encrypted_attributes,
                                           &encrypted_attributes_len),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      khc->failed = true;
      return;
    }
    khc->cb (khc->cb_cls,
             provider_name,
             finished,
             (enum TALER_ErrorCode) error_code,
             error_message,
             provider_user_id,
             provider_legitimization_id,
             collection_time,
             expiration_time,
             encrypted_attributes_len,
             encrypted_attributes);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_history (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_KycHistoryCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct KycHistoryContext khc = {
    .pg = pg,
    .cb = cb,
    .cb_cls = cb_cls
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "lookup_kyc_history",
           "SELECT"
           " lp.provider_name"
           ",lp.finished"
           ",lp.error_code"
           ",lp.error_message"
           ",lp.provider_user_id"
           ",lp.provider_legitimization_id"
           ",ka.collection_time"
           ",ka.expiration_time"
           ",ka.encrypted_attributes"
           " FROM kyc_attributes ka"
           "    JOIN legitimization_processes lp"
           "      ON (ka.legitimization_serial = lp.legitimization_process_serial)"
           " WHERE ka.h_payto=$1"
           " ORDER BY collection_time DESC;");

  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "lookup_kyc_history",
    params,
    &handle_kyc_entry,
    &khc);
  if (qs <= 0)
    return qs;
  if (khc.failed)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}
