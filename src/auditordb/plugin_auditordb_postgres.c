/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
#include "pg_delete_generic.h"
#include "pg_delete_deposit_confirmations.h"
#include "pg_delete_pending_deposit.h"
#include "pg_delete_purse_info.h"
#include "pg_del_denomination_balance.h"
#include "pg_del_reserve_info.h"
#include "pg_get_auditor_progress.h"
#include "pg_get_balance.h"
#include "pg_get_balances.h"
#include "pg_get_denomination_balance.h"
#include "pg_get_deposit_confirmations.h"
#include "pg_get_purse_info.h"
#include "pg_get_reserve_info.h"
#include "pg_get_wire_fee_summary.h"
#include "pg_helper.h"
#include "pg_insert_auditor_progress.h"
#include "pg_insert_balance.h"
#include "pg_insert_denomination_balance.h"
#include "pg_insert_deposit_confirmation.h"
#include "pg_insert_exchange_signkey.h"
#include "pg_insert_historic_denom_revenue.h"
#include "pg_insert_historic_reserve_revenue.h"
#include "pg_insert_pending_deposit.h"
#include "pg_insert_purse_info.h"
#include "pg_insert_reserve_info.h"
#include "pg_select_historic_denom_revenue.h"
#include "pg_select_historic_reserve_revenue.h"
#include "pg_get_progress_points.h"
#include "pg_select_pending_deposits.h"
#include "pg_select_purse_expired.h"
#include "pg_update_generic_suppressed.h"
#include "pg_update_auditor_progress.h"
#include "pg_update_denomination_balance.h"
#include "pg_update_purse_info.h"
#include "pg_update_reserve_info.h"
#include "pg_update_wire_fee_summary.h"
#include "pg_get_amount_arithmetic_inconsistency.h"
#include "pg_get_coin_inconsistency.h"
#include "pg_get_row_inconsistency.h"
#include "pg_update_emergency_by_count.h"
#include "pg_update_row_inconsistency.h"
#include "pg_update_purse_not_closed_inconsistencies.h"
#include "pg_update_reserve_balance_insufficient_inconsistency.h"
#include "pg_update_coin_inconsistency.h"
#include "pg_update_denomination_key_validity_withdraw_inconsistency.h"
#include "pg_update_refreshes_hanging.h"
#include "pg_update_emergency.h"
#include "pg_update_closure_lags.h"
#include "pg_update_row_minor_inconsistencies.h"

#include "pg_update_balance.h"

#include "pg_del_amount_arithmetic_inconsistency.h"
#include "pg_del_coin_inconsistency.h"
#include "pg_del_row_inconsistency.h"

#include "pg_insert_coin_inconsistency.h"
#include "pg_insert_row_inconsistency.h"
#include "pg_insert_amount_arithmetic_inconsistency.h"

#include "pg_get_auditor_closure_lags.h"
#include "pg_del_auditor_closure_lags.h"
#include "pg_insert_auditor_closure_lags.h"

#include "pg_get_emergency_by_count.h"
#include "pg_del_emergency_by_count.h"
#include "pg_insert_emergency_by_count.h"

#include "pg_get_emergency.h"
#include "pg_del_emergency.h"
#include "pg_insert_emergency.h"

#include "pg_del_auditor_progress.h"

#include "pg_get_bad_sig_losses.h"
#include "pg_del_bad_sig_losses.h"
#include "pg_insert_bad_sig_losses.h"
#include "pg_update_bad_sig_losses.h"

#include "pg_get_denomination_key_validity_withdraw_inconsistency.h"
#include "pg_del_denomination_key_validity_withdraw_inconsistency.h"
#include "pg_insert_denomination_key_validity_withdraw_inconsistency.h"

#include "pg_get_fee_time_inconsistency.h"
#include "pg_del_fee_time_inconsistency.h"
#include "pg_insert_fee_time_inconsistency.h"
#include "pg_update_fee_time_inconsistency.h"

#include "pg_get_purse_not_closed_inconsistencies.h"
#include "pg_del_purse_not_closed_inconsistencies.h"
#include "pg_insert_purse_not_closed_inconsistencies.h"

#include "pg_get_refreshes_hanging.h"
#include "pg_del_refreshes_hanging.h"
#include "pg_insert_refreshes_hanging.h"

#include "pg_get_reserve_balance_insufficient_inconsistency.h"
#include "pg_del_reserve_balance_insufficient_inconsistency.h"
#include "pg_insert_reserve_balance_insufficient_inconsistency.h"

