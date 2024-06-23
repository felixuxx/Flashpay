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

#include "pg_insert_bad_sig_losses.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_bad_sig_losses (
  void *cls,
  const struct TALER_AUDITORDB_BadSigLosses *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {

    GNUNET_PQ_query_param_string (dc->operation),
    TALER_PQ_query_param_amount (pg->conn, &dc->loss),
    GNUNET_PQ_query_param_auto_from_type (&dc->operation_specific_pub),

    GNUNET_PQ_query_param_end
  };
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "--storing new bsl\n");
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "--operation %s\n", dc->operation);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "--loss %s\n", TALER_amount_to_string (
                &dc->loss));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO, "--operation_specific_pub %s\n",
              TALER_B2S (&dc->operation_specific_pub));

  PREPARE (pg,
           "auditor_bad_sig_losses_insert",
           "INSERT INTO auditor_bad_sig_losses "
           "(operation"
           ",loss"
           ",operation_specific_pub"
           ") VALUES ($1,$2,$3)"
           " ON CONFLICT (operation, operation_specific_pub) DO UPDATE"
           " SET loss = excluded.loss,"
           " suppressed = false;"
           );
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_bad_sig_losses_insert",
                                             params);
}
