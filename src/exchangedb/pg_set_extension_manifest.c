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
 * @file exchangedb/pg_set_extension_manifest.c
 * @brief Implementation of the set_extension_manifest function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_set_extension_manifest.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_set_extension_manifest (void *cls,
                                 const char *extension_name,
                                 const char *manifest)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam pcfg =
    (NULL == manifest || 0 == *manifest)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (manifest);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (extension_name),
    pcfg,
    GNUNET_PQ_query_param_end
  };


  PREPARE (pg,
           "set_extension_manifest",
           "INSERT INTO extensions (name, manifest) VALUES ($1, $2) "
           "ON CONFLICT (name) "
           "DO UPDATE SET manifest=$2");


  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "set_extension_manifest",
                                             params);
}
