/*
  This file is part of TALER
  Copyright (C) 2014-2016 GNUnet e.V.

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
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 */
#include "platform.h"
#include "taler_pq_lib.h"
#include "taler_auditordb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>

/**
 * Log a query error.
 *
 * @param result PQ result object of the query that failed
 */
#define QUERY_ERR(result)                          \
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed at %s:%u: %s (%s)\n", __FILE__, __LINE__, PQresultErrorMessage (result), PQresStatus (PQresultStatus (result)))


/**
 * Log a really unexpected PQ error.
 *
 * @param result PQ result object of the PQ operation that failed
 */
#define BREAK_DB_ERR(result) do { \
    GNUNET_break (0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s (%s)\n", PQresultErrorMessage (result), PQresStatus (PQresultStatus (result))); \
  } while (0)


/**
 * Shorthand for exit jumps.  Logs the current line number
 * and jumps to the "EXITIF_exit" label.
 *
 * @param cond condition that must be TRUE to exit with an error
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


/**
 * Execute an SQL statement and log errors on failure. Must be
 * run in a function that has an "SQLEXEC_fail" label to jump
 * to in case the SQL statement failed.
 *
 * @param conn database connection
 * @param sql SQL statement to run
 */
#define SQLEXEC_(conn, sql)                                             \
  do {                                                                  \
    PGresult *result = PQexec (conn, sql);                              \
    if (PGRES_COMMAND_OK != PQresultStatus (result))                    \
    {                                                                   \
      BREAK_DB_ERR (result);                                            \
      PQclear (result);                                                 \
      goto SQLEXEC_fail;                                                \
    }                                                                   \
    PQclear (result);                                                   \
  } while (0)


/**
 * Run an SQL statement, ignoring errors and clearing the result.
 *
 * @param conn database connection
 * @param sql SQL statement to run
 */
#define SQLEXEC_IGNORE_ERROR_(conn, sql)                                \
  do {                                                                  \
    PGresult *result = PQexec (conn, sql);                              \
    PQclear (result);                                                   \
  } while (0)


/**
 * Handle for a database session (per-thread, for transactions).
 */
struct TALER_AUDITORDB_Session
{
  /**
   * Postgres connection handle.
   */
  PGconn *conn;
};


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct PostgresClosure
{

  /**
   * Thread-local database connection.
   * Contains a pointer to `PGconn` or NULL.
   */
  pthread_key_t db_conn_threadlocal;

  /**
   * Database connection string, as read from
   * the configuration.
   */
  char *connection_cfg_str;
};


/**
 * Function called by libpq whenever it wants to log something.
 * We already log whenever we care, so this function does nothing
 * and merely exists to silence the libpq logging.
 *
 * @param arg NULL
 * @param res information about some libpq event
 */
static void
pq_notice_receiver_cb (void *arg,
                       const PGresult *res)
{
  /* do nothing, intentionally */
}


/**
 * Function called by libpq whenever it wants to log something.
 * We log those using the Taler logger.
 *
 * @param arg NULL
 * @param message information about some libpq event
 */
static void
pq_notice_processor_cb (void *arg,
                        const char *message)
{
  GNUNET_log_from (GNUNET_ERROR_TYPE_INFO,
                   "pq",
                   "%s",
                   message);
}


/**
 * Establish connection to the Postgres database
 * and initialize callbacks for logging.
 *
 * @param pc configuration to use
 * @return NULL on error
 */
static PGconn *
connect_to_postgres (struct PostgresClosure *pc)
{
  PGconn *conn;

  conn = PQconnectdb (pc->connection_cfg_str);
  if (CONNECTION_OK !=
      PQstatus (conn))
  {
    TALER_LOG_ERROR ("Database connection failed: %s\n",
                     PQerrorMessage (conn));
    GNUNET_break (0);
    return NULL;
  }
  PQsetNoticeReceiver (conn,
                       &pq_notice_receiver_cb,
                       NULL);
  PQsetNoticeProcessor (conn,
                        &pq_notice_processor_cb,
                        NULL);
  return conn;
}


/**
 * Drop all Taler tables.  This should only be used by testcases.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_drop_tables (void *cls)
{
  struct PostgresClosure *pc = cls;
  PGconn *conn;

  conn = connect_to_postgres (pc);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Dropping ALL tables\n");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS test;");
  PQfinish (conn);
  return GNUNET_OK;
 SQLEXEC_fail:
  PQfinish (conn);
  return GNUNET_SYSERR;
}


/**
 * Create the necessary tables if they are not present
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_create_tables (void *cls)
{
  struct PostgresClosure *pc = cls;
  PGconn *conn;

  conn = connect_to_postgres (pc);
  if (NULL == conn)
    return GNUNET_SYSERR;
#define SQLEXEC(sql) SQLEXEC_(conn, sql);
#define SQLEXEC_INDEX(sql) SQLEXEC_IGNORE_ERROR_(conn, sql);

  /* Table with all of the denomination keys that the auditor
     is aware of. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS auditor_denominations"
           "(denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)"
           ",master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
           ",valid_from INT8 NOT NULL"
           ",expire_withdraw INT8 NOT NULL"
           ",expire_deposit INT8 NOT NULL"
           ",expire_legal INT8 NOT NULL"
           ",coin_val INT8 NOT NULL" /* value of this denom */
           ",coin_frac INT4 NOT NULL" /* fractional value of this denom */
           ",coin_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL" /* assuming same currency for fees */
           ",fee_withdraw_val INT8 NOT NULL"
           ",fee_withdraw_frac INT4 NOT NULL"
           ",fee_withdraw_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",fee_deposit_val INT8 NOT NULL"
           ",fee_deposit_frac INT4 NOT NULL"
           ",fee_deposit_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",fee_refresh_val INT8 NOT NULL"
           ",fee_refresh_frac INT4 NOT NULL"
           ",fee_refresh_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",fee_refund_val INT8 NOT NULL"
           ",fee_refund_frac INT4 NOT NULL"
           ",fee_refund_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ")");

  /* Table with all of the customer reserves and their respective
     balances that the auditor is aware of.
     "last_reserve_out_serial_id" marks the last withdrawal from
     "reserves_out" about this reserve that the auditor is aware of,
     and "last_reserve_in_serial_id" is the last "reserve_in"
     operation about this reserve that the auditor is aware of. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS auditor_reserves"
	   "(reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)"
           ",master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
           ",reserve_balance_val INT8 NOT NULL"
           ",reserve_balance_frac INT4 NOT NULL"
           ",reserve_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",withdraw_fee_balance_val INT8 NOT NULL"
           ",withdraw_fee_balance_frac INT4 NOT NULL"
           ",withdraw_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",expiration_date INT8 NOT NULL"
	   ",last_reserve_in_serial_id INT8 NOT NULL"
           ",last_reserve_out_serial_id INT8 NOT NULL"
	   ")");

  /* Table with the sum of the balances of all customer reserves
     (by exchange's master public key) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS auditor_reserve_balance"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",reserve_balance_val INT8 NOT NULL"
           ",reserve_balance_frac INT4 NOT NULL"
           ",reserve_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",withdraw_fee_balance_val INT8 NOT NULL"
           ",withdraw_fee_balance_frac INT4 NOT NULL"
           ",withdraw_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  /* Table with all of the outstanding denomination coins that the
     exchange is aware of.  "last_deposit_serial_id" marks the
     deposit_serial_id from "deposits" about this denomination key
     that the auditor is aware of; "last_melt_serial_id" marks the
     last melt from "refresh_sessions" that the auditor is aware
     of; "refund_serial_id" tells us the last entry in "refunds"
     for this denom_pub that the auditor is aware of. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS denomination_pending"
	   "(denom_pub_hash BYTEA NOT NULL REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE"
           ",denom_balance_val INT8 NOT NULL"
           ",denom_balance_frac INT4 NOT NULL"
           ",denom_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",deposit_fee_balance_val INT8 NOT NULL"
           ",deposit_fee_balance_frac INT4 NOT NULL"
           ",deposit_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",melt_fee_balance_val INT8 NOT NULL"
           ",melt_fee_balance_frac INT4 NOT NULL"
           ",melt_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",refund_fee_balance_val INT8 NOT NULL"
           ",refund_fee_balance_frac INT4 NOT NULL"
           ",refund_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",last_deposit_serial_id INT8 NOT NULL"
	   ",last_melt_serial_id INT8 NOT NULL"
	   ",last_refund INT8 NOT NULL"
	   ")");

  /* Table with the sum of the outstanding coins from
     "denomination_pending" (denom_pubs must belong
     to the respective's exchange's master public key);
     it represents the total_liabilities of the exchange
     at this point (modulo unexpected historic_loss-style
     events where denomination keys are compromised) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS total_liabilities"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",denom_balance_val INT8 NOT NULL"
           ",denom_balance_frac INT4 NOT NULL"
           ",denom_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",deposit_fee_balance_val INT8 NOT NULL"
           ",deposit_fee_balance_frac INT4 NOT NULL"
           ",deposit_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",melt_fee_balance_val INT8 NOT NULL"
           ",melt_fee_balance_frac INT4 NOT NULL"
           ",melt_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  /* Table with the sum of the generated coins all
     denomination keys.  This represents the maximum
     additional total financial risk of the exchange
     in case that all denomination keys are compromised
     (and all of the deposits so far were done by
     the successful attacker).  So this is strictly an
     upper bound on the risk exposure of the exchange.
     (Note that this risk is in addition to the known
     total_liabilities) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS total_risk"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",risk_val INT8 NOT NULL"
           ",risk_frac INT4 NOT NULL"
           ",risk_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");


  /* Table with historic profits; basically, when a denom_pub
     is expired and everything associated with it is garbage
     collected, the final profits end up in here; note that
     the "denom_pub" here is not a foreign key, we just keep
     it as a reference point.   "revenue_balance" is the sum
     of all of the profits we made on the coin except for
     withdraw fees (which are in historic_reserve_revenue);
     the deposit and melt fees are given individually; the
     delta to the revenue_balance is from coins that were withdrawn
     but never deposited prior to expiration. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_denomination_revenue"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",denom_pub_hash BYTEA NOT NULL CHECK (LENGTH(denom_pub_hash)=64)"
	   ",revenue_timestamp INT8 NOT NULL"
	   ",revenue_balance_val INT8 NOT NULL"
           ",revenue_balance_frac INT4 NOT NULL"
           ",revenue_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",deposit_fee_balance_val INT8 NOT NULL"
           ",deposit_fee_balance_frac INT4 NOT NULL"
           ",deposit_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",melt_fee_balance_val INT8 NOT NULL"
           ",melt_fee_balance_frac INT4 NOT NULL"
           ",melt_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"	   ")");

  /* Table with historic losses; basically, when we need to
     invalidate a denom_pub because the denom_priv was
     compromised, we incur a loss. These losses are totaled
     up here. (NOTE: the 'bankrupcy' protocol is not yet
     implemented, so right now this table is not used.)  */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_losses"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",denom_pub_hash BYTEA NOT NULL CHECK (LENGTH(denom_pub_hash)=64)"
	   ",loss_timestamp INT8 NOT NULL"
	   ",loss_balance_val INT8 NOT NULL"
           ",loss_balance_frac INT4 NOT NULL"
           ",loss_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  /* Table with historic profits by reserve; basically, when a
     reserve expires, we transmit the balance back to the user, but
     rounding gains and withdraw fees are listed here. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_reserve_revenue"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32)"
	   ",expiration_date INT8 NOT NULL"
	   ",reserve_profit_val INT8 NOT NULL"
           ",reserve_profit_frac INT4 NOT NULL"
           ",reserve_profit_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  /* Table with historic profits from reserves; we eventually
     GC "historic_reserve_revenue", and then store the totals
     in here (by time intervals). */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_reserve_summary"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",start_date INT8 NOT NULL"
	   ",end_date INT8 NOT NULL"
	   ",reserve_profits_val INT8 NOT NULL"
           ",reserve_profits_frac INT4 NOT NULL"
           ",reserve_profits_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  /* Table with historic business ledger; basically, when the exchange
     operator decides to use operating costs for anything but wire
     transfers to merchants, it goes in here.  This happens when the
     operator users transaction fees for business expenses. "purpose"
     is free-form but should be a human-readable wire transfer
     identifier. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_ledger"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",purpose VARCHAR NOT NULL"
	   ",timestamp INT8 NOT NULL"
	   ",balance_val INT8 NOT NULL"
           ",balance_frac INT4 NOT NULL"
           ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  /* Table with the sum of the ledger, historic_revenue,
     historic_losses and the auditor_reserve_balance.
     This is the final amount that the exchange should have
     in its bank account right now. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS predicted_result"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",balance_val INT8 NOT NULL"
           ",balance_frac INT4 NOT NULL"
           ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");


  SQLEXEC_INDEX("CREATE INDEX testx "
                "ON test(test_pub)");
#undef SQLEXEC
#undef SQLEXEC_INDEX

  PQfinish (conn);
  return GNUNET_OK;

 SQLEXEC_fail:
  PQfinish (conn);
  return GNUNET_SYSERR;
}


/**
 * Setup prepared statements.
 *
 * @param db_conn connection handle to initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
postgres_prepare (PGconn *db_conn)
{
  PGresult *result;

#define PREPARE(name, sql, ...)                                 \
  do {                                                          \
    result = PQprepare (db_conn, name, sql, __VA_ARGS__);       \
    if (PGRES_COMMAND_OK != PQresultStatus (result))            \
    {                                                           \
      BREAK_DB_ERR (result);                                    \
      PQclear (result); result = NULL;                          \
      return GNUNET_SYSERR;                                     \
    }                                                           \
    PQclear (result); result = NULL;                            \
  } while (0);

  /* Used in #postgres_XXX() */
  PREPARE ("test_insert",
           "INSERT INTO test "
           "(test_pub"
           ") VALUES "
           "($1);",
           1, NULL);
  return GNUNET_OK;
