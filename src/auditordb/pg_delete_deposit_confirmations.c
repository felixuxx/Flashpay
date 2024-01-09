/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file auditordb/pg_delete_deposit_confirmations.c
 * @brief Implementation of the delete_deposit_confirmations function for Postgres
 * @author Nicola Eigel
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_delete_deposit_confirmations.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TAH_PG_delete_deposit_confirmations (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (exchange_sig),
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_delete_deposit_confirmations",
           "DELETE"
           " FROM deposit_confirmations"
           " WHERE h_contract_terms=$1"
           "   AND h_wire=$2"
           "   AND merchant_pub=$3"
           "   AND exchange_sig=$4"
           "   AND exchange_pub=$5"
           "   AND master_sig=$6;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_delete_deposit_confirmations",
                                             params);
}
