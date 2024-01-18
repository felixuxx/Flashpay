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
 * @file auditordb/pg_delete_purse_info.c
 * @brief Implementation of the delete_purse_info function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_delete_purse_info.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TAH_PG_delete_purse_info (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_purses_delete",
           "DELETE FROM auditor_purses "
           " WHERE purse_pub=$1");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_purses_delete",
                                             params);
}
