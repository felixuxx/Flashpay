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
 * @file exchangedb/pg_lookup_kyc_requirement_by_row.c
 * @brief Implementation of the lookup_kyc_requirement_by_row function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_kyc_requirement_by_row.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_requirement_by_row (
  void *cls,
  uint64_t requirement_row,
  char **requirements,
  struct TALER_PaytoHashP *h_payto)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&requirement_row),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("required_checks",
                                  requirements),
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_end
  };
/* Used in #postgres_lookup_kyc_requirement_by_row() */
  PREPARE (pg,
           "lookup_legitimization_requirement_by_row",
           "SELECT "
           " required_checks"
           ",h_payto"
           " FROM legitimization_requirements"
           " WHERE legitimization_requirement_serial_id=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_legitimization_requirement_by_row",
    params,
    rs);
}
