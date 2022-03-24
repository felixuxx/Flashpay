/*
   This file is part of TALER
   Copyright (C) 2014--2022 Taler Systems SA

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
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
#include <poll.h>
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
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct PostgresClosure
{

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
   * Our base URL.
   */
  char *exchange_url;

  /**
   * Postgres connection handle.
   */
  struct GNUNET_PQ_Context *conn;

  /**
   * Name of the current transaction, for debugging.
   */
  const char *transaction_name;

  /**
   * Did we initialize the prepared statements
   * for this session?
   */
  bool init;

};


/**
 * Drop all Taler tables.  This should only be used by testcases.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_drop_tables (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     "drop",
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  if (NULL != pg->conn)
  {
    GNUNET_PQ_disconnect (pg->conn);
    pg->conn = NULL;
    pg->init = false;
  }
  return GNUNET_OK;
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
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
 * Setup partitions of already existing tables
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param num the number of partitions to create for each partitioned table
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_setup_partitions (void *cls,
                           const uint32_t num)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&num),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("setup_partitions",
                            "SELECT"
                            " create_partitions"
                            " ($1);",
                            1),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     "partition-",
                                     NULL,
                                     ps);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_OK;
  if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "setup_partitions",
                                              params))
    ret = GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/**
 * Initialize prepared statements for @a pg.
 *
 * @param[in,out] pg connection to initialize
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
prepare_statements (struct PostgresClosure *pg)
{
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_PQ_PreparedStatement ps[] = {
    /* Used in #postgres_insert_denomination_info() and
     #postgres_add_denomination_key() */
    GNUNET_PQ_make_prepare (
      "denomination_insert",
      "INSERT INTO denominations "
      "(denom_pub_hash"
      ",denom_pub"
      ",master_sig"
      ",valid_from"
      ",expire_withdraw"
      ",expire_deposit"
      ",expire_legal"
      ",coin_val"                                                /* value of this denom */
      ",coin_frac"                                                /* fractional value of this denom */
      ",fee_withdraw_val"
      ",fee_withdraw_frac"
      ",fee_deposit_val"
      ",fee_deposit_frac"
      ",fee_refresh_val"
      ",fee_refresh_frac"
      ",fee_refund_val"
      ",fee_refund_frac"
      ",age_mask"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
      " $11, $12, $13, $14, $15, $16, $17, $18);",
      18),
    /* Used in #postgres_iterate_denomination_info() */
    GNUNET_PQ_make_prepare (
      "denomination_iterate",
      "SELECT"
      " master_sig"
      ",denom_pub_hash"
      ",valid_from"
      ",expire_withdraw"
      ",expire_deposit"
      ",expire_legal"
      ",coin_val"                                                /* value of this denom */
      ",coin_frac"                                                /* fractional value of this denom */
      ",fee_withdraw_val"
      ",fee_withdraw_frac"
      ",fee_deposit_val"
      ",fee_deposit_frac"
      ",fee_refresh_val"
      ",fee_refresh_frac"
      ",fee_refund_val"
      ",fee_refund_frac"
      ",denom_pub"
      ",age_mask"
      " FROM denominations;",
      0),
    /* Used in #postgres_iterate_denominations() */
    GNUNET_PQ_make_prepare (
      "select_denominations",
      "SELECT"
      " denominations.master_sig"
      ",denom_revocations_serial_id IS NOT NULL AS revoked"
      ",valid_from"
      ",expire_withdraw"
      ",expire_deposit"
      ",expire_legal"
      ",coin_val"                                                /* value of this denom */
      ",coin_frac"                                                /* fractional value of this denom */
      ",fee_withdraw_val"
      ",fee_withdraw_frac"
      ",fee_deposit_val"
      ",fee_deposit_frac"
      ",fee_refresh_val"
      ",fee_refresh_frac"
      ",fee_refund_val"
      ",fee_refund_frac"
      ",denom_type"
      ",age_mask"
      ",denom_pub"
      " FROM denominations"
      " LEFT JOIN "
      "   denomination_revocations USING (denominations_serial);",
      0),
    /* Used in #postgres_iterate_active_signkeys() */
    GNUNET_PQ_make_prepare (
      "select_signkeys",
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
    GNUNET_PQ_make_prepare (
      "select_auditor_denoms",
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
    GNUNET_PQ_make_prepare (
      "select_auditors",
      "SELECT"
      " auditor_pub"
      ",auditor_url"
      ",auditor_name"
      " FROM auditors"
      " WHERE"
      "   is_active;",
      0),
    /* Used in #postgres_get_denomination_info() */
    GNUNET_PQ_make_prepare (
      "denomination_get",
      "SELECT"
      " master_sig"
      ",valid_from"
      ",expire_withdraw"
      ",expire_deposit"
      ",expire_legal"
      ",coin_val"                                                /* value of this denom */
      ",coin_frac"                                                /* fractional value of this denom */
      ",fee_withdraw_val"
      ",fee_withdraw_frac"
      ",fee_deposit_val"
      ",fee_deposit_frac"
      ",fee_refresh_val"
      ",fee_refresh_frac"
      ",fee_refund_val"
      ",fee_refund_frac"
      ",age_mask"
      " FROM denominations"
      " WHERE denom_pub_hash=$1;",
      1),
    /* Used in #postgres_insert_denomination_revocation() */
    GNUNET_PQ_make_prepare (
      "denomination_revocation_insert",
      "INSERT INTO denomination_revocations "
      "(denominations_serial"
      ",master_sig"
      ") SELECT denominations_serial,$2"
      "    FROM denominations"
      "   WHERE denom_pub_hash=$1;",
      2),
    /* Used in #postgres_get_denomination_revocation() */
    GNUNET_PQ_make_prepare (
      "denomination_revocation_get",
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
    GNUNET_PQ_make_prepare (
      "reserves_get_with_kyc",
      "SELECT"
      " current_balance_val"
      ",current_balance_frac"
      ",expiration_date"
      ",gc_date"
      ",kyc_ok"
      ",wire_target_serial_id AS payment_target_uuid"
      " FROM reserves"
      " JOIN reserves_in ri USING (reserve_pub)"
      " JOIN wire_targets wt "
      "  ON (ri.wire_source_h_payto = wt.wire_target_h_payto)"
      " WHERE reserve_pub=$1"
      " LIMIT 1;",
      1),
    /* Used in #postgres_set_kyc_ok() */
    GNUNET_PQ_make_prepare (
      "set_kyc_ok",
      "UPDATE wire_targets"
      " SET kyc_ok=TRUE"
      ",external_id=$2"
      " WHERE wire_target_h_payto=$1",
      2),
    GNUNET_PQ_make_prepare (
      "get_kyc_h_payto",
      "SELECT"
      " wire_target_h_payto"
      " FROM wire_targets"
      " WHERE wire_target_h_payto=$1"
      " LIMIT 1;",
      1),
    /* Used in #postgres_inselect_wallet_kyc_status() */
    GNUNET_PQ_make_prepare (
      "insert_kyc_status",
      "INSERT INTO wire_targets"
      "  (wire_target_h_payto"
      "  ,payto_uri"
      "  ) VALUES "
      "  ($1, $2)"
      " RETURNING wire_target_serial_id",
      2),
    GNUNET_PQ_make_prepare (
      "select_kyc_status_by_payto",
      "SELECT "
      " kyc_ok"
      ",wire_target_serial_id"
      " FROM wire_targets"
      " WHERE wire_target_h_payto=$1;",
      1),
    /* Used in #reserves_get() */
    GNUNET_PQ_make_prepare (
      "reserves_get",
      "SELECT"
      " current_balance_val"
      ",current_balance_frac"
      ",expiration_date"
      ",gc_date"
      " FROM reserves"
      " WHERE reserve_pub=$1"
      " LIMIT 1;",
      1),
    GNUNET_PQ_make_prepare (
      "reserve_create",
      "INSERT INTO reserves "
      "(reserve_pub"
      ",current_balance_val"
      ",current_balance_frac"
      ",expiration_date"
      ",gc_date"
      ") VALUES "
      "($1, $2, $3, $4, $5)"
      " ON CONFLICT DO NOTHING"
      " RETURNING reserve_uuid;",
      5),
    /* Used in #postgres_insert_reserve_closed() */
    GNUNET_PQ_make_prepare (
      "reserves_close_insert",
      "INSERT INTO reserves_close "
      "(reserve_pub"
      ",execution_date"
      ",wtid"
      ",wire_target_h_payto"
      ",amount_val"
      ",amount_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ") VALUES ($1, $2, $3, $4, $5, $6, $7, $8);",
      8),
    /* Used in #reserves_update() when the reserve is updated */
    GNUNET_PQ_make_prepare (
      "reserve_update",
      "UPDATE reserves"
      " SET"
      " expiration_date=$1"
      ",gc_date=$2"
      ",current_balance_val=$3"
      ",current_balance_frac=$4"
      " WHERE reserve_pub=$5;",
      5),
    /* Used in #postgres_reserves_in_insert() to store transaction details */
    GNUNET_PQ_make_prepare (
      "reserves_in_add_transaction",
      "INSERT INTO reserves_in "
      "(reserve_pub"
      ",wire_reference"
      ",credit_val"
      ",credit_frac"
      ",exchange_account_section"
      ",wire_source_h_payto"
      ",execution_date"
      ") VALUES ($1, $2, $3, $4, $5, $6, $7)"
      " ON CONFLICT DO NOTHING;",
      7),
#if FIXME_DEAD
    /* Used in #postgres_reserves_in_insert() to store transaction details */
    GNUNET_PQ_make_prepare (
      "reserves_in_add_by_pub",
      "INSERT INTO reserves_in "
      "(reserve_pub"
      ",wire_reference"
      ",credit_val"
      ",credit_frac"
      ",exchange_account_section"
      ",wire_source_h_payto"
      ",execution_date"
      ") VALUES ($1, $2, $3, $4, $5, $6, $7)"
      " ON CONFLICT DO NOTHING;",
      7),
#endif
    /* Used in postgres_select_reserves_in_above_serial_id() to obtain inbound
       transactions for reserves with serial id '\geq' the given parameter */
    GNUNET_PQ_make_prepare (
      "audit_reserves_in_get_transactions_incr",
      "SELECT"
      " reserves.reserve_pub"
      ",wire_reference"
      ",credit_val"
      ",credit_frac"
      ",execution_date"
      ",payto_uri AS sender_account_details"
      ",reserve_in_serial_id"
      " FROM reserves_in"
      " JOIN reserves"
      "   USING (reserve_pub)"
      " JOIN wire_targets"
      "   ON (wire_source_h_payto = wire_target_h_payto)"
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
      ",payto_uri AS sender_account_details"
      ",reserve_in_serial_id"
      " FROM reserves_in"
      " JOIN reserves "
      "   USING (reserve_pub)"
      " JOIN wire_targets"
      "   ON (wire_source_h_payto = wire_target_h_payto)"
      " WHERE reserve_in_serial_id>=$1 AND exchange_account_section=$2"
      " ORDER BY reserve_in_serial_id;",
      2),
    /* Used in #postgres_get_reserve_history() to obtain inbound transactions
       for a reserve */
    GNUNET_PQ_make_prepare (
      "reserves_in_get_transactions",
      "SELECT"
      " wire_reference"
      ",credit_val"
      ",credit_frac"
      ",execution_date"
      ",payto_uri AS sender_account_details"
      " FROM reserves_in"
      " JOIN wire_targets"
      "   ON (wire_source_h_payto = wire_target_h_payto)"
      " WHERE reserve_pub=$1;",
      1),
    /* Used in #postgres_do_withdraw() to store
       the signature of a blinded coin with the blinded coin's
       details before returning it during /reserve/withdraw. We store
       the coin's denomination information (public key, signature)
       and the blinded message as well as the reserve that the coin
       is being withdrawn from and the signature of the message
       authorizing the withdrawal. */
    GNUNET_PQ_make_prepare (
      "call_withdraw",
      "SELECT "
      " reserve_found"
      ",balance_ok"
      ",kycok AS kyc_ok"
      ",account_uuid AS payment_target_uuid"
      ",ruuid"
      " FROM exchange_do_withdraw"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);",
      10),
    /* Used in #postgres_do_withdraw_limit_check() to check
       if the withdrawals remain below the limit under which
       KYC is not required. */
    GNUNET_PQ_make_prepare (
      "call_withdraw_limit_check",
      "SELECT "
      " below_limit"
      " FROM exchange_do_withdraw_limit_check"
      " ($1,$2,$3,$4);",
      4),
    /* Used in #postgres_do_deposit() to execute a deposit,
       checking the coin's balance in the process as needed. */
    GNUNET_PQ_make_prepare (
      "call_deposit",
      "SELECT "
      " out_exchange_timestamp AS exchange_timestamp"
      ",out_balance_ok AS balance_ok"
      ",out_conflict AS conflicted"
      " FROM exchange_do_deposit"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17);",
      17),
    /* Used in #postgres_do_melt() to melt a coin. */
    GNUNET_PQ_make_prepare (
      "call_melt",
      "SELECT "
      " out_balance_ok AS balance_ok"
      ",out_zombie_bad AS zombie_required"
      ",out_noreveal_index AS noreveal_index"
      " FROM exchange_do_melt"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9);",
      9),
    /* Used in #postgres_do_refund() to refund a deposit. */
    GNUNET_PQ_make_prepare (
      "call_refund",
      "SELECT "
      " out_not_found AS not_found"
      ",out_refund_ok AS refund_ok"
      ",out_gone AS gone"
      ",out_conflict AS conflict"
      " FROM exchange_do_refund"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);",
      13),
    /* Used in #postgres_do_recoup() to recoup a coin to a reserve. */
    GNUNET_PQ_make_prepare (
      "call_recoup",
      "SELECT "
      " out_recoup_timestamp AS recoup_timestamp"
      ",out_recoup_ok AS recoup_ok"
      ",out_internal_failure AS internal_failure"
      " FROM exchange_do_recoup_to_reserve"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9);",
      9),
    /* Used in #postgres_do_recoup_refresh() to recoup a coin to a zombie coin. */
    GNUNET_PQ_make_prepare (
      "call_recoup_refresh",
      "SELECT "
      " out_recoup_timestamp AS recoup_timestamp"
      ",out_recoup_ok AS recoup_ok"
      ",out_internal_failure AS internal_failure"
      " FROM exchange_do_recoup_to_coin"
      " ($1,$2,$3,$4,$5,$6,$7);",
      7),
    /* Used in #postgres_get_withdraw_info() to
       locate the response for a /reserve/withdraw request
       using the hash of the blinded message.  Used to
       make sure /reserve/withdraw requests are idempotent. */
    GNUNET_PQ_make_prepare (
      "get_withdraw_info",
      "SELECT"
      " denom.denom_pub_hash"
      ",denom_sig"
      ",reserve_sig"
      ",reserves.reserve_pub"
      ",execution_date"
      ",h_blind_ev"
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
    GNUNET_PQ_make_prepare (
      "get_reserves_out",
      "SELECT"
      " ro.h_blind_ev"
      ",denom.denom_pub_hash"
      ",ro.denom_sig"
      ",ro.reserve_sig"
      ",ro.execution_date"
      ",ro.amount_with_fee_val"
      ",ro.amount_with_fee_frac"
      ",denom.fee_withdraw_val"
      ",denom.fee_withdraw_frac"
      " FROM reserves res"
      " JOIN reserves_out_by_reserve ror"
      "   ON (res.reserve_uuid = ror.reserve_uuid)"
      " JOIN reserves_out ro"
      "   ON (ro.h_blind_ev = ror.h_blind_ev)"
      " JOIN denominations denom"
      "   ON (ro.denominations_serial = denom.denominations_serial)"
      " WHERE res.reserve_pub=$1;",
      1),
    /* Used in #postgres_select_withdrawals_above_serial_id() */

    GNUNET_PQ_make_prepare (
      "get_reserve_balance",
      "SELECT"
      " current_balance_val"
      ",current_balance_frac"
      " FROM reserves"
      " WHERE reserve_pub=$1;",
      1),
    /* Fetch deposits with rowid '\geq' the given parameter */

    GNUNET_PQ_make_prepare (
      "audit_get_reserves_out_incr",
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
    GNUNET_PQ_make_prepare (
      "count_known_coins",
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
    GNUNET_PQ_make_prepare (
      "get_known_coin",
      "SELECT"
      " denominations.denom_pub_hash"
      ",age_commitment_hash"
      ",denom_sig"
      " FROM known_coins"
      " JOIN denominations USING (denominations_serial)"
      " WHERE coin_pub=$1;",
      1),
    /* Used in #postgres_ensure_coin_known() */
    GNUNET_PQ_make_prepare (
      "get_known_coin_dh",
      "SELECT"
      " denominations.denom_pub_hash"
      " FROM known_coins"
      " JOIN denominations USING (denominations_serial)"
      " WHERE coin_pub=$1;",
      1),
    /* Used in #postgres_get_coin_denomination() to fetch
       the denomination public key hash for
       a coin known to the exchange. */
    GNUNET_PQ_make_prepare (
      "get_coin_denomination",
      "SELECT"
      " denominations.denom_pub_hash"
      ",known_coin_id"
      " FROM known_coins"
      " JOIN denominations USING (denominations_serial)"
      " WHERE coin_pub=$1"
      " FOR SHARE;",
      1),
    /* Used in #postgres_insert_known_coin() to store the denomination public
       key and signature for a coin known to the exchange.

       See also:
       https://stackoverflow.com/questions/34708509/how-to-use-returning-with-on-conflict-in-postgresql/37543015#37543015
     */
    GNUNET_PQ_make_prepare (
      "insert_known_coin",
      "WITH dd"
      "  (denominations_serial"
      "  ,coin_val"
      "  ,coin_frac"
      "  ) AS ("
      "    SELECT "
      "       denominations_serial"
      "      ,coin_val"
      "      ,coin_frac"
      "        FROM denominations"
      "        WHERE denom_pub_hash=$2"
      "  ), input_rows"
      "    (coin_pub) AS ("
      "      VALUES ($1::BYTEA)"
      "  ), ins AS ("
      "  INSERT INTO known_coins "
      "  (coin_pub"
      "  ,denominations_serial"
      "  ,age_commitment_hash"
      "  ,denom_sig"
      "  ,remaining_val"
      "  ,remaining_frac"
      "  ) SELECT "
      "     $1"
      "    ,denominations_serial"
      "    ,$3"
      "    ,$4"
      "    ,coin_val"
      "    ,coin_frac"
      "  FROM dd"
      "  ON CONFLICT DO NOTHING" /* CONFLICT on (coin_pub) */
      "  RETURNING "
      "     known_coin_id"
      "  ) "
      "SELECT "
      "   FALSE AS existed"
      "  ,known_coin_id"
      "  ,NULL AS denom_pub_hash"
      "  ,NULL AS age_commitment_hash"
      "  FROM ins "
      "UNION ALL "
      "SELECT "
      "   TRUE AS existed"
      "  ,known_coin_id"
      "  ,denom_pub_hash"
      "  ,kc.age_commitment_hash"
      "  FROM input_rows"
      "  JOIN known_coins kc USING (coin_pub)"
      "  JOIN denominations USING (denominations_serial)"
      "  LIMIT 1",
      4),

    /* Used in #postgres_get_melt() to fetch
       high-level information about a melt operation */
    GNUNET_PQ_make_prepare (
      "get_melt",
      "SELECT"
      " denoms.denom_pub_hash"
      ",denoms.fee_refresh_val"
      ",denoms.fee_refresh_frac"
      ",old_coin_pub"
      ",old_coin_sig"
      ",kc.age_commitment_hash"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",noreveal_index"
      ",melt_serial_id"
      " FROM refresh_commitments"
      "   JOIN known_coins kc"
      "     ON (old_coin_pub = kc.coin_pub)"
      "   JOIN denominations denoms"
      "     ON (kc.denominations_serial = denoms.denominations_serial)"
      " WHERE rc=$1;",
      1),
    /* Used in #postgres_select_refreshes_above_serial_id() to fetch
       refresh session with id '\geq' the given parameter */
    GNUNET_PQ_make_prepare (
      "audit_get_refresh_commitments_incr",
      "SELECT"
      " denom.denom_pub"
      ",kc.coin_pub AS old_coin_pub"
      ",kc.age_commitment_hash"
      ",old_coin_sig"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",noreveal_index"
      ",melt_serial_id"
      ",rc"
      " FROM refresh_commitments"
      "   JOIN known_coins kc"
      "     ON (refresh_commitments.old_coin_pub = kc.coin_pub)"
      "   JOIN denominations denom"
      "     ON (kc.denominations_serial = denom.denominations_serial)"
      " WHERE melt_serial_id>=$1"
      " ORDER BY melt_serial_id ASC;",
      1),
    /* Query the 'refresh_commitments' by coin public key */
    GNUNET_PQ_make_prepare (
      "get_refresh_session_by_coin",
      "SELECT"
      " rc"
      ",old_coin_sig"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",denoms.denom_pub_hash"
      ",denoms.fee_refresh_val"
      ",denoms.fee_refresh_frac"
      ",kc.age_commitment_hash"
      ",melt_serial_id"
      " FROM refresh_commitments"
      " JOIN known_coins kc"
      "   ON (refresh_commitments.old_coin_pub = kc.coin_pub)"
      " JOIN denominations denoms"
      "   USING (denominations_serial)"
      " WHERE old_coin_pub=$1;",
      1),
    /* Store information about the desired denominations for a
       refresh operation, used in #postgres_insert_refresh_reveal() */
    GNUNET_PQ_make_prepare (
      "insert_refresh_revealed_coin",
      "INSERT INTO refresh_revealed_coins "
      "(melt_serial_id "
      ",freshcoin_index "
      ",link_sig "
      ",denominations_serial "
      ",coin_ev"
      ",ewv"
      ",h_coin_ev"
      ",ev_sig"
      ") SELECT $1, $2, $3, "
      "         denominations_serial, $5, $6, $7, $8"
      "    FROM denominations"
      "   WHERE denom_pub_hash=$4;",
      8),
    /* Obtain information about the coins created in a refresh
       operation, used in #postgres_get_refresh_reveal() */
    GNUNET_PQ_make_prepare (
      "get_refresh_revealed_coins",
      "SELECT "
      " rrc.freshcoin_index"
      ",denom.denom_pub_hash"
      ",rrc.h_coin_ev"
      ",rrc.link_sig"
      ",rrc.coin_ev"
      ",rrc.ewv"
      ",rrc.ev_sig"
      " FROM refresh_commitments"
      "    JOIN refresh_revealed_coins rrc"
      "      USING (melt_serial_id)"
      "    JOIN denominations denom "
      "      USING (denominations_serial)"
      " WHERE rc=$1;",
      1),

    /* Used in #postgres_insert_refresh_reveal() to store the transfer
       keys we learned */
    GNUNET_PQ_make_prepare (
      "insert_refresh_transfer_keys",
      "INSERT INTO refresh_transfer_keys "
      "(melt_serial_id"
      ",transfer_pub"
      ",transfer_privs"
      ") VALUES ($1, $2, $3);",
      3),
    /* Used in #postgres_insert_refund() to store refund information */
    GNUNET_PQ_make_prepare (
      "insert_refund",
      "INSERT INTO refunds "
      "(deposit_serial_id "
      ",merchant_sig "
      ",rtransaction_id "
      ",amount_with_fee_val "
      ",amount_with_fee_frac "
      ") SELECT dbc.deposit_serial_id, $3, $5, $6, $7"
      "    FROM deposits_by_coin dbc"
      "    JOIN deposits dep USING (shard,deposit_serial_id)"
      "   WHERE dbc.coin_pub=$1"
      "     AND dep.h_contract_terms=$4"
      "     AND dep.merchant_pub=$2",
      7),
    /* Query the 'refunds' by coin public key */
    GNUNET_PQ_make_prepare (
      "get_refunds_by_coin",
      "SELECT"
      " dep.merchant_pub"
      ",ref.merchant_sig"
      ",dep.h_contract_terms"
      ",ref.rtransaction_id"
      ",ref.amount_with_fee_val"
      ",ref.amount_with_fee_frac"
      ",denom.fee_refund_val "
      ",denom.fee_refund_frac "
      ",ref.refund_serial_id"
      " FROM deposits_by_coin dbc"
      " JOIN refunds ref USING (deposit_serial_id)"
      " JOIN deposits dep ON (dbc.shard = dep.shard AND dbc.deposit_serial_id = dep.deposit_serial_id)"
      " JOIN known_coins kc ON (dbc.coin_pub = kc.coin_pub)"
      " JOIN denominations denom USING (denominations_serial)"
      " WHERE dbc.coin_pub=$1;",
      1),
    /* Query the 'refunds' by coin public key, merchant_pub and contract hash */
    GNUNET_PQ_make_prepare (
      "get_refunds_by_coin_and_contract",
      "SELECT"
      " ref.amount_with_fee_val"
      ",ref.amount_with_fee_frac"
      " FROM deposits_by_coin dbc"
      " JOIN refunds ref USING (shard,deposit_serial_id)"
      " JOIN deposits dep ON (dbc.shard = dep.shard AND dbc.deposit_serial_id = dep.deposit_serial_id)"
      " WHERE dbc.coin_pub=$1"
      "   AND dep.merchant_pub=$2"
      "   AND dep.h_contract_terms=$3;",
      3),
    /* Fetch refunds with rowid '\geq' the given parameter */
    GNUNET_PQ_make_prepare (
      "audit_get_refunds_incr",
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
      "   JOIN deposits USING (shard, deposit_serial_id)"
      "   JOIN known_coins kc USING (coin_pub)"
      "   JOIN denominations denom ON (kc.denominations_serial = denom.denominations_serial)"
      " WHERE refund_serial_id>=$1"
      " ORDER BY refund_serial_id ASC;",
      1),
    /* Lock deposit table; NOTE: we may want to eventually shard the
       deposit table to avoid this lock being the main point of
       contention limiting transaction performance. */
    GNUNET_PQ_make_prepare (
      "lock_deposit",
      "LOCK TABLE deposits;",
      0),
    /* Store information about a /deposit the exchange is to execute.
       Used in #postgres_insert_deposit(). */
    GNUNET_PQ_make_prepare (
      "insert_deposit",
      "INSERT INTO deposits "
      "(known_coin_id"
      ",coin_pub"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",wallet_timestamp"
      ",refund_deadline"
      ",wire_deadline"
      ",merchant_pub"
      ",h_contract_terms"
      ",wire_salt"
      ",wire_target_h_payto"
      ",coin_sig"
      ",exchange_timestamp"
      ",shard"
      ") SELECT known_coin_id, $1, $2, $3, $4, $5, $6, "
      " $7, $8, $9, $10, $11, $12, $13"
      "    FROM known_coins"
      "   WHERE coin_pub=$1" // FIXME: maybe we know known_coin_id already in caller?
      " ON CONFLICT DO NOTHING;",
      13),
    /* Fetch an existing deposit request, used to ensure idempotency
       during /deposit processing. Used in #postgres_have_deposit(). */
    GNUNET_PQ_make_prepare (
      "get_deposit",
      "SELECT"
      " dep.amount_with_fee_val"
      ",dep.amount_with_fee_frac"
      ",denominations.fee_deposit_val"
      ",denominations.fee_deposit_frac"
      ",dep.wallet_timestamp"
      ",dep.exchange_timestamp"
      ",dep.refund_deadline"
      ",dep.wire_deadline"
      ",dep.h_contract_terms"
      ",dep.wire_salt"
      ",wt.payto_uri AS receiver_wire_account"
      " FROM deposits_by_coin dbc"
      " JOIN deposits dep USING (shard,deposit_serial_id)"
      " JOIN known_coins kc ON (kc.coin_pub = dbc.coin_pub)"
      " JOIN denominations USING (denominations_serial)"
      " JOIN wire_targets wt USING (wire_target_h_payto)"
      " WHERE dbc.coin_pub=$1"
      "   AND dep.merchant_pub=$3"
      "   AND dep.h_contract_terms=$2;",
      3),
    /* Fetch deposits with rowid '\geq' the given parameter */
    GNUNET_PQ_make_prepare (
      "audit_get_deposits_incr",
      "SELECT"
      " amount_with_fee_val"
      ",amount_with_fee_frac"
      ",wallet_timestamp"
      ",exchange_timestamp"
      ",merchant_pub"
      ",denom.denom_pub"
      ",kc.coin_pub"
      ",kc.age_commitment_hash"
      ",coin_sig"
      ",refund_deadline"
      ",wire_deadline"
      ",h_contract_terms"
      ",wire_salt"
      ",payto_uri AS receiver_wire_account"
      ",done"
      ",deposit_serial_id"
      " FROM deposits"
      "    JOIN wire_targets USING (wire_target_h_payto)"
      "    JOIN known_coins kc USING (coin_pub)"
      "    JOIN denominations denom USING (denominations_serial)"
      " WHERE ("
      "  (deposit_serial_id>=$1)" // FIXME: also select by shard!?
      " )"
      " ORDER BY deposit_serial_id ASC;",
      1),
    /* Fetch an existing deposit request.
       Used in #postgres_lookup_transfer_by_deposit(). */
    GNUNET_PQ_make_prepare (
      "get_deposit_without_wtid",
      "SELECT"
      " wt.kyc_ok"
      ",wt.wire_target_serial_id AS payment_target_uuid"
      ",dep.wire_salt"
      ",wt.payto_uri"
      ",dep.amount_with_fee_val"
      ",dep.amount_with_fee_frac"
      ",denom.fee_deposit_val"
      ",denom.fee_deposit_frac"
      ",dep.wire_deadline"
      " FROM deposits_by_coin dbc"
      "    JOIN deposits dep USING (shard,deposit_serial_id)"
      "    JOIN wire_targets wt USING (wire_target_h_payto)"
      "    JOIN known_coins kc ON (kc.coin_pub = dbc.coin_pub)"
      "    JOIN denominations denom USING (denominations_serial)"
      " WHERE dbc.coin_pub=$1"
      "   AND dep.merchant_pub=$3"
      "   AND dep.h_contract_terms=$2;",
      3),
    /* Used in #postgres_get_ready_deposit() */
    GNUNET_PQ_make_prepare (
      "deposits_get_ready",
      "SELECT"
      " deposit_serial_id"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",denom.fee_deposit_val"
      ",denom.fee_deposit_frac"
      ",h_contract_terms"
      ",payto_uri"
      ",wire_target_serial_id"
      ",merchant_pub"
      ",kc.coin_pub"
      " FROM deposits"
      "  JOIN wire_targets "
      "    USING (wire_target_h_payto)"
      "  JOIN known_coins kc"
      "    USING (coin_pub)"
      "  JOIN denominations denom"
      "    USING (denominations_serial)"
      " WHERE "
      "       shard >= $2"
      "   AND shard <= $3"
      "   AND done=FALSE"
      "   AND extension_blocked=FALSE"
      "   AND tiny=FALSE"
      "   AND wire_deadline<=$1"
      "   AND (kyc_ok OR $4)"
      " ORDER BY "
      "   shard ASC"
      "  ,wire_deadline ASC"
      " LIMIT 1;",
      4),
    /* Used in #postgres_iterate_matching_deposits() */
    GNUNET_PQ_make_prepare (
      "deposits_iterate_matching",
      "SELECT"
      " deposit_serial_id"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",denom.fee_deposit_val"
      ",denom.fee_deposit_frac"
      ",h_contract_terms"
      ",kc.coin_pub"
      " FROM deposits"
      "    JOIN known_coins kc USING (coin_pub)"
      "    JOIN denominations denom USING (denominations_serial)"
      " WHERE shard=$4"
      "  AND merchant_pub=$1"
      "  AND wire_target_h_payto=$2"
      "  AND done=FALSE"
      "  AND extension_blocked=FALSE"
      "  AND refund_deadline<$3"
      " ORDER BY refund_deadline ASC"
      " LIMIT "
      TALER_QUOTE (
        TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT) ";",
      4),
    /* Used in #postgres_mark_deposit_tiny() */
    GNUNET_PQ_make_prepare (
      "mark_deposit_tiny",
      "UPDATE deposits"
      " SET tiny=TRUE"
      " WHERE shard=$2"
      "   AND deposit_serial_id=$1",
      2),
    /* Used in #postgres_mark_deposit_done() */
    GNUNET_PQ_make_prepare (
      "mark_deposit_done",
      "UPDATE deposits"
      " SET done=TRUE"
      " WHERE shard=$2"
      "   AND deposit_serial_id=$1;",
      2),
    /* Used in #postgres_get_coin_transactions() to obtain information
       about how a coin has been spend with /deposit requests. */
    GNUNET_PQ_make_prepare (
      "get_deposit_with_coin_pub",
      "SELECT"
      " dep.amount_with_fee_val"
      ",dep.amount_with_fee_frac"
      ",denoms.fee_deposit_val"
      ",denoms.fee_deposit_frac"
      ",denoms.denom_pub_hash"
      ",kc.age_commitment_hash"
      ",dep.wallet_timestamp"
      ",dep.refund_deadline"
      ",dep.wire_deadline"
      ",dep.merchant_pub"
      ",dep.h_contract_terms"
      ",dep.wire_salt"
      ",wt.payto_uri"
      ",dep.coin_sig"
      ",dep.deposit_serial_id"
      ",dep.done"
      " FROM deposits_by_coin dbc"
      "    JOIN deposits dep"
      "      USING (shard,deposit_serial_id)"
      "    JOIN wire_targets wt"
      "      USING (wire_target_h_payto)"
      "    JOIN known_coins kc"
      "      ON (kc.coin_pub = dbc.coin_pub)"
      "    JOIN denominations denoms"
      "      USING (denominations_serial)"
      " WHERE dbc.coin_pub=$1;",
      1),

    /* Used in #postgres_get_link_data(). */
    GNUNET_PQ_make_prepare (
      "get_link",
      "SELECT "
      " tp.transfer_pub"
      ",denoms.denom_pub"
      ",rrc.ev_sig"
      ",rrc.ewv"
      ",rrc.link_sig"
      ",rrc.freshcoin_index"
      ",rrc.coin_ev"
      " FROM refresh_commitments"
      "     JOIN refresh_revealed_coins rrc"
      "       USING (melt_serial_id)"
      "     JOIN refresh_transfer_keys tp"
      "       USING (melt_serial_id)"
      "     JOIN denominations denoms"
      "       ON (rrc.denominations_serial = denoms.denominations_serial)"
      " WHERE old_coin_pub=$1"
      " ORDER BY tp.transfer_pub, rrc.freshcoin_index ASC",
      1),
    /* Used in #postgres_lookup_wire_transfer */
    GNUNET_PQ_make_prepare (
      "lookup_transactions",
      "SELECT"
      " aggregation_serial_id"
      ",deposits.h_contract_terms"
      ",payto_uri"
      ",wire_targets.wire_target_h_payto"
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
      "    JOIN wire_targets"
      "      USING (wire_target_h_payto)"
      "    JOIN known_coins kc"
      "      USING (coin_pub)"
      "    JOIN denominations denom"
      "      USING (denominations_serial)"
      "    JOIN wire_out"
      "      USING (wtid_raw)"
      " WHERE wtid_raw=$1;",
      1),
    /* Used in #postgres_lookup_transfer_by_deposit */
    GNUNET_PQ_make_prepare (
      "lookup_deposit_wtid",
      "SELECT"
      " aggregation_tracking.wtid_raw"
      ",wire_out.execution_date"
      ",dep.amount_with_fee_val"
      ",dep.amount_with_fee_frac"
      ",dep.wire_salt"
      ",wt.payto_uri"
      ",denom.fee_deposit_val"
      ",denom.fee_deposit_frac"
      " FROM deposits_by_coin dbc"
      "    JOIN deposits dep"
      "      USING (shard,deposit_serial_id)"
      "    JOIN wire_targets wt"
      "      USING (wire_target_h_payto)"
      "    JOIN aggregation_tracking"
      "      USING (deposit_serial_id)"
      "    JOIN known_coins kc"
      "      ON (kc.coin_pub = dbc.coin_pub)"
      "    JOIN denominations denom"
      "      USING (denominations_serial)"
      "    JOIN wire_out"
      "      USING (wtid_raw)"
      " WHERE dbc.coin_pub=$1"
      "   AND dep.merchant_pub=$3"
      "   AND dep.h_contract_terms=$2",
      3),
    /* Used in #postgres_insert_aggregation_tracking */
    GNUNET_PQ_make_prepare (
      "insert_aggregation_tracking",
      "INSERT INTO aggregation_tracking "
      "(deposit_serial_id"
      ",wtid_raw"
      ") VALUES "
      "($1, $2);",
      2),
    /* Used in #postgres_get_wire_fee() */
    GNUNET_PQ_make_prepare (
      "get_wire_fee",
      "SELECT "
      " start_date"
      ",end_date"
      ",wire_fee_val"
      ",wire_fee_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",wad_fee_val"
      ",wad_fee_frac"
      ",master_sig"
      " FROM wire_fee"
      " WHERE wire_method=$1"
      "   AND start_date <= $2"
      "   AND end_date > $2;",
      2),
    /* Used in #postgres_get_global_fee() */
    GNUNET_PQ_make_prepare (
      "get_global_fee",
      "SELECT "
      " start_date"
      ",end_date"
      ",history_fee_val"
      ",history_fee_frac"
      ",kyc_fee_val"
      ",kyc_fee_frac"
      ",account_fee_val"
      ",account_fee_frac"
      ",purse_fee_val"
      ",purse_fee_frac"
      ",purse_timeout"
      ",kyc_timeout"
      ",history_expiration"
      ",purse_account_limit"
      ",master_sig"
      " FROM global_fee"
      " WHERE start_date <= $1"
      "   AND end_date > $1;",
      1),
    /* Used in #postgres_get_global_fees() */
    GNUNET_PQ_make_prepare (
      "get_global_fees",
      "SELECT "
      " start_date"
      ",end_date"
      ",history_fee_val"
      ",history_fee_frac"
      ",kyc_fee_val"
      ",kyc_fee_frac"
      ",account_fee_val"
      ",account_fee_frac"
      ",purse_fee_val"
      ",purse_fee_frac"
      ",purse_timeout"
      ",kyc_timeout"
      ",history_expiration"
      ",purse_account_limit"
      ",master_sig"
      " FROM global_fee"
      " WHERE start_date >= $1",
      1),
    /* Used in #postgres_insert_wire_fee */
    GNUNET_PQ_make_prepare (
      "insert_wire_fee",
      "INSERT INTO wire_fee "
      "(wire_method"
      ",start_date"
      ",end_date"
      ",wire_fee_val"
      ",wire_fee_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",wad_fee_val"
      ",wad_fee_frac"
      ",master_sig"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);",
      10),
    /* Used in #postgres_insert_global_fee */
    GNUNET_PQ_make_prepare (
      "insert_global_fee",
      "INSERT INTO global_fee "
      "(start_date"
      ",end_date"
      ",history_fee_val"
      ",history_fee_frac"
      ",kyc_fee_val"
      ",kyc_fee_frac"
      ",account_fee_val"
      ",account_fee_frac"
      ",purse_fee_val"
      ",purse_fee_frac"
      ",purse_timeout"
      ",kyc_timeout"
      ",history_expiration"
      ",purse_account_limit"
      ",master_sig"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15);",
      15),
    /* Used in #postgres_store_wire_transfer_out */
    GNUNET_PQ_make_prepare (
      "insert_wire_out",
      "INSERT INTO wire_out "
      "(execution_date"
      ",wtid_raw"
      ",wire_target_h_payto"
      ",exchange_account_section"
      ",amount_val"
      ",amount_frac"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6);",
      6),
    GNUNET_PQ_make_prepare (
      "insert_into_table_wire_out",
      "INSERT INTO wire_out"
      "(wireout_uuid"
      ",execution_date"
      ",wtid_raw"
      ",wire_target_h_payto"
      ",exchange_account_section"
      ",amount_val"
      ",amount_frac"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7);",
      7),
    /* Used in #postgres_wire_prepare_data_insert() to store
       wire transfer information before actually committing it with the bank */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_insert",
      "INSERT INTO prewire "
      "(wire_method"
      ",buf"
      ") VALUES "
      "($1, $2);",
      2),
    /* Used in #postgres_wire_prepare_data_mark_finished() */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_mark_done",
      "UPDATE prewire"
      " SET finished=TRUE"
      " WHERE prewire_uuid=$1;",
      1),
    /* Used in #postgres_wire_prepare_data_mark_failed() */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_mark_failed",
      "UPDATE prewire"
      " SET failed=TRUE"
      " WHERE prewire_uuid=$1;",
      1),
    /* Used in #postgres_wire_prepare_data_get() */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_get",
      "SELECT"
      " prewire_uuid"
      ",wire_method"
      ",buf"
      " FROM prewire"
      " WHERE prewire_uuid >= $1"
      "   AND finished=FALSE"
      "   AND failed=FALSE"
      " ORDER BY prewire_uuid ASC"
      " LIMIT $2;",
      2),
    /* Used in #postgres_select_deposits_missing_wire */
    // FIXME: used by the auditor; can probably be done
    // smarter by checking if 'done' or 'tiny' or 'blocked'
    // are set correctly when going over deposits, instead
    // of JOINing with refunds.
    GNUNET_PQ_make_prepare (
      "deposits_get_overdue",
      "SELECT"
      " deposit_serial_id"
      ",coin_pub"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",payto_uri"
      ",wire_deadline"
      ",tiny"
      ",done"
      " FROM deposits d"
      "   JOIN known_coins"
      "     USING (coin_pub)"
      "   JOIN wire_targets"
      "     USING (wire_target_h_payto)"
      " WHERE wire_deadline >= $1"
      " AND wire_deadline < $2"
      " AND NOT (EXISTS (SELECT 1"
      "            FROM refunds"
      "            JOIN deposits dx USING (deposit_serial_id)"
      "            WHERE (dx.coin_pub = d.coin_pub))"
      "       OR EXISTS (SELECT 1"
      "            FROM aggregation_tracking"
      "            WHERE (aggregation_tracking.deposit_serial_id = d.deposit_serial_id)))"
      " ORDER BY wire_deadline ASC",
      2),
    /* Used in #postgres_select_wire_out_above_serial_id() */
    GNUNET_PQ_make_prepare (
      "audit_get_wire_incr",
      "SELECT"
      " wireout_uuid"
      ",execution_date"
      ",wtid_raw"
      ",payto_uri"
      ",amount_val"
      ",amount_frac"
      " FROM wire_out"
      "   JOIN wire_targets"
      "     USING (wire_target_h_payto)"
      " WHERE wireout_uuid>=$1"
      " ORDER BY wireout_uuid ASC;",
      1),
    /* Used in #postgres_select_wire_out_above_serial_id_by_account() */
    GNUNET_PQ_make_prepare (
      "audit_get_wire_incr_by_account",
      "SELECT"
      " wireout_uuid"
      ",execution_date"
      ",wtid_raw"
      ",payto_uri"
      ",amount_val"
      ",amount_frac"
      " FROM wire_out"
      "   JOIN wire_targets"
      "     USING (wire_target_h_payto)"
      " WHERE "
      "      wireout_uuid>=$1 "
      "  AND exchange_account_section=$2"
      " ORDER BY wireout_uuid ASC;",
      2),
    /* Used in #postgres_select_recoup_above_serial_id() to obtain recoup transactions */
    GNUNET_PQ_make_prepare (
      "recoup_get_incr",
      "SELECT"
      " recoup_uuid"
      ",recoup_timestamp"
      ",reserves.reserve_pub"
      ",coins.coin_pub"
      ",coin_sig"
      ",coin_blind"
      ",ro.h_blind_ev"
      ",denoms.denom_pub_hash"
      ",coins.denom_sig"
      ",coins.age_commitment_hash"
      ",denoms.denom_pub"
      ",amount_val"
      ",amount_frac"
      " FROM recoup"
      "    JOIN known_coins coins"
      "      USING (coin_pub)"
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
    GNUNET_PQ_make_prepare (
      "recoup_refresh_get_incr",
      "SELECT"
      " recoup_refresh_uuid"
      ",recoup_timestamp"
      ",old_coins.coin_pub AS old_coin_pub"
      ",new_coins.age_commitment_hash"
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
      "      ON (rfc.old_coin_pub = old_coins.coin_pub)"
      "    INNER JOIN known_coins new_coins"
      "      ON (new_coins.coin_pub = recoup_refresh.coin_pub)"
      "    INNER JOIN denominations new_denoms"
      "      ON (new_coins.denominations_serial = new_denoms.denominations_serial)"
      "    INNER JOIN denominations old_denoms"
      "      ON (old_coins.denominations_serial = old_denoms.denominations_serial)"
      " WHERE recoup_refresh_uuid>=$1"
      " ORDER BY recoup_refresh_uuid ASC;",
      1),
    /* Used in #postgres_select_reserve_closed_above_serial_id() to
       obtain information about closed reserves */
    GNUNET_PQ_make_prepare (
      "reserves_close_get_incr",
      "SELECT"
      " close_uuid"
      ",reserves.reserve_pub"
      ",execution_date"
      ",wtid"
      ",payto_uri AS receiver_account"
      ",amount_val"
      ",amount_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      " FROM reserves_close"
      "   JOIN wire_targets"
      "     USING (wire_target_h_payto)"
      "   JOIN reserves"
      "     USING (reserve_pub)"
      " WHERE close_uuid>=$1"
      " ORDER BY close_uuid ASC;",
      1),
    /* Used in #postgres_get_reserve_history() to obtain recoup transactions
       for a reserve - query optimization should be disabled i.e.
       BEGIN; SET LOCAL join_collapse_limit=1; query; COMMIT; */
    GNUNET_PQ_make_prepare (
      "recoup_by_reserve",
      "SELECT"
      " recoup.coin_pub"
      ",recoup.coin_sig"
      ",recoup.coin_blind"
      ",recoup.amount_val"
      ",recoup.amount_frac"
      ",recoup.recoup_timestamp"
      ",denominations.denom_pub_hash"
      ",known_coins.denom_sig"
      " FROM denominations"
      " JOIN (known_coins"
      "   JOIN recoup "
      "   ON (recoup.coin_pub = known_coins.coin_pub))"
      "  ON (known_coins.denominations_serial = denominations.denominations_serial)"
      " WHERE recoup.coin_pub"
      " IN (SELECT coin_pub"
      "     FROM recoup_by_reserve"
      "     JOIN (reserves_out"
      "       JOIN (reserves_out_by_reserve"
      "         JOIN reserves"
      "           ON (reserves.reserve_uuid = reserves_out_by_reserve.reserve_uuid))"
      "       ON (reserves_out_by_reserve.h_blind_ev = reserves_out.h_blind_ev))"
      "     ON (recoup_by_reserve.reserve_out_serial_id = reserves_out.reserve_out_serial_id)"
      "     WHERE reserves.reserve_pub=$1);",
      1),
    /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
       affecting old coins of refreshed coins */
    GNUNET_PQ_make_prepare (
      "recoup_by_old_coin",
      "SELECT"
      " coins.coin_pub"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",denoms.denom_pub_hash"
      ",coins.denom_sig"
      ",recoup_refresh_uuid"
      " FROM recoup_refresh"
      " JOIN known_coins coins"
      "   USING (coin_pub)"
      " JOIN denominations denoms"
      "   USING (denominations_serial)"
      " WHERE rrc_serial IN"
      "   (SELECT rrc.rrc_serial"
      "    FROM refresh_commitments"
      "       JOIN refresh_revealed_coins rrc"
      "           USING (melt_serial_id)"
      "    WHERE old_coin_pub=$1);",
      1),
    /* Used in #postgres_get_reserve_history() */
    GNUNET_PQ_make_prepare (
      "close_by_reserve",
      "SELECT"
      " amount_val"
      ",amount_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",execution_date"
      ",payto_uri AS receiver_account"
      ",wtid"
      " FROM reserves_close"
      "   JOIN wire_targets"
      "     USING (wire_target_h_payto)"
      " WHERE reserve_pub=$1;",
      1),
    /* Used in #postgres_get_expired_reserves() */
    GNUNET_PQ_make_prepare (
      "get_expired_reserves",
      "SELECT"
      " expiration_date"
      ",payto_uri AS account_details"
      ",reserve_pub"
      ",current_balance_val"
      ",current_balance_frac"
      " FROM reserves"
      "   JOIN reserves_in ri"
      "     USING (reserve_pub)"
      "   JOIN wire_targets wt"
      "     ON (ri.wire_source_h_payto = wt.wire_target_h_payto)"
      " WHERE expiration_date<=$1"
      "   AND (current_balance_val != 0 "
      "        OR current_balance_frac != 0)"
      " ORDER BY expiration_date ASC"
      " LIMIT 1;",
      1),
    /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
       for a coin */
    GNUNET_PQ_make_prepare (
      "recoup_by_coin",
      "SELECT"
      " reserves.reserve_pub"
      ",denoms.denom_pub_hash"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",recoup_uuid"
      " FROM recoup"
      // FIXME: suboptimal sub-query here: crosses shards!
      // MAYBE: replace reserve_out_serial_id with
      // reserve_pub and use new reserve_out_by_reserve table?
      " JOIN reserves_out ro"
      "   USING (reserve_out_serial_id)"
      " JOIN reserves"
      "   USING (reserve_uuid)"
      " JOIN known_coins coins"
      "   USING (coin_pub)"
      " JOIN denominations denoms"
      "   ON (denoms.denominations_serial = coins.denominations_serial)"
      " WHERE coins.coin_pub=$1;",
      1),
    /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
       for a refreshed coin */
    GNUNET_PQ_make_prepare (
      "recoup_by_refreshed_coin",
      "SELECT"
      " old_coins.coin_pub AS old_coin_pub"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",denoms.denom_pub_hash"
      ",coins.denom_sig"
      ",recoup_refresh_uuid"
      " FROM recoup_refresh"
      "    JOIN refresh_revealed_coins rrc"
      "      USING (rrc_serial)"
      "    JOIN refresh_commitments rfc"
      "      ON (rrc.melt_serial_id = rfc.melt_serial_id)"
      "    JOIN known_coins old_coins"
      "      ON (rfc.old_coin_pub = old_coins.coin_pub)"
      "    JOIN known_coins coins"
      "      ON (recoup_refresh.coin_pub = coins.coin_pub)"
      "    JOIN denominations denoms"
      "      ON (denoms.denominations_serial = coins.denominations_serial)"
      " WHERE coins.coin_pub=$1;",
      1),
    /* Used in #postgres_get_reserve_by_h_blind() */
    GNUNET_PQ_make_prepare (
      "reserve_by_h_blind",
      "SELECT"
      " reserves.reserve_pub"
      ",reserve_out_serial_id"
      " FROM reserves_out"
      " JOIN reserves"
      "   USING (reserve_uuid)"
      " WHERE h_blind_ev=$1"
      " LIMIT 1;",
      1),
    /* Used in #postgres_get_old_coin_by_h_blind() */
    GNUNET_PQ_make_prepare (
      "old_coin_by_h_blind",
      "SELECT"
      " okc.coin_pub AS old_coin_pub"
      ",rrc_serial"
      " FROM refresh_revealed_coins rrc"
      " JOIN refresh_commitments rcom USING (melt_serial_id)"
      " JOIN known_coins okc ON (rcom.old_coin_pub = okc.coin_pub)"
      " WHERE h_coin_ev=$1"
      " LIMIT 1;",
      1),
    /* Used in #postgres_lookup_auditor_timestamp() */
    GNUNET_PQ_make_prepare (
      "lookup_auditor_timestamp",
      "SELECT"
      " last_change"
      " FROM auditors"
      " WHERE auditor_pub=$1;",
      1),
    /* Used in #postgres_lookup_auditor_status() */
    GNUNET_PQ_make_prepare (
      "lookup_auditor_status",
      "SELECT"
      " auditor_url"
      ",is_active"
      " FROM auditors"
      " WHERE auditor_pub=$1;",
      1),
    /* Used in #postgres_lookup_wire_timestamp() */
    GNUNET_PQ_make_prepare (
      "lookup_wire_timestamp",
      "SELECT"
      " last_change"
      " FROM wire_accounts"
      " WHERE payto_uri=$1;",
      1),
    /* used in #postgres_insert_auditor() */
    GNUNET_PQ_make_prepare (
      "insert_auditor",
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
    GNUNET_PQ_make_prepare (
      "update_auditor",
      "UPDATE auditors"
      " SET"
      "  auditor_url=$2"
      " ,auditor_name=$3"
      " ,is_active=$4"
      " ,last_change=$5"
      " WHERE auditor_pub=$1",
      5),
    /* used in #postgres_insert_wire() */
    GNUNET_PQ_make_prepare (
      "insert_wire",
      "INSERT INTO wire_accounts "
      "(payto_uri"
      ",master_sig"
      ",is_active"
      ",last_change"
      ") VALUES "
      "($1, $2, true, $3);",
      3),
    /* used in #postgres_update_wire() */
    GNUNET_PQ_make_prepare (
      "update_wire",
      "UPDATE wire_accounts"
      " SET"
      "  is_active=$2"
      " ,last_change=$3"
      " WHERE payto_uri=$1",
      3),
    /* used in #postgres_update_wire() */
    GNUNET_PQ_make_prepare (
      "get_wire_accounts",
      "SELECT"
      " payto_uri"
      ",master_sig"
      " FROM wire_accounts"
      " WHERE is_active",
      0),
    /* used in #postgres_update_wire() */
    GNUNET_PQ_make_prepare (
      "get_wire_fees",
      "SELECT"
      " wire_fee_val"
      ",wire_fee_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",wad_fee_val"
      ",wad_fee_frac"
      ",start_date"
      ",end_date"
      ",master_sig"
      " FROM wire_fee"
      " WHERE wire_method=$1",
      1),
    /* used in #postgres_insert_signkey_revocation() */
    GNUNET_PQ_make_prepare (
      "insert_signkey_revocation",
      "INSERT INTO signkey_revocations "
      "(esk_serial"
      ",master_sig"
      ") SELECT esk_serial, $2 "
      "    FROM exchange_sign_keys"
      "   WHERE exchange_pub=$1;",
      2),
    /* used in #postgres_insert_signkey_revocation() */
    GNUNET_PQ_make_prepare (
      "lookup_signkey_revocation",
      "SELECT "
      " master_sig"
      " FROM signkey_revocations"
      " WHERE esk_serial="
      "   (SELECT esk_serial"
      "      FROM exchange_sign_keys"
      "     WHERE exchange_pub=$1);",
      1),
    /* used in #postgres_insert_signkey() */
    GNUNET_PQ_make_prepare (
      "insert_signkey",
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
    GNUNET_PQ_make_prepare (
      "lookup_signing_key",
      "SELECT"
      " valid_from"
      ",expire_sign"
      ",expire_legal"
      " FROM exchange_sign_keys"
      " WHERE exchange_pub=$1",
      1),
    /* used in #postgres_lookup_denomination_key() */
    GNUNET_PQ_make_prepare (
      "lookup_denomination_key",
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
      ",age_mask"
      " FROM denominations"
      " WHERE denom_pub_hash=$1;",
      1),
    /* used in #postgres_insert_auditor_denom_sig() */
    GNUNET_PQ_make_prepare (
      "insert_auditor_denom_sig",
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
    GNUNET_PQ_make_prepare (
      "select_auditor_denom_sig",
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
    GNUNET_PQ_make_prepare (
      "lookup_wire_fee_by_time",
      "SELECT"
      " wire_fee_val"
      ",wire_fee_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",wad_fee_val"
      ",wad_fee_frac"
      " FROM wire_fee"
      " WHERE wire_method=$1"
      " AND end_date > $2"
      " AND start_date < $3;",
      1),
    /* used in #postgres_lookup_wire_fee_by_time() */
    GNUNET_PQ_make_prepare (
      "lookup_global_fee_by_time",
      "SELECT"
      " history_fee_val"
      ",history_fee_frac"
      ",kyc_fee_val"
      ",kyc_fee_frac"
      ",account_fee_val"
      ",account_fee_frac"
      ",purse_fee_val"
      ",purse_fee_frac"
      ",purse_timeout"
      ",kyc_timeout"
      ",history_expiration"
      ",purse_account_limit"
      " FROM global_fee"
      " WHERE end_date > $1"
      "   AND start_date < $2;",
      1),
    /* used in #postgres_commit */
    GNUNET_PQ_make_prepare (
      "do_commit",
      "COMMIT",
      0),
    /* used in #postgres_lookup_serial_by_table() */
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_denominations",
      "SELECT"
      " denominations_serial AS serial"
      " FROM denominations"
      " ORDER BY denominations_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_denomination_revocations",
      "SELECT"
      " denom_revocations_serial_id AS serial"
      " FROM denomination_revocations"
      " ORDER BY denom_revocations_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_wire_targets",
      "SELECT"
      " wire_target_serial_id AS serial"
      " FROM wire_targets"
      " ORDER BY wire_target_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_reserves",
      "SELECT"
      " reserve_uuid AS serial"
      " FROM reserves"
      " ORDER BY reserve_uuid DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_reserves_in",
      "SELECT"
      " reserve_in_serial_id AS serial"
      " FROM reserves_in"
      " ORDER BY reserve_in_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_reserves_close",
      "SELECT"
      " close_uuid AS serial"
      " FROM reserves_close"
      " ORDER BY close_uuid DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_reserves_out",
      "SELECT"
      " reserve_out_serial_id AS serial"
      " FROM reserves_out"
      " ORDER BY reserve_out_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_auditors",
      "SELECT"
      " auditor_uuid AS serial"
      " FROM auditors"
      " ORDER BY auditor_uuid DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_auditor_denom_sigs",
      "SELECT"
      " auditor_denom_serial AS serial"
      " FROM auditor_denom_sigs"
      " ORDER BY auditor_denom_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_exchange_sign_keys",
      "SELECT"
      " esk_serial AS serial"
      " FROM exchange_sign_keys"
      " ORDER BY esk_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_signkey_revocations",
      "SELECT"
      " signkey_revocations_serial_id AS serial"
      " FROM signkey_revocations"
      " ORDER BY signkey_revocations_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_known_coins",
      "SELECT"
      " known_coin_id AS serial"
      " FROM known_coins"
      " ORDER BY known_coin_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_refresh_commitments",
      "SELECT"
      " melt_serial_id AS serial"
      " FROM refresh_commitments"
      " ORDER BY melt_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_refresh_revealed_coins",
      "SELECT"
      " rrc_serial AS serial"
      " FROM refresh_revealed_coins"
      " ORDER BY rrc_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_refresh_transfer_keys",
      "SELECT"
      " rtc_serial AS serial"
      " FROM refresh_transfer_keys"
      " ORDER BY rtc_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_deposits",
      "SELECT"
      " deposit_serial_id AS serial"
      " FROM deposits"
      " ORDER BY deposit_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_refunds",
      "SELECT"
      " refund_serial_id AS serial"
      " FROM refunds"
      " ORDER BY refund_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_wire_out",
      "SELECT"
      " wireout_uuid AS serial"
      " FROM wire_out"
      " ORDER BY wireout_uuid DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_aggregation_tracking",
      "SELECT"
      " aggregation_serial_id AS serial"
      " FROM aggregation_tracking"
      " ORDER BY aggregation_serial_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_wire_fee",
      "SELECT"
      " wire_fee_serial AS serial"
      " FROM wire_fee"
      " ORDER BY wire_fee_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_global_fee",
      "SELECT"
      " global_fee_serial AS serial"
      " FROM global_fee"
      " ORDER BY global_fee_serial DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_recoup",
      "SELECT"
      " recoup_uuid AS serial"
      " FROM recoup"
      " ORDER BY recoup_uuid DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_recoup_refresh",
      "SELECT"
      " recoup_refresh_uuid AS serial"
      " FROM recoup_refresh"
      " ORDER BY recoup_refresh_uuid DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_extensions",
      "SELECT"
      " extension_id AS serial"
      " FROM extensions"
      " ORDER BY extension_id DESC"
      " LIMIT 1;",
      0),
    GNUNET_PQ_make_prepare (
      "select_serial_by_table_extension_details",
      "SELECT"
      " extension_details_serial_id AS serial"
      " FROM extension_details"
      " ORDER BY extension_details_serial_id DESC"
      " LIMIT 1;",
      0),
    /* For postgres_lookup_records_by_table */
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_denominations",
      "SELECT"
      " denominations_serial AS serial"
      ",denom_type"
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
      ",age_mask"
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
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_wire_targets",
      "SELECT"
      " wire_target_serial_id AS serial"
      ",payto_uri"
      ",kyc_ok"
      ",external_id"
      " FROM wire_targets"
      " WHERE wire_target_serial_id > $1"
      " ORDER BY wire_target_serial_id ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_reserves",
      "SELECT"
      " reserve_uuid AS serial"
      ",reserve_pub"
      ",current_balance_val"
      ",current_balance_frac"
      ",expiration_date"
      ",gc_date"
      " FROM reserves"
      " WHERE reserve_uuid > $1"
      " ORDER BY reserve_uuid ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_reserves_in",
      "SELECT"
      " reserve_in_serial_id AS serial"
      ",reserve_pub"
      ",wire_reference"
      ",credit_val"
      ",credit_frac"
      ",wire_source_h_payto"
      ",exchange_account_section"
      ",execution_date"
      " FROM reserves_in"
      " WHERE reserve_in_serial_id > $1"
      " ORDER BY reserve_in_serial_id ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_reserves_close",
      "SELECT"
      " close_uuid AS serial"
      ",reserve_pub"
      ",execution_date"
      ",wtid"
      ",wire_target_h_payto"
      ",amount_val"
      ",amount_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      " FROM reserves_close"
      " WHERE close_uuid > $1"
      " ORDER BY close_uuid ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_reserves_out",
      "SELECT"
      " reserve_out_serial_id AS serial"
      ",h_blind_ev"
      ",denominations_serial"
      ",denom_sig"
      ",reserve_uuid"
      ",reserve_sig"
      ",execution_date"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      " FROM reserves_out"
      " JOIN reserves USING (reserve_uuid)"
      " WHERE reserve_out_serial_id > $1"
      " ORDER BY reserve_out_serial_id ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_auditors",
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
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_auditor_denom_sigs",
      "SELECT"
      " auditor_denom_serial AS serial"
      ",auditor_uuid"
      ",denominations_serial"
      ",auditor_sig"
      " FROM auditor_denom_sigs"
      " WHERE auditor_denom_serial > $1"
      " ORDER BY auditor_denom_serial ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_exchange_sign_keys",
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
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_known_coins",
      "SELECT"
      " known_coin_id AS serial"
      ",coin_pub"
      ",denom_sig"
      ",denominations_serial"
      ",remaining_val"
      ",remaining_frac"
      " FROM known_coins"
      " WHERE known_coin_id > $1"
      " ORDER BY known_coin_id ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_refresh_commitments",
      "SELECT"
      " melt_serial_id AS serial"
      ",rc"
      ",old_coin_sig"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",noreveal_index"
      ",old_coin_pub"
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
      ",ev_sig"
      ",ewv"
      ",denominations_serial"
      ",melt_serial_id"
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
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_deposits",
      "SELECT"
      " deposit_serial_id AS serial"
      ",shard"
      ",coin_pub"
      ",known_coin_id"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",wallet_timestamp"
      ",exchange_timestamp"
      ",refund_deadline"
      ",wire_deadline"
      ",merchant_pub"
      ",h_contract_terms"
      ",coin_sig"
      ",wire_salt"
      ",wire_target_h_payto"
      ",tiny"
      ",done"
      ",extension_blocked"
      ",extension_details_serial_id"
      " FROM deposits"
      " WHERE deposit_serial_id > $1"
      " ORDER BY deposit_serial_id ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_refunds",
      "SELECT"
      " refund_serial_id AS serial"
      ",shard"
      ",merchant_sig"
      ",rtransaction_id"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",deposit_serial_id"
      " FROM refunds"
      " WHERE refund_serial_id > $1"
      " ORDER BY refund_serial_id ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_wire_out",
      "SELECT"
      " wireout_uuid AS serial"
      ",execution_date"
      ",wtid_raw"
      ",wire_target_h_payto"
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
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_wire_fee",
      "SELECT"
      " wire_fee_serial AS serial"
      ",wire_method"
      ",start_date"
      ",end_date"
      ",wire_fee_val"
      ",wire_fee_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",wad_fee_val"
      ",wad_fee_frac"
      ",master_sig"
      " FROM wire_fee"
      " WHERE wire_fee_serial > $1"
      " ORDER BY wire_fee_serial ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_global_fee",
      "SELECT"
      " global_fee_serial AS serial"
      ",start_date"
      ",end_date"
      ",history_fee_val"
      ",history_fee_frac"
      ",kyc_fee_val"
      ",kyc_fee_frac"
      ",account_fee_val"
      ",account_fee_frac"
      ",purse_fee_val"
      ",purse_fee_frac"
      ",purse_timeout"
      ",kyc_timeout"
      ",history_expiration"
      ",purse_account_limit"
      ",master_sig"
      " FROM global_fee"
      " WHERE global_fee_serial > $1"
      " ORDER BY global_fee_serial ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_recoup",
      "SELECT"
      " recoup_uuid AS serial"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",coin_pub"
      ",reserve_out_serial_id"
      " FROM recoup"
      " WHERE recoup_uuid > $1"
      " ORDER BY recoup_uuid ASC;",
      1),
    GNUNET_PQ_make_prepare (
      "select_above_serial_by_table_recoup_refresh",
      "SELECT"
      " recoup_refresh_uuid AS serial"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",coin_pub"
      ",known_coin_id"
      ",rrc_serial"
      " FROM recoup_refresh"
      " WHERE recoup_refresh_uuid > $1"
      " ORDER BY recoup_refresh_uuid ASC;",
      1),
    /* For postgres_insert_records_by_table */
    GNUNET_PQ_make_prepare (
      "insert_into_table_denominations",
      "INSERT INTO denominations"
      "(denominations_serial"
      ",denom_pub_hash"
      ",denom_type"
      ",age_mask"
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
      " $11, $12, $13, $14, $15, $16, $17, $18, $19, $20);",
      20),
    GNUNET_PQ_make_prepare (
      "insert_into_table_denomination_revocations",
      "INSERT INTO denomination_revocations"
      "(denom_revocations_serial_id"
      ",master_sig"
      ",denominations_serial"
      ") VALUES "
      "($1, $2, $3);",
      3),
    GNUNET_PQ_make_prepare (
      "insert_into_table_wire_targets",
      "INSERT INTO wire_targets"
      "(wire_target_serial_id"
      ",wire_target_h_payto"
      ",payto_uri"
      ",kyc_ok"
      ",external_id"
      ") VALUES "
      "($1, $2, $3, $4, $5);",
      5),
    GNUNET_PQ_make_prepare (
      "insert_into_table_reserves",
      "INSERT INTO reserves"
      "(reserve_uuid"
      ",reserve_pub"
      ",current_balance_val"
      ",current_balance_frac"
      ",expiration_date"
      ",gc_date"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6);",
      6),
    GNUNET_PQ_make_prepare (
      "insert_into_table_reserves_in",
      "INSERT INTO reserves_in"
      "(reserve_in_serial_id"
      ",wire_reference"
      ",credit_val"
      ",credit_frac"
      ",wire_source_h_payto"
      ",exchange_account_section"
      ",execution_date"
      ",reserve_pub"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8);",
      8),
    GNUNET_PQ_make_prepare (
      "insert_into_table_reserves_close",
      "INSERT INTO reserves_close"
      "(close_uuid"
      ",execution_date"
      ",wtid"
      ",wire_target_h_payto"
      ",amount_val"
      ",amount_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",reserve_pub"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
      9),
    GNUNET_PQ_make_prepare (
      "insert_into_table_reserves_out",
      "INSERT INTO reserves_out"
      "(reserve_out_serial_id"
      ",h_blind_ev"
      ",denominations_serial"
      ",denom_sig"
      ",reserve_uuid"
      ",reserve_sig"
      ",execution_date"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
      9),
    GNUNET_PQ_make_prepare (
      "insert_into_table_auditors",
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
    GNUNET_PQ_make_prepare (
      "insert_into_table_auditor_denom_sigs",
      "INSERT INTO auditor_denom_sigs"
      "(auditor_denom_serial"
      ",auditor_uuid"
      ",denominations_serial"
      ",auditor_sig"
      ") VALUES "
      "($1, $2, $3, $4);",
      4),
    GNUNET_PQ_make_prepare (
      "insert_into_table_exchange_sign_keys",
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
    GNUNET_PQ_make_prepare (
      "insert_into_table_signkey_revocations",
      "INSERT INTO signkey_revocations"
      "(signkey_revocations_serial_id"
      ",esk_serial"
      ",master_sig"
      ") VALUES "
      "($1, $2, $3);",
      3),
    GNUNET_PQ_make_prepare (
      "insert_into_table_known_coins",
      "INSERT INTO known_coins"
      "(known_coin_id"
      ",coin_pub"
      ",denom_sig"
      ",denominations_serial"
      ",remaining_val"
      ",remaining_frac"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6);",
      6),
    GNUNET_PQ_make_prepare (
      "insert_into_table_refresh_commitments",
      "INSERT INTO refresh_commitments"
      "(melt_serial_id"
      ",rc"
      ",old_coin_sig"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",noreveal_index"
      ",old_coin_pub"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7);",
      7),
    GNUNET_PQ_make_prepare (
      "insert_into_table_refresh_revealed_coins",
      "INSERT INTO refresh_revealed_coins"
      "(rrc_serial"
      ",freshcoin_index"
      ",link_sig"
      ",coin_ev"
      ",h_coin_ev"
      ",ev_sig"
      ",ewv"
      ",denominations_serial"
      ",melt_serial_id"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
      9),
    GNUNET_PQ_make_prepare (
      "insert_into_table_refresh_transfer_keys",
      "INSERT INTO refresh_transfer_keys"
      "(rtc_serial"
      ",transfer_pub"
      ",transfer_privs"
      ",melt_serial_id"
      ") VALUES "
      "($1, $2, $3, $4);",
      4),
    GNUNET_PQ_make_prepare (
      "insert_into_table_deposits",
      "INSERT INTO deposits"
      "(deposit_serial_id"
      ",shard"
      ",known_coin_id"
      ",coin_pub"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",wallet_timestamp"
      ",exchange_timestamp"
      ",refund_deadline"
      ",wire_deadline"
      ",merchant_pub"
      ",h_contract_terms"
      ",coin_sig"
      ",wire_salt"
      ",wire_target_h_payto"
      ",tiny"
      ",done"
      ",extension_blocked"
      ",extension_details_serial_id"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
      " $11, $12, $13, $14, $15, $16, $17, $18, $19);",
      19),
    GNUNET_PQ_make_prepare (
      "insert_into_table_refunds",
      "INSERT INTO refunds"
      "(shard"
      ",refund_serial_id"
      ",merchant_sig"
      ",rtransaction_id"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",deposit_serial_id"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7);",
      7),
    GNUNET_PQ_make_prepare (
      "insert_into_table_aggregation_tracking",
      "INSERT INTO aggregation_tracking"
      "(aggregation_serial_id"
      ",deposit_serial_id"
      ",wtid_raw"
      ") VALUES "
      "($1, $2, $3);",
      3),
    GNUNET_PQ_make_prepare (
      "insert_into_table_wire_fee",
      "INSERT INTO wire_fee"
      "(wire_fee_serial"
      ",wire_method"
      ",start_date"
      ",end_date"
      ",wire_fee_val"
      ",wire_fee_frac"
      ",closing_fee_val"
      ",closing_fee_frac"
      ",wad_fee_val"
      ",wad_fee_frac"
      ",master_sig"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);",
      11),
    GNUNET_PQ_make_prepare (
      "insert_into_table_global_fee",
      "INSERT INTO global_fee"
      "(global_fee_serial"
      ",start_date"
      ",end_date"
      ",history_fee_val"
      ",history_fee_frac"
      ",kyc_fee_val"
      ",kyc_fee_frac"
      ",account_fee_val"
      ",account_fee_frac"
      ",purse_fee_val"
      ",purse_fee_frac"
      ",purse_timeout"
      ",kyc_timeout"
      ",history_expiration"
      ",purse_account_limit"
      ",master_sig"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16);",
      16),
    GNUNET_PQ_make_prepare (
      "insert_into_table_recoup",
      "INSERT INTO recoup"
      "(recoup_uuid"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",coin_pub"
      ",reserve_out_serial_id"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8);",
      8),
    GNUNET_PQ_make_prepare (
      "insert_into_table_recoup_refresh",
      "INSERT INTO recoup_refresh"
      "(recoup_refresh_uuid"
      ",coin_sig"
      ",coin_blind"
      ",amount_val"
      ",amount_frac"
      ",recoup_timestamp"
      ",known_coin_id"
      ",coin_pub"
      ",rrc_serial"
      ") VALUES "
      "($1, $2, $3, $4, $5, $6, $7, $8, $9);",
      9),
    GNUNET_PQ_make_prepare (
      "insert_into_table_extensions",
      "INSERT INTO extensions"
      "(extension_id"
      ",name"
      ",config"
      ") VALUES "
      "($1, $2, $3);",
      3),
    GNUNET_PQ_make_prepare (
      "insert_into_table_extension_details",
      "INSERT INTO extension_details"
      "(extension_details_serial_id"
      ",extension_options"
      ") VALUES "
      "($1, $2);",
      2),

    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "get_open_shard",
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
    /* Used in #postgres_begin_revolving_shard() */
    GNUNET_PQ_make_prepare (
      "get_open_revolving_shard",
      "SELECT"
      " start_row"
      ",end_row"
      " FROM revolving_work_shards"
      " WHERE job_name=$1"
      "   AND active=FALSE"
      " ORDER BY last_attempt ASC"
      " LIMIT 1;",
      2),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "reclaim_shard",
      "UPDATE work_shards"
      " SET last_attempt=$2"
      " WHERE job_name=$1"
      "   AND start_row=$3"
      "   AND end_row=$4",
      4),
    /* Used in #postgres_begin_revolving_shard() */
    GNUNET_PQ_make_prepare (
      "reclaim_revolving_shard",
      "UPDATE revolving_work_shards"
      " SET last_attempt=$2"
      "    ,active=TRUE"
      " WHERE job_name=$1"
      "   AND start_row=$3"
      "   AND end_row=$4",
      4),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "get_last_shard",
      "SELECT"
      " end_row"
      " FROM work_shards"
      " WHERE job_name=$1"
      " ORDER BY end_row DESC"
      " LIMIT 1;",
      1),
    /* Used in #postgres_begin_revolving_shard() */
    GNUNET_PQ_make_prepare (
      "get_last_revolving_shard",
      "SELECT"
      " end_row"
      " FROM revolving_work_shards"
      " WHERE job_name=$1"
      " ORDER BY end_row DESC"
      " LIMIT 1;",
      1),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "claim_next_shard",
      "INSERT INTO work_shards"
      "(job_name"
      ",last_attempt"
      ",start_row"
      ",end_row"
      ") VALUES "
      "($1, $2, $3, $4);",
      4),
    /* Used in #postgres_claim_revolving_shard() */
    GNUNET_PQ_make_prepare (
      "create_revolving_shard",
      "INSERT INTO revolving_work_shards"
      "(job_name"
      ",last_attempt"
      ",start_row"
      ",end_row"
      ",active"
      ") VALUES "
      "($1, $2, $3, $4, TRUE);",
      4),
    /* Used in #postgres_complete_shard() */
    GNUNET_PQ_make_prepare (
      "complete_shard",
      "UPDATE work_shards"
      " SET completed=TRUE"
      " WHERE job_name=$1"
      "   AND start_row=$2"
      "   AND end_row=$3",
      3),
    /* Used in #postgres_complete_shard() */
    GNUNET_PQ_make_prepare (
      "release_revolving_shard",
      "UPDATE revolving_work_shards"
      " SET active=FALSE"
      " WHERE job_name=$1"
      "   AND start_row=$2"
      "   AND end_row=$3",
      3),
    /* Used in #postgres_set_extension_config */
    GNUNET_PQ_make_prepare (
      "set_extension_config",
      "INSERT INTO extensions (name, config) VALUES ($1, $2) "
      "ON CONFLICT (name) "
      "DO UPDATE SET config=$2",
      2),
    /* Used in #postgres_get_extension_config */
    GNUNET_PQ_make_prepare (
      "get_extension_config",
      "SELECT "
      " config "
      "FROM extensions"
      "   WHERE name=$1;",
      1),

    /* Used in #postgres_insert_partner() */
    GNUNET_PQ_make_prepare (
      "insert_partner",
      "INSERT INTO partners"
      "  (partner_master_pub"
      "  ,start_date"
      "  ,end_date"
      "  ,wad_frequency"
      "  ,wad_fee_val"
      "  ,wad_fee_frac"
      "  ,master_sig"
      "  ,partner_base_url"
      "  ) VALUES "
      "  ($1, $2, $3, $4, $5, $6, $7, $8);",
      8),
    /* Used in #postgres_insert_contract() */
    GNUNET_PQ_make_prepare (
      "insert_contract",
      "INSERT INTO contracts"
      "  (purse_pub"
      "  ,pub_ckey"
      "  ,e_contract"
      "  ,purse_expiration"
      "  ) SELECT "
      "  $1, $2, $3, purse_expiration"
      "  FROM purse_requests"
      "  WHERE purse_pub=$1;",
      3),
    /* Used in #postgres_select_contract */
    GNUNET_PQ_make_prepare (
      "select_contract",
      "SELECT "
      " pub_ckey"
      ",e_contract"
      " FROM contracts"
      "   WHERE purse_pub=$1;",
      1),
    /* Used in #postgres_insert_purse_request() */
    GNUNET_PQ_make_prepare (
      "insert_purse_request",
      "INSERT INTO purse_requests"
      "  (purse_pub"
      "  ,merge_pub"
      "  ,purse_expiration"
      "  ,h_contract_terms"
      "  ,age_limit"
      "  ,amount_with_fee_val"
      "  ,amount_with_fee_frac"
      "  ,purse_sig"
      "  ) VALUES "
      "  ($1, $2, $3, $4, $5, $6, $7, $8);",
      7),
    /* Used in #postgres_select_purse_request */
    GNUNET_PQ_make_prepare (
      "select_purse_request",
      "SELECT "
      " merge_pub"
      ",purse_expiration"
      ",h_contract_terms"
      ",age_limit"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",purse_sig"
      " FROM purse_requests"
      " WHERE purse_pub=$1;",
      1),
    /* Used in #postgres_do_purse_deposit() */
    GNUNET_PQ_make_prepare (
      "call_purse_deposit",
      "SELECT 1"
      " FROM exchange_do_purse_deposit"
      "  ($1, $2, $3, $4, $5);",
      5),
    /* Used in #postgres_do_purse_merge() */
    GNUNET_PQ_make_prepare (
      "call_purse_merge",
      "SELECT 1"
      " FROM exchange_do_purse_merge"
      "  ($1, $2, $3, $4, $5);",
      5),
    /* Used in #postgres_select_purse_merge */
    GNUNET_PQ_make_prepare (
      "select_purse_merge",
      "SELECT "
      " reserve_pub"
      ",purse_pub"
      ",merge_sig"
      ",merge_timestamp"
      ",partner_base_url"
      " FROM purse_merges"
      " JOIN partners USING (partner_serial_id)"
      " WHERE purse_pub=$1;",
      1),
    /* Used in #postgres_do_account_merge() */
    GNUNET_PQ_make_prepare (
      "call_account_merge",
      "SELECT 1"
      " FROM exchange_do_account_merge"
      "  ($1, $2, $3);",
      3),
    /* Used in #postgres_insert_history_request() */
    GNUNET_PQ_make_prepare (
      "call_history_request",
      "SELECT 1"
      " FROM exchange_do_history_request"
      "  ($1, $2, $3, $4, $5)",
      5),
    /* Used in #postgres_insert_close_request() */
    GNUNET_PQ_make_prepare (
      "call_account_close",
      "SELECT "
      " out_final_balance_val"
      ",out_final_balance_frac"
      " FROM exchange_do_close_request"
      "  ($1, $2)",
      2),

    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  ret = GNUNET_PQ_prepare_statements (pg->conn,
                                      ps);
  if (GNUNET_OK != ret)
    return ret;
  pg->init = true;
  return GNUNET_OK;
}


