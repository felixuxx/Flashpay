/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * @file plugin_exchangedb_postgres.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 */
#include "platform.h"
#include "taler_pq_lib.h"
#include "taler_exchangedb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>

#include "plugin_exchangedb_common.c"

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
struct TALER_EXCHANGEDB_Session
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
            "DROP TABLE IF EXISTS prewire;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS aggregation_tracking;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS deposits;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS refresh_out;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS refresh_commit_coin;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS refresh_transfer_public_key;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS refunds;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS refresh_order;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS refresh_sessions CASCADE;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS known_coins CASCADE;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS reserves_out;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS reserves_in;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS reserves;");
  SQLEXEC_ (conn,
            "DROP TABLE IF EXISTS denominations CASCADE;");
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
  /* Denomination table for holding the publicly available information of
     denominations keys.  The denominations are to be referred to using
     foreign keys. */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS denominations"
           "(denom_pub BYTEA PRIMARY KEY"
           ",master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
           ",master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)"
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
  /* reserves table is for summarization of a reserve.  It is updated when new
     funds are added and existing funds are withdrawn.  The 'expiration_date'
     can be used to eventually get rid of reserves that have not been used
     for a very long time (either by refunding the owner or by greedily
     grabbing the money, depending on the Exchange's terms of service) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS reserves"
           "(reserve_pub BYTEA PRIMARY KEY CHECK(LENGTH(reserve_pub)=32)"
           ",current_balance_val INT8 NOT NULL"
           ",current_balance_frac INT4 NOT NULL"
           ",current_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",expiration_date INT8 NOT NULL"
           ")");
  /* index on reserves table */
  SQLEXEC_INDEX ("CREATE INDEX reserves_reserve_pub_index ON "
                 "reserves (reserve_pub)");
  SQLEXEC_INDEX ("CREATE INDEX reserves_expiration_index"
		 " ON reserves (expiration_date);");
  /* reserves_in table collects the transactions which transfer funds
     into the reserve.  The rows of this table correspond to each
     incoming transaction. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS reserves_in"
          "(reserve_in_serial_id BIGSERIAL"
	  ",reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
          ",credit_val INT8 NOT NULL"
          ",credit_frac INT4 NOT NULL"
          ",credit_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",sender_account_details TEXT NOT NULL "
          ",transfer_details TEXT NOT NULL "
          ",execution_date INT8 NOT NULL"
          ",PRIMARY KEY (reserve_pub, transfer_details)"
          ");");
  /* Create indices on reserves_in */
  SQLEXEC_INDEX ("CREATE INDEX reserves_in_execution_index"
		 " ON reserves_in (execution_date);");
  /* Table with the withdraw operations that have been performed on a reserve.
     The 'h_blind_ev' is the hash of the blinded coin. It serves as a primary
     key, as (broken) clients that use a non-random coin and blinding factor
     should fail to even withdraw, as otherwise the coins will fail to deposit
     (as they really must be unique). */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS reserves_out"
           "(reserve_out_serial_id BIGSERIAL"
	   ",h_blind_ev BYTEA PRIMARY KEY"
           ",denom_pub BYTEA NOT NULL REFERENCES denominations (denom_pub) ON DELETE CASCADE"
           ",denom_sig BYTEA NOT NULL"
           ",reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
           ",reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)"
           ",execution_date INT8 NOT NULL"
           ",amount_with_fee_val INT8 NOT NULL"
           ",amount_with_fee_frac INT4 NOT NULL"
           ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ");");
  /* Index blindcoins(reserve_pub) for get_reserves_out statement */
  SQLEXEC_INDEX ("CREATE INDEX reserves_out_reserve_pub_index ON"
                 " reserves_out (reserve_pub)");
  SQLEXEC_INDEX ("CREATE INDEX reserves_out_execution_date ON "
                 "reserves_out (execution_date)");
  /* Table with coins that have been (partially) spent, used to track
     coin information only once. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS known_coins "
          "(coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)"
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (denom_pub) ON DELETE CASCADE"
          ",denom_sig BYTEA NOT NULL"
          ")");
  /**
   * The DB will show negative values for some values of the following fields as
   * we use them as 16 bit unsigned integers
   *   @a num_newcoins
   *   @a noreveal_index
   * Do not do arithmetic in SQL on these fields.
   * NOTE: maybe we should instead forbid values >= 2^15 categorically?
   */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_sessions "
          "(melt_serial_id BIGSERIAL"
	  ",session_hash BYTEA PRIMARY KEY CHECK (LENGTH(session_hash)=64)"
          ",old_coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE"
          ",old_coin_sig BYTEA NOT NULL CHECK(LENGTH(old_coin_sig)=64)"
          ",amount_with_fee_val INT8 NOT NULL"
          ",amount_with_fee_frac INT4 NOT NULL"
          ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",num_newcoins INT2 NOT NULL"
          ",noreveal_index INT2 NOT NULL"
          ")");

  /* Table with information about the desired denominations to be created
     during a refresh operation; contains the denomination key for each
     of the coins (for a given refresh session) */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_order "
          "(session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash) ON DELETE CASCADE"
          ",newcoin_index INT2 NOT NULL "
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (denom_pub) ON DELETE CASCADE"
          ",PRIMARY KEY (session_hash, newcoin_index)"
          ")");

  /* Table with the commitments for a refresh operation; includes
     the session_hash for which this is the link information, the
     oldcoin index and the cut-and-choose index (from 0 to #TALER_CNC_KAPPA-1),
     as well as the actual link data (the transfer public key and the encrypted
     link secret) */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_transfer_public_key "
          "(session_hash BYTEA NOT NULL PRIMARY KEY REFERENCES refresh_sessions (session_hash) ON DELETE CASCADE"
          ",transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)"
          ")");

  /* Table with the commitments for the new coins that are to be created
     during a melting session.  Includes the session, the cut-and-choose
     index and the index of the new coin, and the envelope of the new
     coin to be signed, as well as the encrypted information about the
     private key and the blinding factor for the coin (for verification
     in case this newcoin_index is chosen to be revealed) */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_coin "
          "(session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash) ON DELETE CASCADE"
          ",newcoin_index INT2 NOT NULL"
          ",coin_ev BYTEA NOT NULL"
          ",UNIQUE (session_hash, newcoin_index)"
          ")");
  SQLEXEC_INDEX("CREATE INDEX refresh_commit_coin_session_hash_index "
                "ON refresh_commit_coin(session_hash, newcoin_index)");


  /* Table with the signatures over coins generated during a refresh
     operation. Needed to answer /refresh/link queries later.  Stores
     the coin signatures under the respective session hash and index. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_out "
          "(session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash) ON DELETE CASCADE"
          ",newcoin_index INT2 NOT NULL"
          ",ev_sig BYTEA NOT NULL"
          ",UNIQUE (session_hash, newcoin_index)"
          ")");
  SQLEXEC_INDEX("CREATE INDEX refresh_out_session_hash_index "
                "ON refresh_out(session_hash, newcoin_index)");

  /* This table contains the wire transfers the exchange is supposed to
     execute to transmit funds to the merchants (and manage refunds). */
  SQLEXEC("CREATE TABLE IF NOT EXISTS deposits "
          "(deposit_serial_id BIGSERIAL PRIMARY KEY"
          ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE"
          ",transaction_id INT8 NOT NULL"
          ",amount_with_fee_val INT8 NOT NULL"
          ",amount_with_fee_frac INT4 NOT NULL"
          ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",timestamp INT8 NOT NULL"
          ",refund_deadline INT8 NOT NULL"
          ",wire_deadline INT8 NOT NULL"
          ",merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)"
          ",h_contract BYTEA NOT NULL CHECK (LENGTH(h_contract)=64)"
          ",h_wire BYTEA NOT NULL CHECK (LENGTH(h_wire)=64)"
          ",coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)"
          ",wire TEXT NOT NULL"
          ",tiny BOOLEAN NOT NULL DEFAULT false"
          ",done BOOLEAN NOT NULL DEFAULT false"
          ",UNIQUE (coin_pub, transaction_id, merchant_pub)"
          ")");
  /* Index for get_deposit statement on coin_pub, transaction_id and merchant_pub */
  SQLEXEC_INDEX("CREATE INDEX deposits_coin_pub_index "
                "ON deposits(coin_pub, transaction_id, merchant_pub)");

  /* Table with information about coins that have been refunded. (Technically
     one of the deposit operations that a coin was involved with is refunded.)*/
  SQLEXEC("CREATE TABLE IF NOT EXISTS refunds "
          "(refund_serial_id BIGSERIAL"
	  ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) ON DELETE CASCADE"
          ",merchant_pub BYTEA NOT NULL CHECK(LENGTH(merchant_pub)=32)"
          ",merchant_sig BYTEA NOT NULL CHECK(LENGTH(merchant_sig)=64)"
          ",h_contract BYTEA NOT NULL CHECK(LENGTH(h_contract)=64)"
          ",transaction_id INT8 NOT NULL"
          ",rtransaction_id INT8 NOT NULL"
          ",amount_with_fee_val INT8 NOT NULL"
          ",amount_with_fee_frac INT4 NOT NULL"
          ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",PRIMARY KEY (coin_pub, merchant_pub, transaction_id, rtransaction_id)" /* this combo must be unique, and we usually select by coin_pub */
          ") ");

  /* Table for the tracking API, mapping from wire transfer identifiers
     to transactions and back */
  SQLEXEC("CREATE TABLE IF NOT EXISTS aggregation_tracking "
          "(deposit_serial_id INT8 PRIMARY KEY REFERENCES deposits (deposit_serial_id) ON DELETE CASCADE"
          ",wtid_raw BYTEA NOT NULL CHECK (LENGTH(wtid_raw)=" TALER_WIRE_TRANSFER_IDENTIFIER_LEN_STR ")"
          ",execution_time INT8 NOT NULL"
          ")");
  /* Index for lookup_transactions statement on wtid */
  SQLEXEC_INDEX("CREATE INDEX aggregation_tracking_wtid_index "
                "ON aggregation_tracking(wtid_raw)");

  /* This table contains the pre-commit data for
     wire transfers the exchange is about to execute. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS prewire "
          "(prewire_uuid BIGSERIAL PRIMARY KEY"
          ",type TEXT NOT NULL"
          ",finished BOOLEAN NOT NULL DEFAULT false"
          ",buf BYTEA NOT NULL"
          ")");
  /* Index for prepare_data_iterate statement */
  SQLEXEC_INDEX("CREATE INDEX prepare_iteration_index "
                "ON prewire(type,finished)");


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

  /* Used in #postgres_insert_denomination_info() */
  PREPARE ("denomination_insert",
           "INSERT INTO denominations "
           "(denom_pub"
           ",master_pub"
           ",master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin_val" /* value of this denom */
           ",coin_frac" /* fractional value of this denom */
           ",coin_curr" /* assuming same currency for fees */
           ",fee_withdraw_val"
           ",fee_withdraw_frac"
           ",fee_withdraw_curr" /* must match coin_curr */
           ",fee_deposit_val"
           ",fee_deposit_frac"
           ",fee_deposit_curr"  /* must match coin_curr */
           ",fee_refresh_val"
           ",fee_refresh_frac"
           ",fee_refresh_curr" /* must match coin_curr */
           ",fee_refund_val"
           ",fee_refund_frac"
           ",fee_refund_curr" /* must match coin_curr */
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13, $14, $15, $16, $17, $18,"
	   " $19, $20, $21, $22);",
           22, NULL);

  /* Used in #postgres_get_denomination_info() */
  PREPARE ("denomination_get",
           "SELECT"
           " master_pub"
           ",master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_deposit"
           ",expire_legal"
           ",coin_val"  /* value of this denom */
           ",coin_frac" /* fractional value of this denom */
           ",coin_curr" /* assuming same currency for fees */
           ",fee_withdraw_val"
           ",fee_withdraw_frac"
           ",fee_withdraw_curr" /* must match coin_curr */
           ",fee_deposit_val"
           ",fee_deposit_frac"
           ",fee_deposit_curr"  /* must match coin_curr */
           ",fee_refresh_val"
           ",fee_refresh_frac"
           ",fee_refresh_curr" /* must match coin_curr */
           ",fee_refund_val"
           ",fee_refund_frac"
           ",fee_refund_curr" /* must match coin_curr */
           " FROM denominations"
           " WHERE denom_pub=$1;",
           1, NULL);

  /* Used in #postgres_reserve_get() */
  PREPARE ("reserve_get",
           "SELECT"
           " current_balance_val"
           ",current_balance_frac"
           ",current_balance_curr"
           ",expiration_date"
           " FROM reserves"
           " WHERE reserve_pub=$1"
           " LIMIT 1;",
           1, NULL);

  /* Used in #postgres_reserves_in_insert() when the reserve is new */
  PREPARE ("reserve_create",
           "INSERT INTO reserves "
           "(reserve_pub"
           ",current_balance_val"
           ",current_balance_frac"
           ",current_balance_curr"
           ",expiration_date"
           ") VALUES "
           "($1, $2, $3, $4, $5);",
           5, NULL);

  /* Used in #postgres_reserves_update() when the reserve is updated */
  PREPARE ("reserve_update",
           "UPDATE reserves"
           " SET"
           " expiration_date=$1 "
           ",current_balance_val=$2 "
           ",current_balance_frac=$3 "
           "WHERE current_balance_curr=$4 AND reserve_pub=$5",
           5, NULL);

  /* Used in #postgres_reserves_in_insert() to store transaction details */
  PREPARE ("reserves_in_add_transaction",
           "INSERT INTO reserves_in "
           "(reserve_pub"
           ",credit_val"
           ",credit_frac"
           ",credit_curr"
           ",sender_account_details"
           ",transfer_details"
           ",execution_date"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);",
           7, NULL);

  /* Used in #postgres_get_reserve_history() to obtain inbound transactions
     for a reserve */
  PREPARE ("reserves_in_get_transactions",
           "SELECT"
           " credit_val"
           ",credit_frac"
           ",credit_curr"
           ",execution_date"
           ",sender_account_details"
           ",transfer_details"
           " FROM reserves_in"
           " WHERE reserve_pub=$1",
           1, NULL);

  /* Used in #postgres_insert_withdraw_info() to store
     the signature of a blinded coin with the blinded coin's
     details before returning it during /reserve/withdraw. We store
     the coin's denomination information (public key, signature)
     and the blinded message as well as the reserve that the coin
     is being withdrawn from and the signature of the message
     authorizing the withdrawal. */
  PREPARE ("insert_withdraw_info",
           "INSERT INTO reserves_out "
           "(h_blind_ev"
           ",denom_pub"
           ",denom_sig"
           ",reserve_pub"
           ",reserve_sig"
           ",execution_date"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
           9, NULL);

  /* Used in #postgres_get_withdraw_info() to
     locate the response for a /reserve/withdraw request
     using the hash of the blinded message.  Used to
     make sure /reserve/withdraw requests are idempotent. */
  PREPARE ("get_withdraw_info",
           "SELECT"
           " denom_pub"
           ",denom_sig"
           ",reserve_sig"
           ",reserve_pub"
           ",execution_date"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_withdraw_val"
           ",denom.fee_withdraw_frac"
           ",denom.fee_withdraw_curr"
           " FROM reserves_out"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE h_blind_ev=$1",
           1, NULL);

  /* Used during #postgres_get_reserve_history() to
     obtain all of the /reserve/withdraw operations that
     have been performed on a given reserve. (i.e. to
     demonstrate double-spending) */
  PREPARE ("get_reserves_out",
           "SELECT"
           " h_blind_ev"
           ",denom_pub"
           ",denom_sig"
           ",reserve_sig"
           ",execution_date"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_withdraw_val"
           ",denom.fee_withdraw_frac"
           ",denom.fee_withdraw_curr"
           " FROM reserves_out"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE reserve_pub=$1;",
           1, NULL);

  /* Used in #postgres_get_refresh_session() to fetch
     high-level information about a refresh session */
  PREPARE ("get_refresh_session",
           "SELECT"
           " old_coin_pub"
           ",old_coin_sig"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_refresh_val "
           ",denom.fee_refresh_frac "
           ",denom.fee_refresh_curr "
           ",num_newcoins"
           ",noreveal_index"
           " FROM refresh_sessions "
           "    JOIN known_coins ON (refresh_sessions.old_coin_pub = known_coins.coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE session_hash=$1 ",
           1, NULL);

  /* Used in #postgres_create_refresh_session() to store
     high-level information about a refresh session */
  PREPARE ("insert_refresh_session",
           "INSERT INTO refresh_sessions "
           "(session_hash "
           ",old_coin_pub "
           ",old_coin_sig "
           ",amount_with_fee_val "
           ",amount_with_fee_frac "
           ",amount_with_fee_curr "
           ",num_newcoins "
           ",noreveal_index "
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);",
           8, NULL);

  /* Used in #postgres_get_known_coin() to fetch
     the denomination public key and signature for
     a coin known to the exchange. */
  PREPARE ("get_known_coin",
           "SELECT"
           " denom_pub"
           ",denom_sig"
           " FROM known_coins"
           " WHERE coin_pub=$1",
           1, NULL);

  /* Used in #postgres_insert_known_coin() to store
     the denomination public key and signature for
     a coin known to the exchange. */
  PREPARE ("insert_known_coin",
           "INSERT INTO known_coins "
           "(coin_pub"
           ",denom_pub"
           ",denom_sig"
           ") VALUES "
           "($1,$2,$3);",
           3, NULL);

  /* Store information about the desired denominations for a
     refresh operation, used in #postgres_insert_refresh_order() */
  PREPARE ("insert_refresh_order",
           "INSERT INTO refresh_order "
           "(newcoin_index "
           ",session_hash "
           ",denom_pub "
           ") VALUES "
           "($1, $2, $3);",
           3, NULL);

  /* Obtain information about the desired denominations for a
     refresh operation, used in #postgres_get_refresh_order() */
  PREPARE ("get_refresh_order",
           "SELECT denom_pub"
           " FROM refresh_order"
           " WHERE session_hash=$1 AND newcoin_index=$2",
           2, NULL);

  /* Query the 'refresh_sessions' by coin public key */
  PREPARE ("get_refresh_session_by_coin",
           "SELECT"
           " session_hash"
           ",old_coin_sig"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_refresh_val "
           ",denom.fee_refresh_frac "
           ",denom.fee_refresh_curr "
           " FROM refresh_sessions"
           "    JOIN known_coins ON (refresh_sessions.old_coin_pub = known_coins.coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE old_coin_pub=$1",
           1, NULL);

  /* Query the 'refunds' by coin public key */
  PREPARE ("get_refunds_by_coin",
           "SELECT"
           " merchant_pub"
           ",merchant_sig"
           ",h_contract"
           ",transaction_id"
           ",rtransaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_refund_val "
           ",denom.fee_refund_frac "
           ",denom.fee_refund_curr "
           " FROM refunds"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE coin_pub=$1",
           1, NULL);


  /* Used in #postgres_insert_transfer_public_key() to
     store commitments */
  PREPARE ("insert_transfer_public_key",
           "INSERT INTO refresh_transfer_public_key "
           "(session_hash"
           ",transfer_pub"
           ") VALUES "
           "($1, $2);",
           3, NULL);

  /* Used in #postgres_get_refresh_transfer_public_key() to
     retrieve original commitments during /refresh/reveal */
  PREPARE ("get_refresh_transfer_public_key",
           "SELECT"
           " transfer_pub"
           " FROM refresh_transfer_public_key"
           " WHERE session_hash=$1",
           1, NULL);

  /* Used in #postgres_insert_refresh_commit_coins() to
     store coin commitments. */
  PREPARE ("insert_refresh_commit_coin",
           "INSERT INTO refresh_commit_coin "
           "(session_hash"
           ",newcoin_index"
           ",coin_ev"
           ") VALUES "
           "($1, $2, $3);",
           3, NULL);

  /* Used in #postgres_get_refresh_commit_coins() to
     retrieve the original coin envelopes, to either be
     verified or signed. */
  PREPARE ("get_refresh_commit_coin",
           "SELECT"
           " coin_ev"
           " FROM refresh_commit_coin"
           " WHERE session_hash=$1 AND newcoin_index=$2",
           2, NULL);

  /* Store information about a /deposit the exchange is to execute.
     Used in #postgres_insert_deposit(). */
  PREPARE ("insert_deposit",
           "INSERT INTO deposits "
           "(coin_pub"
           ",transaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",timestamp"
           ",refund_deadline"
           ",wire_deadline"
           ",merchant_pub"
           ",h_contract"
           ",h_wire"
           ",coin_sig"
           ",wire"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13);",
           13, NULL);

  /* Used in #postgres_insert_refund() to store refund information */
  PREPARE ("insert_refund",
           "INSERT INTO refunds "
           "(coin_pub "
           ",merchant_pub "
           ",merchant_sig "
           ",h_contract "
           ",transaction_id "
           ",rtransaction_id "
           ",amount_with_fee_val "
           ",amount_with_fee_frac "
           ",amount_with_fee_curr "
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
           9, NULL);

  /* Fetch an existing deposit request, used to ensure idempotency
     during /deposit processing. Used in #postgres_have_deposit(). */
  PREPARE ("get_deposit",
           "SELECT"
           " amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",timestamp"
           ",refund_deadline"
           ",wire_deadline"
           ",h_contract"
           ",h_wire"
           " FROM deposits"
           " WHERE ("
           "  (coin_pub=$1) AND"
           "  (transaction_id=$2) AND"
           "  (merchant_pub=$3)"
           " )",
           3, NULL);

  /* Fetch an existing deposit request.
     Used in #postgres_wire_lookup_deposit_wtid(). */
  PREPARE ("get_deposit_for_wtid",
           "SELECT"
           " amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.fee_deposit_curr"
           ",wire_deadline"
           " FROM deposits"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE ("
           "  (coin_pub=$1) AND"
           "  (transaction_id=$2) AND"
           "  (merchant_pub=$3) AND"
           "  (h_contract=$4) AND"
           "  (h_wire=$5)"
           " )",
           5, NULL);

  /* Used in #postgres_get_ready_deposit() */
  PREPARE ("deposits_get_ready",
           "SELECT"
           " deposit_serial_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.fee_deposit_curr"
           ",wire_deadline"
           ",transaction_id"
           ",h_contract"
           ",wire"
           ",merchant_pub"
           ",coin_pub"
           " FROM deposits"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE"
           " tiny=false AND"
           " done=false AND"
           " wire_deadline<=$1 AND"
           " refund_deadline<$1"
           " ORDER BY wire_deadline ASC"
           " LIMIT 1",
           1, NULL);

  /* Used in #postgres_iterate_matching_deposits() */
  PREPARE ("deposits_iterate_matching",
           "SELECT"
           " deposit_serial_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.fee_deposit_curr"
           ",wire_deadline"
           ",transaction_id"
           ",h_contract"
           ",coin_pub"
           " FROM deposits"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE"
           " merchant_pub=$1 AND"
           " h_wire=$2 AND"
           " done=false"
           " ORDER BY wire_deadline ASC"
           " LIMIT " TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT_STR,
           2, NULL);

  /* Used in #postgres_mark_deposit_tiny() */
  PREPARE ("mark_deposit_tiny",
           "UPDATE deposits"
           " SET tiny=true"
           " WHERE deposit_serial_id=$1",
           1, NULL);

  /* Used in #postgres_mark_deposit_done() */
  PREPARE ("mark_deposit_done",
           "UPDATE deposits"
           " SET done=true"
           " WHERE deposit_serial_id=$1",
           1, NULL);

  /* Used in #postgres_test_deposit_done() */
  PREPARE ("test_deposit_done",
           "SELECT done"
           " FROM deposits"
           " WHERE coin_pub=$1"
           " AND transaction_id=$2"
           " AND merchant_pub=$3"
           " AND h_contract=$4"
           " AND h_wire=$5",
           5, NULL);

  /* Used in #postgres_get_coin_transactions() to obtain information
     about how a coin has been spend with /deposit requests. */
  PREPARE ("get_deposit_with_coin_pub",
           "SELECT"
           " transaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.fee_deposit_curr"
           ",timestamp"
           ",refund_deadline"
           ",merchant_pub"
           ",h_contract"
           ",h_wire"
           ",wire"
           ",coin_sig"
           " FROM deposits"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE coin_pub=$1",
           1, NULL);

  /* Used in #postgres_insert_refresh_out() to store the
     generated signature(s) for future requests, i.e. /refresh/link */
  PREPARE ("insert_refresh_out",
           "INSERT INTO refresh_out "
           "(session_hash"
           ",newcoin_index"
           ",ev_sig"
           ") VALUES "
           "($1, $2, $3)",
           3, NULL);

  /* Used in #postgres_get_link_data_list().  We use the session_hash
     to obtain the "noreveal_index" for that session, and then select the
     corresponding signatures (ev_sig) and the denomination keys from
     the respective tables (namely refresh_melts and refresh_order)
     using the session_hash as the primary filter (on join) and the
     'noreveal_index' to constrain the selection on the commitment.
     We also want to get the triplet for each of the newcoins, so we
     have another constraint to ensure we get each triplet with
     matching "newcoin_index" values.  NOTE: This may return many
     results, both for different sessions and for the different coins
     being exchangeed in the refresh ops.  NOTE: There may be more
     efficient ways to express the same query.  */
  PREPARE ("get_link",
           "SELECT ev_sig,ro.denom_pub"
           " FROM refresh_sessions rs "
           "     JOIN refresh_order ro USING (session_hash)"
           "     JOIN refresh_commit_coin rcc USING (session_hash)"
           "     JOIN refresh_out rc USING (session_hash)"
           " WHERE ro.session_hash=$1"
           "  AND ro.newcoin_index=rcc.newcoin_index"
           "  AND ro.newcoin_index=rc.newcoin_index",
           1, NULL);

  /* Used in #postgres_get_transfer().  Given the public key of a
     melted coin, we obtain the corresponding encrypted link secret
     and the transfer public key.  This is done by first finding
     the session_hash(es) of all sessions the coin was melted into,
     and then constraining the result to the selected "noreveal_index".
     NOTE: This may (in theory) return multiple results, one per session
     that the old coin was melted into. */
  PREPARE ("get_transfer",
           "SELECT transfer_pub,session_hash"
           " FROM refresh_sessions rs"
           "     JOIN refresh_transfer_public_key rcl USING (session_hash)"
           " WHERE rs.old_coin_pub=$1",
           1, NULL);

  /* Used in #postgres_lookup_wire_transfer */
  PREPARE ("lookup_transactions",
           "SELECT"
           " deposits.h_contract"
           ",deposits.h_wire"
           ",deposits.coin_pub"
           ",deposits.merchant_pub"
           ",deposits.transaction_id"
           ",execution_time"
           ",deposits.amount_with_fee_val"
           ",deposits.amount_with_fee_frac"
           ",deposits.amount_with_fee_curr"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.fee_deposit_curr"
           " FROM aggregation_tracking"
           "    JOIN deposits USING (deposit_serial_id)"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE wtid_raw=$1",
           1, NULL);

  /* Used in #postgres_wire_lookup_deposit_wtid */
  PREPARE ("lookup_deposit_wtid",
           "SELECT"
           " aggregation_tracking.wtid_raw"
           ",aggregation_tracking.execution_time"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",denom.fee_deposit_val"
           ",denom.fee_deposit_frac"
           ",denom.fee_deposit_curr"
           " FROM deposits"
           "    JOIN aggregation_tracking USING (deposit_serial_id)"
           "    JOIN known_coins USING (coin_pub)"
           "    JOIN denominations denom USING (denom_pub)"
           " WHERE coin_pub=$1"
           "  AND h_contract=$2"
           "  AND h_wire=$3"
           "  AND transaction_id=$4"
           "  AND merchant_pub=$5",
           5, NULL);

  /* Used in #postgres_insert_aggregation_tracking */
  PREPARE ("insert_aggregation_tracking",
           "INSERT INTO aggregation_tracking "
           "(deposit_serial_id"
           ",wtid_raw"
           ",execution_time"
           ") VALUES "
           "($1, $2, $3)",
           3, NULL);


  /* Used in #postgres_wire_prepare_data_insert() to store
     wire transfer information before actually committing it with the bank */
  PREPARE ("wire_prepare_data_insert",
           "INSERT INTO prewire "
           "(type"
           ",buf"
           ") VALUES "
           "($1, $2)",
           2, NULL);

  /* Used in #postgres_wire_prepare_data_mark_finished() */
  PREPARE ("wire_prepare_data_mark_done",
           "UPDATE prewire"
           " SET finished=true"
           " WHERE prewire_uuid=$1",
           1, NULL);

  /* Used in #postgres_wire_prepare_data_get() */
  PREPARE ("wire_prepare_data_get",
           "SELECT"
           " prewire_uuid"
           ",type"
           ",buf"
           " FROM prewire"
           " WHERE finished=false"
           " ORDER BY prewire_uuid ASC"
           " LIMIT 1",
           0, NULL);

  /* Used in #postgres_gc() */
  PREPARE ("gc_prewire",
           "DELETE"
           " FROM prewire"
           " WHERE finished=true",
           0, NULL);
  PREPARE ("gc_denominations",
           "DELETE"
           " FROM denominations"
           " WHERE expire_legal < $1",
           1, NULL);
  PREPARE ("gc_reserves",
           "DELETE"
           " FROM reserves"
           " WHERE expiration_date < $1"
           "   AND current_balance_val = 0"
           "   AND current_balance_frac = 0",
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
  struct TALER_EXCHANGEDB_Session *session = cls;
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
static struct TALER_EXCHANGEDB_Session *
postgres_get_session (void *cls)
{
  struct PostgresClosure *pc = cls;
  PGconn *db_conn;
  struct TALER_EXCHANGEDB_Session *session;

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
  session = GNUNET_new (struct TALER_EXCHANGEDB_Session);
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
                struct TALER_EXCHANGEDB_Session *session)
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
                   struct TALER_EXCHANGEDB_Session *session)
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
                 struct TALER_EXCHANGEDB_Session *session)
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
 * Insert a denomination key's public information into the database for
 * reference by auditors and other consistency checks.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub the public key used for signing coins of this denomination
 * @param issue issuing information with value, fees and other info about the coin
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_denomination_info (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const struct TALER_DenominationPublicKey *denom_pub,
                                   const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  PGresult *result;
  int ret;

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    GNUNET_PQ_query_param_auto_from_type (&issue->properties.master),
    GNUNET_PQ_query_param_auto_from_type (&issue->signature),
    GNUNET_PQ_query_param_absolute_time_nbo (&issue->properties.start),
    GNUNET_PQ_query_param_absolute_time_nbo (&issue->properties.expire_withdraw),
    GNUNET_PQ_query_param_absolute_time_nbo (&issue->properties.expire_deposit),
    GNUNET_PQ_query_param_absolute_time_nbo (&issue->properties.expire_legal),
    TALER_PQ_query_param_amount_nbo (&issue->properties.value),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_withdraw),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_deposit),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refresh),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refund),
    GNUNET_PQ_query_param_end
  };
  /* check fees match coin currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_withdraw));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_deposit));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_refresh));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency_nbo (&issue->properties.value,
                                                &issue->properties.fee_refund));

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "denomination_insert",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    ret = GNUNET_SYSERR;
    BREAK_DB_ERR (result);
  }
  else
  {
    ret = GNUNET_OK;
  }
  PQclear (result);
  return ret;
}


/**
 * Fetch information about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub the public key used for signing coins of this denomination
 * @param[out] issue set to issue information with value, fees and other info about the coin, can be NULL
 * @return #GNUNET_OK on success; #GNUNET_NO if no record was found, #GNUNET_SYSERR on failure
 */
