/*
   This file is part of TALER
   Copyright (C) 2022, 2024 Taler Systems SA

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
 * @file exchangedb/pg_update_kyc_process_by_row.c
 * @brief Implementation of the update_kyc_process_by_row function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_kyc_process_by_row.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_update_kyc_process_by_row (
  void *cls,
  uint64_t process_row,
  const char *provider_name,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  const char *redirect_url,
  struct GNUNET_TIME_Absolute expiration,
  enum TALER_ErrorCode ec,
  const char *error_message_hint,
  bool finished)
{
  struct PostgresClosure *pg = cls;
  uint32_t ec32 = (uint32_t) ec;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&process_row),
    GNUNET_PQ_query_param_string (provider_name),
    GNUNET_PQ_query_param_auto_from_type (h_payto), /*3*/
    (NULL != provider_account_id)
    ? GNUNET_PQ_query_param_string (provider_account_id)
    : GNUNET_PQ_query_param_null (), /*4*/
    (NULL != provider_legitimization_id)
    ? GNUNET_PQ_query_param_string (provider_legitimization_id)
    : GNUNET_PQ_query_param_null (), /*5*/
    (NULL != redirect_url)
    ? GNUNET_PQ_query_param_string (redirect_url)
    : GNUNET_PQ_query_param_null (), /*6*/
    GNUNET_PQ_query_param_absolute_time (&expiration),
    GNUNET_PQ_query_param_uint32 (&ec32), /* 8 */
    (NULL != error_message_hint)
    ? GNUNET_PQ_query_param_string (error_message_hint)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_bool (finished), /* 10 */
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Updating KYC data for %llu (%s)\n",
              (unsigned long long) process_row,
              provider_name);
  PREPARE (pg,
           "update_legitimization_process",
           "UPDATE legitimization_processes"
           " SET provider_user_id=$4"
           "    ,provider_legitimization_id=$5"
           "    ,redirect_url=$6"
           "    ,expiration_time=GREATEST(expiration_time,$7)"
           "    ,error_code=$8"
           "    ,error_message=$9"
           "    ,finished=$10"
           " WHERE"
           "      h_payto=$3"
           "  AND legitimization_process_serial_id=$1"
           "  AND provider_name=$2;");
  qs = GNUNET_PQ_eval_prepared_non_select (
    pg->conn,
    "update_legitimization_process",
    params);
  if (qs <= 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to update legitimization process %llu: %d\n",
                (unsigned long long) process_row,
                qs);
    return qs;
  }
  if (GNUNET_TIME_absolute_is_future (expiration))
  {
    enum GNUNET_DB_QueryStatus qs2;
    struct TALER_KycCompletedEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
      .h_payto = *h_payto
    };
    uint32_t trigger_type = 1;
    struct GNUNET_PQ_QueryParam params2[] = {
      GNUNET_PQ_query_param_auto_from_type (h_payto),
      GNUNET_PQ_query_param_uint32 (&trigger_type),
      GNUNET_PQ_query_param_end
    };

    GNUNET_PQ_event_notify (pg->conn,
                            &rep.header,
                            NULL,
                            0);
    PREPARE (pg,
             "alert_kyc_status_change",
             "INSERT INTO kyc_alerts"
             " (h_payto"
             " ,trigger_type)"
             " VALUES"
             " ($1,$2);");
    qs2 = GNUNET_PQ_eval_prepared_non_select (
      pg->conn,
      "alert_kyc_status_change",
      params2);
    if (qs2 < 0)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to store KYC alert: %d\n",
                  qs2);
  }
  return qs;
}