/**
 * Connect to the database if the connection does not exist yet.
 *
 * @param pg the plugin-specific state
 * @param skip_prepare true if we should skip prepared statement setup
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
internal_setup (struct PostgresClosure *pg,
                bool skip_prepare)
{
  if (NULL == pg->conn)
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
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute (
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      GNUNET_PQ_make_try_execute ("SET autocommit=OFF;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
#endif
    struct GNUNET_PQ_Context *db_conn;

    db_conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                          "exchangedb-postgres",
                                          NULL,
                                          es,
                                          NULL);
    if (NULL == db_conn)
      return GNUNET_SYSERR;
    pg->conn = db_conn;
  }
  if (NULL == pg->transaction_name)
    GNUNET_PQ_reconnect_if_down (pg->conn);
  if (pg->init)
    return GNUNET_OK;
  if (skip_prepare)
    return GNUNET_OK;
  return prepare_statements (pg);
}


/**
 * Do a pre-flight check that we are not in an uncommitted transaction.
 * If we are, try to commit the previous transaction and output a warning.
 * Does not return anything, as we will continue regardless of the outcome.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return #GNUNET_OK if everything is fine
 *         #GNUNET_NO if a transaction was rolled back
 *         #GNUNET_SYSERR on hard errors
 */
static enum GNUNET_GenericReturnValue
postgres_preflight (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("ROLLBACK"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (! pg->init)
  {
    if (GNUNET_OK !=
        internal_setup (pg,
                        false))
      return GNUNET_SYSERR;
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
 * @param name unique name identifying the transaction (for debugging)
 *             must point to a constant
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
postgres_start (void *cls,
                const char *name)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("START TRANSACTION ISOLATION LEVEL SERIALIZABLE"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (GNUNET_SYSERR ==
      postgres_preflight (pg))
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting transaction named %s on %p\n",
              name,
              pg->conn);
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR ("Failed to start transaction\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  pg->transaction_name = name;
  return GNUNET_OK;
}


/**
 * Start a READ COMMITTED transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param name unique name identifying the transaction (for debugging)
 *             must point to a constant
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
postgres_start_read_committed (void *cls,
                               const char *name)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("START TRANSACTION ISOLATION LEVEL READ COMMITTED"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (GNUNET_SYSERR ==
      postgres_preflight (pg))
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting transaction named %s on %p\n",
              name,
              pg->conn);
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR ("Failed to start transaction\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  pg->transaction_name = name;
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

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Rolling back transaction on %p\n",
              pg->conn);
  GNUNET_break (GNUNET_OK ==
                GNUNET_PQ_exec_statements (pg->conn,
                                           es));
  pg->transaction_name = NULL;
}


/**
 * Commit the current transaction of a database connection.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @return final transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_commit (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "do_commit",
                                           params);
  pg->transaction_name = NULL;
  return qs;
}


/**
 * Register callback to be invoked on events of type @a es.
 *
 * @param cls database context to use
 * @param timeout how long until to generate a timeout event
 * @param es specification of the event to listen for
 * @param cb function to call when the event happens, possibly
 *         multiple times (until cancel is invoked)
 * @param cb_cls closure for @a cb
 * @return handle useful to cancel the listener
 */
static struct GNUNET_DB_EventHandler *
postgres_event_listen (void *cls,
                       struct GNUNET_TIME_Relative timeout,
                       const struct GNUNET_DB_EventHeaderP *es,
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
 * @param cls the plugin's `struct PostgresClosure`
 * @param eh handle to unregister.
 */
static void
postgres_event_listen_cancel (void *cls,
                              struct GNUNET_DB_EventHandler *eh)
{
  (void) cls;
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

  GNUNET_PQ_event_notify (pg->conn,
                          es,
                          extra,
                          extra_size);
}


/**
 * Insert a denomination key's public information into the database for
 * reference by auditors and other consistency checks.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub the public key used for signing coins of this denomination
 * @param issue issuing information with value, fees and other info about the coin
 * @return status of the query
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_info (
  void *cls,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct PostgresClosure *pg = cls;
  struct TALER_DenominationHashP denom_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&issue->properties.denom_hash),
    TALER_PQ_query_param_denom_pub (denom_pub),
    GNUNET_PQ_query_param_auto_from_type (&issue->signature),
    GNUNET_PQ_query_param_timestamp_nbo (&issue->properties.start),
    GNUNET_PQ_query_param_timestamp_nbo (&issue->properties.expire_withdraw),
    GNUNET_PQ_query_param_timestamp_nbo (&issue->properties.expire_deposit),
    GNUNET_PQ_query_param_timestamp_nbo (&issue->properties.expire_legal),
    TALER_PQ_query_param_amount_nbo (&issue->properties.value),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fees.withdraw),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fees.deposit),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fees.refresh),
    TALER_PQ_query_param_amount_nbo (&issue->properties.fees.refund),
    GNUNET_PQ_query_param_uint32 (&denom_pub->age_mask.bits),
    GNUNET_PQ_query_param_end
  };
  struct TALER_DenomFeeSet fees;

  GNUNET_assert (denom_pub->age_mask.bits ==
                 issue->age_mask.bits);
  TALER_denom_pub_hash (denom_pub,
                        &denom_hash);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&denom_hash,
                                &issue->properties.denom_hash));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   GNUNET_TIME_timestamp_ntoh (
                     issue->properties.start).abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   GNUNET_TIME_timestamp_ntoh (
                     issue->properties.expire_withdraw).abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   GNUNET_TIME_timestamp_ntoh (
                     issue->properties.expire_deposit).abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   GNUNET_TIME_timestamp_ntoh (
                     issue->properties.expire_legal).abs_time));
  /* check fees match denomination currency */
  TALER_denom_fee_set_ntoh (&fees,
                            &issue->properties.fees);
  GNUNET_assert (GNUNET_YES ==
                 TALER_denom_fee_check_currency (
                   issue->properties.value.currency,
                   &fees));
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "denomination_insert",
                                             params);
}


/**
 * Fetch information about a denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the public key used for signing coins of this denomination
 * @param[out] issue set to issue information with value, fees and other info about the coin
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_info (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
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
    GNUNET_PQ_result_spec_timestamp_nbo ("valid_from",
                                         &issue->properties.start),
    GNUNET_PQ_result_spec_timestamp_nbo ("expire_withdraw",
                                         &issue->properties.expire_withdraw),
    GNUNET_PQ_result_spec_timestamp_nbo ("expire_deposit",
                                         &issue->properties.expire_deposit),
    GNUNET_PQ_result_spec_timestamp_nbo ("expire_legal",
                                         &issue->properties.expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("coin",
                                     &issue->properties.value),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_withdraw",
                                     &issue->properties.fees.withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_deposit",
                                     &issue->properties.fees.deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refresh",
                                     &issue->properties.fees.refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refund",
                                     &issue->properties.fees.refund),
    GNUNET_PQ_result_spec_uint32 ("age_mask",
                                  &issue->age_mask.bits),
    GNUNET_PQ_result_spec_end
  };

  memset (&issue->properties.master,
          0,
          sizeof (issue->properties.master));
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "denomination_get",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;
  issue->properties.purpose.size
    = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
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
    struct TALER_DenominationHashP denom_hash;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &issue.signature),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &denom_hash),
      GNUNET_PQ_result_spec_timestamp_nbo ("valid_from",
                                           &issue.properties.start),
      GNUNET_PQ_result_spec_timestamp_nbo ("expire_withdraw",
                                           &issue.properties.expire_withdraw),
      GNUNET_PQ_result_spec_timestamp_nbo ("expire_deposit",
                                           &issue.properties.expire_deposit),
      GNUNET_PQ_result_spec_timestamp_nbo ("expire_legal",
                                           &issue.properties.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("coin",
                                       &issue.properties.value),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_withdraw",
                                       &issue.properties.fees.withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_deposit",
                                       &issue.properties.fees.deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refresh",
                                       &issue.properties.fees.refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("fee_refund",
                                       &issue.properties.fees.refund),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_uint32 ("age_mask",
                                    &issue.age_mask.bits),
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

    /* Unfortunately we have to carry the age mask in both, the
     * TALER_DenominationPublicKey and
     * TALER_EXCHANGEDB_DenominationKeyInformationP at different times.
     * Here we use _both_ so let's make sure the values are the same. */
    denom_pub.age_mask = issue.age_mask;

    issue.properties.purpose.size
      = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
    issue.properties.purpose.purpose
      = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
    TALER_denom_pub_hash (&denom_pub,
                          &issue.properties.denom_hash);
    if (0 !=
        GNUNET_memcmp (&issue.properties.denom_hash,
                       &denom_hash))
    {
      GNUNET_break (0);
    }
    else
    {
      dic->cb (dic->cb_cls,
               &denom_pub,
               &issue);
    }
    TALER_denom_pub_free (&denom_pub);
  }
}


