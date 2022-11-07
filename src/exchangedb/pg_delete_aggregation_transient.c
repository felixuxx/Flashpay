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
 * @file exchangedb/pg_delete_aggregation_transient.c
 * @brief Implementation of the delete_aggregation_transient function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_delete_aggregation_transient.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_delete_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_WireTransferIdentifierRawP *wtid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "delete_aggregation_transient",
           "DELETE FROM aggregation_transient"
           " WHERE wire_target_h_payto=$1"
           "   AND wtid_raw=$2");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "delete_aggregation_transient",
                                             params);
}


