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
 * @file exchangedb/pg_insert_wire_fee.c
 * @brief Implementation of the insert_wire_fee function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_wire_fee.h"
#include "pg_helper.h"
#include "pg_get_wire_fee.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_wire_fee (void *cls,
                        const char *type,
                        struct GNUNET_TIME_Timestamp start_date,
                        struct GNUNET_TIME_Timestamp end_date,
                        const struct TALER_WireFeeSet *fees,
                        const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    TALER_PQ_query_param_amount (pg->conn,
                                 &fees->wire),
    TALER_PQ_query_param_amount (pg->conn,
                                 &fees->closing),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
  struct TALER_WireFeeSet wx;
  struct TALER_MasterSignatureP sig;
  struct GNUNET_TIME_Timestamp sd;
  struct GNUNET_TIME_Timestamp ed;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_PG_get_wire_fee (pg,
                            type,
                            start_date,
                            &sd,
                            &ed,
                            &wx,
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
        TALER_wire_fee_set_cmp (fees,
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
    /* equal record already exists */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  PREPARE (pg,
           "insert_wire_fee",
           "INSERT INTO wire_fee "
           "(wire_method"
           ",start_date"
           ",end_date"
           ",wire_fee"
           ",closing_fee"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_wire_fee",
                                             params);
}