/**
 * Fetch information about all known denomination keys.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each denomination key
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_iterate_denomination_info (void *cls,
                                    TALER_EXCHANGEDB_DenominationCallback cb,
                                    void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
    struct TALER_EXCHANGEDB_DenominationKeyMetaData meta = {0};
    struct TALER_DenominationPublicKey denom_pub = {0};
    struct TALER_MasterSignatureP master_sig = {0};
    struct TALER_DenominationHashP h_denom_pub = {0};
    bool revoked;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &master_sig),
      GNUNET_PQ_result_spec_bool ("revoked",
                                  &revoked),
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &meta.start),
      GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                       &meta.expire_withdraw),
      GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                       &meta.expire_deposit),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                       &meta.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                   &meta.value),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                   &meta.fees.withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &meta.fees.deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                   &meta.fees.refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                   &meta.fees.refund),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_uint32 ("age_mask",
                                    &meta.age_mask.bits),
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

    /* make sure the mask information is the same */
    denom_pub.age_mask = meta.age_mask;

    TALER_denom_pub_hash (&denom_pub,
                          &h_denom_pub);
    dic->cb (dic->cb_cls,
             &denom_pub,
             &h_denom_pub,
             &meta,
             &master_sig,
             revoked);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called to invoke @a cb on every known denomination key (revoked
 * and non-revoked) that has been signed by the master key. Runs in its own
 * read-only transaction.
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct DenomsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &meta.start),
      GNUNET_PQ_result_spec_timestamp ("expire_sign",
                                       &meta.expire_sign),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
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
 * expired keys are skipped. Runs in its own read-only transaction.
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct SignkeysIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };

  now = GNUNET_TIME_absolute_get ();
  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * auditors are skipped. Runs in its own read-only transaction.
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct AuditorsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
    struct TALER_DenominationHashP h_denom_pub;
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
 * skipped. Runs in its own read-only transaction.
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct AuditorDenomsIteratorContext dic = {
    .cb = cb,
    .cb_cls = cb_cls,
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "select_auditor_denoms",
                                               params,
                                               &auditor_denoms_cb_helper,
                                               &dic);
}