static int
postgres_get_denomination_info (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const struct TALER_DenominationPublicKey *denom_pub,
                                struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    GNUNET_PQ_query_param_end
  };

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "denomination_get",
                                   params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }
  if (1 != PQntuples (result))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (NULL == issue)
  {
    PQclear (result);
    return GNUNET_OK;
  }
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_pub",
                                           &issue->properties.master),
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                           &issue->signature),
      GNUNET_PQ_result_spec_absolute_time_nbo ("valid_from",
                                              &issue->properties.start),
      GNUNET_PQ_result_spec_absolute_time_nbo ("expire_withdraw",
                                              &issue->properties.expire_withdraw),
      GNUNET_PQ_result_spec_absolute_time_nbo ("expire_deposit",
                                              &issue->properties.expire_deposit),
      GNUNET_PQ_result_spec_absolute_time_nbo ("expire_legal",
                                              &issue->properties.expire_legal),
      TALER_PQ_result_spec_amount_nbo ("coin",
                                       &issue->properties.value),
      TALER_PQ_result_spec_amount_nbo ("fee_withdraw",
                                       &issue->properties.fee_withdraw),
      TALER_PQ_result_spec_amount_nbo ("fee_deposit",
                                       &issue->properties.fee_deposit),
      TALER_PQ_result_spec_amount_nbo ("fee_refresh",
                                       &issue->properties.fee_refresh),
      TALER_PQ_result_spec_amount_nbo ("fee_refund",
                                       &issue->properties.fee_refund),
      GNUNET_PQ_result_spec_end
    };

    EXITIF (GNUNET_OK !=
            GNUNET_PQ_extract_result (result,
                                      rs,
                                      0));
  }
  PQclear (result);
  issue->properties.purpose.size = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
  issue->properties.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     &issue->properties.denom_hash);
  return GNUNET_OK;

 EXITIF_exit:
  PQclear (result);
  return GNUNET_SYSERR;
}


