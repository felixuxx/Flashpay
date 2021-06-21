/*
  This file is part of TALER
  Copyright (C) 2014--2021 Taler Systems SA

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
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_pq_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
#include <pthread.h>
#include <libpq-fe.h>

#include "plugin_exchangedb_common.c"

/**
 * Set to 1 to enable Postgres auto_explain module. This will
 * slow down things a _lot_, but also provide extensive logging
 * in the Postgres database logger for performance analysis.
 */
#define AUTO_EXPLAIN 1

/**
 * Should we explicitly lock certain individual tables prior to SELECT+INSERT
 * combis?
 */
#define EXPLICIT_LOCKS 0

/**
 * Wrapper macro to add the currency from the plugin's state
 * when fetching amounts from the database.
 *
 * @param field name of the database field to fetch amount from
 * @param[out] amountp pointer to amount to set
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT(field,amountp) TALER_PQ_result_spec_amount ( \
    field,pg->currency,amountp)

/**
 * Wrapper macro to add the currency from the plugin's state
 * when fetching amounts from the database.  NBO variant.
 *
 * @param field name of the database field to fetch amount from
 * @param[out] amountp pointer to amount to set
 */
#define TALER_PQ_RESULT_SPEC_AMOUNT_NBO(field,                          \
                                        amountp) TALER_PQ_result_spec_amount_nbo ( \
    field,pg->currency,amountp)

/**
 * Log a really unexpected PQ error with all the details we can get hold of.
 *
 * @param result PQ result object of the PQ operation that failed
 * @param conn SQL connection that was used
 */
#define BREAK_DB_ERR(result,conn) do {                                  \
    GNUNET_break (0);                                                   \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,                                \
                "Database failure: %s/%s/%s/%s/%s",                     \
                PQresultErrorField (result, PG_DIAG_MESSAGE_PRIMARY),   \
                PQresultErrorField (result, PG_DIAG_MESSAGE_DETAIL),    \
                PQresultErrorMessage (result),                          \
                PQresStatus (PQresultStatus (result)),                  \
                PQerrorMessage (conn));                                 \
} while (0)


/**
 * Handler for a database session (per-thread, for transactions).
 */
struct TALER_EXCHANGEDB_Session
{
  /**
   * Postgres connection handle.
   */
  struct GNUNET_PQ_Context *conn;

