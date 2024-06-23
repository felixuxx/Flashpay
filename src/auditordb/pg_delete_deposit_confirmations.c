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
 * @file auditordb/pg_delete_deposit_confirmations.c
 * @brief Implementation of the delete_deposit_confirmations function for Postgres
 * @author Nicola Eigel
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_delete_deposit_confirmations.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TAH_PG_delete_deposit_confirmation (
  void *cls,
  uint64_t row_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&row_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_delete_deposit_confirmation",
           "DELETE"
           " FROM auditor_deposit_confirmations"
           " WHERE deposit_confirmation_serial_id=$1;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_delete_deposit_confirmation",
                                             params);
}
