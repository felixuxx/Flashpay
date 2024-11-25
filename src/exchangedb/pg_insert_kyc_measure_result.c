/*
   This file is part of TALER
   Copyright (C) 2022, 2023, 2024 Taler Systems SA

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
 * @file exchangedb/pg_insert_kyc_measure_result.c
 * @brief Implementation of the insert_kyc_measure_result function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_kyc_measure_result.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_measure_result (
  void *cls,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  uint32_t birthday,
  struct GNUNET_TIME_Timestamp collection_time,
  const char *provider_name,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration_time,
  const json_t *account_properties,
  const json_t *new_rules,
  bool to_investigate,
  unsigned int num_events,
  const char **events,
  size_t enc_attributes_size,
  const void *enc_attributes)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp expiration
    = GNUNET_TIME_absolute_to_timestamp (expiration_time);
  struct TALER_KycCompletedEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
    .h_payto = *h_payto
  };
  char *kyc_completed_notify_s
    = GNUNET_PQ_get_event_notify_channel (&rep.header);
  struct GNUNET_PQ_QueryParam params[] = {
    (0 == process_row)
      ? GNUNET_PQ_query_param_null ()
      : GNUNET_PQ_query_param_uint64 (&process_row),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint32 (&birthday),
    GNUNET_PQ_query_param_string (provider_name),
    (NULL == provider_account_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (provider_account_id),
    (NULL == provider_legitimization_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (provider_legitimization_id),
    GNUNET_PQ_query_param_timestamp (&collection_time),
    GNUNET_PQ_query_param_absolute_time (&expiration_time),
    GNUNET_PQ_query_param_timestamp (&expiration),
    NULL == account_properties
    ? GNUNET_PQ_query_param_null ()
    : TALER_PQ_query_param_json (account_properties),
    NULL == new_rules
    ? GNUNET_PQ_query_param_null ()
    : TALER_PQ_query_param_json (new_rules),
    GNUNET_PQ_query_param_array_ptrs_string (num_events,
                                             events,
                                             pg->conn),
    (NULL == enc_attributes)
      ? GNUNET_PQ_query_param_null ()
      : GNUNET_PQ_query_param_fixed_size (enc_attributes,
                                          enc_attributes_size),
    GNUNET_PQ_query_param_bool (to_investigate),
    GNUNET_PQ_query_param_string (kyc_completed_notify_s),
    GNUNET_PQ_query_param_end
  };
  bool ok;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("out_ok",
                                &ok),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Inserting KYC attributes, wake up on %s\n",
              kyc_completed_notify_s);
  GNUNET_break (NULL != new_rules);
  GNUNET_break (NULL != h_payto);
  PREPARE (pg,
           "insert_kyc_measure_result",
           "SELECT "
           " out_ok"
           " FROM exchange_do_insert_kyc_measure_result "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "insert_kyc_measure_result",
                                                 params,
                                                 rs);
  GNUNET_PQ_cleanup_query_params_closures (params);
  GNUNET_free (kyc_completed_notify_s);
  GNUNET_PQ_event_do_poll (pg->conn);
  if (qs <= 0)
  {
    GNUNET_break (qs < 0);
    GNUNET_break (0);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      GNUNET_break (0);
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    }
    return qs;
  }
  if (! ok)
  {
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  return qs;
}