#undef PREPARE
}


/**
 * Close thread-local database connection when a thread is destroyed.
 *
 * @param cls closure we get from pthreads (the db handle)
 */
static void
db_conn_destroy (void *cls)
{
  struct TALER_AUDITORDB_Session *session = cls;
  PGconn *db_conn = session->conn;

  if (NULL != db_conn)
    PQfinish (db_conn);
  GNUNET_free (session);
}


/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return the database connection, or NULL on error
 */
static struct TALER_AUDITORDB_Session *
postgres_get_session (void *cls)
{
  struct PostgresClosure *pc = cls;
  PGconn *db_conn;
  struct TALER_AUDITORDB_Session *session;

  if (NULL != (session = pthread_getspecific (pc->db_conn_threadlocal)))
    return session;
  db_conn = connect_to_postgres (pc);
  if (NULL == db_conn)
    return NULL;
  if (GNUNET_OK !=
      postgres_prepare (db_conn))
  {
    GNUNET_break (0);
    PQfinish (db_conn);
    return NULL;
  }
  session = GNUNET_new (struct TALER_AUDITORDB_Session);
  session->conn = db_conn;
  if (0 != pthread_setspecific (pc->db_conn_threadlocal,
                                session))
  {
    GNUNET_break (0);
    PQfinish (db_conn);
    GNUNET_free (session);
    return NULL;
  }
  return session;
}


