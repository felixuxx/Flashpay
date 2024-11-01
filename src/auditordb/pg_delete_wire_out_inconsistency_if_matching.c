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
#include "taler_pq_lib.h"
#include "pg_helper.h"
#include "pg_delete_wire_out_inconsistency_if_matching.h"


enum GNUNET_DB_QueryStatus
TAH_PG_delete_wire_out_inconsistency_if_matching (
  void *cls,
  const struct TALER_AUDITORDB_WireOutInconsistency *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (dc->destination_account.full_payto),
    GNUNET_PQ_query_param_string (dc->diagnostic),
    GNUNET_PQ_query_param_uint64 (&dc->wire_out_row_id),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dc->expected),
    TALER_PQ_query_param_amount (pg->conn,
                                 &dc->claimed),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_wire_out_inconsistency_delete_if_matching",
           "DELETE FROM auditor_wire_out_inconsistency "
           " WHERE destination_account=$1"
           "   AND diagnostic=$2"
           "   AND wire_out_serial_id=$3"
           "   AND (expected).val=($4::taler_amount).val"
           "   AND (expected).frac=($4::taler_amount).frac"
           "   AND (claimed).val=($5::taler_amount).val"
           "   AND (claimed).frac=($5::taler_amount).frac;"
           );
  return GNUNET_PQ_eval_prepared_non_select (
    pg->conn,
    "auditor_wire_out_inconsistency_delete_if_matching",
    params);
}