/**
 * Get the summary of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param[in,out] reserve the reserve data.  The public key of the reserve should be
 *          set in this structure; it is used to query the database.  The balance
 *          and expiration are then filled accordingly.
 * @param[out] kyc set to the KYC status of the reserve
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_reserves_get (void *cls,
                       struct TALER_EXCHANGEDB_Reserve *reserve,
                       struct TALER_EXCHANGEDB_KycStatus *kyc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance",
                                 &reserve->balance),
    GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                     &reserve->expiry),
    GNUNET_PQ_result_spec_timestamp ("gc_date",
                                     &reserve->gc),
    GNUNET_PQ_result_spec_uint64 ("payment_target_uuid",
                                  &kyc->payment_target_uuid),
    GNUNET_PQ_result_spec_bool ("kyc_ok",
                                &kyc->ok),
    GNUNET_PQ_result_spec_end
  };

  kyc->type = TALER_EXCHANGEDB_KYC_WITHDRAW;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "reserves_get_with_kyc",
                                                   params,
                                                   rs);
}


/**
 * Set the KYC status to "OK" for a bank account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto which account has been checked
 * @param id external ID to persist
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_set_kyc_ok (void *cls,
                     const struct TALER_PaytoHashP *h_payto,
                     const char *id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam params2[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (id),
    GNUNET_PQ_query_param_end
  };
  struct TALER_KycCompletedEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED)
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wire_target_h_payto",
                                          &rep.h_payto),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "set_kyc_ok",
                                           params2);
  if (qs <= 0)
    return qs;
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_kyc_h_payto",
                                                 params,
                                                 rs);
  if (qs <= 0)
    return qs;
  postgres_event_notify (pg,
                         &rep.header,
                         NULL,
                         0);
  return qs;
}


/**
 * Get the @a kyc status and @a h_payto by UUID.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto set to the hash of the account's payto URI (unsalted)
 * @param[out] kyc set to the KYC status of the account
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_select_kyc_status (void *cls,
                            const struct TALER_PaytoHashP *h_payto,
                            struct TALER_EXCHANGEDB_KycStatus *kyc)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("wire_target_serial_id",
                                  &kyc->payment_target_uuid),
    GNUNET_PQ_result_spec_bool ("kyc_ok",
                                &kyc->ok),
    GNUNET_PQ_result_spec_end
  };

  kyc->type = TALER_EXCHANGEDB_KYC_UNKNOWN;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_kyc_status_by_payto",
                                                   params,
                                                   rs);
}


/**
 * Get the KYC status for a wallet. If the status is unknown,
 * inserts a new status record (hence INsertSELECT).
 *
 * @param pg the plugin-specific state
 * @param payto_uri the payto URI to check
 * @param[out] kyc set to the KYC status of the wallet
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
inselect_account_kyc_status (
  struct PostgresClosure *pg,
  const char *payto_uri,
  struct TALER_EXCHANGEDB_KycStatus *kyc)
{
  struct TALER_PaytoHashP h_payto;
  enum GNUNET_DB_QueryStatus qs;

  TALER_payto_hash (payto_uri,
                    &h_payto);
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("wire_target_serial_id",
                                    &kyc->payment_target_uuid),
      GNUNET_PQ_result_spec_bool ("kyc_ok",
                                  &kyc->ok),
      GNUNET_PQ_result_spec_end
    };

    qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_kyc_status_by_payto",
                                                   params,
                                                   rs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      struct GNUNET_PQ_QueryParam iparams[] = {
        GNUNET_PQ_query_param_auto_from_type (&h_payto),
        GNUNET_PQ_query_param_string (payto_uri),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec irs[] = {
        GNUNET_PQ_result_spec_uint64 ("wire_target_serial_id",
                                      &kyc->payment_target_uuid),
        GNUNET_PQ_result_spec_end
      };

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "insert_kyc_status",
                                                     iparams,
                                                     irs);
      if (qs < 0)
        return qs;
      if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
        return GNUNET_DB_STATUS_SOFT_ERROR;
      kyc->ok = false;
    }
  }
  kyc->type = TALER_EXCHANGEDB_KYC_BALANCE;
  return qs;
}


/**
 * Get the KYC status for a wallet. If the status is unknown,
 * inserts a new status record (hence INsertSELECT).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the wallet
 * @param[out] kyc set to the KYC status of the wallet
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_inselect_wallet_kyc_status (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_EXCHANGEDB_KycStatus *kyc)
{
  struct PostgresClosure *pg = cls;
  char *payto_uri;
  enum GNUNET_DB_QueryStatus qs;

  payto_uri = TALER_payto_from_reserve (pg->exchange_url,
                                        reserve_pub);
  qs = inselect_account_kyc_status (pg,
                                    payto_uri,
                                    kyc);
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Wire account for `%s' is %llu\n",
              payto_uri,
              (unsigned long long) kyc->payment_target_uuid);
  GNUNET_free (payto_uri);
  return qs;
}


/**
 * Get the summary of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param[in,out] reserve the reserve data.  The public key of the reserve should be
 *          set in this structure; it is used to query the database.  The balance
 *          and expiration are then filled accordingly.
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserves_get_internal (void *cls,
                       struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance",
                                 &reserve->balance),
    GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                     &reserve->expiry),
    GNUNET_PQ_result_spec_timestamp ("gc_date",
                                     &reserve->gc),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "reserves_get",
                                                   params,
                                                   rs);
}


/**
 * Updates a reserve with the data from the given reserve structure.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve the reserve structure whose data will be used to update the
 *          corresponding record in the database.
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserves_update (void *cls,
                 const struct TALER_EXCHANGEDB_Reserve *reserve)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&reserve->expiry),
    GNUNET_PQ_query_param_timestamp (&reserve->gc),
    TALER_PQ_query_param_amount (&reserve->balance),
    GNUNET_PQ_query_param_auto_from_type (&reserve->pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "reserve_update",
                                             params);
}


/**
 * Generate event notification for the reserve
 * change.
 *
 * @param pg plugin state
 * @param reserve_pub reserve to notfiy on
 */
static void
notify_on_reserve (struct PostgresClosure *pg,
                   const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct TALER_ReserveEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_RESERVE_INCOMING),
    .reserve_pub = *reserve_pub
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Notifying on reserve!\n");
  postgres_event_notify (pg,
                         &rep.header,
                         NULL,
                         0);
}


