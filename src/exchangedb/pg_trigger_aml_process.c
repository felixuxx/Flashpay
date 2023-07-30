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
 * @file exchangedb/pg_trigger_aml_process.c
 * @brief Implementation of the trigger_aml_process function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_trigger_aml_process.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_trigger_aml_process (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_Amount *threshold_crossed)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    TALER_PQ_query_param_amount (pg->conn,
                                 threshold_crossed),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "trigger_aml_process",
           "INSERT INTO aml_status"
           "(h_payto"
           ",threshold"
           ",status)"
           "VALUES"
           "($1, $2, 1)" // 1: decision needed
           "ON CONFLICT DO"
           " UPDATE SET"
           "   threshold=$2"
           "  ,status=status | 1;"); // do not clear 'frozen' status
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "trigger_aml_process",
                                             params);
}
