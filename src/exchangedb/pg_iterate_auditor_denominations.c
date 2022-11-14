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
 * @file exchangedb/pg_iterate_auditor_denominations.c
 * @brief Implementation of the iterate_auditor_denominations function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_auditor_denominations.h"
#include "pg_helper.h"

/**
 * Closure for #auditor_denoms_cb_helper()
 */
struct AuditorDenomsIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_AuditorDenominationsCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;
};


/**
 * Helper function for #postgres_iterate_auditor_denominations().
 * Calls the callback with each auditor and denomination pair.
 *
 * @param cls a `struct AuditorDenomsIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
auditor_denoms_cb_helper (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct AuditorDenomsIteratorContext *dic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_AuditorPublicKeyP auditor_pub;
    struct TALER_DenominationHashP h_denom_pub;
    struct TALER_AuditorSignatureP auditor_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("auditor_pub",
                                            &auditor_pub),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &h_denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("auditor_sig",
                                            &auditor_sig),
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
             &h_denom_pub,
             &auditor_sig);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_iterate_auditor_denominations (
  void *cls,
  TALER_EXCHANGEDB_AuditorDenominationsCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct AuditorDenomsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };
    /* Used in #postgres_iterate_auditor_denominations() */
  PREPARE (pg,
           "select_auditor_denoms",
           "SELECT"
           " auditors.auditor_pub"
           ",denominations.denom_pub_hash"
           ",auditor_denom_sigs.auditor_sig"
           " FROM auditor_denom_sigs"
           " JOIN auditors USING (auditor_uuid)"
           " JOIN denominations USING (denominations_serial)"
           " WHERE auditors.is_active;");
    return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "select_auditor_denoms",
                                               params,
                                               &auditor_denoms_cb_helper,
                                               &dic);
}
