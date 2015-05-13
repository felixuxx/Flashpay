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
#include "taler_signatures.h"
#include "taler_mintdb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>

#include "plugin_mintdb_common.c"

#define TALER_TEMP_SCHEMA_NAME "taler_temporary"

#define QUERY_ERR(result)                          \
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed at %s:%u: %s\n", __FILE__, __LINE__, PQresultErrorMessage (result))


#define BREAK_DB_ERR(result) do { \
    GNUNET_break(0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s\n", PQresultErrorMessage (result)); \
  } while (0)

/**
 * Shorthand for exit jumps.
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


#define SQLEXEC_(conn, sql, result)                                     \
  do {                                                                  \
    result = PQexec (conn, sql);                                        \
    if (PGRES_COMMAND_OK != PQresultStatus (result))                    \
    {                                                                   \
      BREAK_DB_ERR (result);                                            \
      PQclear (result); result = NULL;                                  \
      goto SQLEXEC_fail;                                                \
    }                                                                   \
    PQclear (result); result = NULL;                                    \
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
   * Contains a pointer to PGconn or NULL.
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
  PGresult *result;

  SQLEXEC_(db,
           "CREATE SCHEMA IF NOT EXISTS " TALER_TEMP_SCHEMA_NAME ";"
           "SET search_path to " TALER_TEMP_SCHEMA_NAME ";",
           result);
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
  PGresult *result;

  SQLEXEC_ (session->conn,
            "DROP SCHEMA " TALER_TEMP_SCHEMA_NAME " CASCADE;",
            result);
  return GNUNET_OK;
 SQLEXEC_fail:
  return GNUNET_SYSERR;
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
  PGresult *result;
  PGconn *conn;

  result = NULL;
  conn = PQconnectdb (pc->connection_cfg_str);
  if (CONNECTION_OK != PQstatus (conn))
  {
    TALER_LOG_ERROR ("Database connection failed: %s\n",
               PQerrorMessage (conn));
    GNUNET_break (0);
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
  if ( (GNUNET_YES == temporary) &&
       (GNUNET_SYSERR == set_temporary_schema (conn)))
  {
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
#define SQLEXEC(sql) SQLEXEC_(conn, sql, result);
  /* Denomination table for holding the publicly available information of
     denominations keys.  The denominations are to be referred to by using
     foreign keys.  The denominations are deleted by a housekeeping tool;
     hence, do not use `ON DELETE CASCASE' on these rows in the tables
     referencing these rows */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS denominations"
           "("
           " pub BYTEA PRIMARY KEY"
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
           ",fee_refresh_val INT8 NOT NULL"
           ",fee_refresh_frac INT4 NOT NULL"
           ",fee_refresh_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ")");
  /* reserves table is for summarization of a reserve.  It is updated when new
     funds are added and existing funds are withdrawn */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS reserves"
           "("
           " reserve_pub BYTEA PRIMARY KEY"
           ",current_balance_val INT8 NOT NULL"
           ",current_balance_frac INT4 NOT NULL"
           ",current_balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
           ",expiration_date INT8 NOT NULL"
           ")");
  /* reserves_in table collects the transactions which transfer funds into the
     reserve.  The amount and expiration date for the corresponding reserve are
     updated when new transfer funds are added.  The rows of this table
     correspond to each incoming transaction. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS reserves_in"
          "("
          " reserve_pub BYTEA REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
          ",balance_val INT8 NOT NULL"
          ",balance_frac INT4 NOT NULL"
          ",balance_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",details VARCHAR NOT NULL "
          ",expiration_date INT8 NOT NULL"
          " CONSTRAINT unique_details PRIMARY KEY (reserve_pub,details)"
          ");");
  /* Create indices on reserves_in */
  SQLEXEC ("CREATE INDEX reserves_in_reserve_pub_index"
           " ON reserves_in (reserve_pub);");
  SQLEXEC ("CREATE INDEX reserves_in_reserve_pub_details_index"
           " ON reserves_in (reserve_pub,details);");
  SQLEXEC ("CREATE INDEX expiration_index"
           " ON reserves_in (expiration_date);");
  /* Table with the withdraw operations that have been performed on a reserve.
     TODO: maybe rename to "reserves_out"?
     TODO: is blind_ev really a _primary key_? Is this constraint useful? */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS collectable_blindcoins"
           "("
           "blind_ev BYTEA PRIMARY KEY"
           ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
           ",denom_sig BYTEA NOT NULL"
           ",reserve_pub BYTEA NOT NULL CHECK (LENGTH(reserve_pub)=32) REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
           ",reserve_sig BYTEA NOT NULL CHECK (LENGTH(reserve_sig)=64)"
           ");");
  /* Index blindcoins(reserve_pub) for get_reserves_blindcoins statement */
  SQLEXEC ("CREATE INDEX collectable_blindcoins_reserve_pub_index ON"
           " collectable_blindcoins (reserve_pub)");
  /* Table with coins that have been (partially) spent, used to detect
     double-spending.
     TODO: maybe rename to "spent_coins"?
     TODO: maybe have two tables, one for spending and one for refreshing, instead of optional refresh_session_hash? */
  SQLEXEC("CREATE TABLE IF NOT EXISTS known_coins "
          "("
          " coin_pub BYTEA NOT NULL PRIMARY KEY"
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
          ",denom_sig BYTEA NOT NULL"
          ",expended_val INT8 NOT NULL"
          ",expended_frac INT4 NOT NULL"
          ",expended_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",refresh_session_hash BYTEA"
          ")");
  /**
   * The DB will show negative values for some values of the following fields as
   * we use them as 16 bit unsigned integers
   *   @a num_oldcoins
   *   @a num_newcoins
   * Do not do arithmetic in SQL on these fields.
   *
   * TODO: isn't "reveal_ok" no longer interesting / required / used?
   */
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_sessions "
          "("
          " session_hash BYTEA PRIMARY KEY CHECK (LENGTH(session_hash)=64)"
          ",num_oldcoins INT2 NOT NULL"
          ",num_newcoins INT2 NOT NULL"
          ",noreveal_index INT2 NOT NULL"
          // non-zero if all reveals were ok
          // and the new coin signatures are ready
          ",reveal_ok BOOLEAN NOT NULL DEFAULT false"
          ") ");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_order "
          "( "
          " session_hash BYTEA NOT NULL CHECK (LENGTH(session_hash)=64) REFERENCES refresh_sessions (session_hash)"
          ",newcoin_index INT2 NOT NULL "
          ",denom_pub BYTEA NOT NULL "
          ",PRIMARY KEY (session_hash, newcoin_index)"
          ") ");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_link"
          "("
          " session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash)"
          ",transfer_pub BYTEA NOT NULL CHECK(LENGTH(transfer_pub)=32)"
          ",link_secret_enc BYTEA NOT NULL"
          // index of the old coin in the customer's request
          ",oldcoin_index INT2 NOT NULL"
          // index for cut and choose,
          // ranges from 0 to #TALER_CNC_KAPPA-1
          ",cnc_index INT2 NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_coin"
          "("
          " session_hash BYTEA NOT NULL REFERENCES refresh_sessions (session_hash) "
          ",link_vector_enc BYTEA NOT NULL"
          // index of the new coin in the customer's request
          ",newcoin_index INT2 NOT NULL"
          // index for cut and choose,
          ",cnc_index INT2 NOT NULL"
          ",coin_ev BYTEA NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_melt"
          "("
          " session_hash BYTEA NOT NULL CHECK(LENGTH(session_hash=64)) REFERENCES refresh_sessions (session_hash) "
          ",coin_pub BYTEA NOT NULL CHECK(LENGTH(coin_pub)=32) REFERENCES known_coins (coin_pub) "
          ",coin_sig BYTEA NOT NULL CHECK(LENGTH(coin_sig)=64)"
          ",denom_pub BYTEA NOT NULL "
          ",denom_sig BYTEA NOT NULL "
          ",amount_val INT8 NOT NULL "
          ",amount_frac INT8 NOT NULL "
          ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL "
          ",fee_val INT8 NOT NULL "
          ",fee_frac INT8 NOT NULL "
          ",fee_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL "
          ",oldcoin_index INT2 NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_collectable"
          "("
          " session_hash BYTEA NOT NULL CHECK(LENGTH(session_hash)=64) REFERENCES refresh_sessions (session_hash) "
          ",ev_sig BYTEA NOT NULL"
          ",newcoin_index INT2 NOT NULL"
          ")");
  /* This table contains the wire transfers the mint is supposed to
     execute to transmit funds to the merchants (and manage refunds).
     TODO: we might want to generate some other primary key
     to internally identify outgoing transactions, as "coin_pub"
     may not be unique if a wallet chooses not to refresh.  The
     resulting transaction ID should then be returned to the merchant
     and could be used by the mearchant for further inquriries about
     the deposit's execution. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS deposits "
          "( "
          /* FIXME #3769: the following primary key may be too restrictive */
          " coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (LENGTH(coin_pub)=32)"
          ",denom_pub BYTEA NOT NULL REFERENCES denominations (pub)"
          ",denom_sig BYTEA NOT NULL"
          ",transaction_id INT8 NOT NULL"
          ",amount_val INT8 NOT NULL"
          ",amount_frac INT4 NOT NULL"
          ",amount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
          ",merchant_pub BYTEA NOT NULL CHECK (LENGTH(merchant_pub)=32)"
          ",h_contract BYTEA NOT NULL CHECK (LENGTH(h_contract)=64)"
          ",h_wire BYTEA NOT NULL CHECK (LENGTH(h_wire)=64)"
          ",coin_sig BYTEA NOT NULL CHECK (LENGTH(coin_sig)=64)"
          ",wire TEXT NOT NULL"
          ")");
