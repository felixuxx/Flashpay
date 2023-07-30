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
 * @file exchangedb/pg_insert_global_fee.c
 * @brief Implementation of the insert_global_fee function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_global_fee.h"
#include "pg_helper.h"
#include "pg_get_global_fee.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_global_fee (void *cls,
                          struct GNUNET_TIME_Timestamp start_date,
                          struct GNUNET_TIME_Timestamp end_date,
                          const struct TALER_GlobalFeeSet *fees,
                          struct GNUNET_TIME_Relative purse_timeout,
                          struct GNUNET_TIME_Relative history_expiration,
                          uint32_t purse_account_limit,
                          const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    TALER_PQ_query_param_amount (pg->conn,
                                 &fees->history),
    TALER_PQ_query_param_amount (pg->conn,
                                 &fees->account),
    TALER_PQ_query_param_amount (pg->conn,
                                 &fees->purse),
    GNUNET_PQ_query_param_relative_time (&purse_timeout),
    GNUNET_PQ_query_param_relative_time (&history_expiration),
    GNUNET_PQ_query_param_uint32 (&purse_account_limit),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
  struct TALER_GlobalFeeSet wx;
  struct TALER_MasterSignatureP sig;
  struct GNUNET_TIME_Timestamp sd;
  struct GNUNET_TIME_Timestamp ed;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Relative pt;
  struct GNUNET_TIME_Relative he;
  uint32_t pal;

  qs = TEH_PG_get_global_fee (pg,
                              start_date,
                              &sd,
                              &ed,
                              &wx,
                              &pt,
                              &he,
                              &pal,
                              &sig);
  if (qs < 0)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    if (0 != GNUNET_memcmp (&sig,
                            master_sig))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (0 !=
        TALER_global_fee_set_cmp (fees,
                                  &wx))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_TIME_timestamp_cmp (sd,
                                     !=,
                                     start_date)) ||
         (GNUNET_TIME_timestamp_cmp (ed,
                                     !=,
                                     end_date)) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_TIME_relative_cmp (purse_timeout,
                                    !=,
                                    pt)) ||
         (GNUNET_TIME_relative_cmp (history_expiration,
                                    !=,
                                    he)) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (purse_account_limit != pal)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* equal record already exists */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  /* Used in #postgres_insert_global_fee */
  PREPARE (pg,
           "insert_global_fee",
           "INSERT INTO global_fee "
           "(start_date"
           ",end_date"
           ",history_fee"
           ",account_fee"
           ",purse_fee"
           ",purse_timeout"
           ",history_expiration"
           ",purse_account_limit"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_global_fee",
                                             params);
}
