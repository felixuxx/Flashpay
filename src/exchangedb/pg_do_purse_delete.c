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
 * @file exchangedb/pg_do_purse_delete.c
 * @brief Implementation of the do_purse_delete function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_purse_delete.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_purse_delete (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig,
  bool *decided,
  bool *found)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp now = GNUNET_TIME_timestamp_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (purse_sig),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("decided",
                                decided),
    GNUNET_PQ_result_spec_bool ("found",
                                found),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "call_purse_delete",
           "SELECT "
           " out_decided AS decided"
           ",out_found AS found"
           " FROM exchange_do_purse_delete"
           " ($1,$2,$3);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_purse_delete",
                                                   params,
                                                   rs);
}
