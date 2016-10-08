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

  /* Table indicating up to which transactions the auditor has
     processed the exchange database.  Used for SELECTing the
     statements to process.  We basically trace the exchange's
     operations by the 6 primary tables: reserves_in,
     reserves_out, deposits, refresh_sessions, refunds and prewire. The
     other tables of the exchange DB just provide supporting
     evidence which is checked alongside the audit of these
     five tables.  The 6 indices below include the last serial
     ID from the respective tables that we have processed. Thus,
     we need to select those table entries that are strictly
     larger (and process in monotonically increasing order). */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS auditor_progress"
	   "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
	   ",last_reserve_in_serial_id INT8 NOT NULL"
           ",last_reserve_out_serial_id INT8 NOT NULL"
	   ",last_deposit_serial_id INT8 NOT NULL"
           ",last_melt_serial_id INT8 NOT NULL"
	   ",last_refund_serial_id INT8 NOT NULL"
	   ",last_prewire_serial_id INT8 NOT NULL"
	   ")");

  /* Table with all of the customer reserves and their respective
     balances that the auditor is aware of.
     "last_reserve_out_serial_id" marks the last withdrawal from
     "reserves_out" about this reserve that the auditor is aware of,
     and "last_reserve_in_serial_id" is the last "reserve_in"
     operation about this reserve that the auditor is aware of. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS auditor_reserves"
	   "(reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)"
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

  SQLEXEC_INDEX("CREATE INDEX auditor_reserves_by_reserve_pub "
                "ON auditor_reserves(reserve_pub)");

  /* Table with the sum of the balances of all customer reserves
     (by exchange's master public key) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS auditor_reserve_balance"
	   "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
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
	   "(denom_pub_hash BYTEA PRIMARY KEY REFERENCES denominations (denom_pub_hash) ON DELETE CASCADE"
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
           ",last_reserve_out_serial_id INT8 NOT NULL"
           ",last_deposit_serial_id INT8 NOT NULL"
	   ",last_melt_serial_id INT8 NOT NULL"
	   ",last_refund_serial_id INT8 NOT NULL"
	   ")");

  /* Table with the sum of the outstanding coins from
     "denomination_pending" (denom_pubs must belong to the
     respective's exchange's master public key); it represents the
     total_liabilities of the exchange at this point (modulo
     unexpected historic_loss-style events where denomination keys are
     compromised) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS total_liabilities"
	   "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
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
	   ")");

  /* Table with the sum of the generated coins all denomination keys.
     This represents the maximum additional total financial risk of
     the exchange in case that all denomination keys are compromised
     (and all of the deposits so far were done by the successful
     attacker).  So this is strictly an upper bound on the risk
     exposure of the exchange.  (Note that this risk is in addition to
     the known total_liabilities.) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS total_risk"
	   "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
	   ",risk_val INT8 NOT NULL"
           ",risk_frac INT4 NOT NULL"
           ",risk_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");


  /* Table with historic profits; basically, when a denom_pub has
     expired and everything associated with it is garbage collected,
     the final profits end up in here; note that the "denom_pub" here
     is not a foreign key, we just keep it as a reference point.
     "revenue_balance" is the sum of all of the profits we made on the
     coin except for withdraw fees (which are in
     historic_reserve_revenue); the deposit, melt and refund fees are given
     individually; the delta to the revenue_balance is from coins that
     were withdrawn but never deposited prior to expiration. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_denomination_revenue"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)"
	   ",revenue_timestamp INT8 NOT NULL"
	   ",revenue_balance_val INT8 NOT NULL"
           ",revenue_balance_frac INT4 NOT NULL"
           ",revenue_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",deposit_fee_balance_val INT8 NOT NULL"
           ",deposit_fee_balance_frac INT4 NOT NULL"
           ",deposit_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",melt_fee_balance_val INT8 NOT NULL"
           ",melt_fee_balance_frac INT4 NOT NULL"
           ",melt_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",refund_fee_balance_val INT8 NOT NULL"
           ",refund_fee_balance_frac INT4 NOT NULL"
           ",refund_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"	   ")");


  /* Table with historic losses; basically, when we need to
     invalidate a denom_pub because the denom_priv was
     compromised, we incur a loss. These losses are totaled
     up here. (NOTE: the 'bankrupcy' protocol is not yet
     implemented, so right now this table is not used.)  */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_losses"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)"
	   ",loss_timestamp INT8 NOT NULL"
	   ",loss_balance_val INT8 NOT NULL"
           ",loss_balance_frac INT4 NOT NULL"
           ",loss_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
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

  SQLEXEC_INDEX("CREATE INDEX historic_reserve_summary_by_master_pub_start_date"
                " ON historic_ledger(master_pub,start_date)");


  /* Table with historic business ledger; basically, when the exchange
     operator decides to use operating costs for anything but wire
     transfers to merchants, it goes in here.  This happens when the
     operator users transaction fees for business expenses. "purpose"
     is free-form but should be a human-readable wire transfer
     identifier.   This is NOT yet used and outside of the scope of
     the core auditing logic. However, once we do take fees to use
     operating costs, and if we still want "predicted_result" to match
     the tables overall, we'll need a command-line tool to insert rows
     into this table and update "predicted_result" accordingly.
     (So this table for now just exists as a reminder of what we'll
     need in the long term.) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS historic_ledger"
	   "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
	   ",purpose VARCHAR NOT NULL"
	   ",timestamp INT8 NOT NULL"
	   ",balance_val INT8 NOT NULL"
           ",balance_frac INT4 NOT NULL"
           ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");

  SQLEXEC_INDEX("CREATE INDEX history_ledger_by_master_pub_and_time "
                "ON historic_ledger(master_pub,timestamp)");

  /* Table with the sum of the ledger, historic_revenue,
     historic_losses and the auditor_reserve_balance.  This is the
     final amount that the exchange should have in its bank account
     right now. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS predicted_result"
	   "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
	   ",balance_val INT8 NOT NULL"
           ",balance_frac INT4 NOT NULL"
           ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
	   ")");


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
  /* FIXME: this is obviously not going to be this easy... */
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
 * Insert information about a denomination key and in particular
 * the properties (value, fees, expiration times) the coins signed
 * with this key have.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param issue issuing information with value, fees and other info about the denomination
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_denomination_info (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_DenominationKeyValidityPS *issue)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get information about denomination keys of a particular exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_select_denomination_info (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   void *cb, /* FIXME: type! */
                                   void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about a reserve.  There must not be an
 * existing record for the reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param expiration_date expiration date of the reserve
 * @param last_reserve_in_serial_id up to which point did we consider
 *                 incoming transfers for the above information
 * @param last_reserve_out_serial_id up to which point did we consider
 *                 withdrawals for the above information
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_reserve_info (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *reserve_balance,
                              const struct TALER_Amount *withdraw_fee_balance,
                              struct GNUNET_TIME_Absolute expiration_date,
                              uint64_t last_reserve_in_serial_id,
                              uint64_t last_reserve_out_serial_id)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Update information about a reserve.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param expiration_date expiration date of the reserve
 * @param last_reserve_in_serial_id up to which point did we consider
 *                 incoming transfers for the above information
 * @param last_reserve_out_serial_id up to which point did we consider
 *                 withdrawals for the above information
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_update_reserve_info (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *reserve_balance,
                              const struct TALER_Amount *withdraw_fee_balance,
                              struct GNUNET_TIME_Absolute expiration_date,
                              uint64_t last_reserve_in_serial_id,
                              uint64_t last_reserve_out_serial_id)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get information about a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param[out] reserve_balance amount stored in the reserve
 * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param[out] expiration_date expiration date of the reserve
 * @param[out] last_reserve_in_serial_id up to which point did we consider
 *                 incoming transfers for the above information
 * @param[out] last_reserve_out_serial_id up to which point did we consider
 *                 withdrawals for the above information
 * @return #GNUNET_OK on success; #GNUNET_NO if there is no known
 *         record about this reserve; #GNUNET_SYSERR on failure
 */
static int
postgres_get_reserve_info (void *cls,
                           struct TALER_AUDITORDB_Session *session,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           struct TALER_Amount *reserve_balance,
                           struct TALER_Amount *withdraw_fee_balance,
                           struct GNUNET_TIME_Absolute *expiration_date,
                           uint64_t *last_reserve_in_serial_id,
                           uint64_t *last_reserve_out_serial_id)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about all reserves.  There must not be an
 * existing record for the @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_reserve_summary (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *reserve_balance,
                                 const struct TALER_Amount *withdraw_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Update information about all reserves.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param reserve_balance amount stored in the reserve
 * @param withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_update_reserve_summary (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *reserve_balance,
                                 const struct TALER_Amount *withdraw_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get summary information about all reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param[out] reserve_balance amount stored in the reserve
 * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @return #GNUNET_OK on success; #GNUNET_NO if there is no known
 *         record about this exchange; #GNUNET_SYSERR on failure
 */
static int
postgres_get_reserve_summary (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *reserve_balance,
                              struct TALER_Amount *withdraw_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about a denomination key's balances.  There
 * must not be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the denomination public key
 * @param denom_balance value of coins outstanding with this denomination key
 * @param deposit_fee_balance total deposit fees collected for this DK
 * @param melt_fee_balance total melt fees collected for this DK
 * @param refund_fee_balance total refund fees collected for this DK
 * @param last_reserve_out_serial_id up to which point did we consider
 *                 withdrawals for the above information
 * @param last_deposit_serial_id up to which point did we consider
 *                 deposits for the above information
 * @param last_melt_serial_id up to which point did we consider
 *                 melts for the above information
 * @param last_refund_serial_id up to which point did we consider
 *                 refunds for the above information
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_denomination_balance (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct GNUNET_HashCode *denom_pub_hash,
                                      const struct TALER_Amount *denom_balance,
                                      const struct TALER_Amount *deposit_fee_balance,
                                      const struct TALER_Amount *melt_fee_balance,
                                      const struct TALER_Amount *refund_fee_balance,
                                      uint64_t last_reserve_out_serial_id,
                                      uint64_t last_deposit_serial_id,
                                      uint64_t last_melt_serial_id,
                                      uint64_t last_refund_serial_id)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Update information about a denomination key's balances.  There
 * must be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the denomination public key
 * @param denom_balance value of coins outstanding with this denomination key
 * @param deposit_fee_balance total deposit fees collected for this DK
 * @param melt_fee_balance total melt fees collected for this DK
 * @param refund_fee_balance total refund fees collected for this DK
 * @param last_reserve_out_serial_id up to which point did we consider
 *                 withdrawals for the above information
 * @param last_deposit_serial_id up to which point did we consider
 *                 deposits for the above information
 * @param last_melt_serial_id up to which point did we consider
 *                 melts for the above information
 * @param last_refund_serial_id up to which point did we consider
 *                 refunds for the above information
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_update_denomination_balance (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct GNUNET_HashCode *denom_pub_hash,
                                      const struct TALER_Amount *denom_balance,
                                      const struct TALER_Amount *deposit_fee_balance,
                                      const struct TALER_Amount *melt_fee_balance,
                                      const struct TALER_Amount *refund_fee_balance,
                                      uint64_t last_reserve_out_serial_id,
                                      uint64_t last_deposit_serial_id,
                                      uint64_t last_melt_serial_id,
                                      uint64_t last_refund_serial_id)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get information about a denomination key's balances.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the denomination public key
 * @param[out] denom_balance value of coins outstanding with this denomination key
 * @param[out] deposit_fee_balance total deposit fees collected for this DK
 * @param[out] melt_fee_balance total melt fees collected for this DK
 * @param[out] refund_fee_balance total refund fees collected for this DK
 * @param[out] last_reserve_out_serial_id up to which point did we consider
 *                 withdrawals for the above information
 * @param[out] last_deposit_serial_id up to which point did we consider
 *                 deposits for the above information
 * @param[out] last_melt_serial_id up to which point did we consider
 *                 melts for the above information
 * @param[out] last_refund_serial_id up to which point did we consider
 *                 refunds for the above information
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_get_denomination_balance (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct GNUNET_HashCode *denom_pub_hash,
                                   struct TALER_Amount *denom_balance,
                                   struct TALER_Amount *deposit_fee_balance,
                                   struct TALER_Amount *melt_fee_balance,
                                   struct TALER_Amount *refund_fee_balance,
                                   uint64_t *last_reserve_out_serial_id,
                                   uint64_t *last_deposit_serial_id,
                                   uint64_t *last_melt_serial_id,
                                   uint64_t *last_refund_serial_id)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about an exchange's denomination balances.  There
 * must not be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param denom_balance value of coins outstanding with this denomination key
 * @param deposit_fee_balance total deposit fees collected for this DK
 * @param melt_fee_balance total melt fees collected for this DK
 * @param refund_fee_balance total refund fees collected for this DK
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_denomination_summary (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct TALER_MasterPublicKeyP *master_pub,
                                      const struct TALER_Amount *denom_balance,
                                      const struct TALER_Amount *deposit_fee_balance,
                                      const struct TALER_Amount *melt_fee_balance,
                                      const struct TALER_Amount *refund_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Update information about an exchange's denomination balances.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param denom_balance value of coins outstanding with this denomination key
 * @param deposit_fee_balance total deposit fees collected for this DK
 * @param melt_fee_balance total melt fees collected for this DK
 * @param refund_fee_balance total refund fees collected for this DK
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_update_denomination_summary (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct TALER_MasterPublicKeyP *master_pub,
                                      const struct TALER_Amount *denom_balance,
                                      const struct TALER_Amount *deposit_fee_balance,
                                      const struct TALER_Amount *melt_fee_balance,
                                      const struct TALER_Amount *refund_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get information about an exchange's denomination balances.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] denom_balance value of coins outstanding with this denomination key
 * @param[out] deposit_fee_balance total deposit fees collected for this DK
 * @param[out] melt_fee_balance total melt fees collected for this DK
 * @param[out] refund_fee_balance total refund fees collected for this DK
 * @return #GNUNET_OK on success; #GNUNET_NO if there is no entry
 *           for this @a master_pub; #GNUNET_SYSERR on failure
 */
static int
postgres_get_denomination_summary (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   struct TALER_Amount *denom_balance,
                                   struct TALER_Amount *deposit_fee_balance,
                                   struct TALER_Amount *melt_fee_balance,
                                   struct TALER_Amount *refund_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about an exchange's risk exposure.  There
 * must not be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param risk maximum risk exposure of the exchange
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_risk_summary (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *risk)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Update information about an exchange's risk exposure.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param risk maximum risk exposure of the exchange
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_update_risk_summary (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *risk)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get information about an exchange's risk exposure.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] risk maximum risk exposure of the exchange
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure;
 *         #GNUNET_NO if we have no records for the @a master_pub
 */
static int
postgres_get_risk_summary (void *cls,
                           struct TALER_AUDITORDB_Session *session,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           struct TALER_Amount *risk)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about an exchange's historic
 * revenue about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param denom_pub_hash hash of the denomination key
 * @param revenue_timestamp when did this profit get realized
 * @param revenue_balance what was the total profit made from
 *                        deposit fees, melting fees, refresh fees
 *                        and coins that were never returned?
 * @param deposit_fee_balance total profits from deposit fees
 * @param melt_fee_balance total profits from melting fees
 * @param refund_fee_balance total profits from refund fees
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_historic_denom_revenue (void *cls,
                                        struct TALER_AUDITORDB_Session *session,
                                        const struct TALER_MasterPublicKeyP *master_pub,
                                        const struct GNUNET_HashCode *denom_pub_hash,
                                        struct GNUNET_TIME_Absolute revenue_timestamp,
                                        const struct TALER_Amount *revenue_balance,
                                        const struct TALER_Amount *deposit_fee_balance,
                                        const struct TALER_Amount *melt_fee_balance,
                                        const struct TALER_Amount *refund_fee_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Obtain all of the historic denomination key revenue
 * of the given @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
postgres_select_historic_denom_revenue (void *cls,
                                        struct TALER_AUDITORDB_Session *session,
                                        const struct TALER_MasterPublicKeyP *master_pub,
                                        void *cb, /* FIXME: fix type */
                                        void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about an exchange's historic
 * losses (from compromised denomination keys).
 *
 * Note yet used, need to implement exchange's bankrupcy
 * protocol (and tables!) first.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param denom_pub_hash hash of the denomination key
 * @param loss_timestamp when did this profit get realized
 * @param loss_balance what was the total loss
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_historic_losses (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 struct GNUNET_TIME_Absolute loss_timestamp,
                                 const struct TALER_Amount *loss_balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Obtain all of the historic denomination key losses
 * of the given @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
postgres_select_historic_losses (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 void *cb, /* FIXME: fix type */
                                 void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about an exchange's historic revenue from reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param start_time beginning of aggregated time interval
 * @param end_time end of aggregated time interval
 * @param reserve_profits total profits made
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_historic_reserve_revenue (void *cls,
                                          struct TALER_AUDITORDB_Session *session,
                                          const struct TALER_MasterPublicKeyP *master_pub,
                                          struct GNUNET_TIME_Absolute start_time,
                                          struct GNUNET_TIME_Absolute end_time,
                                          const struct TALER_Amount *reserve_profits)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Return information about an exchange's historic revenue from reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_select_historic_reserve_revenue (void *cls,
                                          struct TALER_AUDITORDB_Session *session,
                                          const struct TALER_MasterPublicKeyP *master_pub,
                                          void *cb, /* FIXME: type */
                                          void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Insert information about the predicted exchange's bank
 * account balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_predicted_result (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_Amount *balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Update information about an exchange's predicted balance.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_update_predicted_result (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_Amount *balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Get an exchange's predicted balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] balance expected bank account balance of the exchange
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure;
 *         #GNUNET_NO if we have no records for the @a master_pub
 */
static int
postgres_get_predicted_balance (void *cls,
                                struct TALER_AUDITORDB_Session *session,
                                const struct TALER_MasterPublicKeyP *master_pub,
                                struct TALER_Amount *balance)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
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
  plugin->get_predicted_balance = &postgres_get_predicted_balance;
  plugin->update_predicted_result = &postgres_update_predicted_result;
  plugin->insert_predicted_result = &postgres_insert_predicted_result;
  plugin->select_historic_reserve_revenue = &postgres_select_historic_reserve_revenue;
  plugin->insert_historic_reserve_revenue = &postgres_insert_historic_reserve_revenue;
  plugin->select_historic_losses = &postgres_select_historic_losses;
  plugin->insert_historic_losses = &postgres_insert_historic_losses;
  plugin->select_historic_denom_revenue = &postgres_select_historic_denom_revenue;
  plugin->insert_historic_denom_revenue = &postgres_insert_historic_denom_revenue;
  plugin->get_risk_summary = &postgres_get_risk_summary;
  plugin->update_risk_summary = &postgres_update_risk_summary;
  plugin->insert_risk_summary = &postgres_insert_risk_summary;
  plugin->get_denomination_summary = &postgres_get_denomination_summary;
  plugin->update_denomination_summary = &postgres_update_denomination_summary;
  plugin->insert_denomination_summary = &postgres_insert_denomination_summary;
  plugin->get_denomination_balance = &postgres_get_denomination_balance;
  plugin->update_denomination_balance = &postgres_update_denomination_balance;
  plugin->insert_denomination_balance = &postgres_insert_denomination_balance;
  plugin->get_reserve_summary = &postgres_get_reserve_summary;
  plugin->update_reserve_summary = &postgres_update_reserve_summary;
  plugin->insert_reserve_summary = &postgres_insert_reserve_summary;
  plugin->get_reserve_info = &postgres_get_reserve_info;
  plugin->update_reserve_info = &postgres_update_reserve_info;
  plugin->insert_reserve_info = &postgres_insert_reserve_info;
  plugin->select_denomination_info = &postgres_select_denomination_info;
  plugin->insert_denomination_info = &postgres_insert_denomination_info;

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
