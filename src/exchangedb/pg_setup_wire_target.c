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
 * @file exchangedb/pg_setup_wire_target.c
 * @brief Implementation of the setup_wire_target function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_setup_wire_target.h"


enum GNUNET_DB_QueryStatus
TEH_PG_setup_wire_target (
  struct PostgresClosure *pg,
  const char *payto_uri,
  struct TALER_PaytoHashP *h_payto)
{
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_end
  };

  TALER_payto_hash (payto_uri,
                    h_payto);

  PREPARE (pg,
           "insert_kyc_status",
           "INSERT INTO wire_targets"
           "  (wire_target_h_payto"
           "  ,payto_uri"
           "  ) VALUES "
           "  ($1, $2)"
           " ON CONFLICT DO NOTHING");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_kyc_status",
                                             iparams);
}