  /**
   * Name of the current transaction, for debugging.
   */
  const char *transaction_name;

};


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct PostgresClosure
{

  /**
   * Thread-local database connection.
   * Contains a pointer to `struct GNUNET_PQ_Context` or NULL.
   */
  pthread_key_t db_conn_threadlocal;

  /**
   * Our configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Directory with SQL statements to run to create tables.
   */
  char *sql_dir;

  /**
   * After how long should idle reserves be closed?
   */
  struct GNUNET_TIME_Relative idle_reserve_expiration_time;

  /**
   * After how long should reserves that have seen withdraw operations
   * be garbage collected?
   */
  struct GNUNET_TIME_Relative legal_reserve_expiration_time;

  /**
   * Which currency should we assume all amounts to be in?
   */
  char *currency;

  /**
   * Session to be used if the thread is @e main_self.
   */
  struct TALER_EXCHANGEDB_Session *main_session;

  /**
   * Handle for the main() thread of the program.
   */
  pthread_t main_self;
};


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
  struct GNUNET_PQ_Context *conn;

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "exchangedb-postgres",
                                     "drop",
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return GNUNET_OK;
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
  struct GNUNET_PQ_Context *conn;

  conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                     "exchangedb-postgres",
                                     "exchange-",
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return GNUNET_OK;
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
  struct GNUNET_PQ_Context *db_conn;

  if (NULL == session)
    return;
  db_conn = session->conn;
  session->conn = NULL;
  if (NULL != db_conn)
    GNUNET_PQ_disconnect (db_conn);
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
  struct GNUNET_PQ_Context *db_conn;
  struct TALER_EXCHANGEDB_Session *session;

  if (pthread_equal (pc->main_self,
                     pthread_self ()))
    session = pc->main_session;
  else
    session = pthread_getspecific (pc->db_conn_threadlocal);
  if (NULL != session)
  {
    GNUNET_PQ_reconnect_if_down (session->conn);
    return session;
  }
  {
#if AUTO_EXPLAIN
    /* Enable verbose logging to see where queries do not
       properly use indices */
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute ("LOAD 'auto_explain';"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_min_duration=50;"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_timing=TRUE;"),
      GNUNET_PQ_make_try_execute ("SET auto_explain.log_analyze=TRUE;"),
      /* https://wiki.postgresql.org/wiki/Serializable suggests to really
         force the default to 'serializable' if SSI is to be used. */
      GNUNET_PQ_make_try_execute (
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
#else
    struct GNUNET_PQ_ExecuteStatement *es = NULL;
#endif
    struct GNUNET_PQ_PreparedStatement ps[] = {
      /* Used in #postgres_insert_denomination_info() and
         #postgres_add_denomination_key() */
      GNUNET_PQ_make_prepare ("denomination_insert",
                              "INSERT INTO denominations "
                              "(denom_pub_hash"
                              ",denom_pub"
                              ",master_sig"
                              ",valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"                                          /* value of this denom */
                              ",coin_frac"                                          /* fractional value of this denom */
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
                              " $11, $12, $13, $14, $15, $16, $17);",
                              17),
      /* Used in #postgres_iterate_denomination_info() */
      GNUNET_PQ_make_prepare ("denomination_iterate",
                              "SELECT"
                              " master_sig"
                              ",valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"                                          /* value of this denom */
                              ",coin_frac"                                          /* fractional value of this denom */
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              ",denom_pub"
                              " FROM denominations;",
                              0),
      /* Used in #postgres_iterate_denominations() */
      GNUNET_PQ_make_prepare ("select_denominations",
                              "SELECT"
                              " denominations.master_sig"
                              ",denom_revocations_serial_id IS NOT NULL AS revoked"
                              ",valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"                                          /* value of this denom */
                              ",coin_frac"                                          /* fractional value of this denom */
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              ",denom_pub"
                              " FROM denominations"
                              " LEFT JOIN "
                              "   denomination_revocations USING (denominations_serial);",
                              0),
      /* Used in #postgres_iterate_active_signkeys() */
      GNUNET_PQ_make_prepare ("select_signkeys",
                              "SELECT"
                              " master_sig"
                              ",exchange_pub"
                              ",valid_from"
                              ",expire_sign"
                              ",expire_legal"
                              " FROM exchange_sign_keys esk"
                              " WHERE"
                              "   expire_sign > $1"
                              " AND NOT EXISTS "
                              "  (SELECT esk_serial "
                              "     FROM signkey_revocations skr"
                              "    WHERE esk.esk_serial = skr.esk_serial);",
                              1),
      /* Used in #postgres_iterate_auditor_denominations() */
      GNUNET_PQ_make_prepare ("select_auditor_denoms",
                              "SELECT"
                              " auditors.auditor_pub"
                              ",denominations.denom_pub_hash"
                              ",auditor_denom_sigs.auditor_sig"
                              " FROM auditor_denom_sigs"
                              " JOIN auditors USING (auditor_uuid)"
                              " JOIN denominations USING (denominations_serial)"
                              " WHERE auditors.is_active;",
                              0),
      /* Used in #postgres_iterate_active_auditors() */
      GNUNET_PQ_make_prepare ("select_auditors",
                              "SELECT"
                              " auditor_pub"
                              ",auditor_url"
                              ",auditor_name"
                              " FROM auditors"
                              " WHERE"
                              "   is_active;",
                              0),
      /* Used in #postgres_get_denomination_info() */
      GNUNET_PQ_make_prepare ("denomination_get",
                              "SELECT"
                              " master_sig"
                              ",valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"                                          /* value of this denom */
                              ",coin_frac"                                          /* fractional value of this denom */
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              " FROM denominations"
                              " WHERE denom_pub_hash=$1;",
                              1),
      /* Used in #postgres_insert_denomination_revocation() */
      GNUNET_PQ_make_prepare ("denomination_revocation_insert",
                              "INSERT INTO denomination_revocations "
                              "(denominations_serial"
                              ",master_sig"
                              ") SELECT denominations_serial,$2"
                              "    FROM denominations"
                              "   WHERE denom_pub_hash=$1;",
                              2),
      /* Used in #postgres_get_denomination_revocation() */
      GNUNET_PQ_make_prepare ("denomination_revocation_get",
                              "SELECT"
                              " master_sig"
                              ",denom_revocations_serial_id"
                              " FROM denomination_revocations"
                              " WHERE denominations_serial="
                              "  (SELECT denominations_serial"
                              "    FROM denominations"
                              "    WHERE denom_pub_hash=$1);",
                              1),
      /* Used in #postgres_reserves_get() */
      GNUNET_PQ_make_prepare ("reserves_get",
                              "SELECT"
                              " current_balance_val"
                              ",current_balance_frac"
                              ",expiration_date"
                              ",gc_date"
                              " FROM reserves"
                              " WHERE reserve_pub=$1"
                              " LIMIT 1;",
                              1),
      /* Used in #postgres_reserves_in_insert() when the reserve is new */
      GNUNET_PQ_make_prepare ("reserve_create",
                              "INSERT INTO reserves "
                              "(reserve_pub"
                              ",account_details"
                              ",current_balance_val"
                              ",current_balance_frac"
                              ",expiration_date"
                              ",gc_date"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6)"
                              " ON CONFLICT DO NOTHING;",
                              6),
      /* Used in #postgres_insert_reserve_closed() */
      GNUNET_PQ_make_prepare ("reserves_close_insert",
                              "INSERT INTO reserves_close "
                              "(reserve_uuid"
                              ",execution_date"
                              ",wtid"
                              ",receiver_account"
                              ",amount_val"
                              ",amount_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ") SELECT reserve_uuid, $2, $3, $4, $5, $6, $7, $8"
                              "  FROM reserves"
                              "  WHERE reserve_pub=$1;",
                              8),
      /* Used in #reserves_update() when the reserve is updated */
      GNUNET_PQ_make_prepare ("reserve_update",
                              "UPDATE reserves"
                              " SET"
                              " expiration_date=$1"
                              ",gc_date=$2"
                              ",current_balance_val=$3"
                              ",current_balance_frac=$4"
                              " WHERE reserve_pub=$5;",
                              5),
      /* Used in #postgres_reserves_in_insert() to store transaction details */
      GNUNET_PQ_make_prepare ("reserves_in_add_transaction",
                              "INSERT INTO reserves_in "
                              "(reserve_uuid"
                              ",wire_reference"
                              ",credit_val"
                              ",credit_frac"
                              ",exchange_account_section"
                              ",sender_account_details"
                              ",execution_date"
                              ") SELECT reserve_uuid, $2, $3, $4, $5, $6, $7"
                              "  FROM reserves"
                              "  WHERE reserve_pub=$1"
                              " ON CONFLICT DO NOTHING;",
                              7),
      /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
         transactions for reserves with serial id '\geq' the given parameter */
      GNUNET_PQ_make_prepare ("reserves_in_get_latest_wire_reference",
                              "SELECT"
                              " wire_reference"
                              " FROM reserves_in"
                              " WHERE exchange_account_section=$1"
                              " ORDER BY reserve_in_serial_id DESC"
                              " LIMIT 1;",
                              1),
      /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
         transactions for reserves with serial id '\geq' the given parameter */
      GNUNET_PQ_make_prepare ("audit_reserves_in_get_transactions_incr",
                              "SELECT"
                              " reserves.reserve_pub"
                              ",wire_reference"
                              ",credit_val"
                              ",credit_frac"
                              ",execution_date"
                              ",sender_account_details"
                              ",reserve_in_serial_id"
                              " FROM reserves_in"
                              " JOIN reserves"
                              "   USING (reserve_uuid)"
                              " WHERE reserve_in_serial_id>=$1"
                              " ORDER BY reserve_in_serial_id;",
                              1),
      /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
         transactions for reserves with serial id '\geq' the given parameter */
      GNUNET_PQ_make_prepare (
        "audit_reserves_in_get_transactions_incr_by_account",
        "SELECT"
        " reserves.reserve_pub"
        ",wire_reference"
        ",credit_val"
        ",credit_frac"
        ",execution_date"
        ",sender_account_details"
        ",reserve_in_serial_id"
        " FROM reserves_in"
        " JOIN reserves "
        "   USING (reserve_uuid)"
        " WHERE reserve_in_serial_id>=$1 AND exchange_account_section=$2"
        " ORDER BY reserve_in_serial_id;",
        2),
      /* Used in #postgres_get_reserve_history() to obtain inbound transactions
         for a reserve */
      GNUNET_PQ_make_prepare ("reserves_in_get_transactions",
                              "SELECT"
                              " wire_reference"
                              ",credit_val"
                              ",credit_frac"
                              ",execution_date"
                              ",sender_account_details"
                              " FROM reserves_in"
                              " WHERE reserve_uuid="
                              " (SELECT reserve_uuid "
                              "   FROM reserves"
                              "   WHERE reserve_pub=$1);",
                              1),
      /* Lock withdraw table; NOTE: we may want to eventually shard the
         deposit table to avoid this lock being the main point of
         contention limiting transaction performance. */
      GNUNET_PQ_make_prepare ("lock_withdraw",
                              "LOCK TABLE reserves_out;",
                              0),
      /* Used in #postgres_insert_withdraw_info() to store
         the signature of a blinded coin with the blinded coin's
         details before returning it during /reserve/withdraw. We store
         the coin's denomination information (public key, signature)
         and the blinded message as well as the reserve that the coin
         is being withdrawn from and the signature of the message
         authorizing the withdrawal. */
      GNUNET_PQ_make_prepare ("insert_withdraw_info",
                              "WITH ds AS"
                              " (SELECT denominations_serial"
                              "    FROM denominations"
                              "   WHERE denom_pub_hash=$2)"
                              "INSERT INTO reserves_out "
                              "(h_blind_ev"
                              ",denominations_serial"
                              ",denom_sig"
                              ",reserve_uuid"
                              ",reserve_sig"
                              ",execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ") SELECT $1, ds.denominations_serial, $3, reserve_uuid, $5, $6, $7, $8"
                              "    FROM reserves"
                              "    CROSS JOIN ds"
                              "    WHERE reserve_pub=$4;",
                              8),
      /* Used in #postgres_get_withdraw_info() to
         locate the response for a /reserve/withdraw request
         using the hash of the blinded message.  Used to
         make sure /reserve/withdraw requests are idempotent. */
      GNUNET_PQ_make_prepare ("get_withdraw_info",
                              "SELECT"
                              " denom.denom_pub_hash"
                              ",denom_sig"
                              ",reserve_sig"
                              ",reserves.reserve_pub"
                              ",execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denom.fee_withdraw_val"
                              ",denom.fee_withdraw_frac"
                              " FROM reserves_out"
                              "    JOIN reserves"
                              "      USING (reserve_uuid)"
                              "    JOIN denominations denom"
                              "      USING (denominations_serial)"
                              " WHERE h_blind_ev=$1;",
                              1),
      /* Used during #postgres_get_reserve_history() to
         obtain all of the /reserve/withdraw operations that
         have been performed on a given reserve. (i.e. to
         demonstrate double-spending) */
      GNUNET_PQ_make_prepare ("get_reserves_out",
                              "SELECT"
                              " h_blind_ev"
                              ",denom.denom_pub_hash"
                              ",denom_sig"
                              ",reserve_sig"
                              ",execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denom.fee_withdraw_val"
                              ",denom.fee_withdraw_frac"
                              " FROM reserves_out"
                              "    JOIN denominations denom"
                              "      USING (denominations_serial)"
                              " WHERE reserve_uuid="
                              "   (SELECT reserve_uuid"
                              "      FROM reserves"
                              "     WHERE reserve_pub=$1);",
                              1),
      /* Used in #postgres_select_withdrawals_above_serial_id() */
      GNUNET_PQ_make_prepare ("audit_get_reserves_out_incr",
                              "SELECT"
                              " h_blind_ev"
                              ",denom.denom_pub"
                              ",reserve_sig"
                              ",reserves.reserve_pub"
                              ",execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",reserve_out_serial_id"
                              " FROM reserves_out"
                              "    JOIN reserves"
                              "      USING (reserve_uuid)"
                              "    JOIN denominations denom"
                              "      USING (denominations_serial)"
                              " WHERE reserve_out_serial_id>=$1"
                              " ORDER BY reserve_out_serial_id ASC;",
                              1),

      /* Used in #postgres_count_known_coins() */
      GNUNET_PQ_make_prepare ("count_known_coins",
                              "SELECT"
                              " COUNT(*) AS count"
                              " FROM known_coins"
                              " WHERE denominations_serial="
                              "  (SELECT denominations_serial"
                              "    FROM denominations"
                              "    WHERE denom_pub_hash=$1);",
                              1),
      /* Used in #postgres_get_known_coin() to fetch
         the denomination public key and signature for
         a coin known to the exchange. */
      GNUNET_PQ_make_prepare ("get_known_coin",
                              "SELECT"
                              " denominations.denom_pub_hash"
                              ",denom_sig"
                              " FROM known_coins"
                              " JOIN denominations USING (denominations_serial)"
                              " WHERE coin_pub=$1;",
                              1),
      /* Used in #postgres_ensure_coin_known() */
      GNUNET_PQ_make_prepare ("get_known_coin_dh",
                              "SELECT"
                              " denominations.denom_pub_hash"
                              " FROM known_coins"
                              " JOIN denominations USING (denominations_serial)"
                              " WHERE coin_pub=$1;",
                              1),
      /* Used in #postgres_get_coin_denomination() to fetch
         the denomination public key hash for
         a coin known to the exchange. */
      GNUNET_PQ_make_prepare ("get_coin_denomination",
                              "SELECT"
                              " denominations.denom_pub_hash"
                              " FROM known_coins"
                              " JOIN denominations USING (denominations_serial)"
                              " WHERE coin_pub=$1"
                              " FOR SHARE;",
                              1),
      /* Lock deposit table; NOTE: we may want to eventually shard the
         deposit table to avoid this lock being the main point of
         contention limiting transaction performance. */
      GNUNET_PQ_make_prepare ("lock_known_coins",
                              "LOCK TABLE known_coins;",
                              0),
      /* Used in #postgres_insert_known_coin() to store
         the denomination public key and signature for
         a coin known to the exchange. */
      GNUNET_PQ_make_prepare ("insert_known_coin",
                              "INSERT INTO known_coins "
                              "(coin_pub"
                              ",denominations_serial"
                              ",denom_sig"
                              ") SELECT $1, denominations_serial, $3 "
                              "    FROM denominations"
                              "   WHERE denom_pub_hash=$2;",
                              3),

      /* Used in #postgres_insert_melt() to store
         high-level information about a melt operation */
      GNUNET_PQ_make_prepare ("insert_melt",
                              "INSERT INTO refresh_commitments "
                              "(rc "
                              ",old_known_coin_id "
                              ",old_coin_sig "
                              ",amount_with_fee_val "
                              ",amount_with_fee_frac "
                              ",noreveal_index "
                              ") SELECT $1, known_coin_id, $3, $4, $5, $6"
                              "    FROM known_coins"
                              "   WHERE coin_pub=$2",
                              6),
      /* Used in #postgres_get_melt() to fetch
         high-level information about a melt operation */
      GNUNET_PQ_make_prepare ("get_melt",
                              "SELECT"
                              " denoms.denom_pub_hash"
                              ",denoms.fee_refresh_val"
                              ",denoms.fee_refresh_frac"
                              ",kc.coin_pub AS old_coin_pub"
                              ",old_coin_sig"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",noreveal_index"
                              " FROM refresh_commitments"
                              "   JOIN known_coins kc"
                              "     ON (refresh_commitments.old_known_coin_id = kc.known_coin_id)"
                              "   JOIN denominations denoms"
                              "     ON (kc.denominations_serial = denoms.denominations_serial)"
                              " WHERE rc=$1;",
                              1),
      /* Used in #postgres_get_melt_index() to fetch
         the noreveal index from a previous melt operation */
      GNUNET_PQ_make_prepare ("get_melt_index",
                              "SELECT"
                              " noreveal_index"
                              " FROM refresh_commitments"
                              " WHERE rc=$1;",
                              1),
      /* Used in #postgres_select_refreshes_above_serial_id() to fetch
         refresh session with id '\geq' the given parameter */
      GNUNET_PQ_make_prepare ("audit_get_refresh_commitments_incr",
                              "SELECT"
                              " denom.denom_pub"
                              ",kc.coin_pub AS old_coin_pub"
                              ",old_coin_sig"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",noreveal_index"
                              ",melt_serial_id"
                              ",rc"
                              " FROM refresh_commitments"
                              "   JOIN known_coins kc"
                              "     ON (refresh_commitments.old_known_coin_id = kc.known_coin_id)"
                              "   JOIN denominations denom"
                              "     ON (kc.denominations_serial = denom.denominations_serial)"
                              " WHERE melt_serial_id>=$1"
                              " ORDER BY melt_serial_id ASC;",
                              1),
      /* Query the 'refresh_commitments' by coin public key */
      GNUNET_PQ_make_prepare ("get_refresh_session_by_coin",
                              "SELECT"
                              " rc"
                              ",old_coin_sig"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denoms.denom_pub_hash"
                              ",denoms.fee_refresh_val"
                              ",denoms.fee_refresh_frac"
                              ",melt_serial_id"
                              " FROM refresh_commitments"
                              " JOIN known_coins kc"
                              "   ON (refresh_commitments.old_known_coin_id = kc.known_coin_id)"
                              " JOIN denominations denoms"
                              "   USING (denominations_serial)"
                              " WHERE old_known_coin_id="
                              "(SELECT known_coin_id"
                              "   FROM known_coins"
                              "  WHERE coin_pub=$1);",
                              1),
      /* Store information about the desired denominations for a
         refresh operation, used in #postgres_insert_refresh_reveal() */
      GNUNET_PQ_make_prepare ("insert_refresh_revealed_coin",
                              "WITH rcx AS"
                              " (SELECT melt_serial_id"
                              "    FROM refresh_commitments"
                              "   WHERE rc=$1)"
                              "INSERT INTO refresh_revealed_coins "
                              "(melt_serial_id "
                              ",freshcoin_index "
                              ",link_sig "
                              ",denominations_serial "
                              ",coin_ev"
                              ",h_coin_ev"
                              ",ev_sig"
                              ") SELECT rcx.melt_serial_id, $2, $3, "
                              "         denominations_serial, $5, $6, $7"
                              "    FROM denominations"
                              "   CROSS JOIN rcx"
                              "   WHERE denom_pub_hash=$4;",
                              7),
      /* Obtain information about the coins created in a refresh
         operation, used in #postgres_get_refresh_reveal() */
      GNUNET_PQ_make_prepare ("get_refresh_revealed_coins",
                              "SELECT "
                              " freshcoin_index"
                              ",denom.denom_pub"
                              ",link_sig"
                              ",coin_ev"
                              ",ev_sig"
                              " FROM refresh_revealed_coins"
                              "    JOIN denominations denom "
                              "      USING (denominations_serial)"
                              "    JOIN refresh_commitments"
                              "      USING (melt_serial_id)"
                              " WHERE rc=$1"
                              "   ORDER BY freshcoin_index ASC;",
                              1),

      /* Used in #postgres_insert_refresh_reveal() to store the transfer
         keys we learned */
      GNUNET_PQ_make_prepare ("insert_refresh_transfer_keys",
                              "INSERT INTO refresh_transfer_keys "
                              "(melt_serial_id"
                              ",transfer_pub"
                              ",transfer_privs"
                              ") SELECT melt_serial_id, $2, $3"
                              "    FROM refresh_commitments"
                              "   WHERE rc=$1",
                              3),
      /* Used in #postgres_get_refresh_reveal() to retrieve transfer
         keys from /refresh/reveal */
      GNUNET_PQ_make_prepare ("get_refresh_transfer_keys",
                              "SELECT"
                              " transfer_pub"
                              ",transfer_privs"
                              " FROM refresh_transfer_keys"
                              " JOIN refresh_commitments"
                              "   USING (melt_serial_id)"
                              " WHERE rc=$1;",
                              1),
      /* Used in #postgres_insert_refund() to store refund information */
      GNUNET_PQ_make_prepare ("insert_refund",
                              "INSERT INTO refunds "
                              "(deposit_serial_id "
                              ",merchant_sig "
                              ",rtransaction_id "
                              ",amount_with_fee_val "
                              ",amount_with_fee_frac "
                              ") SELECT deposit_serial_id, $3, $5, $6, $7"
                              "    FROM deposits"
                              "    JOIN known_coins USING (known_coin_id)"
                              "   WHERE coin_pub=$1"
                              "     AND h_contract_terms=$4"
                              "     AND merchant_pub=$2",
                              7),
      /* Query the 'refunds' by coin public key */
      GNUNET_PQ_make_prepare ("get_refunds_by_coin",
                              "SELECT"
                              " merchant_pub"
                              ",merchant_sig"
                              ",h_contract_terms"
                              ",rtransaction_id"
                              ",refunds.amount_with_fee_val"
                              ",refunds.amount_with_fee_frac"
                              ",denom.fee_refund_val "
                              ",denom.fee_refund_frac "
                              ",refund_serial_id"
                              " FROM refunds"
                              " JOIN deposits USING (deposit_serial_id)"
                              " JOIN known_coins USING (known_coin_id)"
                              " JOIN denominations denom USING (denominations_serial)"
                              " WHERE coin_pub=$1;",
                              1),
      /* Query the 'refunds' by coin public key, merchant_pub and contract hash */
      GNUNET_PQ_make_prepare ("get_refunds_by_coin_and_contract",
                              "SELECT"
                              " refunds.amount_with_fee_val"
                              ",refunds.amount_with_fee_frac"
                              " FROM refunds"
                              " JOIN deposits USING (deposit_serial_id)"
                              " JOIN known_coins USING (known_coin_id)"
                              " WHERE coin_pub=$1"
                              "   AND merchant_pub=$2"
                              "   AND h_contract_terms=$3;",
                              3),
      /* Fetch refunds with rowid '\geq' the given parameter */
      GNUNET_PQ_make_prepare ("audit_get_refunds_incr",
                              "SELECT"
                              " merchant_pub"
                              ",merchant_sig"
                              ",h_contract_terms"
                              ",rtransaction_id"
                              ",denom.denom_pub"
                              ",kc.coin_pub"
                              ",refunds.amount_with_fee_val"
                              ",refunds.amount_with_fee_frac"
                              ",refund_serial_id"
                              " FROM refunds"
                              "   JOIN deposits USING (deposit_serial_id)"
                              "   JOIN known_coins kc USING (known_coin_id)"
                              "   JOIN denominations denom ON (kc.denominations_serial = denom.denominations_serial)"
                              " WHERE refund_serial_id>=$1"
                              " ORDER BY refund_serial_id ASC;",
                              1),
      /* Lock deposit table; NOTE: we may want to eventually shard the
         deposit table to avoid this lock being the main point of
         contention limiting transaction performance. */
      GNUNET_PQ_make_prepare ("lock_deposit",
                              "LOCK TABLE deposits;",
                              0),
      /* Store information about a /deposit the exchange is to execute.
         Used in #postgres_insert_deposit(). */
      GNUNET_PQ_make_prepare ("insert_deposit",
                              "INSERT INTO deposits "
                              "(known_coin_id"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",wallet_timestamp"
                              ",refund_deadline"
                              ",wire_deadline"
                              ",merchant_pub"
                              ",h_contract_terms"
                              ",h_wire"
                              ",coin_sig"
                              ",wire"
                              ",exchange_timestamp"
                              ") SELECT known_coin_id, $2, $3, $4, $5, $6, "
                              " $7, $8, $9, $10, $11, $12"
                              "    FROM known_coins"
                              "   WHERE coin_pub=$1;",
                              12),
      /* Fetch an existing deposit request, used to ensure idempotency
         during /deposit processing. Used in #postgres_have_deposit(). */
      GNUNET_PQ_make_prepare ("get_deposit",
                              "SELECT"
                              " amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denominations.fee_deposit_val"
                              ",denominations.fee_deposit_frac"
                              ",wallet_timestamp"
                              ",exchange_timestamp"
                              ",refund_deadline"
                              ",wire_deadline"
                              ",h_contract_terms"
                              ",h_wire"
                              " FROM deposits"
                              " JOIN known_coins USING (known_coin_id)"
                              " JOIN denominations USING (denominations_serial)"
                              " WHERE ((coin_pub=$1)"
                              "    AND (merchant_pub=$3)"
                              "    AND (h_contract_terms=$2));",
                              3),
      /* Fetch deposits with rowid '\geq' the given parameter */
      GNUNET_PQ_make_prepare ("audit_get_deposits_incr",
                              "SELECT"
                              " amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",wallet_timestamp"
                              ",exchange_timestamp"
                              ",merchant_pub"
                              ",denom.denom_pub"
                              ",kc.coin_pub"
                              ",coin_sig"
                              ",refund_deadline"
                              ",wire_deadline"
                              ",h_contract_terms"
                              ",wire"
                              ",done"
                              ",deposit_serial_id"
                              " FROM deposits"
                              "    JOIN known_coins kc USING (known_coin_id)"
                              "    JOIN denominations denom USING (denominations_serial)"
                              " WHERE ("
                              "  (deposit_serial_id>=$1)"
                              " )"
                              " ORDER BY deposit_serial_id ASC;",
                              1),
      /* Fetch an existing deposit request.
         Used in #postgres_lookup_transfer_by_deposit(). */
      GNUNET_PQ_make_prepare ("get_deposit_for_wtid",
                              "SELECT"
                              " amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denom.fee_deposit_val"
                              ",denom.fee_deposit_frac"
                              ",wire_deadline"
                              " FROM deposits"
                              "    JOIN known_coins USING (known_coin_id)"
                              "    JOIN denominations denom USING (denominations_serial)"
                              " WHERE ((coin_pub=$1)"
                              "    AND (merchant_pub=$2)"
                              "    AND (h_contract_terms=$3)"
                              "    AND (h_wire=$4)"
                              " );",
                              4),
      /* Used in #postgres_get_ready_deposit() */
      GNUNET_PQ_make_prepare ("deposits_get_ready",
                              "SELECT"
                              " deposit_serial_id"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denom.fee_deposit_val"
                              ",denom.fee_deposit_frac"
                              ",wire_deadline"
                              ",h_contract_terms"
                              ",wire"
                              ",merchant_pub"
                              ",kc.coin_pub"
                              ",exchange_timestamp"
                              ",wallet_timestamp"
                              " FROM deposits"
                              "    JOIN known_coins kc USING (known_coin_id)"
                              "    JOIN denominations denom USING (denominations_serial)"
                              " WHERE tiny=FALSE"
                              "    AND done=FALSE"
                              "    AND wire_deadline<=$1"
                              "    AND refund_deadline<$1"
                              " ORDER BY wire_deadline ASC"
                              " LIMIT 1;",
                              1),
      /* Used in #postgres_iterate_matching_deposits() */
      GNUNET_PQ_make_prepare ("deposits_iterate_matching",
                              "SELECT"
                              " deposit_serial_id"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denom.fee_deposit_val"
                              ",denom.fee_deposit_frac"
                              ",h_contract_terms"
                              ",kc.coin_pub"
                              " FROM deposits"
                              "    JOIN known_coins kc USING (known_coin_id)"
                              "    JOIN denominations denom USING (denominations_serial)"
                              " WHERE"
                              "     merchant_pub=$1 AND"
                              "     h_wire=$2 AND"
                              "     done=FALSE"
                              " ORDER BY wire_deadline ASC"
                              " LIMIT "
                              TALER_QUOTE (
                                TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT) ";",
                              2),
      /* Used in #postgres_mark_deposit_tiny() */
      GNUNET_PQ_make_prepare ("mark_deposit_tiny",
                              "UPDATE deposits"
                              " SET tiny=TRUE"
                              " WHERE deposit_serial_id=$1",
                              1),
      /* Used in #postgres_mark_deposit_done() */
      GNUNET_PQ_make_prepare ("mark_deposit_done",
                              "UPDATE deposits"
                              " SET done=TRUE"
                              " WHERE deposit_serial_id=$1;",
                              1),
      /* Used in #postgres_test_deposit_done() */
      GNUNET_PQ_make_prepare ("test_deposit_done",
                              "SELECT done"
                              " FROM deposits"
                              " JOIN known_coins USING (known_coin_id)"
                              " WHERE coin_pub=$1"
                              "   AND merchant_pub=$2"
                              "   AND h_contract_terms=$3"
                              "   AND h_wire=$4;",
                              5),
      /* Used in #postgres_get_coin_transactions() to obtain information
         about how a coin has been spend with /deposit requests. */
      GNUNET_PQ_make_prepare ("get_deposit_with_coin_pub",
                              "SELECT"
                              " amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denoms.fee_deposit_val"
                              ",denoms.fee_deposit_frac"
                              ",denoms.denom_pub_hash"
                              ",wallet_timestamp"
                              ",refund_deadline"
                              ",wire_deadline"
                              ",merchant_pub"
                              ",h_contract_terms"
                              ",h_wire"
                              ",wire"
                              ",coin_sig"
                              ",deposit_serial_id"
                              ",done"
                              " FROM deposits"
                              "    JOIN known_coins kc"
                              "      USING (known_coin_id)"
                              "    JOIN denominations denoms"
                              "      USING (denominations_serial)"
                              " WHERE coin_pub=$1;",
                              1),

      /* Used in #postgres_get_link_data(). */
      GNUNET_PQ_make_prepare ("get_link",
                              "SELECT "
                              " tp.transfer_pub"
                              ",denoms.denom_pub"
                              ",rrc.ev_sig"
                              ",rrc.link_sig"
                              " FROM refresh_commitments"
                              "     JOIN refresh_revealed_coins rrc"
                              "       USING (melt_serial_id)"
                              "     JOIN refresh_transfer_keys tp"
                              "       USING (melt_serial_id)"
                              "     JOIN denominations denoms"
                              "       ON (rrc.denominations_serial = denoms.denominations_serial)"
                              " WHERE old_known_coin_id="
                              "   (SELECT known_coin_id "
                              "      FROM known_coins"
                              "     WHERE coin_pub=$1)"
                              " ORDER BY tp.transfer_pub, rrc.freshcoin_index ASC",
                              1),
      /* Used in #postgres_lookup_wire_transfer */
      GNUNET_PQ_make_prepare ("lookup_transactions",
                              "SELECT"
                              " aggregation_serial_id"
                              ",deposits.h_contract_terms"
                              ",deposits.wire"
                              ",deposits.h_wire"
                              ",kc.coin_pub"
                              ",deposits.merchant_pub"
                              ",wire_out.execution_date"
                              ",deposits.amount_with_fee_val"
                              ",deposits.amount_with_fee_frac"
                              ",denom.fee_deposit_val"
                              ",denom.fee_deposit_frac"
                              ",denom.denom_pub"
                              " FROM aggregation_tracking"
                              "    JOIN deposits"
                              "      USING (deposit_serial_id)"
                              "    JOIN known_coins kc"
                              "      USING (known_coin_id)"
                              "    JOIN denominations denom"
                              "      USING (denominations_serial)"
                              "    JOIN wire_out"
                              "      USING (wtid_raw)"
                              " WHERE wtid_raw=$1;",
                              1),
      /* Used in #postgres_lookup_transfer_by_deposit */
      GNUNET_PQ_make_prepare ("lookup_deposit_wtid",
                              "SELECT"
                              " aggregation_tracking.wtid_raw"
                              ",wire_out.execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",denom.fee_deposit_val"
                              ",denom.fee_deposit_frac"
                              " FROM deposits"
                              "    JOIN aggregation_tracking"
                              "      USING (deposit_serial_id)"
                              "    JOIN known_coins"
                              "      USING (known_coin_id)"
                              "    JOIN denominations denom"
                              "      USING (denominations_serial)"
                              "    JOIN wire_out"
                              "      USING (wtid_raw)"
                              " WHERE coin_pub=$1"
                              "  AND h_contract_terms=$2"
                              "  AND h_wire=$3"
                              "  AND merchant_pub=$4;",
                              4),
      /* Used in #postgres_insert_aggregation_tracking */
      GNUNET_PQ_make_prepare ("insert_aggregation_tracking",
                              "INSERT INTO aggregation_tracking "
                              "(deposit_serial_id"
                              ",wtid_raw"
                              ") VALUES "
                              "($1, $2);",
                              2),
      /* Used in #postgres_get_wire_fee() */
      GNUNET_PQ_make_prepare ("get_wire_fee",
                              "SELECT "
                              " start_date"
                              ",end_date"
                              ",wire_fee_val"
                              ",wire_fee_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",master_sig"
                              " FROM wire_fee"
                              " WHERE wire_method=$1"
                              "   AND start_date <= $2"
                              "   AND end_date > $2;",
                              2),
      /* Used in #postgres_insert_wire_fee */
      GNUNET_PQ_make_prepare ("insert_wire_fee",
                              "INSERT INTO wire_fee "
                              "(wire_method"
                              ",start_date"
                              ",end_date"
                              ",wire_fee_val"
                              ",wire_fee_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",master_sig"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8);",
                              8),
      /* Used in #postgres_store_wire_transfer_out */
      GNUNET_PQ_make_prepare ("insert_wire_out",
                              "INSERT INTO wire_out "
                              "(execution_date"
                              ",wtid_raw"
                              ",wire_target"
                              ",exchange_account_section"
                              ",amount_val"
                              ",amount_frac"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6);",
                              6),
      /* Used in #postgres_wire_prepare_data_insert() to store
         wire transfer information before actually committing it with the bank */
      GNUNET_PQ_make_prepare ("wire_prepare_data_insert",
                              "INSERT INTO prewire "
                              "(type"
                              ",buf"
                              ") VALUES "
                              "($1, $2);",
                              2),
      /* Used in #postgres_wire_prepare_data_mark_finished() */
      GNUNET_PQ_make_prepare ("wire_prepare_data_mark_done",
                              "UPDATE prewire"
                              " SET finished=TRUE"
                              " WHERE prewire_uuid=$1;",
                              1),
      /* Used in #postgres_wire_prepare_data_mark_failed() */
      GNUNET_PQ_make_prepare ("wire_prepare_data_mark_failed",
                              "UPDATE prewire"
                              " SET failed=TRUE"
                              " WHERE prewire_uuid=$1;",
                              1),
      /* Used in #postgres_wire_prepare_data_get() */
      GNUNET_PQ_make_prepare ("wire_prepare_data_get",
                              "SELECT"
                              " prewire_uuid"
                              ",type"
                              ",buf"
                              " FROM prewire"
                              " WHERE finished=FALSE"
                              "   AND failed=FALSE"
                              " ORDER BY prewire_uuid ASC"
                              " LIMIT 1;",
                              0),
      /* Used in #postgres_select_deposits_missing_wire */
      GNUNET_PQ_make_prepare ("deposits_get_overdue",
                              "SELECT"
                              " deposit_serial_id"
                              ",coin_pub"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",wire"
                              ",wire_deadline"
                              ",tiny"
                              ",done"
                              " FROM deposits d"
                              " JOIN known_coins USING (known_coin_id)"
                              " WHERE wire_deadline >= $1"
                              " AND wire_deadline < $2"
                              " AND NOT (EXISTS (SELECT 1"
                              "            FROM refunds"
                              "            JOIN deposits dx USING (deposit_serial_id)"
                              "            WHERE (dx.known_coin_id = d.known_coin_id))"
                              "       OR EXISTS (SELECT 1"
                              "            FROM aggregation_tracking"
                              "            WHERE (aggregation_tracking.deposit_serial_id = d.deposit_serial_id)))"
                              " ORDER BY wire_deadline ASC",
                              2),
      /* Used in #postgres_select_wire_out_above_serial_id() */
      GNUNET_PQ_make_prepare ("audit_get_wire_incr",
                              "SELECT"
                              " wireout_uuid"
                              ",execution_date"
                              ",wtid_raw"
                              ",wire_target"
                              ",amount_val"
                              ",amount_frac"
                              " FROM wire_out"
                              " WHERE wireout_uuid>=$1"
                              " ORDER BY wireout_uuid ASC;",
                              1),
      /* Used in #postgres_select_wire_out_above_serial_id_by_account() */
      GNUNET_PQ_make_prepare ("audit_get_wire_incr_by_account",
                              "SELECT"
                              " wireout_uuid"
                              ",execution_date"
                              ",wtid_raw"
                              ",wire_target"
                              ",amount_val"
                              ",amount_frac"
                              " FROM wire_out"
                              " WHERE wireout_uuid>=$1 AND exchange_account_section=$2"
                              " ORDER BY wireout_uuid ASC;",
                              2),
      /* Used in #postgres_insert_recoup_request() to store recoup
         information */
      GNUNET_PQ_make_prepare ("recoup_insert",
                              "WITH rx AS"
                              " (SELECT reserve_out_serial_id"
                              "    FROM reserves_out"
                              "   WHERE h_blind_ev=$7)"
                              "INSERT INTO recoup "
                              "(known_coin_id"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",reserve_out_serial_id"
                              ") SELECT known_coin_id, $2, $3, $4, $5, $6, rx.reserve_out_serial_id"
                              "    FROM known_coins"
                              "   CROSS JOIN rx"
                              "   WHERE coin_pub=$1;",
                              7),
      /* Used in #postgres_insert_recoup_refresh_request() to store recoup-refresh
         information */
      GNUNET_PQ_make_prepare ("recoup_refresh_insert",
                              "WITH rrx AS"
                              " (SELECT rrc_serial"
                              "    FROM refresh_revealed_coins"
                              "   WHERE h_coin_ev=$7)"
                              "INSERT INTO recoup_refresh "
                              "(known_coin_id"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",rrc_serial"
                              ") SELECT known_coin_id, $2, $3, $4, $5, $6, rrx.rrc_serial"
                              "    FROM known_coins"
                              "   CROSS JOIN rrx"
                              "   WHERE coin_pub=$1;",
                              7),
      /* Used in #postgres_select_recoup_above_serial_id() to obtain recoup transactions */
      GNUNET_PQ_make_prepare ("recoup_get_incr",
                              "SELECT"
                              " recoup_uuid"
                              ",timestamp"
                              ",reserves.reserve_pub"
                              ",coins.coin_pub"
                              ",coin_sig"
                              ",coin_blind"
                              ",ro.h_blind_ev"
                              ",denoms.denom_pub_hash"
                              ",coins.denom_sig"
                              ",denoms.denom_pub"
                              ",amount_val"
                              ",amount_frac"
                              " FROM recoup"
                              "    JOIN known_coins coins"
                              "      USING (known_coin_id)"
                              "    JOIN reserves_out ro"
                              "      USING (reserve_out_serial_id)"
                              "    JOIN reserves"
                              "      USING (reserve_uuid)"
                              "    JOIN denominations denoms"
                              "      ON (coins.denominations_serial = denoms.denominations_serial)"
                              " WHERE recoup_uuid>=$1"
                              " ORDER BY recoup_uuid ASC;",
                              1),
      /* Used in #postgres_select_recoup_refresh_above_serial_id() to obtain
         recoup-refresh transactions */
      GNUNET_PQ_make_prepare ("recoup_refresh_get_incr",
                              "SELECT"
                              " recoup_refresh_uuid"
                              ",timestamp"
                              ",old_coins.coin_pub AS old_coin_pub"
                              ",old_denoms.denom_pub_hash AS old_denom_pub_hash"
                              ",new_coins.coin_pub As coin_pub"
                              ",coin_sig"
                              ",coin_blind"
                              ",new_denoms.denom_pub AS denom_pub"
                              ",rrc.h_coin_ev AS h_blind_ev"
                              ",new_denoms.denom_pub_hash"
                              ",new_coins.denom_sig AS denom_sig"
                              ",amount_val"
                              ",amount_frac"
                              " FROM recoup_refresh"
                              "    INNER JOIN refresh_revealed_coins rrc"
                              "      USING (rrc_serial)"
                              "    INNER JOIN refresh_commitments rfc"
                              "      ON (rrc.melt_serial_id = rfc.melt_serial_id)"
                              "    INNER JOIN known_coins old_coins"
                              "      ON (rfc.old_known_coin_id = old_coins.known_coin_id)"
                              "    INNER JOIN known_coins new_coins"
                              "      ON (new_coins.known_coin_id = recoup_refresh.known_coin_id)"
                              "    INNER JOIN denominations new_denoms"
                              "      ON (new_coins.denominations_serial = new_denoms.denominations_serial)"
                              "    INNER JOIN denominations old_denoms"
                              "      ON (old_coins.denominations_serial = old_denoms.denominations_serial)"
                              " WHERE recoup_refresh_uuid>=$1"
                              " ORDER BY recoup_refresh_uuid ASC;",
                              1),
      /* Used in #postgres_select_reserve_closed_above_serial_id() to
         obtain information about closed reserves */
      GNUNET_PQ_make_prepare ("reserves_close_get_incr",
                              "SELECT"
                              " close_uuid"
                              ",reserves.reserve_pub"
                              ",execution_date"
                              ",wtid"
                              ",receiver_account"
                              ",amount_val"
                              ",amount_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              " FROM reserves_close"
                              " JOIN reserves"
                              "   USING (reserve_uuid)"
                              " WHERE close_uuid>=$1"
                              " ORDER BY close_uuid ASC;",
                              1),
      /* Used in #postgres_get_reserve_history() to obtain recoup transactions
         for a reserve */
      GNUNET_PQ_make_prepare ("recoup_by_reserve",
                              "SELECT"
                              " coins.coin_pub"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",denoms.denom_pub_hash"
                              ",coins.denom_sig"
                              " FROM recoup"
                              "    JOIN known_coins coins"
                              "      USING (known_coin_id)"
                              "    JOIN denominations denoms"
                              "      USING (denominations_serial)"
                              "    JOIN reserves_out ro"
                              "      USING (reserve_out_serial_id)"
                              " WHERE ro.reserve_uuid="
                              "   (SELECT reserve_uuid"
                              "     FROM reserves"
                              "    WHERE reserve_pub=$1);",
                              1),
      /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
         affecting old coins of refreshed coins */
      GNUNET_PQ_make_prepare ("recoup_by_old_coin",
                              "SELECT"
                              " coins.coin_pub"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",denoms.denom_pub_hash"
                              ",coins.denom_sig"
                              ",recoup_refresh_uuid"
                              " FROM recoup_refresh"
                              " JOIN known_coins coins"
                              "   USING (known_coin_id)"
                              " JOIN denominations denoms"
                              "   USING (denominations_serial)"
                              " WHERE rrc_serial IN"
                              "   (SELECT rrc.rrc_serial"
                              "    FROM refresh_commitments"
                              "       JOIN refresh_revealed_coins rrc"
                              "           USING (melt_serial_id)"
                              "    WHERE old_known_coin_id="
                              "       (SELECT known_coin_id"
                              "          FROM known_coins"
                              "         WHERE coin_pub=$1));",
                              1),
      /* Used in #postgres_get_reserve_history() */
      GNUNET_PQ_make_prepare ("close_by_reserve",
                              "SELECT"
                              " amount_val"
                              ",amount_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",execution_date"
                              ",receiver_account"
                              ",wtid"
                              " FROM reserves_close"
                              " WHERE reserve_uuid="
                              "   (SELECT reserve_uuid"
                              "     FROM reserves"
                              "    WHERE reserve_pub=$1);",
                              1),
      /* Used in #postgres_get_expired_reserves() */
      GNUNET_PQ_make_prepare ("get_expired_reserves",
                              "SELECT"
                              " expiration_date"
                              ",account_details"
                              ",reserve_pub"
                              ",current_balance_val"
                              ",current_balance_frac"
                              " FROM reserves"
                              " WHERE expiration_date<=$1"
                              "   AND (current_balance_val != 0 "
                              "        OR current_balance_frac != 0)"
                              " ORDER BY expiration_date ASC"
                              " LIMIT 1;",
                              1),
      /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
         for a coin */
      GNUNET_PQ_make_prepare ("recoup_by_coin",
                              "SELECT"
                              " reserves.reserve_pub"
                              ",denoms.denom_pub_hash"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",recoup_uuid"
                              " FROM recoup"
                              " JOIN reserves_out ro"
                              "   USING (reserve_out_serial_id)"
                              " JOIN reserves"
                              "   USING (reserve_uuid)"
                              " JOIN known_coins coins"
                              "   USING (known_coin_id)"
                              " JOIN denominations denoms"
                              "   ON (denoms.denominations_serial = coins.denominations_serial)"
                              " WHERE coins.coin_pub=$1;",
                              1),
      /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
         for a refreshed coin */
      GNUNET_PQ_make_prepare ("recoup_by_refreshed_coin",
                              "SELECT"
                              " old_coins.coin_pub AS old_coin_pub"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",denoms.denom_pub_hash"
                              ",coins.denom_sig"
                              ",recoup_refresh_uuid"
                              " FROM recoup_refresh"
                              "    JOIN refresh_revealed_coins rrc"
                              "      USING (rrc_serial)"
                              "    JOIN refresh_commitments rfc"
                              "      ON (rrc.melt_serial_id = rfc.melt_serial_id)"
                              "    JOIN known_coins old_coins"
                              "      ON (rfc.old_known_coin_id = old_coins.known_coin_id)"
                              "    JOIN known_coins coins"
                              "      ON (recoup_refresh.known_coin_id = coins.known_coin_id)"
                              "    JOIN denominations denoms"
                              "      ON (denoms.denominations_serial = coins.denominations_serial)"
                              " WHERE coins.coin_pub=$1;",
                              1),
      /* Used in #postgres_get_reserve_by_h_blind() */
      GNUNET_PQ_make_prepare ("reserve_by_h_blind",
                              "SELECT"
                              " reserves.reserve_pub"
                              " FROM reserves_out"
                              " JOIN reserves"
                              "   USING (reserve_uuid)"
                              " WHERE h_blind_ev=$1"
                              " LIMIT 1;",
                              1),
      /* Used in #postgres_get_old_coin_by_h_blind() */
      GNUNET_PQ_make_prepare ("old_coin_by_h_blind",
                              "SELECT"
                              " okc.coin_pub AS old_coin_pub"
                              " FROM refresh_revealed_coins rrc"
                              " JOIN refresh_commitments rcom USING (melt_serial_id)"
                              " JOIN known_coins okc ON (rcom.old_known_coin_id = okc.known_coin_id)"
                              " WHERE h_coin_ev=$1"
                              " LIMIT 1;",
                              1),
      /* Used in #postgres_lookup_auditor_timestamp() */
      GNUNET_PQ_make_prepare ("lookup_auditor_timestamp",
                              "SELECT"
                              " last_change"
                              " FROM auditors"
                              " WHERE auditor_pub=$1;",
                              1),
      /* Used in #postgres_lookup_auditor_status() */
      GNUNET_PQ_make_prepare ("lookup_auditor_status",
                              "SELECT"
                              " auditor_url"
                              ",is_active"
                              " FROM auditors"
                              " WHERE auditor_pub=$1;",
                              1),
      /* Used in #postgres_lookup_wire_timestamp() */
      GNUNET_PQ_make_prepare ("lookup_wire_timestamp",
                              "SELECT"
                              " last_change"
                              " FROM wire_accounts"
                              " WHERE payto_uri=$1;",
                              1),
      /* used in #postgres_insert_auditor() */
      GNUNET_PQ_make_prepare ("insert_auditor",
                              "INSERT INTO auditors "
                              "(auditor_pub"
                              ",auditor_name"
                              ",auditor_url"
                              ",is_active"
                              ",last_change"
                              ") VALUES "
                              "($1, $2, $3, true, $4);",
                              4),
      /* used in #postgres_update_auditor() */
      GNUNET_PQ_make_prepare ("update_auditor",
                              "UPDATE auditors"
                              " SET"
                              "  auditor_url=$2"
                              " ,auditor_name=$3"
                              " ,is_active=$4"
                              " ,last_change=$5"
                              " WHERE auditor_pub=$1",
                              5),
      /* used in #postgres_insert_wire() */
      GNUNET_PQ_make_prepare ("insert_wire",
                              "INSERT INTO wire_accounts "
                              "(payto_uri"
                              ",master_sig"
                              ",is_active"
                              ",last_change"
                              ") VALUES "
                              "($1, $2, true, $3);",
                              3),
      /* used in #postgres_update_wire() */
      GNUNET_PQ_make_prepare ("update_wire",
                              "UPDATE wire_accounts"
                              " SET"
                              "  is_active=$2"
                              " ,last_change=$3"
                              " WHERE payto_uri=$1",
                              3),
      /* used in #postgres_update_wire() */
      GNUNET_PQ_make_prepare ("get_wire_accounts",
                              "SELECT"
                              " payto_uri"
                              ",master_sig"
                              " FROM wire_accounts"
                              " WHERE is_active",
                              0),
      /* used in #postgres_update_wire() */
      GNUNET_PQ_make_prepare ("get_wire_fees",
                              "SELECT"
                              " wire_fee_val"
                              ",wire_fee_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",start_date"
                              ",end_date"
                              ",master_sig"
                              " FROM wire_fee"
                              " WHERE wire_method=$1",
                              1),
      /* used in #postgres_insert_signkey_revocation() */
      GNUNET_PQ_make_prepare ("insert_signkey_revocation",
                              "INSERT INTO signkey_revocations "
                              "(esk_serial"
                              ",master_sig"
                              ") SELECT esk_serial, $2 "
                              "    FROM exchange_sign_keys"
                              "   WHERE exchange_pub=$1;",
                              2),
      /* used in #postgres_insert_signkey_revocation() */
      GNUNET_PQ_make_prepare ("lookup_signkey_revocation",
                              "SELECT "
                              " master_sig"
                              " FROM signkey_revocations"
                              " WHERE esk_serial="
                              "   (SELECT esk_serial"
                              "      FROM exchange_sign_keys"
                              "     WHERE exchange_pub=$1);",
                              1),
      /* used in #postgres_insert_signkey() */
      GNUNET_PQ_make_prepare ("insert_signkey",
                              "INSERT INTO exchange_sign_keys "
                              "(exchange_pub"
                              ",valid_from"
                              ",expire_sign"
                              ",expire_legal"
                              ",master_sig"
                              ") VALUES "
                              "($1, $2, $3, $4, $5);",
                              5),
      /* used in #postgres_lookup_signing_key() */
      GNUNET_PQ_make_prepare ("lookup_signing_key",
                              "SELECT"
                              " valid_from"
                              ",expire_sign"
                              ",expire_legal"
                              " FROM exchange_sign_keys"
                              " WHERE exchange_pub=$1",
                              1),
      /* used in #postgres_lookup_denomination_key() */
      GNUNET_PQ_make_prepare ("lookup_denomination_key",
                              "SELECT"
                              " valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"
                              ",coin_frac"
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              " FROM denominations"
                              " WHERE denom_pub_hash=$1;",
                              1),
      /* used in #postgres_insert_auditor_denom_sig() */
      GNUNET_PQ_make_prepare ("insert_auditor_denom_sig",
                              "WITH ax AS"
                              " (SELECT auditor_uuid"
                              "    FROM auditors"
                              "   WHERE auditor_pub=$1)"
                              "INSERT INTO auditor_denom_sigs "
                              "(auditor_uuid"
                              ",denominations_serial"
                              ",auditor_sig"
                              ") SELECT ax.auditor_uuid, denominations_serial, $3 "
                              "    FROM denominations"
                              "   CROSS JOIN ax"
                              "   WHERE denom_pub_hash=$2;",
                              3),
      /* used in #postgres_select_auditor_denom_sig() */
      GNUNET_PQ_make_prepare ("select_auditor_denom_sig",
                              "SELECT"
                              " auditor_sig"
                              " FROM auditor_denom_sigs"
                              " WHERE auditor_uuid="
                              "  (SELECT auditor_uuid"
                              "    FROM auditors"
                              "    WHERE auditor_pub=$1)"
                              " AND denominations_serial="
                              "  (SELECT denominations_serial"
                              "    FROM denominations"
                              "    WHERE denom_pub_hash=$2);",
                              2),
      /* used in #postgres_lookup_wire_fee_by_time() */
      GNUNET_PQ_make_prepare ("lookup_wire_fee_by_time",
                              "SELECT"
                              " wire_fee_val"
                              ",wire_fee_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              " FROM wire_fee"
                              " WHERE wire_method=$1"
                              " AND end_date > $2"
                              " AND start_date < $3;",
                              1),
      /* used in #postgres_commit */
      GNUNET_PQ_make_prepare ("do_commit",
                              "COMMIT",
                              0),
      /* used in #postgres_lookup_serial_by_table() */
      GNUNET_PQ_make_prepare ("select_serial_by_table_denominations",
                              "SELECT"
                              " denominations_serial AS serial"
                              " FROM denominations"
                              " ORDER BY denominations_serial DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_denomination_revocations",
                              "SELECT"
                              " denom_revocations_serial_id AS serial"
                              " FROM denomination_revocations"
                              " ORDER BY denom_revocations_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_reserves",
                              "SELECT"
                              " reserve_uuid AS serial"
                              " FROM reserves"
                              " ORDER BY reserve_uuid DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_reserves_in",
                              "SELECT"
                              " reserve_in_serial_id AS serial"
                              " FROM reserves_in"
                              " ORDER BY reserve_in_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_reserves_close",
                              "SELECT"
                              " close_uuid AS serial"
                              " FROM reserves_close"
                              " ORDER BY close_uuid DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_reserves_out",
                              "SELECT"
                              " reserve_out_serial_id AS serial"
                              " FROM reserves_out"
                              " ORDER BY reserve_out_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_auditors",
                              "SELECT"
                              " auditor_uuid AS serial"
                              " FROM auditors"
                              " ORDER BY auditor_uuid DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_auditor_denom_sigs",
                              "SELECT"
                              " auditor_denom_serial AS serial"
                              " FROM auditor_denom_sigs"
                              " ORDER BY auditor_denom_serial DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_exchange_sign_keys",
                              "SELECT"
                              " esk_serial AS serial"
                              " FROM exchange_sign_keys"
                              " ORDER BY esk_serial DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_signkey_revocations",
                              "SELECT"
                              " signkey_revocations_serial_id AS serial"
                              " FROM signkey_revocations"
                              " ORDER BY signkey_revocations_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_known_coins",
                              "SELECT"
                              " known_coin_id AS serial"
                              " FROM known_coins"
                              " ORDER BY known_coin_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_refresh_commitments",
                              "SELECT"
                              " melt_serial_id AS serial"
                              " FROM refresh_commitments"
                              " ORDER BY melt_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_refresh_revealed_coins",
                              "SELECT"
                              " rrc_serial AS serial"
                              " FROM refresh_revealed_coins"
                              " ORDER BY rrc_serial DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_refresh_transfer_keys",
                              "SELECT"
                              " rtc_serial AS serial"
                              " FROM refresh_transfer_keys"
                              " ORDER BY rtc_serial DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_deposits",
                              "SELECT"
                              " deposit_serial_id AS serial"
                              " FROM deposits"
                              " ORDER BY deposit_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_refunds",
                              "SELECT"
                              " refund_serial_id AS serial"
                              " FROM refunds"
                              " ORDER BY refund_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_wire_out",
                              "SELECT"
                              " wireout_uuid AS serial"
                              " FROM wire_out"
                              " ORDER BY wireout_uuid DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_aggregation_tracking",
                              "SELECT"
                              " aggregation_serial_id AS serial"
                              " FROM aggregation_tracking"
                              " ORDER BY aggregation_serial_id DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_wire_fee",
                              "SELECT"
                              " wire_fee_serial AS serial"
                              " FROM wire_fee"
                              " ORDER BY wire_fee_serial DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_recoup",
                              "SELECT"
                              " recoup_uuid AS serial"
                              " FROM recoup"
                              " ORDER BY recoup_uuid DESC"
                              " LIMIT 1;",
                              0),
      GNUNET_PQ_make_prepare ("select_serial_by_table_recoup_refresh",
                              "SELECT"
                              " recoup_refresh_uuid AS serial"
                              " FROM recoup_refresh"
                              " ORDER BY recoup_refresh_uuid DESC"
                              " LIMIT 1;",
                              0),
      /* For postgres_lookup_records_by_table */
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_denominations",
                              "SELECT"
                              " denominations_serial AS serial"
                              ",denom_pub"
                              ",master_sig"
                              ",valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"
                              ",coin_frac"
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              " FROM denominations"
                              " WHERE denominations_serial > $1"
                              " ORDER BY denominations_serial ASC;",
                              1),
      GNUNET_PQ_make_prepare (
        "select_above_serial_by_table_denomination_revocations",
        "SELECT"
        " denom_revocations_serial_id AS serial"
        ",master_sig"
        ",denominations_serial"
        " FROM denomination_revocations"
        " WHERE denom_revocations_serial_id > $1"
        " ORDER BY denom_revocations_serial_id ASC;",
        1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_reserves",
                              "SELECT"
                              " reserve_uuid AS serial"
                              ",reserve_pub"
                              ",account_details"
                              ",current_balance_val"
                              ",current_balance_frac"
                              ",expiration_date"
                              ",gc_date"
                              " FROM reserves"
                              " WHERE reserve_uuid > $1"
                              " ORDER BY reserve_uuid ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_reserves_in",
                              "SELECT"
                              " reserve_in_serial_id AS serial"
                              ",wire_reference"
                              ",credit_val"
                              ",credit_frac"
                              ",sender_account_details"
                              ",exchange_account_section"
                              ",execution_date"
                              ",reserve_uuid"
                              " FROM reserves_in"
                              " WHERE reserve_in_serial_id > $1"
                              " ORDER BY reserve_in_serial_id ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_reserves_close",
                              "SELECT"
                              " close_uuid AS serial"
                              ",execution_date"
                              ",wtid"
                              ",receiver_account"
                              ",amount_val"
                              ",amount_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",reserve_uuid"
                              " FROM reserves_close"
                              " WHERE close_uuid > $1"
                              " ORDER BY close_uuid ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_reserves_out",
                              "SELECT"
                              " reserve_out_serial_id AS serial"
                              ",h_blind_ev"
                              ",denom_sig"
                              ",reserve_sig"
                              ",execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",reserve_uuid"
                              ",denominations_serial"
                              " FROM reserves_out"
                              " WHERE reserve_out_serial_id > $1"
                              " ORDER BY reserve_out_serial_id ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_auditors",
                              "SELECT"
                              " auditor_uuid AS serial"
                              ",auditor_pub"
                              ",auditor_name"
                              ",auditor_url"
                              ",is_active"
                              ",last_change"
                              " FROM auditors"
                              " WHERE auditor_uuid > $1"
                              " ORDER BY auditor_uuid ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_auditor_denom_sigs",
                              "SELECT"
                              " auditor_denom_serial AS serial"
                              ",auditor_uuid"
                              ",denominations_serial"
                              ",auditor_sig"
                              " FROM auditor_denom_sigs"
                              " WHERE auditor_denom_serial > $1"
                              " ORDER BY auditor_denom_serial ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_exchange_sign_keys",
                              "SELECT"
                              " esk_serial AS serial"
                              ",exchange_pub"
                              ",master_sig"
                              ",valid_from"
                              ",expire_sign"
                              ",expire_legal"
                              " FROM exchange_sign_keys"
                              " WHERE esk_serial > $1"
                              " ORDER BY esk_serial ASC;",
                              1),
      GNUNET_PQ_make_prepare (
        "select_above_serial_by_table_signkey_revocations",
        "SELECT"
        " signkey_revocations_serial_id AS serial"
        ",esk_serial"
        ",master_sig"
        " FROM signkey_revocations"
        " WHERE signkey_revocations_serial_id > $1"
        " ORDER BY signkey_revocations_serial_id ASC;",
        1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_known_coins",
                              "SELECT"
                              " known_coin_id AS serial"
                              ",coin_pub"
                              ",denom_sig"
                              ",denominations_serial"
                              " FROM known_coins"
                              " WHERE known_coin_id > $1"
                              " ORDER BY known_coin_id ASC;",
                              1),
      GNUNET_PQ_make_prepare (
        "select_above_serial_by_table_refresh_commitments",
        "SELECT"
        " melt_serial_id AS serial"
        ",rc"
        ",old_known_coin_id"
        ",old_coin_sig"
        ",amount_with_fee_val"
        ",amount_with_fee_frac"
        ",noreveal_index"
        " FROM refresh_commitments"
        " WHERE melt_serial_id > $1"
        " ORDER BY melt_serial_id ASC;",
        1),
      GNUNET_PQ_make_prepare (
        "select_above_serial_by_table_refresh_revealed_coins",
        "SELECT"
        " rrc_serial AS serial"
        ",freshcoin_index"
        ",link_sig"
        ",coin_ev"
        ",h_coin_ev"
        ",ev_sig"
        ",melt_serial_id"
        ",denominations_serial"
        " FROM refresh_revealed_coins"
        " WHERE rrc_serial > $1"
        " ORDER BY rrc_serial ASC;",
        1),
      GNUNET_PQ_make_prepare (
        "select_above_serial_by_table_refresh_transfer_keys",
        "SELECT"
        " rtc_serial AS serial"
        ",transfer_pub"
        ",transfer_privs"
        ",melt_serial_id"
        " FROM refresh_transfer_keys"
        " WHERE rtc_serial > $1"
        " ORDER BY rtc_serial ASC;",
        1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_deposits",
                              "SELECT"
                              " deposit_serial_id AS serial"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",wallet_timestamp"
                              ",exchange_timestamp"
                              ",refund_deadline"
                              ",wire_deadline"
                              ",merchant_pub"
                              ",h_contract_terms"
                              ",h_wire"
                              ",coin_sig"
                              ",wire"
                              ",tiny"
                              ",done"
                              ",known_coin_id"
                              " FROM deposits"
                              " WHERE deposit_serial_id > $1"
                              " ORDER BY deposit_serial_id ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_refunds",
                              "SELECT"
                              " refund_serial_id AS serial"
                              ",merchant_sig"
                              ",rtransaction_id"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",deposit_serial_id"
                              " FROM refunds"
                              " WHERE refund_serial_id > $1"
                              " ORDER BY refund_serial_id ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_wire_out",
                              "SELECT"
                              " wireout_uuid AS serial"
                              ",execution_date"
                              ",wtid_raw"
                              ",wire_target"
                              ",exchange_account_section"
                              ",amount_val"
                              ",amount_frac"
                              " FROM wire_out"
                              " WHERE wireout_uuid > $1"
                              " ORDER BY wireout_uuid ASC;",
                              1),
      GNUNET_PQ_make_prepare (
        "select_above_serial_by_table_aggregation_tracking",
        "SELECT"
        " aggregation_serial_id AS serial"
        ",deposit_serial_id"
        ",wtid_raw"
        " FROM aggregation_tracking"
        " WHERE aggregation_serial_id > $1"
        " ORDER BY aggregation_serial_id ASC;",
        1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_wire_fee",
                              "SELECT"
                              " wire_fee_serial AS serial"
                              ",wire_method"
                              ",start_date"
                              ",end_date"
                              ",wire_fee_val"
                              ",wire_fee_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",master_sig"
                              " FROM wire_fee"
                              " WHERE wire_fee_serial > $1"
                              " ORDER BY wire_fee_serial ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_recoup",
                              "SELECT"
                              " recoup_uuid AS serial"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",known_coin_id"
                              ",reserve_out_serial_id"
                              " FROM recoup"
                              " WHERE recoup_uuid > $1"
                              " ORDER BY recoup_uuid ASC;",
                              1),
      GNUNET_PQ_make_prepare ("select_above_serial_by_table_recoup_refresh",
                              "SELECT"
                              " recoup_refresh_uuid AS serial"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",known_coin_id"
                              ",rrc_serial"
                              " FROM recoup_refresh"
                              " WHERE recoup_refresh_uuid > $1"
                              " ORDER BY recoup_refresh_uuid ASC;",
                              1),
      /* For postgres_insert_records_by_table */
      GNUNET_PQ_make_prepare ("insert_into_table_denominations",
                              "INSERT INTO denominations"
                              "(denominations_serial"
                              ",denom_pub_hash"
                              ",denom_pub"
                              ",master_sig"
                              ",valid_from"
                              ",expire_withdraw"
                              ",expire_deposit"
                              ",expire_legal"
                              ",coin_val"
                              ",coin_frac"
                              ",fee_withdraw_val"
                              ",fee_withdraw_frac"
                              ",fee_deposit_val"
                              ",fee_deposit_frac"
                              ",fee_refresh_val"
                              ",fee_refresh_frac"
                              ",fee_refund_val"
                              ",fee_refund_frac"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
                              " $11, $12, $13, $14, $15, $16, $17, $18);",
                              18),
      GNUNET_PQ_make_prepare ("insert_into_table_denomination_revocations",
                              "INSERT INTO denomination_revocations"
                              "(denom_revocations_serial_id"
                              ",master_sig"
                              ",denominations_serial"
                              ") VALUES "
                              "($1, $2, $3);",
                              3),
      GNUNET_PQ_make_prepare ("insert_into_table_reserves",
                              "INSERT INTO reserves"
                              "(reserve_uuid"
                              ",reserve_pub"
                              ",account_details"
                              ",current_balance_val"
                              ",current_balance_frac"
                              ",expiration_date"
                              ",gc_date"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7);",
                              7),
      GNUNET_PQ_make_prepare ("insert_into_table_reserves_in",
                              "INSERT INTO reserves_in"
                              "(reserve_in_serial_id"
                              ",wire_reference"
                              ",credit_val"
                              ",credit_frac"
                              ",sender_account_details"
                              ",exchange_account_section"
                              ",execution_date"
                              ",reserve_uuid"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8);",
                              8),
      GNUNET_PQ_make_prepare ("insert_into_table_reserves_close",
                              "INSERT INTO reserves_close"
                              "(close_uuid"
                              ",execution_date"
                              ",wtid"
                              ",receiver_account"
                              ",amount_val"
                              ",amount_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",reserve_uuid"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
                              9),
      GNUNET_PQ_make_prepare ("insert_into_table_reserves_out",
                              "INSERT INTO reserves_out"
                              "(reserve_out_serial_id"
                              ",h_blind_ev"
                              ",denom_sig"
                              ",reserve_sig"
                              ",execution_date"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",reserve_uuid"
                              ",denominations_serial"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
                              9),
      GNUNET_PQ_make_prepare ("insert_into_table_auditors",
                              "INSERT INTO auditors"
                              "(auditor_uuid"
                              ",auditor_pub"
                              ",auditor_name"
                              ",auditor_url"
                              ",is_active"
                              ",last_change"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6);",
                              6),
      GNUNET_PQ_make_prepare ("insert_into_table_auditor_denom_sigs",
                              "INSERT INTO auditor_denom_sigs"
                              "(auditor_denom_serial"
                              ",auditor_uuid"
                              ",denominations_serial"
                              ",auditor_sig"
                              ") VALUES "
                              "($1, $2, $3, $4);",
                              4),
      GNUNET_PQ_make_prepare ("insert_into_table_exchange_sign_keys",
                              "INSERT INTO exchange_sign_keys"
                              "(esk_serial"
                              ",exchange_pub"
                              ",master_sig"
                              ",valid_from"
                              ",expire_sign"
                              ",expire_legal"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6);",
                              6),
      GNUNET_PQ_make_prepare ("insert_into_table_signkey_revocations",
                              "INSERT INTO signkey_revocations"
                              "(signkey_revocations_serial_id"
                              ",esk_serial"
                              ",master_sig"
                              ") VALUES "
                              "($1, $2, $3);",
                              3),
      GNUNET_PQ_make_prepare ("insert_into_table_known_coins",
                              "INSERT INTO known_coins"
                              "(known_coin_id"
                              ",coin_pub"
                              ",denom_sig"
                              ",denominations_serial"
                              ") VALUES "
                              "($1, $2, $3, $4);",
                              4),
      GNUNET_PQ_make_prepare ("insert_into_table_refresh_commitments",
                              "INSERT INTO refresh_commitments"
                              "(melt_serial_id"
                              ",rc"
                              ",old_coin_sig"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",noreveal_index"
                              ",old_known_coin_id"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7);",
                              7),
      GNUNET_PQ_make_prepare ("insert_into_table_refresh_revealed_coins",
                              "INSERT INTO refresh_revealed_coins"
                              "(rrc_serial"
                              ",freshcoin_index"
                              ",link_sig"
                              ",coin_ev"
                              ",h_coin_ev"
                              ",ev_sig"
                              ",denominations_serial"
                              ",melt_serial_id"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8);",
                              8),
      GNUNET_PQ_make_prepare ("insert_into_table_refresh_transfer_keys",
                              "INSERT INTO refresh_transfer_keys"
                              "(rtc_serial"
                              ",transfer_pub"
                              ",transfer_privs"
                              ",melt_serial_id"
                              ") VALUES "
                              "($1, $2, $3, $4);",
                              4),
      GNUNET_PQ_make_prepare ("insert_into_table_deposits",
                              "INSERT INTO deposits"
                              "(deposit_serial_id"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",wallet_timestamp"
                              ",exchange_timestamp"
                              ",refund_deadline"
                              ",wire_deadline"
                              ",merchant_pub"
                              ",h_contract_terms"
                              ",h_wire"
                              ",coin_sig"
                              ",wire"
                              ",tiny"
                              ",done"
                              ",known_coin_id"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
                              " $11, $12, $13, $14, $15);",
                              15),
      GNUNET_PQ_make_prepare ("insert_into_table_refunds",
                              "INSERT INTO refunds"
                              "(refund_serial_id"
                              ",merchant_sig"
                              ",rtransaction_id"
                              ",amount_with_fee_val"
                              ",amount_with_fee_frac"
                              ",deposit_serial_id"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6);",
                              6),
      GNUNET_PQ_make_prepare ("insert_into_table_wire_out",
                              "INSERT INTO wire_out"
                              "(wireout_uuid"
                              ",execution_date"
                              ",wtid_raw"
                              ",wire_target"
                              ",exchange_account_section"
                              ",amount_val"
                              ",amount_frac"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7);",
                              7),
      GNUNET_PQ_make_prepare ("insert_into_table_aggregation_tracking",
                              "INSERT INTO aggregation_tracking"
                              "(aggregation_serial_id"
                              ",deposit_serial_id"
                              ",wtid_raw"
                              ") VALUES "
                              "($1, $2, $3);",
                              3),
      GNUNET_PQ_make_prepare ("insert_into_table_wire_fee",
                              "INSERT INTO wire_fee"
                              "(wire_fee_serial"
                              ",wire_method"
                              ",start_date"
                              ",end_date"
                              ",wire_fee_val"
                              ",wire_fee_frac"
                              ",closing_fee_val"
                              ",closing_fee_frac"
                              ",master_sig"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
                              9),
      GNUNET_PQ_make_prepare ("insert_into_table_recoup",
                              "INSERT INTO recoup"
                              "(recoup_uuid"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",known_coin_id"
                              ",reserve_out_serial_id"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8);",
                              8),
      GNUNET_PQ_make_prepare ("insert_into_table_recoup_refresh",
                              "INSERT INTO recoup_refresh"
                              "(recoup_refresh_uuid"
                              ",coin_sig"
                              ",coin_blind"
                              ",amount_val"
                              ",amount_frac"
                              ",timestamp"
                              ",known_coin_id"
                              ",rrc_serial"
                              ") VALUES "
                              "($1, $2, $3, $4, $5, $6, $7, $8);",
                              8),

      /* Used in #postgres_begin_shard() */
      GNUNET_PQ_make_prepare ("get_open_shard",
                              "SELECT"
                              " start_row"
                              ",end_row"
                              " FROM work_shards"
                              " WHERE job_name=$1"
                              "   AND last_attempt<$2"
                              "   AND completed=FALSE"
                              " ORDER BY last_attempt ASC"
                              " LIMIT 1;",
                              2),
      GNUNET_PQ_make_prepare ("reclaim_shard",
                              "UPDATE work_shards"
                              " SET last_attempt=$2"
                              " WHERE job_name=$1"
                              "   AND start_row=$3"
                              "   AND end_row=$4",
                              4),
      GNUNET_PQ_make_prepare ("get_last_shard",
                              "SELECT"
                              " end_row"
                              " FROM work_shards"
                              " WHERE job_name=$1"
                              " ORDER BY end_row DESC"
                              " LIMIT 1;",
                              1),
      GNUNET_PQ_make_prepare ("claim_next_shard",
                              "INSERT INTO work_shards"
                              "(job_name"
                              ",last_attempt"
                              ",start_row"
                              ",end_row"
                              ") VALUES "
                              "($1, $2, $3, $4);",
                              4),
      /* Used in #postgres_complete_shard() */
      GNUNET_PQ_make_prepare ("complete_shard",
                              "UPDATE work_shards"
                              " SET completed=TRUE"
                              " WHERE job_name=$1"
                              "   AND start_row=$2"
                              "   AND end_row=$3",
                              3),
      GNUNET_PQ_PREPARED_STATEMENT_END
    };

    db_conn = GNUNET_PQ_connect_with_cfg (pc->cfg,
                                          "exchangedb-postgres",
                                          NULL,
                                          es,
                                          ps);
  }
  if (NULL == db_conn)
    return NULL;
  session = GNUNET_new (struct TALER_EXCHANGEDB_Session);
  session->conn = db_conn;
  if (pthread_equal (pc->main_self,
                     pthread_self ()))
  {
    pc->main_session = session;
  }
  else
  {
    if (0 != pthread_setspecific (pc->db_conn_threadlocal,
                                  session))
    {
      GNUNET_break (0);
      GNUNET_PQ_disconnect (db_conn);
      GNUNET_free (session);
      return NULL;
    }
  }
  return session;
}


