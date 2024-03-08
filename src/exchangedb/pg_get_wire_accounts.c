/*
   This file is part of TALER
   Copyright (C) 2022, 2024 Taler Systems SA

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
 * @file exchangedb/pg_get_wire_accounts.c
 * @brief Implementation of the get_wire_accounts function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_wire_accounts.h"
#include "pg_helper.h"


/**
 * Closure for #get_wire_accounts_cb().
 */
struct GetWireAccountsContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_WireAccountCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Flag set to #GNUNET_OK as long as everything is fine.
   */
  enum GNUNET_GenericReturnValue status;

};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_wire_accounts_cb (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct GetWireAccountsContext *ctx = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    char *payto_uri;
    char *conversion_url = NULL;
    json_t *debit_restrictions = NULL;
    json_t *credit_restrictions = NULL;
    struct TALER_MasterSignatureP master_sig;
    char *bank_label = NULL;
    int64_t priority;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("conversion_url",
                                      &conversion_url),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("bank_label",
                                      &bank_label),
        NULL),
      GNUNET_PQ_result_spec_int64 ("priority",
                                   &priority),
      GNUNET_PQ_result_spec_allow_null (
        TALER_PQ_result_spec_json ("debit_restrictions",
                                   &debit_restrictions),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        TALER_PQ_result_spec_json ("credit_restrictions",
                                   &credit_restrictions),
        NULL),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    if (NULL == debit_restrictions)
    {
      debit_restrictions = json_array ();
      GNUNET_assert (NULL != debit_restrictions);
    }
    if (NULL == credit_restrictions)
    {
      credit_restrictions = json_array ();
      GNUNET_assert (NULL != credit_restrictions);
    }
    ctx->cb (ctx->cb_cls,
             payto_uri,
             conversion_url,
             debit_restrictions,
             credit_restrictions,
             &master_sig,
             bank_label,
             priority);
    GNUNET_PQ_cleanup_result (rs);
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_wire_accounts (void *cls,
                          TALER_EXCHANGEDB_WireAccountCallback cb,
                          void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GetWireAccountsContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "get_wire_accounts",
           "SELECT"
           " payto_uri"
           ",conversion_url"
           ",debit_restrictions"
           ",credit_restrictions"
           ",master_sig"
           ",bank_label"
           ",priority"
           " FROM wire_accounts"
           " WHERE is_active");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "get_wire_accounts",
                                             params,
                                             &get_wire_accounts_cb,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
