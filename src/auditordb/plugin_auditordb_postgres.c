/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file plugin_auditordb_postgres.c
 * @brief Low-level (statement-level) Postgres database access for the auditor
 * @author Christian Grothoff
 * @author Gabor X Toth
 */
#include "platform.h"
#include "taler_pq_lib.h"
#include <pthread.h>
#include <libpq-fe.h>
#include "pg_helper.h"
#include "pg_insert_auditor_progress_reserve.h"
#include "pg_update_auditor_progress_reserve.h"
#include "pg_get_auditor_progress_reserve.h"
#include "pg_insert_auditor_progress_purse.h"
#include "pg_update_auditor_progress_purse.h"
#include "pg_get_auditor_progress_purse.h"
#include "pg_insert_auditor_progress_aggregation.h"
#include "pg_update_auditor_progress_aggregation.h"
#include "pg_get_auditor_progress_aggregation.h"
#include "pg_insert_auditor_progress_deposit_confirmation.h"
#include "pg_update_auditor_progress_deposit_confirmation.h"
#include "pg_get_auditor_progress_deposit_confirmation.h"
#include "pg_select_pending_deposits.h"
#include "pg_delete_pending_deposit.h"
#include "pg_insert_pending_deposit.h"
#include "pg_insert_auditor_progress_coin.h"
#include "pg_update_auditor_progress_coin.h"
#include "pg_get_auditor_progress_coin.h"
#include "pg_insert_wire_auditor_account_progress.h"
#include "pg_update_wire_auditor_account_progress.h"
#include "pg_get_wire_auditor_account_progress.h"
#include "pg_insert_wire_auditor_progress.h"
#include "pg_update_wire_auditor_progress.h"
#include "pg_get_wire_auditor_progress.h"
#include "pg_insert_reserve_info.h"
#include "pg_update_reserve_info.h"
#include "pg_del_reserve_info.h"
#include "pg_get_reserve_info.h"
#include "pg_insert_reserve_summary.h"
#include "pg_update_reserve_summary.h"
#include "pg_get_reserve_summary.h"
#include "pg_insert_wire_fee_summary.h"
#include "pg_update_wire_fee_summary.h"
#include "pg_get_wire_fee_summary.h"
#include "pg_insert_denomination_balance.h"
#include "pg_update_denomination_balance.h"
#include "pg_get_denomination_balance.h"
#include "pg_insert_balance_summary.h"
#include "pg_update_balance_summary.h"
#include "pg_get_balance_summary.h"
#include "pg_insert_historic_denom_revenue.h"
#include "pg_select_historic_denom_revenue.h"
#include "pg_insert_historic_reserve_revenue.h"
#include "pg_select_historic_reserve_revenue.h"
#include "pg_insert_predicted_result.h"
#include "pg_update_predicted_result.h"
#include "pg_get_predicted_balance.h"
#include "pg_insert_exchange.h"
#include "pg_list_exchanges.h"
#include "pg_delete_exchange.h"
#include "pg_insert_exchange_signkey.h"
#include "pg_insert_deposit_confirmation.h"
#include "pg_get_deposit_confirmations.h"
#include "pg_insert_auditor_progress_coin.h"
#include "pg_update_auditor_progress_coin.h"
#include "pg_get_auditor_progress_coin.h"
#include "pg_insert_auditor_progress_purse.h"
#include "pg_update_auditor_progress_purse.h"
#include "pg_get_auditor_progress_purse.h"
#include "pg_get_reserve_info.h"
#include "pg_insert_historic_reserve_revenue.h"
#include "pg_insert_wire_auditor_progress.h"
#include "pg_update_wire_auditor_progress.h"
#include "pg_get_wire_auditor_progress.h"
#include "pg_insert_historic_reserve_revenue.h"
#include "pg_helper.h"
#include "pg_get_purse_info.h"
#include "pg_delete_purse_info.h"
#include "pg_update_purse_info.h"
#include "pg_insert_purse_info.h"
#include "pg_get_purse_summary.h"
#include "pg_select_purse_expired.h"
#include "pg_insert_purse_summary.h"
#include "pg_update_purse_summary.h"

#define LOG(kind,...) GNUNET_log_from (kind, "taler-auditordb-postgres", \
                                       __VA_ARGS__)