#include "pg_get_reserve_in_inconsistency.h"
#include "pg_del_reserve_in_inconsistency.h"
#include "pg_insert_reserve_in_inconsistency.h"
#include "pg_update_reserve_in_inconsistency.h"

#include "pg_get_reserve_not_closed_inconsistency.h"
#include "pg_del_reserve_not_closed_inconsistency.h"
#include "pg_insert_reserve_not_closed_inconsistency.h"
#include "pg_update_reserve_not_closed_inconsistency.h"

#include "pg_get_denominations_without_sigs.h"
#include "pg_del_denominations_without_sigs.h"
#include "pg_insert_denominations_without_sigs.h"
#include "pg_update_denominations_without_sigs.h"

#include "pg_get_misattribution_in_inconsistency.h"
#include "pg_del_misattribution_in_inconsistency.h"
#include "pg_insert_misattribution_in_inconsistency.h"
#include "pg_update_misattribution_in_inconsistency.h"

#include "pg_get_reserves.h"
#include "pg_get_purses.h"

#include "pg_get_denomination_pending.h"
#include "pg_del_denomination_pending.h"
#include "pg_insert_denomination_pending.h"
#include "pg_update_denomination_pending.h"

#include "pg_get_exchange_signkeys.h"

#include "pg_get_wire_format_inconsistency.h"
#include "pg_del_wire_format_inconsistency.h"
#include "pg_insert_wire_format_inconsistency.h"
#include "pg_update_wire_format_inconsistency.h"

#include "pg_get_wire_out_inconsistency.h"
#include "pg_del_wire_out_inconsistency.h"
#include "pg_insert_wire_out_inconsistency.h"
#include "pg_delete_wire_out_inconsistency_if_matching.h"
#include "pg_update_wire_out_inconsistency.h"

#include "pg_get_reserve_balance_summary_wrong_inconsistency.h"
#include "pg_del_reserve_balance_summary_wrong_inconsistency.h"
#include "pg_insert_reserve_balance_summary_wrong_inconsistency.h"
#include "pg_update_reserve_balance_summary_wrong_inconsistency.h"

#include "pg_get_row_minor_inconsistencies.h"
#include "pg_del_row_minor_inconsistencies.h"
#include "pg_insert_row_minor_inconsistencies.h"
#include "pg_update_row_minor_inconsistencies.h"

#include "pg_update_amount_arithmetic_inconsistency.h"
#include "pg_update_deposit_confirmations.h"

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
 * @param support_partitions true to support partitioning
 * @param num_partitions number of partitions to use
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_create_tables (void *cls,
                        bool support_partitions,
                        uint32_t num_partitions)
{
  struct PostgresClosure *pc = cls;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;
  struct GNUNET_PQ_Context *conn;
  struct GNUNET_PQ_QueryParam params[] = {
    support_partitions
    ? GNUNET_PQ_query_param_uint32 (&num_partitions)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("create_tables",
                            "SELECT"
                            " auditor.do_create_tables"
                            " ($1);"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO auditor;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "auditordb-postgres",
                                     "auditor-",
                                     es,
                                     ps);
  if (NULL == conn)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to database\n");
    return GNUNET_SYSERR;
  }
  if (0 >
      GNUNET_PQ_eval_prepared_non_select (conn,
                                          "create_tables",
                                          params))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to run 'create_tables' prepared statement\n");
    ret = GNUNET_SYSERR;
  }
  if (GNUNET_OK == ret)
  {
    ret = GNUNET_PQ_exec_sql (conn,
                              "procedures");
    if (GNUNET_OK != ret)
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to load stored procedures\n");
  }
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/**
 * Register callback to be invoked on events of type @a es.
 *
 * @param cls database context to use
 * @param es specification of the event to listen for
 * @param timeout how long to wait for the event
 * @param cb function to call when the event happens, possibly
 *         mulrewardle times (until cancel is invoked)
 * @param cb_cls closure for @a cb
 * @return handle useful to cancel the listener
 */
static struct GNUNET_DB_EventHandler *
postgres_event_listen (void *cls,
                       const struct GNUNET_DB_EventHeaderP *es,
                       struct GNUNET_TIME_Relative timeout,
                       GNUNET_DB_EventCallback cb,
                       void *cb_cls)
{
  struct PostgresClosure *pg = cls;

  return GNUNET_PQ_event_listen (pg->conn,
                                 es,
                                 timeout,
                                 cb,
                                 cb_cls);
}


/**
 * Stop notifications.
 *
 * @param eh handle to unregister.
 */
static void
postgres_event_listen_cancel (struct GNUNET_DB_EventHandler *eh)
{
  GNUNET_PQ_event_listen_cancel (eh);
}