/**
 * Get the summary of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param[in,out] reserve the reserve data.  The public key of the reserve should be
 *          set in this structure; it is used to query the database.  The balance
 *          and expiration are then filled accordingly.
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_reserve_get (void *cls,
                      struct TALER_EXCHANGEDB_Session *session,
                      struct TALER_EXCHANGEDB_Reserve *reserve)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type(&reserve->pub),
    GNUNET_PQ_query_param_end
  };

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "reserve_get",
                                   params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_amount("current_balance", &reserve->balance),
      GNUNET_PQ_result_spec_absolute_time("expiration_date", &reserve->expiry),
      GNUNET_PQ_result_spec_end
    };

    EXITIF (GNUNET_OK !=
            GNUNET_PQ_extract_result (result,
                                     rs,
                                     0));
  }
  PQclear (result);
  return GNUNET_OK;

 EXITIF_exit:
  PQclear (result);
  return GNUNET_SYSERR;
}


/**
 * Updates a reserve with the data from the given reserve structure.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @param reserve the reserve structure whose data will be used to update the
 *          corresponding record in the database.
 * @return #GNUNET_OK upon successful update; #GNUNET_SYSERR upon any error
 */
static int
reserves_update (void *cls,
                 struct TALER_EXCHANGEDB_Session *session,
                 const struct TALER_EXCHANGEDB_Reserve *reserve)
{
  PGresult *result;
  int ret;

  if (NULL == reserve)
    return GNUNET_SYSERR;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&reserve->expiry),
    TALER_PQ_query_param_amount (&reserve->balance),
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };
  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "reserve_update",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    QUERY_ERR (result);
    ret = GNUNET_SYSERR;
  }
  else
  {
    ret = GNUNET_OK;
  }
  PQclear (result);
  return ret;
}


