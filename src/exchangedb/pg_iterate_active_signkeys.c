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
 * @file exchangedb/pg_iterate_active_signkeys.c
 * @brief Implementation of the iterate_active_signkeys function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_iterate_active_signkeys.h"
#include "pg_helper.h"


/**
 * Closure for #signkeys_cb_helper()
 */
struct SignkeysIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_ActiveSignkeysCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

};


/**
 * Helper function for #TEH_PG_iterate_active_signkeys().
 * Calls the callback with each signkey.
 *
 * @param cls a `struct SignkeysIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
signkeys_cb_helper (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct SignkeysIteratorContext *dic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_SignkeyMetaData meta;
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_pub",
                                            &exchange_pub),
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &meta.start),
      GNUNET_PQ_result_spec_timestamp ("expire_sign",
                                       &meta.expire_sign),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                       &meta.expire_legal),
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
             &exchange_pub,
             &meta,
             &master_sig);
  }
}


/**
 * Function called to invoke @a cb on every non-revoked exchange signing key
 * that has been signed by the master key.  Revoked and (for signing!)
 * expired keys are skipped. Runs in its own read-only transaction.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each signing key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_iterate_active_signkeys (void *cls,
                                TALER_EXCHANGEDB_ActiveSignkeysCallback cb,
                                void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct SignkeysIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };

  PREPARE (pg,
           "select_signkeys",
           "SELECT"
           " master_sig"
           ",exchange_pub"
           ",valid_from"
           ",expire_sign"
           ",expire_legal"
           " FROM exchange_sign_keys esk"
           " WHERE"
           "   expire_sign > $1"
           " AND NOT EXISTS "
           "  (SELECT esk_serial "
           "     FROM signkey_revocations skr"
           "    WHERE esk.esk_serial = skr.esk_serial);");
  now = GNUNET_TIME_absolute_get ();
  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "select_signkeys",
                                               params,
                                               &signkeys_cb_helper,
                                               &dic);
}
