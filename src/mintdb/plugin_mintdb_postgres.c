/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file plugin_mintdb_postgres.c
 * @brief Low-level (statement-level) Postgres database access for the mint
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 */
#include "platform.h"
#include "taler_pq_lib.h"
#include "taler_mintdb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>

#include "plugin_mintdb_common.c"

/**
 * For testing / experiments, we set the Postgres schema to
 * #TALER_TEMP_SCHEMA_NAME so we can easily purge everything
 * associated with a test.  We *also* should use the database
 * "talercheck" instead of "taler" for testing, but we're doing
 * both: better safe than sorry.
 */
#define TALER_TEMP_SCHEMA_NAME "taler_temporary"

/**
 * Log a query error.
 *
 * @param result PQ result object of the query that failed
 */
#define QUERY_ERR(result)                          \
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed at %s:%u: %s\n", __FILE__, __LINE__, PQresultErrorMessage (result))


/**
 * Log a really unexpected PQ error.
 *
 * @param result PQ result object of the PQ operation that failed
 */
#define BREAK_DB_ERR(result) do { \
    GNUNET_break (0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s\n", PQresultErrorMessage (result)); \
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
struct TALER_MINTDB_Session
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
 * Set the given connection to use a temporary schema
 *
 * @param db the database connection
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon error
 */
static int
set_temporary_schema (PGconn *db)
{
  SQLEXEC_(db,
           "CREATE SCHEMA IF NOT EXISTS " TALER_TEMP_SCHEMA_NAME ";"
           "SET search_path to " TALER_TEMP_SCHEMA_NAME ";");
  return GNUNET_OK;
 SQLEXEC_fail:
  return GNUNET_SYSERR;
}


/**
 * Drop the temporary taler schema.  This is only useful for testcases
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database session to use
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_drop_temporary (void *cls,
                         struct TALER_MINTDB_Session *session)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Dropping temporary tables\n");
  SQLEXEC_ (session->conn,
            "DROP SCHEMA " TALER_TEMP_SCHEMA_NAME " CASCADE;");
  return GNUNET_OK;
 SQLEXEC_fail:
  return GNUNET_SYSERR;
}


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
 * Create the necessary tables if they are not present
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param temporary should we use a temporary schema
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
postgres_create_tables (void *cls,
                        int temporary)
{
  struct PostgresClosure *pc = cls;
  PGconn *conn;

  conn = PQconnectdb (pc->connection_cfg_str);
  if (CONNECTION_OK != PQstatus (conn))
  {
    TALER_LOG_ERROR ("Database connection failed: %s\n",
                     PQerrorMessage (conn));
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  PQsetNoticeReceiver (conn,
                       &pq_notice_receiver_cb,
                       NULL);
  PQsetNoticeProcessor (conn,
                        &pq_notice_processor_cb,
                        NULL);
  if ( (GNUNET_YES == temporary) &&
       (GNUNET_SYSERR == set_temporary_schema (conn)))
  {
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
#define SQLEXEC(sql) SQLEXEC_(conn, sql);
#define SQLEXEC_INDEX(sql) SQLEXEC_IGNORE_ERROR_(conn, sql);
  /* Denomination table for holding the publicly available information of
     denominations keys.  The denominations are to be referred to by using
     foreign keys.  The denominations are deleted by a housekeeping tool;
     hence, do not use `ON DELETE CASCADE' on these rows in the tables
     referencing these rows */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS denominations"
           "(pub BYTEA PRIMARY KEY"
           ",master_pub BYTEA NOT NULL CHECK (LENGTH(master_pub)=32)"
           ",master_sig BYTEA NOT NULL CHECK (LENGTH(master_sig)=64)"
           ",valid_from INT8 NOT NULL"
           ",expire_withdraw INT8 NOT NULL"
           ",expire_spend INT8 NOT NULL"
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
           ")");
  /* reserves table is for summarization of a reserve.  It is updated when new
     funds are added and existing funds are withdrawn.  The 'expiration_date'
     can be used to eventually get rid of reserves that have not been used
     for a very long time (either by refunding the owner or by greedily
     grabbing the money, depending on the Mint's terms of service) */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS reserves"
           "(reserve_pub BYTEA PRIMARY KEY"
           ",current_balance_val INT8 NOT NULL"
           ",current_balance_frac INT4 NOT NULL"
           ",current_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",expiration_date INT8 NOT NULL"
           ")");
  /* index on reserves table */
  SQLEXEC_INDEX ("CREATE INDEX reserves_reserve_pub_index ON "
                 "reserves (reserve_pub)");
  /* reserves_in table collects the transactions which transfer funds
     into the reserve.  The rows of this table correspond to each
     incoming transaction. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS reserves_in"
          "(reserve_pub BYTEA REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
          ",balance_val INT8 NOT NULL"
          ",balance_frac INT4 NOT NULL"
          ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",details TEXT NOT NULL "
          ",execution_date INT8 NOT NULL"
          ",PRIMARY KEY (reserve_pub,details)"
          ");");
  /* Create indices on reserves_in */
  SQLEXEC_INDEX ("CREATE INDEX reserves_in_reserve_pub_index"
		 " ON reserves_in (reserve_pub);");
  SQLEXEC_INDEX ("CREATE INDEX reserves_in_reserve_pub_details_index"
		 " ON reserves_in (reserve_pub,details);");
  SQLEXEC_INDEX ("CREATE INDEX execution_index"
		 " ON reserves_in (execution_date);");
  /* Table with the withdraw operations that have been performed on a reserve.
     The 'h_blind_ev' is the hash of the blinded coin. It serves as a primary
     key, as (broken) clients that use a non-random coin and blinding factor
     should fail to even withdraw, as otherwise the coins will fail to deposit
     (as they really must be unique). */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS reserves_out"
           "(h_blind_ev BYTEA PRIMARY KEY"
           ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
           ",denom_sig BYTEA NOT NULL"
           ",reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32) REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
           ",reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)"
           ",execution_date INT8 NOT NULL"
           ",amount_with_fee_val INT8 NOT NULL"
           ",amount_with_fee_frac INT4 NOT NULL"
           ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",withdraw_fee_val INT8 NOT NULL"
           ",withdraw_fee_frac INT4 NOT NULL"
           ",withdraw_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ");");
  /* Index blindcoins(reserve_pub) for get_reserves_out statement */
  SQLEXEC_INDEX ("CREATE INDEX reserves_out_reserve_pub_index ON"
                 " reserves_out (reserve_pub)");
  SQLEXEC_INDEX ("CREATE INDEX reserves_out_h_blind_ev_index ON "
                 "reserves_out (h_blind_ev)");
  /* Table with coins that have been (partially) spent, used to track
     coin information only once. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS known_coins "
          "(coin_pub BYTEA NOT NULL PRIMARY KEY"
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
          ",denom_sig BYTEA NOT NULL"
          ")");
  /**
   * The DB will show negative values for some values of the following fields as
   * we use them as 16 bit unsigned integers
   *   @a num_oldcoins
   *   @a num_newcoins
   * Do not do arithmetic in SQL on these fields.
   * NOTE: maybe we should instead forbid values >= 2^15 categorically?
   */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_sessions "
          "(session_hash BYTEA PRIMARY KEY CHECK (LENGTH(session_hash)=64)"
          ",num_oldcoins INT2 NOT NULL"
          ",num_newcoins INT2 NOT NULL"
          ",noreveal_index INT2 NOT NULL"
          ")");
  /* Table with coins that have been melted.  Gives the coin's public
     key (coin_pub), the melting session, the index of this coin in that
     session, the signature affirming the melting and the amount that
     this coin contributed to the melting session.
  */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_melts "
          "(coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub)"
          ",session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash)"
          ",oldcoin_index INT2 NOT NULL"
          ",coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)"
          ",amount_with_fee_val INT8 NOT NULL"
          ",amount_with_fee_frac INT4 NOT NULL"
          ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",melt_fee_val INT8 NOT NULL"
          ",melt_fee_frac INT4 NOT NULL"
          ",melt_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",PRIMARY KEY (session_hash, oldcoin_index)" /* a coin can be used only
                                                 once in a refresh session */
          ") ");
  /* Table with information about the desired denominations to be created
     during a refresh operation; contains the denomination key for each
     of the coins (for a given refresh session) */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_order "
          "(session_hash BYTEA NOT NULL CHECK (LENGTH(session_hash)=64) REFERENCES refresh_sessions (session_hash)"
          ",newcoin_index INT2 NOT NULL "
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
          ",PRIMARY KEY (session_hash, newcoin_index)"
          ")");

  /* Table with the commitments for a refresh operation; includes
     the session_hash for which this is the link information, the
     oldcoin index and the cut-and-choose index (from 0 to #TALER_CNC_KAPPA-1),
     as well as the actual link data (the transfer public key and the encrypted
     link secret).
     NOTE: We might want to simplify this and not have the oldcoin_index
     and instead store all link secrets, one after the other, in one big BYTEA.
     (#3814) */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_link "
          "(session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash)"
          ",transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)"
          ",link_secret_enc BYTEA NOT NULL"
          ",oldcoin_index INT2 NOT NULL"
          ",cnc_index INT2 NOT NULL"
          ")");
  /* Table with the commitments for the new coins that are to be created
     during a melting session.  Includes the session, the cut-and-choose
     index and the index of the new coin, and the envelope of the new
     coin to be signed, as well as the encrypted information about the
     private key and the blinding factor for the coin (for verification
     in case this cnc_index is chosen to be revealed)

     NOTE: We might want to simplify this and not have the
     newcoin_index and instead store all coin_evs and
     link_vector_encs, one after the other, in two big BYTEAs.
     (#3815) */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_coin "
          "(session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash) "
          ",cnc_index INT2 NOT NULL"
          ",newcoin_index INT2 NOT NULL"
          ",link_vector_enc BYTEA NOT NULL"
          ",coin_ev BYTEA NOT NULL"
          ")");
  /* Table with the signatures over coins generated during a refresh
     operation. Needed to answer /refresh/link queries later.  Stores
     the coin signatures under the respective session hash and index. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_out "
          "(session_hash BYTEA NOT NULL CHECK(LENGTH(session_hash)=64) REFERENCES refresh_sessions (session_hash) "
          ",newcoin_index INT2 NOT NULL"
          ",ev_sig BYTEA NOT NULL"
          ")");
  /* This table contains the wire transfers the mint is supposed to
     execute to transmit funds to the merchants (and manage refunds). */
  SQLEXEC("CREATE TABLE IF NOT EXISTS deposits "
          "(serial_id BIGSERIAL"
          ",coin_pub BYTEA NOT NULL CHECK (LENGTH(coin_pub)=32)"
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
          ",denom_sig BYTEA NOT NULL"
          ",transaction_id INT8 NOT NULL"
          ",amount_with_fee_val INT8 NOT NULL"
          ",amount_with_fee_frac INT4 NOT NULL"
          ",amount_with_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",deposit_fee_val INT8 NOT NULL"
          ",deposit_fee_frac INT4 NOT NULL"
          ",deposit_fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",timestamp INT8 NOT NULL"
          ",refund_deadline INT8 NOT NULL"
          ",wire_deadline INT8 NOT NULL"
          ",merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)"
          ",h_contract BYTEA NOT NULL CHECK (LENGTH(h_contract)=64)"
          ",h_wire BYTEA NOT NULL CHECK (LENGTH(h_wire)=64)"
          ",coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)"
          ",wire TEXT NOT NULL"
          ")");
  /* Index for get_deposit statement on coin_pub, transactiojn_id and merchant_pub */
  SQLEXEC_INDEX("CREATE INDEX deposits_coin_pub_index "
                "ON deposits(coin_pub, transaction_id, merchant_pub)");
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
           "(pub"
           ",master_pub"
           ",master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_spend"
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
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13, $14, $15, $16, $17, $18, $19);",
           19, NULL);

  /* Used in #postgres_get_denomination_info() */
  PREPARE ("denomination_get",
           "SELECT"
           " master_pub"
           ",master_sig"
           ",valid_from"
           ",expire_withdraw"
           ",expire_spend"
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
           " FROM denominations"
           " WHERE pub=$1;",
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
           ",balance_val"
           ",balance_frac"
           ",balance_curr"
           ",details"
           ",execution_date"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);",
           6, NULL);
  /* Used in #postgres_get_reserve_history() to obtain inbound transactions
     for a reserve */
  PREPARE ("reserves_in_get_transactions",
           "SELECT"
           " balance_val"
           ",balance_frac"
           ",balance_curr"
           ",execution_date"
           ",details"
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
           ",withdraw_fee_val"
           ",withdraw_fee_frac"
           ",withdraw_fee_curr"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);",
           12, NULL);
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
           ",withdraw_fee_val"
           ",withdraw_fee_frac"
           ",withdraw_fee_curr"
           " FROM reserves_out"
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
           ",withdraw_fee_val"
           ",withdraw_fee_frac"
           ",withdraw_fee_curr"
           " FROM reserves_out"
           " WHERE reserve_pub=$1;",
           1, NULL);
  /* Used in #postgres_get_refresh_session() to fetch
     high-level information about a refresh session */
  PREPARE ("get_refresh_session",
           "SELECT"
           " num_oldcoins"
           ",num_newcoins"
           ",noreveal_index"
           " FROM refresh_sessions "
           " WHERE session_hash=$1 ",
           1, NULL);
  /* Used in #postgres_create_refresh_session() to store
     high-level information about a refresh session */
  PREPARE ("insert_refresh_session",
           "INSERT INTO refresh_sessions "
           "(session_hash "
           ",num_oldcoins "
           ",num_newcoins "
           ",noreveal_index "
           ") VALUES "
           "($1, $2, $3, $4);",
           4, NULL);
  /* Used in #postgres_get_known_coin() to fetch
     the denomination public key and signature for
     a coin known to the mint. */
  PREPARE ("get_known_coin",
           "SELECT"
           " denom_pub"
           ",denom_sig"
           " FROM known_coins "
           " WHERE coin_pub=$1",
           1, NULL);
  /* Used in #postgres_insert_known_coin() to store
     the denomination public key and signature for
     a coin known to the mint. */
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

  /* Used in #postgres_insert_refresh_melt to store information
     about melted coins */
  PREPARE ("insert_refresh_melt",
           "INSERT INTO refresh_melts "
           "(coin_pub "
           ",session_hash"
           ",oldcoin_index "
           ",coin_sig "
           ",amount_with_fee_val "
           ",amount_with_fee_frac "
           ",amount_with_fee_curr "
           ",melt_fee_val "
           ",melt_fee_frac "
           ",melt_fee_curr "
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);",
           10, NULL);
  /* Used in #postgres_get_refresh_melt to obtain information
     about melted coins */
  PREPARE ("get_refresh_melt",
           "SELECT"
           " coin_pub"
           ",coin_sig"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",melt_fee_val "
           ",melt_fee_frac "
           ",melt_fee_curr "
           " FROM refresh_melts"
           " WHERE session_hash=$1 AND oldcoin_index=$2",
           2, NULL);
  /* Query the 'refresh_melts' by coin public key */
  PREPARE ("get_refresh_melt_by_coin",
           "SELECT"
           " session_hash"
           /* ",oldcoin_index" // not needed */
           ",coin_sig"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",melt_fee_val "
           ",melt_fee_frac "
           ",melt_fee_curr "
           " FROM refresh_melts"
           " WHERE coin_pub=$1",
           1, NULL);
  /* Used in #postgres_insert_refresh_commit_links() to
     store commitments */
  PREPARE ("insert_refresh_commit_link",
           "INSERT INTO refresh_commit_link "
           "(session_hash"
           ",transfer_pub"
           ",cnc_index"
           ",oldcoin_index"
           ",link_secret_enc"
           ") VALUES "
           "($1, $2, $3, $4, $5);",
           5, NULL);
  /* Used in #postgres_get_refresh_commit_links() to
     retrieve original commitments during /refresh/reveal */
  PREPARE ("get_refresh_commit_link",
           "SELECT"
           " transfer_pub"
           ",link_secret_enc"
           " FROM refresh_commit_link"
           " WHERE session_hash=$1 AND cnc_index=$2 AND oldcoin_index=$3",
           3, NULL);
  /* Used in #postgres_insert_refresh_commit_coins() to
     store coin commitments. */
  PREPARE ("insert_refresh_commit_coin",
           "INSERT INTO refresh_commit_coin "
           "(session_hash"
           ",cnc_index"
           ",newcoin_index"
           ",link_vector_enc"
           ",coin_ev"
           ") VALUES "
           "($1, $2, $3, $4, $5);",
           5, NULL);
  /* Used in #postgres_get_refresh_commit_coins() to
     retrieve the original coin envelopes, to either be
     verified or signed. */
  PREPARE ("get_refresh_commit_coin",
           "SELECT"
           " link_vector_enc"
           ",coin_ev"
           " FROM refresh_commit_coin"
           " WHERE session_hash=$1 AND cnc_index=$2 AND newcoin_index=$3",
           3, NULL);
  /* Store information about a /deposit the mint is to execute.
     Used in #postgres_insert_deposit(). */
  PREPARE ("insert_deposit",
           "INSERT INTO deposits "
           "(coin_pub"
           ",denom_pub"
           ",denom_sig"
           ",transaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",deposit_fee_val"
           ",deposit_fee_frac"
           ",deposit_fee_curr"
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
           " $11, $12, $13, $14, $15, $16, $17, $18);",
           18, NULL);
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

  /* Used in #postgres_iterate_deposits() */
  PREPARE ("deposits_iterate",
           "SELECT"
           " serial_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",deposit_fee_val"
           ",deposit_fee_frac"
           ",deposit_fee_curr"
           ",wire_deadline"
           ",transaction_id"
           ",h_contract"
           ",wire"
           " FROM deposits"
           " WHERE serial_id>=$1"
           " ORDER BY serial_id ASC"
           " LIMIT $2;",
           2, NULL);
  /* Used in #postgres_get_coin_transactions() to obtain information
     about how a coin has been spend with /deposit requests. */
  PREPARE ("get_deposit_with_coin_pub",
           "SELECT"
           " denom_pub"
           ",denom_sig"
           ",transaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",amount_with_fee_curr"
           ",deposit_fee_val"
           ",deposit_fee_frac"
           ",deposit_fee_curr"
           ",timestamp"
           ",refund_deadline"
           ",merchant_pub"
           ",h_contract"
           ",h_wire"
           ",wire"
           ",coin_sig"
           " FROM deposits"
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
     to obtain the "noreveal_index" for that session, and then select
     the encrypted link vectors (link_vector_enc) and the
     corresponding signatures (ev_sig) and the denomination keys from
     the respective tables (namely refresh_melts and refresh_order)
     using the session_hash as the primary filter (on join) and the
     'noreveal_index' to constrain the selection on the commitment.
     We also want to get the triplet for each of the newcoins, so we
     have another constraint to ensure we get each triplet with
     matching "newcoin_index" values.  NOTE: This may return many
     results, both for different sessions and for the different coins
     being minted in the refresh ops.  NOTE: There may be more
     efficient ways to express the same query.  */
  PREPARE ("get_link",
           "SELECT link_vector_enc,ev_sig,ro.denom_pub"
           " FROM refresh_melts rm "
           "     JOIN refresh_order ro USING (session_hash)"
           "     JOIN refresh_commit_coin rcc USING (session_hash)"
           "     JOIN refresh_sessions rs USING (session_hash)"
           "     JOIN refresh_out rc USING (session_hash)"
           " WHERE ro.session_hash=$1"
           "  AND ro.newcoin_index=rcc.newcoin_index"
           "  AND ro.newcoin_index=rc.newcoin_index"
           "  AND rcc.cnc_index=rs.noreveal_index",
           1, NULL);
  /* Used in #postgres_get_transfer().  Given the public key of a
     melted coin, we obtain the corresponding encrypted link secret
     and the transfer public key.  This is done by first finding
     the session_hash(es) of all sessions the coin was melted into,
     and then constraining the result to the selected "noreveal_index"
     and the transfer public key to the corresponding index of the
     old coin.
     NOTE: This may (in theory) return multiple results, one per session
     that the old coin was melted into. */
  PREPARE ("get_transfer",
           "SELECT transfer_pub,link_secret_enc,session_hash"
           " FROM refresh_melts rm"
           "     JOIN refresh_commit_link rcl USING (session_hash)"
           "     JOIN refresh_sessions rs USING (session_hash)"
           " WHERE rm.coin_pub=$1"
           "  AND rm.oldcoin_index = rcl.oldcoin_index"
           "  AND rcl.cnc_index=rs.noreveal_index",
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
  struct TALER_MINTDB_Session *session = cls;
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
 * @param temporary #GNUNET_YES to use a temporary schema; #GNUNET_NO to use the
 *        database default one
 * @return the database connection, or NULL on error
 */
static struct TALER_MINTDB_Session *
postgres_get_session (void *cls,
                      int temporary)
{
  struct PostgresClosure *pc = cls;
  PGconn *db_conn;
  struct TALER_MINTDB_Session *session;

  if (NULL != (session = pthread_getspecific (pc->db_conn_threadlocal)))
    return session;
  db_conn = PQconnectdb (pc->connection_cfg_str);
  if (CONNECTION_OK !=
      PQstatus (db_conn))
  {
    TALER_LOG_ERROR ("Database connection failed: %s\n",
                     PQerrorMessage (db_conn));
    GNUNET_break (0);
    return NULL;
  }
  PQsetNoticeReceiver (db_conn,
                       &pq_notice_receiver_cb,
                       NULL);
  PQsetNoticeProcessor (db_conn,
                        &pq_notice_processor_cb,
                        NULL);
  if ( (GNUNET_YES == temporary) &&
       (GNUNET_SYSERR == set_temporary_schema(db_conn)) )
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_OK !=
      postgres_prepare (db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  session = GNUNET_new (struct TALER_MINTDB_Session);
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
                struct TALER_MINTDB_Session *session)
{
  PGresult *result;

  result = PQexec (session->conn,
                   "BEGIN");
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
                   struct TALER_MINTDB_Session *session)
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
                 struct TALER_MINTDB_Session *session)
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
                                   struct TALER_MINTDB_Session *session,
                                   const struct TALER_DenominationPublicKey *denom_pub,
                                   const struct TALER_MINTDB_DenominationKeyInformationP *issue)
{
  PGresult *result;
  int ret;

  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    TALER_PQ_query_param_auto_from_type (&issue->properties.master),
    TALER_PQ_query_param_auto_from_type (&issue->signature),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.start),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_withdraw),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_spend),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_legal),
    TALER_PQ_query_param_amount_nbo (&issue->properties.value),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_withdraw),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_deposit),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refresh),
    TALER_PQ_query_param_end
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

  result = TALER_PQ_exec_prepared (session->conn,
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
                                struct TALER_MINTDB_Session *session,
                                const struct TALER_DenominationPublicKey *denom_pub,
                                struct TALER_MINTDB_DenominationKeyInformationP *issue)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    TALER_PQ_query_param_end
  };

  result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_auto_from_type ("master_pub",
                                           &issue->properties.master),
      TALER_PQ_result_spec_auto_from_type ("master_sig",
                                           &issue->signature),
      TALER_PQ_result_spec_absolute_time_nbo ("valid_from",
                                              &issue->properties.start),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_withdraw",
                                              &issue->properties.expire_withdraw),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_spend",
                                              &issue->properties.expire_spend),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_legal",
                                              &issue->properties.expire_legal),
      TALER_PQ_result_spec_amount_nbo ("coin",
                                       &issue->properties.value),
      TALER_PQ_result_spec_amount_nbo ("fee_withdraw",
                                       &issue->properties.fee_withdraw),
      TALER_PQ_result_spec_amount_nbo ("fee_deposit",
                                       &issue->properties.fee_deposit),
      TALER_PQ_result_spec_amount_nbo ("fee_refresh",
                                       &issue->properties.fee_refresh),
      TALER_PQ_result_spec_end
    };

    EXITIF (GNUNET_OK !=
            TALER_PQ_extract_result (result,
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
                      struct TALER_MINTDB_Session *session,
                      struct TALER_MINTDB_Reserve *reserve)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type(&reserve->pub),
    TALER_PQ_query_param_end
  };

  result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_amount("current_balance", &reserve->balance),
      TALER_PQ_result_spec_absolute_time("expiration_date", &reserve->expiry),
      TALER_PQ_result_spec_end
    };

    EXITIF (GNUNET_OK !=
            TALER_PQ_extract_result (result,
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
                 struct TALER_MINTDB_Session *session,
                 const struct TALER_MINTDB_Reserve *reserve)
{
  PGresult *result;
  int ret;

  if (NULL == reserve)
    return GNUNET_SYSERR;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&reserve->expiry),
    TALER_PQ_query_param_amount (&reserve->balance),
    TALER_PQ_query_param_auto_from_type (&reserve->pub),
    TALER_PQ_query_param_end
  };
  result = TALER_PQ_exec_prepared (session->conn,
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
 * @param details bank transaction details justifying the increment,
 *        must be unique for each incoming transaction
 * @return #GNUNET_OK upon success; #GNUNET_NO if the given
 *         @a details are already known for this @a reserve_pub,
 *         #GNUNET_SYSERR upon failures (DB error, incompatible currency)
 */
static int
postgres_reserves_in_insert (void *cls,
                             struct TALER_MINTDB_Session *session,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Absolute execution_time,
                             const json_t *details)
{
  PGresult *result;
  int reserve_exists;
  struct TALER_MINTDB_Reserve reserve;
  struct GNUNET_TIME_Absolute expiry;

  if (GNUNET_OK != postgres_start (cls,
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
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (reserve_pub),
      TALER_PQ_query_param_amount (balance),
      TALER_PQ_query_param_absolute_time (&expiry),
      TALER_PQ_query_param_end
    };

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (&reserve.pub),
      TALER_PQ_query_param_amount (balance),
      TALER_PQ_query_param_json (details),
      TALER_PQ_query_param_absolute_time (&execution_time),
      TALER_PQ_query_param_end
    };

    result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_MINTDB_Reserve updated_reserve;

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
                            struct TALER_MINTDB_Session *session,
                            const struct GNUNET_HashCode *h_blind,
                            struct TALER_MINTDB_CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (h_blind),
    TALER_PQ_query_param_end
  };
  int ret;

  ret = GNUNET_SYSERR;
  result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_rsa_public_key ("denom_pub",
                                           &collectable->denom_pub.rsa_public_key),
      TALER_PQ_result_spec_rsa_signature ("denom_sig",
                                          &collectable->sig.rsa_signature),
      TALER_PQ_result_spec_auto_from_type ("reserve_sig",
                                           &collectable->reserve_sig),
      TALER_PQ_result_spec_auto_from_type ("reserve_pub",
                                           &collectable->reserve_pub),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &collectable->amount_with_fee),
      TALER_PQ_result_spec_amount ("withdraw_fee",
                                   &collectable->withdraw_fee),
      TALER_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, 0))
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
                               struct TALER_MINTDB_Session *session,
                               const struct TALER_MINTDB_CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_MINTDB_Reserve reserve;
  int ret = GNUNET_SYSERR;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    TALER_PQ_query_param_rsa_public_key (collectable->denom_pub.rsa_public_key),
    TALER_PQ_query_param_rsa_signature (collectable->sig.rsa_signature),
    TALER_PQ_query_param_auto_from_type (&collectable->reserve_pub),
    TALER_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    TALER_PQ_query_param_absolute_time (&now),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    TALER_PQ_query_param_amount (&collectable->withdraw_fee),
    TALER_PQ_query_param_end
  };

  now = GNUNET_TIME_absolute_get ();
  result = TALER_PQ_exec_prepared (session->conn,
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
static struct TALER_MINTDB_ReserveHistory *
postgres_get_reserve_history (void *cls,
                              struct TALER_MINTDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub)
{
  PGresult *result;
  struct TALER_MINTDB_ReserveHistory *rh;
  struct TALER_MINTDB_ReserveHistory *rh_tail;
  int rows;
  int ret;

  rh = NULL;
  rh_tail = NULL;
  ret = GNUNET_SYSERR;
  {
    struct TALER_MINTDB_BankTransfer *bt;
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (reserve_pub),
      TALER_PQ_query_param_end
    };

    result = TALER_PQ_exec_prepared (session->conn,
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
      bt = GNUNET_new (struct TALER_MINTDB_BankTransfer);
      {
        struct TALER_PQ_ResultSpec rs[] = {
          TALER_PQ_result_spec_amount ("balance",
                                       &bt->amount),
          TALER_PQ_result_spec_absolute_time ("execution_date",
                                              &bt->execution_date),
          TALER_PQ_result_spec_json ("details",
                                     &bt->wire),
          TALER_PQ_result_spec_end
        };
        if (GNUNET_YES !=
            TALER_PQ_extract_result (result, rs, --rows))
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
        rh_tail->next = GNUNET_new (struct TALER_MINTDB_ReserveHistory);
        rh_tail = rh_tail->next;
      }
      else
      {
        rh_tail = GNUNET_new (struct TALER_MINTDB_ReserveHistory);
        rh = rh_tail;
      }
      rh_tail->type = TALER_MINTDB_RO_BANK_TO_MINT;
      rh_tail->details.bank = bt;
    }
    PQclear (result);
  }
  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (reserve_pub),
      TALER_PQ_query_param_end
    };

    GNUNET_assert (NULL != rh);
    GNUNET_assert (NULL != rh_tail);
    GNUNET_assert (NULL == rh_tail->next);
    result = TALER_PQ_exec_prepared (session->conn,
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
      struct TALER_MINTDB_CollectableBlindcoin *cbc;

      cbc = GNUNET_new (struct TALER_MINTDB_CollectableBlindcoin);
      {
        struct TALER_PQ_ResultSpec rs[] = {
          TALER_PQ_result_spec_auto_from_type ("h_blind_ev",
                                               &cbc->h_coin_envelope),
          TALER_PQ_result_spec_rsa_public_key ("denom_pub",
                                               &cbc->denom_pub.rsa_public_key),
          TALER_PQ_result_spec_rsa_signature ("denom_sig",
                                              &cbc->sig.rsa_signature),
          TALER_PQ_result_spec_auto_from_type ("reserve_sig",
                                               &cbc->reserve_sig),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &cbc->amount_with_fee),
          TALER_PQ_result_spec_amount ("withdraw_fee",
                                       &cbc->withdraw_fee),
          TALER_PQ_result_spec_end
        };
        if (GNUNET_YES !=
            TALER_PQ_extract_result (result, rs, --rows))
        {
          GNUNET_break (0);
          GNUNET_free (cbc);
          PQclear (result);
          goto cleanup;
        }
        cbc->reserve_pub = *reserve_pub;
      }
      rh_tail->next = GNUNET_new (struct TALER_MINTDB_ReserveHistory);
      rh_tail = rh_tail->next;
      rh_tail->type = TALER_MINTDB_RO_WITHDRAW_COIN;
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
                       struct TALER_MINTDB_Session *session,
                       const struct TALER_MINTDB_Deposit *deposit)
{
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    TALER_PQ_query_param_uint64 (&deposit->transaction_id),
    TALER_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    TALER_PQ_query_param_end
  };
  PGresult *result;

  result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_MINTDB_Deposit deposit2;
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &deposit2.amount_with_fee),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                          &deposit2.timestamp),
      TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                          &deposit2.refund_deadline),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                          &deposit2.wire_deadline),
      TALER_PQ_result_spec_auto_from_type ("h_contract",
                                           &deposit2.h_contract),
      TALER_PQ_result_spec_auto_from_type ("h_wire",
                                           &deposit2.h_wire),
      TALER_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, 0))
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
 * Obtain information about deposits.  Iterates over all deposits
 * above a certain ID.  Use a @a min_id of 0 to start at the beginning.
 * This operation is executed in its own transaction in transaction
 * mode "REPEATABLE READ", i.e. we should only see valid deposits.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param min_id deposit to start at
 * @param limit maximum number of transactions to fetch
 * @param deposit_cb function to call for each deposit
 * @param deposit_cb_cls closure for @a deposit_cb
 * @return number of rows processed, 0 if none exist,
 *         #GNUNET_SYSERR on error
 */
