/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_insert_aml_officer.c
 * @brief Implementation of the insert_aml_officer function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_aml_officer.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_officer (
  void *cls,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_MasterSignatureP *master_sig,
  const char *decider_name,
  bool is_active,
  bool read_only,
  struct GNUNET_TIME_Timestamp last_change,
  struct GNUNET_TIME_Timestamp *previous_change)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (decider_pub),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_string (decider_name),
    GNUNET_PQ_query_param_bool (is_active),
    GNUNET_PQ_query_param_bool (read_only),
    GNUNET_PQ_query_param_timestamp (&last_change),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("out_last_change",
                                     previous_change),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "do_insert_aml_staff",
           "SELECT"
           " out_last_change"
           " FROM exchange_do_insert_aml_officer"
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "do_insert_aml_staff",
                                                   params,
                                                   rs);
}
