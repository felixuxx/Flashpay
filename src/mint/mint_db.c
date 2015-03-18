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
 * @file mint_db.c
 * @brief Low-level (statement-level) database access for the mint
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 *
 * TODO:
 * - The mint_db.h-API should ideally be what we need to port
 *   when using other databases; so here we should enable
 *   alternative implementations by returning
 *   a more opaque DB handle.
 */
#include "platform.h"
#include "db_pq.h"
#include "taler_signatures.h"
#include "taler-mint-httpd_responses.h"
#include "mint_db.h"
#include <pthread.h>


/**
 * Thread-local database connection.
 * Contains a pointer to PGconn or NULL.
 */
static pthread_key_t db_conn_threadlocal;


#define QUERY_ERR(result)                          \
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Query failed at %s:%u: %s\n", __FILE__, __LINE__, PQresultErrorMessage (result))

/**
 * Database connection string, as read from
 * the configuration.
 */
static char *TALER_MINT_db_connection_cfg_str;

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
 * This the length of the currency strings (without 0-termination) we use.  Note
 * that we need to use this at the DB layer instead of TALER_CURRENCY_LEN as the
 * DB only needs to store 3 bytes instead of 8 bytes.
 */
#define TALER_DB_CURRENCY_LEN 3

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
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_DB_drop_temporary (PGconn *db)
{
  PGresult *result;

  SQLEXEC_ (db,
            "DROP SCHEMA " TALER_TEMP_SCHEMA_NAME " CASCADE;",
            result);
  return GNUNET_OK;
 SQLEXEC_fail:
  return GNUNET_SYSERR;
}


