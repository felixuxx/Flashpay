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
 * @file exchangedb/pg_insert_succesor_measure.c
 * @brief Implementation of the insert_succesor_measure function for Postgres
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_successor_measure.h"
#include "pg_helper.h"
#include <gnunet/gnunet_pq_lib.h>


enum GNUNET_DB_QueryStatus
TEH_PG_insert_successor_measure (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *new_measure_name,
  const json_t *jmeasures,
  bool *unknown_account,
  struct GNUNET_TIME_Timestamp *last_date)
{
  struct PostgresClosure *pg = cls;
  struct TALER_KycCompletedEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
    .h_payto = *h_payto
  };
  /* We're reverting back to default rules => never expires.*/
  struct GNUNET_TIME_Timestamp expiration_time = {
    .abs_time = GNUNET_TIME_UNIT_FOREVER_ABS,
  };
  struct TALER_FullPaytoHashP h_full_payto;
  char *notify_s
    = GNUNET_PQ_get_event_notify_channel (&rep.header);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_timestamp (&decision_time),
    GNUNET_PQ_query_param_timestamp (&expiration_time),
    NULL != new_measure_name
      ? GNUNET_PQ_query_param_string (new_measure_name)
      : GNUNET_PQ_query_param_null (),
    NULL != jmeasures
      ? TALER_PQ_query_param_json (jmeasures)
      : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("out_account_unknown",
                                unknown_account),
    GNUNET_PQ_result_spec_timestamp ("out_last_date",
                                     last_date),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "do_insert_successor_measure",
           "SELECT"
           ",out_account_unknown"
           ",out_last_date"
           " FROM exchange_do_insert_successor_measure"
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "do_insert_successor_measure",
                                                 params,
                                                 rs);
  GNUNET_free (notify_s);
  GNUNET_PQ_event_do_poll (pg->conn);
  return qs;
}
