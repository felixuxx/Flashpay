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
 * @file exchangedb/pg_get_extension_manifest.c
 * @brief Implementation of the get_extension_manifest function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_extension_manifest.h"
#include "pg_helper.h"

/**
 * Function called to get the manifest of an extension
 * (age-restriction, policy_extension_...)
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param extension_name the name of the extension
 * @param[out] manifest JSON object of the manifest as string
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_extension_manifest (void *cls,
                               const char *extension_name,
                               char **manifest)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (extension_name),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("manifest",
                                    manifest),
      &is_null),
    GNUNET_PQ_result_spec_end
  };

  *manifest = NULL;
  /* Used in #postgres_get_extension_manifest */
  PREPARE (pg,
           "get_extension_manifest",
           "SELECT "
           " manifest "
           "FROM extensions"
           "   WHERE name=$1;");
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_extension_manifest",
                                                   params,
                                                   rs);
}