/**
 * Drop all auditor tables OR deletes recoverable auditor state.
 * This should only be used by testcases or when restarting the
 * auditor from scratch.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param drop_exchangelist drop all tables, including schema versioning
 *        and the exchange and deposit_confirmations table; NOT to be
 *        used when restarting the auditor
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_drop_tables (void *cls,
                      bool drop_exchangelist)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "auditordb-postgres",
                                     NULL,
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_sql (conn,
                            (drop_exchangelist) ? "drop" : "restart");
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/**
 * Create the necessary tables if they are not present
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_create_tables (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_Context *conn;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "auditordb-postgres",
                                     "auditor-",
                                     es,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return GNUNET_OK;
}


/**
 * Connect to the db if the connection does not exist yet.
 *
 * @param[in,out] pg the plugin-specific state
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
setup_connection (struct PostgresClosure *pg)
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  struct GNUNET_PQ_Context *db_conn;

  if (NULL != pg->conn)
  {
    GNUNET_PQ_reconnect_if_down (pg->conn);
    return GNUNET_OK;
  }
  db_conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                        "auditordb-postgres",
                                        NULL,
                                        es,
                                        NULL);
  if (NULL == db_conn)
    return GNUNET_SYSERR;
  pg->conn = db_conn;
  pg->prep_gen++;
  return GNUNET_OK;
}


/**
 * Do a pre-flight check that we are not in an uncommitted transaction.
 * If we are, rollback the previous transaction and output a warning.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if we rolled back an earlier transaction
 *         #GNUNET_SYSERR if we have no DB connection
 */
static enum GNUNET_GenericReturnValue
postgres_preflight (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (NULL == pg->conn)
  {
    if (GNUNET_OK !=
        setup_connection (pg))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  if (NULL == pg->transaction_name)
    return GNUNET_OK; /* all good */
  if (GNUNET_OK ==
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check rolled back transaction `%s'!\n",
                pg->transaction_name);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check failed to rollback transaction `%s'!\n",
                pg->transaction_name);
  }
  pg->transaction_name = NULL;
  return GNUNET_NO;
}


/**
 * Start a transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
postgres_start (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("START TRANSACTION ISOLATION LEVEL SERIALIZABLE"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  postgres_preflight (cls);
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR ("Failed to start transaction\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 */
static void
postgres_rollback (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  GNUNET_break (GNUNET_OK ==
                GNUNET_PQ_exec_statements (pg->conn,
                                           es));
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_commit (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "do_commit",
           "COMMIT");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "do_commit",
                                             params);
}


/**
 * Function called to perform "garbage collection" on the
 * database, expiring records we no longer require.
 *
 * @param cls closure
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static enum GNUNET_GenericReturnValue
postgres_gc (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params_time[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_PreparedStatement ps[] = {
#if 0
    GNUNET_PQ_make_prepare ("gc_auditor",
                            "TODO: #4960",
                            0),
#endif
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  now = GNUNET_TIME_absolute_get ();
  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "auditordb-postgres",
                                     NULL,
                                     es,
                                     ps);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "TODO: Auditor GC not implemented (#4960)\n");
  qs = GNUNET_PQ_eval_prepared_non_select (conn,
                                           "gc_auditor",
                                           params_time);
  GNUNET_PQ_disconnect (conn);
  if (0 > qs)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_AUDITORDB_Plugin`
 */
