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
 * @file exchangedb/pg_set_aml_lock.c
 * @brief Implementation of the set_aml_lock function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_set_aml_lock.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_set_aml_lock (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Relative lock_duration,
  struct GNUNET_TIME_Absolute *existing_lock)
{

  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute expires
    = GNUNET_TIME_relative_to_absolute (lock_duration);
  struct GNUNET_TIME_Absolute now
    = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_absolute_time (&expires),
    GNUNET_PQ_query_param_end
  };
  bool nx; /* true if the *account* is not known */
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_absolute_time ("out_aml_program_lock_timeout",
                                           existing_lock),
      &nx),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "set_aml_lock",
           "SELECT out_aml_program_lock_timeout"
           "  FROM exchange_do_set_aml_lock($1,$2,$3);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "set_aml_lock",
                                                 params,
                                                 rs);
  if (qs <= 0)
    return qs;
  if (nx)
  {
    *existing_lock = GNUNET_TIME_UNIT_ZERO_ABS;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  return qs;
}