/**
 * Create the necessary tables if they are not present
 *
 * @param temporary should we use a temporary schema
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_DB_create_tables (int temporary)
{
  PGresult *result;
  PGconn *conn;

  result = NULL;
  conn = PQconnectdb (TALER_MINT_db_connection_cfg_str);
  if (CONNECTION_OK != PQstatus (conn))
  {
    LOG_ERROR ("Database connection failed: %s\n",
               PQerrorMessage (conn));
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if ((GNUNET_YES == temporary)
      && (GNUNET_SYSERR == set_temporary_schema (conn)))
  {
    PQfinish (conn);
    return GNUNET_SYSERR;
  }
#define SQLEXEC(sql) SQLEXEC_(conn, sql, result);
  /* reserves table is for summarization of a reserve.  It is updated when new
     funds are added and existing funds are withdrawn */
  SQLEXEC ("CREATE TABLE IF NOT EXISTS reserves"
           "("
           " reserve_pub BYTEA PRIMARY KEY"
           ",current_balance_value INT4 NOT NULL"
           ",current_balance_fraction INT4 NOT NULL"
           ",balance_currency VARCHAR(4) NOT NULL"
           ",expiration_date INT8 NOT NULL"
           ")");
  /* reserves_in table collects the transactions which transfer funds into the
     reserve.  The amount and expiration date for the corresponding reserve are
     updated when new transfer funds are added.  The rows of this table
     correspond to each incoming transaction. */
  SQLEXEC("CREATE TABLE IF NOT EXISTS reserves_in"
          "("
          " reserve_pub BYTEA REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
          ",balance_value INT4 NOT NULL"
          ",balance_fraction INT4 NOT NULL"
          ",balance_currency VARCHAR(4) NOT NULL"
          ",expiration_date INT8 NOT NULL"
          ");");
  /* Create an index on the foreign key as it is not created automatically by PSQL */
  SQLEXEC ("CREATE INDEX reserves_in_reserve_pub_index"
           " ON reserves_in (reserve_pub);");
  SQLEXEC ("CREATE TABLE IF NOT EXISTS collectable_blindcoins"
           "("
           "blind_ev BYTEA PRIMARY KEY"
           ",denom_pub BYTEA NOT NULL" /* FIXME: Make this a foreign key? */
           ",denom_sig BYTEA NOT NULL"
           ",reserve_pub BYTEA REFERENCES reserves (reserve_pub) ON DELETE CASCADE"
           ",reserve_sig BYTEA NOT NULL"
           ");");
  SQLEXEC ("CREATE INDEX collectable_blindcoins_reserve_pub_index ON"
           " collectable_blindcoins (reserve_pub)");
  SQLEXEC("CREATE TABLE IF NOT EXISTS known_coins "
          "("
          " coin_pub BYTEA NOT NULL PRIMARY KEY"
          ",denom_pub BYTEA NOT NULL"
          ",denom_sig BYTEA NOT NULL"
          ",expended_value INT4 NOT NULL"
          ",expended_fraction INT4 NOT NULL"
          ",expended_currency VARCHAR(4) NOT NULL"
          ",refresh_session_pub BYTEA"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_sessions "
          "("
          " session_pub BYTEA PRIMARY KEY CHECK (length(session_pub) = 32)"
          ",session_melt_sig BYTEA"
          ",session_commit_sig BYTEA"
          ",noreveal_index INT2 NOT NULL"
          // non-zero if all reveals were ok
          // and the new coin signatures are ready
          ",reveal_ok BOOLEAN NOT NULL DEFAULT false"
          ") ");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_order "
          "( "
          " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub)"
          ",newcoin_index INT2 NOT NULL "
          ",denom_pub BYTEA NOT NULL "
          ",PRIMARY KEY (session_pub, newcoin_index)"
          ") ");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_link"
          "("
          " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub)"
          ",transfer_pub BYTEA NOT NULL"
          ",link_secret_enc BYTEA NOT NULL"
          // index of the old coin in the customer's request
          ",oldcoin_index INT2 NOT NULL"
          // index for cut and choose,
          // ranges from 0 to kappa-1
          ",cnc_index INT2 NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_commit_coin"
          "("
          " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub) "
          ",link_vector_enc BYTEA NOT NULL"
          // index of the new coin in the customer's request
          ",newcoin_index INT2 NOT NULL"
          // index for cut and choose,
          ",cnc_index INT2 NOT NULL"
          ",coin_ev BYTEA NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_melt"
          "("
          " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub) "
          ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) "
          ",denom_pub BYTEA NOT NULL "
          ",oldcoin_index INT2 NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS refresh_collectable"
          "("
          " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub) "
          ",ev_sig BYTEA NOT NULL"
          ",newcoin_index INT2 NOT NULL"
          ")");
  SQLEXEC("CREATE TABLE IF NOT EXISTS deposits "
          "( "
          " coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (length(coin_pub)=32)"
          ",denom_pub BYTEA NOT NULL" /* FIXME: Link this as a foreign key? */
          ",denom_sig BYTEA NOT NULL"
          ",transaction_id INT8 NOT NULL"
          ",amount_currency VARCHAR(4) NOT NULL"
          ",amount_value INT4 NOT NULL"
          ",amount_fraction INT4 NOT NULL"
          ",merchant_pub BYTEA NOT NULL CHECK (length(merchant_pub)=32)"
          ",h_contract BYTEA NOT NULL CHECK (length(h_contract)=64)"
          ",h_wire BYTEA NOT NULL CHECK (length(h_wire)=64)"
          ",coin_sig BYTEA NOT NULL CHECK (length(coin_sig)=64)"
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
int
TALER_MINT_DB_prepare (PGconn *db_conn)
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

  PREPARE ("get_reserve",
           "SELECT "
           "current_balance_value"
           ",current_balance_fraction"
           ",balance_currency "
           ",expiration_date "
           "FROM reserves "
           "WHERE reserve_pub=$1 "
           "LIMIT 1; ",
           1, NULL);
  PREPARE ("create_reserve",
           "INSERT INTO reserves ("
           " reserve_pub,"
           " current_balance_value,"
           " current_balance_fraction,"
           " balance_currency,"
           " expiration_date) VALUES ("
           "$1, $2, $3, $4, $5);",
           5, NULL);
  PREPARE ("update_reserve",
           "UPDATE reserves "
           "SET"
           " current_balance_value=$2 "
           ",current_balance_fraction=$3 "
           ",expiration_date=$4 "
           "WHERE reserve_pub=$1 ",
           4, NULL);
  PREPARE ("create_reserves_in_transaction",
           "INSERT INTO reserves_in ("
           " reserve_pub,"
           " balance_value,"
           " balance_fraction,"
           " balance_currency,"
           " expiration_date) VALUES ("
           " $1, $2, $3, $4, $5);",
           5, NULL);
  PREPARE ("get_reserves_in_transactions",
           "SELECT"
           " balance_value"
           ",balance_fraction"
           ",balance_currency"
           ",expiration_date"
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
           "WHERE blind_ev = $1",
           1, NULL);
  PREPARE ("get_reserves_blindcoins",
           "select"
           " blind_ev"
           ",denom_pub, denom_sig"
           ",reserve_sig"
           " FROM collectable_blindcoins"
           " WHERE reserve_pub=$1;",
           1, NULL);

  /* FIXME: does it make sense to store these computed values in the DB? */
#if 0
  PREPARE ("get_refresh_session",
           "SELECT "
           " (SELECT count(*) FROM refresh_melt WHERE session_pub = $1)::INT2 as num_oldcoins "
           ",(SELECT count(*) FROM refresh_blind_session_keys "
           "  WHERE session_pub = $1 and cnc_index = 0)::INT2 as num_newcoins "
           ",(SELECT count(*) FROM refresh_blind_session_keys "
           "  WHERE session_pub = $1 and newcoin_index = 0)::INT2 as kappa "
           ",noreveal_index"
           ",session_commit_sig "
           ",reveal_ok "
           "FROM refresh_sessions "
           "WHERE session_pub = $1",
           1, NULL);
#endif

  PREPARE ("get_known_coin",
           "SELECT "
           " coin_pub, denom_pub, denom_sig "
           ",expended_value, expended_fraction, expended_currency "
           ",refresh_session_pub "
           "FROM known_coins "
           "WHERE coin_pub = $1",
           1, NULL);
  PREPARE ("update_known_coin",
           "UPDATE known_coins "
           "SET "
           " denom_pub = $2 "
           ",denom_sig = $3 "
           ",expended_value = $4 "
           ",expended_fraction = $5 "
           ",expended_currency = $6 "
           ",refresh_session_pub = $7 "
           "WHERE "
           " coin_pub = $1 ",
           7, NULL);
  PREPARE ("insert_known_coin",
           "INSERT INTO known_coins ("
           " coin_pub"
           ",denom_pub"
           ",denom_sig"
           ",expended_value"
           ",expended_fraction"
           ",expended_currency"
           ",refresh_session_pub"
           ")"
           "VALUES ($1,$2,$3,$4,$5,$6,$7)",
           7, NULL);
  PREPARE ("get_refresh_commit_link",
           "SELECT "
           " transfer_pub "
           ",link_secret_enc "
           "FROM refresh_commit_link "
           "WHERE session_pub = $1 AND cnc_index = $2 AND oldcoin_index = $3",
           3, NULL);
  PREPARE ("get_refresh_commit_coin",
           "SELECT "
           " link_vector_enc "
           ",coin_ev "
           "FROM refresh_commit_coin "
           "WHERE session_pub = $1 AND cnc_index = $2 AND newcoin_index = $3",
           3, NULL);
  PREPARE ("insert_refresh_order",
           "INSERT INTO refresh_order ( "
           " newcoin_index "
           ",session_pub "
           ",denom_pub "
           ") "
           "VALUES ($1, $2, $3) ",
           3, NULL);
  PREPARE ("insert_refresh_melt",
           "INSERT INTO refresh_melt ( "
           " session_pub "
           ",oldcoin_index "
           ",coin_pub "
           ",denom_pub "
           ") "
           "VALUES ($1, $2, $3, $4) ",
           3, NULL);
  PREPARE ("get_refresh_order",
           "SELECT denom_pub "
           "FROM refresh_order "
           "WHERE session_pub = $1 AND newcoin_index = $2",
           2, NULL);
  PREPARE ("get_refresh_collectable",
           "SELECT ev_sig "
           "FROM refresh_collectable "
           "WHERE session_pub = $1 AND newcoin_index = $2",
           2, NULL);
  PREPARE ("get_refresh_melt",
           "SELECT coin_pub "
           "FROM refresh_melt "
           "WHERE session_pub = $1 AND oldcoin_index = $2",
           2, NULL);
  PREPARE ("insert_refresh_session",
           "INSERT INTO refresh_sessions ( "
           " session_pub "
           ",noreveal_index "
           ") "
           "VALUES ($1, $2) ",
           2, NULL);
  PREPARE ("insert_refresh_commit_link",
           "INSERT INTO refresh_commit_link ( "
           " session_pub "
           ",transfer_pub "
           ",cnc_index "
           ",oldcoin_index "
           ",link_secret_enc "
           ") "
           "VALUES ($1, $2, $3, $4, $5) ",
           5, NULL);
  PREPARE ("insert_refresh_commit_coin",
           "INSERT INTO refresh_commit_coin ( "
           " session_pub "
           ",coin_ev "
           ",cnc_index "
           ",newcoin_index "
           ",link_vector_enc "
           ") "
           "VALUES ($1, $2, $3, $4, $5) ",
           5, NULL);
  PREPARE ("insert_refresh_collectable",
           "INSERT INTO refresh_collectable ( "
           " session_pub "
           ",newcoin_index "
           ",ev_sig "
           ") "
           "VALUES ($1, $2, $3) ",
           3, NULL);
  PREPARE ("set_reveal_ok",
           "UPDATE refresh_sessions "
           "SET reveal_ok = TRUE "
           "WHERE session_pub = $1 ",
           1, NULL);
  PREPARE ("get_link",
           "SELECT link_vector_enc, ro.denom_pub, ev_sig "
           "FROM refresh_melt rm "
           "     JOIN refresh_order ro USING (session_pub) "
           "     JOIN refresh_commit_coin rcc USING (session_pub) "
           "     JOIN refresh_sessions rs USING (session_pub) "
           "     JOIN refresh_collectable rc USING (session_pub) "
           "WHERE rm.coin_pub = $1 "
           "AND ro.newcoin_index = rcc.newcoin_index "
           "AND ro.newcoin_index = rc.newcoin_index "
           "AND  rcc.cnc_index = rs.noreveal_index % ( "
           "         SELECT count(*) FROM refresh_commit_coin rcc2 "
           "         WHERE rcc2.newcoin_index = 0 AND rcc2.session_pub = rs.session_pub "
           "     ) ",
           1, NULL);
  PREPARE ("get_transfer",
           "SELECT transfer_pub, link_secret_enc "
           "FROM refresh_melt rm "
           "     JOIN refresh_commit_link rcl USING (session_pub) "
           "     JOIN refresh_sessions rs USING (session_pub) "
           "WHERE rm.coin_pub = $1 "
           "AND  rm.oldcoin_index = rcl.oldcoin_index "
           "AND  rcl.cnc_index = rs.noreveal_index % ( "
           "         SELECT count(*) FROM refresh_commit_coin rcc2 "
           "         WHERE newcoin_index = 0 AND rcc2.session_pub = rm.session_pub "
           "     ) ",
           1, NULL);
  PREPARE ("insert_deposit",
           "INSERT INTO deposits ("
           "coin_pub,"
           "denom_pub,"
           "denom_sig,"
           "transaction_id,"
           "amount_value,"
           "amount_fraction,"
           "amount_currency,"
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
           "amount_value,"
           "amount_fraction,"
           "amount_currency,"
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
  return GNUNET_OK;
#undef PREPARE
}


/**
 * Close thread-local database connection when a thread is destroyed.
 *
 * @param closure we get from pthreads (the db handle)
 */
static void
db_conn_destroy (void *cls)
{
  PGconn *db_conn = cls;

  if (NULL != db_conn)
    PQfinish (db_conn);
}


/**
 * Initialize database subsystem.
 *
 * @param connection_cfg configuration to use to talk to DB
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_init (const char *connection_cfg)
{
  if (0 != pthread_key_create (&db_conn_threadlocal,
                               &db_conn_destroy))
  {
    LOG_ERROR ("Cannnot create pthread key.\n");
    return GNUNET_SYSERR;
  }
  TALER_MINT_db_connection_cfg_str = GNUNET_strdup (connection_cfg);
  return GNUNET_OK;
}


/**
 * Get the thread-local database-handle.
 * Connect to the db if the connection does not exist yet.
 *
 * @param temporary #GNUNET_YES to use a temporary schema; #GNUNET_NO to use the
 *        database default one
 * @return the database connection, or NULL on error
 */
PGconn *
TALER_MINT_DB_get_connection (int temporary)
{
  PGconn *db_conn;

  if (NULL != (db_conn = pthread_getspecific (db_conn_threadlocal)))
    return db_conn;
  db_conn = PQconnectdb (TALER_MINT_db_connection_cfg_str);
  if (CONNECTION_OK !=
      PQstatus (db_conn))
  {
    LOG_ERROR ("Database connection failed: %s\n",
               PQerrorMessage (db_conn));
    GNUNET_break (0);
    return NULL;
  }
  if ((GNUNET_YES == temporary)
      && (GNUNET_SYSERR == set_temporary_schema(db_conn)))
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_OK !=
      TALER_MINT_DB_prepare (db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  if (0 != pthread_setspecific (db_conn_threadlocal,
                                db_conn))
  {
    GNUNET_break (0);
    return NULL;
  }
  return db_conn;
}


/**
 * Start a transaction.
 *
 * @param db_conn the database connection
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_transaction (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec (db_conn,
                   "BEGIN");
  if (PGRES_COMMAND_OK !=
      PQresultStatus (result))
  {
    LOG_ERROR ("Failed to start transaction: %s\n",
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
 * @param db_conn the database connection
 * @return #GNUNET_OK on success
 */
void
TALER_MINT_DB_rollback (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec (db_conn,
                   "ROLLBACK");
  GNUNET_break (PGRES_COMMAND_OK ==
                PQresultStatus (result));
  PQclear (result);
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param db_conn the database connection
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_commit (PGconn *db_conn)
{
  PGresult *result;

  result = PQexec (db_conn,
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
 * Get the summary of a reserve.
 *
 * @param db the database connection handle
 * @param reserve the reserve data.  The public key of the reserve should be set
 *          in this structure; it is used to query the database.  The balance
 *          and expiration are then filled accordingly.
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
int
TALER_MINT_DB_reserve_get (PGconn *db,
                           struct Reserve *reserve)
{
  PGresult *result;
  uint64_t expiration_date_nbo;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(reserve->pub),
    TALER_DB_QUERY_PARAM_END
  };

  if (NULL == reserve->pub)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  result = TALER_DB_exec_prepared (db,
                                   "get_reserve",
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
  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("expiration_date", &expiration_date_nbo),
    TALER_DB_RESULT_SPEC_END
  };
  EXITIF (GNUNET_OK != TALER_DB_extract_result (result, rs, 0));
  EXITIF (GNUNET_OK !=
          TALER_DB_extract_amount (result, 0,
                                   "current_balance_value",
                                   "current_balance_fraction",
                                   "balance_currency",
                                   &reserve->balance));
  reserve->expiry.abs_value_us = GNUNET_ntohll (expiration_date_nbo);
  PQclear (result);
  return GNUNET_OK;

 EXITIF_exit:
  PQclear (result);
  return GNUNET_SYSERR;
}


/**
 * Updates a reserve with the data from the given reserve structure.
 *
 * @param db the database connection
 * @param reserve the reserve structure whose data will be used to update the
 *          corresponding record in the database.
 * @return #GNUNET_OK upon successful update; #GNUNET_SYSERR upon any error
 */
int
reserves_update (PGconn *db,
                 struct Reserve *reserve)
{
  PGresult *result;
  struct TALER_AmountNBO balance_nbo;
  struct GNUNET_TIME_AbsoluteNBO expiry_nbo;
  int ret;

  if ((NULL == reserve) || (NULL == reserve->pub))
    return GNUNET_SYSERR;
  ret = GNUNET_OK;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (reserve->pub),
    TALER_DB_QUERY_PARAM_PTR (&balance_nbo.value),
    TALER_DB_QUERY_PARAM_PTR (&balance_nbo.fraction),
    TALER_DB_QUERY_PARAM_PTR (&expiry_nbo),
    TALER_DB_QUERY_PARAM_END
  };
  TALER_amount_hton (&balance_nbo,
                     &reserve->balance);
  expiry_nbo = GNUNET_TIME_absolute_hton (reserve->expiry);
  result = TALER_DB_exec_prepared (db,
                                   "update_reserve",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    QUERY_ERR (result);
    ret = GNUNET_SYSERR;
  }
  PQclear (result);
  return ret;
}


/**
 * Insert a incoming transaction into reserves.  New reserves are also created
 * through this function.
 *
 * @param db the database connection handle
 * @param reserve the reserve structure.  The public key of the reserve should
 *          be set here.  Upon successful execution of this function, the
 *          balance and expiration of the reserve will be updated.
 * @param balance the amount that has to be added to the reserve
 * @param expiry the new expiration time for the reserve
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failures
 */
int
TALER_MINT_DB_reserves_in_insert (PGconn *db,
                                  struct Reserve *reserve,
                                  const struct TALER_Amount *balance,
                                  const struct GNUNET_TIME_Absolute expiry)
{
  struct TALER_AmountNBO balance_nbo;
  struct GNUNET_TIME_AbsoluteNBO expiry_nbo;
  PGresult *result;
  int reserve_exists;

  result = NULL;
  if (NULL == reserve)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK != TALER_MINT_DB_transaction (db))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  reserve_exists = TALER_MINT_DB_reserve_get (db, reserve);
  if (GNUNET_SYSERR == reserve_exists)
  {
    TALER_MINT_DB_rollback (db);
    return GNUNET_SYSERR;
  }
  TALER_amount_hton (&balance_nbo,
                     balance);
  expiry_nbo = GNUNET_TIME_absolute_hton (expiry);
  if (GNUNET_NO == reserve_exists)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR (reserve->pub),
      TALER_DB_QUERY_PARAM_PTR (&balance_nbo.value),
      TALER_DB_QUERY_PARAM_PTR (&balance_nbo.fraction),
      TALER_DB_QUERY_PARAM_PTR_SIZED (balance_nbo.currency,
                                      TALER_DB_CURRENCY_LEN),
      TALER_DB_QUERY_PARAM_PTR (&expiry_nbo),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db,
                                     "create_reserve",
                                     params);
    if (PGRES_COMMAND_OK != PQresultStatus(result))
    {
      QUERY_ERR (result);
      goto rollback;
    }
  }
  if (NULL != result)
    PQclear (result);
  result = NULL;
  /* create new incoming transaction */
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (reserve->pub),
    TALER_DB_QUERY_PARAM_PTR (&balance_nbo.value),
    TALER_DB_QUERY_PARAM_PTR (&balance_nbo.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED (&balance_nbo.currency,
                                    TALER_DB_CURRENCY_LEN),
    TALER_DB_QUERY_PARAM_PTR (&expiry_nbo),
    TALER_DB_QUERY_PARAM_END
  };
  result = TALER_DB_exec_prepared (db,
                                   "create_reserves_in_transaction",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    QUERY_ERR (result);
    goto rollback;
  }
  PQclear (result);
  result = NULL;
  if (GNUNET_NO == reserve_exists)
  {
    if (GNUNET_OK != TALER_MINT_DB_commit (db))
      return GNUNET_SYSERR;
    reserve->balance = *balance;
    reserve->expiry = expiry;
    return GNUNET_OK;
  }
  /* Update reserve */
  struct Reserve updated_reserve;
  updated_reserve.pub = reserve->pub;

  if (GNUNET_OK !=
      TALER_amount_add (&updated_reserve.balance,
                        &reserve->balance,
                        balance))
  {
    return GNUNET_SYSERR;
  }
  updated_reserve.expiry = GNUNET_TIME_absolute_max (expiry, reserve->expiry);
  if (GNUNET_OK != reserves_update (db, &updated_reserve))
    goto rollback;
  if (GNUNET_OK != TALER_MINT_DB_commit (db))
    return GNUNET_SYSERR;
  reserve->balance = updated_reserve.balance;
  reserve->expiry = updated_reserve.expiry;
  return GNUNET_OK;

 rollback:
  PQclear (result);
  TALER_MINT_DB_rollback (db);
  return GNUNET_SYSERR;
}