#undef SQLEXEC

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

  PREPARE ("insert_denomination",
           "INSERT INTO denominations ("
           " pub"
           ",valid_from"
           ",expire_withdraw"
           ",expire_spend"
           ",expire_legal"
           ",coin_val" /* value of this denom */
           ",coin_frac" /* fractional value of this denom */
           ",coin_curr" /* assuming same currency for fees */
           ",fee_withdraw_val"
           ",fee_withdraw_frac"
           ",fee_withdraw_curr" /* must match coin_currency */
           ",fee_refresh_val"
           ",fee_refresh_frac"
           ",fee_refresh_curr" /* must match coin_currency */
           ") VALUES "
           "($1, $2, $3, $4, $5, $6,"
            "$7, $8, $9, $10, $11, $12, $13, $14);",
           14, NULL);
  PREPARE ("get_reserve",
           "SELECT "
           "current_balance_val"
           ",current_balance_frac"
           ",current_balance_curr"
           ",expiration_date "
           "FROM reserves "
           "WHERE reserve_pub=$1 "
           "LIMIT 1; ",
           1, NULL);
  PREPARE ("create_reserve",
           "INSERT INTO reserves ("
           " reserve_pub,"
           " current_balance_val,"
           " current_balance_frac,"
           " current_balance_curr,"
           " expiration_date) VALUES ("
           "$1, $2, $3, $4, $5);",
           5, NULL);
  PREPARE ("update_reserve",
           "UPDATE reserves "
           "SET"
           "expiration_date=$1 "
           ",current_balance_val=$2 "
           ",current_balance_frac=$3 "
           "WHERE current_balance_curr=$4 AND reserve_pub=$5 ",
           5, NULL);
  PREPARE ("create_reserves_in_transaction",
           "INSERT INTO reserves_in ("
           " reserve_pub,"
           " balance_val,"
           " balance_frac,"
           " balance_curr,"
           " details,"
           " expiration_date) VALUES ("
           " $1, $2, $3, $4, $5, $6);",
           5, NULL);
  PREPARE ("get_reserves_in_transactions",
           "SELECT"
           " balance_val"
           ",balance_frac"
           ",balance_curr"
           ",expiration_date"
           ",details"
           " FROM reserves_in WHERE reserve_pub=$1",
           1, NULL);
  PREPARE ("insert_collectable_blindcoin",
           "INSERT INTO collectable_blindcoins ( "
           " blind_ev"
           ",denom_pub, denom_sig"
           ",reserve_pub, reserve_sig) "
           "VALUES ($1, $2, $3, $4, $5)",
           5, NULL);
  PREPARE ("get_collectable_blindcoin",
           "SELECT "
           " denom_pub, denom_sig"
           ",reserve_sig, reserve_pub "
           "FROM collectable_blindcoins "
           "WHERE blind_ev=$1",
           1, NULL);
  PREPARE ("get_reserves_blindcoins",
           "SELECT"
           " blind_ev"
           ",denom_pub, denom_sig"
           ",reserve_sig"
           " FROM collectable_blindcoins"
           " WHERE reserve_pub=$1;",
           1, NULL);
  /* refreshing */
  PREPARE ("get_refresh_session",
           "SELECT "
           " num_oldcoins"
           ",num_newcoins"
           ",noreveal_index"
           " FROM refresh_sessions "
           " WHERE session_hash=$1 ",
           1, NULL);
  PREPARE ("insert_refresh_session",
           "INSERT INTO refresh_sessions ( "
           " session_hash "
           ",num_oldcoins "
           ",num_newcoins "
           ",noreveal_index "
           ") "
           "VALUES ($1, $2, $3, $4) ",
           4, NULL);

  PREPARE ("get_known_coin",
           "SELECT"
           " coin_pub, denom_pub, denom_sig "
           ",expended_val, expended_frac, expended_curr "
           ",refresh_session_hash "
           "FROM known_coins "
           "WHERE coin_pub = $1",
           1, NULL);
  PREPARE ("update_known_coin",
           "UPDATE known_coins "
           "SET"
           " denom_pub = $2 "
           ",denom_sig = $3 "
           ",expended_val = $4 "
           ",expended_frac = $5 "
           ",expended_curr = $6 "
           ",refresh_session_hash = $7 "
           "WHERE "
           " coin_pub = $1",
           7, NULL);
  PREPARE ("insert_known_coin",
           "INSERT INTO known_coins ("
           " coin_pub"
           ",denom_pub"
           ",denom_sig"
           ",expended_val"
           ",expended_frac"
           ",expended_curr"
           ",refresh_session_hash"
           ")"
           "VALUES ($1,$2,$3,$4,$5,$6,$7)",
           7, NULL);
  PREPARE ("get_refresh_commit_link",
           "SELECT"
           " transfer_pub "
           ",link_secret_enc "
           "FROM refresh_commit_link "
           "WHERE session_hash = $1 AND cnc_index = $2 AND oldcoin_index = $3",
           3, NULL);
  PREPARE ("get_refresh_commit_coin",
           "SELECT"
           " link_vector_enc "
           ",coin_ev "
           "FROM refresh_commit_coin "
           "WHERE session_hash = $1 AND cnc_index = $2 AND newcoin_index = $3",
           3, NULL);
  PREPARE ("insert_refresh_order",
           "INSERT INTO refresh_order ("
           " newcoin_index "
           ",session_hash "
           ",denom_pub "
           ") "
           "VALUES ($1, $2, $3)",
           3, NULL);
  PREPARE ("insert_refresh_melt",
           "INSERT INTO refresh_melt ("
           " session_hash "
           ",oldcoin_index "
           ",coin_pub "
           ",coin_sig "
           ",denom_pub "
           ",denom_sig "
           ",amount_val "
           ",amount_frac "
           ",amount_curr "
           ",fee_val "
           ",fee_frac "
           ",fee_curr "
           ") "
           "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)",
           12, NULL);
  PREPARE ("get_refresh_order",
           "SELECT denom_pub "
           "FROM refresh_order "
           "WHERE session_hash = $1 AND newcoin_index = $2",
           2, NULL);
  PREPARE ("get_refresh_collectable",
           "SELECT ev_sig "
           "FROM refresh_collectable "
           "WHERE session_hash = $1 AND newcoin_index = $2",
           2, NULL);
  PREPARE ("get_refresh_melt",
           "SELECT coin_pub,coin_sig,denom_pub,denom_sig,amount_val,amount_frac,amount_curr,fee_val,fee_frac,fee_curr "
           "FROM refresh_melt "
           "WHERE session_hash = $1 AND oldcoin_index = $2",
           2, NULL);
  PREPARE ("insert_refresh_commit_link",
           "INSERT INTO refresh_commit_link ("
           " session_hash "
           ",transfer_pub "
           ",cnc_index "
           ",oldcoin_index "
           ",link_secret_enc "
           ") "
           "VALUES ($1, $2, $3, $4, $5) ",
           5, NULL);
  PREPARE ("insert_refresh_commit_coin",
           "INSERT INTO refresh_commit_coin ("
           " session_hash "
           ",coin_ev "
           ",cnc_index "
           ",newcoin_index "
           ",link_vector_enc "
           ") "
           "VALUES ($1, $2, $3, $4, $5)",
           5, NULL);
  PREPARE ("insert_refresh_collectable",
           "INSERT INTO refresh_collectable ("
           " session_hash "
           ",newcoin_index "
           ",ev_sig "
           ") "
           "VALUES ($1, $2, $3)",
           3, NULL);
  PREPARE ("set_reveal_ok",
           "UPDATE refresh_sessions "
           "SET reveal_ok = TRUE "
           "WHERE session_hash = $1",
           1, NULL);
  PREPARE ("get_link",
           "SELECT link_vector_enc, ro.denom_pub, ev_sig "
           "FROM refresh_melt rm "
           "     JOIN refresh_order ro USING (session_hash) "
           "     JOIN refresh_commit_coin rcc USING (session_hash) "
           "     JOIN refresh_sessions rs USING (session_hash) "
           "     JOIN refresh_collectable rc USING (session_hash) "
           "WHERE rm.coin_pub = $1 "
           "AND ro.newcoin_index = rcc.newcoin_index "
           "AND ro.newcoin_index = rc.newcoin_index "
           "AND  rcc.cnc_index = rs.noreveal_index % ( "
           "         SELECT count(*) FROM refresh_commit_coin rcc2 "
           "         WHERE rcc2.newcoin_index = 0 AND rcc2.session_hash = rs.session_hash "
           "     ) ",
           1, NULL);
  PREPARE ("get_transfer",
           "SELECT transfer_pub, link_secret_enc "
           "FROM refresh_melt rm "
           "     JOIN refresh_commit_link rcl USING (session_hash) "
           "     JOIN refresh_sessions rs USING (session_hash) "
           "WHERE rm.coin_pub = $1 "
           "AND  rm.oldcoin_index = rcl.oldcoin_index "
           "AND  rcl.cnc_index = rs.noreveal_index % ( "
           "         SELECT count(*) FROM refresh_commit_coin rcc2 "
           "         WHERE newcoin_index = 0 AND rcc2.session_hash = rm.session_hash "
           "     ) ",
           1, NULL);
  PREPARE ("insert_deposit",
           "INSERT INTO deposits ("
           "coin_pub,"
           "denom_pub,"
           "denom_sig,"
           "transaction_id,"
           "amount_val,"
           "amount_frac,"
           "amount_curr,"
           "merchant_pub,"
           "h_contract,"
           "h_wire,"
           "coin_sig,"
           "wire"
           ") VALUES ("
           "$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12"
           ")",
           12, NULL);
  PREPARE ("get_deposit",
           "SELECT "
           "coin_pub,"
           "denom_pub,"
           "transaction_id,"
           "amount_val,"
           "amount_frac,"
           "amount_curr,"
           "merchant_pub,"
           "h_contract,"
           "h_wire,"
           "coin_sig"
           " FROM deposits WHERE ("
           "(coin_pub = $1) AND"
           "(transaction_id = $2) AND"
           "(merchant_pub = $3)"
           ")",
           3, NULL);
  PREPARE ("get_deposit_with_coin_pub",
           "SELECT "
           "coin_pub,"
           "denom_pub,"
           "transaction_id,"
           "amount_val,"
           "amount_frac,"
           "amount_curr,"
           "merchant_pub,"
           "h_contract,"
           "h_wire,"
           "wire,"
           "coin_sig"
           " FROM deposits WHERE "
           " coin_pub = $1",
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
  PGconn *db_conn = cls;

  if (NULL != db_conn)
    PQfinish (db_conn);
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
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}