/**
 * Insert an incoming transaction into reserves.  New reserves are also
 * created through this function. Started within the scope of an ongoing
 * transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
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
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Timestamp execution_time,
                             const char *sender_account_details,
                             const char *exchange_account_section,
                             uint64_t wire_ref)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs1;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Timestamp expiry;
  struct GNUNET_TIME_Timestamp gc;
  uint64_t reserve_uuid;

  reserve.pub = *reserve_pub;
  expiry = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (execution_time.abs_time,
                              pg->idle_reserve_expiration_time));
  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                              pg->legal_reserve_expiration_time));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating reserve %s with expiration in %s\n",
              TALER_B2S (reserve_pub),
              GNUNET_STRINGS_relative_time_to_string (
                pg->idle_reserve_expiration_time,
                GNUNET_NO));
  /* Optimistically assume this is a new reserve, create balance for the first
     time; we do this before adding the actual transaction to "reserves_in",
     as for a new reserve it can't be a duplicate 'add' operation, and as
     the 'add' operation needs the reserve entry as a foreign key. */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &reserve_uuid),
      GNUNET_PQ_result_spec_end
    };

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    /* Note: query uses 'on conflict do nothing' */
    qs1 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "reserve_create",
                                                    params,
                                                    rs);
    if (qs1 < 0)
      return qs1;
  }

  /* Create new incoming transaction, "ON CONFLICT DO NOTHING"
     is again used to guard against duplicates. */
  {
    enum GNUNET_DB_QueryStatus qs2;
    struct TALER_EXCHANGEDB_KycStatus kyc;
    enum GNUNET_DB_QueryStatus qs3;
    struct TALER_PaytoHashP h_payto;

    TALER_payto_hash (sender_account_details,
                      &h_payto);
    memset (&kyc,
            0,
            sizeof (kyc));
    /* FIXME: inselect re-computes h_payto... */
    qs3 = inselect_account_kyc_status (pg,
                                       sender_account_details,
                                       &kyc);
    if (qs3 <= 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs3);
      return qs3;
    }
    GNUNET_assert (0 != kyc.payment_target_uuid);
    /* We do not have the UUID, so insert by public key */
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserve.pub),
      GNUNET_PQ_query_param_uint64 (&wire_ref),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_string (exchange_account_section),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_timestamp (&execution_time),
      GNUNET_PQ_query_param_end
    };

    qs2 = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                              "reserves_in_add_transaction",
                                              params);
    /* qs2 could be 0 as statement used 'ON CONFLICT DO NOTHING' */
    if (0 >= qs2)
    {
      if ( (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs2) &&
           (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs1) )
      {
        /* Conflict for the transaction, but the reserve was
           just now created, that should be impossible. */
        GNUNET_break (0); /* should be impossible: reserve was fresh,
                             but transaction already known */
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      /* Transaction was already known or error. We are finished. */
      return qs2;
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs1)
  {
    /* New reserve, we are finished */
    notify_on_reserve (pg,
                       reserve_pub);
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }

  /* we were wrong with our optimistic assumption:
     reserve did already exist, need to do an update instead */
  {
    /* We need to move away from 'read committed' to serializable.
       Also, we know that it should be safe to commit at this point.
       (We are only run in a larger transaction for performance.) */
    enum GNUNET_DB_QueryStatus cs;

    cs = postgres_commit (pg);
    if (cs < 0)
      return cs;
    if (GNUNET_OK !=
        postgres_start (pg,
                        "reserve-update-serializable"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  {
    enum GNUNET_DB_QueryStatus reserve_exists;

    reserve_exists = reserves_get_internal (pg,
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
    updated_reserve.expiry = GNUNET_TIME_timestamp_max (expiry,
                                                        reserve.expiry);
    updated_reserve.gc = GNUNET_TIME_timestamp_max (gc,
                                                    reserve.gc);
    qs3 = reserves_update (pg,
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
  }
  notify_on_reserve (pg,
                     reserve_pub);
  /* Go back to original transaction mode */
  {
    enum GNUNET_DB_QueryStatus cs;

    cs = postgres_commit (pg);
    if (cs < 0)
      return cs;
    if (GNUNET_OK !=
        postgres_start_read_committed (pg,
                                       "reserve-insert-continued"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Locate the response for a /reserve/withdraw request under the
 * key of the hash of the blinded message.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param bch hash that uniquely identifies the withdraw operation
 * @param collectable corresponding collectable coin (blind signature)
 *                    if a coin is found
 * @return statement execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_withdraw_info (
  void *cls,
  const struct TALER_BlindedCoinHashP *bch,
  struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (bch),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &collectable->denom_pub_hash),
    TALER_PQ_result_spec_blinded_denom_sig ("denom_sig",
                                            &collectable->sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                          &collectable->reserve_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          &collectable->reserve_pub),
    GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                          &collectable->h_coin_envelope),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &collectable->amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &collectable->withdraw_fee),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_withdraw_info",
                                                   params,
                                                   rs);
}


/**
 * Perform withdraw operation, checking for sufficient balance
 * and possibly persisting the withdrawal details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param nonce client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
 * @param[in,out] collectable corresponding collectable coin (blind signature) if a coin is found; possibly updated if a (different) signature exists already
 * @param now current time (rounded)
 * @param[out] found set to true if the reserve was found
 * @param[out] balance_ok set to true if the balance was sufficient
 * @param[out] kyc set to true if the kyc status of the reserve is satisfied
 * @param[out] ruuid set to the reserve's UUID (reserves table row)
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_withdraw (
  void *cls,
  const struct TALER_CsNonce *nonce,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
  struct GNUNET_TIME_Timestamp now,
  bool *found,
  bool *balance_ok,
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  uint64_t *ruuid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp gc;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == nonce
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (nonce),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&collectable->denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    TALER_PQ_query_param_blinded_denom_sig (&collectable->sig),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("reserve_found",
                                found),
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("kyc_ok",
                                &kyc->ok),
    GNUNET_PQ_result_spec_uint64 ("payment_target_uuid",
                                  &kyc->payment_target_uuid),
    GNUNET_PQ_result_spec_uint64 ("ruuid",
                                  ruuid),
    GNUNET_PQ_result_spec_end
  };

  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              pg->legal_reserve_expiration_time));
  kyc->type = TALER_EXCHANGEDB_KYC_WITHDRAW;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_withdraw",
                                                   params,
                                                   rs);
}


/**
 * Check that reserve remains below threshold for KYC
 * checks after withdraw operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param ruuid reserve to check
 * @param withdraw_start starting point to accumulate from
 * @param upper_limit maximum amount allowed
 * @param[out] below_limit set to true if the limit was not exceeded
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_withdraw_limit_check (
  void *cls,
  uint64_t ruuid,
  struct GNUNET_TIME_Absolute withdraw_start,
  const struct TALER_Amount *upper_limit,
  bool *below_limit)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&ruuid),
    GNUNET_PQ_query_param_absolute_time (&withdraw_start),
    TALER_PQ_query_param_amount (upper_limit),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("below_limit",
                                below_limit),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_withdraw_limit_check",
                                                   params,
                                                   rs);
}


/**
 * Compute the shard number of a given @a merchant_pub.
 *
 * @param merchant_pub merchant public key to compute shard for
 * @return shard number
 */
static uint64_t
compute_shard (const struct TALER_MerchantPublicKeyP *merchant_pub)
{
  uint32_t res;

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (&res,
                                    sizeof (res),
                                    merchant_pub,
                                    sizeof (*merchant_pub),
                                    "VOID",
                                    4,
                                    NULL, 0));
  /* interpret hash result as NBO for platform independence,
     convert to HBO and map to [0..2^31-1] range */
  res = ntohl (res);
  if (res > INT32_MAX)
    res += INT32_MIN;
  GNUNET_assert (res <= INT32_MAX);
  return (uint64_t) res;
}


/**
 * Perform deposit operation, checking for sufficient balance
 * of the coin and possibly persisting the deposit details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param deposit deposit operation details
 * @param known_coin_id row of the coin in the known_coins table
 * @param h_payto hash of the merchant's bank account details
 * @param extension_blocked true if an extension is blocking the wire transfer
 * @param[in,out] exchange_timestamp time to use for the deposit (possibly updated)
 * @param[out] balance_ok set to true if the balance was sufficient
 * @param[out] in_conflict set to true if the deposit conflicted
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_deposit (
  void *cls,
  const struct TALER_EXCHANGEDB_Deposit *deposit,
  uint64_t known_coin_id,
  const struct TALER_PaytoHashP *h_payto,
  bool extension_blocked,
  struct GNUNET_TIME_Timestamp *exchange_timestamp,
  bool *balance_ok,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = compute_shard (&deposit->merchant_pub);
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (&deposit->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&deposit->wire_salt),
    GNUNET_PQ_query_param_timestamp (&deposit->timestamp),
    GNUNET_PQ_query_param_timestamp (exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (&deposit->refund_deadline),
    GNUNET_PQ_query_param_timestamp (&deposit->wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
    GNUNET_PQ_query_param_string (deposit->receiver_wire_account),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_bool (extension_blocked),
    (NULL == deposit->extension_details)
    ? GNUNET_PQ_query_param_null ()
    : TALER_PQ_query_param_json (deposit->extension_details),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("conflicted",
                                in_conflict),
    GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                     exchange_timestamp),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_deposit",
                                                   params,
                                                   rs);
}


/**
 * Perform melt operation, checking for sufficient balance
 * of the coin and possibly persisting the melt details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param[in,out] refresh refresh operation details; the noreveal_index
 *                is set in case the coin was already melted before
 * @param known_coin_id row of the coin in the known_coins table
 * @param[in,out] zombie_required true if the melt must only succeed if the coin is a zombie, set to false if the requirement was satisfied
 * @param[out] balance_ok set to true if the balance was sufficient
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_melt (
  void *cls,
  const struct TALER_RefreshMasterSecretP *rms,
  struct TALER_EXCHANGEDB_Refresh *refresh,
  uint64_t known_coin_id,
  bool *zombie_required,
  bool *balance_ok)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == rms
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (rms),
    TALER_PQ_query_param_amount (&refresh->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&refresh->rc),
    GNUNET_PQ_query_param_auto_from_type (&refresh->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refresh->coin_sig),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_uint32 (&refresh->noreveal_index),
    GNUNET_PQ_query_param_bool (*zombie_required),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("zombie_required",
                                zombie_required),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_uint32 ("noreveal_index",
                                    &refresh->noreveal_index),
      &is_null),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "call_melt",
                                                 params,
                                                 rs);
  if (is_null)
    refresh->noreveal_index = UINT32_MAX; /* set to very invalid value */
  return qs;
}


/**
 * Perform refund operation, checking for sufficient deposits
 * of the coin and possibly persisting the refund details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param refund refund operation details
 * @param deposit_fee deposit fee applicable for the coin, possibly refunded
 * @param known_coin_id row of the coin in the known_coins table
 * @param[out] not_found set if the deposit was not found
 * @param[out] refund_ok  set if the refund succeeded (below deposit amount)
 * @param[out] gone if the merchant was already paid
 * @param[out] conflict set if the refund ID was re-used
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_refund (
  void *cls,
  const struct TALER_EXCHANGEDB_Refund *refund,
  const struct TALER_Amount *deposit_fee,
  uint64_t known_coin_id,
  bool *not_found,
  bool *refund_ok,
  bool *gone,
  bool *conflict)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = compute_shard (&refund->details.merchant_pub);
  struct TALER_Amount amount_without_fee;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (&refund->details.refund_amount),
    TALER_PQ_query_param_amount (&amount_without_fee),
    TALER_PQ_query_param_amount (deposit_fee),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.h_contract_terms),
    GNUNET_PQ_query_param_uint64 (&refund->details.rtransaction_id),
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("not_found",
                                not_found),
    GNUNET_PQ_result_spec_bool ("refund_ok",
                                refund_ok),
    GNUNET_PQ_result_spec_bool ("gone",
                                gone),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_end
  };

  if (0 >
      TALER_amount_subtract (&amount_without_fee,
                             &refund->details.refund_amount,
                             &refund->details.refund_fee))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_refund",
                                                   params,
                                                   rs);
}


/**
 * Perform recoup operation, checking for sufficient deposits
 * of the coin and possibly persisting the recoup details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve to credit
 * @param reserve_out_serial_id row in the reserves_out table justifying the recoup
 * @param coin_bks coin blinding key secret to persist
 * @param coin_pub public key of the coin being recouped
 * @param known_coin_id row of the @a coin_pub in the known_coins table
 * @param coin_sig signature of the coin requesting the recoup
 * @param[in,out] recoup_timestamp recoup timestamp, set if recoup existed
 * @param[out] recoup_ok  set if the recoup succeeded (balance ok)
 * @param[out] internal_failure set on internal failures
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_recoup (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t reserve_out_serial_id,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t known_coin_id,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  struct GNUNET_TIME_Timestamp *recoup_timestamp,
  bool *recoup_ok,
  bool *internal_failure)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp reserve_gc
    = GNUNET_TIME_relative_to_timestamp (pg->legal_reserve_expiration_time);
  struct GNUNET_TIME_Timestamp reserve_expiration
    = GNUNET_TIME_relative_to_timestamp (pg->idle_reserve_expiration_time);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_uint64 (&reserve_out_serial_id),
    GNUNET_PQ_query_param_auto_from_type (coin_bks),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_timestamp (&reserve_gc),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    GNUNET_PQ_query_param_timestamp (recoup_timestamp),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       recoup_timestamp),
      &is_null),
    GNUNET_PQ_result_spec_bool ("recoup_ok",
                                recoup_ok),
    GNUNET_PQ_result_spec_bool ("internal_failure",
                                internal_failure),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_recoup",
                                                   params,
                                                   rs);
}


/**
 * Perform recoup-refresh operation, checking for sufficient deposits of the
 * coin and possibly persisting the recoup-refresh details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param old_coin_pub public key of the old coin to credit
 * @param rrc_serial row in the refresh_revealed_coins table justifying the recoup-refresh
 * @param coin_bks coin blinding key secret to persist
 * @param coin_pub public key of the coin being recouped
 * @param known_coin_id row of the @a coin_pub in the known_coins table
 * @param coin_sig signature of the coin requesting the recoup
 * @param[in,out] recoup_timestamp recoup timestamp, set if recoup existed
 * @param[out] recoup_ok  set if the recoup-refresh succeeded (balance ok)
 * @param[out] internal_failure set on internal failures
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_recoup_refresh (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  uint64_t rrc_serial,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t known_coin_id,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  struct GNUNET_TIME_Timestamp *recoup_timestamp,
  bool *recoup_ok,
  bool *internal_failure)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (old_coin_pub),
    GNUNET_PQ_query_param_uint64 (&rrc_serial),
    GNUNET_PQ_query_param_auto_from_type (coin_bks),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_uint64 (&known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    GNUNET_PQ_query_param_timestamp (recoup_timestamp),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       recoup_timestamp),
      &is_null),
    GNUNET_PQ_result_spec_bool ("recoup_ok",
                                recoup_ok),
    GNUNET_PQ_result_spec_bool ("internal_failure",
                                internal_failure),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_recoup_refresh",
                                                   params,
                                                   rs);
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
   * Sum of all credit transactions.
   */
  struct TALER_Amount balance_in;

  /**
   * Sum of all debit transactions.
   */
  struct TALER_Amount balance_out;

  /**
   * Set to #GNUNET_SYSERR on serious internal errors during
   * the callbacks.
   */
  enum GNUNET_GenericReturnValue status;
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
        GNUNET_PQ_result_spec_timestamp ("execution_date",
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
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_in,
                                     &rhc->balance_in,
                                     &bt->amount));
    bt->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE;
    tail->details.bank = bt;
  } /* end of 'while (0 < rows)' */
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
        TALER_PQ_result_spec_blinded_denom_sig ("denom_sig",
                                                &cbc->sig),
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
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &cbc->amount_with_fee));
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
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        TALER_PQ_result_spec_denom_sig (
          "denom_sig",
          &recoup->coin.denom_sig),
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
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_in,
                                     &rhc->balance_in,
                                     &recoup->value));
    recoup->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_RECOUP_COIN;
    tail->details.recoup = recoup;
  } /* end of 'while (0 < rows)' */
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
        GNUNET_PQ_result_spec_timestamp ("execution_date",
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
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &closing->amount));
    closing->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK;
    tail->details.closing = closing;
  } /* end of 'while (0 < rows)' */
}


/**
 * Get all of the transaction history associated with the specified
 * reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param[out] balance set to the reserve balance
 * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_history (void *cls,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              struct TALER_Amount *balance,
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
#ifndef GRID5K_MARCO_OPT
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup_by_reserve",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve",
      &add_exchange_to_bank },
#endif
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
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_out));
  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* make static analysis happy */
  for (unsigned int i = 0; NULL != work[i].cb; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  GNUNET_assert (0 <=
                 TALER_amount_subtract (balance,
                                        &rhc.balance_in,
                                        &rhc.balance_out));
  return qs;
}


/**
 * Get a truncated transaction history associated with the specified
 * reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param[out] balance set to the reserve balance
 * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_status (void *cls,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             struct TALER_Amount *balance,
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

  /* FIXME: actually implement reserve history truncation logic! */
  rhc.reserve_pub = reserve_pub;
  rhc.rh = NULL;
  rhc.rh_tail = NULL;
  rhc.pg = pg;
  rhc.status = GNUNET_OK;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_out));
  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* make static analysis happy */
  for (unsigned int i = 0; NULL != work[i].cb; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  GNUNET_assert (0 <=
                 TALER_amount_subtract (balance,
                                        &rhc.balance_in,
                                        &rhc.balance_out));
  return qs;
}


/**
 * Get the balance of the specified reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param[out] balance set to the reserve balance
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_balance (void *cls,
                              const struct TALER_ReservePublicKeyP *reserve_pub,
                              struct TALER_Amount *balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance",
                                 balance),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_reserve_balance",
                                                   params,
                                                   rs);
}


/**
 * Check if we have the specified deposit already in the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param h_contract_terms contract to check for
 * @param h_wire wire hash to check for
 * @param coin_pub public key of the coin to check for
 * @param merchant merchant public key to check for
 * @param refund_deadline expected refund deadline
 * @param[out] deposit_fee set to the deposit fee the exchange charged
 * @param[out] exchange_timestamp set to the time when the exchange received the deposit
 * @return 1 if we know this operation,
 *         0 if this exact deposit is unknown to us,
 *         otherwise transaction error status
 */
static enum GNUNET_DB_QueryStatus
postgres_have_deposit2 (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  struct GNUNET_TIME_Timestamp refund_deadline,
  struct TALER_Amount *deposit_fee,
  struct GNUNET_TIME_Timestamp *exchange_timestamp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (merchant),
    GNUNET_PQ_query_param_end
  };
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &deposit2.amount_with_fee),
    GNUNET_PQ_result_spec_timestamp ("wallet_timestamp",
                                     &deposit2.timestamp),
    GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                     exchange_timestamp),
    GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                     &deposit2.refund_deadline),
    GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                     &deposit2.wire_deadline),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 deposit_fee),
    GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                          &deposit2.wire_salt),
    GNUNET_PQ_result_spec_string ("receiver_wire_account",
                                  &deposit2.receiver_wire_account),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_MerchantWireHashP h_wire2;
#if EXPLICIT_LOCKS
  struct GNUNET_PQ_QueryParam no_params[] = {
    GNUNET_PQ_query_param_end
  };

  if (0 > (qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                    "lock_deposit",
                                                    no_params)))
    return qs;
#endif
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting deposits for coin %s\n",
              TALER_B2S (coin_pub));
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_deposit",
                                                 params,
                                                 rs);
  if (0 >= qs)
    return qs;
  TALER_merchant_wire_signature_hash (deposit2.receiver_wire_account,
                                      &deposit2.wire_salt,
                                      &h_wire2);
  GNUNET_free (deposit2.receiver_wire_account);
  /* Now we check that the other information in @a deposit
     also matches, and if not report inconsistencies. */
  if ( (GNUNET_TIME_timestamp_cmp (refund_deadline,
                                   !=,
                                   deposit2.refund_deadline)) ||
       (0 != GNUNET_memcmp (h_wire,
                            &h_wire2) ) )
  {
    /* Inconsistencies detected! Does not match!  (We might want to
       expand the API with a 'get_deposit' function to return the
       original transaction details to be used for an error message
       in the future!) FIXME #3838 */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Mark a deposit as tiny, thereby declaring that it cannot be
 * executed by itself and should no longer be returned by
 * @e iterate_ready_deposits()
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param merchant_pub identifies the beneficiary of the deposit
 * @param rowid identifies the deposit row to modify
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_deposit_tiny (void *cls,
                            const struct TALER_MerchantPublicKeyP *merchant_pub,
                            uint64_t rowid)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = compute_shard (merchant_pub);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "mark_deposit_tiny",
                                             params);
}


/**
 * Mark a deposit as done, thereby declaring that it cannot be
 * executed at all anymore, and should no longer be returned by
 * @e iterate_ready_deposits() or @e iterate_matching_deposits().
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param merchant_pub identifies the beneficiary of the deposit
 * @param rowid identifies the deposit row to modify
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_mark_deposit_done (void *cls,
                            const struct TALER_MerchantPublicKeyP *merchant_pub,
                            uint64_t rowid)
{
  struct PostgresClosure *pg = cls;
  uint64_t deposit_shard = compute_shard (merchant_pub);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_uint64 (&deposit_shard),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "mark_deposit_done",
                                             params);
}


/**
 * Obtain information about deposits that are ready to be executed.  Such
 * deposits must not be marked as "tiny" or "done", the execution time must be
 * in the past, and the KYC status must be 'ok'.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_shard_row minimum shard row to select
 * @param end_shard_row maximum shard row to select (inclusive)
 * @param kyc_off true if we should not check the KYC status because
 *                this exchange does not need/support KYC checks.
 * @param deposit_cb function to call for ONE such deposit
 * @param deposit_cb_cls closure for @a deposit_cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_ready_deposit (void *cls,
                            uint64_t start_shard_row,
                            uint64_t end_shard_row,
                            bool kyc_off,
                            TALER_EXCHANGEDB_DepositIterator deposit_cb,
                            void *deposit_cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_uint64 (&start_shard_row),
    GNUNET_PQ_query_param_uint64 (&end_shard_row),
    GNUNET_PQ_query_param_bool (kyc_off),
    GNUNET_PQ_query_param_end
  };
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount deposit_fee;
  struct TALER_PrivateContractHashP h_contract_terms;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  uint64_t serial_id;
  uint64_t wire_target;
  char *payto_uri;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                  &serial_id),
    GNUNET_PQ_result_spec_uint64 ("wire_target_serial_id",
                                  &wire_target),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &deposit_fee),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          &h_contract_terms),
    GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                          &merchant_pub),
    GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                          &coin_pub),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  &payto_uri),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  now = GNUNET_TIME_absolute_get ();
  GNUNET_assert (start_shard_row < end_shard_row);
  GNUNET_assert (end_shard_row <= INT32_MAX);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Finding ready deposits by deadline %s (%llu)\n",
              GNUNET_TIME_absolute2s (now),
              (unsigned long long) now.abs_value_us);

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "deposits_get_ready",
                                                 params,
                                                 rs);
  if (qs <= 0)
    return qs;

  qs = deposit_cb (deposit_cb_cls,
                   serial_id,
                   &merchant_pub,
                   &coin_pub,
                   &amount_with_fee,
                   &deposit_fee,
                   &h_contract_terms,
                   wire_target,
                   payto_uri);
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
  enum GNUNET_GenericReturnValue status;
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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Found %u/%u matching deposits\n",
              num_results,
              mdc->limit);
  num_results = GNUNET_MIN (num_results,
                            mdc->limit);
  for (mdc->i = 0; mdc->i<num_results; mdc->i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct TALER_PrivateContractHashP h_contract_terms;
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
 * @param h_payto destination of the wire transfer
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
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  TALER_EXCHANGEDB_MatchingDepositIterator deposit_cb,
  void *deposit_cb_cls,
  uint32_t limit)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  uint64_t shard = compute_shard (merchant_pub);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_uint64 (&shard),
    GNUNET_PQ_query_param_end
  };
  struct MatchingDepositContext mdc = {
    .deposit_cb = deposit_cb,
    .deposit_cb_cls = deposit_cb_cls,
    .merchant_pub = merchant_pub,
    .pg = pg,
    .limit = limit,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param coin_pub the public key of the coin to search for
 * @param coin_info place holder for the returned coin information object
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_known_coin (void *cls,
                         const struct TALER_CoinSpendPublicKeyP *coin_pub,
                         struct TALER_CoinPublicInfo *coin_info)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          &coin_info->denom_pub_hash),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &coin_info->h_age_commitment),
      &coin_info->no_age_commitment),
    TALER_PQ_result_spec_denom_sig ("denom_sig",
                                    &coin_info->denom_sig),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting known coin data for coin %s\n",
              TALER_B2S (coin_pub));
  coin_info->coin_pub = *coin_pub;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_known_coin",
                                                   params,
                                                   rs);
}


/**
 * Retrieve the denomination of a known coin.
 *
 * @param cls the plugin closure
 * @param coin_pub the public key of the coin to search for
 * @param[out] known_coin_id set to the ID of the coin in the known_coins table
 * @param[out] denom_hash where to store the hash of the coins denomination
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_coin_denomination (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  uint64_t *known_coin_id,
  struct TALER_DenominationHashP *denom_hash)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          denom_hash),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  known_coin_id),
    GNUNET_PQ_result_spec_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting coin denomination of coin %s\n",
              TALER_B2S (coin_pub));
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_coin_denomination",
                                                   params,
                                                   rs);
}


/**
 * Count the number of known coins by denomination.
 *
 * @param cls database connection plugin state
 * @param denom_pub_hash denomination to count by
 * @return number of coins if non-negative, otherwise an `enum GNUNET_DB_QueryStatus`
 */
static long long
postgres_count_known_coins (void *cls,
                            const struct
                            TALER_DenominationHashP *denom_pub_hash)
{
  struct PostgresClosure *pg = cls;
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

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
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
 * @param coin the coin that must be made known
 * @param[out] known_coin_id set to the unique row of the coin
 * @param[out] denom_hash set to the denomination hash of the existing
 *             coin (for conflict error reporting)
 * @param[out] h_age_commitment  set to the conflicting age commitment hash on conflict
 * @return database transaction status, non-negative on success
 */
static enum TALER_EXCHANGEDB_CoinKnownStatus
postgres_ensure_coin_known (void *cls,
                            const struct TALER_CoinPublicInfo *coin,
                            uint64_t *known_coin_id,
                            struct TALER_DenominationHashP *denom_hash,
                            struct TALER_AgeCommitmentHash *h_age_commitment)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool existed;
  bool is_denom_pub_hash_null = false;
  bool is_age_hash_null = false;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin->denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin->h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin->denom_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("existed",
                                &existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            denom_hash),
      &is_denom_pub_hash_null),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            h_age_commitment),
      &is_age_hash_null),
    GNUNET_PQ_result_spec_end
  };

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "insert_known_coin",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return TALER_EXCHANGEDB_CKS_SOFT_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0); /* should be impossible */
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    if (! existed)
      return TALER_EXCHANGEDB_CKS_ADDED;
    break; /* continued below */
  }

  if ( (! is_denom_pub_hash_null) &&
       (0 != GNUNET_memcmp (&denom_hash->hash,
                            &coin->denom_pub_hash.hash)) )
  {
    GNUNET_break_op (0);
    return TALER_EXCHANGEDB_CKS_DENOM_CONFLICT;
  }

  if ( (! is_age_hash_null) &&
       (0 != GNUNET_memcmp (h_age_commitment,
                            &coin->h_age_commitment)) )
  {
    GNUNET_break (GNUNET_is_zero (h_age_commitment));
    GNUNET_break_op (0);
    return TALER_EXCHANGEDB_CKS_AGE_CONFLICT;
  }

  return TALER_EXCHANGEDB_CKS_PRESENT;
}