/**
 * Locate the response for a /withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param db_conn database connection to use
 * @param h_blind hash of the blinded message
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
int
TALER_MINT_DB_get_collectable_blindcoin (PGconn *db_conn,
                                         const struct GNUNET_HashCode *h_blind,
                                         struct CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (h_blind),
    TALER_DB_QUERY_PARAM_END
  };
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
  struct GNUNET_CRYPTO_rsa_Signature *denom_sig;
  char *denom_pub_enc;
  char *denom_sig_enc;
  size_t denom_pub_enc_size;
  size_t denom_sig_enc_size;
  int ret;

  ret = GNUNET_SYSERR;
  denom_pub = NULL;
  denom_pub_enc = NULL;
  denom_sig_enc = NULL;
  result = TALER_DB_exec_prepared (db_conn,
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
  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC_VAR("denom_pub", &denom_pub_enc, &denom_pub_enc_size),
    TALER_DB_RESULT_SPEC_VAR("denom_sig", &denom_sig_enc, &denom_sig_enc_size),
    TALER_DB_RESULT_SPEC("reserve_sig", &collectable->reserve_sig),
    TALER_DB_RESULT_SPEC("reserve_pub", &collectable->reserve_pub),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (denom_pub_enc,
                                                   denom_pub_enc_size);
  denom_sig = GNUNET_CRYPTO_rsa_signature_decode (denom_sig_enc,
                                                  denom_sig_enc_size);
  if ((NULL == denom_pub) || (NULL == denom_sig))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  collectable->denom_pub = denom_pub;
  collectable->sig = denom_sig;
  ret = GNUNET_YES;

 cleanup:
  PQclear (result);
  GNUNET_free_non_null (denom_pub_enc);
  GNUNET_free_non_null (denom_sig_enc);
  if (GNUNET_YES != ret)
  { if (NULL != denom_pub)
      GNUNET_CRYPTO_rsa_public_key_free (denom_pub);
    if (NULL != denom_sig)
      GNUNET_CRYPTO_rsa_signature_free (denom_sig);
  }
  return ret;
}


/**
 * Store collectable bit coin under the corresponding
 * hash of the blinded message.
 *
 * @param db_conn database connection to use
 * @param h_blind hash of the blinded message
 * @param withdraw amount by which the reserve will be withdrawn with this
 *          transaction
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return #GNUNET_SYSERR on internal error
 *         #GNUNET_NO if the collectable was not found
 *         #GNUNET_YES on success
 */
