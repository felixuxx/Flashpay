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
 * @file exchangedb/pg_insert_partner.c
 * @brief Implementation of the insert_partner function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_partner.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_partner (void *cls,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct GNUNET_TIME_Timestamp start_date,
                         struct GNUNET_TIME_Timestamp end_date,
                         struct GNUNET_TIME_Relative wad_frequency,
                         const struct TALER_Amount *wad_fee,
                         const char *partner_base_url,
                         const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    GNUNET_PQ_query_param_relative_time (&wad_frequency),
    TALER_PQ_query_param_amount (wad_fee),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_string (partner_base_url),
    GNUNET_PQ_query_param_end
  };


  PREPARE (pg,
           "insert_partner",
           "INSERT INTO partners"
           "  (partner_master_pub"
           "  ,start_date"
           "  ,end_date"
           "  ,wad_frequency"
           "  ,wad_fee_val"
           "  ,wad_fee_frac"
           "  ,master_sig"
           "  ,partner_base_url"
           "  ) VALUES "
           "  ($1, $2, $3, $4, $5, $6, $7, $8);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_partner",
                                             params);
}


