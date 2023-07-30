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
 * @file exchangedb/pg_add_denomination_key.c
 * @brief Implementation of the add_denomination_key function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_add_denomination_key.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_add_denomination_key (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    TALER_PQ_query_param_denom_pub (denom_pub),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_timestamp (&meta->start),
    GNUNET_PQ_query_param_timestamp (&meta->expire_withdraw),
    GNUNET_PQ_query_param_timestamp (&meta->expire_deposit),
    GNUNET_PQ_query_param_timestamp (&meta->expire_legal),
    TALER_PQ_query_param_amount (pg->conn,
                                 &meta->value),
    TALER_PQ_query_param_amount (pg->conn,
                                 &meta->fees.withdraw),
    TALER_PQ_query_param_amount (pg->conn,
                                 &meta->fees.deposit),
    TALER_PQ_query_param_amount (pg->conn,
                                 &meta->fees.refresh),
    TALER_PQ_query_param_amount (pg->conn,
                                 &meta->fees.refund),
    GNUNET_PQ_query_param_uint32 (&meta->age_mask.bits),
    GNUNET_PQ_query_param_end
  };

  /* Sanity check: ensure fees match coin currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_denom_fee_check_currency (meta->value.currency,
                                                 &meta->fees));
  PREPARE (pg,
           "denomination_insert",
           "INSERT INTO denominations "
           "(denom_pub_hash"
           ",denom_pub"
           ",master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin"     /* value of this denom */
           ",fee_withdraw"
           ",fee_deposit"
           ",fee_refresh"
           ",fee_refund"
           ",age_mask"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "denomination_insert",
                                             iparams);
}
