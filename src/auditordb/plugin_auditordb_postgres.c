/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
#include "taler_auditordb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>


#define LOG(kind,...) GNUNET_log_from (kind, "taler-auditordb-postgres", __VA_ARGS__)


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
  LOG (GNUNET_ERROR_TYPE_INFO,
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
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_predicted_result;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_historic_ledger;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_historic_losses;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_historic_denomination_revenue;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_balance_summary;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_denomination_pending;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_reserve_balance;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_wire_fee_balance;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_reserves;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_progress_reserve;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_progress_aggregation;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_progress_deposit_confirmation;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS auditor_progress_coin;"),
    GNUNET_PQ_make_execute ("DROP TABLE IF EXISTS wire_auditor_progress;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  PGconn *conn;
  int ret;

  conn = connect_to_postgres (pc);
  if (NULL == conn)
    return GNUNET_SYSERR;
  LOG (GNUNET_ERROR_TYPE_INFO,
       "Dropping ALL tables\n");
  ret = GNUNET_PQ_exec_statements (conn,
                                   es);
  /* TODO: we probably need a bit more fine-grained control
     over drops for the '-r' option of taler-auditor; also,
     for the testcase, we currently fail to drop the
     auditor_denominations table... */
  PQfinish (conn);
  return ret;
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
  struct GNUNET_PQ_ExecuteStatement es[] = {
    /* Table with list of exchanges we are auditing */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_exchanges"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",exchange_url VARCHAR NOT NULL"
			    ")"),
    /* Table with list of signing keys of exchanges we are auditing */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_exchange_signkeys"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",ep_start INT8 NOT NULL"
			    ",ep_expire INT8 NOT NULL"
			    ",ep_end INT8 NOT NULL"
			    ",exchange_pub BYTEA NOT NULL CHECK (LENGTH(exchange_pub)=32)"
			    ",master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)"
			    ")"),
    /* Table with all of the denomination keys that the auditor
       is aware of. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_denominations"
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
			    ")"),
    /* List of exchanges audited by this auditor */
    // TODO: not yet used!
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS exchanges"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",exchange_url VARCHAR NOT NULL"
			    ")"),

    /* Table indicating up to which transactions the auditor has
       processed the exchange database.  Used for SELECTing the
       statements to process.  The indices below include the last
       serial ID from the respective tables that we have
       processed. Thus, we need to select those table entries that are
       strictly larger (and process in monotonically increasing
       order). */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_progress_reserve"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",last_reserve_in_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_reserve_out_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_reserve_payback_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_reserve_close_serial_id INT8 NOT NULL DEFAULT 0"
			    ")"),
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_progress_aggregation"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",last_wire_out_serial_id INT8 NOT NULL DEFAULT 0"
			    ")"),
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_progress_deposit_confirmation"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",last_deposit_confirmation_serial_id INT8 NOT NULL DEFAULT 0"
			    ")"),
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_progress_coin"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",last_withdraw_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_deposit_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_melt_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_refund_serial_id INT8 NOT NULL DEFAULT 0"
			    ")"),
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS wire_auditor_progress"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
                            ",account_name TEXT NOT NULL"
			    ",last_wire_reserve_in_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_wire_wire_out_serial_id INT8 NOT NULL DEFAULT 0"
			    ",last_timestamp INT8 NOT NULL"
                            ",wire_in_off BYTEA"
                            ",wire_out_off BYTEA"
			    ")"),
    /* Table with all of the customer reserves and their respective
       balances that the auditor is aware of.
       "last_reserve_out_serial_id" marks the last withdrawal from
       "reserves_out" about this reserve that the auditor is aware of,
       and "last_reserve_in_serial_id" is the last "reserve_in"
       operation about this reserve that the auditor is aware of. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_reserves"
			    "(reserve_pub BYTEA NOT NULL CHECK(LENGTH(reserve_pub)=32)"
			    ",master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
			    ",reserve_balance_val INT8 NOT NULL"
			    ",reserve_balance_frac INT4 NOT NULL"
			    ",reserve_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ",withdraw_fee_balance_val INT8 NOT NULL"
			    ",withdraw_fee_balance_frac INT4 NOT NULL"
			    ",withdraw_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ",expiration_date INT8 NOT NULL"
			    ",auditor_reserves_rowid BIGSERIAL UNIQUE"
			    ")"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX auditor_reserves_by_reserve_pub "
				"ON auditor_reserves(reserve_pub)"),
    /* Table with the sum of the balances of all customer reserves
       (by exchange's master public key) */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_reserve_balance"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",reserve_balance_val INT8 NOT NULL"
			    ",reserve_balance_frac INT4 NOT NULL"
			    ",reserve_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ",withdraw_fee_balance_val INT8 NOT NULL"
			    ",withdraw_fee_balance_frac INT4 NOT NULL"
			    ",withdraw_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    /* Table with the sum of the balances of all wire fees
       (by exchange's master public key) */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_wire_fee_balance"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",wire_fee_balance_val INT8 NOT NULL"
			    ",wire_fee_balance_frac INT4 NOT NULL"
			    ",wire_fee_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    /* Table with all of the outstanding denomination coins that the
       exchange is aware of and what the respective balances are
       (outstanding as well as issued overall which implies the
       maximum value at risk).  We also count the number of coins
       issued (withdraw, refresh-reveal) and the number of coins seen
       at the exchange (refresh-commit, deposit), not just the amounts. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_denomination_pending"
			    "(denom_pub_hash BYTEA PRIMARY KEY"
			    " REFERENCES auditor_denominations (denom_pub_hash) ON DELETE CASCADE"
			    ",denom_balance_val INT8 NOT NULL"
			    ",denom_balance_frac INT4 NOT NULL"
			    ",denom_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ",num_issued INT8 NOT NULL"
			    ",denom_risk_val INT8 NOT NULL"
			    ",denom_risk_frac INT4 NOT NULL"
			    ",denom_risk_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    /* Table with the sum of the outstanding coins from
       "auditor_denomination_pending" (denom_pubs must belong to the
       respective's exchange's master public key); it represents the
       auditor_balance_summary of the exchange at this point (modulo
       unexpected historic_loss-style events where denomination keys are
       compromised) */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_balance_summary"
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
			    ",risk_val INT8 NOT NULL"
			    ",risk_frac INT4 NOT NULL"
			    ",risk_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    /* Table with historic profits; basically, when a denom_pub has
       expired and everything associated with it is garbage collected,
       the final profits end up in here; note that the "denom_pub" here
       is not a foreign key, we just keep it as a reference point.
       "revenue_balance" is the sum of all of the profits we made on the
       coin except for withdraw fees (which are in
       historic_reserve_revenue); the deposit, melt and refund fees are given
       individually; the delta to the revenue_balance is from coins that
       were withdrawn but never deposited prior to expiration. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_historic_denomination_revenue"
			    "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
			    ",denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)"
			    ",revenue_timestamp INT8 NOT NULL"
			    ",revenue_balance_val INT8 NOT NULL"
			    ",revenue_balance_frac INT4 NOT NULL"
			    ",revenue_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    /* Table with historic losses; basically, when we need to
       invalidate a denom_pub because the denom_priv was
       compromised, we incur a loss. These losses are totaled
       up here. (NOTE: the 'bankrupcy' protocol is not yet
       implemented, so right now this table is not used.)  */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_historic_losses"
			    "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
			    ",denom_pub_hash BYTEA PRIMARY KEY CHECK (LENGTH(denom_pub_hash)=64)"
			    ",loss_timestamp INT8 NOT NULL"
			    ",loss_balance_val INT8 NOT NULL"
			    ",loss_balance_frac INT4 NOT NULL"
			    ",loss_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    /* Table with historic profits from reserves; we eventually
       GC "auditor_historic_reserve_revenue", and then store the totals
       in here (by time intervals). */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_historic_reserve_summary"
			    "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
			    ",start_date INT8 NOT NULL"
			    ",end_date INT8 NOT NULL"
			    ",reserve_profits_val INT8 NOT NULL"
			    ",reserve_profits_frac INT4 NOT NULL"
			    ",reserve_profits_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX auditor_historic_reserve_summary_by_master_pub_start_date "
				"ON auditor_historic_reserve_summary(master_pub,start_date)"),

    /* Table with deposit confirmation sent to us by merchants;
       we must check that the exchange reported these properly. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS deposit_confirmations "
			    "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
			    ",h_contract_terms BYTEA CHECK (LENGTH(h_contract_terms)=64)"
                            ",h_wire BYTEA CHECK (LENGTH(h_wire)=64)"
			    ",timestamp INT8 NOT NULL"
			    ",refund_deadline INT8 NOT NULL"
			    ",amount_without_fee_val INT8 NOT NULL"
			    ",amount_without_fee_frac INT4 NOT NULL"
			    ",amount_without_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
                            ",coin_pub BYTEA CHECK (LENGTH(coin_pub)=32)"
                            ",merchant_pub BYTEA CHECK (LENGTH(merchant_pub)=32)"
                            ",exchange_sig BYTEA CHECK (LENGTH(exchange_sig)=64)"
                            ",exchange_pub BYTEA CHECK (LENGTH(exchange_pub)=32)"
                            ",master_sig BYTEA CHECK (LENGTH(master_sig)=64)"
                            ",PRIMARY KEY (h_contract_terms, h_wire, coin_pub, "
                            "  merchant_pub, exchange_sig, exchange_pub, master_sig)"
			    ")"),
    /* Table with historic business ledger; basically, when the exchange
       operator decides to use operating costs for anything but wire
       transfers to merchants, it goes in here.  This happens when the
       operator users transaction fees for business expenses. "purpose"
       is free-form but should be a human-readable wire transfer
       identifier.   This is NOT yet used and outside of the scope of
       the core auditing logic. However, once we do take fees to use
       operating costs, and if we still want "auditor_predicted_result" to match
       the tables overall, we'll need a command-line tool to insert rows
       into this table and update "auditor_predicted_result" accordingly.
       (So this table for now just exists as a reminder of what we'll
       need in the long term.) */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_historic_ledger"
			    "(master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
			    ",purpose VARCHAR NOT NULL"
			    ",timestamp INT8 NOT NULL"
			    ",balance_val INT8 NOT NULL"
			    ",balance_frac INT4 NOT NULL"
			    ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    GNUNET_PQ_make_try_execute ("CREATE INDEX history_ledger_by_master_pub_and_time "
				"ON auditor_historic_ledger(master_pub,timestamp)"),
    /* Table with the sum of the ledger, auditor_historic_revenue,
       auditor_historic_losses and the auditor_reserve_balance.  This is the
       final amount that the exchange should have in its bank account
       right now. */
    GNUNET_PQ_make_execute ("CREATE TABLE IF NOT EXISTS auditor_predicted_result"
			    "(master_pub BYTEA PRIMARY KEY CHECK (LENGTH(master_pub)=32)"
			    ",balance_val INT8 NOT NULL"
			    ",balance_frac INT4 NOT NULL"
			    ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
			    ")"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  PGconn *conn;
  int ret;

  conn = connect_to_postgres (pc);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_statements (conn,
                                   es);
  PQfinish (conn);
  return ret;
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
  struct GNUNET_PQ_PreparedStatement ps[] = {
    /* used in #postgres_commit */
    GNUNET_PQ_make_prepare ("do_commit",
                            "COMMIT",
                            0),
    /* used in #postgres_insert_exchange */
    GNUNET_PQ_make_prepare ("auditor_insert_exchange",
			    "INSERT INTO auditor_exchanges "
			    "(master_pub"
			    ",exchange_url"
			    ") VALUES ($1,$2);",
                            2),
    /* used in #postgres_delete_exchange */
    GNUNET_PQ_make_prepare ("auditor_delete_exchange",
			    "DELETE"
			    " FROM auditor_exchanges"
			    " WHERE master_pub=$1;",
                            1),
    /* used in #postgres_list_exchanges */
    GNUNET_PQ_make_prepare ("auditor_list_exchanges",
			    "SELECT"
			    " master_pub"
                            ",exchange_url"
			    " FROM auditor_exchanges",
                            0),
    /* used in #postgres_insert_exchange_signkey */
    GNUNET_PQ_make_prepare ("auditor_insert_exchange_signkey",
			    "INSERT INTO auditor_exchange_signkeys "
			    "(master_pub"
			    ",ep_start"
			    ",ep_expire"
			    ",ep_end"
			    ",exchange_pub"
                            ",master_sig"
			    ") VALUES ($1,$2,$3,$4,$5,$6);",
                            6),
    /* Used in #postgres_insert_denomination_info() */
    GNUNET_PQ_make_prepare ("auditor_denominations_insert",
			    "INSERT INTO auditor_denominations "
			    "(denom_pub_hash"
			    ",master_pub"
			    ",valid_from"
			    ",expire_withdraw"
			    ",expire_deposit"
			    ",expire_legal"
			    ",coin_val"
			    ",coin_frac"
			    ",coin_curr"
			    ",fee_withdraw_val"
			    ",fee_withdraw_frac"
			    ",fee_withdraw_curr"
			    ",fee_deposit_val"
			    ",fee_deposit_frac"
			    ",fee_deposit_curr"
			    ",fee_refresh_val"
			    ",fee_refresh_frac"
			    ",fee_refresh_curr"
			    ",fee_refund_val"
			    ",fee_refund_frac"
			    ",fee_refund_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21);",
			    21),
    /* Used in #postgres_insert_denomination_info() */
    GNUNET_PQ_make_prepare ("auditor_denominations_select",
			    "SELECT"
			    " denom_pub_hash"
			    ",valid_from"
			    ",expire_withdraw"
			    ",expire_deposit"
			    ",expire_legal"
			    ",coin_val"
			    ",coin_frac"
			    ",coin_curr"
			    ",fee_withdraw_val"
			    ",fee_withdraw_frac"
			    ",fee_withdraw_curr"
			    ",fee_deposit_val"
			    ",fee_deposit_frac"
			    ",fee_deposit_curr"
			    ",fee_refresh_val"
			    ",fee_refresh_frac"
			    ",fee_refresh_curr"
			    ",fee_refund_val"
			    ",fee_refund_frac"
			    ",fee_refund_curr"
			    " FROM auditor_denominations"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_deposit_confirmation_insert",
			    "INSERT INTO deposit_confirmations "
			    "(master_pub"
			    ",h_contract_terms"
			    ",h_wire"
			    ",timestamp"
			    ",refund_deadline"
			    ",amount_without_fee_val"
			    ",amount_without_fee_frac"
			    ",amount_without_fee_curr"
			    ",coin_pub"
			    ",merchant_pub"
			    ",exchange_sig"
			    ",exchange_pub"
			    ",master_sig" /* master_sig could be normalized... */
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);",
			    11),
    /* Used in #postgres_update_auditor_progress_reserve() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_reserve",
			    "UPDATE auditor_progress_reserve SET "
			    " last_reserve_in_serial_id=$1"
			    ",last_reserve_out_serial_id=$2"
			    ",last_reserve_payback_serial_id=$3"
			    ",last_reserve_close_serial_id=$4"
			    " WHERE master_pub=$5",
			    5),
    /* Used in #postgres_get_auditor_progress_reserve() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_reserve",
			    "SELECT"
			    " last_reserve_in_serial_id"
			    ",last_reserve_out_serial_id"
			    ",last_reserve_payback_serial_id"
			    ",last_reserve_close_serial_id"
			    " FROM auditor_progress_reserve"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_auditor_progress_reserve() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_reserve",
			    "INSERT INTO auditor_progress_reserve "
			    "(master_pub"
			    ",last_reserve_in_serial_id"
			    ",last_reserve_out_serial_id"
			    ",last_reserve_payback_serial_id"
			    ",last_reserve_close_serial_id"
			    ") VALUES ($1,$2,$3,$4,$5);",
			    5),
    /* Used in #postgres_update_auditor_progress_aggregation() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_aggregation",
			    "UPDATE auditor_progress_aggregation SET "
			    " last_wire_out_serial_id=$1"
			    " WHERE master_pub=$2",
			    2),
    /* Used in #postgres_get_auditor_progress_aggregation() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_aggregation",
			    "SELECT"
			    " last_wire_out_serial_id"
			    " FROM auditor_progress_aggregation"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_auditor_progress_aggregation() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_aggregation",
			    "INSERT INTO auditor_progress_aggregation "
			    "(master_pub"
			    ",last_wire_out_serial_id"
			    ") VALUES ($1,$2);",
			    2),
    /* Used in #postgres_update_auditor_progress_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_deposit_confirmation",
			    "UPDATE auditor_progress_deposit_confirmation SET "
			    " last_deposit_confirmation_serial_id=$1"
			    " WHERE master_pub=$2",
			    2),
    /* Used in #postgres_get_auditor_progress_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_deposit_confirmation",
			    "SELECT"
			    " last_deposit_confirmation_serial_id"
			    " FROM auditor_progress_deposit_confirmation"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_auditor_progress_deposit_confirmation() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_deposit_confirmation",
			    "INSERT INTO auditor_progress_deposit_confirmation "
			    "(master_pub"
			    ",last_deposit_confirmation_serial_id"
			    ") VALUES ($1,$2);",
			    2),
    /* Used in #postgres_update_auditor_progress_coin() */
    GNUNET_PQ_make_prepare ("auditor_progress_update_coin",
			    "UPDATE auditor_progress_coin SET "
			    " last_withdraw_serial_id=$1"
			    ",last_deposit_serial_id=$2"
			    ",last_melt_serial_id=$3"
			    ",last_refund_serial_id=$4"
			    " WHERE master_pub=$5",
			    4),
    /* Used in #postgres_get_auditor_progress_coin() */
    GNUNET_PQ_make_prepare ("auditor_progress_select_coin",
			    "SELECT"
			    " last_withdraw_serial_id"
			    ",last_deposit_serial_id"
			    ",last_melt_serial_id"
			    ",last_refund_serial_id"
			    " FROM auditor_progress_coin"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_auditor_progress() */
    GNUNET_PQ_make_prepare ("auditor_progress_insert_coin",
			    "INSERT INTO auditor_progress_coin "
			    "(master_pub"
			    ",last_withdraw_serial_id"
			    ",last_deposit_serial_id"
			    ",last_melt_serial_id"
			    ",last_refund_serial_id"
			    ") VALUES ($1,$2,$3,$4,$5);",
			    5),
    /* Used in #postgres_insert_wire_auditor_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_progress_insert",
			    "INSERT INTO wire_auditor_progress "
			    "(master_pub"
                            ",account_name"
			    ",last_wire_reserve_in_serial_id"
			    ",last_wire_wire_out_serial_id"
                            ",last_timestamp"
                            ",wire_in_off"
                            ",wire_out_off"
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7);",
			    7),
    /* Used in #postgres_update_wire_auditor_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_progress_update",
			    "UPDATE wire_auditor_progress SET "
			    " last_wire_reserve_in_serial_id=$1"
			    ",last_wire_wire_out_serial_id=$2"
                            ",last_timestamp=$3"
                            ",wire_in_off=$4"
                            ",wire_out_off=$5"
			    " WHERE master_pub=$6 AND account_name=$7",
			    7),
    /* Used in #postgres_get_wire_auditor_progress() */
    GNUNET_PQ_make_prepare ("wire_auditor_progress_select",
			    "SELECT"
			    " last_wire_reserve_in_serial_id"
			    ",last_wire_wire_out_serial_id"
                            ",last_timestamp"
                            ",wire_in_off"
                            ",wire_out_off"
			    " FROM wire_auditor_progress"
			    " WHERE master_pub=$1 AND account_name=$2;",
			    2),
    /* Used in #postgres_insert_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_insert",
			    "INSERT INTO auditor_reserves "
			    "(reserve_pub"
			    ",master_pub"
			    ",reserve_balance_val"
			    ",reserve_balance_frac"
			    ",reserve_balance_curr"
			    ",withdraw_fee_balance_val"
			    ",withdraw_fee_balance_frac"
			    ",withdraw_fee_balance_curr"
			    ",expiration_date"
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9);",
			    9),
    /* Used in #postgres_update_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_update",
			    "UPDATE auditor_reserves SET"
			    " reserve_balance_val=$1"
			    ",reserve_balance_frac=$2"
			    ",reserve_balance_curr=$3"
			    ",withdraw_fee_balance_val=$4"
			    ",withdraw_fee_balance_frac=$5"
			    ",withdraw_fee_balance_curr=$6"
			    ",expiration_date=$7"
			    " WHERE reserve_pub=$8 AND master_pub=$9;",
			    9),
    /* Used in #postgres_get_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_select",
			    "SELECT"
			    " reserve_balance_val"
			    ",reserve_balance_frac"
			    ",reserve_balance_curr"
			    ",withdraw_fee_balance_val"
			    ",withdraw_fee_balance_frac"
			    ",withdraw_fee_balance_curr"
			    ",expiration_date"
			    ",auditor_reserves_rowid"
			    " FROM auditor_reserves"
			    " WHERE reserve_pub=$1 AND master_pub=$2;",
			    2),
    /* Used in #postgres_del_reserve_info() */
    GNUNET_PQ_make_prepare ("auditor_reserves_delete",
			    "DELETE"
			    " FROM auditor_reserves"
			    " WHERE reserve_pub=$1 AND master_pub=$2;",
			    2),
    /* Used in #postgres_insert_reserve_summary() */
    GNUNET_PQ_make_prepare ("auditor_reserve_balance_insert",
			    "INSERT INTO auditor_reserve_balance"
			    "(master_pub"
			    ",reserve_balance_val"
			    ",reserve_balance_frac"
			    ",reserve_balance_curr"
			    ",withdraw_fee_balance_val"
			    ",withdraw_fee_balance_frac"
			    ",withdraw_fee_balance_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7)",
			    7),
    /* Used in #postgres_update_reserve_summary() */
    GNUNET_PQ_make_prepare ("auditor_reserve_balance_update",
			    "UPDATE auditor_reserve_balance SET"
			    " reserve_balance_val=$1"
			    ",reserve_balance_frac=$2"
			    ",reserve_balance_curr=$3"
			    ",withdraw_fee_balance_val=$4"
			    ",withdraw_fee_balance_frac=$5"
			    ",withdraw_fee_balance_curr=$6"
			    " WHERE master_pub=$7;",
			    7),
    /* Used in #postgres_get_reserve_summary() */
    GNUNET_PQ_make_prepare ("auditor_reserve_balance_select",
			    "SELECT"
			    " reserve_balance_val"
			    ",reserve_balance_frac"
			    ",reserve_balance_curr"
			    ",withdraw_fee_balance_val"
			    ",withdraw_fee_balance_frac"
			    ",withdraw_fee_balance_curr"
			    " FROM auditor_reserve_balance"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_wire_fee_summary() */
    GNUNET_PQ_make_prepare ("auditor_wire_fee_balance_insert",
			    "INSERT INTO auditor_wire_fee_balance"
			    "(master_pub"
			    ",wire_fee_balance_val"
			    ",wire_fee_balance_frac"
			    ",wire_fee_balance_curr"
			    ") VALUES ($1,$2,$3,$4)",
			    4),
    /* Used in #postgres_update_wire_fee_summary() */
    GNUNET_PQ_make_prepare ("auditor_wire_fee_balance_update",
			    "UPDATE auditor_wire_fee_balance SET"
			    " wire_fee_balance_val=$1"
			    ",wire_fee_balance_frac=$2"
			    ",wire_fee_balance_curr=$3"
			    " WHERE master_pub=$4;",
			    4),
    /* Used in #postgres_get_wire_fee_summary() */
    GNUNET_PQ_make_prepare ("auditor_wire_fee_balance_select",
			    "SELECT"
			    " wire_fee_balance_val"
			    ",wire_fee_balance_frac"
			    ",wire_fee_balance_curr"
			    " FROM auditor_wire_fee_balance"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_denomination_balance() */
    GNUNET_PQ_make_prepare ("auditor_denomination_pending_insert",
			    "INSERT INTO auditor_denomination_pending "
			    "(denom_pub_hash"
			    ",denom_balance_val"
			    ",denom_balance_frac"
			    ",denom_balance_curr"
                            ",num_issued"
			    ",denom_risk_val"
			    ",denom_risk_frac"
			    ",denom_risk_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8);",
			    8),
    /* Used in #postgres_update_denomination_balance() */
    GNUNET_PQ_make_prepare ("auditor_denomination_pending_update",
			    "UPDATE auditor_denomination_pending SET"
			    " denom_balance_val=$1"
			    ",denom_balance_frac=$2"
			    ",denom_balance_curr=$3"
                            ",num_issued=$4"
			    ",denom_risk_val=$5"
			    ",denom_risk_frac=$6"
			    ",denom_risk_curr=$7"
			    " WHERE denom_pub_hash=$8",
			    8),
    /* Used in #postgres_get_denomination_balance() */
    GNUNET_PQ_make_prepare ("auditor_denomination_pending_select",
			    "SELECT"
			    " denom_balance_val"
			    ",denom_balance_frac"
			    ",denom_balance_curr"
                            ",num_issued"
			    ",denom_risk_val"
			    ",denom_risk_frac"
			    ",denom_risk_curr"
			    " FROM auditor_denomination_pending"
			    " WHERE denom_pub_hash=$1",
			    1),
    /* Used in #postgres_insert_balance_summary() */
    GNUNET_PQ_make_prepare ("auditor_balance_summary_insert",
			    "INSERT INTO auditor_balance_summary "
			    "(master_pub"
			    ",denom_balance_val"
			    ",denom_balance_frac"
			    ",denom_balance_curr"
			    ",deposit_fee_balance_val"
			    ",deposit_fee_balance_frac"
			    ",deposit_fee_balance_curr"
			    ",melt_fee_balance_val"
			    ",melt_fee_balance_frac"
			    ",melt_fee_balance_curr"
			    ",refund_fee_balance_val"
			    ",refund_fee_balance_frac"
			    ",refund_fee_balance_curr"
			    ",risk_val"
			    ",risk_frac"
			    ",risk_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16);",
			    16),
    /* Used in #postgres_update_balance_summary() */
    GNUNET_PQ_make_prepare ("auditor_balance_summary_update",
			    "UPDATE auditor_balance_summary SET"
			    " denom_balance_val=$1"
			    ",denom_balance_frac=$2"
			    ",denom_balance_curr=$3"
			    ",deposit_fee_balance_val=$4"
			    ",deposit_fee_balance_frac=$5"
			    ",deposit_fee_balance_curr=$6"
			    ",melt_fee_balance_val=$7"
			    ",melt_fee_balance_frac=$8"
			    ",melt_fee_balance_curr=$9"
			    ",refund_fee_balance_val=$10"
			    ",refund_fee_balance_frac=$11"
			    ",refund_fee_balance_curr=$12"
			    ",risk_val=$13"
			    ",risk_frac=$14"
			    ",risk_curr=$15"
			    " WHERE master_pub=$16;",
			    16),
    /* Used in #postgres_get_balance_summary() */
    GNUNET_PQ_make_prepare ("auditor_balance_summary_select",
			    "SELECT"
			    " denom_balance_val"
			    ",denom_balance_frac"
			    ",denom_balance_curr"
			    ",deposit_fee_balance_val"
			    ",deposit_fee_balance_frac"
			    ",deposit_fee_balance_curr"
			    ",melt_fee_balance_val"
			    ",melt_fee_balance_frac"
			    ",melt_fee_balance_curr"
			    ",refund_fee_balance_val"
			    ",refund_fee_balance_frac"
			    ",refund_fee_balance_curr"
			    ",risk_val"
			    ",risk_frac"
			    ",risk_curr"
			    " FROM auditor_balance_summary"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_historic_denom_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_denomination_revenue_insert",
			    "INSERT INTO auditor_historic_denomination_revenue"
			    "(master_pub"
			    ",denom_pub_hash"
			    ",revenue_timestamp"
			    ",revenue_balance_val"
			    ",revenue_balance_frac"
			    ",revenue_balance_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6);",
			    6),
    /* Used in #postgres_select_historic_denom_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_denomination_revenue_select",
			    "SELECT"
			    " denom_pub_hash"
			    ",revenue_timestamp"
			    ",revenue_balance_val"
			    ",revenue_balance_frac"
			    ",revenue_balance_curr"
			    " FROM auditor_historic_denomination_revenue"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_historic_losses() */
    GNUNET_PQ_make_prepare ("auditor_historic_losses_insert",
			    "INSERT INTO auditor_historic_losses"
			    "(master_pub"
			    ",denom_pub_hash"
			    ",loss_timestamp"
			    ",loss_balance_val"
			    ",loss_balance_frac"
			    ",loss_balance_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6);",
			    6),
    /* Used in #postgres_select_historic_losses() */
    GNUNET_PQ_make_prepare ("auditor_historic_losses_select",
			    "SELECT"
			    " denom_pub_hash"
			    ",loss_timestamp"
			    ",loss_balance_val"
			    ",loss_balance_frac"
			    ",loss_balance_curr"
			    " FROM auditor_historic_losses"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_historic_reserve_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_reserve_summary_insert",
			    "INSERT INTO auditor_historic_reserve_summary"
			    "(master_pub"
			    ",start_date"
			    ",end_date"
			    ",reserve_profits_val"
			    ",reserve_profits_frac"
			    ",reserve_profits_curr"
			    ") VALUES ($1,$2,$3,$4,$5,$6);",
			    6),
    /* Used in #postgres_select_historic_reserve_revenue() */
    GNUNET_PQ_make_prepare ("auditor_historic_reserve_summary_select",
			    "SELECT"
			    " start_date"
			    ",end_date"
			    ",reserve_profits_val"
			    ",reserve_profits_frac"
			    ",reserve_profits_curr"
			    " FROM auditor_historic_reserve_summary"
			    " WHERE master_pub=$1;",
			    1),
    /* Used in #postgres_insert_predicted_result() */
    GNUNET_PQ_make_prepare ("auditor_predicted_result_insert",
			    "INSERT INTO auditor_predicted_result"
			    "(master_pub"
			    ",balance_val"
			    ",balance_frac"
			    ",balance_curr"
			    ") VALUES ($1,$2,$3,$4);",
			    4),
    /* Used in #postgres_update_predicted_result() */
    GNUNET_PQ_make_prepare ("auditor_predicted_result_update",
			    "UPDATE auditor_predicted_result SET"
			    " balance_val=$1"
			    ",balance_frac=$2"
			    ",balance_curr=$3"
			    " WHERE master_pub=$4;",
			    4),
    /* Used in #postgres_get_predicted_balance() */
    GNUNET_PQ_make_prepare ("auditor_predicted_result_select",
			    "SELECT"
			    " balance_val"
			    ",balance_frac"
			    ",balance_curr"
			    " FROM auditor_predicted_result"
			    " WHERE master_pub=$1;",
			    1),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  return GNUNET_PQ_prepare_statements (db_conn,
                                       ps);
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
  PGconn *db_conn;

  if (NULL == session)
    return;
  db_conn = session->conn;
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
  {
    if (CONNECTION_BAD == PQstatus (session->conn))
    {
      /**
       * Reset the thread-local database-handle.  Disconnects from the
       * DB.  Needed after the database server restarts as we need to
       * properly reconnect. */
      GNUNET_assert (0 == pthread_setspecific (pc->db_conn_threadlocal,
					      NULL));
      PQfinish (session->conn);
      GNUNET_free (session);
    }
    else
    {
      return session;
    }
  }
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
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_commit (void *cls,
                 struct TALER_AUDITORDB_Session *session)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
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
static int
postgres_gc (void *cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_PQ_QueryParam params_time[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  PGconn *conn;
  enum GNUNET_DB_QueryStatus qs;

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
  qs = GNUNET_PQ_eval_prepared_non_select (conn,
					   "gc_auditor",
					   params_time);
  if (0 > qs)
  {
    GNUNET_break (0);
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  PQfinish (conn);
  return GNUNET_OK;
}


/**
 * Insert information about an exchange this auditor will be auditing.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param master_pub master public key of the exchange
 * @param exchange_url public (base) URL of the API of the exchange
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_exchange (void *cls,
                          struct TALER_AUDITORDB_Session *session,
                          const struct TALER_MasterPublicKeyP *master_pub,
                          const char *exchange_url)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (exchange_url),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_insert_exchange",
					     params);
}


/**
 * Delete an exchange from the list of exchanges this auditor is auditing.
 * Warning: this will cascade and delete all knowledge of this auditor related
 * to this exchange!
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param master_pub master public key of the exchange
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_delete_exchange (void *cls,
                          struct TALER_AUDITORDB_Session *session,
                          const struct TALER_MasterPublicKeyP *master_pub)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_delete_exchange",
					     params);
}


/**
 * Closure for #exchange_info_cb().
 */
struct ExchangeInfoContext
{

  /**
   * Function to call for each exchange.
   */
  TALER_AUDITORDB_ExchangeCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_auditor_list_exchanges().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ExchangeInfoContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
exchange_info_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct ExchangeInfoContext *eic = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_MasterPublicKeyP master_pub;
    char *exchange_url;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_pub", &master_pub),
      GNUNET_PQ_result_spec_string ("exchange_url", &exchange_url),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      eic->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    eic->qs = i + 1;
    eic->cb (eic->cb_cls,
             &master_pub,
             exchange_url);
    GNUNET_free (exchange_url);
  }
}


/**
 * Obtain information about exchanges this auditor is auditing.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param master_pub master public key of the exchange
 * @param exchange_url public (base) URL of the API of the exchange
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_list_exchanges (void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         TALER_AUDITORDB_ExchangeCallback cb,
                         void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct ExchangeInfoContext eic = {
    .cb = cb,
    .cb_cls = cb_cls
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "auditor_list_exchanges",
					     params,
					     &exchange_info_cb,
					     &eic);
  if (qs > 0)
    return eic.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}


/**
 * Insert information about a signing key of the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param sk signing key information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_exchange_signkey (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_AUDITORDB_ExchangeSigningKey *sk)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&sk->master_public_key),
    TALER_PQ_query_param_absolute_time (&sk->ep_start),
    TALER_PQ_query_param_absolute_time (&sk->ep_expire),
    TALER_PQ_query_param_absolute_time (&sk->ep_end),
    GNUNET_PQ_query_param_auto_from_type (&sk->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&sk->master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_insert_exchange_signkey",
					     params);
}


/**
 * Insert information about a deposit confirmation into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param dc deposit confirmation information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_deposit_confirmation (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&dc->master_public_key),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&dc->h_wire),
    TALER_PQ_query_param_absolute_time (&dc->timestamp),
    TALER_PQ_query_param_absolute_time (&dc->refund_deadline),
    TALER_PQ_query_param_amount (&dc->amount_without_fee),
    GNUNET_PQ_query_param_auto_from_type (&dc->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&dc->merchant),
    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_sig),
    GNUNET_PQ_query_param_auto_from_type (&dc->exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (&dc->master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_deposit_confirmation_insert",
					     params);
}


/**
 * Insert information about a denomination key and in particular
 * the properties (value, fees, expiration times) the coins signed
 * with this key have.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param issue issuing information with value, fees and other info about the denomination
 * @return operation status result
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_info (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_DenominationKeyValidityPS *issue)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&issue->denom_hash),
    GNUNET_PQ_query_param_auto_from_type (&issue->master),
    TALER_PQ_query_param_absolute_time_nbo (&issue->start),
    TALER_PQ_query_param_absolute_time_nbo (&issue->expire_withdraw),
    TALER_PQ_query_param_absolute_time_nbo (&issue->expire_deposit),
    TALER_PQ_query_param_absolute_time_nbo (&issue->expire_legal),
    TALER_PQ_query_param_amount_nbo (&issue->value),
    TALER_PQ_query_param_amount_nbo (&issue->fee_withdraw),
    TALER_PQ_query_param_amount_nbo (&issue->fee_deposit),
    TALER_PQ_query_param_amount_nbo (&issue->fee_refresh),
    TALER_PQ_query_param_amount_nbo (&issue->fee_refund),
    GNUNET_PQ_query_param_end
  };

  /* check fees match coin currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->value,
                                                &issue->fee_withdraw));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->value,
                                                &issue->fee_deposit));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->value,
                                                &issue->fee_refresh));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->value,
                                               &issue->fee_refund));
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_denominations_insert",
					     params);
}


/**
 * Closure for #denomination_info_cb().
 */
struct DenominationInfoContext
{

  /**
   * Master public key that is being used.
   */
  const struct TALER_MasterPublicKeyP *master_pub;

  /**
   * Function to call for each denomination.
   */
  TALER_AUDITORDB_DenominationInfoDataCallback cb;

  /**
   * Closure for @e cb
   */
  void *cb_cls;

  /**
   * Query status to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_select_denomination_info().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct DenominationInfoContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
denomination_info_cb (void *cls,
		      PGresult *result,
		      unsigned int num_results)
{
  struct DenominationInfoContext *dic = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_DenominationKeyValidityPS issue = {
      .master = *dic->master_pub
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash", &issue.denom_hash),
      TALER_PQ_result_spec_absolute_time_nbo ("valid_from", &issue.start),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_withdraw", &issue.expire_withdraw),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_deposit", &issue.expire_deposit),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_legal", &issue.expire_legal),
      TALER_PQ_result_spec_amount_nbo ("coin", &issue.value),
      TALER_PQ_result_spec_amount_nbo ("fee_withdraw", &issue.fee_withdraw),
      TALER_PQ_result_spec_amount_nbo ("fee_deposit", &issue.fee_deposit),
      TALER_PQ_result_spec_amount_nbo ("fee_refresh", &issue.fee_refresh),
      TALER_PQ_result_spec_amount_nbo ("fee_refund", &issue.fee_refund),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      dic->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    dic->qs = i + 1;
    if (GNUNET_OK !=
	dic->cb (dic->cb_cls,
		 &issue))
      return;
  }
}


/**
 * Get information about denomination keys of a particular exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_denomination_info (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   TALER_AUDITORDB_DenominationInfoDataCallback cb,
                                   void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct DenominationInfoContext dic = {
    .master_pub = master_pub,
    .cb = cb,
    .cb_cls = cb_cls
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "auditor_denominations_select",
					     params,
					     &denomination_info_cb,
					     &dic);
  if (qs > 0)
    return dic.qs;
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  return qs;
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppr where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_reserve (void *cls,
                                          struct TALER_AUDITORDB_Session *session,
                                          const struct TALER_MasterPublicKeyP *master_pub,
                                          const struct TALER_AUDITORDB_ProgressPointReserve *ppr)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_out_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_payback_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_close_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_insert_reserve",
					     params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppr where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_reserve (void *cls,
                                          struct TALER_AUDITORDB_Session *session,
                                          const struct TALER_MasterPublicKeyP *master_pub,
                                          const struct TALER_AUDITORDB_ProgressPointReserve *ppr)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_out_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_payback_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppr->last_reserve_close_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_update_reserve",
					     params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] ppr set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_reserve (void *cls,
                                       struct TALER_AUDITORDB_Session *session,
                                       const struct TALER_MasterPublicKeyP *master_pub,
                                       struct TALER_AUDITORDB_ProgressPointReserve *ppr)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_reserve_in_serial_id",
                                  &ppr->last_reserve_in_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_out_serial_id",
                                  &ppr->last_reserve_out_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_payback_serial_id",
                                  &ppr->last_reserve_payback_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_reserve_close_serial_id",
                                  &ppr->last_reserve_close_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_progress_select_reserve",
						   params,
						   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppa where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_aggregation (void *cls,
                                              struct TALER_AUDITORDB_Session *session,
                                              const struct TALER_MasterPublicKeyP *master_pub,
                                              const struct TALER_AUDITORDB_ProgressPointAggregation *ppa)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppa->last_wire_out_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_insert_aggregation",
					     params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppa where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_aggregation (void *cls,
                                              struct TALER_AUDITORDB_Session *session,
                                              const struct TALER_MasterPublicKeyP *master_pub,
                                              const struct TALER_AUDITORDB_ProgressPointAggregation *ppa)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppa->last_wire_out_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_update_aggregation",
					     params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] ppa set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_aggregation (void *cls,
                                           struct TALER_AUDITORDB_Session *session,
                                           const struct TALER_MasterPublicKeyP *master_pub,
                                           struct TALER_AUDITORDB_ProgressPointAggregation *ppa)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_wire_out_serial_id",
                                  &ppa->last_wire_out_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_progress_select_aggregation",
						   params,
						   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppdc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_deposit_confirmation (void *cls,
                                                       struct TALER_AUDITORDB_Session *session,
                                                       const struct TALER_MasterPublicKeyP *master_pub,
                                                       const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppdc->last_deposit_confirmation_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_insert_deposit_confirmation",
					     params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppdc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_deposit_confirmation (void *cls,
                                                       struct TALER_AUDITORDB_Session *session,
                                                       const struct TALER_MasterPublicKeyP *master_pub,
                                                       const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppdc->last_deposit_confirmation_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_update_deposit_confirmation",
					     params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] ppdc set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_deposit_confirmation (void *cls,
                                                    struct TALER_AUDITORDB_Session *session,
                                                    const struct TALER_MasterPublicKeyP *master_pub,
                                                    struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_deposit_confirmation_serial_id",
                                  &ppdc->last_deposit_confirmation_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_progress_select_deposit_confirmation",
						   params,
						   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_progress_coin (void *cls,
                                       struct TALER_AUDITORDB_Session *session,
                                       const struct TALER_MasterPublicKeyP *master_pub,
                                       const struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_uint64 (&ppc->last_withdraw_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_deposit_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_melt_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_refund_serial_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_insert_coin",
					     params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param ppc where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor_progress_coin (void *cls,
                                       struct TALER_AUDITORDB_Session *session,
                                       const struct TALER_MasterPublicKeyP *master_pub,
                                       const struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ppc->last_withdraw_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_deposit_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_melt_serial_id),
    GNUNET_PQ_query_param_uint64 (&ppc->last_refund_serial_id),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_progress_update_coin",
					     params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] ppc set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_auditor_progress_coin (void *cls,
                                    struct TALER_AUDITORDB_Session *session,
                                    const struct TALER_MasterPublicKeyP *master_pub,
                                    struct TALER_AUDITORDB_ProgressPointCoin *ppc)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_withdraw_serial_id",
                                  &ppc->last_withdraw_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_deposit_serial_id",
                                  &ppc->last_deposit_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_melt_serial_id",
                                  &ppc->last_melt_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_refund_serial_id",
                                  &ppc->last_refund_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_progress_select_coin",
						   params,
						   rs);
}


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param pp where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_auditor_progress (void *cls,
                                       struct TALER_AUDITORDB_Session *session,
                                       const struct TALER_MasterPublicKeyP *master_pub,
                                       const char *account_name,
                                       const struct TALER_AUDITORDB_WireProgressPoint *pp,
                                       const void *in_wire_off,
                                       const void *out_wire_off,
                                       size_t wire_off_size)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_uint64 (&pp->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&pp->last_wire_out_serial_id),
    TALER_PQ_query_param_absolute_time (&pp->last_timestamp),
    GNUNET_PQ_query_param_fixed_size (in_wire_off,
                                      wire_off_size),
    GNUNET_PQ_query_param_fixed_size (out_wire_off,
                                      wire_off_size),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "wire_auditor_progress_insert",
					     params);
}


/**
 * Update information about the progress of the auditor.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param pp where is the auditor in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire_auditor_progress (void *cls,
                                       struct TALER_AUDITORDB_Session *session,
                                       const struct TALER_MasterPublicKeyP *master_pub,
                                       const char *account_name,
                                       const struct TALER_AUDITORDB_WireProgressPoint *pp,
                                       const void *in_wire_off,
                                       const void *out_wire_off,
                                       size_t wire_off_size)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&pp->last_reserve_in_serial_id),
    GNUNET_PQ_query_param_uint64 (&pp->last_wire_out_serial_id),
    TALER_PQ_query_param_absolute_time (&pp->last_timestamp),
    GNUNET_PQ_query_param_fixed_size (in_wire_off,
                                      wire_off_size),
    GNUNET_PQ_query_param_fixed_size (out_wire_off,
                                      wire_off_size),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "wire_auditor_progress_update",
					     params);
}


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param[out] pp set to where the auditor is in processing
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_auditor_progress (void *cls,
                                    struct TALER_AUDITORDB_Session *session,
                                    const struct TALER_MasterPublicKeyP *master_pub,
                                    const char *account_name,
                                    struct TALER_AUDITORDB_WireProgressPoint *pp,
                                    void **in_wire_off,
                                    void **out_wire_off,
                                    size_t *wire_off_size)
{
  size_t xsize;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("last_wire_reserve_in_serial_id",
                                  &pp->last_reserve_in_serial_id),
    GNUNET_PQ_result_spec_uint64 ("last_wire_wire_out_serial_id",
                                  &pp->last_wire_out_serial_id),
    TALER_PQ_result_spec_absolute_time ("last_timestamp",
                                         &pp->last_timestamp),
    GNUNET_PQ_result_spec_variable_size ("wire_in_off",
                                         in_wire_off,
                                         wire_off_size),
    GNUNET_PQ_result_spec_variable_size ("wire_out_off",
                                         out_wire_off,
                                         &xsize),
    GNUNET_PQ_result_spec_end
  };

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "wire_auditor_progress_select",
                                                 params,
                                                 rs);
  if (qs <= 0)
  {
    *wire_off_size = 0;
    xsize = 0;
  }
  GNUNET_assert (xsize == *wire_off_size);
  return qs;
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_reserve_info (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *reserve_balance,
                              const struct TALER_Amount *withdraw_fee_balance,
                              struct GNUNET_TIME_Absolute expiration_date)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    TALER_PQ_query_param_absolute_time (&expiration_date),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (reserve_balance,
                                            withdraw_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_reserves_insert",
					     params);
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_reserve_info (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              const struct TALER_Amount *reserve_balance,
                              const struct TALER_Amount *withdraw_fee_balance,
                              struct GNUNET_TIME_Absolute expiration_date)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    TALER_PQ_query_param_absolute_time (&expiration_date),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (reserve_balance,
                                            withdraw_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_reserves_update",
					     params);
}


/**
 * Delete information about a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_del_reserve_info (void *cls,
                           struct TALER_AUDITORDB_Session *session,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_MasterPublicKeyP *master_pub)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_reserves_delete",
					     params);
}


/**
 * Get information about a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param master_pub master public key of the exchange
 * @param[out] rowid which row did we get the information from
 * @param[out] reserve_balance amount stored in the reserve
 * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
 *                             due to withdrawals from this reserve
 * @param[out] expiration_date expiration date of the reserve
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_info (void *cls,
                           struct TALER_AUDITORDB_Session *session,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           uint64_t *rowid,
                           struct TALER_Amount *reserve_balance,
                           struct TALER_Amount *withdraw_fee_balance,
                           struct GNUNET_TIME_Absolute *expiration_date)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("reserve_balance", reserve_balance),
    TALER_PQ_result_spec_amount ("withdraw_fee_balance", withdraw_fee_balance),
    TALER_PQ_result_spec_absolute_time ("expiration_date", expiration_date),
    GNUNET_PQ_result_spec_uint64 ("auditor_reserves_rowid", rowid),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_reserves_select",
						   params,
						   rs);
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_reserve_summary (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *reserve_balance,
                                 const struct TALER_Amount *withdraw_fee_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (reserve_balance,
                                            withdraw_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_reserve_balance_insert",
					     params);
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_reserve_summary (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *reserve_balance,
                                 const struct TALER_Amount *withdraw_fee_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (reserve_balance),
    TALER_PQ_query_param_amount (withdraw_fee_balance),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_reserve_balance_update",
					     params);
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_summary (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *reserve_balance,
                              struct TALER_Amount *withdraw_fee_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("reserve_balance", reserve_balance),
    TALER_PQ_result_spec_amount ("withdraw_fee_balance", withdraw_fee_balance),

    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_reserve_balance_select",
						   params,
						   rs);
}


/**
 * Insert information about exchange's wire fee balance. There must not be an
 * existing record for the same @a master_pub.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param wire_fee_balance amount the exchange gained in wire fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_fee_summary (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_Amount *wire_fee_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (wire_fee_balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_wire_fee_balance_insert",
					     params);
}


/**
 * Insert information about exchange's wire fee balance.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param wire_fee_balance amount the exchange gained in wire fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire_fee_summary (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_Amount *wire_fee_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (wire_fee_balance),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_wire_fee_balance_update",
					     params);
}


/**
 * Get summary information about an exchanges wire fee balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master public key of the exchange
 * @param[out] wire_fee_balance set amount the exchange gained in wire fees
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_fee_summary (void *cls,
                               struct TALER_AUDITORDB_Session *session,
                               const struct TALER_MasterPublicKeyP *master_pub,
                               struct TALER_Amount *wire_fee_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("wire_fee_balance", wire_fee_balance),

    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_wire_fee_balance_select",
						   params,
						   rs);
}


/**
 * Insert information about a denomination key's balances.  There
 * must not be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the denomination public key
 * @param denom_balance value of coins outstanding with this denomination key
 * @param denom_risk value of coins issued with this denomination key
 * @param num_issued how many coins of this denomination did the exchange blind-sign
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_balance (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct GNUNET_HashCode *denom_pub_hash,
                                      const struct TALER_Amount *denom_balance,
                                      const struct TALER_Amount *denom_risk,
                                      uint64_t num_issued)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    TALER_PQ_query_param_amount (denom_balance),
    GNUNET_PQ_query_param_uint64 (&num_issued),
    TALER_PQ_query_param_amount (denom_risk),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_denomination_pending_insert",
					     params);
}


/**
 * Update information about a denomination key's balances.  There
 * must be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the denomination public key
 * @param denom_balance value of coins outstanding with this denomination key
 * @param denom_risk value of coins issued with this denomination key
 * @param num_issued how many coins of this denomination did the exchange blind-sign
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_denomination_balance (void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct GNUNET_HashCode *denom_pub_hash,
                                      const struct TALER_Amount *denom_balance,
                                      const struct TALER_Amount *denom_risk,
                                      uint64_t num_issued)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (denom_balance),
    GNUNET_PQ_query_param_uint64 (&num_issued),
    TALER_PQ_query_param_amount (denom_risk),
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_denomination_pending_update",
					     params);
}


/**
 * Get information about a denomination key's balances.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the denomination public key
 * @param[out] denom_balance value of coins outstanding with this denomination key
 * @param[out] denom_risk value of coins issued with this denomination key
 * @param[out] num_issued how many coins of this denomination did the exchange blind-sign
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_balance (void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct GNUNET_HashCode *denom_pub_hash,
                                   struct TALER_Amount *denom_balance,
                                   struct TALER_Amount *denom_risk,
                                   uint64_t *num_issued)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("denom_balance", denom_balance),
    TALER_PQ_result_spec_amount ("denom_risk", denom_risk),
    GNUNET_PQ_result_spec_uint64 ("num_issued", num_issued),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_denomination_pending_select",
						   params,
						   rs);
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
 * @param risk maximum risk exposure of the exchange
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_balance_summary (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *deposit_fee_balance,
                                 const struct TALER_Amount *melt_fee_balance,
                                 const struct TALER_Amount *refund_fee_balance,
                                 const struct TALER_Amount *risk)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (denom_balance),
    TALER_PQ_query_param_amount (deposit_fee_balance),
    TALER_PQ_query_param_amount (melt_fee_balance),
    TALER_PQ_query_param_amount (refund_fee_balance),
    TALER_PQ_query_param_amount (risk),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (denom_balance,
                                            deposit_fee_balance));

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (denom_balance,
                                            melt_fee_balance));

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (denom_balance,
                                            refund_fee_balance));

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_balance_summary_insert",
					     params);
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
 * @param risk maximum risk exposure of the exchange
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_balance_summary (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *deposit_fee_balance,
                                 const struct TALER_Amount *melt_fee_balance,
                                 const struct TALER_Amount *refund_fee_balance,
                                 const struct TALER_Amount *risk)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (denom_balance),
    TALER_PQ_query_param_amount (deposit_fee_balance),
    TALER_PQ_query_param_amount (melt_fee_balance),
    TALER_PQ_query_param_amount (refund_fee_balance),
    TALER_PQ_query_param_amount (risk),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_balance_summary_update",
					     params);
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
 * @param[out] risk maximum risk exposure of the exchange
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_balance_summary (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *denom_balance,
                              struct TALER_Amount *deposit_fee_balance,
                              struct TALER_Amount *melt_fee_balance,
                              struct TALER_Amount *refund_fee_balance,
                              struct TALER_Amount *risk)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("denom_balance", denom_balance),
    TALER_PQ_result_spec_amount ("deposit_fee_balance", deposit_fee_balance),
    TALER_PQ_result_spec_amount ("melt_fee_balance", melt_fee_balance),
    TALER_PQ_result_spec_amount ("refund_fee_balance", refund_fee_balance),
    TALER_PQ_result_spec_amount ("risk", risk),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_balance_summary_select",
						   params,
						   rs);
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_historic_denom_revenue (void *cls,
                                        struct TALER_AUDITORDB_Session *session,
                                        const struct TALER_MasterPublicKeyP *master_pub,
                                        const struct GNUNET_HashCode *denom_pub_hash,
                                        struct GNUNET_TIME_Absolute revenue_timestamp,
                                        const struct TALER_Amount *revenue_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    TALER_PQ_query_param_absolute_time (&revenue_timestamp),
    TALER_PQ_query_param_amount (revenue_balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_historic_denomination_revenue_insert",
					     params);
}


/**
 * Closure for #historic_denom_revenue_cb().
 */
struct HistoricDenomRevenueContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Number of results processed.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_select_historic_denom_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
historic_denom_revenue_cb (void *cls,
			   PGresult *result,
			   unsigned int num_results)
{
  struct HistoricDenomRevenueContext *hrc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_HashCode denom_pub_hash;
    struct GNUNET_TIME_Absolute revenue_timestamp;
    struct TALER_Amount revenue_balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash", &denom_pub_hash),
      TALER_PQ_result_spec_absolute_time ("revenue_timestamp", &revenue_timestamp),
      TALER_PQ_result_spec_amount ("revenue_balance", &revenue_balance),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      hrc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }

    hrc->qs = i + 1;
    if (GNUNET_OK !=
	hrc->cb (hrc->cb_cls,
		 &denom_pub_hash,
		 revenue_timestamp,
		 &revenue_balance))
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_historic_denom_revenue (void *cls,
                                        struct TALER_AUDITORDB_Session *session,
                                        const struct TALER_MasterPublicKeyP *master_pub,
                                        TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb,
                                        void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct HistoricDenomRevenueContext hrc = {
    .cb = cb,
    .cb_cls = cb_cls
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "auditor_historic_denomination_revenue_select",
					     params,
					     &historic_denom_revenue_cb,
					     &hrc);
  if (qs <= 0)
    return qs;
  return hrc.qs;
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_historic_losses (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 struct GNUNET_TIME_Absolute loss_timestamp,
                                 const struct TALER_Amount *loss_balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    TALER_PQ_query_param_absolute_time (&loss_timestamp),
    TALER_PQ_query_param_amount (loss_balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_historic_losses_insert",
					     params);
}


/**
 * Closure for #losses_cb.
 */
struct LossContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricLossesDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Status code to return.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_select_historic_denom_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
losses_cb (void *cls,
	   PGresult *result,
	   unsigned int num_results)
{
  struct LossContext *lctx = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_HashCode denom_pub_hash;
    struct GNUNET_TIME_Absolute loss_timestamp;
    struct TALER_Amount loss_balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash", &denom_pub_hash),
      TALER_PQ_result_spec_absolute_time ("loss_timestamp", &loss_timestamp),
      TALER_PQ_result_spec_amount ("loss_balance", &loss_balance),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      lctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    lctx->qs = i + 1;
    if (GNUNET_OK !=
	lctx->cb (lctx->cb_cls,
		  &denom_pub_hash,
		  loss_timestamp,
		  &loss_balance))
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_historic_losses (void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 TALER_AUDITORDB_HistoricLossesDataCallback cb,
                                 void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct LossContext lctx = {
    .cb = cb,
    .cb_cls = cb_cls
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "auditor_historic_losses_select",
					     params,
					     &losses_cb,
					     &lctx);
  if (qs <= 0)
    return qs;
  return lctx.qs;
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_historic_reserve_revenue (void *cls,
                                          struct TALER_AUDITORDB_Session *session,
                                          const struct TALER_MasterPublicKeyP *master_pub,
                                          struct GNUNET_TIME_Absolute start_time,
                                          struct GNUNET_TIME_Absolute end_time,
                                          const struct TALER_Amount *reserve_profits)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_absolute_time (&start_time),
    TALER_PQ_query_param_absolute_time (&end_time),
    TALER_PQ_query_param_amount (reserve_profits),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_historic_reserve_summary_insert",
					     params);
}


/**
 * Closure for #historic_reserve_revenue_cb().
 */
struct HistoricReserveRevenueContext
{
  /**
   * Function to call for each result.
   */
  TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Number of results processed.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Helper function for #postgres_select_historic_reserve_revenue().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct HistoricRevenueContext *`
 * @param result the postgres result
 * @param num_result the number of results in @a result
 */
static void
historic_reserve_revenue_cb (void *cls,
			     PGresult *result,
			     unsigned int num_results)
{
  struct HistoricReserveRevenueContext *hrc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_TIME_Absolute start_date;
    struct GNUNET_TIME_Absolute end_date;
    struct TALER_Amount reserve_profits;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_absolute_time ("start_date", &start_date),
      TALER_PQ_result_spec_absolute_time ("end_date", &end_date),
      TALER_PQ_result_spec_amount ("reserve_profits", &reserve_profits),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
				  rs,
				  i))
    {
      GNUNET_break (0);
      hrc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    hrc->qs = i + 1;
    if (GNUNET_OK !=
	hrc->cb (hrc->cb_cls,
		 start_date,
		 end_date,
		 &reserve_profits))
      break;
  }
}


/**
 * Return information about an exchange's historic revenue from reserves.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_historic_reserve_revenue (void *cls,
                                          struct TALER_AUDITORDB_Session *session,
                                          const struct TALER_MasterPublicKeyP *master_pub,
                                          TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb,
                                          void *cb_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct HistoricReserveRevenueContext hrc = {
    .cb = cb,
    .cb_cls = cb_cls
  };

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
					     "auditor_historic_reserve_summary_select",
					     params,
					     &historic_reserve_revenue_cb,
					     &hrc);
  if (0 >= qs)
    return qs;
  return hrc.qs;
}


/**
 * Insert information about the predicted exchange's bank
 * account balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_predicted_result (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_Amount *balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    TALER_PQ_query_param_amount (balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_predicted_result_insert",
					     params);
}


/**
 * Update information about an exchange's predicted balance.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_predicted_result (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_Amount *balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (balance),
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
					     "auditor_predicted_result_update",
					     params);
}


/**
 * Get an exchange's predicted balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param master_pub master key of the exchange
 * @param[out] balance expected bank account balance of the exchange
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_predicted_balance (void *cls,
                                struct TALER_AUDITORDB_Session *session,
                                const struct TALER_MasterPublicKeyP *master_pub,
                                struct TALER_Amount *balance)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_amount ("balance", balance),

    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
						   "auditor_predicted_result_select",
						   params,
						   rs);
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
                                               "CONFIG",
                                               &pg->connection_cfg_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "auditordb-postgres",
                                 "CONFIG");
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

  plugin->insert_exchange = &postgres_insert_exchange;
  plugin->delete_exchange = &postgres_delete_exchange;
  plugin->list_exchanges = &postgres_list_exchanges;
  plugin->insert_exchange_signkey = &postgres_insert_exchange_signkey;
  plugin->insert_deposit_confirmation = &postgres_insert_deposit_confirmation;

  plugin->select_denomination_info = &postgres_select_denomination_info;
  plugin->insert_denomination_info = &postgres_insert_denomination_info;

  plugin->get_auditor_progress_reserve = &postgres_get_auditor_progress_reserve;
  plugin->update_auditor_progress_reserve = &postgres_update_auditor_progress_reserve;
  plugin->insert_auditor_progress_reserve = &postgres_insert_auditor_progress_reserve;
  plugin->get_auditor_progress_aggregation = &postgres_get_auditor_progress_aggregation;
  plugin->update_auditor_progress_aggregation = &postgres_update_auditor_progress_aggregation;
  plugin->insert_auditor_progress_aggregation = &postgres_insert_auditor_progress_aggregation;
  plugin->get_auditor_progress_deposit_confirmation = &postgres_get_auditor_progress_deposit_confirmation;
  plugin->update_auditor_progress_deposit_confirmation = &postgres_update_auditor_progress_deposit_confirmation;
  plugin->insert_auditor_progress_deposit_confirmation = &postgres_insert_auditor_progress_deposit_confirmation;
  plugin->get_auditor_progress_coin = &postgres_get_auditor_progress_coin;
  plugin->update_auditor_progress_coin = &postgres_update_auditor_progress_coin;
  plugin->insert_auditor_progress_coin = &postgres_insert_auditor_progress_coin;

  plugin->get_wire_auditor_progress = &postgres_get_wire_auditor_progress;
  plugin->update_wire_auditor_progress = &postgres_update_wire_auditor_progress;
  plugin->insert_wire_auditor_progress = &postgres_insert_wire_auditor_progress;

  plugin->del_reserve_info = &postgres_del_reserve_info;
  plugin->get_reserve_info = &postgres_get_reserve_info;
  plugin->update_reserve_info = &postgres_update_reserve_info;
  plugin->insert_reserve_info = &postgres_insert_reserve_info;

  plugin->get_reserve_summary = &postgres_get_reserve_summary;
  plugin->update_reserve_summary = &postgres_update_reserve_summary;
  plugin->insert_reserve_summary = &postgres_insert_reserve_summary;

  plugin->get_wire_fee_summary = &postgres_get_wire_fee_summary;
  plugin->update_wire_fee_summary = &postgres_update_wire_fee_summary;
  plugin->insert_wire_fee_summary = &postgres_insert_wire_fee_summary;

  plugin->get_denomination_balance = &postgres_get_denomination_balance;
  plugin->update_denomination_balance = &postgres_update_denomination_balance;
  plugin->insert_denomination_balance = &postgres_insert_denomination_balance;

  plugin->get_balance_summary = &postgres_get_balance_summary;
  plugin->update_balance_summary = &postgres_update_balance_summary;
  plugin->insert_balance_summary = &postgres_insert_balance_summary;

  plugin->select_historic_denom_revenue = &postgres_select_historic_denom_revenue;
  plugin->insert_historic_denom_revenue = &postgres_insert_historic_denom_revenue;

  plugin->select_historic_losses = &postgres_select_historic_losses;
  plugin->insert_historic_losses = &postgres_insert_historic_losses;

  plugin->select_historic_reserve_revenue = &postgres_select_historic_reserve_revenue;
  plugin->insert_historic_reserve_revenue = &postgres_insert_historic_reserve_revenue;

  plugin->get_predicted_balance = &postgres_get_predicted_balance;
  plugin->update_predicted_result = &postgres_update_predicted_result;
  plugin->insert_predicted_result = &postgres_insert_predicted_result;

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
