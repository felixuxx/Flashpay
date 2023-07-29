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
 * @file exchangedb/pg_get_global_fee.c
 * @brief Implementation of the get_global_fee function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_global_fee.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_get_global_fee (void *cls,
                       struct GNUNET_TIME_Timestamp date,
                       struct GNUNET_TIME_Timestamp *start_date,
                       struct GNUNET_TIME_Timestamp *end_date,
                       struct TALER_GlobalFeeSet *fees,
                       struct GNUNET_TIME_Relative *purse_timeout,
                       struct GNUNET_TIME_Relative *history_expiration,
                       uint32_t *purse_account_limit,
                       struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("start_date",
                                     start_date),
    GNUNET_PQ_result_spec_timestamp ("end_date",
                                     end_date),
    TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                 &fees->history),
    TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                 &fees->account),
    TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                 &fees->purse),
    GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                         purse_timeout),
    GNUNET_PQ_result_spec_relative_time ("history_expiration",
                                         history_expiration),
    GNUNET_PQ_result_spec_uint32 ("purse_account_limit",
                                  purse_account_limit),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "get_global_fee",
           "SELECT "
           " start_date"
           ",end_date"
           ",history_fee"
           ",account_fee"
           ",purse_fee"
           ",purse_timeout"
           ",history_expiration"
           ",purse_account_limit"
           ",master_sig"
           " FROM global_fee"
           " WHERE start_date <= $1"
           "   AND end_date > $1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_global_fee",
                                                   params,
                                                   rs);
}
