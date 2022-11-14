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
 * @file exchangedb/pg_insert_auditor_denom_sig.c
 * @brief Implementation of the insert_auditor_denom_sig function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_auditor_denom_sig.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_auditor_denom_sig (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_auto_from_type (auditor_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_auditor_denom_sig",
           "WITH ax AS"
           " (SELECT auditor_uuid"
           "    FROM auditors"
           "   WHERE auditor_pub=$1)"
           "INSERT INTO auditor_denom_sigs "
           "(auditor_uuid"
           ",denominations_serial"
           ",auditor_sig"
           ") SELECT ax.auditor_uuid, denominations_serial, $3 "
           "    FROM denominations"
           "   CROSS JOIN ax"
           "   WHERE denom_pub_hash=$2;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_auditor_denom_sig",
                                             params);
}