static int
postgres_iterate_deposits (void *cls,
                           struct TALER_MINTDB_Session *session,
                           uint64_t min_id,
                           uint32_t limit,
                           TALER_MINTDB_DepositIterator deposit_cb,
                           void *deposit_cb_cls)
{
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_uint64 (&min_id),
    TALER_PQ_query_param_uint32 (&limit),
    TALER_PQ_query_param_end
  };
  PGresult *result;
  unsigned int i;
  unsigned int n;

  if (GNUNET_OK !=
      postgres_start (cls, session))
    return GNUNET_SYSERR;
  result = PQexec (session->conn,
                   "SET TRANSACTION REPEATABLE READ");
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    TALER_LOG_ERROR ("Failed to set transaction to REPEATABL EREAD: %s\n",
                     PQresultErrorMessage (result));
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  result = TALER_PQ_exec_prepared (session->conn,
                                   "deposits_iterate",
                                   params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    postgres_rollback (cls, session);
    return GNUNET_SYSERR;
  }
  if (0 == (n = PQntuples (result)))
  {
    PQclear (result);
    postgres_rollback (cls, session);
    return 0;
  }
  for (i=0;i<n;i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_TIME_Absolute wire_deadline;
    struct GNUNET_HashCode h_contract;
    json_t *wire;
    uint64_t transaction_id;
    uint64_t id;
    int ret;
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_uint64 ("id",
                                   &id),
      TALER_PQ_result_spec_uint64 ("transaction_id",
                                   &transaction_id),
      TALER_PQ_result_spec_amount ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_result_spec_amount ("deposit_fee",
                                   &deposit_fee),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                          &wire_deadline),
      TALER_PQ_result_spec_auto_from_type ("h_contract",
                                           &h_contract),
      TALER_PQ_result_spec_json ("wire",
                                 &wire),
      TALER_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, i))
    {
      GNUNET_break (0);
      PQclear (result);
      postgres_rollback (cls, session);
      return GNUNET_SYSERR;
    }
    ret = deposit_cb (deposit_cb_cls,
                      id,
                      &amount_with_fee,
                      &deposit_fee,
                      transaction_id,
                      &h_contract,
                      wire_deadline,
                      wire);
    TALER_PQ_cleanup_result (rs);
    PQclear (result);
    if (GNUNET_OK != ret)
      break;
  }
  postgres_rollback (cls, session);
  return i;
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
                         struct TALER_MINTDB_Session *session,
                         const struct TALER_MINTDB_Deposit *deposit)
{
  PGresult *result;
  int ret;

  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
      TALER_PQ_query_param_rsa_public_key (deposit->coin.denom_pub.rsa_public_key),
      TALER_PQ_query_param_rsa_signature (deposit->coin.denom_sig.rsa_signature),
      TALER_PQ_query_param_uint64 (&deposit->transaction_id),
      TALER_PQ_query_param_amount (&deposit->amount_with_fee),
      TALER_PQ_query_param_amount (&deposit->deposit_fee),
      TALER_PQ_query_param_absolute_time (&deposit->timestamp),
      TALER_PQ_query_param_absolute_time (&deposit->refund_deadline),
      TALER_PQ_query_param_absolute_time (&deposit->wire_deadline),
      TALER_PQ_query_param_auto_from_type (&deposit->merchant_pub),
      TALER_PQ_query_param_auto_from_type (&deposit->h_contract),
      TALER_PQ_query_param_auto_from_type (&deposit->h_wire),
      TALER_PQ_query_param_auto_from_type (&deposit->csig),
      TALER_PQ_query_param_json (deposit->wire),
      TALER_PQ_query_param_end
    };
    result = TALER_PQ_exec_prepared (session->conn,
                                     "insert_deposit",
                                     params);
  }
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
                              struct TALER_MINTDB_Session *session,
                              const struct GNUNET_HashCode *session_hash,
                              struct TALER_MINTDB_RefreshSession *refresh_session)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (session_hash),
    TALER_PQ_query_param_end
  };

  result = TALER_PQ_exec_prepared (session->conn,
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
          sizeof (struct TALER_MINTDB_RefreshSession));
  {
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_uint16 ("num_oldcoins",
                                   &refresh_session->num_oldcoins),
      TALER_PQ_result_spec_uint16 ("num_newcoins",
                                   &refresh_session->num_newcoins),
      TALER_PQ_result_spec_uint16 ("noreveal_index",
                                   &refresh_session->noreveal_index),
      TALER_PQ_result_spec_end
    };
    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
  }
  PQclear (result);
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
                                 struct TALER_MINTDB_Session *session,
                                 const struct GNUNET_HashCode *session_hash,
                                 const struct TALER_MINTDB_RefreshSession *refresh_session)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (session_hash),
    TALER_PQ_query_param_uint16 (&refresh_session->num_oldcoins),
    TALER_PQ_query_param_uint16 (&refresh_session->num_newcoins),
    TALER_PQ_query_param_uint16 (&refresh_session->noreveal_index),
    TALER_PQ_query_param_end
  };

  result = TALER_PQ_exec_prepared (session->conn,
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
 * Insert a coin we know of into the DB.  The coin can then be referenced by
 * tables for deposits, lock and refresh functionality.
 *
 * @param cls plugin closure
 * @param session the shared database session
 * @param coin_info the public coin info
 * @return #GNUNET_SYSERR upon error; #GNUNET_OK upon success
 */
static int
insert_known_coin (void *cls,
                   struct TALER_MINTDB_Session *session,
                   const struct TALER_CoinPublicInfo *coin_info)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (&coin_info->coin_pub),
    TALER_PQ_query_param_rsa_public_key (coin_info->denom_pub.rsa_public_key),
    TALER_PQ_query_param_rsa_signature (coin_info->denom_sig.rsa_signature),
    TALER_PQ_query_param_end
  };
  result = TALER_PQ_exec_prepared (session->conn,
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
                struct TALER_MINTDB_Session *session,
                const struct TALER_CoinSpendPublicKeyP *coin_pub,
                struct TALER_CoinPublicInfo *coin_info)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (coin_pub),
    TALER_PQ_query_param_end
  };
  int nrows;

  result = TALER_PQ_exec_prepared (session->conn,
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
    return GNUNET_YES;
  {
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_rsa_public_key ("denom_pub",
                                           &coin_info->denom_pub.rsa_public_key),
      TALER_PQ_result_spec_rsa_signature ("denom_sig",
                                          &coin_info->denom_sig.rsa_signature),
      TALER_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, 0))
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
 * Store the given /refresh/melt request in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param oldcoin_index index of the coin to store
 * @param melt melt operation details to store; includes
 *             the session hash of the melt
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
static int
postgres_insert_refresh_melt (void *cls,
                              struct TALER_MINTDB_Session *session,
                              uint16_t oldcoin_index,
                              const struct TALER_MINTDB_RefreshMelt *melt)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (&melt->coin.coin_pub),
    TALER_PQ_query_param_auto_from_type (&melt->session_hash),
    TALER_PQ_query_param_uint16 (&oldcoin_index),
    TALER_PQ_query_param_auto_from_type (&melt->coin_sig),
    TALER_PQ_query_param_amount (&melt->amount_with_fee),
    TALER_PQ_query_param_amount (&melt->melt_fee),
    TALER_PQ_query_param_end
  };
  int ret;

  /* check if the coin is already known */
  ret = get_known_coin (cls,
                        session,
                        &melt->coin.coin_pub,
                        NULL);
  if (GNUNET_SYSERR == ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == ret)         /* if not, insert it */
  {
    ret = insert_known_coin (cls,
                             session,
                             &melt->coin);
    if (ret == GNUNET_SYSERR)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  /* insert the melt */
  result = TALER_PQ_exec_prepared (session->conn,
                                   "insert_refresh_melt",
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
 * Get information about melted coin details from the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param session_hash  session hash of the melt operation
 * @param oldcoin_index index of the coin to retrieve
 * @param melt melt data to fill in, can be NULL
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
static int
postgres_get_refresh_melt (void *cls,
                           struct TALER_MINTDB_Session *session,
                           const struct GNUNET_HashCode *session_hash,
                           uint16_t oldcoin_index,
                           struct TALER_MINTDB_RefreshMelt *melt)
{
  PGresult *result;
  struct TALER_CoinPublicInfo coin;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount melt_fee;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (session_hash),
    TALER_PQ_query_param_uint16 (&oldcoin_index),
    TALER_PQ_query_param_end
  };
  int nrows;

  /* check if the melt record exists and get it */
  result = TALER_PQ_exec_prepared (session->conn,
                                   "get_refresh_melt",
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
                "get_refresh_melt() returned 0 matching rows\n");
    PQclear (result);
    return GNUNET_NO;
  }
  GNUNET_assert (1 == nrows);    /* due to primary key constraint */
  {
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_auto_from_type ("coin_pub", &coin.coin_pub),
      TALER_PQ_result_spec_auto_from_type ("coin_sig", &coin_sig),
      TALER_PQ_result_spec_amount ("amount_with_fee", &amount_with_fee),
      TALER_PQ_result_spec_amount ("melt_fee", &melt_fee),
      TALER_PQ_result_spec_end
    };
    if (GNUNET_OK != TALER_PQ_extract_result (result, rs, 0))
    {
      GNUNET_break (0);
      PQclear (result);
      return GNUNET_SYSERR;
    }
    PQclear (result);
  }
  /* fetch the coin info and denomination info */
  if (GNUNET_OK != get_known_coin (cls,
                                   session,
                                   &coin.coin_pub,
                                   &coin))
    return GNUNET_SYSERR;
  if (NULL == melt)
  {
    GNUNET_CRYPTO_rsa_signature_free (coin.denom_sig.rsa_signature);
    GNUNET_CRYPTO_rsa_public_key_free (coin.denom_pub.rsa_public_key);
    return GNUNET_OK;
  }
  melt->coin = coin;
  melt->coin_sig = coin_sig;
  melt->session_hash = *session_hash;
  melt->amount_with_fee = amount_with_fee;
  melt->melt_fee = melt_fee;
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
                               struct TALER_MINTDB_Session *session,
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
      struct TALER_PQ_QueryParam params[] = {
        TALER_PQ_query_param_uint16 (&newcoin_off),
        TALER_PQ_query_param_auto_from_type (session_hash),
        TALER_PQ_query_param_rsa_public_key (denom_pubs[i].rsa_public_key),
        TALER_PQ_query_param_end
      };
      result = TALER_PQ_exec_prepared (session->conn,
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
                            struct TALER_MINTDB_Session *session,
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
      struct TALER_PQ_QueryParam params[] = {
        TALER_PQ_query_param_auto_from_type (session_hash),
        TALER_PQ_query_param_uint16 (&newcoin_off),
        TALER_PQ_query_param_end
      };

      result = TALER_PQ_exec_prepared (session->conn,
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
      struct TALER_PQ_ResultSpec rs[] = {
        TALER_PQ_result_spec_rsa_public_key ("denom_pub",
                                             &denom_pubs[i].rsa_public_key),
        TALER_PQ_result_spec_end
      };
      if (GNUNET_OK !=
          TALER_PQ_extract_result (result, rs, 0))
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
 * @param cnc_index cut and choose index (1st dimension)
 * @param num_newcoins coin index size of the @a commit_coins array
 * @param commit_coins array of coin commitments to store
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on error
 */
static int
postgres_insert_refresh_commit_coins (void *cls,
                                      struct TALER_MINTDB_Session *session,
                                      const struct GNUNET_HashCode *session_hash,
                                      uint16_t cnc_index,
                                      uint16_t num_newcoins,
                                      const struct TALER_MINTDB_RefreshCommitCoin *commit_coins)
{
  char *rle;
  size_t rle_size;
  PGresult *result;
  unsigned int i;
  uint16_t coin_off;

  for (i=0;i<(unsigned int) num_newcoins;i++)
  {
    rle = TALER_refresh_link_encrypted_encode (commit_coins[i].refresh_link,
                                               &rle_size);
    if (NULL == rle)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    coin_off = (uint16_t) i;
    {
      struct TALER_PQ_QueryParam params[] = {
        TALER_PQ_query_param_auto_from_type (session_hash),
        TALER_PQ_query_param_uint16 (&cnc_index),
        TALER_PQ_query_param_uint16 (&coin_off),
        TALER_PQ_query_param_fixed_size (rle,
                                         rle_size),
        TALER_PQ_query_param_fixed_size (commit_coins[i].coin_ev,
                                         commit_coins[i].coin_ev_size),
        TALER_PQ_query_param_end
      };
      result = TALER_PQ_exec_prepared (session->conn,
                                       "insert_refresh_commit_coin",
                                       params);
    }
    GNUNET_free (rle);
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
 * @param commit_coins data to free (but not the array itself)
 * @param commit_coins_len length of @a commit_coins array
 */
static void
free_cc_result (struct TALER_MINTDB_RefreshCommitCoin *commit_coins,
                unsigned int commit_coins_len)
{
  unsigned int i;

  for (i=0;i<commit_coins_len;i++)
  {
    GNUNET_free (commit_coins[i].refresh_link);
    commit_coins[i].refresh_link = NULL;
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
 * @param cnc_index set index (1st dimension)
 * @param num_newcoins size of the @a commit_coins array
 * @param[out] commit_coins array of coin commitments to return
 * @return #GNUNET_OK on success
 *         #GNUNET_NO if not found
 *         #GNUNET_SYSERR on error
 */
static int
postgres_get_refresh_commit_coins (void *cls,
                                   struct TALER_MINTDB_Session *session,
                                   const struct GNUNET_HashCode *session_hash,
                                   uint16_t cnc_index,
                                   uint16_t num_newcoins,
                                   struct TALER_MINTDB_RefreshCommitCoin *commit_coins)
{
  unsigned int i;

  for (i=0;i<(unsigned int) num_newcoins;i++)
  {
    uint16_t newcoin_off = (uint16_t) i;
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (session_hash),
      TALER_PQ_query_param_uint16 (&cnc_index),
      TALER_PQ_query_param_uint16 (&newcoin_off),
      TALER_PQ_query_param_end
    };
    void *c_buf;
    size_t c_buf_size;
    void *rl_buf;
    size_t rl_buf_size;
    struct TALER_RefreshLinkEncrypted *rl;
    PGresult *result;

    result = TALER_PQ_exec_prepared (session->conn,
                                     "get_refresh_commit_coin",
                                     params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      BREAK_DB_ERR (result);
      PQclear (result);
      free_cc_result (commit_coins, i);
      return GNUNET_SYSERR;
    }
    if (0 == PQntuples (result))
    {
      PQclear (result);
      free_cc_result (commit_coins, i);
      return GNUNET_NO;
    }
    {
      struct TALER_PQ_ResultSpec rs[] = {
        TALER_PQ_result_spec_variable_size ("link_vector_enc",
                                            &rl_buf,
                                            &rl_buf_size),
        TALER_PQ_result_spec_variable_size ("coin_ev",
                                            &c_buf,
                                            &c_buf_size),
        TALER_PQ_result_spec_end
      };

      if (GNUNET_YES !=
          TALER_PQ_extract_result (result, rs, 0))
      {
        PQclear (result);
        free_cc_result (commit_coins, i);
        return GNUNET_SYSERR;
      }
    }
    PQclear (result);
    if (rl_buf_size < sizeof (struct TALER_CoinSpendPrivateKeyP))
    {
      GNUNET_free (c_buf);
      GNUNET_free (rl_buf);
      free_cc_result (commit_coins, i);
      return GNUNET_SYSERR;
    }
    rl = TALER_refresh_link_encrypted_decode (rl_buf,
                                              rl_buf_size);
    GNUNET_free (rl_buf);
    commit_coins[i].refresh_link = rl;
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
 * @param cnc_index cut and choose index (1st dimension)
 * @param num_links size of the @a links array to return
 * @param[out] links array of link information to store return
 * @return #GNUNET_SYSERR on internal error, #GNUNET_OK on success
 */
static int
postgres_insert_refresh_commit_links (void *cls,
                                      struct TALER_MINTDB_Session *session,
                                      const struct GNUNET_HashCode *session_hash,
                                      uint16_t cnc_index,
                                      uint16_t num_links,
                                      const struct TALER_RefreshCommitLinkP *links)
{
  uint16_t i;

  for (i=0;i<num_links;i++)
  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (session_hash),
      TALER_PQ_query_param_auto_from_type (&links[i].transfer_pub),
      TALER_PQ_query_param_uint16 (&cnc_index),
      TALER_PQ_query_param_uint16 (&i),
      TALER_PQ_query_param_auto_from_type (&links[i].shared_secret_enc),
      TALER_PQ_query_param_end
    };

    PGresult *result = TALER_PQ_exec_prepared (session->conn,
					       "insert_refresh_commit_link",
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
  }
  return GNUNET_OK;
}


/**
 * Obtain the commited (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param cnc_index cut and choose index (1st dimension)
 * @param num_links size of the @a commit_link array
 * @param[out] links array of link information to return
 * @return #GNUNET_SYSERR on internal error,
 *         #GNUNET_NO if commitment was not found
 *         #GNUNET_OK on success
 */
static int
postgres_get_refresh_commit_links (void *cls,
                                   struct TALER_MINTDB_Session *session,
                                   const struct GNUNET_HashCode *session_hash,
                                   uint16_t cnc_index,
                                   uint16_t num_links,
                                   struct TALER_RefreshCommitLinkP *links)
{
  uint16_t i;

  for (i=0;i<num_links;i++)
  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (session_hash),
      TALER_PQ_query_param_uint16 (&cnc_index),
      TALER_PQ_query_param_uint16 (&i),
      TALER_PQ_query_param_end
    };
    PGresult *result;

    result = TALER_PQ_exec_prepared (session->conn,
				     "get_refresh_commit_link",
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
      struct TALER_PQ_ResultSpec rs[] = {
	TALER_PQ_result_spec_auto_from_type ("transfer_pub",
					     &links[i].transfer_pub),
	TALER_PQ_result_spec_auto_from_type ("link_secret_enc",
					     &links[i].shared_secret_enc),
	TALER_PQ_result_spec_end
      };

      if (GNUNET_YES !=
	  TALER_PQ_extract_result (result, rs, 0))
      {
	PQclear (result);
	return GNUNET_SYSERR;
      }
    }
    PQclear (result);
  }
  return GNUNET_OK;
}


/**
 * Get all of the information from the given melt commit operation.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @return NULL if the @a session_hash does not correspond to any known melt
 *         operation
 */
static struct TALER_MINTDB_MeltCommitment *
postgres_get_melt_commitment (void *cls,
                              struct TALER_MINTDB_Session *session,
                              const struct GNUNET_HashCode *session_hash)
{
  struct TALER_MINTDB_RefreshSession rs;
  struct TALER_MINTDB_MeltCommitment *mc;
  uint16_t cnc_index;
  unsigned int i;

  if (GNUNET_OK !=
      postgres_get_refresh_session (cls,
                                    session,
                                    session_hash,
                                    &rs))
    return NULL;
  mc = GNUNET_new (struct TALER_MINTDB_MeltCommitment);
  mc->num_newcoins = rs.num_newcoins;
  mc->num_oldcoins = rs.num_oldcoins;
  mc->melts = GNUNET_malloc (mc->num_oldcoins *
                             sizeof (struct TALER_MINTDB_RefreshMelt));
  for (i=0;i<mc->num_oldcoins;i++)
    if (GNUNET_OK !=
        postgres_get_refresh_melt (cls,
                                   session,
                                   session_hash,
                                   (uint16_t) i,
                                   &mc->melts[i]))
      goto cleanup;
  mc->denom_pubs = GNUNET_malloc (mc->num_newcoins *
                                  sizeof (struct TALER_DenominationPublicKey));
  if (GNUNET_OK !=
      postgres_get_refresh_order (cls,
                                  session,
                                  session_hash,
                                  mc->num_newcoins,
                                  mc->denom_pubs))
    goto cleanup;
  for (cnc_index=0;cnc_index<TALER_CNC_KAPPA;cnc_index++)
  {
    mc->commit_coins[cnc_index]
      = GNUNET_malloc (mc->num_newcoins *
                       sizeof (struct TALER_MINTDB_RefreshCommitCoin));
    if (GNUNET_OK !=
        postgres_get_refresh_commit_coins (cls,
                                           session,
                                           session_hash,
                                           cnc_index,
                                           mc->num_newcoins,
                                           mc->commit_coins[cnc_index]))
      goto cleanup;
    mc->commit_links[cnc_index]
      = GNUNET_malloc (mc->num_oldcoins *
                       sizeof (struct TALER_RefreshCommitLinkP));
    if (GNUNET_OK !=
        postgres_get_refresh_commit_links (cls,
                                           session,
                                           session_hash,
                                           cnc_index,
                                           mc->num_oldcoins,
                                           mc->commit_links[cnc_index]))
      goto cleanup;
  }
  return mc;

 cleanup:
  common_free_melt_commitment (cls, mc);
  return NULL;
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
                             struct TALER_MINTDB_Session *session,
                             const struct GNUNET_HashCode *session_hash,
                             uint16_t newcoin_index,
                             const struct TALER_DenominationSignature *ev_sig)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (session_hash),
    TALER_PQ_query_param_uint16 (&newcoin_index),
    TALER_PQ_query_param_rsa_signature (ev_sig->rsa_signature),
    TALER_PQ_query_param_end
  };

  result = TALER_PQ_exec_prepared (session->conn,
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
static struct TALER_MINTDB_LinkDataList *
postgres_get_link_data_list (void *cls,
                             struct TALER_MINTDB_Session *session,
                             const struct GNUNET_HashCode *session_hash)
{
  struct TALER_MINTDB_LinkDataList *ldl;
  struct TALER_MINTDB_LinkDataList *pos;
  int i;
  int nrows;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (session_hash),
    TALER_PQ_query_param_end
  };
  PGresult *result;

  result = TALER_PQ_exec_prepared (session->conn,
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

  for (i = 0; i < nrows; i++)
  {
    struct TALER_RefreshLinkEncrypted *link_enc;
    struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
    struct GNUNET_CRYPTO_rsa_Signature *sig;
    void *ld_buf;
    size_t ld_buf_size;
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_variable_size ("link_vector_enc",
                                          &ld_buf,
                                          &ld_buf_size),
      TALER_PQ_result_spec_rsa_signature ("ev_sig",
                                          &sig),
      TALER_PQ_result_spec_rsa_public_key ("denom_pub",
                                           &denom_pub),
      TALER_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, i))
    {
      PQclear (result);
      GNUNET_break (0);
      common_free_link_data_list (cls,
                                  ldl);
      return NULL;
    }
    if (ld_buf_size < sizeof (struct GNUNET_CRYPTO_EddsaPrivateKey))
    {
      PQclear (result);
      GNUNET_free (ld_buf);
      common_free_link_data_list (cls,
                                  ldl);
      return NULL;
    }
    link_enc = TALER_refresh_link_encrypted_decode (ld_buf,
                                                    ld_buf_size);
    GNUNET_free (ld_buf);
    pos = GNUNET_new (struct TALER_MINTDB_LinkDataList);
    pos->next = ldl;
    pos->link_data_enc = link_enc;
    pos->denom_pub.rsa_public_key = denom_pub;
    pos->ev_sig.rsa_signature = sig;
    ldl = pos;
  }
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
                       struct TALER_MINTDB_Session *session,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       TALER_MINTDB_TransferDataCallback tdc,
                       void *tdc_cls)
{
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_query_param_auto_from_type (coin_pub),
    TALER_PQ_query_param_end
  };
  PGresult *result;
  int nrows;
  int i;

  result = TALER_PQ_exec_prepared (session->conn,
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
    struct TALER_EncryptedLinkSecretP shared_secret_enc;
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_auto_from_type ("transfer_pub", &transfer_pub),
      TALER_PQ_result_spec_auto_from_type ("link_secret_enc", &shared_secret_enc),
      TALER_PQ_result_spec_auto_from_type ("session_hash", &session_hash),
      TALER_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        TALER_PQ_extract_result (result, rs, 0))
    {
      PQclear (result);
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    tdc (tdc_cls,
         &session_hash,
         &transfer_pub,
         &shared_secret_enc);
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Compile a list of all (historic) transactions performed
 * with the given coin (/refresh/melt and /deposit operations).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub coin to investigate
 * @return list of transactions, NULL if coin is fresh
 */
static struct TALER_MINTDB_TransactionList *
postgres_get_coin_transactions (void *cls,
                                struct TALER_MINTDB_Session *session,
                                const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  struct TALER_MINTDB_TransactionList *head;

  head = NULL;
  /* check deposits */
  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (&coin_pub->eddsa_pub),
      TALER_PQ_query_param_end
    };
    int nrows;
    int i;
    PGresult *result;
    struct TALER_MINTDB_TransactionList *tl;

    result = TALER_PQ_exec_prepared (session->conn,
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
      struct TALER_MINTDB_Deposit *deposit;

      deposit = GNUNET_new (struct TALER_MINTDB_Deposit);
      {
        struct TALER_PQ_ResultSpec rs[] = {
          TALER_PQ_result_spec_rsa_public_key ("denom_pub",
                                               &deposit->coin.denom_pub.rsa_public_key),
          TALER_PQ_result_spec_rsa_signature ("denom_sig",
                                              &deposit->coin.denom_sig.rsa_signature),
          TALER_PQ_result_spec_uint64 ("transaction_id",
                                       &deposit->transaction_id),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &deposit->amount_with_fee),
          TALER_PQ_result_spec_amount ("deposit_fee",
                                       &deposit->deposit_fee),
          TALER_PQ_result_spec_absolute_time ("timestamp",
                                              &deposit->timestamp),
          TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                              &deposit->refund_deadline),
          TALER_PQ_result_spec_auto_from_type ("merchant_pub",
                                               &deposit->merchant_pub),
          TALER_PQ_result_spec_auto_from_type ("h_contract",
                                               &deposit->h_contract),
          TALER_PQ_result_spec_auto_from_type ("h_wire",
                                               &deposit->h_wire),
          TALER_PQ_result_spec_json ("wire",
                                     &deposit->wire),
          TALER_PQ_result_spec_auto_from_type ("coin_sig",
                                               &deposit->csig),
          TALER_PQ_result_spec_end
        };

        if (GNUNET_OK !=
            TALER_PQ_extract_result (result, rs, i))
        {
          GNUNET_break (0);
          GNUNET_free (deposit);
          PQclear (result);
          goto cleanup;
        }
        deposit->coin.coin_pub = *coin_pub;
      }
      tl = GNUNET_new (struct TALER_MINTDB_TransactionList);
      tl->next = head;
      tl->type = TALER_MINTDB_TT_DEPOSIT;
      tl->details.deposit = deposit;
      head = tl;
      continue;
    }
    PQclear (result);
  }
  /* Handle refreshing */
  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_query_param_auto_from_type (&coin_pub->eddsa_pub),
      TALER_PQ_query_param_end
    };
    int nrows;
    int i;
    PGresult *result;
    struct TALER_MINTDB_TransactionList *tl;

    /* check if the melt record exists and get it */
    result = TALER_PQ_exec_prepared (session->conn,
                                     "get_refresh_melt_by_coin",
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
      struct TALER_MINTDB_RefreshMelt *melt;

      melt = GNUNET_new (struct TALER_MINTDB_RefreshMelt);
      {
        struct TALER_PQ_ResultSpec rs[] = {
          TALER_PQ_result_spec_auto_from_type ("session_hash",
                                               &melt->session_hash),
          /* oldcoin_index not needed */
          TALER_PQ_result_spec_auto_from_type ("coin_sig",
                                               &melt->coin_sig),
          TALER_PQ_result_spec_amount ("amount_with_fee",
                                       &melt->amount_with_fee),
          TALER_PQ_result_spec_amount ("melt_fee",
                                       &melt->melt_fee),
          TALER_PQ_result_spec_end
        };
        if (GNUNET_OK !=
            TALER_PQ_extract_result (result, rs, 0))
        {
          GNUNET_break (0);
          GNUNET_free (melt);
          PQclear (result);
          goto cleanup;
        }
	melt->coin.coin_pub = *coin_pub;
      }
      tl = GNUNET_new (struct TALER_MINTDB_TransactionList);
      tl->next = head;
      tl->type = TALER_MINTDB_TT_REFRESH_MELT;
      tl->details.melt = melt;
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
 * Try to find the wire transfer details for a deposit operation.
 * If we did not execute the deposit yet, return when it is supposed
 * to be executed.
 * 
 * @param cls closure
 * @param h_contract hash of the contract
 * @param h_wire hash of merchant wire details
 * @param coin_pub public key of deposited coin
 * @param merchant_pub merchant public key
 * @param transaction_id transaction identifier
 * @param cb function to call with the result
 * @param cb_cls closure to pass to @a cb
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on DB errors
 */
static int
postgres_wire_lookup_deposit_wtid (void *cls,
				   const struct GNUNET_HashCode *h_contract,
				   const struct GNUNET_HashCode *h_wire,
				   const struct TALER_CoinSpendPublicKeyP *coin_pub,
				   const struct TALER_MerchantPublicKeyP *merchant_pub,
				   uint64_t transaction_id,
				   TALER_MINTDB_DepositWtidCallback cb,
				   void *cb_cls)
{
  GNUNET_break (0); // not implemented
  return GNUNET_SYSERR;
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_MINTDB_Plugin`
 */
void *
libtaler_plugin_mintdb_postgres_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_MINTDB_Plugin *plugin;

  pg = GNUNET_new (struct PostgresClosure);

  if (0 != pthread_key_create (&pg->db_conn_threadlocal,
                               &db_conn_destroy))
  {
    TALER_LOG_ERROR ("Cannnot create pthread key.\n");
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mintdb-postgres",
                                             "db_conn_str",
                                             &pg->connection_cfg_str))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint",
                               "db_conn_str");
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_MINTDB_Plugin);
  plugin->cls = pg;
  plugin->get_session = &postgres_get_session;
  plugin->drop_temporary = &postgres_drop_temporary;
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
  plugin->iterate_deposits = &postgres_iterate_deposits;
  plugin->insert_deposit = &postgres_insert_deposit;

  plugin->get_refresh_session = &postgres_get_refresh_session;
  plugin->create_refresh_session = &postgres_create_refresh_session;
  plugin->insert_refresh_melt = &postgres_insert_refresh_melt;
  plugin->get_refresh_melt = &postgres_get_refresh_melt;
  plugin->insert_refresh_order = &postgres_insert_refresh_order;
  plugin->get_refresh_order = &postgres_get_refresh_order;
  plugin->insert_refresh_commit_coins = &postgres_insert_refresh_commit_coins;
  plugin->get_refresh_commit_coins = &postgres_get_refresh_commit_coins;
  plugin->insert_refresh_commit_links = &postgres_insert_refresh_commit_links;
  plugin->get_refresh_commit_links = &postgres_get_refresh_commit_links;

  plugin->get_melt_commitment = &postgres_get_melt_commitment;
  plugin->free_melt_commitment = &common_free_melt_commitment;
  plugin->insert_refresh_out = &postgres_insert_refresh_out;
  plugin->get_link_data_list = &postgres_get_link_data_list;
  plugin->free_link_data_list = &common_free_link_data_list;
  plugin->get_transfer = &postgres_get_transfer;
  plugin->get_coin_transactions = &postgres_get_coin_transactions;
  plugin->free_coin_transaction_list = &common_free_coin_transaction_list;
  plugin->wire_lookup_deposit_wtid = &postgres_wire_lookup_deposit_wtid;
  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_MINTDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_mintdb_postgres_done (void *cls)
{
  struct TALER_MINTDB_Plugin *plugin = cls;
  struct PostgresClosure *pg = plugin->cls;

  GNUNET_free (pg->connection_cfg_str);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_mintdb_postgres.c */
