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
 * @file pg_iterate_kyc_reference.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_kyc_reference.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_iterate_kyc_reference (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_LegitimizationProcessCallback lpc,
  void *lpc_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  // FIXME: everything from here is copy*paste
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("insufficient_funds",
                                insufficient_funds),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "iterate_kyc_reference",
           "SELECT "
           " insufficient_funds"
           " FROM exchange_do_reserve_open_deposit"
           " ($1,$2,$3,$4,$5,$6);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "iterate_kyc_reference",
                                                   params,
                                                   rs);
}
