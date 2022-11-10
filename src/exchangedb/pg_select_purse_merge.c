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
 * @file exchangedb/pg_select_purse_merge.c
 * @brief Implementation of the select_purse_merge function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_merge.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_PurseMergeSignatureP *merge_sig,
  struct GNUNET_TIME_Timestamp *merge_timestamp,
  char **partner_url,
  struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("merge_sig",
                                          merge_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          reserve_pub),
    GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                     merge_timestamp),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("partner_base_url",
                                    partner_url),
      &is_null),
    GNUNET_PQ_result_spec_end
  };

  *partner_url = NULL;
 /* Used in #postgres_select_purse_merge */
  PREPARE (pg,
           "select_purse_merge",
           "SELECT "
           " reserve_pub"
           ",merge_sig"
           ",merge_timestamp"
           ",partner_base_url"
           " FROM purse_merges"
           " LEFT JOIN partners USING (partner_serial_id)"
           " WHERE purse_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse_merge",
                                                   params,
                                                   rs);
}