/**
 * Insert information about deposited coin into the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param exchange_timestamp time the exchange received the deposit request
 * @param deposit deposit information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_deposit (void *cls,
                         struct GNUNET_TIME_Timestamp exchange_timestamp,
                         const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct PostgresClosure *pg = cls;
  struct TALER_EXCHANGEDB_KycStatus kyc;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_PaytoHashP h_payto;

  TALER_payto_hash (deposit->receiver_wire_account,
                    &h_payto);
  /* FIXME: inselect re-computes h_payto... */
  qs = inselect_account_kyc_status (pg,
                                    deposit->receiver_wire_account,
                                    &kyc);
  if (qs <= 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  {
    uint64_t shard = compute_shard (&deposit->merchant_pub);
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&deposit->coin.coin_pub),
      TALER_PQ_query_param_amount (&deposit->amount_with_fee),
      GNUNET_PQ_query_param_timestamp (&deposit->timestamp),
      GNUNET_PQ_query_param_timestamp (&deposit->refund_deadline),
      GNUNET_PQ_query_param_timestamp (&deposit->wire_deadline),
      GNUNET_PQ_query_param_auto_from_type (&deposit->merchant_pub),
      GNUNET_PQ_query_param_auto_from_type (&deposit->h_contract_terms),
      GNUNET_PQ_query_param_auto_from_type (&deposit->wire_salt),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_auto_from_type (&deposit->csig),
      GNUNET_PQ_query_param_timestamp (&exchange_timestamp),
      GNUNET_PQ_query_param_uint64 (&shard),
      GNUNET_PQ_query_param_end
    };

    GNUNET_assert (shard <= INT32_MAX);
    GNUNET_log (
      GNUNET_ERROR_TYPE_INFO,
      "Inserting deposit to be executed at %s (%llu/%llu)\n",
      GNUNET_TIME_timestamp2s (deposit->wire_deadline),
      (unsigned long long) deposit->wire_deadline.abs_time.abs_value_us,
      (unsigned long long) deposit->refund_deadline.abs_time.abs_value_us);
    return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "insert_deposit",
                                               params);
  }
}


/**
 * Insert information about refunded coin into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param refund refund information to store
 * @return query result status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_refund (void *cls,
                        const struct TALER_EXCHANGEDB_Refund *refund)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&refund->coin.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.merchant_sig),
    GNUNET_PQ_query_param_auto_from_type (&refund->details.h_contract_terms),
    GNUNET_PQ_query_param_uint64 (&refund->details.rtransaction_id),
    TALER_PQ_query_param_amount (&refund->details.refund_amount),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_YES ==
                 TALER_amount_cmp_currency (&refund->details.refund_amount,
                                            &refund->details.refund_fee));
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
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
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PrivateContractHashP *h_contract,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param rc commitment hash to use to locate the operation
 * @param[out] melt where to store the result; note that
 *             melt->session.coin.denom_sig will be set to NULL
 *             and is not fetched by this routine (as it is not needed by the client)
 * @param[out] melt_serial_id set to the row ID of @a rc in the refresh_commitments table
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_melt (void *cls,
                   const struct TALER_RefreshCommitmentP *rc,
                   struct TALER_EXCHANGEDB_Melt *melt,
                   uint64_t *melt_serial_id)
{
  struct PostgresClosure *pg = cls;
  bool h_age_commitment_is_null;
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
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &melt->session.coin.h_age_commitment),
      &h_age_commitment_is_null),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 &melt->session.amount_with_fee),
    GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                  melt_serial_id),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  memset (&melt->session.coin.denom_sig,
          0,
          sizeof (melt->session.coin.denom_sig));
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_melt",
                                                 params,
                                                 rs);
  if (h_age_commitment_is_null)
    memset (&melt->session.coin.h_age_commitment,
            0,
            sizeof(melt->session.coin.h_age_commitment));

  melt->session.rc = *rc;
  return qs;
}


/**
 * Store in the database which coin(s) the wallet wanted to create
 * in a given refresh operation and all of the other information
 * we learned or created in the /refresh/reveal step.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param melt_serial_id row ID of the commitment / melt operation in refresh_commitments
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
  uint64_t melt_serial_id,
  uint32_t num_rrcs,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
  unsigned int num_tprivs,
  const struct TALER_TransferPrivateKeyP *tprivs,
  const struct TALER_TransferPublicKeyP *tp)
{
  struct PostgresClosure *pg = cls;

  if (TALER_CNC_KAPPA != num_tprivs + 1)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  for (uint32_t i = 0; i<num_rrcs; i++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_uint64 (&melt_serial_id),
      GNUNET_PQ_query_param_uint32 (&i),
      GNUNET_PQ_query_param_auto_from_type (&rrc->orig_coin_link_sig),
      GNUNET_PQ_query_param_auto_from_type (&rrc->h_denom_pub),
      TALER_PQ_query_param_blinded_planchet (&rrc->blinded_planchet),
      TALER_PQ_query_param_exchange_withdraw_values (&rrc->exchange_vals),
      GNUNET_PQ_query_param_auto_from_type (&rrc->coin_envelope_hash),
      TALER_PQ_query_param_blinded_denom_sig (&rrc->coin_sig),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_refresh_revealed_coin",
                                             params);
    if (0 > qs)
      return qs;
  }

  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_uint64 (&melt_serial_id),
      GNUNET_PQ_query_param_auto_from_type (tp),
      GNUNET_PQ_query_param_fixed_size (
        tprivs,
        num_tprivs * sizeof (struct TALER_TransferPrivateKeyP)),
      GNUNET_PQ_query_param_end
    };

    return GNUNET_PQ_eval_prepared_non_select (pg->conn,
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
    uint32_t off;
    struct GNUNET_PQ_ResultSpec rso[] = {
      GNUNET_PQ_result_spec_uint32 ("freshcoin_index",
                                    &off),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rso,
                                  i))
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    if (off >= num_results)
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    {
      struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx->rrcs[off];
      struct GNUNET_PQ_ResultSpec rsi[] = {
        /* NOTE: freshcoin_index selected and discarded here... */
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &rrc->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                              &rrc->orig_coin_link_sig),
        GNUNET_PQ_result_spec_auto_from_type ("h_coin_ev",
                                              &rrc->coin_envelope_hash),
        TALER_PQ_result_spec_blinded_planchet ("coin_ev",
                                               &rrc->blinded_planchet),
        TALER_PQ_result_spec_exchange_withdraw_values ("ewv",
                                                       &rrc->exchange_vals),
        TALER_PQ_result_spec_blinded_denom_sig ("ev_sig",
                                                &rrc->coin_sig),
        GNUNET_PQ_result_spec_end
      };

      if (TALER_DENOMINATION_INVALID != rrc->blinded_planchet.cipher)
      {
        /* duplicate offset, not allowed */
        GNUNET_break (0);
        grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rsi,
                                    i))
      {
        GNUNET_break (0);
        grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
    }
  }
}


/**
 * Lookup in the database the coins that we want to
 * create in the given refresh operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param rc identify commitment and thus refresh operation
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_refresh_reveal (void *cls,
                             const struct TALER_RefreshCommitmentP *rc,
                             TALER_EXCHANGEDB_RefreshCallback cb,
                             void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GetRevealContext grctx;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };

  memset (&grctx,
          0,
          sizeof (grctx));
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  default: /* can have more than one result */
    break;
  }
  switch (grctx.qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT: /* should be impossible */
    break;
  }

  /* Pass result back to application */
  cb (cb_cls,
      grctx.rrcs_len,
      grctx.rrcs);
cleanup:
  for (unsigned int i = 0; i < grctx.rrcs_len; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx.rrcs[i];

    TALER_blinded_denom_sig_free (&rrc->coin_sig);
    TALER_blinded_planchet_free (&rrc->blinded_planchet);
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
    TALER_denom_pub_free (&ldl->denom_pub);
    TALER_blinded_denom_sig_free (&ldl->ev_sig);
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
      struct TALER_BlindedPlanchet bp;
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                              &transfer_pub),
        GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                              &pos->orig_coin_link_sig),
        TALER_PQ_result_spec_blinded_denom_sig ("ev_sig",
                                                &pos->ev_sig),
        GNUNET_PQ_result_spec_uint32 ("freshcoin_index",
                                      &pos->coin_refresh_offset),
        TALER_PQ_result_spec_exchange_withdraw_values ("ewv",
                                                       &pos->alg_values),
        TALER_PQ_result_spec_denom_pub ("denom_pub",
                                        &pos->denom_pub),
        TALER_PQ_result_spec_blinded_planchet ("coin_ev",
                                               &bp),
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
      if (TALER_DENOMINATION_CS == bp.cipher)
      {
        pos->nonce = bp.details.cs_blinded_planchet.nonce;
        pos->have_nonce = true;
      }
      TALER_blinded_planchet_free (&bp);
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
 * @param coin_pub public key of the coin
 * @param ldc function to call for each session the coin was melted into
 * @param ldc_cls closure for @a tdc
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_link_data (void *cls,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        TALER_EXCHANGEDB_LinkCallback ldc,
                        void *ldc_cls)
{
  struct PostgresClosure *pg = cls;
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
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &deposit->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                     &deposit->deposit_fee),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &deposit->h_denom_pub),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                                &deposit->h_age_commitment),
          &deposit->no_age_commitment),
        GNUNET_PQ_result_spec_timestamp ("wallet_timestamp",
                                         &deposit->timestamp),
        GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                         &deposit->refund_deadline),
        GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                         &deposit->wire_deadline),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &deposit->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &deposit->h_contract_terms),
        GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                              &deposit->wire_salt),
        GNUNET_PQ_result_spec_string ("payto_uri",
                                      &deposit->receiver_wire_account),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &deposit->csig),
        GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_auto_from_type ("done",
                                              &deposit->done),
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
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                                &melt->h_age_commitment),
          &melt->no_age_commitment),
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
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        TALER_PQ_result_spec_denom_sig ("denom_sig",
                                        &recoup->coin.denom_sig),
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
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
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
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        TALER_PQ_result_spec_denom_sig ("denom_sig",
                                        &recoup->coin.denom_sig),
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
 * @param coin_pub coin to investigate
 * @param include_recoup should recoup transactions be included in the @a tlp
 * @param[out] tlp set to list of transactions, NULL if coin is fresh
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_coin_transactions (
  void *cls,
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
    .pg = pg,
    .db_cls = cls
  };

  work = (GNUNET_YES == include_recoup) ? work_wp : work_op;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting transactions for coin %s\n",
              TALER_B2S (coin_pub));
  for (unsigned int i = 0; NULL != work[i].statement; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
    struct TALER_PrivateContractHashP h_contract_terms;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_PaytoHashP h_payto;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct GNUNET_TIME_Timestamp exec_time;
    struct TALER_Amount amount_with_fee;
    struct TALER_Amount deposit_fee;
    struct TALER_DenominationPublicKey denom_pub;
    char *payto_uri;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("aggregation_serial_id", &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &h_contract_terms),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      GNUNET_PQ_result_spec_auto_from_type ("wire_target_h_payto",
                                            &h_payto),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &merchant_pub),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &exec_time),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &deposit_fee),
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
             payto_uri,
             &h_payto,
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
 * @param wtid the raw wire transfer identifier we used
 * @param cb function to call on each transaction found
 * @param cb_cls closure for @a cb
 * @return query status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_transfer (
  void *cls,
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
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param h_contract_terms hash of the proposal data
 * @param h_wire hash of merchant wire details
 * @param coin_pub public key of deposited coin
 * @param merchant_pub merchant public key
 * @param[out] pending set to true if the transaction is still pending
 * @param[out] wtid wire transfer identifier, only set if @a pending is false
 * @param[out] exec_time when was the transaction done, or
 *         when we expect it to be done (if @a pending is false)
 * @param[out] amount_with_fee set to the total deposited amount
 * @param[out] deposit_fee set to how much the exchange did charge for the deposit
 * @param[out] kyc set to the kyc status of the receiver (if @a pending)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_transfer_by_deposit (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  bool *pending,
  struct TALER_WireTransferIdentifierRawP *wtid,
  struct GNUNET_TIME_Timestamp *exec_time,
  struct TALER_Amount *amount_with_fee,
  struct TALER_Amount *deposit_fee,
  struct TALER_EXCHANGEDB_KycStatus *kyc)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_end
  };
  char *payto_uri;
  struct TALER_WireSaltP wire_salt;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                          wtid),
    GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                          &wire_salt),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  &payto_uri),
    GNUNET_PQ_result_spec_timestamp ("execution_date",
                                     exec_time),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 amount_with_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 deposit_fee),
    GNUNET_PQ_result_spec_end
  };

  /* check if the aggregation record exists and get it */
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "lookup_deposit_wtid",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    struct TALER_MerchantWireHashP wh;

    TALER_merchant_wire_signature_hash (payto_uri,
                                        &wire_salt,
                                        &wh);
    GNUNET_PQ_cleanup_result (rs);
    if (0 ==
        GNUNET_memcmp (&wh,
                       h_wire))
    {
      *pending = false;
      memset (kyc,
              0,
              sizeof (*kyc));
      kyc->type = TALER_EXCHANGEDB_KYC_DEPOSIT;
      kyc->ok = true;
      return qs;
    }
    qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  if (0 > qs)
    return qs;
  *pending = true;
  memset (wtid,
          0,
          sizeof (*wtid));
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "lookup_deposit_wtid returned 0 matching rows\n");
  {
    /* Check if transaction exists in deposits, so that we just
       do not have a WTID yet. In that case, return without wtid
       (by setting 'pending' true). */
    struct GNUNET_PQ_ResultSpec rs2[] = {
      GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                            &wire_salt),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      GNUNET_PQ_result_spec_uint64 ("payment_target_uuid",
                                    &kyc->payment_target_uuid),
      GNUNET_PQ_result_spec_auto_from_type ("kyc_ok",
                                            &kyc->ok),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   amount_with_fee),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   deposit_fee),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       exec_time),
      GNUNET_PQ_result_spec_end
    };

    qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_deposit_without_wtid",
                                                   params,
                                                   rs2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    {
      struct TALER_MerchantWireHashP wh;

      TALER_merchant_wire_signature_hash (payto_uri,
                                          &wire_salt,
                                          &wh);
      GNUNET_PQ_cleanup_result (rs);
      if (0 !=
          GNUNET_memcmp (&wh,
                         h_wire))
        return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    kyc->type = TALER_EXCHANGEDB_KYC_DEPOSIT;
    return qs;
  }
}


/**
 * Function called to insert aggregation information into the DB.
 *
 * @param cls closure
 * @param wtid the raw wire transfer identifier we used
 * @param deposit_serial_id row in the deposits table for which this is aggregation data
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_aggregation_tracking (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  unsigned long long deposit_serial_id)
{
  struct PostgresClosure *pg = cls;
  uint64_t rid = deposit_serial_id;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rid),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_aggregation_tracking",
                                             params);
}


/**
 * Obtain wire fee from database.
 *
 * @param cls closure
 * @param type type of wire transfer the fee applies for
 * @param date for which date do we want the fee?
 * @param[out] start_date when does the fee go into effect
 * @param[out] end_date when does the fee end being valid
 * @param[out] fees how high are the wire fees
 * @param[out] master_sig signature over the above by the exchange master key
 * @return status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_get_wire_fee (void *cls,
                       const char *type,
                       struct GNUNET_TIME_Timestamp date,
                       struct GNUNET_TIME_Timestamp *start_date,
                       struct GNUNET_TIME_Timestamp *end_date,
                       struct TALER_WireFeeSet *fees,
                       struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("start_date",
                                     start_date),
    GNUNET_PQ_result_spec_timestamp ("end_date",
                                     end_date),
    TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                 &fees->wire),
    TALER_PQ_RESULT_SPEC_AMOUNT ("wad_fee",
                                 &fees->wad),
    TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                 &fees->closing),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_wire_fee",
                                                   params,
                                                   rs);
}


/**
 * Obtain global fees from database.
 *
 * @param cls closure
 * @param date for which date do we want the fee?
 * @param[out] start_date when does the fee go into effect
 * @param[out] end_date when does the fee end being valid
 * @param[out] fees how high are the wire fees
 * @param[out] purse_timeout set to how long we keep unmerged purses
 * @param[out] kyc_timeout set to how long we keep accounts without KYC
 * @param[out] history_expiration set to how long we keep account histories
 * @param[out] purse_account_limit set to the number of free purses per account
 * @param[out] master_sig signature over the above by the exchange master key
 * @return status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_get_global_fee (void *cls,
                         struct GNUNET_TIME_Timestamp date,
                         struct GNUNET_TIME_Timestamp *start_date,
                         struct GNUNET_TIME_Timestamp *end_date,
                         struct TALER_GlobalFeeSet *fees,
                         struct GNUNET_TIME_Relative *purse_timeout,
                         struct GNUNET_TIME_Relative *kyc_timeout,
                         struct GNUNET_TIME_Relative *history_expiration,
                         uint32_t *purse_account_limit,
                         struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("start_date",
                                     start_date),
    GNUNET_PQ_result_spec_timestamp ("end_date",
                                     end_date),
    TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                 &fees->history),
    TALER_PQ_RESULT_SPEC_AMOUNT ("kyc_fee",
                                 &fees->kyc),
    TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                 &fees->account),
    TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                 &fees->purse),
    GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                         purse_timeout),
    GNUNET_PQ_result_spec_relative_time ("kyc_timeout",
                                         kyc_timeout),
    GNUNET_PQ_result_spec_relative_time ("history_expiration",
                                         history_expiration),
    GNUNET_PQ_result_spec_uint32 ("purse_account_limit",
                                  purse_account_limit),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_global_fee",
                                                   params,
                                                   rs);
}


/**
 * Closure for #global_fees_cb().
 */
struct GlobalFeeContext
{
  /**
   * Function to call for each global fee block.
   */
  TALER_EXCHANGEDB_GlobalFeeCallback cb;

  /**
   * Closure to give to @e rec.
   */
  void *cb_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to #GNUNET_SYSERR on error.
   */
  enum GNUNET_GenericReturnValue status;
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
global_fees_cb (void *cls,
                PGresult *result,
                unsigned int num_results)
{
  struct GlobalFeeContext *gctx = cls;
  struct PostgresClosure *pg = gctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_GlobalFeeSet fees;
    struct GNUNET_TIME_Relative purse_timeout;
    struct GNUNET_TIME_Relative kyc_timeout;
    struct GNUNET_TIME_Relative history_expiration;
    uint32_t purse_account_limit;
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct TALER_MasterSignatureP master_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_timestamp ("start_date",
                                       &start_date),
      GNUNET_PQ_result_spec_timestamp ("end_date",
                                       &end_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                   &fees.history),
      TALER_PQ_RESULT_SPEC_AMOUNT ("kyc_fee",
                                   &fees.kyc),
      TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                   &fees.account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                   &fees.purse),
      GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                           &purse_timeout),
      GNUNET_PQ_result_spec_relative_time ("kyc_timeout",
                                           &kyc_timeout),
      GNUNET_PQ_result_spec_relative_time ("history_expiration",
                                           &history_expiration),
      GNUNET_PQ_result_spec_uint32 ("purse_account_limit",
                                    &purse_account_limit),
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
      gctx->status = GNUNET_SYSERR;
      break;
    }
    gctx->cb (gctx->cb_cls,
              &fees,
              purse_timeout,
              kyc_timeout,
              history_expiration,
              purse_account_limit,
              start_date,
              end_date,
              &master_sig);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Obtain global fees from database.
 *
 * @param cls closure
 * @param cb function to call on each fee entry
 * @param cb_cls closure for @a cb
 * @return status of the transaction
 */
static enum GNUNET_DB_QueryStatus
postgres_get_global_fees (void *cls,
                          TALER_EXCHANGEDB_GlobalFeeCallback cb,
                          void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp date
    = GNUNET_TIME_timestamp_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_end
  };
  struct GlobalFeeContext gctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "get_global_fees",
                                               params,
                                               &global_fees_cb,
                                               &gctx);
}


/**
 * Insert wire transfer fee into database.
 *
 * @param cls closure
 * @param type type of wire transfer this fee applies for
 * @param start_date when does the fee go into effect
 * @param end_date when does the fee end being valid
 * @param fees how high are the wire fees
 * @param master_sig signature over the above by the exchange master key
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire_fee (void *cls,
                          const char *type,
                          struct GNUNET_TIME_Timestamp start_date,
                          struct GNUNET_TIME_Timestamp end_date,
                          const struct TALER_WireFeeSet *fees,
                          const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    TALER_PQ_query_param_amount (&fees->wire),
    TALER_PQ_query_param_amount (&fees->closing),
    TALER_PQ_query_param_amount (&fees->wad),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
  struct TALER_WireFeeSet wx;
  struct TALER_MasterSignatureP sig;
  struct GNUNET_TIME_Timestamp sd;
  struct GNUNET_TIME_Timestamp ed;
  enum GNUNET_DB_QueryStatus qs;

  qs = postgres_get_wire_fee (pg,
                              type,
                              start_date,
                              &sd,
                              &ed,
                              &wx,
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
    if (0 !=
        TALER_wire_fee_set_cmp (fees,
                                &wx))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_TIME_timestamp_cmp (sd,
                                     !=,
                                     start_date)) ||
         (GNUNET_TIME_timestamp_cmp (ed,
                                     !=,
                                     end_date)) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* equal record already exists */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_wire_fee",
                                             params);
}


/**
 * Insert global fee data into database.
 *
 * @param cls closure
 * @param start_date when does the fee go into effect
 * @param fees how high is are the global fees
 * @param purse_timeout when do purses time out
 * @param kyc_timeout when do reserves without KYC time out
 * @param history_expiration how long are account histories preserved
 * @param purse_account_limit how many purses are free per account * @param master_sig signature over the above by the exchange master key
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_global_fee (void *cls,
                            struct GNUNET_TIME_Timestamp start_date,
                            struct GNUNET_TIME_Timestamp end_date,
                            const struct TALER_GlobalFeeSet *fees,
                            struct GNUNET_TIME_Relative purse_timeout,
                            struct GNUNET_TIME_Relative kyc_timeout,
                            struct GNUNET_TIME_Relative history_expiration,
                            uint32_t purse_account_limit,
                            const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    TALER_PQ_query_param_amount (&fees->history),
    TALER_PQ_query_param_amount (&fees->kyc),
    TALER_PQ_query_param_amount (&fees->account),
    TALER_PQ_query_param_amount (&fees->purse),
    GNUNET_PQ_query_param_relative_time (&purse_timeout),
    GNUNET_PQ_query_param_relative_time (&kyc_timeout),
    GNUNET_PQ_query_param_relative_time (&history_expiration),
    GNUNET_PQ_query_param_uint32 (&purse_account_limit),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };
  struct TALER_GlobalFeeSet wx;
  struct TALER_MasterSignatureP sig;
  struct GNUNET_TIME_Timestamp sd;
  struct GNUNET_TIME_Timestamp ed;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Relative pt;
  struct GNUNET_TIME_Relative kt;
  struct GNUNET_TIME_Relative he;
  uint32_t pal;

  qs = postgres_get_global_fee (pg,
                                start_date,
                                &sd,
                                &ed,
                                &wx,
                                &pt,
                                &kt,
                                &he,
                                &pal,
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
    if (0 !=
        TALER_global_fee_set_cmp (fees,
                                  &wx))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_TIME_timestamp_cmp (sd,
                                     !=,
                                     start_date)) ||
         (GNUNET_TIME_timestamp_cmp (ed,
                                     !=,
                                     end_date)) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_TIME_relative_cmp (purse_timeout,
                                    !=,
                                    pt)) ||
         (GNUNET_TIME_relative_cmp (kyc_timeout,
                                    !=,
                                    kt)) ||
         (GNUNET_TIME_relative_cmp (history_expiration,
                                    !=,
                                    he)) )
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (purse_account_limit != pal)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* equal record already exists */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_global_fee",
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
  enum GNUNET_GenericReturnValue status;
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
  enum GNUNET_GenericReturnValue ret;

  ret = GNUNET_OK;
  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_TIME_Timestamp exp_date;
    char *account_details;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_Amount remaining_balance;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_timestamp ("expiration_date",
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
 * @param now timestamp based on which we decide expiration
 * @param rec function to call on expired reserves
 * @param rec_cls closure for @a rec
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_expired_reserves (void *cls,
                               struct GNUNET_TIME_Timestamp now,
                               TALER_EXCHANGEDB_ReserveExpiredCallback rec,
                               void *rec_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct ExpiredReserveContext ectx = {
    .rec = rec,
    .rec_cls = rec_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct GNUNET_TIME_Timestamp execution_date,
  const char *receiver_account,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee)
{
  struct PostgresClosure *pg = cls;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct TALER_EXCHANGEDB_KycStatus kyc;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_PaytoHashP h_payto;

  TALER_payto_hash (receiver_account,
                    &h_payto);
  /* FIXME: inselect re-computes h_payto... */
  qs = inselect_account_kyc_status (pg,
                                    receiver_account,
                                    &kyc);
  if (qs <= 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      GNUNET_PQ_query_param_timestamp (&execution_date),
      GNUNET_PQ_query_param_auto_from_type (wtid),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      TALER_PQ_query_param_amount (amount_with_fee),
      TALER_PQ_query_param_amount (closing_fee),
      GNUNET_PQ_query_param_end
    };

    qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "reserves_close_insert",
                                             params);
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;

  /* update reserve balance */
  reserve.pub = *reserve_pub;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      (qs = reserves_get_internal (cls,
                                   &reserve)))
  {
    /* Existence should have been checked before we got here... */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    return qs;
  }
  {
    enum TALER_AmountArithmeticResult ret;

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
  }
  return reserves_update (cls,
                          &reserve);
}