int
TALER_MINT_DB_insert_collectable_blindcoin (PGconn *db_conn,
                                            const struct GNUNET_HashCode *h_blind,
                                            struct TALER_Amount withdraw,
                                            const struct CollectableBlindcoin *collectable)
{
  PGresult *result;
  struct Reserve reserve;
  char *denom_pub_enc = NULL;
  char *denom_sig_enc = NULL;
  size_t denom_pub_enc_size;
  size_t denom_sig_enc_size;
  int ret;

  ret = GNUNET_SYSERR;
  denom_pub_enc_size =
      GNUNET_CRYPTO_rsa_public_key_encode (collectable->denom_pub,
                                           &denom_pub_enc);
  denom_sig_enc_size =
      GNUNET_CRYPTO_rsa_signature_encode (collectable->sig,
                                          &denom_sig_enc);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (h_blind),
    TALER_DB_QUERY_PARAM_PTR_SIZED (denom_pub_enc, denom_pub_enc_size - 1),
    TALER_DB_QUERY_PARAM_PTR_SIZED (denom_sig_enc, denom_sig_enc_size - 1), /* DB doesn't like the trailing \0 */
    TALER_DB_QUERY_PARAM_PTR (&collectable->reserve_pub),
    TALER_DB_QUERY_PARAM_PTR (&collectable->reserve_sig),
    TALER_DB_QUERY_PARAM_END
  };
  if (GNUNET_OK != TALER_MINT_DB_transaction (db_conn))
    goto cleanup;
  result = TALER_DB_exec_prepared (db_conn,
                                   "insert_collectable_blindcoin",
                                   params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    QUERY_ERR (result);
    goto rollback;
  }
  reserve.pub = (struct GNUNET_CRYPTO_EddsaPublicKey *)
      &collectable->reserve_pub;
  if (GNUNET_OK != TALER_MINT_DB_reserve_get (db_conn,
                                              &reserve))
    goto rollback;
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&reserve.balance,
                             &reserve.balance,
                             &withdraw))
    goto rollback;
  if (GNUNET_OK != reserves_update (db_conn, &reserve))
    goto rollback;
  if (GNUNET_OK == TALER_MINT_DB_commit (db_conn))
  {
    ret = GNUNET_OK;
    goto cleanup;
  }

 rollback:
    TALER_MINT_DB_rollback(db_conn);
 cleanup:
  PQclear (result);
  GNUNET_free_non_null (denom_pub_enc);
  GNUNET_free_non_null (denom_sig_enc);
  return ret;
}