/**
 * Insert a denomination key
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param sesssion connection to use
 * @param dki the denomination key information
 * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
 */
static int
postgres_insert_denomination (void *cls,
                              struct TALER_MINTDB_Session *session,
                              const struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  const struct TALER_DenominationKeyValidityPS *issue = &dki->issue;
  PGresult *result;
  int ret;

  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY (dki->denom_pub.rsa_public_key),
    TALER_PQ_QUERY_PARAM_PTR (&issue->start.abs_value_us__),
    TALER_PQ_QUERY_PARAM_PTR (&issue->expire_withdraw.abs_value_us__),
    TALER_PQ_QUERY_PARAM_PTR (&issue->expire_spend.abs_value_us__),
    TALER_PQ_QUERY_PARAM_PTR (&issue->expire_legal.abs_value_us__),
    TALER_PQ_QUERY_PARAM_AMOUNT_NBO (&issue->value),
    TALER_PQ_QUERY_PARAM_AMOUNT_NBO (&issue->fee_withdraw),
    TALER_PQ_QUERY_PARAM_AMOUNT_NBO (&issue->fee_refresh),
    TALER_PQ_QUERY_PARAM_END
  };
  result = TALER_PQ_exec_prepared (session->conn,
                                   "insert_denomination",
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
 * Get the summary of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param reserve the reserve data.  The public key of the reserve should be set
 *          in this structure; it is used to query the database.  The balance
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
    TALER_PQ_QUERY_PARAM_PTR(&reserve->pub),
    TALER_PQ_QUERY_PARAM_END
  };
  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT("current_balance", &reserve->balance),
    TALER_PQ_RESULT_SPEC_ABSOLUTE_TIME("expiration_date", &reserve->expiry),
    TALER_PQ_RESULT_SPEC_END
  };

  result = TALER_PQ_exec_prepared (session->conn,
                                   "get_reserve",
                                   params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    PQclear (resultE);
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_NO;
  }
  EXITIF (GNUNET_OK !=
	  TALER_PQ_extract_result (result,
				   rs,
				   0));
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
postgres_reserves_update (void *cls,
                          struct TALER_MINTDB_Session *session,
                          struct TALER_MINTDB_Reserve *reserve)
{
  PGresult *result;
  int ret;