/**
 * Insert an incoming transaction into reserves.  New reserves are also created
 * through this function.  Note that this API call starts (and stops) its
 * own transaction scope (so the application must not do so).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param reserve_pub public key of the reserve
 * @param balance the amount that has to be added to the reserve
 * @param execution_time when was the amount added
 * @param sender_account_details account information for the sender
 * @param transfer_details information that uniquely identifies the transfer
 * @return #GNUNET_OK upon success; #GNUNET_NO if the given
 *         @a details are already known for this @a reserve_pub,
 *         #GNUNET_SYSERR upon failures (DB error, incompatible currency)
 */
static int
postgres_reserves_in_insert (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Absolute execution_time,
                             const json_t *sender_account_details,
                             const json_t *transfer_details)
{
  PGresult *result;
  int reserve_exists;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Absolute expiry;

  if (GNUNET_OK !=
      postgres_start (cls,
                      session))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  reserve.pub = *reserve_pub;
  reserve_exists = postgres_reserve_get (cls,
                                         session,
                                         &reserve);
  if (GNUNET_SYSERR == reserve_exists)
  {
    GNUNET_break (0);
    goto rollback;
  }
  expiry = GNUNET_TIME_absolute_add (execution_time,
                                     TALER_IDLE_RESERVE_EXPIRATION_TIME);
  if (GNUNET_NO == reserve_exists)
  {
    /* New reserve, create balance for the first time; we do this
       before adding the actual transaction to "reserves_in", as
       for a new reserve it can't be a duplicate 'add' operation,
       and as the 'add' operation may need the reserve entry
       as a foreign key. */
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_absolute_time (&expiry),
      GNUNET_PQ_query_param_end
    };

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    result = GNUNET_PQ_exec_prepared (session->conn,
                                      "reserve_create",
                                      params);
    if (PGRES_COMMAND_OK != PQresultStatus(result))
    {
      QUERY_ERR (result);
      PQclear (result);
      goto rollback;
    }
    PQclear (result);
  }
  /* Create new incoming transaction, SQL "primary key" logic
     is used to guard against duplicates.  If a duplicate is
     detected, we rollback (which really shouldn't undo
     anything) and return #GNUNET_NO to indicate that this failure
     is kind-of harmless (already executed). */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserve.pub),
      TALER_PQ_query_param_amount (balance),
      TALER_PQ_query_param_json (sender_account_details),
      TALER_PQ_query_param_json (transfer_details),
      GNUNET_PQ_query_param_absolute_time (&execution_time),
      GNUNET_PQ_query_param_end
    };

    result = GNUNET_PQ_exec_prepared (session->conn,
                                      "reserves_in_add_transaction",
                                      params);
  }
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    const char *efield;

    efield = PQresultErrorField (result,
				 PG_DIAG_SQLSTATE);
    if ( (PGRES_FATAL_ERROR == PQresultStatus(result)) &&
	 (NULL != strstr ("23505", /* unique violation */
			  efield)) )
    {
      /* This means we had the same reserve/justification/details
	 before */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Uniqueness violation, deposit details already known\n");
      PQclear (result);
      postgres_rollback (cls,
			 session);
      return GNUNET_NO;
    }
    QUERY_ERR (result);
    PQclear (result);
    goto rollback;
  }
  PQclear (result);

  if (GNUNET_YES == reserve_exists)
  {
    /* If the reserve already existed, we need to still update the
       balance; we do this after checking for duplication, as
       otherwise we might have to actually pay the cost to roll this
       back for duplicate transactions; like this, we should virtually
       never actually have to rollback anything. */
    struct TALER_EXCHANGEDB_Reserve updated_reserve;

    updated_reserve.pub = reserve.pub;
    if (GNUNET_OK !=
        TALER_amount_add (&updated_reserve.balance,
                          &reserve.balance,
                          balance))
    {
      /* currency overflow or incompatible currency */
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Attempt to deposit incompatible amount into reserve\n");
      goto rollback;
    }
    updated_reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                                       reserve.expiry);
    if (GNUNET_OK != reserves_update (cls,
                                      session,
                                      &updated_reserve))
      goto rollback;
  }
  if (GNUNET_OK != postgres_commit (cls,
                                    session))
    return GNUNET_SYSERR;
  return GNUNET_OK;

 rollback:
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Transaction failed, doing rollback\n");
  postgres_rollback (cls,
                     session);
  return GNUNET_SYSERR;
}


/**
 * Locate the response for a /reserve/withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param h_blind hash of the blinded coin to be signed (will match
 *                `h_coin_envelope` in the @a collectable to be returned)
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
static int
postgres_get_withdraw_info (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct GNUNET_HashCode *h_blind,
                            struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind),
    GNUNET_PQ_query_param_end
  };
  int ret;

  ret = GNUNET_SYSERR;
  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "get_withdraw_info",
                                   params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    goto cleanup;
  }
  if (0 == PQntuples (result))
  {
    ret = GNUNET_NO;
    goto cleanup;
  }
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                           &collectable->denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                          &collectable->sig.rsa_signature),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                           &collectable->reserve_sig),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                           &collectable->reserve_pub),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &collectable->amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_withdraw",
                                   &collectable->withdraw_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      goto cleanup;
    }
  }
  collectable->h_coin_envelope = *h_blind;
  ret = GNUNET_YES;

 cleanup:
  PQclear (result);
  return ret;
}


/**
 * Store collectable bit coin under the corresponding
 * hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
static int
postgres_insert_withdraw_info (void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_EXCHANGEDB_Reserve reserve;
  int ret = GNUNET_SYSERR;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute expiry;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    GNUNET_PQ_query_param_rsa_public_key (collectable->denom_pub.rsa_public_key),
    GNUNET_PQ_query_param_rsa_signature (collectable->sig.rsa_signature),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    GNUNET_PQ_query_param_absolute_time (&now),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    GNUNET_PQ_query_param_end
  };

  now = GNUNET_TIME_absolute_get ();
  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "insert_withdraw_info",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    goto cleanup;
  }
  reserve.pub = collectable->reserve_pub;
  if (GNUNET_OK != postgres_reserve_get (cls,
                                         session,
                                         &reserve))
  {
    /* Should have been checked before we got here... */
    GNUNET_break (0);
    goto cleanup;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&reserve.balance,
                             &reserve.balance,
                             &collectable->amount_with_fee))
  {
    /* Should have been checked before we got here... */
    GNUNET_break (0);
    goto cleanup;
  }
  expiry = GNUNET_TIME_absolute_add (now,
                                     TALER_IDLE_RESERVE_EXPIRATION_TIME);
  reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                             reserve.expiry);
  if (GNUNET_OK != reserves_update (cls,
                                    session,
                                    &reserve))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  ret = GNUNET_OK;
 cleanup:
  PQclear (result);
  return ret;
}


/**
 * Get all of the transaction history associated with the specified
 * reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @return known transaction history (NULL if reserve is unknown)
 */
static struct TALER_EXCHANGEDB_ReserveHistory *
postgres_get_reserve_history (void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub)
{
  PGresult *result;
  struct TALER_EXCHANGEDB_ReserveHistory *rh;
  struct TALER_EXCHANGEDB_ReserveHistory *rh_tail;
  int rows;
  int ret;

  rh = NULL;
  rh_tail = NULL;
  ret = GNUNET_SYSERR;
  {
    struct TALER_EXCHANGEDB_BankTransfer *bt;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      GNUNET_PQ_query_param_end
    };

    result = GNUNET_PQ_exec_prepared (session->conn,
                                      "reserves_in_get_transactions",
                                      params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      QUERY_ERR (result);
      goto cleanup;
    }
    if (0 == (rows = PQntuples (result)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Asked to fetch history for an unknown reserve.\n");
      goto cleanup;
    }
    while (0 < rows)
    {
      bt = GNUNET_new (struct TALER_EXCHANGEDB_BankTransfer);
      {
        struct GNUNET_PQ_ResultSpec rs[] = {
          TALER_PQ_result_spec_amount ("credit",
                                       &bt->amount),
          GNUNET_PQ_result_spec_absolute_time ("execution_date",
                                              &bt->execution_date),
          TALER_PQ_result_spec_json ("sender_account_details",
                                     &bt->sender_account_details),
          TALER_PQ_result_spec_json ("transfer_details",
                                     &bt->transfer_details),
          GNUNET_PQ_result_spec_end
        };
        if (GNUNET_OK !=
            GNUNET_PQ_extract_result (result, rs, --rows))
        {
          GNUNET_break (0);
          GNUNET_free (bt);
          PQclear (result);
          goto cleanup;
        }
      }
      bt->reserve_pub = *reserve_pub;
      if (NULL != rh_tail)
      {
        rh_tail->next = GNUNET_new (struct TALER_EXCHANGEDB_ReserveHistory);
        rh_tail = rh_tail->next;
      }
      else
      {
        rh_tail = GNUNET_new (struct TALER_EXCHANGEDB_ReserveHistory);
        rh = rh_tail;
      }
      rh_tail->type = TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE;
      rh_tail->details.bank = bt;
    }
    PQclear (result);
  }
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      GNUNET_PQ_query_param_end
    };

    GNUNET_assert (NULL != rh);
    GNUNET_assert (NULL != rh_tail);
    GNUNET_assert (NULL == rh_tail->next);
    result = GNUNET_PQ_exec_prepared (session->conn,
                                     "get_reserves_out",
                                     params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      QUERY_ERR (result);
      PQclear (result);
      goto cleanup;
    }
    rows = PQntuples (result);
    while (0 < rows)
    {
      struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;

      cbc = GNUNET_new (struct TALER_EXCHANGEDB_CollectableBlindcoin);
      {
        struct GNUNET_PQ_ResultSpec rs[] = {
          GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                               &cbc->h_coin_envelope),
          GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                               &cbc->denom_pub.rsa_public_key),
          GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                              &cbc->sig.rsa_signature),
          GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                               &cbc->reserve_sig),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &cbc->amount_with_fee),
          TALER_PQ_result_spec_amount ("fee_withdraw",
                                       &cbc->withdraw_fee),
          GNUNET_PQ_result_spec_end
        };
        if (GNUNET_OK !=
            GNUNET_PQ_extract_result (result, rs, --rows))
        {
          GNUNET_break (0);
          GNUNET_free (cbc);
          PQclear (result);
          goto cleanup;
        }
        cbc->reserve_pub = *reserve_pub;
      }
      rh_tail->next = GNUNET_new (struct TALER_EXCHANGEDB_ReserveHistory);
      rh_tail = rh_tail->next;
      rh_tail->type = TALER_EXCHANGEDB_RO_WITHDRAW_COIN;
      rh_tail->details.withdraw = cbc;
    }
    ret = GNUNET_OK;
    PQclear (result);
  }
 cleanup:
  if (GNUNET_SYSERR == ret)
  {
    common_free_reserve_history (cls,
                                 rh);
    rh = NULL;
  }
  return rh;
}


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param deposit deposit to search for
 * @return #GNUNET_YES if we know this operation,
 *         #GNUNET_NO if this exact deposit is unknown to us
 *         #GNUNET_SYSERR on DB error
 */