/**
 * Get all of the transaction history associated with the specified
 * reserve.
 *
 * @param db_conn connection to use
 * @param reserve_pub public key of the reserve
 * @return known transaction history (NULL if reserve is unknown)
 */
struct ReserveHistory *
TALER_MINT_DB_get_reserve_history (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub)
{
  PGresult *result;
  struct ReserveHistory *rh;
  struct ReserveHistory *rh_head;
  int rows;
  int ret;

  result = NULL;
  rh = NULL;
  rh_head = NULL;
  ret = GNUNET_SYSERR;
  {
    struct BankTransfer *bt;
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR (reserve_pub),
      TALER_DB_QUERY_PARAM_END
    };

    result = TALER_DB_exec_prepared (db_conn,
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
      bt = GNUNET_new (struct BankTransfer);
      if (GNUNET_OK != TALER_DB_extract_amount (result,
                                                --rows,
                                                "balance_value",
                                                "balance_fraction",
                                                "balance_currency",
                                                &bt->amount))
      {
        GNUNET_free (bt);
        GNUNET_break (0);
        goto cleanup;
      }
      (void) memcpy (&bt->reserve_pub, reserve_pub, sizeof (bt->reserve_pub));
      if (NULL != rh_head)
      {
        rh_head->next = GNUNET_new (struct ReserveHistory);
        rh_head = rh_head->next;
      }
      else
      {
        rh_head = GNUNET_new (struct ReserveHistory);
        rh = rh_head;
      }
      rh_head->type = TALER_MINT_DB_RO_BANK_TO_MINT;
      rh_head->details.bank = bt;
    }
  }
  PQclear (result);
  result = NULL;
  {
    struct GNUNET_HashCode blind_ev;
    struct GNUNET_CRYPTO_EddsaSignature reserve_sig;
    struct CollectableBlindcoin *cbc;
    char *denom_pub_enc;
    char *denom_sig_enc;
    size_t denom_pub_enc_size;
    size_t denom_sig_enc_size;

    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR (reserve_pub),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn,
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
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC ("blind_ev", &blind_ev),
      TALER_DB_RESULT_SPEC_VAR ("denom_pub", &denom_pub_enc, &denom_pub_enc_size),
      TALER_DB_RESULT_SPEC_VAR ("denom_sig", &denom_sig_enc, &denom_sig_enc_size),
      TALER_DB_RESULT_SPEC ("reserve_sig", &reserve_sig),
      TALER_DB_RESULT_SPEC_END
    };
    GNUNET_assert (NULL != rh);
    GNUNET_assert (NULL != rh_head);
    GNUNET_assert (NULL == rh_head->next);
    while (0 < rows)
    {
      if (GNUNET_YES != TALER_DB_extract_result (result, rs, --rows))
      {
        GNUNET_break (0);
        goto cleanup;
      }
      cbc = GNUNET_new (struct CollectableBlindcoin);
      cbc->sig = GNUNET_CRYPTO_rsa_signature_decode (denom_sig_enc,
                                                    denom_sig_enc_size);
      GNUNET_free (denom_sig_enc);
      denom_sig_enc = NULL;
      cbc->denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (denom_pub_enc,
                                                            denom_pub_enc_size);
      GNUNET_free (denom_pub_enc);
      denom_pub_enc = NULL;
      if ((NULL == cbc->sig) || (NULL == cbc->denom_pub))
      {
        if (NULL != cbc->sig)
          GNUNET_CRYPTO_rsa_signature_free (cbc->sig);
        if (NULL != cbc->denom_pub)
          GNUNET_CRYPTO_rsa_public_key_free (cbc->denom_pub);
        GNUNET_free (cbc);
        GNUNET_break (0);
        goto cleanup;
      }
      (void) memcpy (&cbc->h_coin_envelope, &blind_ev, sizeof (blind_ev));
      (void) memcpy (&cbc->reserve_pub, reserve_pub, sizeof (cbc->reserve_pub));
      (void) memcpy (&cbc->reserve_sig, &reserve_sig, sizeof (cbc->reserve_sig));
      rh_head->next = GNUNET_new (struct ReserveHistory);
      rh_head = rh_head->next;
      rh_head->type = TALER_MINT_DB_RO_WITHDRAW_COIN;
      rh_head->details.withdraw = cbc;
    }
  }
  ret = GNUNET_OK;

 cleanup:
  if (NULL != result)
    PQclear (result);
  if (GNUNET_SYSERR == ret)
  {
    TALER_MINT_DB_free_reserve_history (rh);
    rh = NULL;
  }
  return rh;
}


