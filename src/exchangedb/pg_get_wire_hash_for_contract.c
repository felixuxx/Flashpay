/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_get_wire_hash_for_contract.c
 * @brief Implementation of the get_wire_hash_for_contract function for Postgres
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_exchangedb_plugin.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_hash_for_contract.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_wire_hash_for_contract (
  void *cls,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct TALER_MerchantWireHashP *h_wire)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_end
  };
  char *payto_uri;
  struct TALER_WireSaltP wire_salt;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                          &wire_salt),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  &payto_uri),
    GNUNET_PQ_result_spec_end
  };

  /* check if the necessary records exist and get them */
  PREPARE (pg,
           "get_wire_hash_for_contract",
           "SELECT"
           " bdep.wire_salt"
           ",wt.payto_uri"
           " FROM coin_deposits"
           "    JOIN batch_deposits bdep"
           "      USING (batch_deposit_serial_id)"
           "    JOIN wire_targets wt"
           "      USING (wire_target_h_payto)"
           " WHERE bdep.merchant_pub=$1"
           "   AND bdep.h_contract_terms=$2");
  /* NOTE: above query might be more efficient if we computed the shard
     from the merchant_pub and included that in the query */
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_wire_hash_for_contract",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    TALER_merchant_wire_signature_hash (payto_uri,
                                        &wire_salt,
                                        h_wire);
    GNUNET_PQ_cleanup_result (rs);
  }
  return qs;
}