/**
 * Notify all that listen on @a es of an event.
 *
 * @param cls database context to use
 * @param es specification of the event to generate
 * @param extra additional event data provided
 * @param extra_size number of bytes in @a extra
 */
static void
postgres_event_notify (void *cls,
                       const struct GNUNET_DB_EventHeaderP *es,
                       const void *extra,
                       size_t extra_size)
{
  struct PostgresClosure *pg = cls;

  return GNUNET_PQ_event_notify (pg->conn,
                                 es,
                                 extra,
                                 extra_size);
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
static enum GNUNET_DB_QueryStatus
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
libtaler_plugin_auditordb_postgres_init (void *cls);

/* Declaration used to squash compiler warning */
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

  // MARK: CRUD

  plugin = GNUNET_new (struct TALER_AUDITORDB_Plugin);
  plugin->cls = pg;
  plugin->preflight = &postgres_preflight;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->event_listen = &postgres_event_listen;
  plugin->event_listen_cancel = &postgres_event_listen_cancel;
  plugin->event_notify = &postgres_event_notify;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->rollback = &postgres_rollback;
  plugin->gc = &postgres_gc;

  plugin->get_auditor_progress
    = &TAH_PG_get_auditor_progress;

  plugin->get_balance = &TAH_PG_get_balance;
  plugin->get_balances = &TAH_PG_get_balances;

  plugin->insert_auditor_progress
    = &TAH_PG_insert_auditor_progress;
  plugin->insert_balance
    = &TAH_PG_insert_balance;
  plugin->update_generic_suppressed
    = &TAH_PG_update_generic_suppressed;
  plugin->delete_generic
    = &TAH_PG_delete_generic;


  plugin->update_auditor_progress
    = &TAH_PG_update_auditor_progress;
  plugin->insert_deposit_confirmation
    = &TAH_PG_insert_deposit_confirmation;
  plugin->get_deposit_confirmations
    = &TAH_PG_get_deposit_confirmations;
  plugin->delete_deposit_confirmation
    = &TAH_PG_delete_deposit_confirmation;


  plugin->get_amount_arithmetic_inconsistency
    = &TAH_PG_get_amount_arithmetic_inconsistency;
  plugin->get_coin_inconsistency
    = &TAH_PG_get_coin_inconsistency;
  plugin->get_row_inconsistency
    = &TAH_PG_get_row_inconsistency;


  plugin->delete_row_inconsistency
    = &TAH_PG_del_row_inconsistency;
  plugin->delete_coin_inconsistency
    = &TAH_PG_del_coin_inconsistency;
  plugin->delete_amount_arithmetic_inconsistency
    = &TAH_PG_del_amount_arithmetic_inconsistency;


  plugin->insert_amount_arithmetic_inconsistency
    = &TAH_PG_insert_amount_arithmetic_inconsistency;
  plugin->insert_coin_inconsistency
    = &TAH_PG_insert_coin_inconsistency;
  plugin->insert_row_inconsistency
    = &TAH_PG_insert_row_inconsistency;

  plugin->insert_reserve_info
    = &TAH_PG_insert_reserve_info;
  plugin->update_reserve_info
    = &TAH_PG_update_reserve_info;
  plugin->get_reserve_info
    = &TAH_PG_get_reserve_info;
  plugin->del_reserve_info
    = &TAH_PG_del_reserve_info;

  plugin->insert_pending_deposit
    = &TAH_PG_insert_pending_deposit;
  plugin->select_pending_deposits
    = &TAH_PG_select_pending_deposits;
  plugin->delete_pending_deposit
    = &TAH_PG_delete_pending_deposit;

  plugin->insert_purse_info
    = &TAH_PG_insert_purse_info;
  plugin->update_purse_info
    = &TAH_PG_update_purse_info;
  plugin->get_purse_info
    = &TAH_PG_get_purse_info;
  plugin->delete_purse_info
    = &TAH_PG_delete_purse_info;
  plugin->select_purse_expired
    = &TAH_PG_select_purse_expired;

  plugin->insert_denomination_balance
    = &TAH_PG_insert_denomination_balance;
  plugin->update_denomination_balance
    = &TAH_PG_update_denomination_balance;
  plugin->del_denomination_balance
    = &TAH_PG_del_denomination_balance;
  plugin->get_denomination_balance
    = &TAH_PG_get_denomination_balance;

  plugin->insert_historic_denom_revenue
    = &TAH_PG_insert_historic_denom_revenue;

  plugin->select_historic_denom_revenue
    = &TAH_PG_select_historic_denom_revenue;

  plugin->insert_historic_reserve_revenue
    = &TAH_PG_insert_historic_reserve_revenue;
  plugin->select_historic_reserve_revenue
    = &TAH_PG_select_historic_reserve_revenue;


  plugin->delete_emergency = &TAH_PG_del_emergency;
  plugin->insert_emergency = &TAH_PG_insert_emergency;
  plugin->get_emergency = &TAH_PG_get_emergency;

  plugin->delete_emergency_by_count = &TAH_PG_del_emergency_by_count;
  plugin->insert_emergency_by_count = &TAH_PG_insert_emergency_by_count;
  plugin->get_emergency_by_count = &TAH_PG_get_emergency_by_count;


  plugin->delete_denomination_key_validity_withdraw_inconsistency =
    &TAH_PG_del_denomination_key_validity_withdraw_inconsistency;
  plugin->insert_denomination_key_validity_withdraw_inconsistency =
    &TAH_PG_insert_denomination_key_validity_withdraw_inconsistency;
  plugin->get_denomination_key_validity_withdraw_inconsistency =
    &TAH_PG_get_denomination_key_validity_withdraw_inconsistency;

  plugin->delete_purse_not_closed_inconsistencies =
    &TAH_PG_del_purse_not_closed_inconsistencies;
  plugin->insert_purse_not_closed_inconsistencies =
    &TAH_PG_insert_purse_not_closed_inconsistencies;
  plugin->get_purse_not_closed_inconsistencies =
    &TAH_PG_get_purse_not_closed_inconsistencies;


  plugin->delete_reserve_balance_insufficient_inconsistency =
    &TAH_PG_del_reserve_balance_insufficient_inconsistency;
  plugin->insert_reserve_balance_insufficient_inconsistency =
    &TAH_PG_insert_reserve_balance_insufficient_inconsistency;
  plugin->get_reserve_balance_insufficient_inconsistency =
    &TAH_PG_get_reserve_balance_insufficient_inconsistency;

  plugin->delete_bad_sig_losses = &TAH_PG_del_bad_sig_losses;
  plugin->insert_bad_sig_losses = &TAH_PG_insert_bad_sig_losses;
  plugin->get_bad_sig_losses = &TAH_PG_get_bad_sig_losses;
  plugin->update_bad_sig_losses = &TAH_PG_update_bad_sig_losses;

  plugin->delete_auditor_closure_lags = &TAH_PG_del_auditor_closure_lags;
  plugin->insert_auditor_closure_lags = &TAH_PG_insert_auditor_closure_lags;
  plugin->get_auditor_closure_lags = &TAH_PG_get_auditor_closure_lags;


  plugin->delete_progress = &TAH_PG_del_progress;


  plugin->delete_refreshes_hanging = &TAH_PG_del_refreshes_hanging;
  plugin->insert_refreshes_hanging = &TAH_PG_insert_refreshes_hanging;
  plugin->get_refreshes_hanging = &TAH_PG_get_refreshes_hanging;

  plugin->update_emergency_by_count = &TAH_PG_update_emergency_by_count;
  plugin->update_row_inconsistency = &TAH_PG_update_row_inconsistency;
  plugin->update_purse_not_closed_inconsistencies =
    &TAH_PG_update_purse_not_closed_inconsistencies;
  plugin->update_reserve_balance_insufficient_inconsistency =
    &TAH_PG_update_reserve_balance_insufficient_inconsistency;
  plugin->update_coin_inconsistency = &TAH_PG_update_coin_inconsistency;
  plugin->update_denomination_key_validity_withdraw_inconsistency =
    &TAH_PG_update_denomination_key_validity_withdraw_inconsistency;
  plugin->update_refreshes_hanging = &TAH_PG_update_refreshes_hanging;
  plugin->update_emergency = &TAH_PG_update_emergency;
  plugin->update_closure_lags = &TAH_PG_update_closure_lags;


  plugin->delete_reserve_in_inconsistency =
    &TAH_PG_del_reserve_in_inconsistency;
  plugin->insert_reserve_in_inconsistency =
    &TAH_PG_insert_reserve_in_inconsistency;
  plugin->get_reserve_in_inconsistency = &TAH_PG_get_reserve_in_inconsistency;
  plugin->update_reserve_in_inconsistency =
    &TAH_PG_update_reserve_in_inconsistency;


  plugin->delete_reserve_not_closed_inconsistency =
    &TAH_PG_del_reserve_not_closed_inconsistency;
  plugin->insert_reserve_not_closed_inconsistency =
    &TAH_PG_insert_reserve_not_closed_inconsistency;
  plugin->get_reserve_not_closed_inconsistency =
    &TAH_PG_get_reserve_not_closed_inconsistency;
  plugin->update_reserve_not_closed_inconsistency =
    &TAH_PG_update_reserve_not_closed_inconsistency;


  plugin->delete_denominations_without_sigs =
    &TAH_PG_del_denominations_without_sigs;
  plugin->insert_denominations_without_sigs =
    &TAH_PG_insert_denominations_without_sigs;
  plugin->get_denominations_without_sigs =
    &TAH_PG_get_denominations_without_sigs;
  plugin->update_denominations_without_sigs =
    &TAH_PG_update_denominations_without_sigs;

  plugin->get_progress_points
    = &TAH_PG_get_progress_points;


  plugin->delete_misattribution_in_inconsistency =
    &TAH_PG_del_misattribution_in_inconsistency;
  plugin->insert_misattribution_in_inconsistency =
    &TAH_PG_insert_misattribution_in_inconsistency;
  plugin->get_misattribution_in_inconsistency =
    &TAH_PG_get_misattribution_in_inconsistency;
  plugin->update_misattribution_in_inconsistency =
    &TAH_PG_update_misattribution_in_inconsistency;

  plugin->get_reserves = &TAH_PG_get_reserves;
  plugin->get_purses = &TAH_PG_get_purses;

  plugin->delete_denomination_pending = &TAH_PG_del_denomination_pending;
  plugin->insert_denomination_pending = &TAH_PG_insert_denomination_pending;
  plugin->get_denomination_pending = &TAH_PG_get_denomination_pending;
  plugin->update_denomination_pending = &TAH_PG_update_denomination_pending;

  plugin->get_exchange_signkeys = &TAH_PG_get_exchange_signkeys;

  plugin->delete_wire_format_inconsistency =
    &TAH_PG_del_wire_format_inconsistency;
  plugin->insert_wire_format_inconsistency =
    &TAH_PG_insert_wire_format_inconsistency;
  plugin->get_wire_format_inconsistency = &TAH_PG_get_wire_format_inconsistency;
  plugin->update_wire_format_inconsistency =
    &TAH_PG_update_wire_format_inconsistency;


  plugin->delete_wire_out_inconsistency
    = &TAH_PG_del_wire_out_inconsistency;
  plugin->insert_wire_out_inconsistency
    = &TAH_PG_insert_wire_out_inconsistency;
  plugin->delete_wire_out_inconsistency_if_matching
    = &TAH_PG_delete_wire_out_inconsistency_if_matching;
  plugin->get_wire_out_inconsistency
    = &TAH_PG_get_wire_out_inconsistency;
  plugin->update_wire_out_inconsistency
    = &TAH_PG_update_wire_out_inconsistency;

  plugin->delete_reserve_balance_summary_wrong_inconsistency =
    &TAH_PG_del_reserve_balance_summary_wrong_inconsistency;
  plugin->insert_reserve_balance_summary_wrong_inconsistency =
    &TAH_PG_insert_reserve_balance_summary_wrong_inconsistency;
  plugin->get_reserve_balance_summary_wrong_inconsistency =
    &TAH_PG_get_reserve_balance_summary_wrong_inconsistency;
  plugin->update_reserve_balance_summary_wrong_inconsistency =
    &TAH_PG_update_reserve_balance_summary_wrong_inconsistency;


  plugin->delete_row_minor_inconsistencies =
    &TAH_PG_del_row_minor_inconsistencies;
  plugin->insert_row_minor_inconsistencies =
    &TAH_PG_insert_row_minor_inconsistencies;
  plugin->get_row_minor_inconsistencies = &TAH_PG_get_row_minor_inconsistencies;
  plugin->update_row_minor_inconsistencies =
    &TAH_PG_update_row_minor_inconsistencies;

  plugin->delete_fee_time_inconsistency = &TAH_PG_del_fee_time_inconsistency;
  plugin->insert_fee_time_inconsistency = &TAH_PG_insert_fee_time_inconsistency;
  plugin->get_fee_time_inconsistency = &TAH_PG_get_fee_time_inconsistency;
  plugin->update_fee_time_inconsistency = &TAH_PG_update_fee_time_inconsistency;

  plugin->update_balance
    = &TAH_PG_update_balance;

  plugin->insert_exchange_signkey
    = &TAH_PG_insert_exchange_signkey;

  plugin->update_deposit_confirmations
    = &TAH_PG_update_deposit_confirmations;
  plugin->update_amount_arithmetic_inconsistency
    = &TAH_PG_update_amount_arithmetic_inconsistency;

  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_AUDITORDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_auditordb_postgres_done (void *cls);

/* Declaration used to squash compiler warning */
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