/**
 * Function called to insert wire transfer commit data into the DB.
 *
 * @param cls closure
 * @param type type of the wire transfer (i.e. "iban")
 * @param buf buffer with wire transfer preparation data
 * @param buf_size number of bytes in @a buf
 * @return query status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_insert (void *cls,
                                   const char *type,
                                   const char *buf,
                                   size_t buf_size)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (type),
    GNUNET_PQ_query_param_fixed_size (buf, buf_size),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_prepare_data_insert",
                                             params);
}


/**
 * Function called to mark wire transfer commit data as finished.
 *
 * @param cls closure
 * @param rowid which entry to mark as finished
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_mark_finished (
  void *cls,
  uint64_t rowid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_prepare_data_mark_done",
                                             params);
}


/**
 * Function called to mark wire transfer commit data as failed.
 *
 * @param cls closure
 * @param rowid which entry to mark as failed
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_mark_failed (
  void *cls,
  uint64_t rowid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&rowid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "wire_prepare_data_mark_failed",
                                             params);
}


/**
 * Closure for #prewire_cb().
 */
struct PrewireContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_WirePreparationIterator cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * #GNUNET_OK if everything went fine.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Invoke the callback for each result.
 *
 * @param cls a `struct MissingWireContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
prewire_cb (void *cls,
            PGresult *result,
            unsigned int num_results)
{
  struct PrewireContext *pc = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    uint64_t prewire_uuid;
    char *wire_method;
    void *buf = NULL;
    size_t buf_size;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("prewire_uuid",
                                    &prewire_uuid),
      GNUNET_PQ_result_spec_string ("wire_method",
                                    &wire_method),
      GNUNET_PQ_result_spec_variable_size ("buf",
                                           &buf,
                                           &buf_size),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      pc->status = GNUNET_SYSERR;
      return;
    }
    pc->cb (pc->cb_cls,
            prewire_uuid,
            wire_method,
            buf,
            buf_size);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Function called to get an unfinished wire transfer
 * preparation data. Fetches at most one item.
 *
 * @param cls closure
 * @param start_row offset to query table at
 * @param limit maximum number of results to return
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_wire_prepare_data_get (void *cls,
                                uint64_t start_row,
                                uint64_t limit,
                                TALER_EXCHANGEDB_WirePreparationIterator cb,
                                void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&start_row),
    GNUNET_PQ_query_param_uint64 (&limit),
    GNUNET_PQ_query_param_end
  };
  struct PrewireContext pc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "wire_prepare_data_get",
                                             params,
                                             &prewire_cb,
                                             &pc);
  if (GNUNET_OK != pc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Starts a READ COMMITTED transaction where we transiently violate the foreign
 * constraints on the "wire_out" table as we insert aggregations
 * and only add the wire transfer out at the end.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
postgres_start_deferred_wire_out (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute (
      "START TRANSACTION ISOLATION LEVEL READ COMMITTED;"),
    GNUNET_PQ_make_execute ("SET CONSTRAINTS ALL DEFERRED;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  if (GNUNET_SYSERR ==
      postgres_preflight (pg))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR (
      "Failed to defer wire_out_ref constraint on transaction\n");
    GNUNET_break (0);
    postgres_rollback (pg);
    return GNUNET_SYSERR;
  }
  pg->transaction_name = "deferred wire out";
  return GNUNET_OK;
}


/**
 * Store information about an outgoing wire transfer that was executed.
 *
 * @param cls closure
 * @param date time of the wire transfer
 * @param wtid subject of the wire transfer
 * @param h_payto identifies the receiver account of the wire transfer
 * @param exchange_account_section configuration section of the exchange specifying the
 *        exchange's bank account being used
 * @param amount amount that was transmitted
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_store_wire_transfer_out (
  void *cls,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_PaytoHashP *h_payto,
  const char *exchange_account_section,
  const struct TALER_Amount *amount)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&date),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (exchange_account_section),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
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
static enum GNUNET_GenericReturnValue
postgres_gc (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = GNUNET_TIME_absolute_get ();
  struct GNUNET_TIME_Absolute long_ago;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&long_ago),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret;

  /* Keep wire fees for 10 years, that should always
     be enough _and_ they are tiny so it does not
     matter to make this tight */
  long_ago = GNUNET_TIME_absolute_subtract (
    now,
    GNUNET_TIME_relative_multiply (
      GNUNET_TIME_UNIT_YEARS,
      10));
  {
    struct GNUNET_PQ_PreparedStatement ps[] = {
      /* Used in #postgres_gc() */
      GNUNET_PQ_make_prepare ("run_gc",
                              "CALL"
                              " exchange_do_gc"
                              " ($1,$2);",
                              2),
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
  if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "run_gc",
                                              params))
    ret = GNUNET_SYSERR;
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
    struct GNUNET_TIME_Timestamp exchange_timestamp;
    struct TALER_DenominationPublicKey denom_pub;
    bool done;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &deposit.amount_with_fee),
      GNUNET_PQ_result_spec_timestamp ("wallet_timestamp",
                                       &deposit.timestamp),
      GNUNET_PQ_result_spec_timestamp ("exchange_timestamp",
                                       &exchange_timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &deposit.merchant_pub),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &deposit.coin.coin_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &deposit.coin.h_age_commitment),
        &deposit.coin.no_age_commitment),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &deposit.csig),
      GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                       &deposit.refund_deadline),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &deposit.wire_deadline),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &deposit.h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                            &deposit.wire_salt),
      GNUNET_PQ_result_spec_string ("receiver_wire_account",
                                    &deposit.receiver_wire_account),
      GNUNET_PQ_result_spec_bool ("done",
                                  &done),
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    int ret;

    memset (&deposit,
            0,
            sizeof (deposit));
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
                   &deposit,
                   &denom_pub,
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
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_deposits_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    struct TALER_AgeCommitmentHash h_age_commitment;
    bool ac_isnull;
    struct TALER_Amount amount_with_fee;
    uint32_t noreveal_index;
    uint64_t rowid;
    struct TALER_RefreshCommitmentP rc;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &h_age_commitment),
        &ac_isnull),
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
    enum GNUNET_GenericReturnValue ret;

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
                   ac_isnull ? NULL : &h_age_commitment,
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
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refreshes_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
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
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_refunds_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    struct GNUNET_TIME_Timestamp execution_date;
    uint64_t rowid;
    uint64_t wire_reference;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                    &wire_reference),
      TALER_PQ_RESULT_SPEC_AMOUNT ("credit",
                                   &credit),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &execution_date),
      GNUNET_PQ_result_spec_string ("sender_account_details",
                                    &sender_account_details),
      GNUNET_PQ_result_spec_uint64 ("reserve_in_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

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
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_in_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param account_name name of the account to select by
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserves_in_above_serial_id_by_account (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    struct TALER_BlindedCoinHashP h_blind_ev;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_TIME_Timestamp execution_date;
    struct TALER_Amount amount_with_fee;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &execution_date),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

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
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_withdrawals_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
    struct GNUNET_TIME_Timestamp date;
    struct TALER_WireTransferIdentifierRawP wtid;
    char *payto_uri;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("wireout_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
                                       &date),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &wtid),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
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
                    payto_uri,
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
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_wire_out_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param account_name account to select
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_wire_out_above_serial_id_by_account (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    union TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_Amount amount;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_BlindedCoinHashP h_blind_ev;
    struct GNUNET_TIME_Timestamp timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("recoup_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                       &timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin.coin_pub),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &coin_sig),
      GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                            &coin_blind),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &coin.h_age_commitment),
        &coin.no_age_commitment),
      TALER_PQ_result_spec_denom_sig ("denom_sig",
                                      &coin.denom_sig),
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
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_recoup_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    union TALER_DenominationBlindingKeyP coin_blind;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_DenominationHashP old_denom_pub_hash;
    struct TALER_Amount amount;
    struct TALER_BlindedCoinHashP h_blind_ev;
    struct GNUNET_TIME_Timestamp timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
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
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                            &h_blind_ev),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &coin.denom_pub_hash),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &coin.h_age_commitment),
        &coin.no_age_commitment),
      TALER_PQ_result_spec_denom_sig ("denom_sig",
                                      &coin.denom_sig),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

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
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_recoup_refresh_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    struct GNUNET_TIME_Timestamp execution_date;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("close_uuid",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_timestamp ("execution_date",
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
    enum GNUNET_GenericReturnValue ret;

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
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_reserve_closed_above_serial_id (
  void *cls,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "reserves_close_get_incr",
                                             params,
                                             &reserve_closed_serial_helper_cb,
                                             &rcsc);
  if (GNUNET_OK != rcsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Obtain information about which reserve a coin was generated
 * from given the hash of the blinded coin.
 *
 * @param cls closure
 * @param bch hash that uniquely identifies the withdraw request
 * @param[out] reserve_pub set to information about the reserve (on success only)
 * @param[out] reserve_out_serial_id set to row of the @a h_blind_ev in reserves_out
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_by_h_blind (
  void *cls,
  const struct TALER_BlindedCoinHashP *bch,
  struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *reserve_out_serial_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (bch),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          reserve_pub),
    GNUNET_PQ_result_spec_uint64 ("reserve_out_serial_id",
                                  reserve_out_serial_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "reserve_by_h_blind",
                                                   params,
                                                   rs);
}


/**
 * Obtain information about which old coin a coin was refreshed
 * given the hash of the blinded (fresh) coin.
 *
 * @param cls closure
 * @param h_blind_ev hash of the blinded coin
 * @param[out] old_coin_pub set to information about the old coin (on success only)
 * @param[out] rrc_serial set to serial number of the entry in the database
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_old_coin_by_h_blind (
  void *cls,
  const struct TALER_BlindedCoinHashP *h_blind_ev,
  struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  uint64_t *rrc_serial)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_blind_ev),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                          old_coin_pub),
    GNUNET_PQ_result_spec_uint64 ("rrc_serial",
                                  rrc_serial),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "old_coin_by_h_blind",
                                                   params,
                                                   rs);
}


/**
 * Store information that a denomination key was revoked
 * in the database.
 *
 * @param cls closure
 * @param denom_pub_hash hash of the revoked denomination key
 * @param master_sig signature affirming the revocation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_denomination_revocation (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "denomination_revocation_insert",
                                             params);
}


/**
 * Obtain information about a denomination key's revocation from
 * the database.
 *
 * @param cls closure
 * @param denom_pub_hash hash of the revoked denomination key
 * @param[out] master_sig signature affirming the revocation
 * @param[out] rowid row where the information is stored
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_denomination_revocation (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_MasterSignatureP *master_sig,
  uint64_t *rowid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (denom_pub_hash),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_uint64 ("denom_revocations_serial_id",
                                  rowid),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;
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
    char *payto_uri;
    struct GNUNET_TIME_Timestamp deadline;
    bool tiny;
    bool done;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                       &deadline),
      GNUNET_PQ_result_spec_bool ("tiny",
                                  &tiny),
      GNUNET_PQ_result_spec_bool ("done",
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
             payto_uri,
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
 * @param start_date lower bound on the requested wire execution date
 * @param end_date upper bound on the requested wire execution date
 * @param cb function to call on all such deposits
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_deposits_missing_wire (void *cls,
                                       struct GNUNET_TIME_Timestamp start_date,
                                       struct GNUNET_TIME_Timestamp end_date,
                                       TALER_EXCHANGEDB_WireMissingCallback cb,
                                       void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    GNUNET_PQ_query_param_end
  };
  struct MissingWireContext mwc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param auditor_pub key to look up information for
 * @param[out] last_date last modification date to auditor status
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_auditor_timestamp (
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp *last_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("last_change",
                                     last_date),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_auditor_timestamp",
                                                   params,
                                                   rs);
}


/**
 * Lookup current state of an auditor.
 *
 * @param cls closure
 * @param auditor_pub key to look up information for
 * @param[out] auditor_url set to the base URL of the auditor's REST API; memory to be
 *            released by the caller!
 * @param[out] enabled set if the auditor is currently in use
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_auditor_status (
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  char **auditor_url,
  bool *enabled)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("auditor_url",
                                  auditor_url),
    GNUNET_PQ_result_spec_bool ("is_active",
                                enabled),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_auditor_status",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an auditor that will audit this exchange.
 *
 * @param cls closure
 * @param auditor_pub key of the auditor
 * @param auditor_url base URL of the auditor's REST service
 * @param auditor_name name of the auditor (for humans)
 * @param start_date date when the auditor was added by the offline system
 *                      (only to be used for replay detection)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor (void *cls,
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                         struct GNUNET_TIME_Timestamp start_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_string (auditor_name),
    GNUNET_PQ_query_param_string (auditor_url),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_auditor",
                                             params);
}


/**
 * Update information about an auditor that will audit this exchange.
 *
 * @param cls closure
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
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                         struct GNUNET_TIME_Timestamp change_date,
                         bool enabled)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_string (auditor_url),
    GNUNET_PQ_query_param_string (auditor_name),
    GNUNET_PQ_query_param_bool (enabled),
    GNUNET_PQ_query_param_timestamp (&change_date),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "update_auditor",
                                             params);
}


/**
 * Check the last date an exchange wire account was modified.
 *
 * @param cls closure
 * @param payto_uri key to look up information for
 * @param[out] last_date last modification date to auditor status
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_timestamp (void *cls,
                                const char *payto_uri,
                                struct GNUNET_TIME_Timestamp *last_date)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("last_change",
                                     last_date),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_wire_timestamp",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an wire account used by this exchange.
 *
 * @param cls closure
 * @param payto_uri wire account of the exchange
 * @param start_date date when the account was added by the offline system
 *                      (only to be used for replay detection)
 * @param master_sig public signature affirming the existence of the account,
 *         must be of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_wire (void *cls,
                      const char *payto_uri,
                      struct GNUNET_TIME_Timestamp start_date,
                      const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_wire",
                                             params);
}


/**
 * Update information about a wire account of the exchange.
 *
 * @param cls closure
 * @param payto_uri account the update is about
 * @param change_date date when the account status was last changed
 *                      (only to be used for replay detection)
 * @param enabled true to enable, false to disable (the actual change)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_update_wire (void *cls,
                      const char *payto_uri,
                      struct GNUNET_TIME_Timestamp change_date,
                      bool enabled)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_bool (enabled),
    GNUNET_PQ_query_param_timestamp (&change_date),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;

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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
  enum GNUNET_GenericReturnValue status;

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
    struct TALER_WireFeeSet fees;
    struct GNUNET_TIME_Timestamp start_date;
    struct GNUNET_TIME_Timestamp end_date;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &fees.wire),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &fees.closing),
      TALER_PQ_RESULT_SPEC_AMOUNT ("wad_fee",
                                   &fees.wad),
      GNUNET_PQ_result_spec_timestamp ("start_date",
                                       &start_date),
      GNUNET_PQ_result_spec_timestamp ("end_date",
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
             &fees,
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

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
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
 * @param exchange_pub exchange online signing key that was revoked
 * @param master_sig signature affirming the revocation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_signkey_revocation (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_signkey_revocation",
                                             params);
}


/**
 * Obtain information about a revoked online signing key.
 *
 * @param cls closure
 * @param exchange_pub exchange online signing key
 * @param[out] master_sig set to signature affirming the revocation (if revoked)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_signkey_revocation (
  void *cls,
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

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_signkey_revocation",
                                                   params,
                                                   rs);
}


/**
 * Lookup information about current denomination key.
 *
 * @param cls closure
 * @param h_denom_pub hash of the denomination public key
 * @param[out] meta set to various meta data about the key
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_denomination_key (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("valid_from",
                                     &meta->start),
    GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                     &meta->expire_withdraw),
    GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                     &meta->expire_deposit),
    GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                     &meta->expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                 &meta->value),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &meta->fees.withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &meta->fees.deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &meta->fees.refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                 &meta->fees.refund),
    GNUNET_PQ_result_spec_uint32 ("age_mask",
                                  &meta->age_mask.bits),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_denomination_key",
                                                   params,
                                                   rs);
}


/**
 * Activate denomination key, turning it into a "current" or "valid"
 * denomination key by adding the master signature.
 *
 * @param cls closure
 * @param h_denom_pub hash of the denomination public key
 * @param denom_pub the actual denomination key
 * @param meta meta data about the denomination
 * @param master_sig master signature to add
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_add_denomination_key (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    TALER_PQ_query_param_denom_pub (denom_pub),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_timestamp (&meta->start),
    GNUNET_PQ_query_param_timestamp (&meta->expire_withdraw),
    GNUNET_PQ_query_param_timestamp (&meta->expire_deposit),
    GNUNET_PQ_query_param_timestamp (&meta->expire_legal),
    TALER_PQ_query_param_amount (&meta->value),
    TALER_PQ_query_param_amount (&meta->fees.withdraw),
    TALER_PQ_query_param_amount (&meta->fees.deposit),
    TALER_PQ_query_param_amount (&meta->fees.refresh),
    TALER_PQ_query_param_amount (&meta->fees.refund),
    GNUNET_PQ_query_param_uint32 (&meta->age_mask.bits),
    GNUNET_PQ_query_param_end
  };

  /* Sanity check: ensure fees match coin currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_denom_fee_check_currency (meta->value.currency,
                                                 &meta->fees));
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "denomination_insert",
                                             iparams);
}


/**
 * Add signing key.
 *
 * @param cls closure
 * @param exchange_pub the exchange online signing public key
 * @param meta meta data about @a exchange_pub
 * @param master_sig master signature to add
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_activate_signing_key (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_EXCHANGEDB_SignkeyMetaData *meta,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_timestamp (&meta->start),
    GNUNET_PQ_query_param_timestamp (&meta->expire_sign),
    GNUNET_PQ_query_param_timestamp (&meta->expire_legal),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_signkey",
                                             iparams);
}


/**
 * Lookup signing key meta data.
 *
 * @param cls closure
 * @param exchange_pub the exchange online signing public key
 * @param[out] meta meta data about @a exchange_pub
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_signing_key (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_EXCHANGEDB_SignkeyMetaData *meta)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("valid_from",
                                     &meta->start),
    GNUNET_PQ_result_spec_timestamp ("expire_sign",
                                     &meta->expire_sign),
    GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                     &meta->expire_legal),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_signing_key",
                                                   params,
                                                   rs);
}


/**
 * Insert information about an auditor auditing a denomination key.
 *
 * @param cls closure
 * @param h_denom_pub the audited denomination
 * @param auditor_pub the auditor's key
 * @param auditor_sig signature affirming the auditor's audit activity
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_auditor_denom_sig (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (auditor_pub),
    GNUNET_PQ_query_param_auto_from_type (h_denom_pub),
    GNUNET_PQ_query_param_auto_from_type (auditor_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_auditor_denom_sig",
                                             params);
}


/**
 * Select information about an auditor auditing a denomination key.
 *
 * @param cls closure
 * @param h_denom_pub the audited denomination
 * @param auditor_pub the auditor's key
 * @param[out] auditor_sig set to signature affirming the auditor's audit activity
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_auditor_denom_sig (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct TALER_AuditorSignatureP *auditor_sig)
{
  struct PostgresClosure *pg = cls;
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

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
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
   * Set to the wire fees. Set to invalid if fees conflict over
   * the given time period.
   */
  struct TALER_WireFeeSet *fees;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_lookup_wire_fee_by_time().
 * Calls the callback with the wire fee structure.
 *
 * @param cls a `struct WireFeeLookupContext`
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
    struct TALER_WireFeeSet fs;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("wire_fee",
                                   &fs.wire),
      TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                   &fs.closing),
      TALER_PQ_RESULT_SPEC_AMOUNT ("wad_fee",
                                   &fs.wad),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_WireFeeSet));
      return;
    }
    if (0 == i)
    {
      *wlc->fees = fs;
      continue;
    }
    if (0 !=
        TALER_wire_fee_set_cmp (&fs,
                                wlc->fees))
    {
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_WireFeeSet));
      return;
    }
  }
}


/**
 * Lookup information about known wire fees.  Finds all applicable
 * fees in the given range. If they are identical, returns the
 * respective @a fees. If any of the fees
 * differ between @a start_time and @a end_time, the transaction
 * succeeds BUT returns an invalid amount for both fees.
 *
 * @param cls closure
 * @param wire_method the wire method to lookup fees for
 * @param start_time starting time of fee
 * @param end_time end time of fee
 * @param[out] fees wire fees for that time period; if
 *             different fees exists within this time
 *             period, an 'invalid' amount is returned.
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_wire_fee_by_time (
  void *cls,
  const char *wire_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  struct TALER_WireFeeSet *fees)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (wire_method),
    GNUNET_PQ_query_param_timestamp (&start_time),
    GNUNET_PQ_query_param_timestamp (&end_time),
    GNUNET_PQ_query_param_end
  };
  struct WireFeeLookupContext wlc = {
    .fees = fees,
    .pg = pg
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "lookup_wire_fee_by_time",
                                               params,
                                               &wire_fee_by_time_helper,
                                               &wlc);
}


/**
 * Closure for #global_fee_by_time_helper()
 */
struct GlobalFeeLookupContext
{

  /**
   * Set to the wire fees. Set to invalid if fees conflict over
   * the given time period.
   */
  struct TALER_GlobalFeeSet *fees;

  /**
   * Set to timeout of unmerged purses
   */
  struct GNUNET_TIME_Relative *purse_timeout;

  /**
   * Set to timeout of accounts without kyc.
   */
  struct GNUNET_TIME_Relative *kyc_timeout;

  /**
   * Set to history expiration for reserves.
   */
  struct GNUNET_TIME_Relative *history_expiration;

  /**
   * Set to number of free purses per account.
   */
  uint32_t *purse_account_limit;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;
};


/**
 * Helper function for #postgres_lookup_global_fee_by_time().
 * Calls the callback with each denomination key.
 *
 * @param cls a `struct GlobalFeeLookupContext`
 * @param result db results
 * @param num_results number of results in @a result
 */
static void
global_fee_by_time_helper (void *cls,
                           PGresult *result,
                           unsigned int num_results)
{
  struct GlobalFeeLookupContext *wlc = cls;
  struct PostgresClosure *pg = wlc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_GlobalFeeSet fs;
    struct GNUNET_TIME_Relative purse_timeout;
    struct GNUNET_TIME_Relative kyc_timeout;
    struct GNUNET_TIME_Relative history_expiration;
    uint32_t purse_account_limit;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                   &fs.history),
      TALER_PQ_RESULT_SPEC_AMOUNT ("kyc_fee",
                                   &fs.kyc),
      TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                   &fs.account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                   &fs.purse),
      GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                           &purse_timeout),
      GNUNET_PQ_result_spec_relative_time ("kyc_timeout",
                                           &kyc_timeout),
      GNUNET_PQ_result_spec_relative_time ("history_expiration",
                                           &history_expiration),
      GNUNET_PQ_result_spec_uint32 ("purse_account_limit",
                                    &purse_account_limit),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_GlobalFeeSet));
      return;
    }
    if (0 == i)
    {
      *wlc->fees = fs;
      *wlc->purse_timeout = purse_timeout;
      *wlc->kyc_timeout = kyc_timeout;
      *wlc->history_expiration = history_expiration;
      *wlc->purse_account_limit = purse_account_limit;
      continue;
    }
    if ( (0 !=
          TALER_global_fee_set_cmp (&fs,
                                    wlc->fees)) ||
         (purse_account_limit != *wlc->purse_account_limit) ||
         (GNUNET_TIME_relative_cmp (purse_timeout,
                                    !=,
                                    *wlc->purse_timeout)) ||
         (GNUNET_TIME_relative_cmp (kyc_timeout,
                                    !=,
                                    *wlc->kyc_timeout)) ||
         (GNUNET_TIME_relative_cmp (history_expiration,
                                    !=,
                                    *wlc->history_expiration)) )
    {
      /* invalidate */
      memset (wlc->fees,
              0,
              sizeof (struct TALER_GlobalFeeSet));
      return;
    }
  }
}


/**
 * Lookup information about known global fees.
 *
 * @param cls closure
 * @param start_time starting time of fee
 * @param end_time end time of fee
 * @param[out] fees set to wire fees for that time period; if
 *             different global fee exists within this time
 *             period, an 'invalid' amount is returned.
 * @param[out] purse_timeout set to when unmerged purses expire
 * @param[out] kyc_timeout set to when reserves without kyc expire
 * @param[out] history_expiration set to when we expire reserve histories
 * @param[out] purse_account_limit set to number of free purses
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_global_fee_by_time (
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative *purse_timeout,
  struct GNUNET_TIME_Relative *kyc_timeout,
  struct GNUNET_TIME_Relative *history_expiration,
  uint32_t *purse_account_limit)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_time),
    GNUNET_PQ_query_param_timestamp (&end_time),
    GNUNET_PQ_query_param_end
  };
  struct GlobalFeeLookupContext wlc = {
    .fees = fees,
    .purse_timeout = purse_timeout,
    .kyc_timeout = kyc_timeout,
    .history_expiration = history_expiration,
    .purse_account_limit = purse_account_limit,
    .pg = pg
  };

  return GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "lookup_global_fee_by_time",
                                               params,
                                               &global_fee_by_time_helper,
                                               &wlc);
}


/**
 * Lookup the latest serial number of @a table.  Used in
 * exchange-auditor database replication.
 *
 * @param cls closure
 * @param table table for which we should return the serial
 * @param[out] serial latest serial number in use
 * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
 *         @a table does not have a serial number
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_serial_by_table (void *cls,
                                 enum TALER_EXCHANGEDB_ReplicatedTable table,
                                 uint64_t *serial)
{
  struct PostgresClosure *pg = cls;
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
  case TALER_EXCHANGEDB_RT_WIRE_TARGETS:
    statement = "select_serial_by_table_wire_targets";
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
  case TALER_EXCHANGEDB_RT_GLOBAL_FEE:
    statement = "select_serial_by_table_global_fee";
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    statement = "select_serial_by_table_recoup";
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    statement = "select_serial_by_table_recoup_refresh";
    break;
  case TALER_EXCHANGEDB_RT_EXTENSIONS:
    statement = "select_serial_by_table_extensions";
    break;
  case TALER_EXCHANGEDB_RT_EXTENSION_DETAILS:
    statement = "select_serial_by_table_extension_details";
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
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
 * @param table table for which we should return the serial
 * @param serial largest serial number to exclude
 * @param cb function to call on the records
 * @param cb_cls closure for @a cb
 * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
 *         @a table does not have a serial number
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_records_by_table (void *cls,
                                  enum TALER_EXCHANGEDB_ReplicatedTable table,
                                  uint64_t serial,
                                  TALER_EXCHANGEDB_ReplicationCallback cb,
                                  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial),
    GNUNET_PQ_query_param_end
  };
  struct LookupRecordsByTableContext ctx = {
    .pg = pg,
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
  case TALER_EXCHANGEDB_RT_WIRE_TARGETS:
    statement = "select_above_serial_by_table_wire_targets";
    rh = &lrbt_cb_table_wire_targets;
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
  case TALER_EXCHANGEDB_RT_GLOBAL_FEE:
    statement = "select_above_serial_by_table_global_fee";
    rh = &lrbt_cb_table_global_fee;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    statement = "select_above_serial_by_table_recoup";
    rh = &lrbt_cb_table_recoup;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    statement = "select_above_serial_by_table_recoup_refresh";
    rh = &lrbt_cb_table_recoup_refresh;
    break;
  case TALER_EXCHANGEDB_RT_EXTENSIONS:
    statement = "select_above_serial_by_table_extensions";
    rh = &lrbt_cb_table_extensions;
    break;
  case TALER_EXCHANGEDB_RT_EXTENSION_DETAILS:
    statement = "select_above_serial_by_table_extension_details";
    rh = &lrbt_cb_table_extension_details;
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             statement,
                                             params,
                                             rh,
                                             &ctx);
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to run `%s'\n",
                statement);
    return qs;
  }
  if (ctx.error)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * Signature of helper functions of #postgres_insert_records_by_table.
 *
 * @param pg plugin context
 * @param td record to insert
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*InsertRecordCallback)(struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td);