/**
 * Do a pre-flight check that we are not in an uncommitted transaction.
 * If we are, try to commit the previous transaction and output a warning.
 * Does not return anything, as we will continue regardless of the outcome.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 */
static void
postgres_preflight (void *cls,
                    struct TALER_EXCHANGEDB_Session *session);

/**
 * Start a transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @param name unique name identifying the transaction (for debugging)
 *             must point to a constant
 * @return #GNUNET_OK on success
 */
static int
postgres_start (void *cls,
                struct TALER_EXCHANGEDB_Session *session,
                const char *name)
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("START TRANSACTION ISOLATION LEVEL SERIALIZABLE"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting transaction named: %s\n",
              name);
  postgres_preflight (cls,
                      session);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting transaction on %p\n",
              session->conn);
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (session->conn,
                                 es))
  {
    TALER_LOG_ERROR ("Failed to start transaction\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  session->transaction_name = name;
  return GNUNET_OK;
}


/**
 * Roll back the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 */
static void
postgres_rollback (void *cls,
                   struct TALER_EXCHANGEDB_Session *session)
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Rolling back transaction on %p\n",
              session->conn);
  GNUNET_break (GNUNET_OK ==
                GNUNET_PQ_exec_statements (session->conn,
                                           es));
  session->transaction_name = NULL;
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @return final transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_commit (void *cls,
                 struct TALER_EXCHANGEDB_Session *session)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "do_commit",
                                           params);
  session->transaction_name = NULL;
  return qs;
}


