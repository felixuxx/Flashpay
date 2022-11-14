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
 * @file exchangedb/pg_expire_purse.c
 * @brief Implementation of the expire_purse function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_expire_purse.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_expire_purse (
  void *cls,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Absolute end_time)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&start_time),
    GNUNET_PQ_query_param_absolute_time (&end_time),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  bool found = false;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("found",
                                &found),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;


  PREPARE (pg,
           "call_expire_purse",
           "SELECT "
           " out_found AS found"
           " FROM exchange_do_expire_purse"
           " ($1,$2,$3);");

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "call_expire_purse",
                                                 params,
                                                 rs);
  if (qs < 0)
    return qs;
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  return found
         ? GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
         : GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}
