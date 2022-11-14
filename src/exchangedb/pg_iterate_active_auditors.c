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
 * @file exchangedb/pg_iterate_active_auditors.c
 * @brief Implementation of the iterate_active_auditors function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_active_auditors.h"
#include "pg_helper.h"


/**
 * Closure for #auditors_cb_helper()
 */
struct AuditorsIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_AuditorsCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

};


/**
 * Helper function for #postgres_iterate_active_auditors().
 * Calls the callback with each auditor.
 *
 * @param cls a `struct SignkeysIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
auditors_cb_helper (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct AuditorsIteratorContext *dic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_AuditorPublicKeyP auditor_pub;
    char *auditor_url;
    char *auditor_name;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("auditor_pub",
                                            &auditor_pub),
      GNUNET_PQ_result_spec_string ("auditor_url",
                                    &auditor_url),
      GNUNET_PQ_result_spec_string ("auditor_name",
                                    &auditor_name),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    dic->cb (dic->cb_cls,
             &auditor_pub,
             auditor_url,
             auditor_name);
    GNUNET_PQ_cleanup_result (rs);
  }
}



enum GNUNET_DB_QueryStatus
TEH_PG_iterate_active_auditors (void *cls,
                                  TALER_EXCHANGEDB_AuditorsCallback cb,
                                  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct AuditorsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };
    /* Used in #postgres_iterate_active_auditors() */
  PREPARE (pg,
           "select_auditors",
           "SELECT"
           " auditor_pub"
           ",auditor_url"
           ",auditor_name"
           " FROM auditors"
           " WHERE"
           "   is_active;");

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "select_auditors",
                                               params,
                                               &auditors_cb_helper,
                                               &dic);
}