/**
 * Do a pre-flight check that we are not in an uncommitted transaction.
 * If we are, try to commit the previous transaction and output a warning.
 * Does not return anything, as we will continue regardless of the outcome.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 */
static void
postgres_preflight (void *cls,
                    struct TALER_EXCHANGEDB_Session *session)
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  (void) cls;
  if (NULL == session)
  {
    GNUNET_break (0);
    return;
  }
  if (NULL == session->transaction_name)
    return; /* all good */
  if (GNUNET_OK ==
      GNUNET_PQ_exec_statements (session->conn,
                                 es))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check rolled back transaction `%s'!\n",
                session->transaction_name);
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "BUG: Preflight check failed to rollback transaction `%s'!\n",
                session->transaction_name);
  }
  session->transaction_name = NULL;
}


/**
 * Insert a denomination key's public information into the database for
 * reference by auditors and other consistency checks.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub the public key used for signing coins of this denomination
 * @param issue issuing information with value, fees and other info about the coin
 * @return status of the query
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_info (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&issue->properties.denom_hash),
    GNUNET_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    GNUNET_PQ_query_param_auto_from_type (&issue->signature),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.start),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_withdraw),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_deposit),
    TALER_PQ_query_param_absolute_time_nbo (&issue->properties.expire_legal),
    TALER_PQ_query_param_amount_nbo (&issue->properties.value),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_withdraw),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_deposit),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refresh),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fee_refund),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
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

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "denomination_insert",
                                             params);
}


/**
 * Fetch information about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param denom_pub_hash hash of the public key used for signing coins of this denomination
 * @param[out] issue set to issue information with value, fees and other info about the coin
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_info (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *denom_pub_hash,
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          &issue->signature),
    TALER_PQ_result_spec_absolute_time_nbo ("valid_from",
                                            &issue->properties.start),
    TALER_PQ_result_spec_absolute_time_nbo ("expire_withdraw",
                                            &issue->properties.expire_withdraw),
    TALER_PQ_result_spec_absolute_time_nbo ("expire_deposit",
                                            &issue->properties.expire_deposit),
    TALER_PQ_result_spec_absolute_time_nbo ("expire_legal",
                                            &issue->properties.expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("coin",
                                     &issue->properties.value),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_withdraw",
                                     &issue->properties.fee_withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_deposit",
                                     &issue->properties.fee_deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refresh",
                                     &issue->properties.fee_refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refund",
                                     &issue->properties.fee_refund),
    GNUNET_PQ_result_spec_end
  };

  memset (&issue->properties.master,
          0,
          sizeof (issue->properties.master));
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "denomination_get",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;
  issue->properties.purpose.size = htonl (sizeof (struct
                                                  TALER_DenominationKeyValidityPS));
  issue->properties.purpose.purpose = htonl (
    TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  issue->properties.denom_hash = *denom_pub_hash;
  return qs;
}


/**
 * Closure for #domination_cb_helper()
 */
struct DenomIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_DenominationCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_iterate_denomination_info().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct DenomIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
domination_cb_helper (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct DenomIteratorContext *dic = cls;
  struct PostgresClosure *pg = dic->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_DenominationKeyInformationP issue;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &issue.signature),
      TALER_PQ_result_spec_absolute_time_nbo ("valid_from",
                                              &issue.properties.start),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_withdraw",
                                              &issue.properties.expire_withdraw),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_deposit",
                                              &issue.properties.expire_deposit),
      TALER_PQ_result_spec_absolute_time_nbo ("expire_legal",
                                              &issue.properties.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("coin",
                                       &issue.properties.value),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_withdraw",
                                       &issue.properties.fee_withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_deposit",
                                       &issue.properties.fee_deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refresh",
                                       &issue.properties.fee_refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refund",
                                       &issue.properties.fee_refund),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_end
    };

    memset (&issue.properties.master,
            0,
            sizeof (issue.properties.master));
    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    issue.properties.purpose.size
      = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
    issue.properties.purpose.purpose
      = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
    GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key,
                                       &issue.properties.denom_hash);
    dic->cb (dic->cb_cls,
             &denom_pub,
             &issue);
    GNUNET_CRYPTO_rsa_public_key_free (denom_pub.rsa_public_key);
  }
}


/**
 * Fetch information about all known denomination keys.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @param cb function to call on each denomination key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_denomination_info (void *cls,
                                    struct TALER_EXCHANGEDB_Session *session,
                                    TALER_EXCHANGEDB_DenominationCallback cb,
                                    void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pc
  };

  if (NULL == session)
    session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               "denomination_iterate",
                                               params,
                                               &domination_cb_helper,
                                               &dic);
}


/**
 * Closure for #dominations_cb_helper()
 */
struct DenomsIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_DenominationsCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_iterate_denominations().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct DenomsIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
dominations_cb_helper (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct DenomsIteratorContext *dic = cls;
  struct PostgresClosure *pg = dic->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_HashCode h_denom_pub;
    uint8_t revoked;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
      GNUNET_PQ_result_spec_auto_from_type ("revoked",
                                            &revoked),
      TALER_PQ_result_spec_absolute_time ("valid_from",
                                          &meta.start),
      TALER_PQ_result_spec_absolute_time ("expire_withdraw",
                                          &meta.expire_withdraw),
      TALER_PQ_result_spec_absolute_time ("expire_deposit",
                                          &meta.expire_deposit),
      TALER_PQ_result_spec_absolute_time ("expire_legal",
                                          &meta.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                   &meta.value),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                   &meta.fee_withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &meta.fee_deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                   &meta.fee_refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                   &meta.fee_refund),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key,
                                       &h_denom_pub);
    dic->cb (dic->cb_cls,
             &denom_pub,
             &h_denom_pub,
             &meta,
             &master_sig,
             (0 != revoked));
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
* Function called to invoke @a cb on every known denomination key (revoked
* and non-revoked) that has been signed by the master key. Runs in its own
* read-only transaction (hence no session provided).
*
*
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each denomination key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_denominations (void *cls,
                                TALER_EXCHANGEDB_DenominationsCallback cb,
                                void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pc
  };
  struct TALER_EXCHANGEDB_Session *session;

  session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               "select_denominations",
                                               params,
                                               &dominations_cb_helper,
                                               &dic);
}


/**
 * Closure for #signkeys_cb_helper()
 */
struct SignkeysIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_ActiveSignkeysCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

};


/**
 * Helper function for #postgres_iterate_active_signkeys().
 * Calls the callback with each signkey.
 *
 * @param cls a `struct SignkeysIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
signkeys_cb_helper (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct SignkeysIteratorContext *dic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_SignkeyMetaData meta;
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
      GNUNET_PQ_result_spec_auto_from_type ("exchange_pub",
                                            &exchange_pub),
      TALER_PQ_result_spec_absolute_time ("valid_from",
                                          &meta.start),
      TALER_PQ_result_spec_absolute_time ("expire_sign",
                                          &meta.expire_sign),
      TALER_PQ_result_spec_absolute_time ("expire_legal",
                                          &meta.expire_legal),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    dic->cb (dic->cb_cls,
             &exchange_pub,
             &meta,
             &master_sig);
  }
}


/**
 * Function called to invoke @a cb on every non-revoked exchange signing key
 * that has been signed by the master key.  Revoked and (for signing!)
 * expired keys are skipped. Runs in its own read-only transaction (hence no
 * session provided).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each signing key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_active_signkeys (void *cls,
                                  TALER_EXCHANGEDB_ActiveSignkeysCallback cb,
                                  void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct SignkeysIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };
  struct TALER_EXCHANGEDB_Session *session;

  now = GNUNET_TIME_absolute_get ();
  session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               "select_signkeys",
                                               params,
                                               &signkeys_cb_helper,
                                               &dic);
}


/**
 * Closure for #auditors_cb_helper()
 */
struct AuditorsIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_AuditorsCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;

};


/**
 * Helper function for #postgres_iterate_active_auditors().
 * Calls the callback with each auditor.
 *
 * @param cls a `struct SignkeysIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
auditors_cb_helper (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct AuditorsIteratorContext *dic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_AuditorPublicKeyP auditor_pub;
    char *auditor_url;
    char *auditor_name;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("auditor_pub",
                                            &auditor_pub),
      GNUNET_PQ_result_spec_string ("auditor_url",
                                    &auditor_url),
      GNUNET_PQ_result_spec_string ("auditor_name",
                                    &auditor_name),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    dic->cb (dic->cb_cls,
             &auditor_pub,
             auditor_url,
             auditor_name);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called to invoke @a cb on every active auditor. Disabled
 * auditors are skipped. Runs in its own read-only transaction (hence no
 * session provided).
  *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each active auditor
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_active_auditors (void *cls,
                                  TALER_EXCHANGEDB_AuditorsCallback cb,
                                  void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct AuditorsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };
  struct TALER_EXCHANGEDB_Session *session;

  session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               "select_auditors",
                                               params,
                                               &auditors_cb_helper,
                                               &dic);
}


/**
 * Closure for #auditor_denoms_cb_helper()
 */
struct AuditorDenomsIteratorContext
{
  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_AuditorDenominationsCallback cb;

  /**
   * Closure to pass to @e cb
   */
  void *cb_cls;
};


/**
 * Helper function for #postgres_iterate_auditor_denominations().
 * Calls the callback with each auditor and denomination pair.
 *
 * @param cls a `struct AuditorDenomsIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
auditor_denoms_cb_helper (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct AuditorDenomsIteratorContext *dic = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_AuditorPublicKeyP auditor_pub;
    struct GNUNET_HashCode h_denom_pub;
    struct TALER_AuditorSignatureP auditor_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("auditor_pub",
                                            &auditor_pub),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &h_denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("auditor_sig",
                                            &auditor_sig),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      return;
    }
    dic->cb (dic->cb_cls,
             &auditor_pub,
             &h_denom_pub,
             &auditor_sig);
  }
}


/**
 * Function called to invoke @a cb on every denomination with an active
 * auditor. Disabled auditors and denominations without auditor are
 * skipped. Runs in its own read-only transaction (hence no session
 * provided).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each active auditor
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_auditor_denominations (
  void *cls,
  TALER_EXCHANGEDB_AuditorDenominationsCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct AuditorDenomsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };
  struct TALER_EXCHANGEDB_Session *session;

  session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               "select_auditor_denoms",
                                               params,
                                               &auditor_denoms_cb_helper,
                                               &dic);
}


/**
 * Get the summary of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param[in,out] reserve the reserve data.  The public key of the reserve should be
 *          set in this structure; it is used to query the database.  The balance
 *          and expiration are then filled accordingly.
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_reserves_get (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance", &reserve->balance),
    TALER_PQ_result_spec_absolute_time ("expiration_date", &reserve->expiry),
    TALER_PQ_result_spec_absolute_time ("gc_date", &reserve->gc),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "reserves_get",
                                                   params,
                                                   rs);
}


/**
 * Updates a reserve with the data from the given reserve structure.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection
 * @param reserve the reserve structure whose data will be used to update the
 *          corresponding record in the database.
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserves_update (void *cls,
                 struct TALER_EXCHANGEDB_Session *session,
                 const struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&reserve->expiry),
    TALER_PQ_query_param_absolute_time (&reserve->gc),
    TALER_PQ_query_param_amount (&reserve->balance),
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "reserve_update",
                                             params);
}


/**
 * Insert an incoming transaction into reserves.  New reserves are also created
 * through this function.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session the database connection handle
 * @param reserve_pub public key of the reserve
 * @param balance the amount that has to be added to the reserve
 * @param execution_time when was the amount added
 * @param sender_account_details account information for the sender (payto://-URL)
 * @param exchange_account_section name of the section in the configuration for the exchange's
 *                       account into which the deposit was made
 * @param wire_ref unique reference identifying the wire transfer
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_reserves_in_insert (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Absolute execution_time,
                             const char *sender_account_details,
                             const char *exchange_account_section,
                             uint64_t wire_ref)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs1;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Absolute expiry;

  reserve.pub = *reserve_pub;
  expiry = GNUNET_TIME_absolute_add (execution_time,
                                     pg->idle_reserve_expiration_time);
  (void) GNUNET_TIME_round_abs (&expiry);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating reserve %s with expiration in %s\n",
              TALER_B2S (reserve_pub),
              GNUNET_STRINGS_relative_time_to_string (
                pg->idle_reserve_expiration_time,
                GNUNET_NO));
  /* Optimistically assume this is a new reserve, create balance for the first
     time; we do this before adding the actual transaction to "reserves_in",
     as for a new reserve it can't be a duplicate 'add' operation, and as
     the 'add' operation may need the reserve entry as a foreign key. */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      GNUNET_PQ_query_param_string (sender_account_details),
      TALER_PQ_query_param_amount (balance),
      TALER_PQ_query_param_absolute_time (&expiry),
      TALER_PQ_query_param_absolute_time (&expiry),
      GNUNET_PQ_query_param_end
    };

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    /* Note: query uses 'on conflict do nothing' */
    qs1 = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                              "reserve_create",
                                              params);
    if (qs1 < 0)
      return qs1;
  }

  /* Create new incoming transaction, "ON CONFLICT DO NOTHING"
     is again used to guard against duplicates. */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserve.pub),
      GNUNET_PQ_query_param_uint64 (&wire_ref),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_string (exchange_account_section),
      GNUNET_PQ_query_param_string (sender_account_details),
      TALER_PQ_query_param_absolute_time (&execution_time),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs2;

    qs2 = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                              "reserves_in_add_transaction",
                                              params);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs2)
    {
      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs2);
      return qs2;
    }
    if (0 >= qs2)
    {
      /* Transaction was already known or error. We are finished. */
      return qs2;
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs1)
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT; /* new reserve, we are finished */

  /* we were wrong with our optimistic assumption:
     reserve does exist, need to do an update instead */
  {
    enum GNUNET_DB_QueryStatus reserve_exists;

    reserve_exists = postgres_reserves_get (cls,
                                            session,
                                            &reserve);
    switch (reserve_exists)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return reserve_exists;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      return reserve_exists;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      /* First we got a conflict, but then we cannot select? Very strange. */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_SOFT_ERROR;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* continued below */
      break;
    }
  }

  {
    struct TALER_EXCHANGEDB_Reserve updated_reserve;
    enum GNUNET_DB_QueryStatus qs3;

    /* If the reserve already existed, we need to still update the
       balance; we do this after checking for duplication, as
       otherwise we might have to actually pay the cost to roll this
       back for duplicate transactions; like this, we should virtually
       never actually have to rollback anything. */
    updated_reserve.pub = reserve.pub;
    if (0 >
        TALER_amount_add (&updated_reserve.balance,
                          &reserve.balance,
                          balance))
    {
      /* currency overflow or incompatible currency */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Attempt to deposit incompatible amount into reserve\n");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    updated_reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                                       reserve.expiry);
    (void) GNUNET_TIME_round_abs (&updated_reserve.expiry);
    updated_reserve.gc = GNUNET_TIME_absolute_max (updated_reserve.expiry,
                                                   reserve.gc);
    (void) GNUNET_TIME_round_abs (&updated_reserve.gc);
    qs3 = reserves_update (cls,
                           session,
                           &updated_reserve);
    switch (qs3)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return qs3;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      return qs3;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      /* How can the UPDATE not work here? Very strange. */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* continued below */
      break;
    }
    return qs3;
  }
}


