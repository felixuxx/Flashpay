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
 * @file exchangedb/pg_insert_contract.c
 * @brief Implementation of the insert_contract function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_contract.h"
#include "pg_select_contract_by_purse.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_contract (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_EncryptedContract *econtract,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (&econtract->contract_pub),
    GNUNET_PQ_query_param_fixed_size (econtract->econtract,
                                      econtract->econtract_size),
    GNUNET_PQ_query_param_auto_from_type (&econtract->econtract_sig),
    GNUNET_PQ_query_param_end
  };

  *in_conflict = false;
  /* Used in #postgres_insert_contract() */
  PREPARE (pg,
           "insert_contract",
           "INSERT INTO contracts"
           "  (purse_pub"
           "  ,pub_ckey"
           "  ,e_contract"
           "  ,contract_sig"
           "  ,purse_expiration"
           "  ) SELECT "
           "  $1, $2, $3, $4, purse_expiration"
           "  FROM purse_requests"
           "  WHERE purse_pub=$1"
           "  ON CONFLICT DO NOTHING;");
  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "insert_contract",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs)
    return qs;
  {
    struct TALER_EncryptedContract econtract2;

    qs = TEH_PG_select_contract_by_purse (pg,
                                          purse_pub,
                                          &econtract2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (0 == GNUNET_memcmp (&econtract->contract_pub,
                              &econtract2.contract_pub)) &&
         (econtract2.econtract_size ==
          econtract->econtract_size) &&
         (0 == memcmp (econtract2.econtract,
                       econtract->econtract,
                       econtract->econtract_size)) )
    {
      GNUNET_free (econtract2.econtract);
      return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    GNUNET_free (econtract2.econtract);
    *in_conflict = true;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
}