void *
libtaler_plugin_auditordb_postgres_init (void *cls)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_AUDITORDB_Plugin *plugin;

  pg = GNUNET_new (struct PostgresClosure);
  pg->cfg = cfg;
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &pg->currency))
  {
    GNUNET_free (pg);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_AUDITORDB_Plugin);
  plugin->cls = pg;
  plugin->preflight = &postgres_preflight;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->rollback = &postgres_rollback;
  plugin->gc = &postgres_gc;

  plugin->insert_exchange
    = &TAH_PG_insert_exchange;
  plugin->delete_exchange
    = &TAH_PG_delete_exchange;
  plugin->list_exchanges
    = &TAH_PG_list_exchanges;

  plugin->insert_exchange_signkey
    = &TAH_PG_insert_exchange_signkey;
  plugin->insert_deposit_confirmation
    = &TAH_PG_insert_deposit_confirmation;
  plugin->get_deposit_confirmations
    = &TAH_PG_get_deposit_confirmations;

  plugin->get_auditor_progress_reserve
    = &TAH_PG_get_auditor_progress_reserve;
  plugin->update_auditor_progress_reserve
    = &TAH_PG_update_auditor_progress_reserve;
  plugin->insert_auditor_progress_reserve
    = &TAH_PG_insert_auditor_progress_reserve;

  plugin->get_auditor_progress_purse
    = &TAH_PG_get_auditor_progress_purse;
  plugin->update_auditor_progress_purse
    = &TAH_PG_update_auditor_progress_purse;
  plugin->insert_auditor_progress_purse
    = &TAH_PG_insert_auditor_progress_purse;

  plugin->get_auditor_progress_aggregation
    = &TAH_PG_get_auditor_progress_aggregation;
  plugin->update_auditor_progress_aggregation
    = &TAH_PG_update_auditor_progress_aggregation;
  plugin->insert_auditor_progress_aggregation
    = &TAH_PG_insert_auditor_progress_aggregation;

  plugin->get_auditor_progress_deposit_confirmation
    = &TAH_PG_get_auditor_progress_deposit_confirmation;
  plugin->update_auditor_progress_deposit_confirmation
    = &TAH_PG_update_auditor_progress_deposit_confirmation;
  plugin->insert_auditor_progress_deposit_confirmation
    = &TAH_PG_insert_auditor_progress_deposit_confirmation;

  plugin->get_auditor_progress_coin
    = &TAH_PG_get_auditor_progress_coin;
  plugin->update_auditor_progress_coin
    = &TAH_PG_update_auditor_progress_coin;
  plugin->insert_auditor_progress_coin
    = &TAH_PG_insert_auditor_progress_coin;

  plugin->get_wire_auditor_account_progress
    = &TAH_PG_get_wire_auditor_account_progress;
  plugin->update_wire_auditor_account_progress
    = &TAH_PG_update_wire_auditor_account_progress;
  plugin->insert_wire_auditor_account_progress
    = &TAH_PG_insert_wire_auditor_account_progress;

  plugin->get_wire_auditor_progress
    = &TAH_PG_get_wire_auditor_progress;
  plugin->update_wire_auditor_progress
    = &TAH_PG_update_wire_auditor_progress;
  plugin->insert_wire_auditor_progress
    = &TAH_PG_insert_wire_auditor_progress;

  plugin->del_reserve_info
    = &TAH_PG_del_reserve_info;
  plugin->get_reserve_info
    = &TAH_PG_get_reserve_info;
  plugin->update_reserve_info
    = &TAH_PG_update_reserve_info;
  plugin->insert_reserve_info
    = &TAH_PG_insert_reserve_info;

  plugin->get_reserve_summary
    = &TAH_PG_get_reserve_summary;
  plugin->update_reserve_summary
    = &TAH_PG_update_reserve_summary;
  plugin->insert_reserve_summary
    = &TAH_PG_insert_reserve_summary;

  plugin->get_wire_fee_summary
    = &TAH_PG_get_wire_fee_summary;
  plugin->update_wire_fee_summary
    = &TAH_PG_update_wire_fee_summary;
  plugin->insert_wire_fee_summary
    = &TAH_PG_insert_wire_fee_summary;

  plugin->get_denomination_balance
    = &TAH_PG_get_denomination_balance;
  plugin->update_denomination_balance
    = &TAH_PG_update_denomination_balance;
  plugin->insert_denomination_balance
    = &TAH_PG_insert_denomination_balance;

  plugin->get_balance_summary
    = &TAH_PG_get_balance_summary;
  plugin->update_balance_summary
    = &TAH_PG_update_balance_summary;
  plugin->insert_balance_summary
    = &TAH_PG_insert_balance_summary;

  plugin->select_historic_denom_revenue
    = &TAH_PG_select_historic_denom_revenue;
  plugin->insert_historic_denom_revenue
    = &TAH_PG_insert_historic_denom_revenue;

  plugin->select_historic_reserve_revenue
    = &TAH_PG_select_historic_reserve_revenue;
  plugin->insert_historic_reserve_revenue
    = &TAH_PG_insert_historic_reserve_revenue;

  plugin->select_pending_deposits
    = &TAH_PG_select_pending_deposits;
  plugin->delete_pending_deposit
    = &TAH_PG_delete_pending_deposit;
  plugin->insert_pending_deposit
    = &TAH_PG_insert_pending_deposit;

  plugin->get_predicted_balance
    = &TAH_PG_get_predicted_balance;
  plugin->update_predicted_result
    = &TAH_PG_update_predicted_result;
  plugin->insert_predicted_result
    = &TAH_PG_insert_predicted_result;
  plugin->get_purse_info
    = &TAH_PG_get_purse_info;

  plugin->delete_purse_info
    = &TAH_PG_delete_purse_info;
  plugin->update_purse_info
    = &TAH_PG_update_purse_info;
  plugin->insert_purse_info
    = &TAH_PG_insert_purse_info;
  plugin->get_purse_summary
    = &TAH_PG_get_purse_summary;

  plugin->select_purse_expired
    = &TAH_PG_select_purse_expired;
  plugin->insert_purse_summary
    = &TAH_PG_insert_purse_summary;
  plugin->update_purse_summary
    = &TAH_PG_update_purse_summary;

  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_AUDITORDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_auditordb_postgres_done (void *cls)
{
  struct TALER_AUDITORDB_Plugin *plugin = cls;
  struct PostgresClosure *pg = plugin->cls;

  if (NULL != pg->conn)
    GNUNET_PQ_disconnect (pg->conn);
  GNUNET_free (pg->currency);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}


/* end of plugin_auditordb_postgres.c */