static int
postgres_have_deposit (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_uint64 (&deposit->transaction_id),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "get_deposit",
                                   params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }

  /* Now we check that the other information in @a deposit
     also matches, and if not report inconsistencies. */
  {
    struct TALER_EXCHANGEDB_Deposit deposit2;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &deposit2.amount_with_fee),
      GNUNET_PQ_result_spec_absolute_time ("timestamp",
                                          &deposit2.timestamp),
      GNUNET_PQ_result_spec_absolute_time ("refund_deadline",
                                          &deposit2.refund_deadline),
      GNUNET_PQ_result_spec_absolute_time ("wire_deadline",
                                          &deposit2.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract",
                                           &deposit2.h_contract),
      GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                           &deposit2.h_wire),
      GNUNET_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    if ( (0 != TALER_amount_cmp (&deposit->amount_with_fee,
                                 &deposit2.amount_with_fee)) ||
         (deposit->timestamp.abs_value_us !=
          deposit2.timestamp.abs_value_us) ||
         (deposit->refund_deadline.abs_value_us !=
          deposit2.refund_deadline.abs_value_us) ||
         (0 != memcmp (&deposit->h_contract,
                       &deposit2.h_contract,
                       sizeof (struct GNUNET_HashCode))) ||
         (0 != memcmp (&deposit->h_wire,
                       &deposit2.h_wire,
                       sizeof (struct GNUNET_HashCode))) )
    {
      /* Inconsistencies detected! Does not match!  (We might want to
         expand the API with a 'get_deposit' function to return the
         original transaction details to be used for an error message
         in the future!) #3838 */
      PQclear (result);
      return GNUNET_NO;
    }
  }
  PQclear (result);
  return GNUNET_YES;
}


/**
 * Mark a deposit as tiny, thereby declaring that it cannot be
 * executed by itself and should no longer be returned by
 * @e iterate_ready_deposits()
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param deposit_serial_id identifies the deposit row to modify
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
postgres_mark_deposit_tiny (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            unsigned long long rowid)
{
  uint64_t serial_id = rowid;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "mark_deposit_tiny",
                                   params);
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Test if a deposit was marked as done, thereby declaring that it cannot be
 * refunded anymore.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param deposit the deposit to check
 * @return #GNUNET_YES if is is marked done done, #GNUNET_NO if not,
 *         #GNUNET_SYSERR on error (deposit unknown)
 */
static int
postgres_test_deposit_done (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_uint64 (&deposit->transaction_id),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_wire),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "test_deposit_done",
                                    params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (1 != PQntuples (result))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  {
    uint8_t done = 0;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("done",
                                            &done),
      GNUNET_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    PQclear (result);
    return (done ? GNUNET_YES : GNUNET_NO);
  }
}


/**
 * Mark a deposit as done, thereby declaring that it cannot be
 * executed at all anymore, and should no longer be returned by
 * @e iterate_ready_deposits() or @e iterate_matching_deposits().
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param deposit_serial_id identifies the deposit row to modify
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
postgres_mark_deposit_done (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            unsigned long long rowid)
{
  uint64_t serial_id = rowid;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "mark_deposit_done",
                                   params);
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Obtain information about deposits that are ready to be executed.
 * Such deposits must not be marked as "tiny" or "done", and the
 * execution time must be in the past.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param deposit_cb function to call for ONE such deposit
 * @param deposit_cb_cls closure for @a deposit_cb
 * @return number of rows processed, 0 if none exist,
 *         #GNUNET_SYSERR on error
 */
static int
postgres_get_ready_deposit (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            TALER_EXCHANGEDB_DepositIterator deposit_cb,
                            void *deposit_cb_cls)
{
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;
  unsigned int n;
  int ret;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "deposits_get_ready",
                                   params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == (n = PQntuples (result)))
  {
    PQclear (result);
    return 0;
  }
  GNUNET_break (1 == n);
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_TIME_Absolute wire_deadline;
    struct GNUNET_HashCode h_contract;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    uint64_t transaction_id;
    uint64_t serial_id;
    json_t *wire;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                   &serial_id),
      GNUNET_PQ_result_spec_uint64 ("transaction_id",
                                   &transaction_id),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit",
                                   &deposit_fee),
      GNUNET_PQ_result_spec_absolute_time ("wire_deadline",
                                          &wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract",
                                           &h_contract),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                           &merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                           &coin_pub),
      TALER_PQ_result_spec_json ("wire",
                                 &wire),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    ret = deposit_cb (deposit_cb_cls,
                      serial_id,
                      &merchant_pub,
                      &coin_pub,
                      &amount_with_fee,
                      &deposit_fee,
                      transaction_id,
                      &h_contract,
                      wire_deadline,
                      wire);
    GNUNET_PQ_cleanup_result (rs);
    PQclear (result);
  }
  return (GNUNET_OK == ret) ? 1 : 0;
}


/**
 * Obtain information about other pending deposits for the same
 * destination.  Those deposits must not already be "done".
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param h_wire destination of the wire transfer
 * @param merchant_pub public key of the merchant
 * @param deposit_cb function to call for each deposit
 * @param deposit_cb_cls closure for @a deposit_cb
 * @param limit maximum number of matching deposits to return
 * @return number of rows processed, 0 if none exist,
 *         #GNUNET_SYSERR on error
 */
static int
postgres_iterate_matching_deposits (void *cls,
                                    struct TALER_EXCHANGEDB_Session *session,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct TALER_MerchantPublicKeyP *merchant_pub,
                                    TALER_EXCHANGEDB_DepositIterator deposit_cb,
                                    void *deposit_cb_cls,
                                    uint32_t limit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;
  unsigned int i;
  unsigned int n;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "deposits_iterate_matching",
                                    params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == (n = PQntuples (result)))
  {
    PQclear (result);
    return 0;
  }
  if (n > limit)
    n = limit;
  for (i=0;i<n;i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_TIME_Absolute wire_deadline;
    struct GNUNET_HashCode h_contract;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    uint64_t transaction_id;
    uint64_t serial_id;
    int ret;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &serial_id),
      GNUNET_PQ_result_spec_uint64 ("transaction_id",
                                    &transaction_id),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit",
                                   &deposit_fee),
      GNUNET_PQ_result_spec_absolute_time ("wire_deadline",
                                           &wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract",
                                            &h_contract),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, i))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    ret = deposit_cb (deposit_cb_cls,
                      serial_id,
                      merchant_pub,
                      &coin_pub,
                      &amount_with_fee,
                      &deposit_fee,
                      transaction_id,
                      &h_contract,
                      wire_deadline,
                      NULL);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
  PQclear (result);
  return i;
}


/**
 * Retrieve the record for a known coin.
 *
 * @param cls the plugin closure
 * @param session the database session handle
 * @param coin_pub the public key of the coin to search for
 * @param coin_info place holder for the returned coin information object
 * @return #GNUNET_SYSERR upon error; #GNUNET_NO if no coin is found; #GNUNET_OK
 *           if upon succesfullying retrieving the record data info @a
 *           coin_info
 */
static int
get_known_coin (void *cls,
                struct TALER_EXCHANGEDB_Session *session,
                const struct TALER_CoinSpendPublicKeyP *coin_pub,
                struct TALER_CoinPublicInfo *coin_info)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  int nrows;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "get_known_coin",
                                   params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  nrows = PQntuples (result);
  if (0 == nrows)
  {
    PQclear (result);
    return GNUNET_NO;
  }
  GNUNET_assert (1 == nrows);   /* due to primary key */
  if (NULL == coin_info)
  {
    PQclear (result);
    return GNUNET_YES;
  }
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &coin_info->denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                           &coin_info->denom_sig.rsa_signature),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      PQclear (result);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  PQclear (result);
  coin_info->coin_pub = *coin_pub;
  return GNUNET_OK;
}


/**
 * Insert a coin we know of into the DB.  The coin can then be referenced by
 * tables for deposits, refresh and refund functionality.
 *
 * @param cls plugin closure
 * @param session the shared database session
 * @param coin_info the public coin info
 * @return #GNUNET_SYSERR upon error; #GNUNET_OK upon success
 */
static int
insert_known_coin (void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_CoinPublicInfo *coin_info)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin_info->coin_pub),
    GNUNET_PQ_query_param_rsa_public_key (coin_info->denom_pub.rsa_public_key),
    GNUNET_PQ_query_param_rsa_signature (coin_info->denom_sig.rsa_signature),
    GNUNET_PQ_query_param_end
  };
  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "insert_known_coin",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Insert information about deposited coin into the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session connection to the database
 * @param deposit deposit information to store
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
postgres_insert_deposit (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  PGresult *result;
  int ret;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_uint64 (&deposit->transaction_id),
    TALER_PQ_query_param_amount (&deposit->amount_with_fee),
    GNUNET_PQ_query_param_absolute_time (&deposit->timestamp),
    GNUNET_PQ_query_param_absolute_time (&deposit->refund_deadline),
    GNUNET_PQ_query_param_absolute_time (&deposit->wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_wire),
    GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
    TALER_PQ_query_param_json (deposit->receiver_wire_account),
    GNUNET_PQ_query_param_end
  };

  /* check if the coin is already known */
  ret = get_known_coin (cls,
                        session,
                        &deposit->coin.coin_pub,
                        NULL);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)         /* if not, insert it */
  {
    if (GNUNET_SYSERR ==
        insert_known_coin (cls,
                           session,
                           &deposit->coin))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "insert_deposit",
                                    params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    ret = GNUNET_SYSERR;
  }
  else
  {
    ret = GNUNET_OK;
  }
  PQclear (result);
  return ret;
}


/**
 * Insert information about refunded coin into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param refund refund information to store
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
postgres_insert_refund (void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_Refund *refund)
{
  PGresult *result;
  int ret;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->merchant_sig),
    GNUNET_PQ_query_param_auto_from_type (&refund->h_contract),
    GNUNET_PQ_query_param_uint64 (&refund->transaction_id),
    GNUNET_PQ_query_param_uint64 (&refund->rtransaction_id),
    TALER_PQ_query_param_amount (&refund->refund_amount),
    GNUNET_PQ_query_param_end
  };
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&refund->refund_amount,
                                            &refund->refund_fee));
  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "insert_refund",
                                    params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    ret = GNUNET_SYSERR;
    BREAK_DB_ERR (result);
  }
  else
  {
    ret = GNUNET_OK;
  }
  PQclear (result);
  return ret;
}


/**
 * Lookup refresh session data under the given @a session_hash.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param session_hash hash over the melt to use to locate the session
 * @param[out] refresh_session where to store the result, can be NULL
 *             to just check if the session exists
 * @return #GNUNET_YES on success,
 *         #GNUNET_NO if not found,
 *         #GNUNET_SYSERR on DB failure
 */
static int
postgres_get_refresh_session (void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct GNUNET_HashCode *session_hash,
                              struct TALER_EXCHANGEDB_RefreshSession *refresh_session)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (session_hash),
    GNUNET_PQ_query_param_end
  };

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "get_refresh_session",
                                    params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }
  GNUNET_assert (1 == PQntuples (result));
  if (NULL == refresh_session)
  {
    /* We're done if the caller is only interested in whether the
     * session exists or not */
    PQclear (result);
    return GNUNET_YES;
  }
  memset (refresh_session,
          0,
          sizeof (struct TALER_EXCHANGEDB_RefreshSession));
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint16 ("num_newcoins",
                                    &refresh_session->num_newcoins),
      GNUNET_PQ_result_spec_uint16 ("noreveal_index",
                                    &refresh_session->noreveal_index),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &refresh_session->melt.coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                            &refresh_session->melt.coin_sig),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &refresh_session->melt.amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_refresh",
                                   &refresh_session->melt.melt_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
  }
  PQclear (result);
  if (GNUNET_OK !=
      get_known_coin (cls,
                      session,
                      &refresh_session->melt.coin.coin_pub,
                      &refresh_session->melt.coin))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  refresh_session->melt.session_hash = *session_hash;
  return GNUNET_YES;
}


