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
 * @file exchangedb/pg_drain_kyc_alert.c
 * @brief Implementation of the drain_kyc_alert function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_drain_kyc_alert.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_drain_kyc_alert (void *cls,
                        uint32_t trigger_type,
                        struct TALER_PaytoHashP *h_payto)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&trigger_type),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "drain_kyc_alert",
           "DELETE FROM kyc_alerts"
           " WHERE trigger_type=$1"
           "   AND h_payto = "
           "   (SELECT h_payto "
           "      FROM kyc_alerts"
           "     WHERE trigger_type=$1"
           "     LIMIT 1)"
           " RETURNING h_payto;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "drain_kyc_alert",
                                                   params,
                                                   rs);
}