  if (NULL == reserve)
    return GNUNET_SYSERR;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_ABSOLUTE_TIME (reserve->expiry),
    TALER_PQ_QUERY_PARAM_AMOUNT (&reserve->balance),
    TALER_PQ_QUERY_PARAM_PTR (&reserve->pub),
    TALER_PQ_QUERY_PARAM_END
  };
  result = TALER_PQ_exec_prepared (session->conn,
                                   "update_reserve",
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
 * Insert a incoming transaction into reserves.  New reserves are also created
 * through this function.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param reserve_pub public key of the reserve
 * @param balance the amount that has to be added to the reserve
 * @param details bank transaction details justifying the increment,
 *        must be unique for each incoming transaction
 * @param expiry the new expiration time for the reserve
 * @return #GNUNET_OK upon success; #GNUNET_NO if the given
 *         @a details are already known for this @a reserve_pub,
 *         #GNUNET_SYSERR upon failures (DB error, incompatible currency)
 */
static int
postgres_reserves_in_insert (void *cls,
                             struct TALER_MINTDB_Session *session,
                             struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             const char *details,
                             const struct GNUNET_TIME_Absolute expiry)
{
  PGresult *result;
  int reserve_exists;
  struct TALER_MINTDB_Reserve reserve;
  struct TALER_MINTDB_Reserve updated_reserve;

  result = NULL;
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
    postgres_rollback (cls,
                       session);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO == reserve_exists)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR (reserve_pub),
      TALER_PQ_QUERY_PARAM_AMOUNT (balance),
      TALER_PQ_QUERY_PARAM_ABSOLUTE_TIME (expiry),
      TALER_PQ_QUERY_PARAM_END
    };
    result = TALER_PQ_exec_prepared (session->conn,
                                     "create_reserve",
                                     params);
    if (PGRES_COMMAND_OK != PQresultStatus(result))
    {
      QUERY_ERR (result);
      goto rollback;
    }
  }
  else
  {
    /* Update reserve */
    updated_reserve.pub = reserve->pub;

    if (GNUNET_OK !=
        TALER_amount_add (&updated_reserve.balance,
                          &reserve->balance,
                          balance))
    {
      /* currency overflow or incompatible currency */
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Attempt to deposit incompatible amount into reserve\n");
      goto rollback;
    }
    updated_reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                                       reserve->expiry);

  }
  if (NULL != result)
    PQclear (result);
  result = NULL;
  /* create new incoming transaction, SQL "primary key" logic
     is used to guard against duplicates! */
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR (&reserve->pub),
    TALER_PQ_QUERY_PARAM_AMOUNT (balance),
    TALER_PQ_QUERY_PARAM_PTR_SIZED (details, strlen (details)),
    TALER_PQ_QUERY_PARAM_ABSOLUTE_TIME (expiry),
    TALER_PQ_QUERY_PARAM_END
  };
  result = TALER_PQ_exec_prepared (session->conn,
                                   "create_reserves_in_transaction",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    QUERY_ERR (result);
    goto rollback;
  }
  PQclear (result);
  result = NULL;
  if ( (GNUNET_YES == reserve_exists) &&
       (GNUNET_OK != postgres_reserves_update (cls,
                                               session,
                                               &updated_reserve)) )
    goto rollback;
  if (GNUNET_OK != postgres_commit (cls,
                                    session))
    return GNUNET_SYSERR;
  return GNUNET_OK;
 rollback:
  if (NULL != result)
    PQclear (result);
  postgres_rollback (cls,
                     session);
  return GNUNET_SYSERR;
}


