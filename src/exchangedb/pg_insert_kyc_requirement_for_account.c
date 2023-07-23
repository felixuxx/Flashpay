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
 * @file exchangedb/pg_insert_kyc_requirement_for_account.c
 * @brief Implementation of the insert_kyc_requirement_for_account function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_kyc_requirement_for_account.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_requirement_for_account (
  void *cls,
  const char *provider_section,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *requirement_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    (NULL ==  reserve_pub)
      ? GNUNET_PQ_query_param_null ()
      : GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_string (provider_section),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("legitimization_requirement_serial_id",
                                  requirement_row),
    GNUNET_PQ_result_spec_end
  };
  /* Used in #postgres_insert_kyc_requirement_for_account() */
  PREPARE (pg,
           "insert_legitimization_requirement",
           "INSERT INTO legitimization_requirements"
           "  (h_payto"
           "   ,reserve_pub"
           "  ,required_checks"
           "  ) VALUES "
           "  ($1, $2, $3)"
           " ON CONFLICT (h_payto,required_checks) "
           "   DO UPDATE SET h_payto=$1" /* syntax requirement: dummy op */
           " RETURNING legitimization_requirement_serial_id");
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "insert_legitimization_requirement",
    params,
    rs);
}
