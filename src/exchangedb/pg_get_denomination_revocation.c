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
 * @file exchangedb/pg_get_denomination_revocation.c
 * @brief Implementation of the get_denomination_revocation function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_denomination_revocation.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_get_denomination_revocation (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_MasterSignatureP *master_sig,
  uint64_t *rowid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_uint64 ("denom_revocations_serial_id",
                                  rowid),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "denomination_revocation_get",
           "SELECT"
           " master_sig"
           ",denom_revocations_serial_id"
           " FROM denomination_revocations"
           " WHERE denominations_serial="
           "  (SELECT denominations_serial"
           "    FROM denominations"
           "    WHERE denom_pub_hash=$1);");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "denomination_revocation_get",
                                                   params,
                                                   rs);
}