/**
 * Obtain the most recent @a wire_reference that was inserted via @e reserves_in_insert.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session the database session handle
 * @param exchange_account_name name of the section in the exchange's configuration
 *                       for the account that we are tracking here
 * @param[out] wire_reference set to unique reference identifying the wire transfer
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_latest_reserve_in_reference (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const char *exchange_account_name,
  uint64_t *wire_reference)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (exchange_account_name),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                  wire_reference),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "reserves_in_get_latest_wire_reference",
                                                   params,
                                                   rs);
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
 * @return statement execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_withdraw_info (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_blind,
  struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &collectable->denom_pub_hash),
    GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                         &collectable->sig.rsa_signature),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                          &collectable->reserve_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          &collectable->reserve_pub),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &collectable->amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &collectable->withdraw_fee),
    GNUNET_PQ_result_spec_end
  };
#if EXPLICIT_LOCKS
  struct GNUNET_PQ_QueryParam no_params[] = {
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  if (0 > (qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                                    "lock_withdraw",
                                                    no_params)))
    return qs;
#endif
  collectable->h_coin_envelope = *h_blind;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_withdraw_info",
                                                   params,
                                                   rs);
}


/**
 * Store collectable bit coin under the corresponding
 * hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection to use
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_withdraw_info (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  struct PostgresClosure *pg = cls;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute expiry;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    GNUNET_PQ_query_param_auto_from_type (&collectable->denom_pub_hash),
    GNUNET_PQ_query_param_rsa_signature (collectable->sig.rsa_signature),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    TALER_PQ_query_param_absolute_time (&now),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "insert_withdraw_info",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* update reserve balance */
  reserve.pub = collectable->reserve_pub;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      (qs = postgres_reserves_get (cls,
                                   session,
                                   &reserve)))
  {
    /* Should have been checked before we got here... */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    return qs;
  }
  if (0 >
      TALER_amount_subtract (&reserve.balance,
                             &reserve.balance,
                             &collectable->amount_with_fee))
  {
    /* The reserve history was checked to make sure there is enough of a balance
       left before we tried this; however, concurrent operations may have changed
       the situation by now, causing us to fail here. As reserves can no longer
       be topped up, retrying should not help either.  */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Withdrawal from reserve `%s' refused due to insufficient balance.\n",
                TALER_B2S (&collectable->reserve_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  expiry = GNUNET_TIME_absolute_add (now,
                                     pg->legal_reserve_expiration_time);
  reserve.gc = GNUNET_TIME_absolute_max (expiry,
                                         reserve.gc);
  (void) GNUNET_TIME_round_abs (&reserve.gc);
  qs = reserves_update (cls,
                        session,
                        &reserve);
  GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * Closure for callbacks invoked via #postgres_get_reserve_history.
 */
struct ReserveHistoryContext
{

  /**
   * Which reserve are we building the history for?
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Where we build the history.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

  /**
   * Tail of @e rh list.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh_tail;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious internal errors during
   * the callbacks.
   */
  int status;
};


/**
 * Append and return a fresh element to the reserve
 * history kept in @a rhc.
 *
 * @param rhc where the history is kept
 * @return the fresh element that was added
 */
static struct TALER_EXCHANGEDB_ReserveHistory *
append_rh (struct ReserveHistoryContext *rhc)
{
  struct TALER_EXCHANGEDB_ReserveHistory *tail;

  tail = GNUNET_new (struct TALER_EXCHANGEDB_ReserveHistory);
  if (NULL != rhc->rh_tail)
  {
    rhc->rh_tail->next = tail;
    rhc->rh_tail = tail;
  }
  else
  {
    rhc->rh_tail = tail;
    rhc->rh = tail;
  }
  return tail;
}


/**
 * Add bank transfers to result set for #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_bank_to_exchange (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_BankTransfer *bt;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    bt = GNUNET_new (struct TALER_EXCHANGEDB_BankTransfer);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                      &bt->wire_reference),
        TALER_PQ_RESULT_SPEC_AMOUNT ("credit",
                                     &bt->amount),
        TALER_PQ_result_spec_absolute_time ("execution_date",
                                            &bt->execution_date),
        GNUNET_PQ_result_spec_string ("sender_account_details",
                                      &bt->sender_account_details),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (bt);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    bt->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE;
    tail->details.bank = bt;
  }   /* end of 'while (0 < rows)' */
}


/**
 * Add coin withdrawals to result set for #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_withdraw_coin (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    cbc = GNUNET_new (struct TALER_EXCHANGEDB_CollectableBlindcoin);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                              &cbc->h_coin_envelope),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &cbc->denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                             &cbc->sig.rsa_signature),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &cbc->reserve_sig),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &cbc->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                     &cbc->withdraw_fee),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (cbc);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    cbc->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_WITHDRAW_COIN;
    tail->details.withdraw = cbc;
  }
}


/**
 * Add recoups to result set for #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_recoup (void *cls,
            PGresult *result,
            unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_Recoup *recoup;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_Recoup);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                              &recoup->coin.coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature (
          "denom_sig",
          &recoup->coin.denom_sig.rsa_signature),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    recoup->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_RECOUP_COIN;
    tail->details.recoup = recoup;
  }   /* end of 'while (0 < rows)' */
}


/**
 * Add exchange-to-bank transfers to result set for
 * #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_exchange_to_bank (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_ClosingTransfer *closing;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    closing = GNUNET_new (struct TALER_EXCHANGEDB_ClosingTransfer);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &closing->amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                     &closing->closing_fee),
        TALER_PQ_result_spec_absolute_time ("execution_date",
                                            &closing->execution_date),
        GNUNET_PQ_result_spec_string ("receiver_account",
                                      &closing->receiver_account_details),
        GNUNET_PQ_result_spec_auto_from_type ("wtid",
                                              &closing->wtid),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (closing);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    closing->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK;
    tail->details.closing = closing;
  }   /* end of 'while (0 < rows)' */
}


/**
 * Get all of the transaction history associated with the specified
 * reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session connection to use
 * @param reserve_pub public key of the reserve
 * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_history (void *cls,
                              struct TALER_EXCHANGEDB_Session *session,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              struct TALER_EXCHANGEDB_ReserveHistory **rhp)
{
  struct PostgresClosure *pg = cls;
  struct ReserveHistoryContext rhc;
  struct
  {
    /**
     * Name of the prepared statement to run.
     */
    const char *statement;
    /**
     * Function to use to process the results.
     */
    GNUNET_PQ_PostgresResultHandler cb;
  } work[] = {
    /** #TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE */
    { "reserves_in_get_transactions",
      add_bank_to_exchange },
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup_by_reserve",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve",
      &add_exchange_to_bank },
    /* List terminator */
    { NULL,
      NULL }
  };
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };

  rhc.reserve_pub = reserve_pub;
  rhc.rh = NULL;
  rhc.rh_tail = NULL;
  rhc.pg = pg;
  rhc.status = GNUNET_OK;
  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* make static analysis happy */
  for (unsigned int i = 0; NULL != work[i].cb; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               work[i].statement,
                                               params,
                                               work[i].cb,
                                               &rhc);
    if ( (0 > qs) ||
         (GNUNET_OK != rhc.status) )
      break;
  }
  if ( (qs < 0) ||
       (rhc.status != GNUNET_OK) )
  {
    common_free_reserve_history (cls,
                                 rhc.rh);
    rhc.rh = NULL;
    if (qs >= 0)
    {
      /* status == SYSERR is a very hard error... */
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  *rhp = rhc.rh;
  return qs;
}


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param deposit deposit to search for
 * @param check_extras whether to check extra fields match or not
 * @param[out] deposit_fee set to the deposit fee the exchange charged
 * @param[out] exchange_timestamp set to the time when the exchange received the deposit
 * @return 1 if we know this operation,
 *         0 if this exact deposit is unknown to us,
 *         otherwise transaction error status
 */
static enum GNUNET_DB_QueryStatus
postgres_have_deposit (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_EXCHANGEDB_Deposit *deposit,
                       int check_extras,
                       struct TALER_Amount *deposit_fee,
                       struct GNUNET_TIME_Absolute *exchange_timestamp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_end
  };
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &deposit2.amount_with_fee),
    TALER_PQ_result_spec_absolute_time ("wallet_timestamp",
                                        &deposit2.timestamp),
    TALER_PQ_result_spec_absolute_time ("exchange_timestamp",
                                        exchange_timestamp),
    TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                        &deposit2.refund_deadline),
    TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                        &deposit2.wire_deadline),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 deposit_fee),
    GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                          &deposit2.h_wire),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;
#if EXPLICIT_LOCKS
  struct GNUNET_PQ_QueryParam no_params[] = {
    GNUNET_PQ_query_param_end
  };

  if (0 > (qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                                    "lock_deposit",
                                                    no_params)))
    return qs;
#endif
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting deposits for coin %s\n",
              TALER_B2S (&deposit->coin.coin_pub));
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "get_deposit",
                                                 params,
                                                 rs);
  if (0 >= qs)
    return qs;
  /* Now we check that the other information in @a deposit
     also matches, and if not report inconsistencies. */
  if ( ( (check_extras) &&
         ( (0 != TALER_amount_cmp (&deposit->amount_with_fee,
                                   &deposit2.amount_with_fee)) ||
           (deposit->timestamp.abs_value_us !=
            deposit2.timestamp.abs_value_us) ) ) ||
       (deposit->refund_deadline.abs_value_us !=
        deposit2.refund_deadline.abs_value_us) ||
       (0 != GNUNET_memcmp (&deposit->h_wire,
                            &deposit2.h_wire) ) )
  {
    /* Inconsistencies detected! Does not match!  (We might want to
       expand the API with a 'get_deposit' function to return the
       original transaction details to be used for an error message
       in the future!) #3838 */
    return 0;   /* Counts as if the transaction was not there */
  }
  return 1;
}


/**
 * Mark a deposit as tiny, thereby declaring that it cannot be
 * executed by itself and should no longer be returned by
 * @e iterate_ready_deposits()
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param rowid identifies the deposit row to modify
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_deposit_tiny (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "mark_deposit_tiny",
                                             params);
}


/**
 * Test if a deposit was marked as done, thereby declaring that it cannot be
 * refunded anymore.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param coin_pub the coin to check for deposit
 * @param merchant_pub merchant to receive the deposit
 * @param h_contract_terms contract terms of the deposit
 * @param h_wire hash of the merchant's wire details
 * @return #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT if is is marked done,
 *         #GNUNET_DB_STATUS_SUCCESS_NO_RESULTS if not,
 *         otherwise transaction error status (incl. deposit unknown)
 */
static enum GNUNET_DB_QueryStatus
postgres_test_deposit_done (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_CoinSpendPublicKeyP *coin_pub,
                            const struct TALER_MerchantPublicKeyP *merchant_pub,
                            const struct GNUNET_HashCode *h_contract_terms,
                            const struct GNUNET_HashCode *h_wire)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_end
  };
  uint8_t done = 0;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("done",
                                          &done),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "test_deposit_done",
                                                 params,
                                                 rs);
  if (qs < 0)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return GNUNET_DB_STATUS_HARD_ERROR; /* deposit MUST exist */
  return (done
          ? GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
          : GNUNET_DB_STATUS_SUCCESS_NO_RESULTS);
}


/**
 * Mark a deposit as done, thereby declaring that it cannot be
 * executed at all anymore, and should no longer be returned by
 * @e iterate_ready_deposits() or @e iterate_matching_deposits().
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param rowid identifies the deposit row to modify
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_deposit_done (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "mark_deposit_done",
                                             params);
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_ready_deposit (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            TALER_EXCHANGEDB_DepositIterator deposit_cb,
                            void *deposit_cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount deposit_fee;
  struct GNUNET_TIME_Absolute wire_deadline;
  struct GNUNET_TIME_Absolute wallet_timestamp;
  struct GNUNET_TIME_Absolute exchange_timestamp;
  struct GNUNET_HashCode h_contract_terms;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  uint64_t serial_id;
  json_t *wire;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                  &serial_id),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &deposit_fee),
    TALER_PQ_result_spec_absolute_time ("exchange_timestamp",
                                        &exchange_timestamp),
    TALER_PQ_result_spec_absolute_time ("wallet_timestamp",
                                        &wallet_timestamp),
    TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                        &wire_deadline),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          &h_contract_terms),
    GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                          &merchant_pub),
    GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                          &coin_pub),
    TALER_PQ_result_spec_json ("wire",
                               &wire),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) GNUNET_TIME_round_abs (&now);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Finding ready deposits by deadline %s (%llu)\n",
              GNUNET_STRINGS_absolute_time_to_string (now),
              (unsigned long long) now.abs_value_us);

  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "deposits_get_ready",
                                                 params,
                                                 rs);
  if (qs <= 0)
    return qs;

  qs = deposit_cb (deposit_cb_cls,
                   serial_id,
                   exchange_timestamp,
                   wallet_timestamp,
                   &merchant_pub,
                   &coin_pub,
                   &amount_with_fee,
                   &deposit_fee,
                   &h_contract_terms,
                   wire_deadline,
                   wire);
  GNUNET_PQ_cleanup_result (rs);
  return qs;
}


/**
 * Closure for #match_deposit_cb().
 */
struct MatchingDepositContext
{
  /**
   * Function to call for each result
   */
  TALER_EXCHANGEDB_MatchingDepositIterator deposit_cb;

  /**
   * Closure for @e deposit_cb.
   */
  void *deposit_cb_cls;

  /**
   * Public key of the merchant against which we are matching.
   */
  const struct TALER_MerchantPublicKeyP *merchant_pub;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Maximum number of results to return.
   */
  uint32_t limit;

  /**
   * Loop counter, actual number of results returned.
   */
  unsigned int i;

  /**
   * Set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function for #postgres_iterate_matching_deposits().
 * To be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct MatchingDepositContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
match_deposit_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct MatchingDepositContext *mdc = cls;
  struct PostgresClosure *pg = mdc->pg;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Found %u/%u matching deposits\n",
              num_results,
              mdc->limit);
  num_results = GNUNET_MIN (num_results,
                            mdc->limit);
  for (mdc->i = 0; mdc->i<num_results; mdc->i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_HashCode h_contract_terms;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    uint64_t serial_id;
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &serial_id),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &deposit_fee),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  mdc->i))
    {
      GNUNET_break (0);
      mdc->status = GNUNET_SYSERR;
      return;
    }
    qs = mdc->deposit_cb (mdc->deposit_cb_cls,
                          serial_id,
                          &coin_pub,
                          &amount_with_fee,
                          &deposit_fee,
                          &h_contract_terms);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
      break;
  }
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
 * @return transaction status code, if positive:
 *         number of rows processed, 0 if none exist
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_matching_deposits (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_wire,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  TALER_EXCHANGEDB_MatchingDepositIterator deposit_cb,
  void *deposit_cb_cls,
  uint32_t limit)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_end
  };
  struct MatchingDepositContext mdc;
  enum GNUNET_DB_QueryStatus qs;

  mdc.deposit_cb = deposit_cb;
  mdc.deposit_cb_cls = deposit_cb_cls;
  mdc.merchant_pub = merchant_pub;
  mdc.pg = pg;
  mdc.limit = limit;
  mdc.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "deposits_iterate_matching",
                                             params,
                                             &match_deposit_cb,
                                             &mdc);
  if (GNUNET_OK != mdc.status)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (qs >= 0)
    return mdc.i;
  return qs;
}


/**
 * Retrieve the record for a known coin.
 *
 * @param cls the plugin closure
 * @param session the database session handle
 * @param coin_pub the public key of the coin to search for
 * @param coin_info place holder for the returned coin information object
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_known_coin (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_CoinSpendPublicKeyP *coin_pub,
                         struct TALER_CoinPublicInfo *coin_info)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &coin_info->denom_pub_hash),
    GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                         &coin_info->denom_sig.rsa_signature),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting known coin data for coin %s\n",
              TALER_B2S (coin_pub));
  coin_info->coin_pub = *coin_pub;
  if (NULL == session)
    session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_known_coin",
                                                   params,
                                                   rs);
}


/**
 * Retrieve the denomination of a known coin.
 *
 * @param cls the plugin closure
 * @param session the database session handle
 * @param coin_pub the public key of the coin to search for
 * @param[out] denom_hash where to store the hash of the coins denomination
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_coin_denomination (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct GNUNET_HashCode *denom_hash)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          denom_hash),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting coin denomination of coin %s\n",
              TALER_B2S (coin_pub));
  if (NULL == session)
    session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_coin_denomination",
                                                   params,
                                                   rs);
}


/**
 * Insert a coin we know of into the DB.  The coin can then be
 * referenced by tables for deposits, refresh and refund
 * functionality.
 *
 * @param cls plugin closure
 * @param session the shared database session
 * @param coin_info the public coin info
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
insert_known_coin (void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_CoinPublicInfo *coin_info)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin_info->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin_info->denom_pub_hash),
    GNUNET_PQ_query_param_rsa_signature (coin_info->denom_sig.rsa_signature),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating known coin %s\n",
              TALER_B2S (&coin_info->coin_pub));
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_known_coin",
                                             params);
}


/**
 * Count the number of known coins by denomination.
 *
 * @param cls database connection plugin state
 * @param session database session
 * @param denom_pub_hash denomination to count by
 * @return number of coins if non-negative, otherwise an `enum GNUNET_DB_QueryStatus`
 */
static long long
postgres_count_known_coins (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct GNUNET_HashCode *denom_pub_hash)
{
  uint64_t count;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("count",
                                  &count),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "count_known_coins",
                                                 params,
                                                 rs);
  if (0 > qs)
    return (long long) qs;
  return (long long) count;
}


/**
 * Make sure the given @a coin is known to the database.
 *
 * @param cls database connection plugin state
 * @param session database session
 * @param coin the coin that must be made known
 * @return database transaction status, non-negative on success
 */
static enum TALER_EXCHANGEDB_CoinKnownStatus
postgres_ensure_coin_known (void *cls,
                            struct TALER_EXCHANGEDB_Session *session,
                            const struct TALER_CoinPublicInfo *coin)
{
  struct PostgresClosure *pc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_HashCode denom_pub_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &denom_pub_hash),
    GNUNET_PQ_result_spec_end
  };
#if EXPLICIT_LOCKS
  struct GNUNET_PQ_QueryParam no_params[] = {
    GNUNET_PQ_query_param_end
  };

  if (0 > (qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                                    "lock_known_coins",
                                                    no_params)))
    return qs;
#endif
  /* check if the coin is already known */
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "get_known_coin_dh",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return TALER_EXCHANGEDB_CKS_SOFT_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    if (0 == GNUNET_memcmp (&denom_pub_hash,
                            &coin->denom_pub_hash))
      return TALER_EXCHANGEDB_CKS_PRESENT;
    GNUNET_break_op (0);
    return TALER_EXCHANGEDB_CKS_CONFLICT;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    break;
  }

  /* if not known, insert it */
  qs = insert_known_coin (pc,
                          session,
                          coin);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    return TALER_EXCHANGEDB_CKS_SOFT_FAIL;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0);
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }
  return TALER_EXCHANGEDB_CKS_ADDED;
}


/**
 * Insert information about deposited coin into the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session connection to the database
 * @param exchange_timestamp time the exchange received the deposit request
 * @param deposit deposit information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_deposit (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         struct GNUNET_TIME_Absolute exchange_timestamp,
                         const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    TALER_PQ_query_param_amount (&deposit->amount_with_fee),
    TALER_PQ_query_param_absolute_time (&deposit->timestamp),
    TALER_PQ_query_param_absolute_time (&deposit->refund_deadline),
    TALER_PQ_query_param_absolute_time (&deposit->wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_wire),
    GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
    TALER_PQ_query_param_json (deposit->receiver_wire_account),
    TALER_PQ_query_param_absolute_time (&exchange_timestamp),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Inserting deposit to be executed at %s (%llu/%llu)\n",
              GNUNET_STRINGS_absolute_time_to_string (deposit->wire_deadline),
              (unsigned long long) deposit->wire_deadline.abs_value_us,
              (unsigned long long) deposit->refund_deadline.abs_value_us);
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_deposit",
                                             params);
}


/**
 * Insert information about refunded coin into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to the database
 * @param refund refund information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_refund (void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_Refund *refund)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_sig),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.h_contract_terms),
    GNUNET_PQ_query_param_uint64 (&refund->details.rtransaction_id),
    TALER_PQ_query_param_amount (&refund->details.refund_amount),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&refund->details.refund_amount,
                                            &refund->details.refund_fee));
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_refund",
                                             params);
}


/**
 * Closure for #get_refunds_cb().
 */
struct SelectRefundContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_RefundCoinCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct SelectRefundContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
get_refunds_cb (void *cls,
                PGresult *result,
                unsigned int num_results)
{
  struct SelectRefundContext *srctx = cls;
  struct PostgresClosure *pg = srctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount_with_fee;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      srctx->status = GNUNET_SYSERR;
      return;
    }
    if (GNUNET_OK !=
        srctx->cb (srctx->cb_cls,
                   &amount_with_fee))
      return;
  }
}


/**
 * Select refunds by @a coin_pub, @a merchant_pub and @a h_contract.
 *
 * @param cls closure of plugin
 * @param session database handle to use
 * @param coin_pub coin to get refunds for
 * @param merchant_pub merchant to get refunds for
 * @param h_contract contract (hash) to get refunds for
 * @param cb function to call for each refund found
 * @param cb_cls closure for @a cb
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refunds_by_coin (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct GNUNET_HashCode *h_contract,
  TALER_EXCHANGEDB_RefundCoinCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract),
    GNUNET_PQ_query_param_end
  };
  struct SelectRefundContext srctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_refunds_by_coin_and_contract",
                                             params,
                                             &get_refunds_cb,
                                             &srctx);
  if (GNUNET_SYSERR == srctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Lookup refresh melt commitment data under the given @a rc.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use, NULL if not run in any transaction
 * @param rc commitment hash to use to locate the operation
 * @param[out] melt where to store the result; note that
 *             melt->session.coin.denom_sig will be set to NULL
 *             and is not fetched by this routine (as it is not needed by the client)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_melt (void *cls,
                   struct TALER_EXCHANGEDB_Session *session,
                   const struct TALER_RefreshCommitmentP *rc,
                   struct TALER_EXCHANGEDB_Melt *melt)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &melt->session.coin.
                                          denom_pub_hash),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &melt->melt_fee),
    GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                  &melt->session.noreveal_index),
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          &melt->session.coin.coin_pub),
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                          &melt->session.coin_sig),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &melt->session.amount_with_fee),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  melt->session.coin.denom_sig.rsa_signature = NULL;
  if (NULL == session)
    session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "get_melt",
                                                 params,
                                                 rs);
  melt->session.rc = *rc;
  return qs;
}


/**
 * Lookup noreveal index of a previous melt operation under the given
 * @a rc.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param rc commitment hash to use to locate the operation
 * @param[out] noreveal_index returns the "gamma" value selected by the
 *             exchange which is the index of the transfer key that is
 *             not to be revealed to the exchange
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_melt_index (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_RefreshCommitmentP *rc,
                         uint32_t *noreveal_index)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                  noreveal_index),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_melt_index",
                                                   params,
                                                   rs);
}


/**
 * Store new refresh melt commitment data.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database handle to use
 * @param refresh_session session data to store
 * @return query status for the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_melt (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_EXCHANGEDB_Refresh *refresh_session)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->rc),
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refresh_session->coin_sig),
    TALER_PQ_query_param_amount (&refresh_session->amount_with_fee),
    GNUNET_PQ_query_param_uint32 (&refresh_session->noreveal_index),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_melt",
                                             params);
}


/**
 * Store in the database which coin(s) the wallet wanted to create
 * in a given refresh operation and all of the other information
 * we learned or created in the /refresh/reveal step.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session database connection
 * @param rc identify commitment and thus refresh operation
 * @param num_rrcs number of coins to generate, size of the @a rrcs array
 * @param rrcs information about the new coins
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs transfer private keys to store
 * @param tp public key to store
 * @return query status for the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_refresh_reveal (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_RefreshCommitmentP *rc,
  uint32_t num_rrcs,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
  unsigned int num_tprivs,
  const struct TALER_TransferPrivateKeyP *tprivs,
  const struct TALER_TransferPublicKeyP *tp)
{
  (void) cls;
  if (TALER_CNC_KAPPA != num_tprivs + 1)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  for (uint32_t i = 0; i<num_rrcs; i++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct GNUNET_HashCode denom_pub_hash;
    struct GNUNET_HashCode h_coin_ev;
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (rc),
      GNUNET_PQ_query_param_uint32 (&i),
      GNUNET_PQ_query_param_auto_from_type (&rrc->orig_coin_link_sig),
      GNUNET_PQ_query_param_auto_from_type (&denom_pub_hash),
      GNUNET_PQ_query_param_fixed_size (rrc->coin_ev,
                                        rrc->coin_ev_size),
      GNUNET_PQ_query_param_auto_from_type (&h_coin_ev),
      GNUNET_PQ_query_param_rsa_signature (rrc->coin_sig.rsa_signature),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    GNUNET_CRYPTO_rsa_public_key_hash (rrc->denom_pub.rsa_public_key,
                                       &denom_pub_hash);
    GNUNET_CRYPTO_hash (rrc->coin_ev,
                        rrc->coin_ev_size,
                        &h_coin_ev);
    qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_refresh_revealed_coin",
                                             params);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
      return qs;
  }

  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (rc),
      GNUNET_PQ_query_param_auto_from_type (tp),
      GNUNET_PQ_query_param_fixed_size (tprivs,
                                        num_tprivs * sizeof (struct
                                                             TALER_TransferPrivateKeyP)),
      GNUNET_PQ_query_param_end
    };

    return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                               "insert_refresh_transfer_keys",
                                               params);
  }
}


/**
 * Context where we aggregate data from the database.
 * Closure for #add_revealed_coins().
 */
struct GetRevealContext
{
  /**
   * Array of revealed coins we obtained from the DB.
   */
  struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs;

  /**
   * Length of the @a rrcs array.
   */
  unsigned int rrcs_len;

  /**
   * Set to an error code if we ran into trouble.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct GetRevealContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_revealed_coins (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct GetRevealContext *grctx = cls;

  if (0 == num_results)
    return;
  grctx->rrcs = GNUNET_new_array (num_results,
                                  struct TALER_EXCHANGEDB_RefreshRevealedCoin);
  grctx->rrcs_len = num_results;
  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx->rrcs[i];
    uint32_t off;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint32 ("freshcoin_index",
                                    &off),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &rrc->denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                            &rrc->orig_coin_link_sig),
      GNUNET_PQ_result_spec_variable_size ("coin_ev",
                                           (void **) &rrc->coin_ev,
                                           &rrc->coin_ev_size),
      GNUNET_PQ_result_spec_rsa_signature ("ev_sig",
                                           &rrc->coin_sig.rsa_signature),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    if (off != i)
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
  }
}


/**
 * Lookup in the database the coins that we want to
 * create in the given refresh operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param rc identify commitment and thus refresh operation
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_refresh_reveal (void *cls,
                             struct TALER_EXCHANGEDB_Session *session,
                             const struct TALER_RefreshCommitmentP *rc,
                             TALER_EXCHANGEDB_RefreshCallback cb,
                             void *cb_cls)
{
  struct GetRevealContext grctx;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_TransferPublicKeyP tp;
  void *tpriv;
  size_t tpriv_size;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                          &tp),
    GNUNET_PQ_result_spec_variable_size ("transfer_privs",
                                         &tpriv,
                                         &tpriv_size),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  /* First get the coins */
  memset (&grctx,
          0,
          sizeof (grctx));
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_refresh_revealed_coins",
                                             params,
                                             &add_revealed_coins,
                                             &grctx);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
  default:   /* can have more than one result */
    break;
  }
  switch (grctx.qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:   /* should be impossible */
    break;
  }

  /* now also get the transfer keys (public and private) */
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "get_refresh_transfer_keys",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  default:
    GNUNET_assert (0);
  }
  if ( (0 != tpriv_size % sizeof (struct TALER_TransferPrivateKeyP)) ||
       (TALER_CNC_KAPPA - 1 != tpriv_size / sizeof (struct
                                                    TALER_TransferPrivateKeyP)) )
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
    GNUNET_PQ_cleanup_result (rs);
    goto cleanup;
  }

  /* Pass result back to application */
  cb (cb_cls,
      grctx.rrcs_len,
      grctx.rrcs,
      tpriv_size / sizeof (struct TALER_TransferPrivateKeyP),
      (const struct TALER_TransferPrivateKeyP *) tpriv,
      &tp);
  GNUNET_PQ_cleanup_result (rs);

cleanup:
  for (unsigned int i = 0; i < grctx.rrcs_len; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx.rrcs[i];

    if (NULL != rrc->denom_pub.rsa_public_key)
      GNUNET_CRYPTO_rsa_public_key_free (rrc->denom_pub.rsa_public_key);
    if (NULL != rrc->coin_sig.rsa_signature)
      GNUNET_CRYPTO_rsa_signature_free (rrc->coin_sig.rsa_signature);
    GNUNET_free (rrc->coin_ev);
  }
  GNUNET_free (grctx.rrcs);

  return qs;
}


/**
 * Closure for #add_ldl().
 */
struct LinkDataContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_LinkCallback ldc;

  /**
   * Closure for @e ldc.
   */
  void *ldc_cls;

  /**
   * Last transfer public key for which we have information in @e last.
   * Only valid if @e last is non-NULL.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Link data for @e transfer_pub
   */
  struct TALER_EXCHANGEDB_LinkList *last;

  /**
   * Status, set to #GNUNET_SYSERR on errors,
   */
  int status;
};


/**
 * Free memory of the link data list.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param ldl link data list to release
 */
static void
free_link_data_list (void *cls,
                     struct TALER_EXCHANGEDB_LinkList *ldl)
{
  struct TALER_EXCHANGEDB_LinkList *next;

  (void) cls;
  while (NULL != ldl)
  {
    next = ldl->next;
    if (NULL != ldl->denom_pub.rsa_public_key)
      GNUNET_CRYPTO_rsa_public_key_free (ldl->denom_pub.rsa_public_key);
    if (NULL != ldl->ev_sig.rsa_signature)
      GNUNET_CRYPTO_rsa_signature_free (ldl->ev_sig.rsa_signature);
    GNUNET_free (ldl);
    ldl = next;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct LinkDataContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_ldl (void *cls,
         PGresult *result,
         unsigned int num_results)
{
  struct LinkDataContext *ldctx = cls;

  for (int i = num_results - 1; i >= 0; i--)
  {
    struct TALER_EXCHANGEDB_LinkList *pos;
    struct TALER_TransferPublicKeyP transfer_pub;

    pos = GNUNET_new (struct TALER_EXCHANGEDB_LinkList);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                              &transfer_pub),
        GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                              &pos->orig_coin_link_sig),
        GNUNET_PQ_result_spec_rsa_signature ("ev_sig",
                                             &pos->ev_sig.rsa_signature),
        GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                              &pos->denom_pub.rsa_public_key),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (pos);
        ldctx->status = GNUNET_SYSERR;
        return;
      }
    }
    if ( (NULL != ldctx->last) &&
         (0 == GNUNET_memcmp (&transfer_pub,
                              &ldctx->transfer_pub)) )
    {
      pos->next = ldctx->last;
    }
    else
    {
      if (NULL != ldctx->last)
      {
        ldctx->ldc (ldctx->ldc_cls,
                    &ldctx->transfer_pub,
                    ldctx->last);
        free_link_data_list (cls,
                             ldctx->last);
      }
      ldctx->transfer_pub = transfer_pub;
    }
    ldctx->last = pos;
  }
}


/**
 * Obtain the link data of a coin, that is the encrypted link
 * information, the denomination keys and the signatures.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub public key of the coin
 * @param ldc function to call for each session the coin was melted into
 * @param ldc_cls closure for @a tdc
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_link_data (void *cls,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        TALER_EXCHANGEDB_LinkCallback ldc,
                        void *ldc_cls)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct LinkDataContext ldctx;

  ldctx.ldc = ldc;
  ldctx.ldc_cls = ldc_cls;
  ldctx.last = NULL;
  ldctx.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_link",
                                             params,
                                             &add_ldl,
                                             &ldctx);
  if (NULL != ldctx.last)
  {
    if (GNUNET_OK == ldctx.status)
    {
      /* call callback one more time! */
      ldc (ldc_cls,
           &ldctx.transfer_pub,
           ldctx.last);
    }
    free_link_data_list (cls,
                         ldctx.last);
    ldctx.last = NULL;
  }
  if (GNUNET_OK != ldctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for callbacks called from #postgres_get_coin_transactions()
 */
struct CoinHistoryContext
{
  /**
   * Head of the coin's history list.
   */
  struct TALER_EXCHANGEDB_TransactionList *head;

  /**
   * Public key of the coin we are building the history for.
   */
  const struct TALER_CoinSpendPublicKeyP *coin_pub;

  /**
   * Closure for all callbacks of this database plugin.
   */
  void *db_cls;

  /**
   * Database session we are using.
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to 'true' if the transaction failed.
   */
  bool failed;

  /**
   * Set to 'true' if we found a deposit or melt (for invariant check).
   */
  bool have_deposit_or_melt;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_deposit (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_DepositListEntry *deposit;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    chc->have_deposit_or_melt = true;
    deposit = GNUNET_new (struct TALER_EXCHANGEDB_DepositListEntry);
    {
      uint8_t done = 0;
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &deposit->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                     &deposit->deposit_fee),
        TALER_PQ_result_spec_absolute_time ("wallet_timestamp",
                                            &deposit->timestamp),
        TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                            &deposit->refund_deadline),
        TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                            &deposit->wire_deadline),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &deposit->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &deposit->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &deposit->h_contract_terms),
        GNUNET_PQ_result_spec_auto_from_type ("h_wire",
                                              &deposit->h_wire),
        TALER_PQ_result_spec_json ("wire",
                                   &deposit->receiver_wire_account),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &deposit->csig),
        GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_auto_from_type ("done",
                                              &done),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (deposit);
        chc->failed = true;
        return;
      }
      deposit->done = (0 != done);
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_DEPOSIT;
    tl->details.deposit = deposit;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_melt (void *cls,
               PGresult *result,
               unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_MeltListEntry *melt;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    chc->have_deposit_or_melt = true;
    melt = GNUNET_new (struct TALER_EXCHANGEDB_MeltListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("rc",
                                              &melt->rc),
        /* oldcoin_index not needed */
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &melt->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                              &melt->coin_sig),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &melt->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                     &melt->melt_fee),
        GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (melt);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_MELT;
    tl->details.melt = melt;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_refund (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RefundListEntry *refund;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    refund = GNUNET_new (struct TALER_EXCHANGEDB_RefundListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &refund->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                              &refund->merchant_sig),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &refund->h_contract_terms),
        GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                      &refund->rtransaction_id),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &refund->refund_amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                     &refund->refund_fee),
        GNUNET_PQ_result_spec_uint64 ("refund_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (refund);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_REFUND;
    tl->details.refund = refund;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_old_coin_recoup (void *cls,
                     PGresult *result,
                     unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RecoupRefreshListEntry *recoup;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_RecoupRefreshListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                              &recoup->coin.coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                             &recoup->coin.denom_sig.
                                             rsa_signature),
        GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        chc->failed = true;
        return;
      }
      recoup->old_coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP;
    tl->details.old_coin_recoup = recoup;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_recoup (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RecoupListEntry *recoup;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_RecoupListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &recoup->reserve_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &recoup->timestamp),
        GNUNET_PQ_result_spec_uint64 ("recoup_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_RECOUP;
    tl->details.recoup = recoup;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_recoup_refresh (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RecoupRefreshListEntry *recoup;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_RecoupRefreshListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                              &recoup->old_coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        TALER_PQ_result_spec_absolute_time ("timestamp",
                                            &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                             &recoup->coin.denom_sig.
                                             rsa_signature),
        GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        chc->failed = true;
        return;
      }
      recoup->coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_RECOUP_REFRESH;
    tl->details.recoup_refresh = recoup;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Work we need to do.
 */
struct Work
{
  /**
   * SQL prepared statement name.
   */
  const char *statement;

  /**
   * Function to call to handle the result(s).
   */
  GNUNET_PQ_PostgresResultHandler cb;
};


/**
 * Compile a list of all (historic) transactions performed with the given coin
 * (/refresh/melt, /deposit, /refund and /recoup operations).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param session database connection
 * @param coin_pub coin to investigate
 * @param include_recoup should recoup transactions be included in the @a tlp
 * @param[out] tlp set to list of transactions, NULL if coin is fresh
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_coin_transactions (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  int include_recoup,
  struct TALER_EXCHANGEDB_TransactionList **tlp)
{
  struct PostgresClosure *pg = cls;
  static const struct Work work_op[] = {
    /** #TALER_EXCHANGEDB_TT_DEPOSIT */
    { "get_deposit_with_coin_pub",
      &add_coin_deposit },
    /** #TALER_EXCHANGEDB_TT_MELT */
    { "get_refresh_session_by_coin",
      &add_coin_melt },
    /** #TALER_EXCHANGEDB_TT_REFUND */
    { "get_refunds_by_coin",
      &add_coin_refund },
    { NULL, NULL }
  };
  static const struct Work work_wp[] = {
    /** #TALER_EXCHANGEDB_TT_DEPOSIT */
    { "get_deposit_with_coin_pub",
      &add_coin_deposit },
    /** #TALER_EXCHANGEDB_TT_MELT */
    { "get_refresh_session_by_coin",
      &add_coin_melt },
    /** #TALER_EXCHANGEDB_TT_REFUND */
    { "get_refunds_by_coin",
      &add_coin_refund },
    /** #TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP */
    { "recoup_by_old_coin",
      &add_old_coin_recoup },
    /** #TALER_EXCHANGEDB_TT_RECOUP */
    { "recoup_by_coin",
      &add_coin_recoup },
    /** #TALER_EXCHANGEDB_TT_RECOUP_REFRESH */
    { "recoup_by_refreshed_coin",
      &add_coin_recoup_refresh },
    { NULL, NULL }
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  const struct Work *work;
  struct CoinHistoryContext chc = {
    .head = NULL,
    .coin_pub = coin_pub,
    .session = session,
    .pg = pg,
    .db_cls = cls
  };

  work = (GNUNET_YES == include_recoup) ? work_wp : work_op;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting transactions for coin %s\n",
              TALER_B2S (coin_pub));
  for (unsigned int i = 0; NULL != work[i].statement; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               work[i].statement,
                                               params,
                                               work[i].cb,
                                               &chc);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Coin %s yielded %d transactions of type %s\n",
                TALER_B2S (coin_pub),
                qs,
                work[i].statement);
    if ( (0 > qs) ||
         (chc.failed) )
    {
      if (NULL != chc.head)
        common_free_coin_transaction_list (cls,
                                           chc.head);
      *tlp = NULL;
      if (chc.failed)
        qs = GNUNET_DB_STATUS_HARD_ERROR;
      return qs;
    }
  }
  *tlp = chc.head;
  if (NULL == chc.head)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Closure for #handle_wt_result.
 */
struct WireTransferResultContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_AggregationDataCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on serious errors.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.  Helper function
 * for #postgres_lookup_wire_transfer().
 *
 * @param cls closure of type `struct WireTransferResultContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
handle_wt_result (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct WireTransferResultContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct GNUNET_HashCode h_contract_terms;
    struct GNUNET_HashCode h_wire;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct GNUNET_TIME_Absolute exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct TALER_DenominationPublicKey denom_pub;
    json_t *wire;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("aggregation_serial_id", &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &h_contract_terms),
      TALER_PQ_result_spec_json ("wire", &wire),
      GNUNET_PQ_result_spec_auto_from_type ("h_wire", &h_wire),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub", &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub", &merchant_pub),
      TALER_PQ_result_spec_absolute_time ("execution_date", &exec_time),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee", &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit", &deposit_fee),
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
    ctx->cb (ctx->cb_cls,
             rowid,
             &merchant_pub,
             &h_wire,
             wire,
             exec_time,
             &h_contract_terms,
             &denom_pub,
             &coin_pub,
             &amount_with_fee,
             &deposit_fee);
    GNUNET_PQ_cleanup_result (rs);
  }
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
 * @return query status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_transfer (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  TALER_EXCHANGEDB_AggregationDataCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  struct WireTransferResultContext ctx;
  enum GNUNET_DB_QueryStatus qs;

  ctx.cb = cb;
  ctx.cb_cls = cb_cls;
  ctx.pg = pg;
  ctx.status = GNUNET_OK;
  /* check if the melt record exists and get it */
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "lookup_transactions",
                                             params,
                                             &handle_wt_result,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Try to find the wire transfer details for a deposit operation.
 * If we did not execute the deposit yet, return when it is supposed
 * to be executed.
 *
 * @param cls closure
 * @param session database connection
 * @param h_contract_terms hash of the proposal data
 * @param h_wire hash of merchant wire details
 * @param coin_pub public key of deposited coin
 * @param merchant_pub merchant public key
 * @param cb function to call with the result
 * @param cb_cls closure to pass to @a cb
 * @return transaction status code
 - */
static enum GNUNET_DB_QueryStatus
postgres_lookup_transfer_by_deposit (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_contract_terms,
  const struct GNUNET_HashCode *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  TALER_EXCHANGEDB_WireTransferByCoinCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (h_wire),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_end
  };
  struct TALER_WireTransferIdentifierRawP wtid;
  struct GNUNET_TIME_Absolute exec_time;
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount deposit_fee;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                          &wtid),
    TALER_PQ_result_spec_absolute_time ("execution_date",
                                        &exec_time),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &deposit_fee),
    GNUNET_PQ_result_spec_end
  };

  /* check if the melt record exists and get it */
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "lookup_deposit_wtid",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    cb (cb_cls,
        &wtid,
        &amount_with_fee,
        &deposit_fee,
        exec_time);
    return qs;
  }
  if (0 > qs)
    return qs;

  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "lookup_deposit_wtid returned 0 matching rows\n");
  {
    /* Check if transaction exists in deposits, so that we just
       do not have a WTID yet, if so, do call the CB with a NULL wtid
       and return #GNUNET_YES! */
    struct GNUNET_PQ_QueryParam params2[] = {
      GNUNET_PQ_query_param_auto_from_type (coin_pub),
      GNUNET_PQ_query_param_auto_from_type (merchant_pub),
      GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
      GNUNET_PQ_query_param_auto_from_type (h_wire),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_TIME_Absolute exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct GNUNET_PQ_ResultSpec rs2[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee", &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit", &deposit_fee),
      TALER_PQ_result_spec_absolute_time ("wire_deadline", &exec_time),
      GNUNET_PQ_result_spec_end
    };

    qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_deposit_for_wtid",
                                                   params2,
                                                   rs2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    {
      /* Ok, we're aware of the transaction, but it has not yet been
         executed */
      cb (cb_cls,
          NULL,
          &amount_with_fee,
          &deposit_fee,
          exec_time);
      return qs;
    }
    return qs;
  }
}