/**
 * Free memory associated with the given reserve history.
 *
 * @param rh history to free.
 */
void
TALER_MINT_DB_free_reserve_history (struct ReserveHistory *rh)
{
  struct BankTransfer *bt;
  struct CollectableBlindcoin *cbc;
  struct ReserveHistory *backref;

  while (NULL != rh)
  {
    switch(rh->type)
    {
    case TALER_MINT_DB_RO_BANK_TO_MINT:
      bt = rh->details.bank;
      if (NULL != bt->wire)
        json_decref ((json_t *) bt->wire); /* FIXME: avoid cast? */
      GNUNET_free (bt);
      break;
    case TALER_MINT_DB_RO_WITHDRAW_COIN:
      cbc = rh->details.withdraw;
      GNUNET_CRYPTO_rsa_signature_free (cbc->sig);
      GNUNET_CRYPTO_rsa_public_key_free (cbc->denom_pub);
      GNUNET_free (cbc);
      break;
    }
    backref = rh;
    rh = rh->next;
    GNUNET_free (backref);
  }
}


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param db_conn database connection
 * @param deposit deposit to search for
 * @return #GNUNET_YES if we know this operation,
 *         #GNUNET_NO if this deposit is unknown to us
 */
int
TALER_MINT_DB_have_deposit (PGconn *db_conn,
                            const struct Deposit *deposit)
{
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin.coin_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->transaction_id),
    TALER_DB_QUERY_PARAM_PTR (&deposit->merchant_pub),
    TALER_DB_QUERY_PARAM_END
  };
  PGresult *result;
  int ret;

  ret = GNUNET_SYSERR;
  result = TALER_DB_exec_prepared (db_conn,
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
 * @param db_conn connection to the database
 * @param deposit deposit information to store
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_MINT_DB_insert_deposit (PGconn *db_conn,
                              const struct Deposit *deposit)
{
  char *denom_pub_enc;
  char *denom_sig_enc;
  char *json_wire_enc;
  PGresult *result;
  struct TALER_AmountNBO amount_nbo;
  size_t denom_pub_enc_size;
  size_t denom_sig_enc_size;
  int ret;

  ret = GNUNET_SYSERR;
  denom_pub_enc_size =
      GNUNET_CRYPTO_rsa_public_key_encode (deposit->coin.denom_pub,
                                           &denom_pub_enc);
  denom_sig_enc_size =
      GNUNET_CRYPTO_rsa_signature_encode (deposit->coin.denom_sig,
                                          &denom_sig_enc);
  json_wire_enc = json_dumps (deposit->wire, JSON_COMPACT);
  TALER_amount_hton (&amount_nbo,
                     &deposit->amount);
  struct TALER_DB_QueryParam params[]= {
    TALER_DB_QUERY_PARAM_PTR (&deposit->coin.coin_pub),
    TALER_DB_QUERY_PARAM_PTR_SIZED (denom_pub_enc, denom_pub_enc_size),
    TALER_DB_QUERY_PARAM_PTR_SIZED (denom_sig_enc, denom_sig_enc_size),
    TALER_DB_QUERY_PARAM_PTR (&deposit->transaction_id),
    TALER_DB_QUERY_PARAM_PTR (&amount_nbo.value),
    TALER_DB_QUERY_PARAM_PTR (&amount_nbo.fraction),
    TALER_DB_QUERY_PARAM_PTR_SIZED (amount_nbo.currency,
                                    TALER_CURRENCY_LEN - 1),
    TALER_DB_QUERY_PARAM_PTR (&deposit->merchant_pub),
    TALER_DB_QUERY_PARAM_PTR (&deposit->h_contract),
    TALER_DB_QUERY_PARAM_PTR (&deposit->h_wire),
    TALER_DB_QUERY_PARAM_PTR (&deposit->csig),
    TALER_DB_QUERY_PARAM_PTR_SIZED (json_wire_enc,
                                    strlen (json_wire_enc)),
    TALER_DB_QUERY_PARAM_END
  };
  result = TALER_DB_exec_prepared (db_conn, "insert_deposit", params);
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    goto cleanup;
  }
  ret = GNUNET_OK;

 cleanup:
  PQclear (result);
  GNUNET_free_non_null (denom_pub_enc);
  GNUNET_free_non_null (denom_sig_enc);
  GNUNET_free_non_null (json_wire_enc);
  return ret;
}


/**
 * Lookup refresh session data under the given public key.
 *
 * @param db_conn database handle to use
 * @param refresh_session_pub public key to use for the lookup
 * @param session[OUT] where to store the result
 * @return #GNUNET_YES on success,
 *         #GNUNET_NO if not found,
 *         #GNUNET_SYSERR on DB failure
 */
int
TALER_MINT_DB_get_refresh_session (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                   struct RefreshSession *session)
{
  // FIXME: check logic!
  int res;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_session", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Query failed: %s\n",
                PQresultErrorMessage (result));
    PQclear (result);
    return GNUNET_SYSERR;
  }

  if (0 == PQntuples (result))
    return GNUNET_NO;

  GNUNET_assert (1 == PQntuples (result));

  /* We're done if the caller is only interested in
   * whether the session exists or not */

  if (NULL == session)
    return GNUNET_YES;

  memset (session, 0, sizeof (struct RefreshSession));

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("num_oldcoins", &session->num_oldcoins),
    TALER_DB_RESULT_SPEC("num_newcoins", &session->num_newcoins),
    TALER_DB_RESULT_SPEC("kappa", &session->kappa),
    TALER_DB_RESULT_SPEC("noreveal_index", &session->noreveal_index),
    TALER_DB_RESULT_SPEC_END
  };

  res = TALER_DB_extract_result (result, rs, 0);

  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    PQclear (result);
    return GNUNET_SYSERR;
  }

  session->num_oldcoins = ntohs (session->num_oldcoins);
  session->num_newcoins = ntohs (session->num_newcoins);
  session->kappa = ntohs (session->kappa);
  session->noreveal_index = ntohs (session->noreveal_index);

  PQclear (result);
  return GNUNET_YES;
}


/**
 * Store new refresh session data under the given public key.
 *
 * @param db_conn database handle to use
 * @param refresh_session_pub public key to use to locate the session
 * @param session session data to store
 * @return #GNUNET_YES on success,
 *         #GNUNET_SYSERR on DB failure
 */
