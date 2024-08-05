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
 * @file exchangedb/pg_insert_aml_decision.c
 * @brief Implementation of the insert_aml_decision function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_aml_decision.h"
#include "pg_helper.h"
#include <gnunet/gnunet_pq_lib.h>


enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_decision (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  struct GNUNET_TIME_Timestamp expiration_time,
  const json_t *properties,
  const json_t *new_rules,
  bool to_investigate,
  const char *new_measure_name,
  const json_t *jmeasures,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_AmlOfficerSignatureP *decider_sig,
  bool *invalid_officer,
  bool *unknown_account,
  struct GNUNET_TIME_Timestamp *last_date)
{
  struct PostgresClosure *pg = cls;
  struct TALER_KycCompletedEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
    .h_payto = *h_payto
  };
  char *notify_s
    = GNUNET_PQ_get_event_notify_channel (&rep.header);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_timestamp (&decision_time),
    GNUNET_PQ_query_param_timestamp (&expiration_time),
    NULL != properties
    ? TALER_PQ_query_param_json (properties)
    : GNUNET_PQ_query_param_null (),
    TALER_PQ_query_param_json (new_rules),
    GNUNET_PQ_query_param_bool (to_investigate),
    NULL != new_measure_name
    ? GNUNET_PQ_query_param_string (new_measure_name)
    : GNUNET_PQ_query_param_null (),
    NULL != jmeasures
    ? TALER_PQ_query_param_json (jmeasures)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_string (justification),
    GNUNET_PQ_query_param_auto_from_type (decider_pub),
    GNUNET_PQ_query_param_auto_from_type (decider_sig),
    GNUNET_PQ_query_param_string (notify_s),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("out_invalid_officer",
                                invalid_officer),
    GNUNET_PQ_result_spec_bool ("out_account_unknown",
                                unknown_account),
    GNUNET_PQ_result_spec_timestamp ("out_last_date",
                                     last_date),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "do_insert_aml_decision",
           "SELECT"
           " out_invalid_officer"
           ",out_account_unknown"
           ",out_last_date"
           " FROM exchange_do_insert_aml_decision"
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "do_insert_aml_decision",
                                                 params,
                                                 rs);
  GNUNET_free (notify_s);
  GNUNET_PQ_event_do_poll (pg->conn);
  return qs;
}