/**
 * Function called to insert aggregation information into the DB.
 *
 * @param cls closure
 * @param session database connection
 * @param wtid the raw wire transfer identifier we used
 * @param deposit_serial_id row in the deposits table for which this is aggregation data
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_aggregation_tracking (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  unsigned long long deposit_serial_id)
{
  uint64_t rid = deposit_serial_id;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rid),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_aggregation_tracking",
                                             params);
}


/**
 * Obtain wire fee from database.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of wire transfer the fee applies for
 * @param date for which date do we want the fee?
 * @param[out] start_date when does the fee go into effect
 * @param[out] end_date when does the fee end being valid
 * @param[out] wire_fee how high is the wire transfer fee
 * @param[out] closing_fee how high is the closing fee
 * @param[out] master_sig signature over the above by the exchange master key
 * @return status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_fee (void *cls,
                       struct TALER_EXCHANGEDB_Session *session,
                       const char *type,
                       struct GNUNET_TIME_Absolute date,
                       struct GNUNET_TIME_Absolute *start_date,
                       struct GNUNET_TIME_Absolute *end_date,
                       struct TALER_Amount *wire_fee,
                       struct TALER_Amount *closing_fee,
                       struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    TALER_PQ_query_param_absolute_time (&date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_absolute_time ("start_date", start_date),
    TALER_PQ_result_spec_absolute_time ("end_date", end_date),
    TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee", wire_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee", closing_fee),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig", master_sig),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "get_wire_fee",
                                                   params,
                                                   rs);
}


/**
 * Insert wire transfer fee into database.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of wire transfer this fee applies for
 * @param start_date when does the fee go into effect
 * @param end_date when does the fee end being valid
 * @param wire_fee how high is the wire transfer fee
 * @param closing_fee how high is the closing fee
 * @param master_sig signature over the above by the exchange master key
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_fee (void *cls,
                          struct TALER_EXCHANGEDB_Session *session,
                          const char *type,
                          struct GNUNET_TIME_Absolute start_date,
                          struct GNUNET_TIME_Absolute end_date,
                          const struct TALER_Amount *wire_fee,
                          const struct TALER_Amount *closing_fee,
                          const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    TALER_PQ_query_param_absolute_time (&start_date),
    TALER_PQ_query_param_absolute_time (&end_date),
    TALER_PQ_query_param_amount (wire_fee),
    TALER_PQ_query_param_amount (closing_fee),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
  struct TALER_Amount wf;
  struct TALER_Amount cf;
  struct TALER_MasterSignatureP sig;
  struct GNUNET_TIME_Absolute sd;
  struct GNUNET_TIME_Absolute ed;
  enum GNUNET_DB_QueryStatus qs;

  qs = postgres_get_wire_fee (pg,
                              session,
                              type,
                              start_date,
                              &sd,
                              &ed,
                              &wf,
                              &cf,
                              &sig);
  if (qs < 0)
    return qs;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    if (0 != GNUNET_memcmp (&sig,
                            master_sig))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (0 != TALER_amount_cmp (wire_fee,
                               &wf))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (0 != TALER_amount_cmp (closing_fee,
                               &cf))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (sd.abs_value_us != start_date.abs_value_us) ||
         (ed.abs_value_us != end_date.abs_value_us) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* equal record already exists */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_wire_fee",
                                             params);
}


/**
 * Closure for #reserve_expired_cb().
 */
struct ExpiredReserveContext
{
  /**
   * Function to call for each expired reserve.
   */
  TALER_EXCHANGEDB_ReserveExpiredCallback rec;

  /**
   * Closure to give to @e rec.
   */
  void *rec_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserve_expired_cb (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct ExpiredReserveContext *erc = cls;
  struct PostgresClosure *pg = erc->pg;
  int ret;

  ret = GNUNET_OK;
  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_TIME_Absolute exp_date;
    char *account_details;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount remaining_balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_absolute_time ("expiration_date",
                                          &exp_date),
      GNUNET_PQ_result_spec_string ("account_details",
                                    &account_details),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance",
                                   &remaining_balance),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ret = GNUNET_SYSERR;
      break;
    }
    ret = erc->rec (erc->rec_cls,
                    &reserve_pub,
                    &remaining_balance,
                    account_details,
                    exp_date);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
  erc->status = ret;
}


