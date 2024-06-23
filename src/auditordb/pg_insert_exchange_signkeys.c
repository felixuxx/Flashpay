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


#include "platform.h"
#include "taler_pq_lib.h"
#include "pg_helper.h"

#include "pg_insert_exchange_signkeys.h"

enum GNUNET_DB_QueryStatus
TAH_PG_insert_exchange_signkeys (
  void *cls,
  const struct TALER_AUDITORDB_ExchangeSignkeys *dc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {

    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&dc->master_sig),
    GNUNET_PQ_query_param_absolute_time (&dc->ep_valid_from),
    GNUNET_PQ_query_param_absolute_time (&dc->ep_expire_sign),
    GNUNET_PQ_query_param_absolute_time (&dc->ep_expire_legal),


    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "auditor_exchange_signkeys_insert",
           "INSERT INTO auditor_exchange_signkeys "
           "( exchange_pub,"
           " master_sig,"
           " ep_valid_from,"
           " ep_expire_sign,"
           " ep_expire_legal"
           ") VALUES ($1,$2,$3,$4,$5);"
           );
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "auditor_exchange_signkeys_insert",
                                             params);
}