/**
 * Locate the response for a /withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param h_blind hash of the blinded message
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
static int
postgres_get_collectable_blindcoin (void *cls,
                                    struct TALER_MINTDB_Session *session,
                                    const struct GNUNET_HashCode *h_blind,
                                    struct TALER_MINTDB_CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR (h_blind),
    TALER_PQ_QUERY_PARAM_END
  };
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
  struct GNUNET_CRYPTO_rsa_Signature *denom_sig;
  int ret;

  ret = GNUNET_SYSERR;
  result = TALER_PQ_exec_prepared (session->conn,
                                   "get_collectable_blindcoin",
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
  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_RSA_PUBLIC_KEY("denom_pub", &denom_pub),
    TALER_PQ_RESULT_SPEC_RSA_SIGNATURE("denom_sig", &denom_sig),
    TALER_PQ_RESULT_SPEC("reserve_sig", &collectable->reserve_sig),
    TALER_PQ_RESULT_SPEC("reserve_pub", &collectable->reserve_pub),
    TALER_PQ_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_PQ_extract_result (result, rs, 0))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  collectable->denom_pub.rsa_public_key = denom_pub;
  collectable->sig.rsa_signature = denom_sig;
  ret = GNUNET_YES;

 cleanup:
  PQclear (result);
  if (GNUNET_YES != ret)
    TALER_PQ_cleanup_result (rs);
  return ret;
}


/**
 * Store collectable bit coin under the corresponding
 * hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param h_blind hash of the blinded message
 * @param withdraw amount by which the reserve will be withdrawn with this
 *          transaction
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
static int
postgres_insert_collectable_blindcoin (void *cls,
                                       struct TALER_MINTDB_Session *session,
                                       const struct GNUNET_HashCode *h_blind,
                                       struct TALER_Amount withdraw,
                                       const struct TALER_MINTDB_CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_MINTDB_Reserve reserve;
  int ret = GNUNET_SYSERR;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR (h_blind),
    TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY (collectable->denom_pub.rsa_public_key),
    TALER_PQ_QUERY_PARAM_RSA_SIGNATURE (collectable->sig.rsa_signature),
    TALER_PQ_QUERY_PARAM_PTR (&collectable->reserve_pub),
    TALER_PQ_QUERY_PARAM_PTR (&collectable->reserve_sig),
    TALER_PQ_QUERY_PARAM_END
  };

  if (GNUNET_OK != postgres_start (cls,
                                   session))
  {
    return GNUNET_SYSERR;
  }
  result = TALER_PQ_exec_prepared (session->conn,
                                   "insert_collectable_blindcoin",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    goto rollback;
  }
  reserve.pub = collectable->reserve_pub;
  if (GNUNET_OK != postgres_reserve_get (cls,
                                         session,
                                         &reserve))
    goto rollback;
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&reserve.balance,
                             &reserve.balance,
                             &withdraw))
    goto rollback;
  if (GNUNET_OK != postgres_reserves_update (cls,
                                             session,
                                             &reserve))
    goto rollback;
  if (GNUNET_OK == postgres_commit (cls,
                                    session))
  {
    ret = GNUNET_OK;
    goto cleanup;
  }

 rollback:
  postgres_rollback (cls,
                     session);
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
  struct TALER_MINTDB_ReserveHistory *rh_head;
  int rows;
  int ret;

  result = NULL;
  rh = NULL;
  rh_head = NULL;
  ret = GNUNET_SYSERR;
  {
    struct TALER_MINTDB_BankTransfer *bt;
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR (reserve_pub),
      TALER_PQ_QUERY_PARAM_END
    };

    result = TALER_PQ_exec_prepared (session->conn,
                                     "get_reserves_in_transactions",
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
      if (GNUNET_OK != TALER_PQ_extract_amount (result,
                                                --rows,
                                                "balance_val",
                                                "balance_frac",
                                                "balance_curr",
                                                &bt->amount))
      {
        GNUNET_free (bt);
        GNUNET_break (0);
        goto cleanup;
      }
      bt->reserve_pub = *reserve_pub;
      if (NULL != rh_head)
      {
        rh_head->next = GNUNET_new (struct TALER_MINTDB_ReserveHistory);
        rh_head = rh_head->next;
      }
      else
      {
        rh_head = GNUNET_new (struct TALER_MINTDB_ReserveHistory);
        rh = rh_head;
      }
      rh_head->type = TALER_MINTDB_RO_BANK_TO_MINT;
      rh_head->details.bank = bt;
    }
  }
  PQclear (result);
  result = NULL;
  {
    struct GNUNET_HashCode blind_ev;
    struct TALER_ReserveSignatureP reserve_sig;
    struct TALER_MINTDB_CollectableBlindcoin *cbc;
    struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
    struct GNUNET_CRYPTO_rsa_Signature *denom_sig;

    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR (reserve_pub),
      TALER_PQ_QUERY_PARAM_END
    };
    result = TALER_PQ_exec_prepared (session->conn,
                                     "get_reserves_blindcoins",
                                     params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      QUERY_ERR (result);
      goto cleanup;
    }
    if (0 == (rows = PQntuples (result)))
    {
      ret = GNUNET_OK;          /* Its OK if there are no withdrawls yet */
      goto cleanup;
    }
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC ("blind_ev", &blind_ev),
      TALER_PQ_RESULT_SPEC_RSA_PUBLIC_KEY ("denom_pub", &denom_pub),
      TALER_PQ_RESULT_SPEC_RSA_SIGNATURE ("denom_sig", &denom_sig),
      TALER_PQ_RESULT_SPEC ("reserve_sig", &reserve_sig),
      TALER_PQ_RESULT_SPEC_END
    };
    GNUNET_assert (NULL != rh);
    GNUNET_assert (NULL != rh_head);
    GNUNET_assert (NULL == rh_head->next);
    while (0 < rows)
    {
      if (GNUNET_YES !=
	  TALER_PQ_extract_result (result, rs, --rows))
      {
        GNUNET_break (0);
        goto cleanup;
      }
      cbc = GNUNET_new (struct TALER_MINTDB_CollectableBlindcoin);
      cbc->sig.rsa_signature = denom_sig;
      cbc->denom_pub.rsa_public_key = denom_pub;
      cbc->h_coin_envelope =  blind_ev;
      cbc->reserve_pub = *reserve_pub;
      cbc->reserve_sig = reserve_sig;
      rh_head->next = GNUNET_new (struct TALER_MINTDB_ReserveHistory);
      rh_head = rh_head->next;
      rh_head->type = TALER_MINTDB_RO_WITHDRAW_COIN;
      rh_head->details.withdraw = cbc;
    }
  }
  ret = GNUNET_OK;

 cleanup:
  if (NULL != result)
    PQclear (result);
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
 *         #GNUNET_NO if this deposit is unknown to us
 */
static int
postgres_have_deposit (void *cls,
                       struct TALER_MINTDB_Session *session,
                       const struct TALER_MINTDB_Deposit *deposit)
{
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR (&deposit->coin.coin_pub),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->transaction_id),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->merchant_pub),
    TALER_PQ_QUERY_PARAM_END
  };
  PGresult *result;
  int ret;

  ret = GNUNET_SYSERR;
  result = TALER_PQ_exec_prepared (session->conn,
                                   "get_deposit",
                                   params);
  if (PGRES_TUPLES_OK !=
      PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    goto cleanup;
  }

  if (0 == PQntuples (result))
  {
    ret = GNUNET_NO;
    goto cleanup;
  }
  ret = GNUNET_YES;

 cleanup:
  PQclear (result);
  return ret;
}