int
TALER_MINT_DB_create_refresh_session (PGconn *db_conn,
                                      const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                      const struct RefreshSession *session)
{
  // FIXME: actually store session data!
  uint16_t noreveal_index;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&noreveal_index),
    TALER_DB_QUERY_PARAM_END
  };

  noreveal_index = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, 1<<15);
  noreveal_index = htonl (noreveal_index);

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_session", params);

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
 * @param db_conn database connection
 * @param session session key of the melt operation
 * @param oldcoin_index index of the coin to store
 * @param melt melt operation
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_insert_refresh_melt (PGconn *db_conn,
                                   const struct GNUNET_CRYPTO_EddsaPublicKey *session,
                                   uint16_t oldcoin_index,
                                   const struct RefreshMelt *melt)
{
  // FIXME: check logic!
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);
  char *buf;
  size_t buf_size;
  PGresult *result;

  buf_size = GNUNET_CRYPTO_rsa_public_key_encode (melt->coin.denom_pub,
                                                  &buf);
  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR(session),
      TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
      TALER_DB_QUERY_PARAM_PTR(&melt->coin.coin_pub),
      TALER_DB_QUERY_PARAM_PTR_SIZED(buf, buf_size),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn, "insert_refresh_melt", params);
  }
  GNUNET_free (buf);
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
 * @param db_conn database connection
 * @param session session key of the melt operation
 * @param oldcoin_index index of the coin to retrieve
 * @param melt melt data to fill in
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_get_refresh_melt (PGconn *db_conn,
                                const struct GNUNET_CRYPTO_EddsaPublicKey *session,
                                uint16_t oldcoin_index,
                                struct RefreshMelt *melt)
{
  // FIXME: check logic!
  GNUNET_break (0);
  return GNUNET_SYSERR;
}


/**
 * Store in the database which coin(s) we want to create
 * in a given refresh operation.
 *
 * @param db_conn database connection
 * @param session_pub refresh session key
 * @param newcoin_index index of the coin to generate
 * @param denom_pub denomination of the coin to create
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_DB_insert_refresh_order (PGconn *db_conn,
                                    const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                    uint16_t newcoin_index,
                                    const struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub)
{
  // FIXME: check logic
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  char *buf;
  size_t buf_size;
  PGresult *result;

  buf_size = GNUNET_CRYPTO_rsa_public_key_encode (denom_pub,
                                                  &buf);

  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR (&newcoin_index_nbo),
      TALER_DB_QUERY_PARAM_PTR (session_pub),
      TALER_DB_QUERY_PARAM_PTR_SIZED (buf, buf_size),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn,
                                     "insert_refresh_order",
                                     params);
  }
  GNUNET_free (buf);
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
 * Lookup in the database the @a newcoin_index coin that we want to
 * create in the given refresh operation.
 *
 * @param db_conn database connection
 * @param session_pub refresh session key
 * @param newcoin_index index of the coin to generate
 * @param denom_pub denomination of the coin to create
 * @return NULL on error (not found or internal error)
 */
struct GNUNET_CRYPTO_rsa_PublicKey *
TALER_MINT_DB_get_refresh_order (PGconn *db_conn,
                                 const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                 uint16_t newcoin_index)
{
  // FIXME: check logic
  char *buf;
  size_t buf_size;
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;
  uint16_t newcoin_index_nbo = htons (newcoin_index);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(session_pub),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_order", params);

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    BREAK_DB_ERR (result);
    PQclear (result);
    return NULL;
  }

  if (0 == PQntuples (result))
  {
    PQclear (result);
    /* FIXME: may want to distinguish between different error cases! */
    return NULL;
  }
  GNUNET_assert (1 == PQntuples (result));
  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC_VAR ("denom_pub", &buf, &buf_size),
    TALER_DB_RESULT_SPEC_END
  };
  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_break (0);
    return NULL;
  }
  PQclear (result);
  denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (buf, buf_size);
  GNUNET_free (buf);
  return denom_pub;
}



/**
 * Store information about the commitment of the
 * given coin for the given refresh session in the database.
 *
 * @param db_conn database connection to use
 * @param refresh_session_pub refresh session this commitment belongs to
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to refreshed (new) coins
 * @param commit_coin coin commitment to store
 * @return #GNUNET_OK on success
 *         #GNUNET_SYSERR on error
 */
int
TALER_MINT_DB_insert_refresh_commit_coin (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                          unsigned int i,
                                          unsigned int j,
                                          const struct RefreshCommitCoin *commit_coin)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t newcoin_index_nbo = htons (j);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR_SIZED(commit_coin->coin_ev, commit_coin->coin_ev_size),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR_SIZED(commit_coin->refresh_link->coin_priv_enc,
                                   commit_coin->refresh_link->blinding_key_enc_size +
                                   sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "insert_refresh_commit_coin", params);

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
 * @param db_conn database connection to use
 * @param refresh_session_pub refresh session the commitment belongs to
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to refreshed (new) coins
 * @param commit_coin[OUT] coin commitment to return
 * @return #GNUNET_OK on success
 *         #GNUNET_NO if not found
 *         #GNUNET_SYSERR on error
 */
int
TALER_MINT_DB_get_refresh_commit_coin (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       unsigned int cnc_index,
                                       unsigned int newcoin_index,
                                       struct RefreshCommitCoin *cc)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };
  char *c_buf;
  size_t c_buf_size;
  char *rl_buf;
  size_t rl_buf_size;
  struct TALER_RefreshLinkEncrypted *rl;

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_refresh_commit_coin", params);

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

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC_VAR("coin_ev", &c_buf, &c_buf_size),
    TALER_DB_RESULT_SPEC_VAR("link_vector_enc", &rl_buf, &rl_buf_size),
    TALER_DB_RESULT_SPEC_END
  };
  if (GNUNET_YES != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);
  if (rl_buf_size < sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey))
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
 * @param db_conn database connection to use
 * @param refresh_session_pub public key of the refresh session this
 *        commitment belongs with
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to melted (old) coins
 * @param commit_link link information to store
 * @return #GNUNET_SYSERR on internal error, #GNUNET_OK on success
 */
int
TALER_MINT_DB_insert_refresh_commit_link (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                          unsigned int i,
                                          unsigned int j,
                                          const struct RefreshCommitLink *commit_link)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (i);
  uint16_t oldcoin_index_nbo = htons (j);
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&commit_link->transfer_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&commit_link->shared_secret_enc),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn,
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
 * @param db_conn database connection to use
 * @param refresh_session_pub public key of the refresh session this
 *        commitment belongs with
 * @param i set index (1st dimension)
 * @param j coin index (2nd dimension), corresponds to melted (old) coins
 * @param cc[OUT] link information to return
 * @return #GNUNET_SYSERR on internal error,
 *         #GNUNET_NO if commitment was not found
 *         #GNUNET_OK on success
 */