/**
 * Obtain information about expired reserves and their
 * remaining balances.
 *
 * @param cls closure of the plugin
 * @param session database connection
 * @param now timestamp based on which we decide expiration
 * @param rec function to call on expired reserves
 * @param rec_cls closure for @a rec
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_expired_reserves (void *cls,
                               struct TALER_EXCHANGEDB_Session *session,
                               struct GNUNET_TIME_Absolute now,
                               TALER_EXCHANGEDB_ReserveExpiredCallback rec,
                               void *rec_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct ExpiredReserveContext ectx;
  enum GNUNET_DB_QueryStatus qs;

  ectx.rec = rec;
  ectx.rec_cls = rec_cls;
  ectx.pg = pg;
  ectx.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_expired_reserves",
                                             params,
                                             &reserve_expired_cb,
                                             &ectx);
  if (GNUNET_OK != ectx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Insert reserve close operation into database.
 *
 * @param cls closure
 * @param session database connection
 * @param reserve_pub which reserve is this about?
 * @param execution_date when did we perform the transfer?
 * @param receiver_account to which account do we transfer?
 * @param wtid wire transfer details
 * @param amount_with_fee amount we charged to the reserve
 * @param closing_fee how high is the closing fee
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_reserve_closed (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct GNUNET_TIME_Absolute execution_date,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee)
{
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    TALER_PQ_query_param_absolute_time (&execution_date),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_string (receiver_account),
    TALER_PQ_query_param_amount (amount_with_fee),
    TALER_PQ_query_param_amount (closing_fee),
    GNUNET_PQ_query_param_end
  };
  enum TALER_AmountArithmeticResult ret;
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "reserves_close_insert",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;

  /* update reserve balance */
  reserve.pub = *reserve_pub;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      (qs = postgres_reserves_get (cls,
                                   session,
                                   &reserve)))
  {
    /* Existence should have been checked before we got here... */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    return qs;
  }
  ret = TALER_amount_subtract (&reserve.balance,
                               &reserve.balance,
                               amount_with_fee);
  if (ret < 0)
  {
    /* The reserve history was checked to make sure there is enough of a balance
       left before we tried this; however, concurrent operations may have changed
       the situation by now.  We should re-try the transaction.  */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Closing of reserve `%s' refused due to balance mismatch. Retrying.\n",
                TALER_B2S (reserve_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_break (TALER_AAR_RESULT_ZERO == ret);
  return reserves_update (cls,
                          session,
                          &reserve);
}


/**
 * Function called to insert wire transfer commit data into the DB.
 *
 * @param cls closure
 * @param session database connection
 * @param type type of the wire transfer (i.e. "iban")
 * @param buf buffer with wire transfer preparation data
 * @param buf_size number of bytes in @a buf
 * @return query status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_insert (void *cls,
                                   struct TALER_EXCHANGEDB_Session *session,
                                   const char *type,
                                   const char *buf,
                                   size_t buf_size)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_fixed_size (buf, buf_size),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "wire_prepare_data_insert",
                                             params);
}


/**
 * Function called to mark wire transfer commit data as finished.
 *
 * @param cls closure
 * @param session database connection
 * @param rowid which entry to mark as finished
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_mark_finished (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "wire_prepare_data_mark_done",
                                             params);
}


/**
 * Function called to mark wire transfer commit data as failed.
 *
 * @param cls closure
 * @param session database connection
 * @param rowid which entry to mark as failed
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_mark_failed (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "wire_prepare_data_mark_failed",
                                             params);
}


/**
 * Function called to get an unfinished wire transfer
 * preparation data. Fetches at most one item.
 *
 * @param cls closure
 * @param session database connection
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_get (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                TALER_EXCHANGEDB_WirePreparationIterator cb,
                                void *cb_cls)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
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

  (void) cls;
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "wire_prepare_data_get",
                                                 params,
                                                 rs);
  if (0 >= qs)
    return qs;
  cb (cb_cls,
      prewire_uuid,
      type,
      buf,
      buf_size);
  GNUNET_PQ_cleanup_result (rs);
  return qs;
}


/**
 * Start a transaction where we transiently violate the foreign
 * constraints on the "wire_out" table as we insert aggregations
 * and only add the wire transfer out at the end.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session connection to use
 * @return #GNUNET_OK on success
 */
static int
postgres_start_deferred_wire_out (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session)
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("SET CONSTRAINTS wire_out_ref DEFERRED"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  postgres_preflight (cls,
                      session);
  if (GNUNET_OK !=
      postgres_start (cls,
                      session,
                      "deferred wire out"))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (session->conn,
                                 es))
  {
    TALER_LOG_ERROR (
      "Failed to defer wire_out_ref constraint on transaction\n");
    GNUNET_break (0);
    postgres_rollback (cls,
                       session);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Store information about an outgoing wire transfer that was executed.
 *
 * @param cls closure
 * @param session database connection
 * @param date time of the wire transfer
 * @param wtid subject of the wire transfer
 * @param wire_account details about the receiver account of the wire transfer
 * @param exchange_account_section configuration section of the exchange specifying the
 *        exchange's bank account being used
 * @param amount amount that was transmitted
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_store_wire_transfer_out (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  struct GNUNET_TIME_Absolute date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const json_t *wire_account,
  const char *exchange_account_section,
  const struct TALER_Amount *amount)
{
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&date),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    TALER_PQ_query_param_json (wire_account),
    GNUNET_PQ_query_param_string (exchange_account_section),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_wire_out",
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute long_ago;
  struct GNUNET_PQ_QueryParam params_none[] = {
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params_time[] = {
    TALER_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params_ancient_time[] = {
    TALER_PQ_query_param_absolute_time (&long_ago),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_Context *conn;
  int ret;

  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  /* Keep wire fees for 10 years, that should always
     be enough _and_ they are tiny so it does not
     matter to make this tight */
  long_ago = GNUNET_TIME_absolute_subtract (now,
                                            GNUNET_TIME_relative_multiply (
                                              GNUNET_TIME_UNIT_YEARS,
                                              10));
  {
    struct GNUNET_PQ_PreparedStatement ps[] = {
      /* Used in #postgres_gc() */
      GNUNET_PQ_make_prepare ("gc_prewire",
                              "DELETE"
                              " FROM prewire"
                              " WHERE finished=true;",
                              0),
      GNUNET_PQ_make_prepare ("gc_reserves",
                              "DELETE"
                              " FROM reserves"
                              " WHERE gc_date < $1"
                              "   AND current_balance_val = 0"
                              "   AND current_balance_frac = 0;",
                              1),
      GNUNET_PQ_make_prepare ("gc_wire_fee",
                              "DELETE"
                              " FROM wire_fee"
                              " WHERE end_date < $1;",
                              1),
      GNUNET_PQ_make_prepare ("gc_denominations",
                              "DELETE"
                              " FROM denominations"
                              " WHERE expire_legal < $1;",
                              1),
      GNUNET_PQ_PREPARED_STATEMENT_END
    };

    conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                       "exchangedb-postgres",
                                       NULL,
                                       NULL,
                                       ps);
  }
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_OK;
  if ( (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                                "gc_reserves",
                                                params_time)) ||
       (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                                "gc_prewire",
                                                params_none)) ||
       (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                                "gc_wire_fee",
                                                params_ancient_time)) )
    ret = GNUNET_SYSERR;
  /* This one may fail due to foreign key constraints from
     recoup and reserves_out tables to known_coins; these
     are NOT using 'ON DROP CASCADE' and might keep denomination
     keys alive for a bit longer, thus causing this statement
     to fail. */(void) GNUNET_PQ_eval_prepared_non_select (conn,
                                             "gc_denominations",
                                             params_time);
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/**
 * Closure for #deposit_serial_helper_cb().
 */
struct DepositSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_DepositCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct DepositSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
deposit_serial_helper_cb (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct DepositSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_Deposit deposit;
    struct GNUNET_TIME_Absolute exchange_timestamp;
    struct TALER_DenominationPublicKey denom_pub;
    uint8_t done = 0;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &deposit.amount_with_fee),
      TALER_PQ_result_spec_absolute_time ("wallet_timestamp",
                                          &deposit.timestamp),
      TALER_PQ_result_spec_absolute_time ("exchange_timestamp",
                                          &exchange_timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &deposit.merchant_pub),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &deposit.coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &deposit.csig),
      TALER_PQ_result_spec_absolute_time ("refund_deadline",
                                          &deposit.refund_deadline),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                          &deposit.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &deposit.h_contract_terms),
      TALER_PQ_result_spec_json ("wire",
                                 &deposit.receiver_wire_account),
      GNUNET_PQ_result_spec_auto_from_type ("done",
                                            &done),
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   exchange_timestamp,
                   deposit.timestamp,
                   &deposit.merchant_pub,
                   &denom_pub,
                   &deposit.coin.coin_pub,
                   &deposit.csig,
                   &deposit.amount_with_fee,
                   &deposit.h_contract_terms,
                   deposit.refund_deadline,
                   deposit.wire_deadline,
                   deposit.receiver_wire_account,
                   done);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_deposits_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_DepositCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct DepositSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_get_deposits_incr",
                                             params,
                                             &deposit_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #refreshs_serial_helper_cb().
 */
struct RefreshsSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RefreshesCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct RefreshsSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
refreshs_serial_helper_cb (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct RefreshsSerialContext *rsc = cls;
  struct PostgresClosure *pg = rsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_Amount amount_with_fee;
    uint32_t noreveal_index;
    uint64_t rowid;
    struct TALER_RefreshCommitmentP rc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                            &coin_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                    &noreveal_index),
      GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("rc",
                                            &rc),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rsc->cb (rsc->cb_cls,
                   rowid,
                   &denom_pub,
                   &coin_pub,
                   &coin_sig,
                   &amount_with_fee,
                   noreveal_index,
                   &rc);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refreshes_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RefreshesCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RefreshsSerialContext rsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_get_refresh_commitments_incr",
                                             params,
                                             &refreshs_serial_helper_cb,
                                             &rsc);
  if (GNUNET_OK != rsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #refunds_serial_helper_cb().
 */
struct RefundsSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RefundCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct RefundsSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
refunds_serial_helper_cb (void *cls,
                          PGresult *result,
                          unsigned int num_results)
{
  struct RefundsSerialContext *rsc = cls;
  struct PostgresClosure *pg = rsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_Refund refund;
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &refund.details.merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                            &refund.details.merchant_sig),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &refund.details.h_contract_terms),
      GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                    &refund.details.rtransaction_id),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &refund.coin.coin_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &refund.details.refund_amount),
      GNUNET_PQ_result_spec_uint64 ("refund_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rsc->cb (rsc->cb_cls,
                   rowid,
                   &denom_pub,
                   &refund.coin.coin_pub,
                   &refund.details.merchant_pub,
                   &refund.details.merchant_sig,
                   &refund.details.h_contract_terms,
                   refund.details.rtransaction_id,
                   &refund.details.refund_amount);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refunds_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RefundCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RefundsSerialContext rsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_get_refunds_incr",
                                             params,
                                             &refunds_serial_helper_cb,
                                             &rsc);
  if (GNUNET_OK != rsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #reserves_in_serial_helper_cb().
 */
struct ReservesInSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveInCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReservesInSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserves_in_serial_helper_cb (void *cls,
                              PGresult *result,
                              unsigned int num_results)
{
  struct ReservesInSerialContext *risc = cls;
  struct PostgresClosure *pg = risc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount credit;
    char *sender_account_details;
    struct GNUNET_TIME_Absolute execution_date;
    uint64_t rowid;
    uint64_t wire_reference;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                    &wire_reference),
      TALER_PQ_RESULT_SPEC_AMOUNT ("credit",
                                   &credit),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                          &execution_date),
      GNUNET_PQ_result_spec_string ("sender_account_details",
                                    &sender_account_details),
      GNUNET_PQ_result_spec_uint64 ("reserve_in_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      risc->status = GNUNET_SYSERR;
      return;
    }
    ret = risc->cb (risc->cb_cls,
                    rowid,
                    &reserve_pub,
                    &credit,
                    sender_account_details,
                    wire_reference,
                    execution_date);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_in_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_ReserveInCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReservesInSerialContext risc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_reserves_in_get_transactions_incr",
                                             params,
                                             &reserves_in_serial_helper_cb,
                                             &risc);
  if (GNUNET_OK != risc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Select inbound wire transfers into reserves_in above @a serial_id
 * in monotonically increasing order by account.
 *
 * @param cls closure
 * @param session database connection
 * @param account_name name of the account to select by
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_in_above_serial_id_by_account (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const char *account_name,
  uint64_t serial_id,
  TALER_EXCHANGEDB_ReserveInCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct ReservesInSerialContext risc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_reserves_in_get_transactions_incr_by_account",
                                             params,
                                             &reserves_in_serial_helper_cb,
                                             &risc);
  if (GNUNET_OK != risc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #reserves_out_serial_helper_cb().
 */
struct ReservesOutSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_WithdrawCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReservesOutSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserves_out_serial_helper_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct ReservesOutSerialContext *rosc = cls;
  struct PostgresClosure *pg = rosc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_HashCode h_blind_ev;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_TIME_Absolute execution_date;
    struct TALER_Amount amount_with_fee;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                          &execution_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rosc->status = GNUNET_SYSERR;
      return;
    }
    ret = rosc->cb (rosc->cb_cls,
                    rowid,
                    &h_blind_ev,
                    &denom_pub,
                    &reserve_pub,
                    &reserve_sig,
                    execution_date,
                    &amount_with_fee);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
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
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_withdrawals_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_WithdrawCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReservesOutSerialContext rosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_get_reserves_out_incr",
                                             params,
                                             &reserves_out_serial_helper_cb,
                                             &rosc);
  if (GNUNET_OK != rosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #wire_out_serial_helper_cb().
 */
struct WireOutSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_WireTransferOutCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct WireOutSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
wire_out_serial_helper_cb (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct WireOutSerialContext *wosc = cls;
  struct PostgresClosure *pg = wosc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct GNUNET_TIME_Absolute date;
    struct TALER_WireTransferIdentifierRawP wtid;
    json_t *wire;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("wireout_uuid",
                                    &rowid),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                          &date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &wtid),
      TALER_PQ_result_spec_json ("wire_target",
                                 &wire),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      wosc->status = GNUNET_SYSERR;
      return;
    }
    ret = wosc->cb (wosc->cb_cls,
                    rowid,
                    date,
                    &wtid,
                    wire,
                    &amount);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select all wire transfers the exchange
 * executed.
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_wire_out_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_WireTransferOutCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct WireOutSerialContext wosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_get_wire_incr",
                                             params,
                                             &wire_out_serial_helper_cb,
                                             &wosc);
  if (GNUNET_OK != wosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Function called to select all wire transfers the exchange
 * executed by account.
 *
 * @param cls closure
 * @param session database connection
 * @param account_name account to select
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_wire_out_above_serial_id_by_account (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const char *account_name,
  uint64_t serial_id,
  TALER_EXCHANGEDB_WireTransferOutCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_string (account_name),
    GNUNET_PQ_query_param_end
  };
  struct WireOutSerialContext wosc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "audit_get_wire_incr_by_account",
                                             params,
                                             &wire_out_serial_helper_cb,
                                             &wosc);
  if (GNUNET_OK != wosc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #recoup_serial_helper_cb().
 */
struct RecoupSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RecoupCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct RecoupSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
recoup_serial_helper_cb (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct RecoupSerialContext *psc = cls;
  struct PostgresClosure *pg = psc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_CoinPublicInfo coin;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_Amount amount;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_HashCode h_blind_ev;
    struct GNUNET_TIME_Absolute timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("recoup_uuid",
                                    &rowid),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                          &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                           &coin.denom_sig.rsa_signature),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      psc->status = GNUNET_SYSERR;
      return;
    }
    ret = psc->cb (psc->cb_cls,
                   rowid,
                   timestamp,
                   &amount,
                   &reserve_pub,
                   &coin,
                   &denom_pub,
                   &coin_sig,
                   &coin_blind);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select recoup requests the exchange
 * received, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_recoup_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RecoupCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RecoupSerialContext psc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "recoup_get_incr",
                                             params,
                                             &recoup_serial_helper_cb,
                                             &psc);
  if (GNUNET_OK != psc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #recoup_refresh_serial_helper_cb().
 */
struct RecoupRefreshSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_RecoupRefreshCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct RecoupRefreshSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
recoup_refresh_serial_helper_cb (void *cls,
                                 PGresult *result,
                                 unsigned int num_results)
{
  struct RecoupRefreshSerialContext *psc = cls;
  struct PostgresClosure *pg = psc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_CoinSpendPublicKeyP old_coin_pub;
    struct TALER_CoinPublicInfo coin;
    struct TALER_CoinSpendSignatureP coin_sig;
    struct TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_DenominationPublicKey denom_pub;
    struct GNUNET_HashCode old_denom_pub_hash;
    struct TALER_Amount amount;
    struct GNUNET_HashCode h_blind_ev;
    struct GNUNET_TIME_Absolute timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                    &rowid),
      TALER_PQ_result_spec_absolute_time ("timestamp",
                                          &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                            &old_coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("old_denom_pub_hash",
                                            &old_denom_pub_hash),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      GNUNET_PQ_result_spec_rsa_public_key ("denom_pub",
                                            &denom_pub.rsa_public_key),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_rsa_signature ("denom_sig",
                                           &coin.denom_sig.rsa_signature),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      psc->status = GNUNET_SYSERR;
      return;
    }
    ret = psc->cb (psc->cb_cls,
                   rowid,
                   timestamp,
                   &amount,
                   &old_coin_pub,
                   &old_denom_pub_hash,
                   &coin,
                   &denom_pub,
                   &coin_sig,
                   &coin_blind);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select recoup requests the exchange received for
 * refreshed coins, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_recoup_refresh_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RecoupRefreshCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct RecoupRefreshSerialContext psc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "recoup_refresh_get_incr",
                                             params,
                                             &recoup_refresh_serial_helper_cb,
                                             &psc);
  if (GNUNET_OK != psc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #reserve_closed_serial_helper_cb().
 */
struct ReserveClosedSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_ReserveClosedCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin's context.
   */
  struct PostgresClosure *pg;

  /**
   * Status code, set to #GNUNET_SYSERR on hard errors.
   */
  int status;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct ReserveClosedSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
reserve_closed_serial_helper_cb (void *cls,
                                 PGresult *result,
                                 unsigned int num_results)
{
  struct ReserveClosedSerialContext *rcsc = cls;
  struct PostgresClosure *pg = rcsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_ReservePublicKeyP reserve_pub;
    char *receiver_account;
    struct TALER_WireTransferIdentifierRawP wtid;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount closing_fee;
    struct GNUNET_TIME_Absolute execution_date;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("close_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      TALER_PQ_result_spec_absolute_time ("execution_date",
                                          &execution_date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid",
                                            &wtid),
      GNUNET_PQ_result_spec_string ("receiver_account",
                                    &receiver_account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &closing_fee),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      rcsc->status = GNUNET_SYSERR;
      return;
    }
    ret = rcsc->cb (rcsc->cb_cls,
                    rowid,
                    execution_date,
                    &amount_with_fee,
                    &closing_fee,
                    &reserve_pub,
                    receiver_account,
                    &wtid);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Function called to select reserve close operations the aggregator
 * triggered, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param session database connection
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserve_closed_above_serial_id (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  uint64_t serial_id,
  TALER_EXCHANGEDB_ReserveClosedCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct ReserveClosedSerialContext rcsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "reserves_close_get_incr",
                                             params,
                                             &reserve_closed_serial_helper_cb,
                                             &rcsc);
  if (GNUNET_OK != rcsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Function called to add a request for an emergency recoup for a
 * coin.  The funds are to be added back to the reserve.  The function
 * should return the @a deadline by which the exchange will trigger a
 * wire transfer back to the customer's account for the reserve.
 *
 * @param cls closure
 * @param session database connection
 * @param reserve_pub public key of the reserve that is being refunded
 * @param coin information about the coin
 * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding key of the coin
 * @param amount total amount to be paid back
 * @param h_blind_ev hash of the blinded coin's envelope (must match reserves_out entry)
 * @param timestamp current time (rounded)
 * @return transaction result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_recoup_request (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_DenominationBlindingKeyP *coin_blind,
  const struct TALER_Amount *amount,
  const struct GNUNET_HashCode *h_blind_ev,
  struct GNUNET_TIME_Absolute timestamp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_auto_from_type (coin_blind),
    TALER_PQ_query_param_amount (amount),
    TALER_PQ_query_param_absolute_time (&timestamp),
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  /* now store actual recoup information */
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "recoup_insert",
                                           params);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* Update reserve balance */
  reserve.pub = *reserve_pub;
  qs = postgres_reserves_get (cls,
                              session,
                              &reserve);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 >
      TALER_amount_add (&reserve.balance,
                        &reserve.balance,
                        amount))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Inserting recoup for coin %s\n",
              TALER_B2S (&coin->coin_pub));
  expiry = GNUNET_TIME_absolute_add (timestamp,
                                     pg->legal_reserve_expiration_time);
  reserve.gc = GNUNET_TIME_absolute_max (expiry,
                                         reserve.gc);
  (void) GNUNET_TIME_round_abs (&reserve.gc);
  expiry = GNUNET_TIME_absolute_add (timestamp,
                                     pg->idle_reserve_expiration_time);
  reserve.expiry = GNUNET_TIME_absolute_max (expiry,
                                             reserve.expiry);
  (void) GNUNET_TIME_round_abs (&reserve.expiry);
  qs = reserves_update (cls,
                        session,
                        &reserve);
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return qs;
}


/**
 * Function called to add a request for an emergency recoup for a
 * refreshed coin.  The funds are to be added back to the original coin
 * (which is implied via @a h_blind_ev, see the prepared statement
 * "recoup_by_old_coin" used in #postgres_get_coin_transactions()).
 *
 * @param cls closure
 * @param session database connection
 * @param coin public information about the refreshed coin
 * @param coin_sig signature of the coin of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding key of the coin
 * @param h_blind_ev blinded envelope, as calculated by the exchange
 * @param amount total amount to be paid back
 * @param h_blind_ev hash of the blinded coin's envelope (must match reserves_out entry)
 * @param timestamp a timestamp to store
 * @return transaction result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_recoup_refresh_request (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_DenominationBlindingKeyP *coin_blind,
  const struct TALER_Amount *amount,
  const struct GNUNET_HashCode *h_blind_ev,
  struct GNUNET_TIME_Absolute timestamp)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_auto_from_type (coin_blind),
    TALER_PQ_query_param_amount (amount),
    TALER_PQ_query_param_absolute_time (&timestamp),
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  /* now store actual recoup information */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Inserting recoup-refresh for coin %s\n",
              TALER_B2S (&coin->coin_pub));
  qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                           "recoup_refresh_insert",
                                           params);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return qs;
}


/**
 * Obtain information about which reserve a coin was generated
 * from given the hash of the blinded coin.
 *
 * @param cls closure
 * @param session a session
 * @param h_blind_ev hash of the blinded coin
 * @param[out] reserve_pub set to information about the reserve (on success only)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_by_h_blind (void *cls,
                                 struct TALER_EXCHANGEDB_Session *session,
                                 const struct GNUNET_HashCode *h_blind_ev,
                                 struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          reserve_pub),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "reserve_by_h_blind",
                                                   params,
                                                   rs);
}


/**
 * Obtain information about which old coin a coin was refreshed
 * given the hash of the blinded (fresh) coin.
 *
 * @param cls closure
 * @param session a session
 * @param h_blind_ev hash of the blinded coin
 * @param[out] old_coin_pub set to information about the old coin (on success only)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_old_coin_by_h_blind (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  const struct GNUNET_HashCode *h_blind_ev,
                                  struct TALER_CoinSpendPublicKeyP *old_coin_pub)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          old_coin_pub),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "old_coin_by_h_blind",
                                                   params,
                                                   rs);
}


/**
 * Store information that a denomination key was revoked
 * in the database.
 *
 * @param cls closure
 * @param session a session
 * @param denom_pub_hash hash of the revoked denomination key
 * @param master_sig signature affirming the revocation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_revocation (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *denom_pub_hash,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  if (NULL == session)
    session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;

  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "denomination_revocation_insert",
                                             params);
}


/**
 * Obtain information about a denomination key's revocation from
 * the database.
 *
 * @param cls closure
 * @param session a session
 * @param denom_pub_hash hash of the revoked denomination key
 * @param[out] master_sig signature affirming the revocation
 * @param[out] rowid row where the information is stored
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_revocation (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *denom_pub_hash,
  struct TALER_MasterSignatureP *master_sig,
  uint64_t *rowid)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig", master_sig),
    GNUNET_PQ_result_spec_uint64 ("denom_revocations_serial_id", rowid),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "denomination_revocation_get",
                                                   params,
                                                   rs);
}


/**
 * Closure for #missing_wire_cb().
 */
struct MissingWireContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_WireMissingCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  int status;
};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
missing_wire_cb (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct MissingWireContext *mwc = cls;
  struct PostgresClosure *pg = mwc->pg;

  while (0 < num_results)
  {
    uint64_t rowid;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_Amount amount;
    json_t *wire;
    struct GNUNET_TIME_Absolute deadline;
    uint8_t tiny;
    uint8_t done;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount),
      TALER_PQ_result_spec_json ("wire",
                                 &wire),
      TALER_PQ_result_spec_absolute_time ("wire_deadline",
                                          &deadline),
      GNUNET_PQ_result_spec_auto_from_type ("tiny",
                                            &tiny),
      GNUNET_PQ_result_spec_auto_from_type ("done",
                                            &done),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  --num_results))
    {
      GNUNET_break (0);
      mwc->status = GNUNET_SYSERR;
      return;
    }
    mwc->cb (mwc->cb_cls,
             rowid,
             &coin_pub,
             &amount,
             wire,
             deadline,
             tiny,
             done);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Select all of those deposits in the database for which we do
 * not have a wire transfer (or a refund) and which should have
 * been deposited between @a start_date and @a end_date.
 *
 * @param cls closure
 * @param session a session
 * @param start_date lower bound on the requested wire execution date
 * @param end_date upper bound on the requested wire execution date
 * @param cb function to call on all such deposits
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_deposits_missing_wire (void *cls,
                                       struct TALER_EXCHANGEDB_Session *session,
                                       struct GNUNET_TIME_Absolute start_date,
                                       struct GNUNET_TIME_Absolute end_date,
                                       TALER_EXCHANGEDB_WireMissingCallback cb,
                                       void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_absolute_time (&start_date),
    TALER_PQ_query_param_absolute_time (&end_date),
    GNUNET_PQ_query_param_end
  };
  struct MissingWireContext mwc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "deposits_get_overdue",
                                             params,
                                             &missing_wire_cb,
                                             &mwc);
  if (GNUNET_OK != mwc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Check the last date an auditor was modified.
 *
 * @param cls closure
 * @param session a session
 * @param auditor_pub key to look up information for
 * @param[out] last_date last modification date to auditor status
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_auditor_timestamp (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Absolute *last_date)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_absolute_time ("last_change",
                                        last_date),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "lookup_auditor_timestamp",
                                                   params,
                                                   rs);
}


/**
 * Lookup current state of an auditor.
 *
 * @param cls closure
 * @param session a session
 * @param auditor_pub key to look up information for
 * @param[out] auditor_url set to the base URL of the auditor's REST API; memory to be
 *            released by the caller!
 * @param[out] enabled set if the auditor is currently in use
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_auditor_status (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const struct
                                TALER_AuditorPublicKeyP *auditor_pub,
                                char **auditor_url,
                                bool *enabled)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_end
  };
  uint8_t enabled8 = 0;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("auditor_url",
                                  auditor_url),
    GNUNET_PQ_result_spec_auto_from_type ("is_active",
                                          &enabled8),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                 "lookup_auditor_status",
                                                 params,
                                                 rs);
  *enabled = (0 != enabled8);
  return qs;
}


/**
 * Insert information about an auditor that will audit this exchange.
 *
 * @param cls closure
 * @param session a session
 * @param auditor_pub key of the auditor
 * @param auditor_url base URL of the auditor's REST service
 * @param auditor_name name of the auditor (for humans)
 * @param start_date date when the auditor was added by the offline system
 *                      (only to be used for replay detection)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                         struct GNUNET_TIME_Absolute start_date)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_string (auditor_name),
    GNUNET_PQ_query_param_string (auditor_url),
    GNUNET_PQ_query_param_absolute_time (&start_date),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_auditor",
                                             params);
}


/**
 * Update information about an auditor that will audit this exchange.
 *
 * @param cls closure
 * @param session a session
 * @param auditor_pub key of the auditor (primary key for the existing record)
 * @param auditor_url base URL of the auditor's REST service, to be updated
 * @param auditor_name name of the auditor (for humans)
 * @param change_date date when the auditor status was last changed
 *                      (only to be used for replay detection)
 * @param enabled true to enable, false to disable
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_auditor (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                         struct GNUNET_TIME_Absolute change_date,
                         bool enabled)
{
  uint8_t enabled8 = enabled ? 1 : 0;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_string (auditor_url),
    GNUNET_PQ_query_param_string (auditor_name),
    GNUNET_PQ_query_param_auto_from_type (&enabled8),
    GNUNET_PQ_query_param_absolute_time (&change_date),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "update_auditor",
                                             params);
}


/**
 * Check the last date an exchange wire account was modified.
 *
 * @param cls closure
 * @param session a session
 * @param payto_uri key to look up information for
 * @param[out] last_date last modification date to auditor status
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_timestamp (void *cls,
                                struct TALER_EXCHANGEDB_Session *session,
                                const char *payto_uri,
                                struct GNUNET_TIME_Absolute *last_date)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_absolute_time ("last_change",
                                        last_date),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "lookup_wire_timestamp",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an wire account used by this exchange.
 *
 * @param cls closure
 * @param session a session
 * @param payto_uri wire account of the exchange
 * @param start_date date when the account was added by the offline system
 *                      (only to be used for replay detection)
 * @param master_sig public signature affirming the existence of the account,
 *         must be of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire (void *cls,
                      struct TALER_EXCHANGEDB_Session *session,
                      const char *payto_uri,
                      struct GNUNET_TIME_Absolute start_date,
                      const struct TALER_MasterSignatureP *master_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_absolute_time (&start_date),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_wire",
                                             params);
}


/**
 * Update information about a wire account of the exchange.
 *
 * @param cls closure
 * @param session a session
 * @param payto_uri account the update is about
 * @param change_date date when the account status was last changed
 *                      (only to be used for replay detection)
 * @param enabled true to enable, false to disable (the actual change)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire (void *cls,
                      struct TALER_EXCHANGEDB_Session *session,
                      const char *payto_uri,
                      struct GNUNET_TIME_Absolute change_date,
                      bool enabled)
{
  uint8_t enabled8 = enabled ? 1 : 0;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_auto_from_type (&enabled8),
    GNUNET_PQ_query_param_absolute_time (&change_date),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "update_wire",
                                             params);
}


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
  int status;

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
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
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
    ctx->cb (ctx->cb_cls,
             payto_uri,
             &master_sig);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Obtain information about the enabled wire accounts of the exchange.
 *
 * @param cls closure
 * @param cb function to call on each account
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_accounts (void *cls,
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
  struct TALER_EXCHANGEDB_Session *session;

  session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_wire_accounts",
                                             params,
                                             &get_wire_accounts_cb,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;

}


/**
 * Closure for #get_wire_fees_cb().
 */
struct GetWireFeesContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_WireFeeCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Flag set to #GNUNET_OK as long as everything is fine.
   */
  int status;

};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_wire_fees_cb (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct GetWireFeesContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_MasterSignatureP master_sig;
    struct TALER_Amount wire_fee;
    struct TALER_Amount closing_fee;
    struct GNUNET_TIME_Absolute start_date;
    struct GNUNET_TIME_Absolute end_date;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &wire_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &closing_fee),
      TALER_PQ_result_spec_absolute_time ("start_date",
                                          &start_date),
      TALER_PQ_result_spec_absolute_time ("end_date",
                                          &end_date),
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
    ctx->cb (ctx->cb_cls,
             &wire_fee,
             &closing_fee,
             start_date,
             end_date,
             &master_sig);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Obtain information about the fee structure of the exchange for
 * a given @a wire_method
 *
 * @param cls closure
 * @param wire_method which wire method to obtain fees for
 * @param cb function to call on each account
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_fees (void *cls,
                        const char *wire_method,
                        TALER_EXCHANGEDB_WireFeeCallback cb,
                        void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (wire_method),
    GNUNET_PQ_query_param_end
  };
  struct GetWireFeesContext ctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_Session *session;

  session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             "get_wire_fees",
                                             params,
                                             &get_wire_fees_cb,
                                             &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Store information about a revoked online signing key.
 *
 * @param cls closure
 * @param session a session (can be NULL)
 * @param exchange_pub exchange online signing key that was revoked
 * @param master_sig signature affirming the revocation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_signkey_revocation (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_signkey_revocation",
                                             params);
}


/**
 * Obtain information about a revoked online signing key.
 *
 * @param cls closure
 * @param session a session (can be NULL)
 * @param exchange_pub exchange online signing key
 * @param[out] master_sig set to signature affirming the revocation (if revoked)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_signkey_revocation (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  if (NULL == session)
    session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "lookup_signkey_revocation",
                                                   params,
                                                   rs);
}


/**
 * Lookup information about current denomination key.
 *
 * @param cls closure
 * @param session a session
 * @param h_denom_pub hash of the denomination public key
 * @param[out] meta set to various meta data about the key
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_denomination_key (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_denom_pub,
  struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_absolute_time ("valid_from",
                                        &meta->start),
    TALER_PQ_result_spec_absolute_time ("expire_withdraw",
                                        &meta->expire_withdraw),
    TALER_PQ_result_spec_absolute_time ("expire_deposit",
                                        &meta->expire_deposit),
    TALER_PQ_result_spec_absolute_time ("expire_legal",
                                        &meta->expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                 &meta->value),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &meta->fee_withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &meta->fee_deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &meta->fee_refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                 &meta->fee_refund),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "lookup_denomination_key",
                                                   params,
                                                   rs);
}


/**
 * Activate denomination key, turning it into a "current" or "valid"
 * denomination key by adding the master signature.
 *
 * @param cls closure
 * @param session a session
 * @param h_denom_pub hash of the denomination public key
 * @param denom_pub the actual denomination key
 * @param meta meta data about the denomination
 * @param master_sig master signature to add
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_add_denomination_key (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_rsa_public_key (denom_pub->rsa_public_key),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    TALER_PQ_query_param_absolute_time (&meta->start),
    TALER_PQ_query_param_absolute_time (&meta->expire_withdraw),
    TALER_PQ_query_param_absolute_time (&meta->expire_deposit),
    TALER_PQ_query_param_absolute_time (&meta->expire_legal),
    TALER_PQ_query_param_amount (&meta->value),
    TALER_PQ_query_param_amount (&meta->fee_withdraw),
    TALER_PQ_query_param_amount (&meta->fee_deposit),
    TALER_PQ_query_param_amount (&meta->fee_refresh),
    TALER_PQ_query_param_amount (&meta->fee_refund),
    GNUNET_PQ_query_param_end
  };

  if (NULL == session)
    session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  /* Sanity check: ensure fees match coin currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&meta->value,
                                            &meta->fee_withdraw));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&meta->value,
                                            &meta->fee_deposit));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&meta->value,
                                            &meta->fee_refresh));
  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&meta->value,
                                            &meta->fee_refund));
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "denomination_insert",
                                             iparams);
}


/**
 * Add signing key.
 *
 * @param cls closure
 * @param session a session
 * @param exchange_pub the exchange online signing public key
 * @param meta meta data about @a exchange_pub
 * @param master_sig master signature to add
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_activate_signing_key (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_EXCHANGEDB_SignkeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    TALER_PQ_query_param_absolute_time (&meta->start),
    TALER_PQ_query_param_absolute_time (&meta->expire_sign),
    TALER_PQ_query_param_absolute_time (&meta->expire_legal),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  if (NULL == session)
    session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_signkey",
                                             iparams);
}


/**
 * Lookup signing key meta data.
 *
 * @param cls closure
 * @param session a session
 * @param exchange_pub the exchange online signing public key
 * @param[out] meta meta data about @a exchange_pub
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_signing_key (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_EXCHANGEDB_SignkeyMetaData *meta)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_result_spec_absolute_time ("valid_from",
                                        &meta->start),
    TALER_PQ_result_spec_absolute_time ("expire_sign",
                                        &meta->expire_sign),
    TALER_PQ_result_spec_absolute_time ("expire_legal",
                                        &meta->expire_legal),
    GNUNET_PQ_result_spec_end
  };

  if (NULL == session)
    session = postgres_get_session (pg);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "lookup_signing_key",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an auditor auditing a denomination key.
 *
 * @param cls closure
 * @param session a session
 * @param h_denom_pub the audited denomination
 * @param auditor_pub the auditor's key
 * @param auditor_sig signature affirming the auditor's audit activity
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_denom_sig (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_auto_from_type (auditor_sig),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "insert_auditor_denom_sig",
                                             params);
}


/**
 * Select information about an auditor auditing a denomination key.
 *
 * @param cls closure
 * @param session a session
 * @param h_denom_pub the audited denomination
 * @param auditor_pub the auditor's key
 * @param[out] auditor_sig set to signature affirming the auditor's audit activity
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_auditor_denom_sig (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct TALER_AuditorSignatureP *auditor_sig)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("auditor_sig",
                                          auditor_sig),
    GNUNET_PQ_result_spec_end
  };

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   "select_auditor_denom_sig",
                                                   params,
                                                   rs);
}


/**
 * Closure for #wire_fee_by_time_helper()
 */
struct WireFeeLookupContext
{

  /**
   * Set to the wire fee. Set to invalid if fees conflict over
   * the given time period.
   */
  struct TALER_Amount *wire_fee;

  /**
   * Set to the closing fee. Set to invalid if fees conflict over
   * the given time period.
   */
  struct TALER_Amount *closing_fee;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_iterate_denomination_info().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct DenomIteratorContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
wire_fee_by_time_helper (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct WireFeeLookupContext *wlc = cls;
  struct PostgresClosure *pg = wlc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount wf;
    struct TALER_Amount cf;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &wf),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &cf),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      /* invalidate */
      memset (wlc->wire_fee,
              0,
              sizeof (struct TALER_Amount));
      memset (wlc->closing_fee,
              0,
              sizeof (struct TALER_Amount));
      return;
    }
    if (0 == i)
    {
      *wlc->wire_fee = wf;
      *wlc->closing_fee = cf;
      continue;
    }
    if ( (GNUNET_YES !=
          TALER_amount_cmp_currency (&wf,
                                     wlc->wire_fee)) ||
         (GNUNET_YES !=
          TALER_amount_cmp_currency (&cf,
                                     wlc->closing_fee)) ||
         (0 !=
          TALER_amount_cmp (&wf,
                            wlc->wire_fee)) ||
         (0 !=
          TALER_amount_cmp (&cf,
                            wlc->closing_fee)) )
    {
      /* invalidate */
      memset (wlc->wire_fee,
              0,
              sizeof (struct TALER_Amount));
      memset (wlc->closing_fee,
              0,
              sizeof (struct TALER_Amount));
      return;
    }
  }
}


/**
 * Lookup information about known wire fees.  Finds all applicable
 * fees in the given range. If they are identical, returns the
 * respective @a wire_fee and @a closing_fee. If any of the fees
 * differ between @a start_time and @a end_time, the transaction
 * succeeds BUT returns an invalid amount for both fees.
 *
 * @param cls closure
 * @param session a session
 * @param wire_method the wire method to lookup fees for
 * @param start_time starting time of fee
 * @param end_time end time of fee
 * @param[out] wire_fee wire fee for that time period; if
 *             different wire fee exists within this time
 *             period, an 'invalid' amount is returned.
 * @param[out] closing_fee wire fee for that time period; if
 *             different wire fee exists within this time
 *             period, an 'invalid' amount is returned.
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_fee_by_time (
  void *cls,
  struct TALER_EXCHANGEDB_Session *session,
  const char *wire_method,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Absolute end_time,
  struct TALER_Amount *wire_fee,
  struct TALER_Amount *closing_fee)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (wire_method),
    GNUNET_PQ_query_param_absolute_time (&start_time),
    GNUNET_PQ_query_param_absolute_time (&end_time),
    GNUNET_PQ_query_param_end
  };
  struct WireFeeLookupContext wlc = {
    .wire_fee = wire_fee,
    .closing_fee = closing_fee,
    .pg = pc,
  };

  if (NULL == session)
    session = postgres_get_session (pc);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                               "lookup_wire_fee_by_time",
                                               params,
                                               &wire_fee_by_time_helper,
                                               &wlc);
}


/**
 * Lookup the latest serial number of @a table.  Used in
 * exchange-auditor database replication.
 *
 * @param cls closure
 * @param session a session
 * @param table table for which we should return the serial
 * @param[out] serial latest serial number in use
 * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
 *         @a table does not have a serial number
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_serial_by_table (void *cls,
                                 struct TALER_EXCHANGEDB_Session *session,
                                 enum TALER_EXCHANGEDB_ReplicatedTable table,
                                 uint64_t *serial)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("serial",
                                  serial),
    GNUNET_PQ_result_spec_end
  };
  const char *statement;

  switch (table)
  {
  case TALER_EXCHANGEDB_RT_DENOMINATIONS:
    statement = "select_serial_by_table_denominations";
    break;
  case TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS:
    statement = "select_serial_by_table_denomination_revocations";
    break;
  case TALER_EXCHANGEDB_RT_RESERVES:
    statement = "select_serial_by_table_reserves";
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_IN:
    statement = "select_serial_by_table_reserves_in";
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_CLOSE:
    statement = "select_serial_by_table_reserves_close";
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OUT:
    statement = "select_serial_by_table_reserves_out";
    break;
  case TALER_EXCHANGEDB_RT_AUDITORS:
    statement = "select_serial_by_table_auditors";
    break;
  case TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS:
    statement = "select_serial_by_table_auditor_denom_sigs";
    break;
  case TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS:
    statement = "select_serial_by_table_exchange_sign_keys";
    break;
  case TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS:
    statement = "select_serial_by_table_signkey_revocations";
    break;
  case TALER_EXCHANGEDB_RT_KNOWN_COINS:
    statement = "select_serial_by_table_known_coins";
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS:
    statement = "select_serial_by_table_refresh_commitments";
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS:
    statement = "select_serial_by_table_refresh_revealed_coins";
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS:
    statement = "select_serial_by_table_refresh_transfer_keys";
    break;
  case TALER_EXCHANGEDB_RT_DEPOSITS:
    statement = "select_serial_by_table_deposits";
    break;
  case TALER_EXCHANGEDB_RT_REFUNDS:
    statement = "select_serial_by_table_refunds";
    break;
  case TALER_EXCHANGEDB_RT_WIRE_OUT:
    statement = "select_serial_by_table_wire_out";
    break;
  case TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING:
    statement = "select_serial_by_table_aggregation_tracking";
    break;
  case TALER_EXCHANGEDB_RT_WIRE_FEE:
    statement = "select_serial_by_table_wire_fee";
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    statement = "select_serial_by_table_recoup";
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    statement = "select_serial_by_table_recoup_refresh";
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  (void) cls;
  return GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                   statement,
                                                   params,
                                                   rs);
}


/**
 * Closure for callbacks used by #postgres_lookup_records_by_table.
 */
struct LookupRecordsByTableContext
{
  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Function to call with the results.
   */
  TALER_EXCHANGEDB_ReplicationCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Set to true on errors.
   */
  bool error;
};


#include "lrbt_callbacks.c"


/**
 * Lookup records above @a serial number in @a table. Used in
 * exchange-auditor database replication.
 *
 * @param cls closure
 * @param session a session
 * @param table table for which we should return the serial
 * @param serial largest serial number to exclude
 * @param cb function to call on the records
 * @param cb_cls closure for @a cb
 * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
 *         @a table does not have a serial number
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_records_by_table (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  enum TALER_EXCHANGEDB_ReplicatedTable table,
                                  uint64_t serial,
                                  TALER_EXCHANGEDB_ReplicationCallback cb,
                                  void *cb_cls)
{
  struct PostgresClosure *pc = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial),
    GNUNET_PQ_query_param_end
  };
  struct LookupRecordsByTableContext ctx = {
    .pg = pc,
    .cb = cb,
    .cb_cls = cb_cls
  };
  GNUNET_PQ_PostgresResultHandler rh;
  const char *statement;
  enum GNUNET_DB_QueryStatus qs;

  switch (table)
  {
  case TALER_EXCHANGEDB_RT_DENOMINATIONS:
    statement = "select_above_serial_by_table_denominations";
    rh = &lrbt_cb_table_denominations;
    break;
  case TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS:
    statement = "select_above_serial_by_table_denomination_revocations";
    rh = &lrbt_cb_table_denomination_revocations;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES:
    statement = "select_above_serial_by_table_reserves";
    rh = &lrbt_cb_table_reserves;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_IN:
    statement = "select_above_serial_by_table_reserves_in";
    rh = &lrbt_cb_table_reserves_in;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_CLOSE:
    statement = "select_above_serial_by_table_reserves_close";
    rh = &lrbt_cb_table_reserves_close;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OUT:
    statement = "select_above_serial_by_table_reserves_out";
    rh = &lrbt_cb_table_reserves_out;
    break;
  case TALER_EXCHANGEDB_RT_AUDITORS:
    statement = "select_above_serial_by_table_auditors";
    rh = &lrbt_cb_table_auditors;
    break;
  case TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS:
    statement = "select_above_serial_by_table_auditor_denom_sigs";
    rh = &lrbt_cb_table_auditor_denom_sigs;
    break;
  case TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS:
    statement = "select_above_serial_by_table_exchange_sign_keys";
    rh = &lrbt_cb_table_exchange_sign_keys;
    break;
  case TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS:
    statement = "select_above_serial_by_table_signkey_revocations";
    rh = &lrbt_cb_table_signkey_revocations;
    break;
  case TALER_EXCHANGEDB_RT_KNOWN_COINS:
    statement = "select_above_serial_by_table_known_coins";
    rh = &lrbt_cb_table_known_coins;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS:
    statement = "select_above_serial_by_table_refresh_commitments";
    rh = &lrbt_cb_table_refresh_commitments;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS:
    statement = "select_above_serial_by_table_refresh_revealed_coins";
    rh = &lrbt_cb_table_refresh_revealed_coins;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS:
    statement = "select_above_serial_by_table_refresh_transfer_keys";
    rh = &lrbt_cb_table_refresh_transfer_keys;
    break;
  case TALER_EXCHANGEDB_RT_DEPOSITS:
    statement = "select_above_serial_by_table_deposits";
    rh = &lrbt_cb_table_deposits;
    break;
  case TALER_EXCHANGEDB_RT_REFUNDS:
    statement = "select_above_serial_by_table_refunds";
    rh = &lrbt_cb_table_refunds;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_OUT:
    statement = "select_above_serial_by_table_wire_out";
    rh = &lrbt_cb_table_wire_out;
    break;
  case TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING:
    statement = "select_above_serial_by_table_aggregation_tracking";
    rh = &lrbt_cb_table_aggregation_tracking;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_FEE:
    statement = "select_above_serial_by_table_wire_fee";
    rh = &lrbt_cb_table_wire_fee;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    statement = "select_above_serial_by_table_recoup";
    rh = &lrbt_cb_table_recoup;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    statement = "select_above_serial_by_table_recoup_refresh";
    rh = &lrbt_cb_table_recoup_refresh;
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  (void) cls;
  qs = GNUNET_PQ_eval_prepared_multi_select (session->conn,
                                             statement,
                                             params,
                                             rh,
                                             &ctx);
  if (qs < 0)
    return qs;
  if (ctx.error)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Signature of helper functions of #postgres_insert_records_by_table.
 *
 * @param pg plugin context
 * @param session database session
 * @param td record to insert
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*InsertRecordCallback)(struct PostgresClosure *pg,
                        struct TALER_EXCHANGEDB_Session *session,
                        const struct TALER_EXCHANGEDB_TableData *td);


#include "irbt_callbacks.c"


/**
 * Insert record set into @a table.  Used in exchange-auditor database
 * replication.
 *
 * @param cls closure
 * @param session a session
 * @param td table data to insert
 * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
 *         @e table in @a tr is not supported
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_records_by_table (void *cls,
                                  struct TALER_EXCHANGEDB_Session *session,
                                  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct PostgresClosure *pg = cls;
  InsertRecordCallback rh;

  switch (td->table)
  {
  case TALER_EXCHANGEDB_RT_DENOMINATIONS:
    rh = &irbt_cb_table_denominations;
    break;
  case TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS:
    rh = &irbt_cb_table_denomination_revocations;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES:
    rh = &irbt_cb_table_reserves;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_IN:
    rh = &irbt_cb_table_reserves_in;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_CLOSE:
    rh = &irbt_cb_table_reserves_close;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OUT:
    rh = &irbt_cb_table_reserves_out;
    break;
  case TALER_EXCHANGEDB_RT_AUDITORS:
    rh = &irbt_cb_table_auditors;
    break;
  case TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS:
    rh = &irbt_cb_table_auditor_denom_sigs;
    break;
  case TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS:
    rh = &irbt_cb_table_exchange_sign_keys;
    break;
  case TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS:
    rh = &irbt_cb_table_signkey_revocations;
    break;
  case TALER_EXCHANGEDB_RT_KNOWN_COINS:
    rh = &irbt_cb_table_known_coins;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS:
    rh = &irbt_cb_table_refresh_commitments;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS:
    rh = &irbt_cb_table_refresh_revealed_coins;
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS:
    rh = &irbt_cb_table_refresh_transfer_keys;
    break;
  case TALER_EXCHANGEDB_RT_DEPOSITS:
    rh = &irbt_cb_table_deposits;
    break;
  case TALER_EXCHANGEDB_RT_REFUNDS:
    rh = &irbt_cb_table_refunds;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_OUT:
    rh = &irbt_cb_table_wire_out;
    break;
  case TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING:
    rh = &irbt_cb_table_aggregation_tracking;
    break;
  case TALER_EXCHANGEDB_RT_WIRE_FEE:
    rh = &irbt_cb_table_wire_fee;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    rh = &irbt_cb_table_recoup;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    rh = &irbt_cb_table_recoup_refresh;
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return rh (pg,
             session,
             td);
}


/**
 * Function called to grab a work shard on an operation @a op. Runs in its
 * own transaction (hence no session provided).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to grab a word shard for
 * @param delay minimum age of a shard to grab
 * @param size desired shard size
 * @param[out] start_row inclusive start row of the shard (returned)
 * @param[out] end_row exclusive end row of the shard (returned)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_begin_shard (void *cls,
                      const char *job_name,
                      struct GNUNET_TIME_Relative delay,
                      uint64_t shard_size,
                      uint64_t *start_row,
                      uint64_t *end_row)
{
  struct TALER_EXCHANGEDB_Session *session;

  session = postgres_get_session (cls);
  if (NULL == session)
    return GNUNET_DB_STATUS_HARD_ERROR;
  for (unsigned int retries = 0; retries<3; retries++)
  {
    if (GNUNET_OK !=
        postgres_start (cls,
                        session,
                        "begin_shard"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    {
      struct GNUNET_TIME_Absolute past;
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&past),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint64 ("start_row",
                                      start_row),
        GNUNET_PQ_result_spec_uint64 ("end_row",
                                      end_row),
        GNUNET_PQ_result_spec_end
      };

      past = GNUNET_TIME_absolute_subtract (GNUNET_TIME_absolute_get (),
                                            delay);
      qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                     "get_open_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (cls,
                           session);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (cls,
                           session);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        {
          enum GNUNET_DB_QueryStatus qs;
          struct GNUNET_TIME_Absolute now;
          struct GNUNET_PQ_QueryParam params[] = {
            GNUNET_PQ_query_param_string (job_name),
            GNUNET_PQ_query_param_absolute_time (&now),
            GNUNET_PQ_query_param_uint64 (start_row),
            GNUNET_PQ_query_param_uint64 (end_row),
            GNUNET_PQ_query_param_end
          };

          now = GNUNET_TIME_absolute_get ();
          qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                                   "reclaim_shard",
                                                   params);
          switch (qs)
          {
          case GNUNET_DB_STATUS_HARD_ERROR:
            GNUNET_break (0);
            postgres_rollback (cls,
                               session);
            return qs;
          case GNUNET_DB_STATUS_SOFT_ERROR:
            postgres_rollback (cls,
                               session);
            continue;
          case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
            goto commit;
          case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
            GNUNET_break (0); /* logic error, should be impossible */
            postgres_rollback (cls,
                               session);
            return GNUNET_DB_STATUS_HARD_ERROR;
          }
        }
        break; /* actually unreachable */
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        break; /* continued below */
      }
    } /* get_open_shard */

    /* No open shard, find last 'end_row' */
    {
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint64 ("end_row",
                                      start_row),
        GNUNET_PQ_result_spec_end
      };

      qs = GNUNET_PQ_eval_prepared_singleton_select (session->conn,
                                                     "get_last_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (cls,
                           session);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (cls,
                           session);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        *start_row = 0; /* base-case: no shards yet */
        break; /* continued below */
      }
      *end_row = *start_row + shard_size;
    } /* get_last_shard */

    /* Claim fresh shard */
    {
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_TIME_Absolute now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&now),
        GNUNET_PQ_query_param_uint64 (start_row),
        GNUNET_PQ_query_param_uint64 (end_row),
        GNUNET_PQ_query_param_end
      };

      now = GNUNET_TIME_absolute_get ();
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying to claim shard %llu-%llu\n",
                  (unsigned long long) *start_row,
                  (unsigned long long) *end_row);
      qs = GNUNET_PQ_eval_prepared_non_select (session->conn,
                                               "claim_next_shard",
                                               params);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (cls,
                           session);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (cls,
                           session);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        /* continued below */
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* someone else got this shard already,
           try again */
        postgres_rollback (cls,
                           session);
        continue;
      }
    } /* claim_next_shard */

    /* commit */
commit:
    {
      enum GNUNET_DB_QueryStatus qs;

      qs = postgres_commit (cls,
                            session);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (cls,
                           session);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (cls,
                           session);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
      }
    }
  } /* retry 'for' loop */
  return GNUNET_DB_STATUS_SOFT_ERROR;
}


/**
 * Function called to persist that work on a shard was completed.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param session a session
 * @param job_name name of the operation to grab a word shard for
 * @param start_row inclusive start row of the shard
 * @param end_row exclusive end row of the shard
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_complete_shard (void *cls,
                         struct TALER_EXCHANGEDB_Session *session,
                         const char *job_name,
                         uint64_t start_row,
                         uint64_t end_row)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (job_name),
    GNUNET_PQ_query_param_uint64 (&start_row),
    GNUNET_PQ_query_param_uint64 (&end_row),
    GNUNET_PQ_query_param_end
  };

  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Completing shard %llu-%llu\n",
              (unsigned long long) start_row,
              (unsigned long long) end_row);
  return GNUNET_PQ_eval_prepared_non_select (session->conn,
                                             "complete_shard",
                                             params);
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct
 *         TALER_EXCHANGEDB_Plugin`
 */
void *
libtaler_plugin_exchangedb_postgres_init (void *cls)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct PostgresClosure *pg;
  struct TALER_EXCHANGEDB_Plugin *plugin;

  pg = GNUNET_new (struct PostgresClosure);
  pg->cfg = cfg;
  pg->main_self = pthread_self (); /* loaded while single-threaded! */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchangedb-postgres",
                                               "SQL_DIR",
                                               &pg->sql_dir))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb-postgres",
                               "CONFIG");
    GNUNET_free (pg);
    return NULL;
  }
  if (0 != pthread_key_create (&pg->db_conn_threadlocal,
                               &db_conn_destroy))
  {
    TALER_LOG_ERROR ("Cannot create pthread key.\n");
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  if ( (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_time (cfg,
                                             "exchangedb",
                                             "IDLE_RESERVE_EXPIRATION_TIME",
                                             &pg->idle_reserve_expiration_time))
       ||
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_time (cfg,
                                             "exchangedb",
                                             "LEGAL_RESERVE_EXPIRATION_TIME",
                                             &pg->legal_reserve_expiration_time)) )
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "LEGAL/IDLE_RESERVE_EXPIRATION_TIME");
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &pg->currency))
  {
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_EXCHANGEDB_Plugin);
  plugin->cls = pg;
  plugin->get_session = &postgres_get_session;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->start = &postgres_start;
  plugin->commit = &postgres_commit;
  plugin->preflight = &postgres_preflight;
  plugin->rollback = &postgres_rollback;
  plugin->insert_denomination_info = &postgres_insert_denomination_info;
  plugin->get_denomination_info = &postgres_get_denomination_info;
  plugin->iterate_denomination_info = &postgres_iterate_denomination_info;
  plugin->iterate_denominations = &postgres_iterate_denominations;
  plugin->iterate_active_signkeys = &postgres_iterate_active_signkeys;
  plugin->iterate_active_auditors = &postgres_iterate_active_auditors;
  plugin->iterate_auditor_denominations =
    &postgres_iterate_auditor_denominations;
  plugin->reserves_get = &postgres_reserves_get;
  plugin->reserves_in_insert = &postgres_reserves_in_insert;
  plugin->get_latest_reserve_in_reference =
    &postgres_get_latest_reserve_in_reference;
  plugin->get_withdraw_info = &postgres_get_withdraw_info;
  plugin->insert_withdraw_info = &postgres_insert_withdraw_info;
  plugin->get_reserve_history = &postgres_get_reserve_history;
  plugin->free_reserve_history = &common_free_reserve_history;
  plugin->count_known_coins = &postgres_count_known_coins;
  plugin->ensure_coin_known = &postgres_ensure_coin_known;
  plugin->get_known_coin = &postgres_get_known_coin;
  plugin->get_coin_denomination = &postgres_get_coin_denomination;
  plugin->have_deposit = &postgres_have_deposit;
  plugin->mark_deposit_tiny = &postgres_mark_deposit_tiny;
  plugin->test_deposit_done = &postgres_test_deposit_done;
  plugin->mark_deposit_done = &postgres_mark_deposit_done;
  plugin->get_ready_deposit = &postgres_get_ready_deposit;
  plugin->iterate_matching_deposits = &postgres_iterate_matching_deposits;
  plugin->insert_deposit = &postgres_insert_deposit;
  plugin->insert_refund = &postgres_insert_refund;
  plugin->select_refunds_by_coin = &postgres_select_refunds_by_coin;
  plugin->insert_melt = &postgres_insert_melt;
  plugin->get_melt = &postgres_get_melt;
  plugin->get_melt_index = &postgres_get_melt_index;
  plugin->insert_refresh_reveal = &postgres_insert_refresh_reveal;
  plugin->get_refresh_reveal = &postgres_get_refresh_reveal;
  plugin->get_link_data = &postgres_get_link_data;
  plugin->get_coin_transactions = &postgres_get_coin_transactions;
  plugin->free_coin_transaction_list = &common_free_coin_transaction_list;
  plugin->lookup_wire_transfer = &postgres_lookup_wire_transfer;
  plugin->lookup_transfer_by_deposit = &postgres_lookup_transfer_by_deposit;
  plugin->insert_aggregation_tracking = &postgres_insert_aggregation_tracking;
  plugin->insert_wire_fee = &postgres_insert_wire_fee;
  plugin->get_wire_fee = &postgres_get_wire_fee;
  plugin->get_expired_reserves = &postgres_get_expired_reserves;
  plugin->insert_reserve_closed = &postgres_insert_reserve_closed;
  plugin->wire_prepare_data_insert = &postgres_wire_prepare_data_insert;
  plugin->wire_prepare_data_mark_finished =
    &postgres_wire_prepare_data_mark_finished;
  plugin->wire_prepare_data_mark_failed =
    &postgres_wire_prepare_data_mark_failed;
  plugin->wire_prepare_data_get = &postgres_wire_prepare_data_get;
  plugin->start_deferred_wire_out = &postgres_start_deferred_wire_out;
  plugin->store_wire_transfer_out = &postgres_store_wire_transfer_out;
  plugin->gc = &postgres_gc;
  plugin->select_deposits_above_serial_id
    = &postgres_select_deposits_above_serial_id;
  plugin->select_refreshes_above_serial_id
    = &postgres_select_refreshes_above_serial_id;
  plugin->select_refunds_above_serial_id
    = &postgres_select_refunds_above_serial_id;
  plugin->select_reserves_in_above_serial_id
    = &postgres_select_reserves_in_above_serial_id;
  plugin->select_reserves_in_above_serial_id_by_account
    = &postgres_select_reserves_in_above_serial_id_by_account;
  plugin->select_withdrawals_above_serial_id
    = &postgres_select_withdrawals_above_serial_id;
  plugin->select_wire_out_above_serial_id
    = &postgres_select_wire_out_above_serial_id;
  plugin->select_wire_out_above_serial_id_by_account
    = &postgres_select_wire_out_above_serial_id_by_account;
  plugin->select_recoup_above_serial_id
    = &postgres_select_recoup_above_serial_id;
  plugin->select_recoup_refresh_above_serial_id
    = &postgres_select_recoup_refresh_above_serial_id;
  plugin->select_reserve_closed_above_serial_id
    = &postgres_select_reserve_closed_above_serial_id;
  plugin->insert_recoup_request
    = &postgres_insert_recoup_request;
  plugin->insert_recoup_refresh_request
    = &postgres_insert_recoup_refresh_request;
  plugin->get_reserve_by_h_blind
    = &postgres_get_reserve_by_h_blind;
  plugin->get_old_coin_by_h_blind
    = &postgres_get_old_coin_by_h_blind;
  plugin->insert_denomination_revocation
    = &postgres_insert_denomination_revocation;
  plugin->get_denomination_revocation
    = &postgres_get_denomination_revocation;
  plugin->select_deposits_missing_wire
    = &postgres_select_deposits_missing_wire;
  plugin->lookup_auditor_timestamp
    = &postgres_lookup_auditor_timestamp;
  plugin->lookup_auditor_status
    = &postgres_lookup_auditor_status;
  plugin->insert_auditor
    = &postgres_insert_auditor;
  plugin->update_auditor
    = &postgres_update_auditor;
  plugin->lookup_wire_timestamp
    = &postgres_lookup_wire_timestamp;
  plugin->insert_wire
    = &postgres_insert_wire;
  plugin->update_wire
    = &postgres_update_wire;
  plugin->get_wire_accounts
    = &postgres_get_wire_accounts;
  plugin->get_wire_fees
    = &postgres_get_wire_fees;
  plugin->insert_signkey_revocation
    = &postgres_insert_signkey_revocation;
  plugin->lookup_signkey_revocation
    = &postgres_lookup_signkey_revocation;
  plugin->lookup_denomination_key
    = &postgres_lookup_denomination_key;
  plugin->insert_auditor_denom_sig
    = &postgres_insert_auditor_denom_sig;
  plugin->select_auditor_denom_sig
    = &postgres_select_auditor_denom_sig;
  plugin->lookup_wire_fee_by_time
    = &postgres_lookup_wire_fee_by_time;
  plugin->add_denomination_key
    = &postgres_add_denomination_key;
  plugin->activate_signing_key
    = &postgres_activate_signing_key;
  plugin->lookup_signing_key
    = &postgres_lookup_signing_key;
  plugin->lookup_serial_by_table
    = &postgres_lookup_serial_by_table;
  plugin->lookup_records_by_table
    = &postgres_lookup_records_by_table;
  plugin->insert_records_by_table
    = &postgres_insert_records_by_table;
  plugin->begin_shard
    = &postgres_begin_shard;
  plugin->complete_shard
    = &postgres_complete_shard;
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

  /* If we launched a session for the main thread,
     kill it here before we unload */
  db_conn_destroy (pg->main_session);
  GNUNET_free (pg->sql_dir);
  GNUNET_free (pg->currency);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}


/* end of plugin_exchangedb_postgres.c */