/**
 * Insert information about deposited coin into the
 * database.
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
  char *json_wire_enc;
  PGresult *result;
  int ret;

  ret = GNUNET_SYSERR;
  json_wire_enc = json_dumps (deposit->wire, JSON_COMPACT);
  struct TALER_PQ_QueryParam params[]= {
    TALER_PQ_QUERY_PARAM_PTR (&deposit->coin.coin_pub),
    TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY (deposit->coin.denom_pub.rsa_public_key),
    TALER_PQ_QUERY_PARAM_RSA_SIGNATURE (deposit->coin.denom_sig.rsa_signature),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->transaction_id),
    TALER_PQ_QUERY_PARAM_AMOUNT (&deposit->amount_with_fee),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->merchant_pub),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->h_contract),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->h_wire),
    TALER_PQ_QUERY_PARAM_PTR (&deposit->csig),
    TALER_PQ_QUERY_PARAM_PTR_SIZED (json_wire_enc,
                                    strlen (json_wire_enc)),
    TALER_PQ_QUERY_PARAM_END
  };
  result = TALER_PQ_exec_prepared (session->conn, "insert_deposit", params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    goto cleanup;
  }
  ret = GNUNET_OK;

 cleanup:
  PQclear (result);
  GNUNET_free_non_null (json_wire_enc);
  return ret;
}


/**
 * Lookup refresh session data under the given @a session_hash.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param session_hash hash over the melt to use to locate the session
 * @param[out] refresh_session where to store the result
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
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_END
  };
  int ret;
  uint16_t num_oldcoins;
  uint16_t num_newcoins;
  uint16_t noreveal_index;

  ret = GNUNET_SYSERR;
  result = TALER_PQ_exec_prepared (session->conn,
                                   "get_refresh_session",
                                   params);
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    goto cleanup;
  }
  if (0 == PQntuples (result))
  {
    ret = GNUNET_NO;
    goto cleanup;
  }
  GNUNET_assert (1 == PQntuples (result));
  /* We're done if the caller is only interested in whether the session exists
   * or not */
  if (NULL == refresh_session)
  {
    ret = GNUNET_YES;
    goto cleanup;
  }
  memset (refresh_session, 0, sizeof (struct TALER_MINTDB_RefreshSession));
  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC("num_oldcoins", &num_oldcoins),
    TALER_PQ_RESULT_SPEC("num_newcoins", &num_newcoins),
    TALER_PQ_RESULT_SPEC("noreveal_index", &noreveal_index),
    TALER_PQ_RESULT_SPEC_END
  };
  if (GNUNET_OK != TALER_PQ_extract_result (result, rs, 0))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  refresh_session->num_oldcoins = ntohs (num_oldcoins);
  refresh_session->num_newcoins = ntohs (num_newcoins);
  refresh_session->noreveal_index = ntohs (noreveal_index);
  ret = GNUNET_YES;

 cleanup:
  if (NULL != result)
    PQclear (result);
  return ret;
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
  uint16_t num_oldcoins;
  uint16_t num_newcoins;
  uint16_t noreveal_index;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_PTR(&num_oldcoins),
    TALER_PQ_QUERY_PARAM_PTR(&num_newcoins),
    TALER_PQ_QUERY_PARAM_PTR(&noreveal_index),
    TALER_PQ_QUERY_PARAM_END
  };
  num_oldcoins = htons (refresh_session->num_oldcoins);
  num_newcoins = htons (refresh_session->num_newcoins);
  noreveal_index = htons (refresh_session->noreveal_index);
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
  // FIXME: check logic!
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);
  PGresult *result;

  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR(&melt->session_hash),
      TALER_PQ_QUERY_PARAM_PTR(&oldcoin_index_nbo),
      TALER_PQ_QUERY_PARAM_PTR(&melt->coin.coin_pub),
      TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY(melt->coin.denom_pub.rsa_public_key),
      TALER_PQ_QUERY_PARAM_END
    };
    result = TALER_PQ_exec_prepared (session->conn,
                                     "insert_refresh_melt",
                                     params);
  }
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
 * @param melt melt data to fill in
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
#if 0
  // FIXME: check logic!
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);
  struct TALER_PQ_Query params[] = {
    TALER_PQ_QUERY_PARAM_PTR (session_hash),
    TALER_PQ_QUERY_PARAM_PTR (&oldcoin_index_nbo),
    TALER_PQ_QUERY_PARAM_END
  };
  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC ("coin_pub", &melt->coin),
    TALER_PQ_RESULT_SPEC ("coin_sig", &melt->coin_sig),
    TALER_PQ_RESULT_SPEC ("denom_pub", &melt->coin),
    TALER_PQ_RESULT_SPEC ("denom_sig", &melt->coin),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount", melt->amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee", melt->melt_fee),
    TALER_PQ_RESULT_SPEC_END
  };

  result = TALER_PQ_exec_prepared (session->conn,
                                   "get_refresh_melt",
                                   params);
  if (0 == PQntuples (result))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }
  if (1 != PQntuples (result))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
#endif
  melt->session_hash = *session_hash;

  GNUNET_break (0);
  return GNUNET_SYSERR;
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
  // FIXME: check logic: was written for just one COIN!
  uint16_t newcoin_index_nbo = htons (num_newcoins);
  PGresult *result;

  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR (&newcoin_index_nbo),
      TALER_PQ_QUERY_PARAM_PTR (session_hash),
      TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY (denom_pubs->rsa_public_key),
      TALER_PQ_QUERY_PARAM_END
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
  return GNUNET_OK;
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
  // FIXME: check logic -- was written for just one coin!
  uint16_t newcoin_index_nbo = htons (num_newcoins);

  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_PQ_QUERY_PARAM_END
  };

  PGresult *result = TALER_PQ_exec_prepared (session->conn,
                                             "get_refresh_order", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    /* FIXME: may want to distinguish between different error cases! */
    return GNUNET_SYSERR;
  }
  GNUNET_assert (1 == PQntuples (result));
  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_RSA_PUBLIC_KEY ("denom_pub", &denom_pubs->rsa_public_key),
    TALER_PQ_RESULT_SPEC_END
  };
  if (GNUNET_OK != TALER_PQ_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  return GNUNET_OK;
}



/**
 * Store information about the commitment of the
 * given coin for the given refresh session in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param i set index (1st dimension)
 * @param num_newcoins coin index size of the @a commit_coins array
 * @param commit_coins array of coin commitments to store
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on error
 */
static int
postgres_insert_refresh_commit_coins (void *cls,
                                      struct TALER_MINTDB_Session *session,
                                      const struct GNUNET_HashCode *session_hash,
                                      unsigned int i,
                                      unsigned int num_newcoins,
                                      const struct TALER_MINTDB_RefreshCommitCoin *commit_coins)
{
  // FIXME: check logic! -- was written for single commit_coin!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t newcoin_index_nbo = htons (num_newcoins);
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_PTR_SIZED(commit_coins->coin_ev, commit_coins->coin_ev_size),
    TALER_PQ_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_PQ_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_PQ_QUERY_PARAM_PTR_SIZED (commit_coins->refresh_link->coin_priv_enc,
                                    commit_coins->refresh_link->blinding_key_enc_size +
                                    sizeof (union TALER_CoinSpendPrivateKeyP)),
    TALER_PQ_QUERY_PARAM_END
  };

  PGresult *result = TALER_PQ_exec_prepared (session->conn,
                                             "insert_refresh_commit_coin",
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
 * Obtain information about the commitment of the
 * given coin of the given refresh session from the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param cnc_index set index (1st dimension)
 * @param newcoin_index coin index (2nd dimension), corresponds to refreshed (new) coins
 * @param[out] cc coin commitment to return
 * @return #GNUNET_OK on success
 *         #GNUNET_NO if not found
 *         #GNUNET_SYSERR on error
 */
static int
postgres_get_refresh_commit_coins (void *cls,
                                   struct TALER_MINTDB_Session *session,
                                   const struct GNUNET_HashCode *session_hash,
                                   unsigned int cnc_index,
                                   unsigned int newcoin_index,
                                   struct TALER_MINTDB_RefreshCommitCoin *cc)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_PQ_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_PQ_QUERY_PARAM_END
  };
  void *c_buf;
  size_t c_buf_size;
  void *rl_buf;
  size_t rl_buf_size;
  struct TALER_RefreshLinkEncrypted *rl;

  PGresult *result = TALER_PQ_exec_prepared (session->conn,
                                             "get_refresh_commit_coin",
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

  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_VAR("coin_ev", &c_buf, &c_buf_size),
    TALER_PQ_RESULT_SPEC_VAR("link_vector_enc", &rl_buf, &rl_buf_size),
    TALER_PQ_RESULT_SPEC_END
  };
  if (GNUNET_YES != TALER_PQ_extract_result (result, rs, 0))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  if (rl_buf_size < sizeof (union TALER_CoinSpendPrivateKeyP))
  {
    GNUNET_free (c_buf);
    GNUNET_free (rl_buf);
    return GNUNET_SYSERR;
  }
  rl = TALER_refresh_link_encrypted_decode (rl_buf,
                                            rl_buf_size);
  GNUNET_free (rl_buf);
  cc->refresh_link = rl;
  cc->coin_ev = c_buf;
  cc->coin_ev_size = c_buf_size;
  return GNUNET_YES;
}


