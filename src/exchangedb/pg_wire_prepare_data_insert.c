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
 * @file exchangedb/pg_wire_prepare_data_insert.c
 * @brief Implementation of the wire_prepare_data_insert function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_wire_prepare_data_insert.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TEH_PG_wire_prepare_data_insert (void *cls,
                                   const char *type,
                                   const char *buf,
                                   size_t buf_size)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_fixed_size (buf, buf_size),
    GNUNET_PQ_query_param_end
  };


      /* Used in #postgres_wire_prepare_data_insert() to store
       wire transfer information before actually committing it with the bank */
  PREPARE (pg,
      "wire_prepare_data_insert",
      "INSERT INTO prewire "
      "(wire_method"
      ",buf"
      ") VALUES "
      "($1, $2);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_prepare_data_insert",
                                             params);
}