#include "irbt_callbacks.c"


/**
 * Insert record set into @a table.  Used in exchange-auditor database
 * replication.
 *
 * @param cls closure
 * @param td table data to insert
 * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
 *         @e table in @a tr is not supported
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_records_by_table (void *cls,
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
  case TALER_EXCHANGEDB_RT_WIRE_TARGETS:
    rh = &irbt_cb_table_wire_targets;
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
  case TALER_EXCHANGEDB_RT_GLOBAL_FEE:
    rh = &irbt_cb_table_global_fee;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    rh = &irbt_cb_table_recoup;
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    rh = &irbt_cb_table_recoup_refresh;
    break;
  case TALER_EXCHANGEDB_RT_EXTENSIONS:
    rh = &irbt_cb_table_extensions;
    break;
  case TALER_EXCHANGEDB_RT_EXTENSION_DETAILS:
    rh = &irbt_cb_table_extension_details;
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return rh (pg,
             td);
}


/**
 * Function called to grab a work shard on an operation @a op. Runs in its
 * own transaction.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to grab a word shard for
 * @param delay minimum age of a shard to grab
 * @param shard_size desired shard size
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
  struct PostgresClosure *pg = cls;

  for (unsigned int retries = 0; retries<3; retries++)
  {
    if (GNUNET_OK !=
        postgres_start (pg,
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
      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_open_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        {
          enum GNUNET_DB_QueryStatus qs;
          struct GNUNET_TIME_Timestamp now;
          struct GNUNET_PQ_QueryParam params[] = {
            GNUNET_PQ_query_param_string (job_name),
            GNUNET_PQ_query_param_timestamp (&now),
            GNUNET_PQ_query_param_uint64 (start_row),
            GNUNET_PQ_query_param_uint64 (end_row),
            GNUNET_PQ_query_param_end
          };

          now = GNUNET_TIME_timestamp_get ();
          qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                   "reclaim_shard",
                                                   params);
          switch (qs)
          {
          case GNUNET_DB_STATUS_HARD_ERROR:
            GNUNET_break (0);
            postgres_rollback (pg);
            return qs;
          case GNUNET_DB_STATUS_SOFT_ERROR:
            postgres_rollback (pg);
            continue;
          case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
            goto commit;
          case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
            GNUNET_break (0); /* logic error, should be impossible */
            postgres_rollback (pg);
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

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_last_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
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
      struct GNUNET_TIME_Timestamp now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_timestamp (&now),
        GNUNET_PQ_query_param_uint64 (start_row),
        GNUNET_PQ_query_param_uint64 (end_row),
        GNUNET_PQ_query_param_end
      };

      now = GNUNET_TIME_timestamp_get ();
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying to claim shard %llu-%llu\n",
                  (unsigned long long) *start_row,
                  (unsigned long long) *end_row);
      qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "claim_next_shard",
                                               params);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        /* continued below */
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* someone else got this shard already,
           try again */
        postgres_rollback (pg);
        continue;
      }
    } /* claim_next_shard */

    /* commit */
commit:
    {
      enum GNUNET_DB_QueryStatus qs;

      qs = postgres_commit (pg);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
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
 * @param job_name name of the operation to grab a word shard for
 * @param start_row inclusive start row of the shard
 * @param end_row exclusive end row of the shard
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_complete_shard (void *cls,
                         const char *job_name,
                         uint64_t start_row,
                         uint64_t end_row)
{
  struct PostgresClosure *pg = cls;

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (job_name),
    GNUNET_PQ_query_param_uint64 (&start_row),
    GNUNET_PQ_query_param_uint64 (&end_row),
    GNUNET_PQ_query_param_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Completing shard %llu-%llu\n",
              (unsigned long long) start_row,
              (unsigned long long) end_row);
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "complete_shard",
                                             params);
}


/**
 * Function called to grab a revolving work shard on an operation @a op. Runs
 * in its own transaction. Returns the oldest inactive shard.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to grab a revolving shard for
 * @param shard_size desired shard size
 * @param shard_limit exclusive end of the shard range
 * @param[out] start_row inclusive start row of the shard (returned)
 * @param[out] end_row inclusive end row of the shard (returned)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_begin_revolving_shard (void *cls,
                                const char *job_name,
                                uint32_t shard_size,
                                uint32_t shard_limit,
                                uint32_t *start_row,
                                uint32_t *end_row)
{
  struct PostgresClosure *pg = cls;

  GNUNET_assert (shard_limit <= 1U + (uint32_t) INT_MAX);
  GNUNET_assert (shard_limit > 0);
  GNUNET_assert (shard_size > 0);
  for (unsigned int retries = 0; retries<3; retries++)
  {
    if (GNUNET_OK !=
        postgres_start (pg,
                        "begin_revolving_shard"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    /* First, find last 'end_row' */
    {
      enum GNUNET_DB_QueryStatus qs;
      uint32_t last_end;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint32 ("end_row",
                                      &last_end),
        GNUNET_PQ_result_spec_end
      };

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_last_revolving_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        *start_row = 1U + last_end;
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        *start_row = 0; /* base-case: no shards yet */
        break; /* continued below */
      }
    } /* get_last_shard */

    if (*start_row < shard_limit)
    {
      /* Claim fresh shard */
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_TIME_Timestamp now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_timestamp (&now),
        GNUNET_PQ_query_param_uint32 (start_row),
        GNUNET_PQ_query_param_uint32 (end_row),
        GNUNET_PQ_query_param_end
      };

      *end_row = GNUNET_MIN (shard_limit,
                             *start_row + shard_size - 1);
      now = GNUNET_TIME_timestamp_get ();
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying to claim shard %llu-%llu\n",
                  (unsigned long long) *start_row,
                  (unsigned long long) *end_row);
      qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "create_revolving_shard",
                                               params);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        /* continued below (with commit) */
        break;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* someone else got this shard already,
           try again */
        postgres_rollback (pg);
        continue;
      }
    } /* end create fresh reovlving shard */
    else
    {
      /* claim oldest existing shard */
      enum GNUNET_DB_QueryStatus qs;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint32 ("start_row",
                                      start_row),
        GNUNET_PQ_result_spec_uint32 ("end_row",
                                      end_row),
        GNUNET_PQ_result_spec_end
      };

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "get_open_revolving_shard",
                                                     params,
                                                     rs);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
        continue;
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        /* no open shards available */
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
        {
          enum GNUNET_DB_QueryStatus qs;
          struct GNUNET_TIME_Timestamp now;
          struct GNUNET_PQ_QueryParam params[] = {
            GNUNET_PQ_query_param_string (job_name),
            GNUNET_PQ_query_param_timestamp (&now),
            GNUNET_PQ_query_param_uint32 (start_row),
            GNUNET_PQ_query_param_uint32 (end_row),
            GNUNET_PQ_query_param_end
          };

          now = GNUNET_TIME_timestamp_get ();
          qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                   "reclaim_revolving_shard",
                                                   params);
          switch (qs)
          {
          case GNUNET_DB_STATUS_HARD_ERROR:
            GNUNET_break (0);
            postgres_rollback (pg);
            return qs;
          case GNUNET_DB_STATUS_SOFT_ERROR:
            postgres_rollback (pg);
            continue;
          case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
            break; /* continue with commit */
          case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
            GNUNET_break (0); /* logic error, should be impossible */
            postgres_rollback (pg);
            return GNUNET_DB_STATUS_HARD_ERROR;
          }
        }
        break; /* continue with commit */
      }
    } /* end claim oldest existing shard */

    /* commit */
    {
      enum GNUNET_DB_QueryStatus qs;

      qs = postgres_commit (pg);
      switch (qs)
      {
      case GNUNET_DB_STATUS_HARD_ERROR:
        GNUNET_break (0);
        postgres_rollback (pg);
        return qs;
      case GNUNET_DB_STATUS_SOFT_ERROR:
        postgres_rollback (pg);
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
 * Function called to release a revolving shard
 * back into the work pool.  Clears the
 * "completed" flag.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to grab a word shard for
 * @param start_row inclusive start row of the shard
 * @param end_row exclusive end row of the shard
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_release_revolving_shard (void *cls,
                                  const char *job_name,
                                  uint32_t start_row,
                                  uint32_t end_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (job_name),
    GNUNET_PQ_query_param_uint32 (&start_row),
    GNUNET_PQ_query_param_uint32 (&end_row),
    GNUNET_PQ_query_param_end
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Releasing revolving shard %s %u-%u\n",
              job_name,
              (unsigned int) start_row,
              (unsigned int) end_row);
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "release_revolving_shard",
                                             params);
}


/**
 * Function called to delete all revolving shards.
 * To be used after a crash or when the shard size is
 * changed.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_delete_shard_locks (void *cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("DELETE FROM work_shards;"),
    GNUNET_PQ_make_execute ("DELETE FROM revolving_work_shards;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  return GNUNET_PQ_exec_statements (pg->conn,
                                    es);
}


/**
 * Function called to save the configuration of an extension
 * (age-restriction, peer2peer, ...).  After succesfull storage of the
 * configuration it triggers the corresponding event.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param extension_name the name of the extension
 * @param config JSON object of the configuration as string
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_set_extension_config (void *cls,
                               const char *extension_name,
                               const char *config)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam pcfg = (NULL == config || 0 == *config) ?
                                     GNUNET_PQ_query_param_null () :
                                     GNUNET_PQ_query_param_string (config);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (extension_name),
    pcfg,
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "set_extension_config",
                                             params);
}


/**
 * Function called to get the configuration of an extension
 * (age-restriction, peer2peer, ...)
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param extension_name the name of the extension
 * @param[out] config JSON object of the configuration as string
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
postgres_get_extension_config (void *cls,
                               const char *extension_name,
                               char **config)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (extension_name),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  *config = NULL;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("config", config),
      &is_null),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "get_extension_config",
                                                 params,
                                                 rs);
  return qs;
}


/**
 * Function called to store configuration data about a partner
 * exchange that we are federated with.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub public offline signing key of the partner exchange
 * @param start_date when does the following data start to be valid
 * @param end_date when does the validity end (exclusive)
 * @param wad_frequency how often do we do exchange-to-exchange settlements?
 * @param wad_fee how much do we charge for transfers to the partner
 * @param partner_base_url base URL of the partner exchange
 * @param master_sig signature with our offline signing key affirming the above
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_partner (void *cls,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct GNUNET_TIME_Timestamp start_date,
                         struct GNUNET_TIME_Timestamp end_date,
                         struct GNUNET_TIME_Relative wad_frequency,
                         const struct TALER_Amount *wad_fee,
                         const char *partner_base_url,
                         const struct TALER_MasterSignatureP *master_sig)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to persist an encrypted contract associated with a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub the purse the contract is associated with (must exist)
 * @param pub_ckey ephemeral key for DH used to encrypt the contract
 * @param econtract_size number of bytes in @a econtract
 * @param econtract the encrypted contract
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_contract (void *cls,
                          const struct TALER_PurseContractPublicKeyP *purse_pub,
                          const struct TALER_ContractDiffiePublicP *pub_ckey,
                          size_t econtract_size,
                          const void *econtract)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to retrieve an encrypted contract.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub key to lookup the contract by
 * @param[out] pub_ckey set to the ephemeral DH used to encrypt the contract
 * @param[out] econtract_size set to the number of bytes in @a econtract
 * @param[out] econtract set to the encrypted contract on success, to be freed by the caller
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_contract (void *cls,
                          const struct TALER_PurseContractPublicKeyP *purse_pub,
                          struct TALER_ContractDiffiePublicP *pub_ckey,
                          size_t *econtract_size,
                          void **econtract)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to create a new purse with certain meta data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the new purse
 * @param merge_pub public key providing the merge capability
 * @param purse_expiration time when the purse will expire
 * @param h_contract_terms hash of the contract for the purse
 * @param age_limit age limit to enforce for payments into the purse
 * @param amount target amount (with fees) to be put into the purse
 * @param purse_sig signature with @a purse_pub's private key affirming the above
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_purse_request (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t age_limit,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to reutrn meta data about a purse by the
 * purse public key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse
 * @param[out] merge_pub public key representing the merge capability
 * @param[out] purse_expiration when would an unmerged purse expire
 * @param[out] h_contract_terms contract associated with the purse
 * @param[out] target_amount amount to be put into the purse
 * @param[out] balance amount put so far into the purse
 * @param[out] purse_sig signature of the purse over the initialization data
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_request (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
  struct TALER_Amount *target_amount,
  struct TALER_Amount *balance,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to return meta data about a purse by the
 * merge capability key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param merge_pub public key representing the merge capability
 * @param[out] purse_pub public key of the purse
 * @param[out] purse_expiration when would an unmerged purse expire
 * @param[out] h_contract_terms contract associated with the purse
 * @param[out] target_amount amount to be put into the purse
 * @param[out] balance amount put so far into the purse
 * @param[out] purse_sig signature of the purse over the initialization data
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_by_merge_pub (
  void *cls,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
  struct TALER_Amount *target_amount,
  struct TALER_Amount *balance,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to execute a transaction crediting
 * a purse with @a amount from @a coin_pub. Reduces the
 * value of @a coin_pub and increase the balance of
 * the @a purse_pub purse. If the balance reaches the
 * target amount and the purse has been merged, triggers
 * the updates of the reserve/account balance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to credit
 * @param coin_pub coin to deposit (debit)
 * @param amount fraction of the coin's value to deposit
 * @param coin_sig signature affirming the operation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_do_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to approve merging a purse into a
 * reserve by the respective purse merge key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to merge
 * @param merge_sig signature affirming the merge
 * @param merge_timestamp time of the merge
 * @param partner_url URL of the partner exchange, can be NULL if the reserves lives with us
 * @param reserve_pub public key of the reserve to credit
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_do_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const char *partner_url,
  const struct TALER_ReservePublicKeyP *reserve_pub)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to approve merging of a purse with
 * an account, made by the receiving account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse
 * @param[out] merge_sig set to the signature confirming the merge
 * @param[out] merge_timestamp set to the time of the merge
 * @param[out] partner_url set to the URL of the target exchange, or NULL if the target exchange is us. To be freed by the caller.
 * @param[out] reserve_pub set to the public key of the reserve/account being credited
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_PurseMergeSignatureP *merge_sig,
  struct GNUNET_TIME_Timestamp *merge_timestamp,
  char **partner_url,
  struct TALER_ReservePublicKeyP *reserve_pub)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to approve merging of a purse with
 * an account, made by the receiving account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse being merged
 * @param reserve_pub public key of the account being credited
 * @param reserve_sig signature of the account holder affirming the merge
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_do_account_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to persist a signature that
 * prove that the client requested an
 * account history.  Debits the @a history_fee from
 * the reserve (if possible).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub account that the history was requested for
 * @param reserve_sig signature affirming the request
 * @param request_timestamp when was the request made
 * @param history_fee how much should the @a reserve_pub be charged for the request
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_history_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Absolute request_timestamp,
  const struct TALER_Amount *history)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
}


/**
 * Function called to initiate closure of an account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the account to close
 * @param reserve_sig signature affiming that the account is to be closed
 * @param[out] final_balance set to the final balance in the account that will be wired back to the origin account
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_close_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct TALER_Amount *final_balance)
{
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
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
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &pg->exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
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
    GNUNET_free (pg->exchange_url);
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &pg->currency))
  {
    GNUNET_free (pg->exchange_url);
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  if (GNUNET_OK !=
      internal_setup (pg,
                      true))
  {
    GNUNET_free (pg->exchange_url);
    GNUNET_free (pg->currency);
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }

  plugin = GNUNET_new (struct TALER_EXCHANGEDB_Plugin);
  plugin->cls = pg;
  plugin->drop_tables = &postgres_drop_tables;
  plugin->create_tables = &postgres_create_tables;
  plugin->setup_partitions = &postgres_setup_partitions;
  plugin->start = &postgres_start;
  plugin->start_read_committed = &postgres_start_read_committed;
  plugin->commit = &postgres_commit;
  plugin->preflight = &postgres_preflight;
  plugin->rollback = &postgres_rollback;
  plugin->event_listen = &postgres_event_listen;
  plugin->event_listen_cancel = &postgres_event_listen_cancel;
  plugin->event_notify = &postgres_event_notify;
  plugin->insert_denomination_info = &postgres_insert_denomination_info;
  plugin->get_denomination_info = &postgres_get_denomination_info;
  plugin->iterate_denomination_info = &postgres_iterate_denomination_info;
  plugin->iterate_denominations = &postgres_iterate_denominations;
  plugin->iterate_active_signkeys = &postgres_iterate_active_signkeys;
  plugin->iterate_active_auditors = &postgres_iterate_active_auditors;
  plugin->iterate_auditor_denominations =
    &postgres_iterate_auditor_denominations;
  plugin->select_kyc_status = &postgres_select_kyc_status;
  plugin->reserves_get = &postgres_reserves_get;
  plugin->set_kyc_ok = &postgres_set_kyc_ok;
  plugin->inselect_wallet_kyc_status = &postgres_inselect_wallet_kyc_status;
  plugin->reserves_in_insert = &postgres_reserves_in_insert;
  plugin->get_withdraw_info = &postgres_get_withdraw_info;
  plugin->do_withdraw = &postgres_do_withdraw;
  plugin->do_withdraw_limit_check = &postgres_do_withdraw_limit_check;
  plugin->do_deposit = &postgres_do_deposit;
  plugin->do_melt = &postgres_do_melt;
  plugin->do_refund = &postgres_do_refund;
  plugin->do_recoup = &postgres_do_recoup;
  plugin->do_recoup_refresh = &postgres_do_recoup_refresh;
  plugin->get_reserve_balance = &postgres_get_reserve_balance;
  plugin->get_reserve_history = &postgres_get_reserve_history;
  plugin->get_reserve_status = &postgres_get_reserve_status;
  plugin->free_reserve_history = &common_free_reserve_history;
  plugin->count_known_coins = &postgres_count_known_coins;
  plugin->ensure_coin_known = &postgres_ensure_coin_known;
  plugin->get_known_coin = &postgres_get_known_coin;
  plugin->get_coin_denomination = &postgres_get_coin_denomination;
  plugin->have_deposit2 = &postgres_have_deposit2;
  plugin->mark_deposit_tiny = &postgres_mark_deposit_tiny;
  plugin->mark_deposit_done = &postgres_mark_deposit_done;
  plugin->get_ready_deposit = &postgres_get_ready_deposit;
  plugin->iterate_matching_deposits = &postgres_iterate_matching_deposits;
  plugin->insert_deposit = &postgres_insert_deposit;
  plugin->insert_refund = &postgres_insert_refund;
  plugin->select_refunds_by_coin = &postgres_select_refunds_by_coin;
  plugin->get_melt = &postgres_get_melt;
  plugin->insert_refresh_reveal = &postgres_insert_refresh_reveal;
  plugin->get_refresh_reveal = &postgres_get_refresh_reveal;
  plugin->get_link_data = &postgres_get_link_data;
  plugin->get_coin_transactions = &postgres_get_coin_transactions;
  plugin->free_coin_transaction_list = &common_free_coin_transaction_list;
  plugin->lookup_wire_transfer = &postgres_lookup_wire_transfer;
  plugin->lookup_transfer_by_deposit = &postgres_lookup_transfer_by_deposit;
  plugin->insert_aggregation_tracking = &postgres_insert_aggregation_tracking;
  plugin->insert_wire_fee = &postgres_insert_wire_fee;
  plugin->insert_global_fee = &postgres_insert_global_fee;
  plugin->get_wire_fee = &postgres_get_wire_fee;
  plugin->get_global_fee = &postgres_get_global_fee;
  plugin->get_global_fees = &postgres_get_global_fees;
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
  plugin->lookup_global_fee_by_time
    = &postgres_lookup_global_fee_by_time;
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
  plugin->begin_revolving_shard
    = &postgres_begin_revolving_shard;
  plugin->release_revolving_shard
    = &postgres_release_revolving_shard;
  plugin->delete_shard_locks
    = &postgres_delete_shard_locks;
  plugin->set_extension_config
    = &postgres_set_extension_config;
  plugin->get_extension_config
    = &postgres_get_extension_config;
  plugin->insert_partner
    = &postgres_insert_partner;
  plugin->insert_contract
    = &postgres_insert_contract;
  plugin->select_contract
    = &postgres_select_contract;
  plugin->insert_purse_request
    = &postgres_insert_purse_request;
  plugin->select_purse_request
    = &postgres_select_purse_request;
  plugin->select_purse_by_merge_pub
    = &postgres_select_purse_by_merge_pub;
  plugin->do_purse_deposit
    = &postgres_do_purse_deposit;
  plugin->do_purse_merge
    = &postgres_do_purse_merge;
  plugin->select_purse_merge
    = &postgres_select_purse_merge;
  plugin->do_account_merge
    = &postgres_do_account_merge;
  plugin->insert_history_request
    = &postgres_insert_history_request;
  plugin->insert_close_request
    = &postgres_insert_close_request;
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

  if (NULL != pg->conn)
  {
    GNUNET_PQ_disconnect (pg->conn);
    pg->conn = NULL;
  }
  GNUNET_free (pg->exchange_url);
  GNUNET_free (pg->sql_dir);
  GNUNET_free (pg->currency);
  GNUNET_free (pg);
  GNUNET_free (plugin);
  return NULL;
}


/* end of plugin_exchangedb_postgres.c */