/**
 * Start a transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @return #GNUNET_OK on success
 */
static int
postgres_start (void *cls,
                struct TALER_AUDITORDB_Session *session)
{
  PGresult *result;

  result = PQexec (session->conn,
                   "START TRANSACTION ISOLATION LEVEL SERIALIZABLE");
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    TALER_LOG_ERROR ("Failed to start transaction: %s\n",
               PQresultErrorMessage (result));
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @return #GNUNET_OK on success
 */
static void
postgres_rollback (void *cls,
                   struct TALER_AUDITORDB_Session *session)
{
  PGresult *result;

  result = PQexec (session->conn,
                   "ROLLBACK");
  GNUNET_break (PGRES_COMMAND_OK ==
                PQresultStatus (result));
  PQclear (result);
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @return #GNUNET_OK on success
 */
static int
postgres_commit (void *cls,
                 struct TALER_AUDITORDB_Session *session)
{
  PGresult *result;

  result = PQexec (session->conn,
                   "COMMIT");
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    const char *sqlstate;

    sqlstate = PQresultErrorField (result,
                                   PG_DIAG_SQLSTATE);
    if (NULL == sqlstate)
    {
      /* very unexpected... */
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    /* 40P01: deadlock, 40001: serialization failure */
    if ( (0 == strcmp (sqlstate,
                       "40P01")) ||
         (0 == strcmp (sqlstate,
                       "40001")) )
    {
      /* These two can be retried and have a fair chance of working
         the next time */
      PQclear (result);
      return GNUNET_NO;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Database commit failure: %s\n",
                sqlstate);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Function called to perform "garbage collection" on the
 * database, expiring records we no longer require.
 *
 * @param cls closure
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_gc (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_PQ_QueryParam params_time[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  PGconn *conn;
  PGresult *result;

  now = GNUNET_TIME_absolute_get ();
  conn = connect_to_postgres (pc);
  if (NULL == conn)
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      postgres_prepare (conn))
  {
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  result = GNUNET_PQ_exec_prepared (conn,
                                    "gc_auditor",
                                    params_time);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  PQfinish (conn);
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
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_AUDITORDB_Plugin *plugin;
  const char *ec;

  pg = GNUNET_new (struct PostgresClosure);

  if (0 != pthread_key_create (&pg->db_conn_threadlocal,
                               &db_conn_destroy))
  {
    TALER_LOG_ERROR ("Cannnot create pthread key.\n");
    GNUNET_free (pg);
    return NULL;
  }
  ec = getenv ("TALER_AUDITORDB_POSTGRES_CONFIG");
  if (NULL != ec)
  {
    pg->connection_cfg_str = GNUNET_strdup (ec);
  }
  else
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "auditordb-postgres",
                                               "db_conn_str",
                                               &pg->connection_cfg_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "auditordb-postgres",
                                 "db_conn_str");
      GNUNET_free (pg);
      return NULL;
    }
  }
  plugin = GNUNET_new (struct TALER_AUDITORDB_Plugin);
  plugin->cls = pg;
  plugin->get_session = &postgres_get_session;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->rollback = &postgres_rollback;
  plugin->gc = &postgres_gc;
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

  GNUNET_free (pg->connection_cfg_str);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_auditordb_postgres.c */