/**
 * Store new refresh session data under the given @a session_hash.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param session_hash hash over the melt to use to locate the session
 * @param refresh_session session data to store
 * @return #GNUNET_YES on success,
 *         #GNUNET_SYSERR on DB failure
 */
static int
postgres_create_refresh_session (void *cls,
                                 struct TALER_EXCHANGEDB_Session *session,
                                 const struct GNUNET_HashCode *session_hash,
                                 const struct TALER_EXCHANGEDB_RefreshSession *refresh_session)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (session_hash),
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->melt.coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->melt.coin_sig),
    TALER_PQ_query_param_amount (&refresh_session->melt.amount_with_fee),
    GNUNET_PQ_query_param_uint16 (&refresh_session->num_newcoins),
    GNUNET_PQ_query_param_uint16 (&refresh_session->noreveal_index),
    GNUNET_PQ_query_param_end
  };
  int ret;

  /* check if the coin is already known */
  ret = get_known_coin (cls,
                        session,
                        &refresh_session->melt.coin.coin_pub,
                        NULL);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)         /* if not, insert it */
  {
    if (GNUNET_SYSERR ==
        insert_known_coin (cls,
                           session,
                           &refresh_session->melt.coin))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  /* insert session */
  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "insert_refresh_session",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Store in the database which coin(s) we want to create
 * in a given refresh operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param session_hash hash to identify refresh session
 * @param num_newcoins number of coins to generate, size of the @a denom_pubs array
 * @param denom_pubs array denominations of the coins to create
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
static int
postgres_insert_refresh_order (void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               const struct GNUNET_HashCode *session_hash,
                               uint16_t num_newcoins,
                               const struct TALER_DenominationPublicKey *denom_pubs)
{
  unsigned int i;

  for (i=0;i<(unsigned int) num_newcoins;i++)
  {
    uint16_t newcoin_off = (uint16_t) i;
    PGresult *result;

    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_uint16 (&newcoin_off),
        GNUNET_PQ_query_param_auto_from_type (session_hash),
        GNUNET_PQ_query_param_rsa_public_key (denom_pubs[i].rsa_public_key),
        GNUNET_PQ_query_param_end
      };
      result = GNUNET_PQ_exec_prepared (session->conn,
                                       "insert_refresh_order",
                                       params);
    }
    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    if (0 != strcmp ("1", PQcmdTuples (result)))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    PQclear (result);
  }
  return GNUNET_OK;
}


/**
 * We allocated some @a denom_pubs information, but now need
 * to abort. Free allocated memory.
 *
 * @param denom_pubs data to free (but not the array itself)
 * @param denom_pubs_len length of @a denom_pubs array
 */
static void
free_dpk_result (struct TALER_DenominationPublicKey *denom_pubs,
                 unsigned int denom_pubs_len)
{
  unsigned int i;

  for (i=0;i<denom_pubs_len;i++)
  {
    GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[i].rsa_public_key);
    denom_pubs[i].rsa_public_key = NULL;
  }
}


/**
 * Lookup in the database the coins that we want to
 * create in the given refresh operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param session_hash hash to identify refresh session
 * @param num_newcoins size of the array of the @a denom_pubs array
 * @param denom_pubs where to store the deomination keys
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
static int
postgres_get_refresh_order (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct GNUNET_HashCode *session_hash,
                            uint16_t num_newcoins,
                            struct TALER_DenominationPublicKey *denom_pubs)
{
  unsigned int i;

  for (i=0;i<(unsigned int) num_newcoins;i++)
  {
    uint16_t newcoin_off = (uint16_t) i;
    PGresult *result;

    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (session_hash),
        GNUNET_PQ_query_param_uint16 (&newcoin_off),
        GNUNET_PQ_query_param_end
      };

      result = GNUNET_PQ_exec_prepared (session->conn,
                                       "get_refresh_order",
                                       params);
    }
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      free_dpk_result (denom_pubs, i);
      return GNUNET_SYSERR;
    }
    if (0 == PQntuples (result))
    {
      PQclear (result);
      /* FIXME: may want to distinguish between different error cases! */
      free_dpk_result (denom_pubs, i);
      return GNUNET_SYSERR;
    }
    GNUNET_assert (1 == PQntuples (result));
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                             &denom_pubs[i].rsa_public_key),
        GNUNET_PQ_result_spec_end
      };
      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result, rs, 0))
      {
        PQclear (result);
        GNUNET_break (0);
        free_dpk_result (denom_pubs, i);
        return GNUNET_SYSERR;
      }
      PQclear (result);
    }
  }
  return GNUNET_OK;
}


/**
 * Store information about the commitment of the
 * given coin for the given refresh session in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param num_newcoins coin index size of the @a commit_coins array
 * @param commit_coins array of coin commitments to store
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on error
 */
static int
postgres_insert_refresh_commit_coins (void *cls,
                                      struct TALER_EXCHANGEDB_Session *session,
                                      const struct GNUNET_HashCode *session_hash,
                                      uint16_t num_newcoins,
                                      const struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins)
{
  PGresult *result;
  unsigned int i;
  uint16_t coin_off;

  for (i=0;i<(unsigned int) num_newcoins;i++)
  {
    coin_off = (uint16_t) i;
    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (session_hash),
        GNUNET_PQ_query_param_uint16 (&coin_off),
        GNUNET_PQ_query_param_fixed_size (commit_coins[i].coin_ev,
					  commit_coins[i].coin_ev_size),
        GNUNET_PQ_query_param_end
      };
      result = GNUNET_PQ_exec_prepared (session->conn,
                                       "insert_refresh_commit_coin",
                                       params);
    }
    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    if (0 != strcmp ("1", PQcmdTuples (result)))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    PQclear (result);
  }
  return GNUNET_OK;
}


/**
 * We allocated some @a commit_coin information, but now need
 * to abort. Free allocated memory.
 *
 * @param cls unused
 * @param commit_coins_len length of @a commit_coins array
 * @param commit_coins data to free (but not the array itself)
 */
static void
postgres_free_refresh_commit_coins (void *cls,
                                    unsigned int commit_coins_len,
                                    struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins)
{
  unsigned int i;

  for (i=0;i<commit_coins_len;i++)
  {
    GNUNET_free (commit_coins[i].coin_ev);
    commit_coins[i].coin_ev = NULL;
    commit_coins[i].coin_ev_size = 0;
  }
}


/**
 * Obtain information about the commitment of the
 * given coin of the given refresh session from the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param num_newcoins size of the @a commit_coins array
 * @param[out] commit_coins array of coin commitments to return
 * @return #GNUNET_OK on success
 *         #GNUNET_NO if not found
 *         #GNUNET_SYSERR on error
 */
static int
postgres_get_refresh_commit_coins (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const struct GNUNET_HashCode *session_hash,
                                   uint16_t num_newcoins,
                                   struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins)
{
  unsigned int i;

  for (i=0;i<(unsigned int) num_newcoins;i++)
  {
    uint16_t newcoin_off = (uint16_t) i;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (session_hash),
      GNUNET_PQ_query_param_uint16 (&newcoin_off),
      GNUNET_PQ_query_param_end
    };
    void *c_buf;
    size_t c_buf_size;
    PGresult *result;

    result = GNUNET_PQ_exec_prepared (session->conn,
                                     "get_refresh_commit_coin",
                                     params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      postgres_free_refresh_commit_coins (cls, i, commit_coins);
      return GNUNET_SYSERR;
    }
    if (0 == PQntuples (result))
    {
      PQclear (result);
      postgres_free_refresh_commit_coins (cls, i, commit_coins);
      return GNUNET_NO;
    }
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_variable_size ("coin_ev",
					     &c_buf,
					     &c_buf_size),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_YES !=
          GNUNET_PQ_extract_result (result, rs, 0))
      {
        PQclear (result);
        postgres_free_refresh_commit_coins (cls, i, commit_coins);
        return GNUNET_SYSERR;
      }
    }
    PQclear (result);
    commit_coins[i].coin_ev = c_buf;
    commit_coins[i].coin_ev_size = c_buf_size;
  }
  return GNUNET_YES;
}


/**
 * Store the commitment to the given (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param tp transfer public key to store
 * @return #GNUNET_SYSERR on internal error, #GNUNET_OK on success
 */
static int
postgres_insert_refresh_transfer_public_key (void *cls,
                                             struct TALER_EXCHANGEDB_Session *session,
                                             const struct GNUNET_HashCode *session_hash,
                                             const struct TALER_TransferPublicKeyP *tp)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (session_hash),
    GNUNET_PQ_query_param_auto_from_type (tp),
    GNUNET_PQ_query_param_end
  };

  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "insert_transfer_public_key",
                                    params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Obtain the commited (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param[out] tp information to return
 * @return #GNUNET_SYSERR on internal error,
 *         #GNUNET_NO if commitment was not found
 *         #GNUNET_OK on success
 */
static int
postgres_get_refresh_transfer_public_key (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          const struct GNUNET_HashCode *session_hash,
                                          struct TALER_TransferPublicKeyP *tp)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (session_hash),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "get_refresh_transfer_public_key",
                                    params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                            tp),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_YES !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      PQclear (result);
      return GNUNET_SYSERR;
    }
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Insert signature of a new coin generated during refresh into
 * the database indexed by the refresh session and the index
 * of the coin.  This data is later used should an old coin
 * be used to try to obtain the private keys during "/refresh/link".
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param session_hash hash to identify refresh session
 * @param newcoin_index coin index
 * @param ev_sig coin signature
 * @return #GNUNET_OK on success
 */
static int
postgres_insert_refresh_out (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct GNUNET_HashCode *session_hash,
                             uint16_t newcoin_index,
                             const struct TALER_DenominationSignature *ev_sig)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (session_hash),
    GNUNET_PQ_query_param_uint16 (&newcoin_index),
    GNUNET_PQ_query_param_rsa_signature (ev_sig->rsa_signature),
    GNUNET_PQ_query_param_end
  };

  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "insert_refresh_out",
                                    params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Obtain the link data of a coin, that is the encrypted link
 * information, the denomination keys and the signatures.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param session_hash refresh session to get linkage data for
 * @return all known link data for the session
 */
static struct TALER_EXCHANGEDB_LinkDataList *
postgres_get_link_data_list (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct GNUNET_HashCode *session_hash)
{
  struct TALER_EXCHANGEDB_LinkDataList *ldl;
  int i;
  int nrows;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (session_hash),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "get_link",
                                   params);
  ldl = NULL;
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return NULL;
  }
  nrows = PQntuples (result);
  if (0 == nrows)
  {
    PQclear (result);
    return NULL;
  }

  for (i = nrows-1; i >= 0; i--)
  {
    struct GNUNET_CRYPTO_RsaPublicKey *denom_pub;
    struct GNUNET_CRYPTO_RsaSignature *sig;
    struct TALER_EXCHANGEDB_LinkDataList *pos;

    pos = GNUNET_new (struct TALER_EXCHANGEDB_LinkDataList);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
	GNUNET_PQ_result_spec_rsa_signature ("ev_sig",
					     &sig),
	GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
					      &denom_pub),
	GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
	  GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
	PQclear (result);
	GNUNET_break (0);
	common_free_link_data_list (cls,
				    ldl);
	GNUNET_free (pos);
	return NULL;
      }
    }
    pos->next = ldl;
    pos->denom_pub.rsa_public_key = denom_pub;
    pos->ev_sig.rsa_signature = sig;
    ldl = pos;
  }
  PQclear (result);
  return ldl;
}


