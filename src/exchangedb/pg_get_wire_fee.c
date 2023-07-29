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
 * @file exchangedb/pg_get_wire_fee.c
 * @brief Implementation of the get_wire_fee function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_fee.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_wire_fee (void *cls,
                     const char *type,
                     struct GNUNET_TIME_Timestamp date,
                     struct GNUNET_TIME_Timestamp *start_date,
                     struct GNUNET_TIME_Timestamp *end_date,
                     struct TALER_WireFeeSet *fees,
                     struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("start_date",
                                     start_date),
    GNUNET_PQ_result_spec_timestamp ("end_date",
                                     end_date),
    TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                 &fees->wire),
    TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                 &fees->closing),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "get_wire_fee",
           "SELECT "
           " start_date"
           ",end_date"
           ",wire_fee"
           ",closing_fee"
           ",master_sig"
           " FROM wire_fee"
           " WHERE wire_method=$1"
           "   AND start_date <= $2"
           "   AND end_date > $2;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_wire_fee",
                                                   params,
                                                   rs);
}