/**
 * Store the commitment to the given (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to melted (old) coins
 * @param commit_link link information to store
 * @return #GNUNET_SYSERR on internal error, #GNUNET_OK on success
 */
static int
postgres_insert_refresh_commit_links (void *cls,
                                      struct TALER_MINTDB_Session *session,
                                      const struct GNUNET_HashCode *session_hash,
                                      unsigned int i,
                                      unsigned int j,
                                      const struct TALER_MINTDB_RefreshCommitLinkP *commit_link)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t oldcoin_index_nbo = htons (j);
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_PTR(&commit_link->transfer_pub),
    TALER_PQ_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_PQ_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_PQ_QUERY_PARAM_PTR(&commit_link->shared_secret_enc),
    TALER_PQ_QUERY_PARAM_END
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
  return GNUNET_OK;
}


/**
 * Obtain the commited (encrypted) refresh link data
 * for the given refresh session.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param session_hash hash to identify refresh session
 * @param i set index (1st dimension)
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
                                   unsigned int i,
                                   unsigned int num_links,
                                   struct TALER_MINTDB_RefreshCommitLinkP *links)
{
  // FIXME: check logic: was written for a single link!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t oldcoin_index_nbo = htons (num_links);

  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(session_hash),
    TALER_PQ_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_PQ_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_PQ_QUERY_PARAM_END
  };

  PGresult *result = TALER_PQ_exec_prepared (session->conn,
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

  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC("transfer_pub", &links->transfer_pub),
    TALER_PQ_RESULT_SPEC("link_secret_enc", &links->shared_secret_enc),
    TALER_PQ_RESULT_SPEC_END
  };

  if (GNUNET_YES != TALER_PQ_extract_result (result, rs, 0))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }

  PQclear (result);
  return GNUNET_OK;
}


/**
 * Get all of the information from the given melt commit operation.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param sesssion database connection to use
 * @param session_hash hash to identify refresh session
 * @return NULL if the @a session_hash does not correspond to any known melt
 *         operation
 */