/**
 * Obtain shared secret and transfer public key from the public key of
 * the coin.  This information and the link information returned by
 * #postgres_get_link_data_list() enable the owner of an old coin to
 * determine the private keys of the new coins after the melt.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub public key of the coin
 * @param tdc function to call for each session the coin was melted into
 * @param tdc_cls closure for @a tdc
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO on failure (not found)
 *         #GNUNET_SYSERR on internal failure (database issue)
 */
static int
postgres_get_transfer (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       TALER_EXCHANGEDB_TransferDataCallback tdc,
                       void *tdc_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;
  int nrows;
  int i;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "get_transfer",
                                   params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  nrows = PQntuples (result);
  if (0 == nrows)
  {
    /* no matches found */
    PQclear (result);
    return GNUNET_NO;
  }
  for (i=0;i<nrows;i++)
  {
    struct GNUNET_HashCode session_hash;
    struct TALER_TransferPublicKeyP transfer_pub;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("transfer_pub", &transfer_pub),
      GNUNET_PQ_result_spec_auto_from_type ("session_hash", &session_hash),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result, rs, 0))
    {
      PQclear (result);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    tdc (tdc_cls,
         &session_hash,
         &transfer_pub);
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Compile a list of all (historic) transactions performed
 * with the given coin (/refresh/melt, /deposit and /refund operations).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub coin to investigate
 * @return list of transactions, NULL if coin is fresh
 */
static struct TALER_EXCHANGEDB_TransactionList *
postgres_get_coin_transactions (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  struct TALER_EXCHANGEDB_TransactionList *head;

  head = NULL;
  /* check deposits */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&coin_pub->eddsa_pub),
      GNUNET_PQ_query_param_end
    };
    int nrows;
    int i;
    PGresult *result;
    struct TALER_EXCHANGEDB_TransactionList *tl;

    result = GNUNET_PQ_exec_prepared (session->conn,
                                      "get_deposit_with_coin_pub",
                                      params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      QUERY_ERR (result);
      PQclear (result);
      goto cleanup;
    }
    nrows = PQntuples (result);
    for (i = 0; i < nrows; i++)
    {
      struct TALER_EXCHANGEDB_Deposit *deposit;

      deposit = GNUNET_new (struct TALER_EXCHANGEDB_Deposit);
      {
        struct GNUNET_PQ_ResultSpec rs[] = {
          GNUNET_PQ_result_spec_uint64 ("transaction_id",
                                        &deposit->transaction_id),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &deposit->amount_with_fee),
          TALER_PQ_result_spec_amount ("fee_deposit",
                                       &deposit->deposit_fee),
          GNUNET_PQ_result_spec_absolute_time ("timestamp",
                                               &deposit->timestamp),
          GNUNET_PQ_result_spec_absolute_time ("refund_deadline",
                                               &deposit->refund_deadline),
          GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                                &deposit->merchant_pub),
          GNUNET_PQ_result_spec_auto_from_type ("h_contract",
                                                &deposit->h_contract),
          GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                                &deposit->h_wire),
          TALER_PQ_result_spec_json ("wire",
                                     &deposit->receiver_wire_account),
          GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                               &deposit->csig),
          GNUNET_PQ_result_spec_end
        };

        if (GNUNET_OK !=
            GNUNET_PQ_extract_result (result, rs, i))
        {
          GNUNET_break (0);
          GNUNET_free (deposit);
          PQclear (result);
          goto cleanup;
        }
        deposit->coin.coin_pub = *coin_pub;
      }
      tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
      tl->next = head;
      tl->type = TALER_EXCHANGEDB_TT_DEPOSIT;
      tl->details.deposit = deposit;
      if (GNUNET_SYSERR == get_known_coin (cls,
                                           session,
                                           &deposit->coin.coin_pub,
                                           &deposit->coin))
      {
        GNUNET_break (0);
        GNUNET_free (deposit);
        PQclear (result);
        goto cleanup;
      }
      head = tl;
      continue;
    }
    PQclear (result);
  }
  /* Handle refreshing */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&coin_pub->eddsa_pub),
      GNUNET_PQ_query_param_end
    };
    int nrows;
    int i;
    PGresult *result;
    struct TALER_EXCHANGEDB_TransactionList *tl;

    /* check if the melt records exist and get them */
    result = GNUNET_PQ_exec_prepared (session->conn,
                                      "get_refresh_session_by_coin",
                                      params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      goto cleanup;
    }
    nrows = PQntuples (result);
    for (i=0;i<nrows;i++)
    {
      struct TALER_EXCHANGEDB_RefreshMelt *melt;

      melt = GNUNET_new (struct TALER_EXCHANGEDB_RefreshMelt);
      {
        struct GNUNET_PQ_ResultSpec rs[] = {
          GNUNET_PQ_result_spec_auto_from_type ("session_hash",
                                                &melt->session_hash),
          /* oldcoin_index not needed */
          GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                                &melt->coin_sig),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &melt->amount_with_fee),
          TALER_PQ_result_spec_amount ("fee_refresh",
                                       &melt->melt_fee),
          GNUNET_PQ_result_spec_end
        };
        if (GNUNET_OK !=
            GNUNET_PQ_extract_result (result, rs, 0))
        {
          GNUNET_break (0);
          GNUNET_free (melt);
          PQclear (result);
          goto cleanup;
        }
	melt->coin.coin_pub = *coin_pub;
      }
      tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
      tl->next = head;
      tl->type = TALER_EXCHANGEDB_TT_REFRESH_MELT;
      tl->details.melt = melt;
      if (GNUNET_SYSERR == get_known_coin (cls,
                                           session,
                                           coin_pub,
                                           &melt->coin))
      {
        GNUNET_break (0);
        GNUNET_free (melt);
        PQclear (result);
        goto cleanup;
      }
      head = tl;
      continue;
    }
    PQclear (result);
  }
  /* handle refunds */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&coin_pub->eddsa_pub),
      GNUNET_PQ_query_param_end
    };
    int nrows;
    int i;
    PGresult *result;
    struct TALER_EXCHANGEDB_TransactionList *tl;

    /* check if a refund records exist and get them */
    result = GNUNET_PQ_exec_prepared (session->conn,
                                      "get_refunds_by_coin",
                                      params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      goto cleanup;
    }
    nrows = PQntuples (result);
    for (i=0;i<nrows;i++)
    {
      struct TALER_EXCHANGEDB_Refund *refund;

      refund = GNUNET_new (struct TALER_EXCHANGEDB_Refund);
      {
        struct GNUNET_PQ_ResultSpec rs[] = {
          GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                                &refund->merchant_pub),
          GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                                &refund->merchant_sig),
          GNUNET_PQ_result_spec_auto_from_type ("h_contract",
                                                &refund->h_contract),
          GNUNET_PQ_result_spec_uint64 ("transaction_id",
                                        &refund->transaction_id),
          GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                        &refund->rtransaction_id),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &refund->refund_amount),
          TALER_PQ_result_spec_amount ("fee_refund",
                                       &refund->refund_fee),
          GNUNET_PQ_result_spec_end
        };
        if (GNUNET_OK !=
            GNUNET_PQ_extract_result (result, rs, 0))
        {
          GNUNET_break (0);
          GNUNET_free (refund);
          PQclear (result);
          goto cleanup;
        }
	refund->coin.coin_pub = *coin_pub;
      }
      tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
      tl->next = head;
      tl->type = TALER_EXCHANGEDB_TT_REFUND;
      tl->details.refund = refund;
      if (GNUNET_SYSERR ==
          get_known_coin (cls,
                          session,
                          coin_pub,
                          &refund->coin))
      {
        GNUNET_break (0);
        GNUNET_free (refund);
        PQclear (result);
        goto cleanup;
      }
      head = tl;
      continue;
    }
    PQclear (result);
  }
  return head;
 cleanup:
  if (NULL != head)
    common_free_coin_transaction_list (cls,
                                       head);
  return NULL;
}


/**
 * Lookup the list of Taler transactions that were aggregated
 * into a wire transfer by the respective @a wtid.
 *
 * @param cls closure
 * @param session database connection
 * @param wtid the raw wire transfer identifier we used
 * @param cb function to call on each transaction found
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on database errors,
 *         #GNUNET_NO if we found no results
 */
static int
postgres_lookup_wire_transfer (void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               const struct TALER_WireTransferIdentifierRawP *wtid,
                               TALER_EXCHANGEDB_WireTransferDataCallback cb,
                               void *cb_cls)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  int nrows;
  int i;

  /* check if the melt record exists and get it */
  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "lookup_transactions",
                                    params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  nrows = PQntuples (result);
  if (0 == nrows)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "lookup_wire_transfer() returned 0 matching rows\n");
    PQclear (result);
    return GNUNET_NO;
  }
  for (i=0;i<nrows;i++)
  {
    struct GNUNET_HashCode h_contract;
    struct GNUNET_HashCode h_wire;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_MerchantPublicKeyP merchant_pub;
    uint64_t transaction_id;
    struct GNUNET_TIME_Absolute exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("h_contract", &h_contract),
      GNUNET_PQ_result_spec_auto_from_type ("h_wire", &h_wire),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub", &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub", &merchant_pub),
      GNUNET_PQ_result_spec_uint64 ("transaction_id", &transaction_id),
      GNUNET_PQ_result_spec_absolute_time ("execution_time", &exec_time),
      TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit", &deposit_fee),
       GNUNET_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    cb (cb_cls,
        &merchant_pub,
        &h_wire,
        exec_time,
        &h_contract,
        transaction_id,
        &coin_pub,
        &amount_with_fee,
        &deposit_fee);
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Try to find the wire transfer details for a deposit operation.
 * If we did not execute the deposit yet, return when it is supposed
 * to be executed.
 *
 * @param cls closure
 * @param session database connection
 * @param h_contract hash of the contract
 * @param h_wire hash of merchant wire details
 * @param coin_pub public key of deposited coin
 * @param merchant_pub merchant public key
 * @param transaction_id transaction identifier
 * @param cb function to call with the result
 * @param cb_cls closure to pass to @a cb
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors,
 *         #GNUNET_NO if nothing was found
 */
