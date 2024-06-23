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

#include "pg_update_purse_not_closed_inconsistencies.h"

/*
Update a given resource – for now this only means suppressing
*/
enum GNUNET_DB_QueryStatus
TAH_PG_update_purse_not_closed_inconsistencies (
  void *cls,
  const struct TALER_AUDITORDB_Generic_Update *gu)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&gu->row_id),
    GNUNET_PQ_query_param_bool (gu->suppressed),
    GNUNET_PQ_query_param_end
  };


  PREPARE (pg,
           "update_purse_not_closed_inconsistencies",
           "UPDATE auditor_purse_not_closed_inconsistencies SET"
           " suppressed=$2"
           " WHERE row_id=$1");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "update_purse_not_closed_inconsistencies",
                                             params);
}