int
TALER_MINT_DB_get_refresh_commit_link (PGconn *db_conn,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                                       unsigned int cnc_index,
                                       unsigned int oldcoin_index,
                                       struct RefreshCommitLink *cc)
{
  // FIXME: check logic!
  uint16_t cnc_index_nbo = htons (cnc_index);
  uint16_t oldcoin_index_nbo = htons (oldcoin_index);

  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(refresh_session_pub),
    TALER_DB_QUERY_PARAM_PTR(&cnc_index_nbo),
    TALER_DB_QUERY_PARAM_PTR(&oldcoin_index_nbo),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn,
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

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("transfer_pub", &cc->transfer_pub),
    TALER_DB_RESULT_SPEC("link_secret_enc", &cc->shared_secret_enc),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_YES != TALER_DB_extract_result (result, rs, 0))
  {
    PQclear (result);
    GNUNET_free (cc);
    return GNUNET_SYSERR;
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
 * @param db_conn database connection
 * @param session_pub refresh session
 * @param newcoin_index coin index
 * @param ev_sig coin signature
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_DB_insert_refresh_collectable (PGconn *db_conn,
                                          const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                          uint16_t newcoin_index,
                                          const struct GNUNET_CRYPTO_rsa_Signature *ev_sig)
{
  // FIXME: check logic!
  uint16_t newcoin_index_nbo = htons (newcoin_index);
  char *buf;
  size_t buf_size;
  PGresult *result;

  buf_size = GNUNET_CRYPTO_rsa_signature_encode (ev_sig,
                                                 &buf);
  {
    struct TALER_DB_QueryParam params[] = {
      TALER_DB_QUERY_PARAM_PTR(session_pub),
      TALER_DB_QUERY_PARAM_PTR(&newcoin_index_nbo),
      TALER_DB_QUERY_PARAM_PTR_SIZED(buf, buf_size),
      TALER_DB_QUERY_PARAM_END
    };
    result = TALER_DB_exec_prepared (db_conn,
                                     "insert_refresh_collectable",
                                     params);
  }
  GNUNET_free (buf);
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
 * @param db_conn database connection
 * @param coin_pub public key to use to retrieve linkage data
 * @return all known link data for the coin
 */
struct LinkDataList *
TALER_db_get_link (PGconn *db_conn,
                   const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub)
{
  // FIXME: check logic!
  struct LinkDataList *ldl;
  struct LinkDataList *pos;
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(coin_pub),
    TALER_DB_QUERY_PARAM_END
  };
  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_link", params);

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
    char *ld_buf;
    size_t ld_buf_size;
    char *pk_buf;
    size_t pk_buf_size;
    char *sig_buf;
    size_t sig_buf_size;
    struct TALER_DB_ResultSpec rs[] = {
      TALER_DB_RESULT_SPEC_VAR("link_vector_enc", &ld_buf, &ld_buf_size),
      TALER_DB_RESULT_SPEC_VAR("denom_pub", &pk_buf, &pk_buf_size),
      TALER_DB_RESULT_SPEC_VAR("ev_sig", &sig_buf, &sig_buf_size),
      TALER_DB_RESULT_SPEC_END
    };

    if (GNUNET_OK != TALER_DB_extract_result (result, rs, i))
    {
      PQclear (result);
      GNUNET_break (0);
      TALER_db_link_data_list_free (ldl);
      return NULL;
    }
    if (ld_buf_size < sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey))
    {
      PQclear (result);
      GNUNET_free (pk_buf);
      GNUNET_free (sig_buf);
      GNUNET_free (ld_buf);
      TALER_db_link_data_list_free (ldl);
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

    sig = GNUNET_CRYPTO_rsa_signature_decode (sig_buf,
                                              sig_buf_size);
    denom_pub = GNUNET_CRYPTO_rsa_public_key_decode (pk_buf,
                                                     pk_buf_size);
    GNUNET_free (pk_buf);
    GNUNET_free (sig_buf);
    GNUNET_free (ld_buf);
    if ( (NULL == sig) ||
         (NULL == denom_pub) )
    {
      if (NULL != denom_pub)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pub);
      if (NULL != sig)
        GNUNET_CRYPTO_rsa_signature_free (sig);
      GNUNET_free (link_enc);
      GNUNET_break (0);
      PQclear (result);
      TALER_db_link_data_list_free (ldl);
      return NULL;
    }
    pos = GNUNET_new (struct LinkDataList);
    pos->next = ldl;
    pos->link_data_enc = link_enc;
    pos->denom_pub = denom_pub;
    pos->ev_sig = sig;
    ldl = pos;
  }
  return ldl;
}


/**
 * Free memory of the link data list.
 *
 * @param ldl link data list to release
 */
void
TALER_db_link_data_list_free (struct LinkDataList *ldl)
{
  GNUNET_break (0); // FIXME
}


/**
 * Obtain shared secret and transfer public key from the public key of
 * the coin.  This information and the link information returned by
 * #TALER_db_get_link() enable the owner of an old coin to determine
 * the private keys of the new coins after the melt.
 *
 *
 * @param db_conn database connection
 * @param coin_pub public key of the coin
 * @param transfer_pub[OUT] public transfer key
 * @param shared_secret_enc[OUT] set to shared secret
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO on failure (not found)
 *         #GNUNET_SYSERR on internal failure (database issue)
 */
int
TALER_db_get_transfer (PGconn *db_conn,
                       const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                       struct GNUNET_CRYPTO_EcdsaPublicKey *transfer_pub,
                       struct TALER_EncryptedLinkSecret *shared_secret_enc)
{
  // FIXME: check logic!
  struct TALER_DB_QueryParam params[] = {
    TALER_DB_QUERY_PARAM_PTR(coin_pub),
    TALER_DB_QUERY_PARAM_END
  };

  PGresult *result = TALER_DB_exec_prepared (db_conn, "get_transfer", params);

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

  struct TALER_DB_ResultSpec rs[] = {
    TALER_DB_RESULT_SPEC("transfer_pub", transfer_pub),
    TALER_DB_RESULT_SPEC("link_secret_enc", shared_secret_enc),
    TALER_DB_RESULT_SPEC_END
  };

  if (GNUNET_OK != TALER_DB_extract_result (result, rs, 0))
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
 * @param db_conn database connection
 * @param coin_pub coin to investigate
 * @return list of transactions, NULL if coin is fresh
 */
struct TALER_MINT_DB_TransactionList *
TALER_MINT_DB_get_coin_transactions (PGconn *db_conn,
                                     const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub)
{
  // FIXME: check logic!
  GNUNET_break (0); // FIXME: implement!
  return NULL;
}


/**
 * Free linked list of transactions.
 *
 * @param list list to free
 */
void
TALER_MINT_DB_free_coin_transaction_list (struct TALER_MINT_DB_TransactionList *list)
{
  // FIXME: check logic!
  GNUNET_break (0);
}


/* end of mint_db.c */
