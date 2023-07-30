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
 * @file auditordb/pg_insert_purse_info.c
 * @brief Implementation of the insert_purse_info function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_purse_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_insert_purse_info (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *balance,
  struct GNUNET_TIME_Timestamp expiration_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (pg->conn,
                                 balance),
    GNUNET_PQ_query_param_timestamp (&expiration_date),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_purses_insert",
           "INSERT INTO auditor_purses "
           "(purse_pub"
           ",master_pub"
           ",target"
           ",expiration_date"
           ") VALUES ($1,$2,$3,$4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_purses_insert",
                                             params);
}
