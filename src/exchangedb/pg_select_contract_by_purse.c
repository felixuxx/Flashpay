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
 * @file exchangedb/pg_select_contract_by_purse.c
 * @brief Implementation of the select_contract_by_purse function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_contract_by_purse.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_select_contract_by_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_EncryptedContract *econtract)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("pub_ckey",
                                          &econtract->contract_pub),
    GNUNET_PQ_result_spec_auto_from_type ("contract_sig",
                                          &econtract->econtract_sig),
    GNUNET_PQ_result_spec_variable_size ("e_contract",
                                         &econtract->econtract,
                                         &econtract->econtract_size),
    GNUNET_PQ_result_spec_end
  };
 /* Used in #postgres_select_contract_by_purse */
  PREPARE (pg,
           "select_contract_by_purse",
           "SELECT "
           " pub_ckey"
           ",e_contract"
           ",contract_sig"
           " FROM contracts"
           "   WHERE purse_pub=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_contract_by_purse",
                                                   params,
                                                   rs);

}