static int
postgres_wire_lookup_deposit_wtid (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
				   const struct GNUNET_HashCode *h_contract,
				   const struct GNUNET_HashCode *h_wire,
				   const struct TALER_CoinSpendPublicKeyP *coin_pub,
				   const struct TALER_MerchantPublicKeyP *merchant_pub,
				   uint64_t transaction_id,
				   TALER_EXCHANGEDB_TrackTransactionCallback cb,
				   void *cb_cls)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_uint64 (&transaction_id),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_end
  };
  int nrows;

  /* check if the melt record exists and get it */
  result = GNUNET_PQ_exec_prepared (session->conn,
                                    "lookup_deposit_wtid",
                                    params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  nrows = PQntuples (result);
  if (0 == nrows)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "lookup_deposit_wtid returned 0 matching rows\n");
    PQclear (result);

    /* Check if transaction exists in deposits, so that we just
       do not have a WTID yet, if so, do call the CB with a NULL wtid
       and return #GNUNET_YES! */
    {
      struct GNUNET_PQ_QueryParam params2[] = {
        GNUNET_PQ_query_param_auto_from_type (coin_pub),
        GNUNET_PQ_query_param_uint64 (&transaction_id),
        GNUNET_PQ_query_param_auto_from_type (merchant_pub),
        GNUNET_PQ_query_param_auto_from_type (h_contract),
        GNUNET_PQ_query_param_auto_from_type (h_wire),
        GNUNET_PQ_query_param_end
      };

      result = GNUNET_PQ_exec_prepared (session->conn,
                                        "get_deposit_for_wtid",
                                        params2);
      if (PGRES_TUPLES_OK != PQresultStatus (result))
      {
        BREAK_DB_ERR (result);
        PQclear (result);
        return GNUNET_SYSERR;
      }
    }
    nrows = PQntuples (result);
    if (0 == nrows)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "get_deposit_for_wtid returned 0 matching rows\n");
      PQclear (result);
      return GNUNET_NO;
    }

    /* Ok, we're aware of the transaction, but it has not yet been
       executed */
    {
      struct GNUNET_TIME_Absolute exec_time;
      struct TALER_Amount amount_with_fee;
      struct TALER_Amount deposit_fee;
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
        TALER_PQ_result_spec_amount ("fee_deposit", &deposit_fee),
        GNUNET_PQ_result_spec_absolute_time ("wire_deadline", &exec_time),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK != GNUNET_PQ_extract_result (result, rs, 0))
      {
        GNUNET_break (0);
        PQclear (result);
        return GNUNET_SYSERR;
      }
      cb (cb_cls,
          NULL,
          &amount_with_fee,
          &deposit_fee,
          exec_time);
      PQclear (result);
      return GNUNET_YES;
    }
  }
  if (1 != nrows)
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  {
    struct TALER_WireTransferIdentifierRawP wtid;
    struct GNUNET_TIME_Absolute exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw", &wtid),
      GNUNET_PQ_result_spec_absolute_time ("execution_time", &exec_time),
      TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
      TALER_PQ_result_spec_amount ("fee_deposit", &deposit_fee),
      GNUNET_PQ_result_spec_end
    };
    if (GNUNET_OK != GNUNET_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    cb (cb_cls,
        &wtid,
        &amount_with_fee,
        &deposit_fee,
        exec_time);
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Function called to insert aggregation information into the DB.
 *
 * @param cls closure
 * @param session database connection
 * @param wtid the raw wire transfer identifier we used
 * @param deposit_serial_id row in the deposits table for which this is aggregation data
 * @param execution_time when did we execute the transaction
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors
 */
static int
postgres_insert_aggregation_tracking (void *cls,
                                      struct TALER_EXCHANGEDB_Session *session,
                                      const struct TALER_WireTransferIdentifierRawP *wtid,
                                      unsigned long long deposit_serial_id,
                                      struct GNUNET_TIME_Absolute execution_time)
{
  uint64_t rid = deposit_serial_id;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rid),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_absolute_time (&execution_time),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "insert_aggregation_tracking",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 != strcmp ("1", PQcmdTuples (result)))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Function called to insert wire transfer commit data into the DB.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of the wire transfer (i.e. "sepa")
 * @param buf buffer with wire transfer preparation data
 * @param buf_size number of bytes in @a buf
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors
 */
static int
postgres_wire_prepare_data_insert (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const char *type,
                                   const char *buf,
                                   size_t buf_size)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_fixed_size (buf, buf_size),
    GNUNET_PQ_query_param_end
  };

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "wire_prepare_data_insert",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Function called to mark wire transfer commit data as finished.
 *
 * @param cls closure
 * @param session database connection
 * @param rowid which entry to mark as finished
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors
 */
static int
postgres_wire_prepare_data_mark_finished (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          unsigned long long rowid)
{
  uint64_t prewire_uuid = rowid;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&prewire_uuid),
    GNUNET_PQ_query_param_end
  };
  PGresult *result;

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "wire_prepare_data_mark_done",
                                   params);
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Function called to get an unfinished wire transfer
 * preparation data. Fetches at most one item.
 *
 * @param cls closure
 * @param session database connection
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if there are no entries,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_wire_prepare_data_get (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                TALER_EXCHANGEDB_WirePreparationIterator cb,
                                void *cb_cls)
{
  PGresult *result;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };

  result = GNUNET_PQ_exec_prepared (session->conn,
                                   "wire_prepare_data_get",
                                   params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }
  if (1 != PQntuples (result))
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  {
    uint64_t prewire_uuid;
    char *type;
    void *buf = NULL;
    size_t buf_size;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("prewire_uuid",
                                    &prewire_uuid),
      GNUNET_PQ_result_spec_string ("type",
                                    &type),
      GNUNET_PQ_result_spec_variable_size ("buf",
                                           &buf,
                                           &buf_size),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                 rs,
                                 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    cb (cb_cls,
        prewire_uuid,
        type,
        buf,
        buf_size);
    GNUNET_PQ_cleanup_result (rs);
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
  struct GNUNET_PQ_QueryParam params_none[] = {
    GNUNET_PQ_query_param_end
  };
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
                                    "gc_prewire",
                                    params_none);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  result = GNUNET_PQ_exec_prepared (conn,
                                    "gc_denominations",
                                    params_time);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  result = GNUNET_PQ_exec_prepared (conn,
                                    "gc_reserves",
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
 * Select deposits above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_select_deposits_above_serial_id (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          uint64_t serial_id,
                                          TALER_EXCHANGEDB_DepositCallback cb,
                                          void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Select refresh sessions above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_select_refreshs_above_serial_id (void *cls,
                                          struct TALER_EXCHANGEDB_Session *session,
                                          uint64_t serial_id,
                                          TALER_EXCHANGEDB_RefreshSessionCallback cb,
                                          void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Select refunds above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_select_refunds_above_serial_id (void *cls,
                                         struct TALER_EXCHANGEDB_Session *session,
                                         uint64_t serial_id,
                                         TALER_EXCHANGEDB_RefundCallback cb,
                                         void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Select inbound wire transfers into reserves_in above @a serial_id
 * in monotonically increasing order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_select_reserves_in_above_serial_id (void *cls,
                                             struct TALER_EXCHANGEDB_Session *session,
                                             uint64_t serial_id,
                                             TALER_EXCHANGEDB_ReserveInCallback cb,
                                             void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Select withdraw operations from reserves_out above @a serial_id
 * in monotonically increasing order.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_select_reserves_out_above_serial_id (void *cls,
                                              struct TALER_EXCHANGEDB_Session *session,
                                              uint64_t serial_id,
                                              TALER_EXCHANGEDB_WithdrawCallback cb,
                                              void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Function called to select all wire transfers the exchange
 * executed or plans to execute.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if there are no entries,
 *         #GNUNET_SYSERR on DB errors
 */
static int
postgres_select_prepare_above_serial_id (void *cls,
                                         struct TALER_EXCHANGEDB_Session *session,
                                         uint64_t serial_id,
                                         TALER_EXCHANGEDB_WirePreparationCallback cb,
                                         void *cb_cls)
{
  GNUNET_break (0); // FIXME: not implemented
  return GNUNET_SYSERR;
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_EXCHANGEDB_Plugin`
 */
void *
libtaler_plugin_exchangedb_postgres_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_EXCHANGEDB_Plugin *plugin;
  const char *ec;

  pg = GNUNET_new (struct PostgresClosure);

  if (0 != pthread_key_create (&pg->db_conn_threadlocal,
                               &db_conn_destroy))
  {
    TALER_LOG_ERROR ("Cannnot create pthread key.\n");
    GNUNET_free (pg);
    return NULL;
  }
  ec = getenv ("TALER_EXCHANGEDB_POSTGRES_CONFIG");
  if (NULL != ec)
  {
    pg->connection_cfg_str = GNUNET_strdup (ec);
  }
  else
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchangedb-postgres",
                                               "db_conn_str",
                                               &pg->connection_cfg_str))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchangedb-postgres",
                                 "db_conn_str");
      GNUNET_free (pg);
      return NULL;
    }
  }
  plugin = GNUNET_new (struct TALER_EXCHANGEDB_Plugin);
  plugin->cls = pg;
  plugin->get_session = &postgres_get_session;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->rollback = &postgres_rollback;
  plugin->insert_denomination_info = &postgres_insert_denomination_info;
  plugin->get_denomination_info = &postgres_get_denomination_info;
  plugin->reserve_get = &postgres_reserve_get;
  plugin->reserves_in_insert = &postgres_reserves_in_insert;
  plugin->get_withdraw_info = &postgres_get_withdraw_info;
  plugin->insert_withdraw_info = &postgres_insert_withdraw_info;
  plugin->get_reserve_history = &postgres_get_reserve_history;
  plugin->free_reserve_history = &common_free_reserve_history;
  plugin->have_deposit = &postgres_have_deposit;
  plugin->mark_deposit_tiny = &postgres_mark_deposit_tiny;
  plugin->test_deposit_done = &postgres_test_deposit_done;
  plugin->mark_deposit_done = &postgres_mark_deposit_done;
  plugin->get_ready_deposit = &postgres_get_ready_deposit;
  plugin->iterate_matching_deposits = &postgres_iterate_matching_deposits;
  plugin->insert_deposit = &postgres_insert_deposit;
  plugin->insert_refund = &postgres_insert_refund;
  plugin->get_refresh_session = &postgres_get_refresh_session;
  plugin->create_refresh_session = &postgres_create_refresh_session;
  plugin->insert_refresh_order = &postgres_insert_refresh_order;
  plugin->get_refresh_order = &postgres_get_refresh_order;
  plugin->insert_refresh_commit_coins = &postgres_insert_refresh_commit_coins;
  plugin->get_refresh_commit_coins = &postgres_get_refresh_commit_coins;
  plugin->free_refresh_commit_coins = &postgres_free_refresh_commit_coins;
  plugin->insert_refresh_transfer_public_key = &postgres_insert_refresh_transfer_public_key;
  plugin->get_refresh_transfer_public_key = &postgres_get_refresh_transfer_public_key;
  plugin->insert_refresh_out = &postgres_insert_refresh_out;
  plugin->get_link_data_list = &postgres_get_link_data_list;
  plugin->free_link_data_list = &common_free_link_data_list;
  plugin->get_transfer = &postgres_get_transfer;
  plugin->get_coin_transactions = &postgres_get_coin_transactions;
  plugin->free_coin_transaction_list = &common_free_coin_transaction_list;
  plugin->lookup_wire_transfer = &postgres_lookup_wire_transfer;
  plugin->wire_lookup_deposit_wtid = &postgres_wire_lookup_deposit_wtid;
  plugin->insert_aggregation_tracking = &postgres_insert_aggregation_tracking;
  plugin->wire_prepare_data_insert = &postgres_wire_prepare_data_insert;
  plugin->wire_prepare_data_mark_finished = &postgres_wire_prepare_data_mark_finished;
  plugin->wire_prepare_data_get = &postgres_wire_prepare_data_get;
  plugin->gc = &postgres_gc;
  plugin->select_deposits_above_serial_id = &postgres_select_deposits_above_serial_id;
  plugin->select_refreshs_above_serial_id = &postgres_select_refreshs_above_serial_id;
  plugin->select_refunds_above_serial_id = &postgres_select_refunds_above_serial_id;
  plugin->select_reserves_in_above_serial_id = &postgres_select_reserves_in_above_serial_id;
  plugin->select_reserves_out_above_serial_id = &postgres_select_reserves_out_above_serial_id;
  plugin->select_prepare_above_serial_id = &postgres_select_prepare_above_serial_id;
  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_EXCHANGEDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_exchangedb_postgres_done (void *cls)
{
  struct TALER_EXCHANGEDB_Plugin *plugin = cls;
  struct PostgresClosure *pg = plugin->cls;

  GNUNET_free (pg->connection_cfg_str);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_exchangedb_postgres.c */
