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
 * @file exchangedb/pg_update_wire.c
 * @brief Implementation of the update_wire function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_wire.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_update_wire (
  void *cls,
  const struct TALER_FullPayto payto_uri,
  const char *conversion_url,
  const json_t *debit_restrictions,
  const json_t *credit_restrictions,
  struct GNUNET_TIME_Timestamp change_date,
  const struct TALER_MasterSignatureP *master_sig,
  const char *bank_label,
  int64_t priority,
  bool enabled)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri.full_payto),
    GNUNET_PQ_query_param_bool (enabled),
    NULL == conversion_url
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (conversion_url),
    enabled
    ? TALER_PQ_query_param_json (debit_restrictions)
    : GNUNET_PQ_query_param_null (),
    enabled
    ? TALER_PQ_query_param_json (credit_restrictions)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_timestamp (&change_date),
    NULL == master_sig
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (master_sig),
    NULL == bank_label
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (bank_label),
    GNUNET_PQ_query_param_int64 (&priority),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "update_wire",
           "UPDATE wire_accounts"
           " SET"
           "  is_active=$2"
           " ,conversion_url=$3"
           " ,debit_restrictions=$4"
           " ,credit_restrictions=$5"
           " ,last_change=$6"
           " ,master_sig=$7"
           " ,bank_label=$8"
           " ,priority=$9"
           " WHERE payto_uri=$1");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "update_wire",
                                             params);
}