static struct TALER_MINTDB_MeltCommitment *
postgres_get_melt_commitment (void *cls,
                              struct TALER_MINTDB_Session *sesssion,
                              const struct GNUNET_HashCode *session_hash)
{
  // FIXME: needs to be implemented!
#if 0
  struct TALER_MINTDB_MeltCommitment *mc;
  unsigned int k;
  unsigned int i;

  mc = GNUNET_new (struct TALER_MINTDB_MeltCommitment);
  mc->num_newcoins = ;
  mc->num_oldcoins = ;
  mc->denom_pubs = GNUNET_malloc (mc->num_newcoins *
                                  sizeof (struct TALER_DenominationPublicKey));
  mc->melts = GNUNET_malloc (mc->num_oldcoins *
                             sizeof (struct TALER_MINTDB_RefreshMelt));
  for (k=0;k<TALER_CNC_KAPPA;k++)
  {
    mc->commit_coins[k] = GNUNET_malloc (mc->num_newcoins *
                                         sizeof (struct TALER_MINTDB_RefreshCommitCoin));
    for (i=0;i<mc->num_newcoins;i++)
    {
      mc->commit_coins[k][i].refresh_link = ; // malloc...
      mc->commit_coins[k][i].coin_ev = ; // malloc...
    }
    mc->commit_links[k] = GNUNET_malloc (mc->num_oldcoins *
                                         sizeof (struct TALER_MINTDB_RefreshCommitLinkP));
  }

  return mc;
#endif
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
postgres_insert_refresh_collectable (void *cls,
                                     struct TALER_MINTDB_Session *session,
                                     const struct GNUNET_HashCode *session_hash,
                                     uint16_t newcoin_index,
                                     const struct TALER_DenominationSignature *ev_sig)
{
  // FIXME: check logic!
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  PGresult *result;

  {
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR(session_hash),
      TALER_PQ_QUERY_PARAM_PTR(&newcoin_index_nbo),
      TALER_PQ_QUERY_PARAM_RSA_SIGNATURE(ev_sig->rsa_signature),
      TALER_PQ_QUERY_PARAM_END
    };
    result = TALER_PQ_exec_prepared (session->conn,
                                     "insert_refresh_collectable",
                                     params);
  }
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
 * @param coin_pub public key to use to retrieve linkage data
 * @return all known link data for the coin
 */
static struct TALER_MINTDB_LinkDataList *
postgres_get_link_data_list (void *cls,
                             struct TALER_MINTDB_Session *session,
                             const union TALER_CoinSpendPublicKeyP *coin_pub)
{
  // FIXME: check logic!
  struct TALER_MINTDB_LinkDataList *ldl;
  struct TALER_MINTDB_LinkDataList *pos;
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(coin_pub),
    TALER_PQ_QUERY_PARAM_END
  };
  PGresult *result = TALER_PQ_exec_prepared (session->conn, "get_link", params);

  ldl = NULL;
  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return NULL;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    return NULL;
  }

  int i = 0;
  for (i = 0; i < PQntuples (result); i++)
  {
    struct TALER_RefreshLinkEncrypted *link_enc;
    struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
    struct GNUNET_CRYPTO_rsa_Signature *sig;
    void *ld_buf;
    size_t ld_buf_size;
    struct TALER_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_VAR("link_vector_enc", &ld_buf, &ld_buf_size),
      TALER_PQ_RESULT_SPEC_RSA_PUBLIC_KEY("denom_pub", &denom_pub),
      TALER_PQ_RESULT_SPEC_RSA_SIGNATURE("ev_sig", &sig),
      TALER_PQ_RESULT_SPEC_END
    };

    if (GNUNET_OK != TALER_PQ_extract_result (result, rs, i))
    {
      PQclear (result);
      GNUNET_break (0);
      common_free_link_data_list (cls,
                                  ldl);
      return NULL;
    }
    if (ld_buf_size < sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey))
    {
      PQclear (result);
      GNUNET_free (ld_buf);
      common_free_link_data_list (cls,
                                  ldl);
      return NULL;
    }
    // FIXME: use util API for this!
    link_enc = GNUNET_malloc (sizeof (struct TALER_RefreshLinkEncrypted) +
                              ld_buf_size - sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey));
    link_enc->blinding_key_enc = (const char *) &link_enc[1];
    link_enc->blinding_key_enc_size = ld_buf_size - sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey);
    memcpy (link_enc->coin_priv_enc,
            ld_buf,
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
 * @param[out] transfer_pub public transfer key
 * @param[out] shared_secret_enc set to shared secret
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO on failure (not found)
 *         #GNUNET_SYSERR on internal failure (database issue)
 */
static int
postgres_get_transfer (void *cls,
                       struct TALER_MINTDB_Session *session,
                       const union TALER_CoinSpendPublicKeyP *coin_pub,
                       struct TALER_TransferPublicKeyP *transfer_pub,
                       struct TALER_EncryptedLinkSecretP *shared_secret_enc)
{
  // FIXME: check logic!
  struct TALER_PQ_QueryParam params[] = {
    TALER_PQ_QUERY_PARAM_PTR(coin_pub),
    TALER_PQ_QUERY_PARAM_END
  };

  PGresult *result = TALER_PQ_exec_prepared (session->conn, "get_transfer", params);

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

  if (1 != PQntuples (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "got %d tuples for get_transfer\n",
                PQntuples (result));
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  struct TALER_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC("transfer_pub", transfer_pub),
    TALER_PQ_RESULT_SPEC("link_secret_enc", shared_secret_enc),
    TALER_PQ_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_PQ_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return GNUNET_SYSERR;
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
                                const union TALER_CoinSpendPublicKeyP *coin_pub)
{
  PGresult *result;
  struct TALER_MINTDB_TransactionList *head;
  struct TALER_MINTDB_TransactionList *tl;
  int nrows;
  int ret;

  result = NULL;
  head = NULL;
  tl = NULL;
  nrows = 0;
  ret = GNUNET_SYSERR;

  /* check deposits */
  {
    struct TALER_MINTDB_Deposit *deposit;
    struct TALER_PQ_QueryParam params[] = {
      TALER_PQ_QUERY_PARAM_PTR (&coin_pub->ecdsa_pub),
      TALER_PQ_QUERY_PARAM_END
    };
    json_error_t json_error;
    void *json_wire_enc;
    size_t json_wire_enc_size;
    int i;
    result = TALER_PQ_exec_prepared (session->conn,
                                     "get_deposit_with_coin_pub",
                                     params);
    if (PGRES_TUPLES_OK != PQresultStatus (result))
    {
      QUERY_ERR (result);
      goto cleanup;
    }
    nrows = PQntuples (result);
    for (i=0; i < nrows; i++)
    {
      deposit = GNUNET_new (struct TALER_MINTDB_Deposit);
      struct TALER_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC ("coin_pub", &deposit->coin),
        TALER_PQ_RESULT_SPEC ("coin_sig", &deposit->csig),
        TALER_PQ_RESULT_SPEC ("merchant_pub", &deposit->merchant_pub),
        TALER_PQ_RESULT_SPEC ("h_contract", &deposit->h_contract),
        TALER_PQ_RESULT_SPEC ("h_wire", &deposit->h_wire),
        TALER_PQ_RESULT_SPEC_VAR ("wire", &json_wire_enc, &json_wire_enc_size),
        TALER_PQ_RESULT_SPEC ("transaction_id", &deposit->transaction_id),
        /**  FIXME:
         * TALER_PQ_RESULT_SPEC ("timestamp", &deposit->timestamp),
         * TALER_PQ_RESULT_SPEC ("refund_deadline", &deposit->refund_deadline),
         * TALER_PQ_RESULT_AMOUNT_NBO ("deposit_fee", &deposit->deposit_fee)
         */
        TALER_PQ_RESULT_SPEC_END
      };
      if ((GNUNET_OK != TALER_PQ_extract_result (result, rs, i)) ||
	  (GNUNET_OK != TALER_PQ_extract_amount (result,
						 i,
						 "amount_val",
						 "amount_frac",
						 "amount_curr",
						 &deposit->amount_with_fee)))
      {
        GNUNET_break (0);
        goto cleanup_deposit;
      }
      deposit->wire = json_loads (json_wire_enc,
                                  JSON_REJECT_DUPLICATES,
                                  &json_error);
      if (NULL == deposit->wire)
      {
        TALER_json_warn (json_error);
        goto cleanup_deposit;
      }
      GNUNET_free (json_wire_enc);
      json_wire_enc = NULL;
      deposit->transaction_id = GNUNET_ntohll (deposit->transaction_id);
      tl = GNUNET_new (struct TALER_MINTDB_TransactionList);
      tl->type = TALER_MINTDB_TT_DEPOSIT;
      tl->details.deposit = deposit;
      deposit = NULL;
      continue;
    cleanup_deposit:
      GNUNET_free_non_null (json_wire_enc);
      GNUNET_free_non_null (deposit);
      goto cleanup;
    }
  }
  // FIXME: check logic!
  /* We need to get this information from 3 tables:
   1. Deposits
   2. Coins used in for refreshing
   3. locked coins (locking is not implemented as of now) */
 cleanup:
  if (GNUNET_OK == ret)
    return head;
  if (NULL != head)
    common_free_coin_transaction_list (cls, head);
  return NULL;
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
  /* FIXME: use configuration section with "postgres" in its name... */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint", "db_conn_str",
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
  plugin->insert_denomination = &postgres_insert_denomination;
  plugin->reserve_get = &postgres_reserve_get;
  plugin->reserves_in_insert = &postgres_reserves_in_insert;
  plugin->get_collectable_blindcoin = &postgres_get_collectable_blindcoin;
  plugin->insert_collectable_blindcoin = &postgres_insert_collectable_blindcoin;
  plugin->get_reserve_history = &postgres_get_reserve_history;
  plugin->free_reserve_history = &common_free_reserve_history;
  plugin->have_deposit = &postgres_have_deposit;
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
  plugin->insert_refresh_collectable = &postgres_insert_refresh_collectable;
  plugin->get_link_data_list = &postgres_get_link_data_list;
  plugin->free_link_data_list = &common_free_link_data_list;
  plugin->get_transfer = &postgres_get_transfer;
  // plugin->have_lock = &postgres_have_lock;
  // plugin->insert_lock = &postgres_insert_lock;
  plugin->get_coin_transactions = &postgres_get_coin_transactions;
  plugin->free_coin_transaction_list = &common_free_coin_transaction_list;
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
