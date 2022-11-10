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
 * @file exchangedb/pg_do_purse_merge.c
 * @brief Implementation of the do_purse_merge function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_purse_merge.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_do_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const char *partner_url,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *no_partner,
  bool *no_balance,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  struct TALER_PaytoHashP h_payto;
  struct GNUNET_TIME_Timestamp expiration
    = GNUNET_TIME_relative_to_timestamp (pg->legal_reserve_expiration_time);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (merge_sig),
    GNUNET_PQ_query_param_timestamp (&merge_timestamp),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    (NULL == partner_url)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (partner_url),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&h_payto),
    GNUNET_PQ_query_param_timestamp (&expiration),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("no_partner",
                                no_partner),
    GNUNET_PQ_result_spec_bool ("no_balance",
                                no_balance),
    GNUNET_PQ_result_spec_bool ("conflict",
                                in_conflict),
    GNUNET_PQ_result_spec_end
  };

  {
    char *payto_uri;

    payto_uri = TALER_reserve_make_payto (pg->exchange_url,
                                          reserve_pub);
    TALER_payto_hash (payto_uri,
                      &h_payto);
    GNUNET_free (payto_uri);
  }
    /* Used in #postgres_do_purse_merge() */
  PREPARE (pg,
           "call_purse_merge",
           "SELECT"
           " out_no_partner AS no_partner"
           ",out_no_balance AS no_balance"
           ",out_conflict AS conflict"
           " FROM exchange_do_purse_merge"
           "  ($1, $2, $3, $4, $5, $6, $7, $8);");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_purse_merge",
                                                   params,
                                                   rs);
}
