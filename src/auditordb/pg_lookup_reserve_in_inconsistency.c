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
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_helper.h"
#include "pg_lookup_reserve_in_inconsistency.h"


enum GNUNET_DB_QueryStatus
TAH_PG_lookup_reserve_in_inconsistency (
  void *cls,
  uint64_t bank_row_id,
  struct TALER_AUDITORDB_ReserveInInconsistency *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&bank_row_id),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("row_id",
                                  &dc->serial_id),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_exchange_expected",
                                 &dc->amount_exchange_expected),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_wired",
                                 &dc->amount_wired),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          &dc->reserve_pub),
    GNUNET_PQ_result_spec_absolute_time ("timestamp",
                                         &dc->timestamp),
    GNUNET_PQ_result_spec_string ("account",
                                  &dc->account.full_payto),
    GNUNET_PQ_result_spec_string ("diagnostic",
                                  &dc->diagnostic),
    GNUNET_PQ_result_spec_bool ("suppressed",
                                &dc->suppressed),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "auditor_lookup_reserve_in_inconsistency",
           "SELECT"
           " row_id"
           ",amount_exchange_expected"
           ",amount_wired"
           ",reserve_pub"
           ",timestamp"
           ",account"
           ",diagnostic"
           ",suppressed"
           " FROM auditor_reserve_in_inconsistency"
           " WHERE (bank_row_id = $1)"
           );
  dc->bank_row_id = bank_row_id;
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "auditor_lookup_reserve_in_inconsistency",
    params,
    rs);
}
