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
 * @file exchangedb/pg_do_batch_withdraw_insert.c
 * @brief Implementation of the do_batch_withdraw_insert function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_do_batch_withdraw_insert.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_do_batch_withdraw_insert (
  void *cls,
  const struct TALER_CsNonce *nonce,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
  struct GNUNET_TIME_Timestamp now,
  uint64_t ruuid,
  bool *denom_unknown,
  bool *conflict,
  bool *nonce_reuse)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == nonce
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (nonce),
    TALER_PQ_query_param_amount (pg->conn,
                                 &collectable->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&collectable->denom_pub_hash),
    GNUNET_PQ_query_param_uint64 (&ruuid),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    TALER_PQ_query_param_blinded_denom_sig (&collectable->sig),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("denom_unknown",
                                denom_unknown),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_bool ("nonce_reuse",
                                nonce_reuse),
    GNUNET_PQ_result_spec_end
  };
  /* Used in #postgres_do_batch_withdraw_insert() to store
        the signature of a blinded coin with the blinded coin's
        details. */
  PREPARE (pg,
           "call_batch_withdraw_insert",
           "SELECT "
           " out_denom_unknown AS denom_unknown"
           ",out_conflict AS conflict"
           ",out_nonce_reuse AS nonce_reuse"
           " FROM exchange_do_batch_withdraw_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8);");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_batch_withdraw_insert",
                                                   params,
                                                   rs);
}
