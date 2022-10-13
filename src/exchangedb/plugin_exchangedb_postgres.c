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
#include "pg_helper.h"
#include "pg_do_reserve_open.h"
#include "pg_get_expired_reserves.h"
#include "pg_get_unfinished_close_requests.h"
#include "pg_insert_close_request.h"
#include "pg_insert_records_by_table.h"
#include "pg_insert_reserve_open_deposit.h"
#include "pg_iterate_kyc_reference.h"
#include "pg_iterate_reserve_close_info.h"
#include "pg_lookup_records_by_table.h"
#include "pg_lookup_serial_by_table.h"
#include "pg_select_reserve_close_info.h"
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
  enum GNUNET_GenericReturnValue ret;

  if (NULL != pg->conn)
  {
    GNUNET_PQ_disconnect (pg->conn);
    pg->conn = NULL;
    pg->init = false;
  }
  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     NULL,
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_sql (conn,
                            "drop");
  GNUNET_PQ_disconnect (conn);
  return ret;
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
  enum GNUNET_GenericReturnValue ret;

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     "exchange-",
                                     NULL,
                                     NULL);
  if (NULL == conn)
    return GNUNET_SYSERR;
  ret = GNUNET_PQ_exec_sql (conn,
                            "procedures");
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/**
 * Create tables of a shard node with index idx
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param idx the shards index, will be appended as suffix to all tables
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_create_shard_tables (void *cls,
                              uint32_t idx)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&idx),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("create_shard_tables",
                            "SELECT"
                            " setup_shard"
                            " ($1);"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     "shard-",
                                     es,
                                     ps);
  if (NULL == conn)
    return GNUNET_SYSERR;
  if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                              "create_shard_tables",
                                              params))
    ret = GNUNET_SYSERR;
  GNUNET_PQ_disconnect (conn);
  return ret;
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
                           uint32_t num)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&num),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("setup_partitions",
                            "SELECT"
                            " create_partitions"
                            " ($1);"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     NULL,
                                     es,
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
 * Setup foreign servers (shards) for already existing tables
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param num the number of foreign servers (shards) to create for each partitioned table
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static enum GNUNET_GenericReturnValue
postgres_setup_foreign_servers (void *cls,
                                uint32_t num)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_Context *conn;
  enum GNUNET_GenericReturnValue ret = GNUNET_OK;
  char *shard_domain = NULL;
  char *remote_user = NULL;
  char *remote_user_pw = NULL;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (pg->cfg,
                                             "exchange",
                                             "SHARD_DOMAIN",
                                             &shard_domain))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "SHARD_DOMAIN");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (pg->cfg,
                                             "exchangedb-postgres",
                                             "SHARD_REMOTE_USER",
                                             &remote_user))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb-postgres",
                               "SHARD_REMOTE_USER");
    GNUNET_free (shard_domain);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (pg->cfg,
                                             "exchangedb-postgres",
                                             "SHARD_REMOTE_USER_PW",
                                             &remote_user_pw))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb-postgres",
                               "SHARD_REMOTE_USER_PW");
    GNUNET_free (shard_domain);
    GNUNET_free (remote_user);
    return GNUNET_SYSERR;
  }

  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&num),
    GNUNET_PQ_query_param_string (shard_domain),
    GNUNET_PQ_query_param_string (remote_user),
    GNUNET_PQ_query_param_string (remote_user_pw),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("create_foreign_servers",
                            "SELECT"
                            " create_foreign_servers"
                            " ($1, $2, $3, $4);"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                     "exchangedb-postgres",
                                     NULL,
                                     es,
                                     ps);
  if (NULL == conn)
  {
    ret = GNUNET_SYSERR;
  }
  else if (0 > GNUNET_PQ_eval_prepared_non_select (conn,
                                                   "create_foreign_servers",
                                                   params))
  {
    ret = GNUNET_SYSERR;
  }
  GNUNET_free (shard_domain);
  GNUNET_free (remote_user);
  GNUNET_free (remote_user_pw);
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
      " $11, $12, $13, $14, $15, $16, $17, $18);"),
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
      " FROM denominations;"),
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
      "   denomination_revocations USING (denominations_serial);"),
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
      "    WHERE esk.esk_serial = skr.esk_serial);"),
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
      " WHERE auditors.is_active;"),
    /* Used in #postgres_iterate_active_auditors() */
    GNUNET_PQ_make_prepare (
      "select_auditors",
      "SELECT"
      " auditor_pub"
      ",auditor_url"
      ",auditor_name"
      " FROM auditors"
      " WHERE"
      "   is_active;"),
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
      " WHERE denom_pub_hash=$1;"),
    /* Used in #postgres_insert_denomination_revocation() */
    GNUNET_PQ_make_prepare (
      "denomination_revocation_insert",
      "INSERT INTO denomination_revocations "
      "(denominations_serial"
      ",master_sig"
      ") SELECT denominations_serial,$2"
      "    FROM denominations"
      "   WHERE denom_pub_hash=$1;"),
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
      "    WHERE denom_pub_hash=$1);"),
    /* Used in #postgres_reserves_get_origin() */
    GNUNET_PQ_make_prepare (
      "get_h_wire_source_of_reserve",
      "SELECT"
      " wire_source_h_payto"
      " FROM reserves_in"
      " WHERE reserve_pub=$1"),
    GNUNET_PQ_make_prepare (
      "get_kyc_h_payto",
      "SELECT"
      " wire_target_h_payto"
      " FROM wire_targets"
      " WHERE wire_target_h_payto=$1"
      " LIMIT 1;"),
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
      "  ($1, $2, $3, $4, $5, $6, $7, $8);"),
    /* Used in #setup_wire_target() */
    GNUNET_PQ_make_prepare (
      "insert_kyc_status",
      "INSERT INTO wire_targets"
      "  (wire_target_h_payto"
      "  ,payto_uri"
      "  ) VALUES "
      "  ($1, $2)"
      " ON CONFLICT DO NOTHING"),
    /* Used in #postgres_drain_kyc_alert() */
    GNUNET_PQ_make_prepare (
      "drain_kyc_alert",
      "DELETE FROM kyc_alerts"
      " WHERE trigger_type=$1"
      "   AND h_payto = "
      "   (SELECT h_payto "
      "      FROM kyc_alerts"
      "     WHERE trigger_type=$1"
      "     LIMIT 1)"
      " RETURNING h_payto;"),
    /* Used in #postgres_reserves_get() */
    GNUNET_PQ_make_prepare (
      "reserves_get",
      "SELECT"
      " current_balance_val"
      ",current_balance_frac"
      ",expiration_date"
      ",gc_date"
      " FROM reserves"
      " WHERE reserve_pub=$1"
      " LIMIT 1;"),
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
      " RETURNING reserve_uuid;"),
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
      ") VALUES ($1, $2, $3, $4, $5, $6, $7, $8);"),
    /* Used in #postgres_insert_drain_profit() */
    GNUNET_PQ_make_prepare (
      "drain_profit_insert",
      "INSERT INTO profit_drains "
      "(wtid"
      ",account_section"
      ",payto_uri"
      ",trigger_date"
      ",amount_val"
      ",amount_frac"
      ",master_sig"
      ") VALUES ($1, $2, $3, $4, $5, $6, $7);"),
    /* Used in #postgres_profit_drains_get_pending() */
    GNUNET_PQ_make_prepare (
      "get_ready_profit_drain",
      "SELECT"
      " profit_drain_serial_id"
      ",wtid"
      ",account_section"
      ",payto_uri"
      ",trigger_date"
      ",amount_val"
      ",amount_frac"
      ",master_sig"
      " FROM profit_drains"
      " WHERE NOT executed"
      " ORDER BY trigger_date ASC;"),
    /* Used in #postgres_profit_drains_get() */
    GNUNET_PQ_make_prepare (
      "get_profit_drain",
      "SELECT"
      " profit_drain_serial_id"
      ",account_section"
      ",payto_uri"
      ",trigger_date"
      ",amount_val"
      ",amount_frac"
      ",master_sig"
      " FROM profit_drains"
      " WHERE wtid=$1;"),
    /* Used in #postgres_profit_drains_set_finished() */
    GNUNET_PQ_make_prepare (
      "drain_profit_set_finished",
      "UPDATE profit_drains"
      " SET"
      " executed=TRUE"
      " WHERE profit_drain_serial_id=$1;"),
    /* Used in #postgres_reserves_update() when the reserve is updated */
    GNUNET_PQ_make_prepare (
      "reserve_update",
      "UPDATE reserves"
      " SET"
      " expiration_date=$1"
      ",gc_date=$2"
      ",current_balance_val=$3"
      ",current_balance_frac=$4"
      " WHERE reserve_pub=$5;"),
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
      " ON CONFLICT DO NOTHING;"),
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
      " ORDER BY reserve_in_serial_id;"),
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
      " ORDER BY reserve_in_serial_id;"),
    /* Used in #postgres_get_reserve_history() to obtain inbound transactions
       for a reserve */
    GNUNET_PQ_make_prepare (
      "reserves_in_get_transactions",
      /*
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
      */
      "WITH ri AS MATERIALIZED ( "
      "  SELECT * "
      "  FROM reserves_in "
      "  WHERE reserve_pub = $1 "
      ") "
      "SELECT  "
      "  wire_reference "
      "  ,credit_val "
      "  ,credit_frac "
      "  ,execution_date "
      "  ,payto_uri AS sender_account_details "
      "FROM wire_targets "
      "JOIN ri  "
      "  ON (wire_target_h_payto = wire_source_h_payto) "
      "WHERE wire_target_h_payto = ( "
      "  SELECT wire_source_h_payto FROM ri "
      "); "),
    /* Used in #postgres_get_reserve_status() to obtain inbound transactions
       for a reserve */
    GNUNET_PQ_make_prepare (
      "reserves_in_get_transactions_truncated",
      /*
      "SELECT"
      " wire_reference"
      ",credit_val"
      ",credit_frac"
      ",execution_date"
      ",payto_uri AS sender_account_details"
      " FROM reserves_in"
      " JOIN wire_targets"
      "   ON (wire_source_h_payto = wire_target_h_payto)"
      " WHERE reserve_pub=$1"
      "   AND execution_date>=$2;",
      */
      "WITH ri AS MATERIALIZED ( "
      "  SELECT * "
      "  FROM reserves_in "
      "  WHERE reserve_pub = $1 "
      ") "
      "SELECT  "
      "  wire_reference "
      "  ,credit_val "
      "  ,credit_frac "
      "  ,execution_date "
      "  ,payto_uri AS sender_account_details "
      "FROM wire_targets "
      "JOIN ri  "
      "  ON (wire_target_h_payto = wire_source_h_payto) "
      "WHERE execution_date >= $2"
      "  AND wire_target_h_payto = ( "
      "  SELECT wire_source_h_payto FROM ri "
      "); "),
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
      ",nonce_ok"
      ",ruuid"
      " FROM exchange_do_withdraw"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);"),
    /* Used in #postgres_do_batch_withdraw() to
       update the reserve balance and check its status */
    GNUNET_PQ_make_prepare (
      "call_batch_withdraw",
      "SELECT "
      " reserve_found"
      ",balance_ok"
      ",ruuid"
      " FROM exchange_do_batch_withdraw"
      " ($1,$2,$3,$4,$5);"),
    /* Used in #postgres_do_batch_withdraw_insert() to store
       the signature of a blinded coin with the blinded coin's
       details. */
    GNUNET_PQ_make_prepare (
      "call_batch_withdraw_insert",
      "SELECT "
      " out_denom_unknown AS denom_unknown"
      ",out_conflict AS conflict"
      ",out_nonce_reuse AS nonce_reuse"
      " FROM exchange_do_batch_withdraw_insert"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9);"),
    /* Used in #postgres_do_deposit() to execute a deposit,
       checking the coin's balance in the process as needed. */
    GNUNET_PQ_make_prepare (
      "call_deposit",
      "SELECT "
      " out_exchange_timestamp AS exchange_timestamp"
      ",out_balance_ok AS balance_ok"
      ",out_conflict AS conflicted"
      " FROM exchange_do_deposit"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17);"),
    /* used in postgres_do_purse_deposit() */
    GNUNET_PQ_make_prepare (
      "call_purse_deposit",
      "SELECT "
      " out_balance_ok AS balance_ok"
      ",out_conflict AS conflict"
      " FROM exchange_do_purse_deposit"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9);"),
    /* Used in #postgres_update_aggregation_transient() */
    GNUNET_PQ_make_prepare (
      "set_purse_balance",
      "UPDATE purse_requests"
      " SET balance_val=$2"
      "    ,balance_frac=$3"
      " WHERE purse_pub=$1;"),
    /* used in #postgres_expire_purse() */
    GNUNET_PQ_make_prepare (
      "call_expire_purse",
      "SELECT "
      " out_found AS found"
      " FROM exchange_do_expire_purse"
      " ($1,$2);"),
    /* Used in #postgres_do_melt() to melt a coin. */
    GNUNET_PQ_make_prepare (
      "call_melt",
      "SELECT "
      " out_balance_ok AS balance_ok"
      ",out_zombie_bad AS zombie_required"
      ",out_noreveal_index AS noreveal_index"
      " FROM exchange_do_melt"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9);"),
    /* Used in #postgres_do_refund() to refund a deposit. */
    GNUNET_PQ_make_prepare (
      "call_refund",
      "SELECT "
      " out_not_found AS not_found"
      ",out_refund_ok AS refund_ok"
      ",out_gone AS gone"
      ",out_conflict AS conflict"
      " FROM exchange_do_refund"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13);"),
    /* Used in #postgres_do_recoup() to recoup a coin to a reserve. */
    GNUNET_PQ_make_prepare (
      "call_recoup",
      "SELECT "
      " out_recoup_timestamp AS recoup_timestamp"
      ",out_recoup_ok AS recoup_ok"
      ",out_internal_failure AS internal_failure"
      " FROM exchange_do_recoup_to_reserve"
      " ($1,$2,$3,$4,$5,$6,$7,$8,$9);"),
    /* Used in #postgres_do_recoup_refresh() to recoup a coin to a zombie coin. */
    GNUNET_PQ_make_prepare (
      "call_recoup_refresh",
      "SELECT "
      " out_recoup_timestamp AS recoup_timestamp"
      ",out_recoup_ok AS recoup_ok"
      ",out_internal_failure AS internal_failure"
      " FROM exchange_do_recoup_to_coin"
      " ($1,$2,$3,$4,$5,$6,$7);"),
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
      " WHERE h_blind_ev=$1;"),
    /* Used during #postgres_get_reserve_history() to
       obtain all of the /reserve/withdraw operations that
       have been performed on a given reserve. (i.e. to
       demonstrate double-spending) */
    GNUNET_PQ_make_prepare (
      "get_reserves_out",
      /*
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
      */
      "WITH robr AS MATERIALIZED ( "
      "  SELECT h_blind_ev "
      "  FROM reserves_out_by_reserve "
      "  WHERE reserve_uuid= ( "
      "    SELECT reserve_uuid "
      "    FROM reserves "
      "    WHERE reserve_pub = $1 "
      "  ) "
      ") SELECT "
      "  ro.h_blind_ev "
      "  ,denom.denom_pub_hash "
      "  ,ro.denom_sig "
      "  ,ro.reserve_sig "
      "  ,ro.execution_date "
      "  ,ro.amount_with_fee_val "
      "  ,ro.amount_with_fee_frac "
      "  ,denom.fee_withdraw_val "
      "  ,denom.fee_withdraw_frac "
      "FROM robr "
      "JOIN reserves_out ro "
      "  ON (ro.h_blind_ev = robr.h_blind_ev) "
      "JOIN denominations denom "
      "  ON (ro.denominations_serial = denom.denominations_serial);"),
    /* Used during #postgres_get_reserve_status() to
       obtain all of the /reserve/withdraw operations that
       have been performed on a given reserve. (i.e. to
       demonstrate double-spending) */
    GNUNET_PQ_make_prepare (
      "get_reserves_out_truncated",
      /*
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
      " WHERE res.reserve_pub=$1"
      "   AND execution_date>=$2;",
      */
      "WITH robr AS MATERIALIZED ( "
      "  SELECT h_blind_ev "
      "  FROM reserves_out_by_reserve "
      "  WHERE reserve_uuid= ( "
      "    SELECT reserve_uuid "
      "    FROM reserves "
      "    WHERE reserve_pub = $1 "
      "  ) "
      ") SELECT "
      "  ro.h_blind_ev "
      "  ,denom.denom_pub_hash "
      "  ,ro.denom_sig "
      "  ,ro.reserve_sig "
      "  ,ro.execution_date "
      "  ,ro.amount_with_fee_val "
      "  ,ro.amount_with_fee_frac "
      "  ,denom.fee_withdraw_val "
      "  ,denom.fee_withdraw_frac "
      "FROM robr "
      "JOIN reserves_out ro "
      "  ON (ro.h_blind_ev = robr.h_blind_ev) "
      "JOIN denominations denom "
      "  ON (ro.denominations_serial = denom.denominations_serial)"
      " WHERE ro.execution_date>=$2;"),
    /* Used in #postgres_select_withdrawals_above_serial_id() */

    GNUNET_PQ_make_prepare (
      "get_reserve_balance",
      "SELECT"
      " current_balance_val"
      ",current_balance_frac"
      " FROM reserves"
      " WHERE reserve_pub=$1;"),
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
      " ORDER BY reserve_out_serial_id ASC;"),

    /* Used in #postgres_count_known_coins() */
    GNUNET_PQ_make_prepare (
      "count_known_coins",
      "SELECT"
      " COUNT(*) AS count"
      " FROM known_coins"
      " WHERE denominations_serial="
      "  (SELECT denominations_serial"
      "    FROM denominations"
      "    WHERE denom_pub_hash=$1);"),
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
      " WHERE coin_pub=$1;"),
    /* Used in #postgres_ensure_coin_known() */
    GNUNET_PQ_make_prepare (
      "get_known_coin_dh",
      "SELECT"
      " denominations.denom_pub_hash"
      " FROM known_coins"
      " JOIN denominations USING (denominations_serial)"
      " WHERE coin_pub=$1;"),
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
      " FOR SHARE;"),
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
      "  LIMIT 1"),

    /* Used in #postgres_get_melt() to fetch
       high-level information about a melt operation */
    GNUNET_PQ_make_prepare (
      "get_melt",
      /* "SELECT"
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
      " WHERE rc=$1;", */
      "WITH rc AS MATERIALIZED ( "
      " SELECT"
      "  * FROM refresh_commitments"
      " WHERE rc=$1"
      ")"
      "SELECT"
      " denoms.denom_pub_hash"
      ",denoms.fee_refresh_val"
      ",denoms.fee_refresh_frac"
      ",rc.old_coin_pub"
      ",rc.old_coin_sig"
      ",kc.age_commitment_hash"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",noreveal_index"
      ",melt_serial_id "
      "FROM ("
      " SELECT"
      "  * "
      " FROM known_coins"
      " WHERE coin_pub=(SELECT old_coin_pub from rc)"
      ") kc "
      "JOIN rc"
      "  ON (kc.coin_pub=rc.old_coin_pub) "
      "JOIN denominations denoms"
      "  USING (denominations_serial);"),
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
      " ORDER BY melt_serial_id ASC;"),
    /* Query the 'refresh_commitments' by coin public key,
       used in #postgres_get_coin_transactions() */
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
      " WHERE old_coin_pub=$1;"),
    /* Find purse deposits by coin,
       used in #postgres_get_coin_transactions() */
    GNUNET_PQ_make_prepare (
      "get_purse_deposit_by_coin_pub",
      "SELECT"
      " partner_base_url"
      ",pd.amount_with_fee_val"
      ",pd.amount_with_fee_frac"
      ",denoms.fee_deposit_val"
      ",denoms.fee_deposit_frac"
      ",pd.purse_pub"
      ",kc.age_commitment_hash"
      ",pd.coin_sig"
      ",pd.purse_deposit_serial_id"
      ",pr.refunded"
      " FROM purse_deposits pd"
      " LEFT JOIN partners"
      "   USING (partner_serial_id)"
      " JOIN purse_requests pr"
      "   USING (purse_pub)"
      " JOIN known_coins kc"
      "   ON (pd.coin_pub = kc.coin_pub)"
      " JOIN denominations denoms"
      "   USING (denominations_serial)"
      // FIXME: use to-be-created materialized index
      // on coin_pub (query crosses partitions!)
      " WHERE pd.coin_pub=$1;"),
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
      "   WHERE denom_pub_hash=$4"
      " ON CONFLICT DO NOTHING;"),
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
      " WHERE rc=$1;"),

    /* Used in #postgres_insert_refresh_reveal() to store the transfer
       keys we learned */
    GNUNET_PQ_make_prepare (
      "insert_refresh_transfer_keys",
      "INSERT INTO refresh_transfer_keys "
      "(melt_serial_id"
      ",transfer_pub"
      ",transfer_privs"
      ") VALUES ($1, $2, $3)"
      " ON CONFLICT DO NOTHING;"),
    /* Used in #postgres_insert_refund() to store refund information */
    GNUNET_PQ_make_prepare (
      "insert_refund",
      "INSERT INTO refunds "
      "(coin_pub "
      ",deposit_serial_id"
      ",merchant_sig "
      ",rtransaction_id "
      ",amount_with_fee_val "
      ",amount_with_fee_frac "
      ") SELECT $1, deposit_serial_id, $3, $5, $6, $7"
      "    FROM deposits"
      "   WHERE coin_pub=$1"
      "     AND h_contract_terms=$4"
      "     AND merchant_pub=$2"),
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
      " FROM refunds ref"
      " JOIN deposits dep"
      "   ON (ref.coin_pub = dep.coin_pub AND ref.deposit_serial_id = dep.deposit_serial_id)"
      " JOIN known_coins kc"
      "   ON (ref.coin_pub = kc.coin_pub)"
      " JOIN denominations denom"
      "   USING (denominations_serial)"
      " WHERE ref.coin_pub=$1;"),
    /* Query the 'refunds' by coin public key, merchant_pub and contract hash */
    GNUNET_PQ_make_prepare (
      "get_refunds_by_coin_and_contract",
      "SELECT"
      " ref.amount_with_fee_val"
      ",ref.amount_with_fee_frac"
      " FROM refunds ref"
      " JOIN deposits dep"
      "   USING (coin_pub,deposit_serial_id)"
      " WHERE ref.coin_pub=$1"
      "   AND dep.merchant_pub=$2"
      "   AND dep.h_contract_terms=$3;"),
    /* Fetch refunds with rowid '\geq' the given parameter */
    GNUNET_PQ_make_prepare (
      "audit_get_refunds_incr",
      "SELECT"
      " dep.merchant_pub"
      ",ref.merchant_sig"
      ",dep.h_contract_terms"
      ",ref.rtransaction_id"
      ",denom.denom_pub"
      ",kc.coin_pub"
      ",ref.amount_with_fee_val"
      ",ref.amount_with_fee_frac"
      ",ref.refund_serial_id"
      " FROM refunds ref"
      "   JOIN deposits dep"
      "     ON (ref.coin_pub=dep.coin_pub AND ref.deposit_serial_id=dep.deposit_serial_id)"
      "   JOIN known_coins kc"
      "     ON (dep.coin_pub=kc.coin_pub)"
      "   JOIN denominations denom"
      "     ON (kc.denominations_serial=denom.denominations_serial)"
      " WHERE ref.refund_serial_id>=$1"
      " ORDER BY ref.refund_serial_id ASC;"),
    GNUNET_PQ_make_prepare (
      "test_refund_full",
      "SELECT"
      " CAST(SUM(CAST(ref.amount_with_fee_frac AS INT8)) AS INT8) AS s_f"
      ",CAST(SUM(ref.amount_with_fee_val) AS INT8) AS s_v"
      ",dep.amount_with_fee_val"
      ",dep.amount_with_fee_frac"
      " FROM refunds ref"
      "   JOIN deposits dep"
      "     ON (ref.coin_pub=dep.coin_pub AND ref.deposit_serial_id=dep.deposit_serial_id)"
      " WHERE ref.refund_serial_id=$1"
      " GROUP BY (dep.amount_with_fee_val, dep.amount_with_fee_frac);"),

    /* Store information about a /deposit the exchange is to execute.
       Used in #postgres_insert_deposit().  Only used in test cases. */
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
      "   WHERE coin_pub=$1"
      " ON CONFLICT DO NOTHING;"),
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
      " FROM deposits dep"
      " JOIN known_coins kc ON (kc.coin_pub = dep.coin_pub)"
      " JOIN denominations USING (denominations_serial)"
      " JOIN wire_targets wt USING (wire_target_h_payto)"
      " WHERE dep.coin_pub=$1"
      "   AND dep.merchant_pub=$3"
      "   AND dep.h_contract_terms=$2;"),
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
      "  (deposit_serial_id>=$1)"
      " )"
      " ORDER BY deposit_serial_id ASC;"),
    /* Fetch purse deposits with rowid '\geq' the given parameter */
    GNUNET_PQ_make_prepare (
      "audit_get_purse_deposits_incr",
      "SELECT"
      " pd.amount_with_fee_val"
      ",pd.amount_with_fee_frac"
      ",pr.amount_with_fee_val AS total_val"
      ",pr.amount_with_fee_frac AS total_frac"
      ",pr.balance_val"
      ",pr.balance_frac"
      ",pr.flags"
      ",pd.purse_pub"
      ",pd.coin_sig"
      ",partner_base_url"
      ",denom.denom_pub"
      ",pm.reserve_pub"
      ",kc.coin_pub"
      ",kc.age_commitment_hash"
      ",pd.purse_deposit_serial_id"
      " FROM purse_deposits pd"
      " LEFT JOIN partners USING (partner_serial_id)"
      " LEFT JOIN purse_merges pm USING (purse_pub)"
      " JOIN purse_requests pr USING (purse_pub)"
      " JOIN known_coins kc USING (coin_pub)"
      " JOIN denominations denom USING (denominations_serial)"
      " WHERE ("
      "  (purse_deposit_serial_id>=$1)"
      " )"
      " ORDER BY purse_deposit_serial_id ASC;"),

    GNUNET_PQ_make_prepare (
      "audit_get_account_merge_incr",
      "SELECT"
      " am.account_merge_request_serial_id"
      ",am.reserve_pub"
      ",am.purse_pub"
      ",pr.h_contract_terms"
      ",pr.purse_expiration"
      ",pr.amount_with_fee_val"
      ",pr.amount_with_fee_frac"
      ",pr.age_limit"
      ",pr.flags"
      ",pr.purse_fee_val"
      ",pr.purse_fee_frac"
      ",pm.merge_timestamp"
      ",am.reserve_sig"
      " FROM account_merges am"
      " JOIN purse_requests pr USING (purse_pub)"
      " JOIN purse_merges pm USING (purse_pub)"
      " WHERE ("
      "  (account_merge_request_serial_id>=$1)"
      " )"
      " ORDER BY account_merge_request_serial_id ASC;"),

    GNUNET_PQ_make_prepare (
      "audit_get_purse_merge_incr",
      "SELECT"
      " pm.purse_merge_request_serial_id"
      ",partner_base_url"
      ",pr.amount_with_fee_val"
      ",pr.amount_with_fee_frac"
      ",pr.balance_val"
      ",pr.balance_frac"
      ",pr.flags"
      ",pr.merge_pub"
      ",pm.reserve_pub"
      ",pm.merge_sig"
      ",pm.purse_pub"
      ",pm.merge_timestamp"
      " FROM purse_merges pm"
      " JOIN purse_requests pr USING (purse_pub)"
      " LEFT JOIN partners USING (partner_serial_id)"
      " WHERE ("
      "  (purse_merge_request_serial_id>=$1)"
      " )"
      " ORDER BY purse_merge_request_serial_id ASC;"),

    GNUNET_PQ_make_prepare (
      "audit_get_history_requests_incr",
      "SELECT"
      " history_request_serial_id"
      ",history_fee_val"
      ",history_fee_frac"
      ",request_timestamp"
      ",reserve_pub"
      ",reserve_sig"
      " FROM history_requests"
      " WHERE ("
      "  (history_request_serial_id>=$1)"
      " )"
      " ORDER BY history_request_serial_id ASC;"),

    GNUNET_PQ_make_prepare (
      "audit_get_purse_deposits_by_purse",
      "SELECT"
      " pd.purse_deposit_serial_id"
      ",pd.amount_with_fee_val"
      ",pd.amount_with_fee_frac"
      ",pd.coin_pub"
      ",denom.denom_pub"
      " FROM purse_deposits pd"
      " JOIN known_coins kc USING (coin_pub)"
      " JOIN denominations denom USING (denominations_serial)"
      " WHERE purse_pub=$1;"),
    GNUNET_PQ_make_prepare (
      "audit_get_purse_refunds_incr",
      "SELECT"
      " purse_pub"
      ",purse_refunds_serial_id"
      " FROM purse_refunds"
      " WHERE ("
      "  (purse_refunds_serial_id>=$1)"
      " )"
      " ORDER BY purse_refunds_serial_id ASC;"),
    /* Fetch an existing deposit request.
       Used in #postgres_lookup_transfer_by_deposit(). */
    GNUNET_PQ_make_prepare (
      "get_deposit_without_wtid",
      "SELECT"
      " agt.legitimization_requirement_serial_id"
      ",dep.wire_salt"
      ",wt.payto_uri"
      ",dep.amount_with_fee_val"
      ",dep.amount_with_fee_frac"
      ",denom.fee_deposit_val"
      ",denom.fee_deposit_frac"
      ",dep.wire_deadline"
      " FROM deposits dep"
      " JOIN wire_targets wt"
      "   USING (wire_target_h_payto)"
      " JOIN known_coins kc"
      "   ON (kc.coin_pub = dep.coin_pub)"
      " JOIN denominations denom"
      "   USING (denominations_serial)"
      " LEFT JOIN aggregation_transient agt "
      "   ON ( (dep.wire_target_h_payto = agt.wire_target_h_payto) AND"
      "        (dep.merchant_pub = agt.merchant_pub) )"
      " WHERE dep.coin_pub=$1"
      "   AND dep.merchant_pub=$3"
      "   AND dep.h_contract_terms=$2"
      " LIMIT 1;"),
    /* Used in #postgres_get_ready_deposit() */
    GNUNET_PQ_make_prepare (
      "deposits_get_ready",
      "SELECT"
      " payto_uri"
      ",merchant_pub"
      " FROM deposits_by_ready dbr"
      "  JOIN deposits dep"
      "    ON (dbr.coin_pub = dep.coin_pub AND"
      "        dbr.deposit_serial_id = dep.deposit_serial_id)"
      "  JOIN wire_targets wt"
      "    USING (wire_target_h_payto)"
      " WHERE dbr.wire_deadline<=$1"
      "   AND dbr.shard >= $2"
      "   AND dbr.shard <= $3"
      " ORDER BY "
      "   dbr.wire_deadline ASC"
      "  ,dbr.shard ASC"
      " LIMIT 1;"),
    /* Used in #postgres_aggregate() */
    GNUNET_PQ_make_prepare (
      "aggregate",
      "WITH rdy AS (" /* find deposits ready by merchant */
      "  SELECT"
      "    coin_pub"
      "    FROM deposits_for_matching"
      "    WHERE refund_deadline<$1" /* filter by shard, only actually executable deposits */
      "      AND merchant_pub=$2" /* filter by target merchant */
      "    ORDER BY refund_deadline ASC" /* ordering is not critical */
      "    LIMIT "
      TALER_QUOTE (TALER_EXCHANGEDB_MATCHING_DEPOSITS_LIMIT) /* limits transaction size */
      " )"
      " ,dep AS (" /* restrict to our merchant and account and mark as done */
      "  UPDATE deposits"
      "     SET done=TRUE"
      "   WHERE coin_pub IN (SELECT coin_pub FROM rdy)"
      "     AND merchant_pub=$2" /* theoretically, same coin could be spent at another merchant */
      "     AND wire_target_h_payto=$3" /* merchant could have a 2nd bank account */
      "     AND done=FALSE" /* theoretically, same coin could be spend at the same merchant a 2nd time */
      "   RETURNING"
      "     deposit_serial_id"
      "    ,coin_pub"
      "    ,amount_with_fee_val AS amount_val"
      "    ,amount_with_fee_frac AS amount_frac)"
      " ,ref AS (" /* find applicable refunds -- NOTE: may do a full join on the master, maybe find a left-join way to integrate with query above to push it to the shards? */
      "  SELECT"
      "    amount_with_fee_val AS refund_val"
      "   ,amount_with_fee_frac AS refund_frac"
      "   ,coin_pub"
      "   ,deposit_serial_id" /* theoretically, coin could be in multiple refunded transactions */
      "    FROM refunds"
      "   WHERE coin_pub IN (SELECT coin_pub FROM dep)"
      "     AND deposit_serial_id IN (SELECT deposit_serial_id FROM dep))"
      " ,ref_by_coin AS (" /* total up refunds by coin */
      "  SELECT"
      "    SUM(refund_val) AS sum_refund_val"
      "   ,SUM(refund_frac) AS sum_refund_frac"
      "   ,coin_pub"
      "   ,deposit_serial_id" /* theoretically, coin could be in multiple refunded transactions */
      "    FROM ref"
      "   GROUP BY coin_pub, deposit_serial_id)"
      " ,norm_ref_by_coin AS (" /* normalize */
      "  SELECT"
      "    sum_refund_val + sum_refund_frac / 100000000 AS norm_refund_val"
      "   ,sum_refund_frac % 100000000 AS norm_refund_frac"
      "   ,coin_pub"
      "   ,deposit_serial_id" /* theoretically, coin could be in multiple refunded transactions */
      "    FROM ref_by_coin)"
      " ,fully_refunded_coins AS (" /* find applicable refunds -- NOTE: may do a full join on the master, maybe find a left-join way to integrate with query above to push it to the shards? */
      "  SELECT"
      "    dep.coin_pub"
      "    FROM norm_ref_by_coin norm"
      "    JOIN dep"
      "      ON (norm.coin_pub = dep.coin_pub"
      "      AND norm.deposit_serial_id = dep.deposit_Serial_id"
      "      AND norm.norm_refund_val = dep.amount_val"
      "      AND norm.norm_refund_frac = dep.amount_frac))"
      " ,fees AS (" /* find deposit fees for not fully refunded deposits */
      "  SELECT"
      "    denom.fee_deposit_val AS fee_val"
      "   ,denom.fee_deposit_frac AS fee_frac"
      "   ,cs.deposit_serial_id" /* ensures we get the fee for each coin, not once per denomination */
      "    FROM dep cs"
      "    JOIN known_coins kc" /* NOTE: may do a full join on the master, maybe find a left-join way to integrate with query above to push it to the shards? */
      "      USING (coin_pub)"
      "    JOIN denominations denom"
      "      USING (denominations_serial)"
      "    WHERE coin_pub NOT IN (SELECT coin_pub FROM fully_refunded_coins))"
      " ,dummy AS (" /* add deposits to aggregation_tracking */
      "    INSERT INTO aggregation_tracking"
      "    (deposit_serial_id"
      "    ,wtid_raw)"
      "    SELECT deposit_serial_id,$4"
      "      FROM dep)"
      "SELECT" /* calculate totals (deposits, refunds and fees) */
      "  CAST(COALESCE(SUM(dep.amount_val),0) AS INT8) AS sum_deposit_value" /* cast needed, otherwise we get NUMBER */
      " ,COALESCE(SUM(dep.amount_frac),0) AS sum_deposit_fraction" /* SUM over INT returns INT8 */
      " ,CAST(COALESCE(SUM(ref.refund_val),0) AS INT8) AS sum_refund_value"
      " ,COALESCE(SUM(ref.refund_frac),0) AS sum_refund_fraction"
      " ,CAST(COALESCE(SUM(fees.fee_val),0) AS INT8) AS sum_fee_value"
      " ,COALESCE(SUM(fees.fee_frac),0) AS sum_fee_fraction"
      " FROM dep "
      "   FULL OUTER JOIN ref ON (FALSE)"    /* We just want all sums */
      "   FULL OUTER JOIN fees ON (FALSE);"),


    /* Used in #postgres_create_aggregation_transient() */
    GNUNET_PQ_make_prepare (
      "create_aggregation_transient",
      "INSERT INTO aggregation_transient"
      " (amount_val"
      " ,amount_frac"
      " ,merchant_pub"
      " ,wire_target_h_payto"
      " ,legitimization_requirement_serial_id"
      " ,exchange_account_section"
      " ,wtid_raw)"
      " VALUES ($1, $2, $3, $4, $5, $6, $7);"),
    /* Used in #postgres_select_aggregation_transient() */
    GNUNET_PQ_make_prepare (
      "select_aggregation_transient",
      "SELECT"
      "  amount_val"
      " ,amount_frac"
      " ,wtid_raw"
      " FROM aggregation_transient"
      " WHERE wire_target_h_payto=$1"
      "   AND merchant_pub=$2"
      "   AND exchange_account_section=$3;"),
    /* Used in #postgres_find_aggregation_transient() */
    GNUNET_PQ_make_prepare (
      "find_transient_aggregations",
      "SELECT"
      "  amount_val"
      " ,amount_frac"
      " ,wtid_raw"
      " ,merchant_pub"
      " ,payto_uri"
      " FROM aggregation_transient atr"
      " JOIN wire_targets wt USING (wire_target_h_payto)"
      " WHERE atr.wire_target_h_payto=$1;"),
    /* Used in #postgres_update_aggregation_transient() */
    GNUNET_PQ_make_prepare (
      "update_aggregation_transient",
      "UPDATE aggregation_transient"
      " SET amount_val=$1"
      "    ,amount_frac=$2"
      "    ,legitimization_requirement_serial_id=$5"
      " WHERE wire_target_h_payto=$3"
      "   AND wtid_raw=$4"),
    /* Used in #postgres_delete_aggregation_transient() */
    GNUNET_PQ_make_prepare (
      "delete_aggregation_transient",
      "DELETE FROM aggregation_transient"
      " WHERE wire_target_h_payto=$1"
      "   AND wtid_raw=$2"),

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
      " FROM deposits dep"
      "    JOIN wire_targets wt"
      "      USING (wire_target_h_payto)"
      "    JOIN known_coins kc"
      "      ON (kc.coin_pub = dep.coin_pub)"
      "    JOIN denominations denoms"
      "      USING (denominations_serial)"
      " WHERE dep.coin_pub=$1;"),

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
      " ORDER BY tp.transfer_pub, rrc.freshcoin_index ASC"),
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
      " WHERE wtid_raw=$1;"),
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
      " FROM deposits dep"
      "    JOIN wire_targets wt"
      "      USING (wire_target_h_payto)"
      "    JOIN aggregation_tracking"
      "      USING (deposit_serial_id)"
      "    JOIN known_coins kc"
      "      ON (kc.coin_pub = dep.coin_pub)"
      "    JOIN denominations denom"
      "      USING (denominations_serial)"
      "    JOIN wire_out"
      "      USING (wtid_raw)"
      " WHERE dep.coin_pub=$1"
      "   AND dep.merchant_pub=$3"
      "   AND dep.h_contract_terms=$2"),
    /* Used in #postgres_insert_aggregation_tracking */
    GNUNET_PQ_make_prepare (
      "insert_aggregation_tracking",
      "INSERT INTO aggregation_tracking "
      "(deposit_serial_id"
      ",wtid_raw"
      ") VALUES "
      "($1, $2);"),
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
      "   AND end_date > $2;"),
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
      "   AND end_date > $1;"),
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
      " WHERE start_date >= $1"),
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
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);"),
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
      "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15);"),
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
      "($1, $2, $3, $4, $5, $6);"),
    /* Used in #postgres_wire_prepare_data_insert() to store
       wire transfer information before actually committing it with the bank */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_insert",
      "INSERT INTO prewire "
      "(wire_method"
      ",buf"
      ") VALUES "
      "($1, $2);"),
    /* Used in #postgres_wire_prepare_data_mark_finished() */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_mark_done",
      "UPDATE prewire"
      " SET finished=TRUE"
      " WHERE prewire_uuid=$1;"),
    /* Used in #postgres_wire_prepare_data_mark_failed() */
    GNUNET_PQ_make_prepare (
      "wire_prepare_data_mark_failed",
      "UPDATE prewire"
      " SET failed=TRUE"
      " WHERE prewire_uuid=$1;"),
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
      " LIMIT $2;"),
    /* Used in #postgres_select_deposits_missing_wire */
    // FIXME: used by the auditor; can probably be done
    // smarter by checking if 'done' or 'blocked'
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
      ",done"
      " FROM deposits d"
      "   JOIN known_coins"
      "     USING (coin_pub)"
      "   JOIN wire_targets"
      "     USING (wire_target_h_payto)"
      " WHERE wire_deadline >= $1"
      " AND wire_deadline < $2"
      " AND NOT (EXISTS (SELECT 1"
      "            FROM refunds r"
      "            WHERE (r.coin_pub = d.coin_pub) AND (r.deposit_serial_id = d.deposit_serial_id))"
      "       OR EXISTS (SELECT 1"
      "            FROM aggregation_tracking"
      "            WHERE (aggregation_tracking.deposit_serial_id = d.deposit_serial_id)))"
      " ORDER BY wire_deadline ASC"),
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
      " ORDER BY wireout_uuid ASC;"),
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
      " ORDER BY wireout_uuid ASC;"),
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
      " ORDER BY recoup_uuid ASC;"),
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
      " ORDER BY recoup_refresh_uuid ASC;"),
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
      " ORDER BY close_uuid ASC;"),
    /* Used in #postgres_get_reserve_history() to obtain recoup transactions
       for a reserve - query optimization should be disabled i.e.
       BEGIN; SET LOCAL join_collapse_limit=1; query; COMMIT; */
    GNUNET_PQ_make_prepare (
      "recoup_by_reserve",
      /*
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
      */
      "SELECT robr.coin_pub "
      "  ,robr.coin_sig "
      "  ,robr.coin_blind "
      "  ,robr.amount_val "
      "  ,robr.amount_frac "
      "  ,robr.recoup_timestamp "
      "  ,denominations.denom_pub_hash "
      "  ,robr.denom_sig "
      "FROM denominations "
      "  JOIN exchange_do_recoup_by_reserve($1) robr"
      " USING (denominations_serial);"),
    /* Used in #postgres_get_reserve_status() to obtain recoup transactions
       for a reserve - query optimization should be disabled i.e.
       BEGIN; SET LOCAL join_collapse_limit=1; query; COMMIT; */
    GNUNET_PQ_make_prepare (
      "recoup_by_reserve_truncated",
      /*
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
      " WHERE recoup_timestamp>=$2"
      " AND recoup.coin_pub"
      "  IN (SELECT coin_pub"
      "     FROM recoup_by_reserve"
      "     JOIN (reserves_out"
      "       JOIN (reserves_out_by_reserve"
      "         JOIN reserves"
      "           ON (reserves.reserve_uuid = reserves_out_by_reserve.reserve_uuid))"
      "       ON (reserves_out_by_reserve.h_blind_ev = reserves_out.h_blind_ev))"
      "     ON (recoup_by_reserve.reserve_out_serial_id = reserves_out.reserve_out_serial_id)"
      "     WHERE reserves.reserve_pub=$1);",
      */
      "SELECT robr.coin_pub "
      "  ,robr.coin_sig "
      "  ,robr.coin_blind "
      "  ,robr.amount_val "
      "  ,robr.amount_frac "
      "  ,robr.recoup_timestamp "
      "  ,denominations.denom_pub_hash "
      "  ,robr.denom_sig "
      "FROM denominations "
      "  JOIN exchange_do_recoup_by_reserve($1) robr"
      "    USING (denominations_serial)"
      " WHERE recoup_timestamp>=$2;"),
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
      "    WHERE old_coin_pub=$1);"),
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
      " WHERE reserve_pub=$1;"),
    /* Used in #postgres_get_reserve_status() */
    GNUNET_PQ_make_prepare (
      "close_by_reserve_truncated",
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
      " WHERE reserve_pub=$1"
      "   AND execution_date>=$2;"),
    /* Used in #postgres_get_reserve_history() */
    GNUNET_PQ_make_prepare (
      "merge_by_reserve",
      "SELECT"
      " pr.amount_with_fee_val"
      ",pr.amount_with_fee_frac"
      ",pr.balance_val"
      ",pr.balance_frac"
      ",pr.purse_fee_val"
      ",pr.purse_fee_frac"
      ",pr.h_contract_terms"
      ",pr.merge_pub"
      ",am.reserve_sig"
      ",pm.purse_pub"
      ",pm.merge_timestamp"
      ",pr.purse_expiration"
      ",pr.age_limit"
      ",pr.flags"
      " FROM purse_merges pm"
      "   JOIN purse_requests pr"
      "     USING (purse_pub)"
      "   JOIN account_merges am"
      "     ON (am.purse_pub = pm.purse_pub AND"
      "         am.reserve_pub = pm.reserve_pub)"
      " WHERE pm.reserve_pub=$1"
      "  AND pm.partner_serial_id=0" /* must be local! */
      "  AND pr.finished"
      "  AND NOT pr.refunded;"),
    /* Used in #postgres_get_reserve_status() */
    GNUNET_PQ_make_prepare (
      "merge_by_reserve_truncated",
      "SELECT"
      " pr.amount_with_fee_val"
      ",pr.amount_with_fee_frac"
      ",pr.balance_val"
      ",pr.balance_frac"
      ",pr.purse_fee_val"
      ",pr.purse_fee_frac"
      ",pr.h_contract_terms"
      ",pr.merge_pub"
      ",am.reserve_sig"
      ",pm.purse_pub"
      ",pm.merge_timestamp"
      ",pr.purse_expiration"
      ",pr.age_limit"
      ",pr.flags"
      " FROM purse_merges pm"
      "   JOIN purse_requests pr"
      "     USING (purse_pub)"
      "   JOIN account_merges am"
      "     ON (am.purse_pub = pm.purse_pub AND"
      "         am.reserve_pub = pm.reserve_pub)"
      " WHERE pm.reserve_pub=$1"
      "  AND pm.merge_timestamp >= $2"
      "  AND pm.partner_serial_id=0" /* must be local! */
      "  AND pr.finished"
      "  AND NOT pr.refunded;"),
    /* Used in #postgres_get_reserve_history() */
    GNUNET_PQ_make_prepare (
      "history_by_reserve",
      "SELECT"
      " history_fee_val"
      ",history_fee_frac"
      ",request_timestamp"
      ",reserve_sig"
      " FROM history_requests"
      " WHERE reserve_pub=$1;"),
    /* Used in #postgres_get_reserve_status() */
    GNUNET_PQ_make_prepare (
      "history_by_reserve_truncated",
      "SELECT"
      " history_fee_val"
      ",history_fee_frac"
      ",request_timestamp"
      ",reserve_sig"
      " FROM history_requests"
      " WHERE reserve_pub=$1"
      "  AND request_timestamp>=$2;"),
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
      " FROM recoup rcp"
      /* NOTE: suboptimal JOIN follows: crosses shards!
         Could theoretically be improved via a materialized
         index. But likely not worth it (query is rare and
         number of reserve shards might be limited) */
      " JOIN reserves_out ro"
      "   USING (reserve_out_serial_id)"
      " JOIN reserves"
      "   USING (reserve_uuid)"
      " JOIN known_coins coins"
      "   USING (coin_pub)"
      " JOIN denominations denoms"
      "   ON (denoms.denominations_serial = coins.denominations_serial)"
      " WHERE coins.coin_pub=$1;"),
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
      " WHERE coins.coin_pub=$1;"),
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
      " LIMIT 1;"),
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
      " LIMIT 1;"),
    /* Used in #postgres_lookup_auditor_timestamp() */
    GNUNET_PQ_make_prepare (
      "lookup_auditor_timestamp",
      "SELECT"
      " last_change"
      " FROM auditors"
      " WHERE auditor_pub=$1;"),
    /* Used in #postgres_lookup_auditor_status() */
    GNUNET_PQ_make_prepare (
      "lookup_auditor_status",
      "SELECT"
      " auditor_url"
      ",is_active"
      " FROM auditors"
      " WHERE auditor_pub=$1;"),
    /* Used in #postgres_lookup_wire_timestamp() */
    GNUNET_PQ_make_prepare (
      "lookup_wire_timestamp",
      "SELECT"
      " last_change"
      " FROM wire_accounts"
      " WHERE payto_uri=$1;"),
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
      "($1, $2, $3, true, $4);"),
    /* used in #postgres_update_auditor() */
    GNUNET_PQ_make_prepare (
      "update_auditor",
      "UPDATE auditors"
      " SET"
      "  auditor_url=$2"
      " ,auditor_name=$3"
      " ,is_active=$4"
      " ,last_change=$5"
      " WHERE auditor_pub=$1"),
    /* used in #postgres_insert_wire() */
    GNUNET_PQ_make_prepare (
      "insert_wire",
      "INSERT INTO wire_accounts "
      "(payto_uri"
      ",master_sig"
      ",is_active"
      ",last_change"
      ") VALUES "
      "($1, $2, true, $3);"),
    /* used in #postgres_update_wire() */
    GNUNET_PQ_make_prepare (
      "update_wire",
      "UPDATE wire_accounts"
      " SET"
      "  is_active=$2"
      " ,last_change=$3"
      " WHERE payto_uri=$1"),
    /* used in #postgres_update_wire() */
    GNUNET_PQ_make_prepare (
      "get_wire_accounts",
      "SELECT"
      " payto_uri"
      ",master_sig"
      " FROM wire_accounts"
      " WHERE is_active"),
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
      " WHERE wire_method=$1"),
    /* used in #postgres_insert_signkey_revocation() */
    GNUNET_PQ_make_prepare (
      "insert_signkey_revocation",
      "INSERT INTO signkey_revocations "
      "(esk_serial"
      ",master_sig"
      ") SELECT esk_serial, $2 "
      "    FROM exchange_sign_keys"
      "   WHERE exchange_pub=$1;"),
    /* used in #postgres_insert_signkey_revocation() */
    GNUNET_PQ_make_prepare (
      "lookup_signkey_revocation",
      "SELECT "
      " master_sig"
      " FROM signkey_revocations"
      " WHERE esk_serial="
      "   (SELECT esk_serial"
      "      FROM exchange_sign_keys"
      "     WHERE exchange_pub=$1);"),
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
      "($1, $2, $3, $4, $5);"),
    /* used in #postgres_lookup_signing_key() */
    GNUNET_PQ_make_prepare (
      "lookup_signing_key",
      "SELECT"
      " valid_from"
      ",expire_sign"
      ",expire_legal"
      " FROM exchange_sign_keys"
      " WHERE exchange_pub=$1"),
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
      " WHERE denom_pub_hash=$1;"),
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
      "   WHERE denom_pub_hash=$2;"),
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
      "    WHERE denom_pub_hash=$2);"),
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
      " AND start_date < $3;"),
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
      "   AND start_date < $2;"),
    /* used in #postgres_commit */
    GNUNET_PQ_make_prepare (
      "do_commit",
      "COMMIT"),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "get_open_shard",
      "SELECT"
      " start_row"
      ",end_row"
      " FROM work_shards"
      " WHERE job_name=$1"
      "   AND completed=FALSE"
      "   AND last_attempt<$2"
      " ORDER BY last_attempt ASC"
      " LIMIT 1;"),
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
      " LIMIT 1;"),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "reclaim_shard",
      "UPDATE work_shards"
      " SET last_attempt=$2"
      " WHERE job_name=$1"
      "   AND start_row=$3"
      "   AND end_row=$4"),
    /* Used in #postgres_begin_revolving_shard() */
    GNUNET_PQ_make_prepare (
      "reclaim_revolving_shard",
      "UPDATE revolving_work_shards"
      " SET last_attempt=$2"
      "    ,active=TRUE"
      " WHERE job_name=$1"
      "   AND start_row=$3"
      "   AND end_row=$4"),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "get_last_shard",
      "SELECT"
      " end_row"
      " FROM work_shards"
      " WHERE job_name=$1"
      " ORDER BY end_row DESC"
      " LIMIT 1;"),
    /* Used in #postgres_begin_revolving_shard() */
    GNUNET_PQ_make_prepare (
      "get_last_revolving_shard",
      "SELECT"
      " end_row"
      " FROM revolving_work_shards"
      " WHERE job_name=$1"
      " ORDER BY end_row DESC"
      " LIMIT 1;"),
    /* Used in #postgres_abort_shard() */
    GNUNET_PQ_make_prepare (
      "abort_shard",
      "UPDATE work_shards"
      "   SET last_attempt=0"
      " WHERE job_name = $1 "
      "    AND start_row = $2 "
      "    AND end_row = $3;"),
    /* Used in #postgres_begin_shard() */
    GNUNET_PQ_make_prepare (
      "claim_next_shard",
      "INSERT INTO work_shards"
      "(job_name"
      ",last_attempt"
      ",start_row"
      ",end_row"
      ") VALUES "
      "($1, $2, $3, $4);"),
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
      "($1, $2, $3, $4, TRUE);"),
    /* Used in #postgres_complete_shard() */
    GNUNET_PQ_make_prepare (
      "complete_shard",
      "UPDATE work_shards"
      " SET completed=TRUE"
      " WHERE job_name=$1"
      "   AND start_row=$2"
      "   AND end_row=$3"),
    /* Used in #postgres_complete_shard() */
    GNUNET_PQ_make_prepare (
      "release_revolving_shard",
      "UPDATE revolving_work_shards"
      " SET active=FALSE"
      " WHERE job_name=$1"
      "   AND start_row=$2"
      "   AND end_row=$3"),
    /* Used in #postgres_set_extension_config */
    GNUNET_PQ_make_prepare (
      "set_extension_config",
      "INSERT INTO extensions (name, config) VALUES ($1, $2) "
      "ON CONFLICT (name) "
      "DO UPDATE SET config=$2"),
    /* Used in #postgres_get_extension_config */
    GNUNET_PQ_make_prepare (
      "get_extension_config",
      "SELECT "
      " config "
      "FROM extensions"
      "   WHERE name=$1;"),
    /* Used in #postgres_insert_contract() */
    GNUNET_PQ_make_prepare (
      "insert_contract",
      "INSERT INTO contracts"
      "  (purse_pub"
      "  ,pub_ckey"
      "  ,e_contract"
      "  ,contract_sig"
      "  ,purse_expiration"
      "  ) SELECT "
      "  $1, $2, $3, $4, purse_expiration"
      "  FROM purse_requests"
      "  WHERE purse_pub=$1"
      "  ON CONFLICT DO NOTHING;"),
    /* Used in #postgres_select_contract */
    GNUNET_PQ_make_prepare (
      "select_contract",
      "SELECT "
      " purse_pub"
      ",e_contract"
      ",contract_sig"
      " FROM contracts"
      "   WHERE pub_ckey=$1;"),
    /* Used in #postgres_select_contract_by_purse */
    GNUNET_PQ_make_prepare (
      "select_contract_by_purse",
      "SELECT "
      " pub_ckey"
      ",e_contract"
      ",contract_sig"
      " FROM contracts"
      "   WHERE purse_pub=$1;"),
    /* Used in #postgres_insert_purse_request() */
    GNUNET_PQ_make_prepare (
      "insert_purse_request",
      "INSERT INTO purse_requests"
      "  (purse_pub"
      "  ,merge_pub"
      "  ,purse_creation"
      "  ,purse_expiration"
      "  ,h_contract_terms"
      "  ,age_limit"
      "  ,flags"
      "  ,in_reserve_quota"
      "  ,amount_with_fee_val"
      "  ,amount_with_fee_frac"
      "  ,purse_fee_val"
      "  ,purse_fee_frac"
      "  ,purse_sig"
      "  ) VALUES "
      "  ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)"
      "  ON CONFLICT DO NOTHING;"),
    /* Used in #postgres_select_purse */
    GNUNET_PQ_make_prepare (
      "select_purse",
      "SELECT "
      " merge_pub"
      ",purse_expiration"
      ",h_contract_terms"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",balance_val"
      ",balance_frac"
      ",merge_timestamp"
      " FROM purse_requests"
      " LEFT JOIN purse_merges USING (purse_pub)"
      " WHERE purse_pub=$1;"),
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
      ",balance_val"
      ",balance_frac"
      ",purse_sig"
      " FROM purse_requests"
      " WHERE purse_pub=$1;"),
    /* Used in #postgres_select_purse_by_merge_pub */
    GNUNET_PQ_make_prepare (
      "select_purse_by_merge_pub",
      "SELECT "
      " purse_pub"
      ",purse_expiration"
      ",h_contract_terms"
      ",age_limit"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",balance_val"
      ",balance_frac"
      ",purse_sig"
      " FROM purse_requests"
      " WHERE merge_pub=$1;"),
    /* Used in #postgres_get_purse_deposit */
    GNUNET_PQ_make_prepare (
      "select_purse_deposit_by_coin_pub",
      "SELECT "
      " coin_sig"
      ",amount_with_fee_val"
      ",amount_with_fee_frac"
      ",denom_pub_hash"
      ",age_commitment_hash"
      ",partner_base_url"
      " FROM purse_deposits"
      " LEFT JOIN partners USING (partner_serial_id)"
      " JOIN known_coins kc USING (coin_pub)"
      " JOIN denominations USING (denominations_serial)"
      " WHERE coin_pub=$2"
      "   AND purse_pub=$1;"),
    /* Used in #postgres_do_purse_merge() */
    GNUNET_PQ_make_prepare (
      "call_purse_merge",
      "SELECT"
      " out_no_partner AS no_partner"
      ",out_no_balance AS no_balance"
      ",out_conflict AS conflict"
      " FROM exchange_do_purse_merge"
      "  ($1, $2, $3, $4, $5, $6, $7, $8);"),
    /* Used in #postgres_do_reserve_purse() */
    GNUNET_PQ_make_prepare (
      "call_reserve_purse",
      "SELECT"
      " out_no_funds AS insufficient_funds"
      ",out_no_reserve AS no_reserve"
      ",out_conflict AS conflict"
      " FROM exchange_do_reserve_purse"
      "  ($1, $2, $3, $4, $5, $6, $7, $8, $9);"),
    /* Used in #postgres_select_purse_merge */
    GNUNET_PQ_make_prepare (
      "select_purse_merge",
      "SELECT "
      " reserve_pub"
      ",merge_sig"
      ",merge_timestamp"
      ",partner_base_url"
      " FROM purse_merges"
      " LEFT JOIN partners USING (partner_serial_id)"
      " WHERE purse_pub=$1;"),
    /* Used in #postgres_do_account_merge() */
    GNUNET_PQ_make_prepare (
      "call_account_merge",
      "SELECT 1"
      " FROM exchange_do_account_merge"
      "  ($1, $2, $3);"),
    /* Used in #postgres_insert_history_request() */
    GNUNET_PQ_make_prepare (
      "call_history_request",
      "SELECT"
      "  out_balance_ok AS balance_ok"
      " ,out_idempotent AS idempotent"
      " FROM exchange_do_history_request"
      "  ($1, $2, $3, $4, $5)"),

    /* Used in #postgres_insert_kyc_requirement_for_account() */
    GNUNET_PQ_make_prepare (
      "insert_legitimization_requirement",
      "INSERT INTO legitimization_requirements"
      "  (h_payto"
      "  ,required_checks"
      "  ) VALUES "
      "  ($1, $2)"
      " ON CONFLICT (h_payto,required_checks) "
      "   DO UPDATE SET h_payto=$1" /* syntax requirement: dummy op */
      " RETURNING legitimization_requirement_serial_id"),
    /* Used in #postgres_insert_kyc_requirement_process() */
    GNUNET_PQ_make_prepare (
      "insert_legitimization_process",
      "INSERT INTO legitimization_processes"
      "  (h_payto"
      "  ,provider_section"
      "  ,provider_user_id"
      "  ,provider_legitimization_id"
      "  ) VALUES "
      "  ($1, $2, $3, $4)"
      " ON CONFLICT (h_payto,provider_section) "
      "   DO UPDATE SET"
      "      provider_user_id=$3"
      "     ,provider_legitimization_id=$4"
      " RETURNING legitimization_process_serial_id"),
    /* Used in #postgres_update_kyc_requirement_by_row() */
    GNUNET_PQ_make_prepare (
      "update_legitimization_process",
      "UPDATE legitimization_processes"
      " SET provider_user_id=$4"
      "    ,provider_legitimization_id=$5"
      "    ,expiration_time=GREATEST(expiration_time,$6)"
      " WHERE"
      "      h_payto=$3"
      "  AND legitimization_process_serial_id=$1"
      "  AND provider_section=$2;"),
    GNUNET_PQ_make_prepare (
      "alert_kyc_status_change",
      "INSERT INTO kyc_alerts"
      " (h_payto"
      " ,trigger_type)"
      " VALUES"
      " ($1,$2);"),
    /* Used in #postgres_lookup_kyc_requirement_by_row() */
    GNUNET_PQ_make_prepare (
      "lookup_legitimization_requirement_by_row",
      "SELECT "
      " required_checks"
      ",h_payto"
      " FROM legitimization_requirements"
      " WHERE legitimization_requirement_serial_id=$1;"),
    /* Used in #postgres_lookup_kyc_process_by_account() */
    GNUNET_PQ_make_prepare (
      "lookup_process_by_account",
      "SELECT "
      " legitimization_process_serial_id"
      ",expiration_time"
      ",provider_user_id"
      ",provider_legitimization_id"
      " FROM legitimization_processes"
      " WHERE h_payto=$1"
      "   AND provider_section=$2;"),
    /* Used in #postgres_kyc_provider_account_lookup() */
    GNUNET_PQ_make_prepare (
      "get_wire_target_by_legitimization_id",
      "SELECT "
      " h_payto"
      ",legitimization_process_serial_id"
      " FROM legitimization_processes"
      " WHERE provider_legitimization_id=$1"
      "   AND provider_section=$2;"),
    /* Used in #postgres_select_satisfied_kyc_processes() */
    GNUNET_PQ_make_prepare (
      "get_satisfied_legitimizations",
      "SELECT "
      " provider_section"
      " FROM legitimization_processes"
      " WHERE h_payto=$1"
      "   AND expiration_time>=$2;"),

    /* Used in #postgres_select_withdraw_amounts_for_kyc_check (
() */
    GNUNET_PQ_make_prepare (
      "select_kyc_relevant_withdraw_events",
      "SELECT"
      " ro.amount_with_fee_val AS amount_val"
      ",ro.amount_with_fee_frac AS amount_frac"
      ",ro.execution_date AS date"
      " FROM reserves_out ro"
      " JOIN reserves_out_by_reserve USING (h_blind_ev)"
      " JOIN reserves res ON (ro.reserve_uuid = res.reserve_uuid)"
      " JOIN reserves_in ri ON (res.reserve_pub = ri.reserve_pub)"
      " WHERE wire_source_h_payto=$1"
      "   AND ro.execution_date >= $2"
      " ORDER BY ro.execution_date DESC"),
    /* Used in #postgres_select_aggregation_amounts_for_kyc_check (
() */
    GNUNET_PQ_make_prepare (
      "select_kyc_relevant_aggregation_events",
      "SELECT"
      " amount_val"
      ",amount_frac"
      ",execution_date AS date"
      " FROM wire_out"
      " WHERE wire_target_h_payto=$1"
      "   AND execution_date >= $2"
      " ORDER BY execution_date DESC"),

    /* Used in #postgres_select_merge_amounts_for_kyc_check (
() */
    GNUNET_PQ_make_prepare (
      "select_kyc_relevant_merge_events",
      "SELECT"
      " amount_with_fee_val AS amount_val"
      ",amount_with_fee_frac AS amount_frac"
      ",merge_timestamp AS date"
      " FROM account_merges"
      " JOIN purse_merges USING (purse_pub)"
      " JOIN purse_requests USING (purse_pub)"
      " WHERE wallet_h_payto=$1"
      "   AND merge_timestamp >= $2"
      "   AND finished"
      " ORDER BY merge_timestamp DESC"),

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
      GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
#else
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute (
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      GNUNET_PQ_make_try_execute ("SET autocommit=OFF;"),
      GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
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
    pg->prep_gen++;
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

  GNUNET_assert (NULL != name);
  if (GNUNET_SYSERR ==
      postgres_preflight (pg))
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting transaction `%s'\n",
              name);
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

  GNUNET_assert (NULL != name);
  if (GNUNET_SYSERR ==
      postgres_preflight (pg))
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting READ COMMITTED transaction `%s`\n",
              name);
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
 * Start a READ ONLY serializable transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param name unique name identifying the transaction (for debugging)
 *             must point to a constant
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
postgres_start_read_only (void *cls,
                          const char *name)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute (
      "START TRANSACTION ISOLATION LEVEL SERIALIZABLE READ ONLY"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  GNUNET_assert (NULL != name);
  if (GNUNET_SYSERR ==
      postgres_preflight (pg))
    return GNUNET_SYSERR;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting READ ONLY transaction `%s`\n",
              name);
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

  if (NULL == pg->transaction_name)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping rollback, no transaction active\n");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Rolling back transaction\n");
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

  GNUNET_break (NULL != pg->transaction_name);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Committing transaction `%s'\n",
              pg->transaction_name);
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
  const struct TALER_EXCHANGEDB_DenominationKeyInformation *issue)
{
  struct PostgresClosure *pg = cls;
  struct TALER_DenominationHashP denom_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&issue->denom_hash),
    TALER_PQ_query_param_denom_pub (denom_pub),
    GNUNET_PQ_query_param_auto_from_type (&issue->signature),
    GNUNET_PQ_query_param_timestamp (&issue->start),
    GNUNET_PQ_query_param_timestamp (&issue->expire_withdraw),
    GNUNET_PQ_query_param_timestamp (&issue->expire_deposit),
    GNUNET_PQ_query_param_timestamp (&issue->expire_legal),
    TALER_PQ_query_param_amount (&issue->value),
    TALER_PQ_query_param_amount (&issue->fees.withdraw),
    TALER_PQ_query_param_amount (&issue->fees.deposit),
    TALER_PQ_query_param_amount (&issue->fees.refresh),
    TALER_PQ_query_param_amount (&issue->fees.refund),
    GNUNET_PQ_query_param_uint32 (&denom_pub->age_mask.bits),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (denom_pub->age_mask.bits ==
                 issue->age_mask.bits);
  TALER_denom_pub_hash (denom_pub,
                        &denom_hash);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&denom_hash,
                                &issue->denom_hash));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->start.abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->expire_withdraw.abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->expire_deposit.abs_time));
  GNUNET_assert (! GNUNET_TIME_absolute_is_zero (
                   issue->expire_legal.abs_time));
  /* check fees match denomination currency */
  GNUNET_assert (GNUNET_YES ==
                 TALER_denom_fee_check_currency (
                   issue->value.currency,
                   &issue->fees));
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
  struct TALER_EXCHANGEDB_DenominationKeyInformation *issue)
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
    GNUNET_PQ_result_spec_timestamp ("valid_from",
                                     &issue->start),
    GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                     &issue->expire_withdraw),
    GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                     &issue->expire_deposit),
    GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                     &issue->expire_legal),
    TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                 &issue->value),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                 &issue->fees.withdraw),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                 &issue->fees.deposit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                 &issue->fees.refresh),
    TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                 &issue->fees.refund),
    GNUNET_PQ_result_spec_uint32 ("age_mask",
                                  &issue->age_mask.bits),
    GNUNET_PQ_result_spec_end
  };

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "denomination_get",
                                                 params,
                                                 rs);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    return qs;
  issue->denom_hash = *denom_pub_hash;
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
    struct TALER_EXCHANGEDB_DenominationKeyInformation issue;
    struct TALER_DenominationPublicKey denom_pub;
    struct TALER_DenominationHashP denom_hash;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                            &issue.signature),
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &denom_hash),
      GNUNET_PQ_result_spec_timestamp ("valid_from",
                                       &issue.start),
      GNUNET_PQ_result_spec_timestamp ("expire_withdraw",
                                       &issue.expire_withdraw),
      GNUNET_PQ_result_spec_timestamp ("expire_deposit",
                                       &issue.expire_deposit),
      GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                       &issue.expire_legal),
      TALER_PQ_RESULT_SPEC_AMOUNT ("coin",
                                   &issue.value),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                   &issue.fees.withdraw),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                   &issue.fees.deposit),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                   &issue.fees.refresh),
      TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                   &issue.fees.refund),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_uint32 ("age_mask",
                                    &issue.age_mask.bits),
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

    /* Unfortunately we have to carry the age mask in both, the
     * TALER_DenominationPublicKey and
     * TALER_EXCHANGEDB_DenominationKeyInformation at different times.
     * Here we use _both_ so let's make sure the values are the same. */
    denom_pub.age_mask = issue.age_mask;
    TALER_denom_pub_hash (&denom_pub,
                          &issue.denom_hash);
    if (0 !=
        GNUNET_memcmp (&issue.denom_hash,
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
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_reserves_get (void *cls,
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
 * Get the origin of funds of a reserve.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param[out] h_payto set to hash of the wire source payto://-URI
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_reserves_get_origin (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_PaytoHashP *h_payto)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("wire_source_h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_h_wire_source_of_reserve",
                                                   params,
                                                   rs);
}


/**
 * Extract next KYC alert.  Deletes the alert.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param trigger_type which type of alert to drain
 * @param[out] h_payto set to hash of payto-URI where KYC status changed
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_drain_kyc_alert (void *cls,
                          uint32_t trigger_type,
                          struct TALER_PaytoHashP *h_payto)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint32 (&trigger_type),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "drain_kyc_alert",
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
 * Setup new wire target for @a payto_uri.
 *
 * @param pg the plugin-specific state
 * @param payto_uri the payto URI to check
 * @param[out] h_payto set to the hash of @a payto_uri
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
setup_wire_target (
  struct PostgresClosure *pg,
  const char *payto_uri,
  struct TALER_PaytoHashP *h_payto)
{
  struct GNUNET_PQ_QueryParam iparams[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_end
  };

  TALER_payto_hash (payto_uri,
                    h_payto);
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_kyc_status",
                                             iparams);
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
    enum GNUNET_DB_QueryStatus qs3;
    struct TALER_PaytoHashP h_payto;

    qs3 = setup_wire_target (pg,
                             sender_account_details,
                             &h_payto);
    if (qs3 < 0)
      return qs3;
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

    reserve_exists = postgres_reserves_get (pg,
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
 * @param[out] nonce_ok set to false if the nonce was reused
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
  bool *nonce_ok,
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
    GNUNET_PQ_result_spec_bool ("nonce_ok",
                                nonce_ok),
    GNUNET_PQ_result_spec_uint64 ("ruuid",
                                  ruuid),
    GNUNET_PQ_result_spec_end
  };

  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              pg->legal_reserve_expiration_time));
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_withdraw",
                                                   params,
                                                   rs);
}


/**
 * Perform reserve update as part of a batch withdraw operation, checking
 * for sufficient balance. Persisting the withdrawal details is done
 * separately!
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param now current time (rounded)
 * @param reserve_pub public key of the reserve to debit
 * @param amount total amount to withdraw
 * @param[out] found set to true if the reserve was found
 * @param[out] balance_ok set to true if the balance was sufficient
 * @param[out] ruuid set to the reserve's UUID (reserves table row)
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_batch_withdraw (
  void *cls,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *amount,
  bool *found,
  bool *balance_ok,
  uint64_t *ruuid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp gc;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("reserve_found",
                                found),
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_uint64 ("ruuid",
                                  ruuid),
    GNUNET_PQ_result_spec_end
  };

  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              pg->legal_reserve_expiration_time));
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_batch_withdraw",
                                                   params,
                                                   rs);
}


/**
 * Perform insert as part of a batch withdraw operation, and persisting the
 * withdrawal details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param nonce client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
 * @param collectable corresponding collectable coin (blind signature)
 * @param now current time (rounded)
 * @param ruuid reserve UUID
 * @param[out] denom_unknown set if the denomination is unknown in the DB
 * @param[out] conflict if the envelope was already in the DB
 * @param[out] nonce_reuse if @a nonce was non-NULL and reused
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_do_batch_withdraw_insert (
  void *cls,
  const struct TALER_CsNonce *nonce,
  const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable,
  struct GNUNET_TIME_Timestamp now,
  uint64_t ruuid,
  bool *denom_unknown,
  bool *conflict,
  bool *nonce_reuse)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    NULL == nonce
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (nonce),
    TALER_PQ_query_param_amount (&collectable->amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&collectable->denom_pub_hash),
    GNUNET_PQ_query_param_uint64 (&ruuid),
    GNUNET_PQ_query_param_auto_from_type (&collectable->reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (&collectable->h_coin_envelope),
    TALER_PQ_query_param_blinded_denom_sig (&collectable->sig),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("denom_unknown",
                                denom_unknown),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_bool ("nonce_reuse",
                                nonce_reuse),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_batch_withdraw_insert",
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
 * @param rms client-contributed input for CS denominations that must be checked for idempotency, or NULL for non-CS withdrawals
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
 * Add purse merge transfers to result set for
 * #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_p2p_merge (void *cls,
               PGresult *result,
               unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_PurseMerge *merge;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    merge = GNUNET_new (struct TALER_EXCHANGEDB_PurseMerge);
    {
      uint32_t flags32;
      struct TALER_Amount balance;
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                     &merge->purse_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                     &balance),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &merge->amount_with_fee),
        GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                         &merge->merge_timestamp),
        GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                         &merge->purse_expiration),
        GNUNET_PQ_result_spec_uint32 ("age_limit",
                                      &merge->min_age),
        GNUNET_PQ_result_spec_uint32 ("flags",
                                      &flags32),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &merge->h_contract_terms),
        GNUNET_PQ_result_spec_auto_from_type ("merge_pub",
                                              &merge->merge_pub),
        GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                              &merge->purse_pub),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &merge->reserve_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (merge);
        rhc->status = GNUNET_SYSERR;
        return;
      }
      merge->flags = (enum TALER_WalletAccountMergeFlags) flags32;
      if ( (! GNUNET_TIME_absolute_is_future (
              merge->merge_timestamp.abs_time)) &&
           (-1 != TALER_amount_cmp (&balance,
                                    &merge->amount_with_fee)) )
        merge->merged = true;
    }
    if (merge->merged)
      GNUNET_assert (0 <=
                     TALER_amount_add (&rhc->balance_in,
                                       &rhc->balance_in,
                                       &merge->amount_with_fee));
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &merge->purse_fee));
    merge->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_PURSE_MERGE;
    tail->details.merge = merge;
  }
}


/**
 * Add paid for history requests to result set for
 * #postgres_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_history_requests (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_HistoryRequest *history;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    history = GNUNET_new (struct TALER_EXCHANGEDB_HistoryRequest);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                     &history->history_fee),
        GNUNET_PQ_result_spec_timestamp ("request_timestamp",
                                         &history->request_timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &history->reserve_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (history);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &history->history_fee));
    history->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_HISTORY_REQUEST;
    tail->details.history = history;
  }
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
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup_by_reserve",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve",
      &add_exchange_to_bank },
    /** #TALER_EXCHANGEDB_RO_PURSE_MERGE */
    { "merge_by_reserve",
      &add_p2p_merge },
    /** #TALER_EXCHANGEDB_RO_HISTORY_REQUEST */
    { "history_by_reserve",
      &add_history_requests },
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
 * @param[out] balance_in set to the total of inbound
 *             transactions in the returned history
 * @param[out] balance_out set to the total of outbound
 *             transactions in the returned history
 * @param[out] rhp set to known transaction history (NULL if reserve is unknown)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_reserve_status (void *cls,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             struct TALER_Amount *balance_in,
                             struct TALER_Amount *balance_out,
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
    { "reserves_in_get_transactions_truncated",
      add_bank_to_exchange },
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out_truncated",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup_by_reserve_truncated",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve_truncated",
      &add_exchange_to_bank },
    /** #TALER_EXCHANGEDB_RO_PURSE_MERGE */
    { "merge_by_reserve_truncated",
      &add_p2p_merge },
    /** #TALER_EXCHANGEDB_RO_HISTORY_REQUEST */
    { "history_by_reserve_truncated",
      &add_history_requests },
    /* List terminator */
    { NULL,
      NULL }
  };
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Absolute timelimit;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_absolute_time (&timelimit),
    GNUNET_PQ_query_param_end
  };

  timelimit = GNUNET_TIME_absolute_subtract (
    GNUNET_TIME_absolute_get (),
    GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_WEEKS,
                                   5));
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
  *balance_in = rhc.balance_in;
  *balance_out = rhc.balance_out;
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
    /* Inconsistencies detected! Does not match! */
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Aggregate all matching deposits for @a h_payto and
 * @a merchant_pub, returning the total amounts.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param merchant_pub public key of the merchant
 * @param wtid wire transfer ID to set for the aggregate
 * @param[out] total set to the sum of the total deposits minus applicable deposit fees and refunds
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_aggregate (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  uint64_t sum_deposit_value;
  uint64_t sum_deposit_frac;
  uint64_t sum_refund_value;
  uint64_t sum_refund_frac;
  uint64_t sum_fee_value;
  uint64_t sum_fee_frac;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("sum_deposit_value",
                                  &sum_deposit_value),
    GNUNET_PQ_result_spec_uint64 ("sum_deposit_fraction",
                                  &sum_deposit_frac),
    GNUNET_PQ_result_spec_uint64 ("sum_refund_value",
                                  &sum_refund_value),
    GNUNET_PQ_result_spec_uint64 ("sum_refund_fraction",
                                  &sum_refund_frac),
    GNUNET_PQ_result_spec_uint64 ("sum_fee_value",
                                  &sum_fee_value),
    GNUNET_PQ_result_spec_uint64 ("sum_fee_fraction",
                                  &sum_fee_frac),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount sum_deposit;
  struct TALER_Amount sum_refund;
  struct TALER_Amount sum_fee;
  struct TALER_Amount delta;

  now = GNUNET_TIME_absolute_round_down (GNUNET_TIME_absolute_get (),
                                         pg->aggregator_shift);
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "aggregate",
                                                 params,
                                                 rs);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (pg->currency,
                                          total));
    return qs;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &sum_deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &sum_refund));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &sum_fee));
  sum_deposit.value    = sum_deposit_frac / TALER_AMOUNT_FRAC_BASE
                         + sum_deposit_value;
  sum_deposit.fraction = sum_deposit_frac % TALER_AMOUNT_FRAC_BASE;
  sum_refund.value     = sum_refund_frac  / TALER_AMOUNT_FRAC_BASE
                         + sum_refund_value;
  sum_refund.fraction  = sum_refund_frac  % TALER_AMOUNT_FRAC_BASE;
  sum_fee.value        = sum_fee_frac     / TALER_AMOUNT_FRAC_BASE
                         + sum_fee_value;
  sum_fee.fraction     = sum_fee_frac     % TALER_AMOUNT_FRAC_BASE; \
  GNUNET_assert (0 <=
                 TALER_amount_subtract (&delta,
                                        &sum_deposit,
                                        &sum_refund));
  GNUNET_assert (0 <=
                 TALER_amount_subtract (total,
                                        &delta,
                                        &sum_fee));
  return qs;
}


/**
 * Create a new entry in the transient aggregation table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param exchange_account_section exchange account to use
 * @param merchant_pub public key of the merchant receiving the transfer
 * @param wtid the raw wire transfer identifier to be used
 * @param kyc_requirement_row row in legitimization_requirements that need to be satisfied to continue, or 0 for none
 * @param total amount to be wired in the future
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_create_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *exchange_account_section,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t kyc_requirement_row,
  const struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (total),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint64 (&kyc_requirement_row),
    GNUNET_PQ_query_param_string (exchange_account_section),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "create_aggregation_transient",
                                             params);
}


/**
 * Find existing entry in the transient aggregation table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param merchant_pub public key of the merchant receiving the transfer
 * @param exchange_account_section exchange account to use
 * @param[out] wtid set to the raw wire transfer identifier to be used
 * @param[out] total existing amount to be wired in the future
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_select_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const char *exchange_account_section,
  struct TALER_WireTransferIdentifierRawP *wtid,
  struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (merchant_pub),
    GNUNET_PQ_query_param_string (exchange_account_section),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                 total),
    GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                          wtid),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_aggregation_transient",
                                                   params,
                                                   rs);
}


/**
 * Closure for #get_refunds_cb().
 */
struct FindAggregationTransientContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_TransientAggregationCallback cb;

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
  enum GNUNET_GenericReturnValue status;
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
get_transients_cb (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct FindAggregationTransientContext *srctx = cls;
  struct PostgresClosure *pg = srctx->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount;
    char *payto_uri;
    struct TALER_WireTransferIdentifierRawP wtid;
    struct TALER_MerchantPublicKeyP merchant_pub;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                            &merchant_pub),
      GNUNET_PQ_result_spec_auto_from_type ("wtid_raw",
                                            &wtid),
      GNUNET_PQ_result_spec_string ("payto_uri",
                                    &payto_uri),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_end
    };
    bool cont;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      srctx->status = GNUNET_SYSERR;
      return;
    }
    cont = srctx->cb (srctx->cb_cls,
                      payto_uri,
                      &wtid,
                      &merchant_pub,
                      &amount);
    GNUNET_free (payto_uri);
    if (! cont)
      break;
  }
}


/**
 * Find existing entry in the transient aggregation table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param cb function to call on each matching entry
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_find_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_TransientAggregationCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_end
  };
  struct FindAggregationTransientContext srctx = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "find_transient_aggregations",
                                             params,
                                             &get_transients_cb,
                                             &srctx);
  if (GNUNET_SYSERR == srctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Update existing entry in the transient aggregation table.
 * @a h_payto is only needed for query performance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param wtid the raw wire transfer identifier to update
 * @param kyc_requirement_row row in legitimization_requirements that need to be satisfied to continue, or 0 for none
 * @param total new total amount to be wired in the future
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_update_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t kyc_requirement_row,
  const struct TALER_Amount *total)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    TALER_PQ_query_param_amount (total),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_uint64 (&kyc_requirement_row),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "update_aggregation_transient",
                                             params);
}


/**
 * Delete existing entry in the transient aggregation table.
 * @a h_payto is only needed for query performance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param wtid the raw wire transfer identifier to update
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_delete_aggregation_transient (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_WireTransferIdentifierRawP *wtid)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "delete_aggregation_transient",
                                             params);
}


/**
 * Obtain information about deposits that are ready to be executed.  Such
 * deposits must not be marked as "done", the execution time must be
 * in the past, and the KYC status must be 'ok'.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_shard_row minimum shard row to select
 * @param end_shard_row maximum shard row to select (inclusive)
 * @param[out] merchant_pub set to the public key of a merchant with a ready deposit
 * @param[out] payto_uri set to the account of the merchant, to be freed by caller
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_ready_deposit (void *cls,
                            uint64_t start_shard_row,
                            uint64_t end_shard_row,
                            struct TALER_MerchantPublicKeyP *merchant_pub,
                            char **payto_uri)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now = {0};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_uint64 (&start_shard_row),
    GNUNET_PQ_query_param_uint64 (&end_shard_row),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                          merchant_pub),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  payto_uri),
    GNUNET_PQ_result_spec_end
  };

  now = GNUNET_TIME_absolute_round_down (GNUNET_TIME_absolute_get (),
                                         pg->aggregator_shift);
  GNUNET_assert (start_shard_row < end_shard_row);
  GNUNET_assert (end_shard_row <= INT32_MAX);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Finding ready deposits by deadline %s (%llu)\n",
              GNUNET_TIME_absolute2s (now),
              (unsigned long long) now.abs_value_us);
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "deposits_get_ready",
                                                   params,
                                                   rs);
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
  struct TALER_PaytoHashP h_payto;
  enum GNUNET_DB_QueryStatus qs;

  qs = setup_wire_target (pg,
                          deposit->receiver_wire_account,
                          &h_payto);
  if (qs < 0)
    return qs;
  if (GNUNET_TIME_timestamp_cmp (deposit->wire_deadline,
                                 <,
                                 deposit->refund_deadline))
  {
    GNUNET_break (0);
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
add_coin_purse_deposit (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_PurseDepositListEntry *deposit;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    chc->have_deposit_or_melt = true;
    deposit = GNUNET_new (struct TALER_EXCHANGEDB_PurseDepositListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &deposit->amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                     &deposit->deposit_fee),
        GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                              &deposit->purse_pub),
        GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_string ("partner_base_url",
                                        &deposit->exchange_base_url),
          NULL),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &deposit->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &deposit->h_age_commitment),
        GNUNET_PQ_result_spec_bool ("refunded",
                                    &deposit->refunded),
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
      deposit->no_age_commitment = GNUNET_is_zero (&deposit->h_age_commitment);
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_PURSE_DEPOSIT;
    tl->details.purse_deposit = deposit;
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
 * @param[out] tlp set to list of transactions, NULL if coin is fresh
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_get_coin_transactions (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_EXCHANGEDB_TransactionList **tlp)
{
  struct PostgresClosure *pg = cls;
  static const struct Work work[] = {
    /** #TALER_EXCHANGEDB_TT_DEPOSIT */
    { "get_deposit_with_coin_pub",
      &add_coin_deposit },
    /** #TALER_EXCHANGEDB_TT_MELT */
    { "get_refresh_session_by_coin",
      &add_coin_melt },
    /** #TALER_EXCHANGEDB_TT_PURSE_DEPOSIT */
    { "get_purse_deposit_by_coin_pub",
      &add_coin_purse_deposit },
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
  struct CoinHistoryContext chc = {
    .head = NULL,
    .coin_pub = coin_pub,
    .pg = pg,
    .db_cls = cls
  };

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

  memset (kyc,
          0,
          sizeof (*kyc));
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
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint64 ("legitimization_requirement_serial_id",
                                      &kyc->requirement_row),
        NULL),
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

      if (0 == kyc->requirement_row)
        kyc->ok = true; /* technically: unknown */
      TALER_merchant_wire_signature_hash (payto_uri,
                                          &wire_salt,
                                          &wh);
      GNUNET_PQ_cleanup_result (rs);
      if (0 !=
          GNUNET_memcmp (&wh,
                         h_wire))
        return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
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
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_subtract (
          GNUNET_TIME_absolute_get (),
          GNUNET_TIME_UNIT_YEARS));
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
 * @param start_date when does the fees go into effect
 * @param end_date when does the fees end being valid
 * @param fees how high is are the global fees
 * @param purse_timeout when do purses time out
 * @param kyc_timeout when do reserves without KYC time out
 * @param history_expiration how long are account histories preserved
 * @param purse_account_limit how many purses are free per account
 * @param master_sig signature over the above by the exchange master key
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
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_PaytoHashP h_payto;

  TALER_payto_hash (receiver_account,
                    &h_payto);
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
      (qs = postgres_reserves_get (cls,
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting READ COMMITTED DEFERRED transaction `%s'\n",
              pg->transaction_name);
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
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute ("SET search_path TO exchange;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
    struct GNUNET_PQ_PreparedStatement ps[] = {
      /* Used in #postgres_gc() */
      GNUNET_PQ_make_prepare ("run_gc",
                              "CALL"
                              " exchange_do_gc"
                              " ($1,$2);"),
      GNUNET_PQ_PREPARED_STATEMENT_END
    };

    conn = GNUNET_PQ_connect_with_cfg (pg->cfg,
                                       "exchangedb-postgres",
                                       NULL,
                                       es,
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
  enum GNUNET_GenericReturnValue status;
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
    enum GNUNET_GenericReturnValue ret;

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
 * Closure for #purse_deposit_serial_helper_cb().
 */
struct PurseDepositSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseDepositCallback cb;

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
 * @param cls closure of type `struct DepositSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_deposit_serial_helper_cb (void *cls,
                                PGresult *result,
                                unsigned int num_results)
{
  struct PurseDepositSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_PurseDeposit deposit = {
      .exchange_base_url = NULL
    };
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    uint32_t flags32;
    struct TALER_ReservePublicKeyP reserve_pub;
    bool not_merged = false;
    struct TALER_Amount purse_balance;
    struct TALER_Amount purse_total;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &deposit.amount),
      TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                   &purse_balance),
      TALER_PQ_RESULT_SPEC_AMOUNT ("total",
                                   &purse_total),
      TALER_PQ_RESULT_SPEC_AMOUNT ("deposit_fee",
                                   &deposit.deposit_fee),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("partner_base_url",
                                      &deposit.exchange_base_url),
        NULL),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &reserve_pub),
        &not_merged),
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &deposit.purse_pub),
      GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                            &deposit.coin_sig),
      GNUNET_PQ_result_spec_uint32 ("flags",
                                    &flags32),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &deposit.coin_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                              &deposit.h_age_commitment),
        &deposit.no_age_commitment),
      GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

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
                   &deposit,
                   not_merged ? NULL : &reserve_pub,
                   (enum TALER_WalletAccountMergeFlags) flags32,
                   &purse_balance,
                   &purse_total,
                   &denom_pub);
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
postgres_select_purse_deposits_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_PurseDepositCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PurseDepositSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_deposits_incr",
                                             params,
                                             &purse_deposit_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #account_merge_serial_helper_cb().
 */
struct AccountMergeSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_AccountMergeCallback cb;

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
 * @param cls closure of type `struct AccountMergeSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
account_merge_serial_helper_cb (void *cls,
                                PGresult *result,
                                unsigned int num_results)
{
  struct AccountMergeSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_PurseContractPublicKeyP purse_pub;
    struct TALER_PrivateContractHashP h_contract_terms;
    struct GNUNET_TIME_Timestamp purse_expiration;
    struct TALER_Amount amount;
    uint32_t min_age;
    uint32_t flags32;
    enum TALER_WalletAccountMergeFlags flags;
    struct TALER_Amount purse_fee;
    struct GNUNET_TIME_Timestamp merge_timestamp;
    struct TALER_ReserveSignatureP reserve_sig;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount),
      TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                   &purse_fee),
      GNUNET_PQ_result_spec_uint32 ("flags",
                                    &flags32),
      GNUNET_PQ_result_spec_uint32 ("age_limit",
                                    &min_age),
      GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                       &purse_expiration),
      GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                       &merge_timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                            &h_contract_terms),
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_uint64 ("account_merge_request_serial_id",
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
      dsc->status = GNUNET_SYSERR;
      return;
    }
    flags = (enum TALER_WalletAccountMergeFlags) flags32;
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   &reserve_pub,
                   &purse_pub,
                   &h_contract_terms,
                   purse_expiration,
                   &amount,
                   min_age,
                   flags,
                   &purse_fee,
                   merge_timestamp,
                   &reserve_sig);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select account merges above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_account_merges_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_AccountMergeCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct AccountMergeSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_account_merge_incr",
                                             params,
                                             &account_merge_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #purse_deposit_serial_helper_cb().
 */
struct PurseMergeSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseMergeCallback cb;

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
 * @param cls closure of type `struct PurseMergeSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_merges_serial_helper_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct PurseMergeSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    char *partner_base_url = NULL;
    struct TALER_Amount amount;
    struct TALER_Amount balance;
    uint32_t flags32;
    enum TALER_WalletAccountMergeFlags flags;
    struct TALER_PurseMergePublicKeyP merge_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_PurseMergeSignatureP merge_sig;
    struct TALER_PurseContractPublicKeyP purse_pub;
    struct GNUNET_TIME_Timestamp merge_timestamp;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount),
      TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                   &balance),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_string ("partner_base_url",
                                      &partner_base_url),
        NULL),
      GNUNET_PQ_result_spec_uint32 ("flags",
                                    &flags32),
      GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                       &merge_timestamp),
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("merge_sig",
                                            &merge_sig),
      GNUNET_PQ_result_spec_auto_from_type ("merge_pub",
                                            &merge_pub),
      GNUNET_PQ_result_spec_uint64 ("purse_merge_request_serial_id",
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
      dsc->status = GNUNET_SYSERR;
      return;
    }
    flags = (enum TALER_WalletAccountMergeFlags) flags32;
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   partner_base_url,
                   &amount,
                   &balance,
                   flags,
                   &merge_pub,
                   &reserve_pub,
                   &merge_sig,
                   &purse_pub,
                   merge_timestamp);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select purse merges deposits above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_merges_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_PurseMergeCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PurseMergeSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_merge_incr",
                                             params,
                                             &purse_merges_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #purse_deposit_serial_helper_cb().
 */
struct HistoryRequestSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_HistoryRequestCallback cb;

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
 * @param cls closure of type `struct HistoryRequestSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
history_request_serial_helper_cb (void *cls,
                                  PGresult *result,
                                  unsigned int num_results)
{
  struct HistoryRequestSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    uint64_t rowid;
    struct TALER_Amount history_fee;
    struct GNUNET_TIME_Timestamp ts;
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_ReserveSignatureP reserve_sig;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                   &history_fee),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                            &reserve_pub),
      GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                            &reserve_sig),
      GNUNET_PQ_result_spec_uint64 ("history_request_serial_id",
                                    &rowid),
      GNUNET_PQ_result_spec_timestamp ("request_timestamp",
                                       &ts),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

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
                   &history_fee,
                   ts,
                   &reserve_pub,
                   &reserve_sig);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select history requests above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_history_requests_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_HistoryRequestCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct HistoryRequestSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_history_requests_incr",
                                             params,
                                             &history_request_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #purse_refund_serial_helper_cb().
 */
struct PurseRefundSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseRefundCallback cb;

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
 * @param cls closure of type `struct PurseRefundSerialContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_refund_serial_helper_cb (void *cls,
                               PGresult *result,
                               unsigned int num_results)
{
  struct PurseRefundSerialContext *dsc = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_PurseContractPublicKeyP purse_pub;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
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
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   &purse_pub);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select purse refunds above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_refunds_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_PurseRefundCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };
  struct PurseRefundSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_refunds_incr",
                                             params,
                                             &purse_refund_serial_helper_cb,
                                             &dsc);
  if (GNUNET_OK != dsc.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #purse_refund_coin_helper_cb().
 */
struct PurseRefundCoinContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseRefundCoinCallback cb;

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
 * @param cls closure of type `struct PurseRefundCoinContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
purse_refund_coin_helper_cb (void *cls,
                             PGresult *result,
                             unsigned int num_results)
{
  struct PurseRefundCoinContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_Amount amount_with_fee;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_DenominationPublicKey denom_pub;
    uint64_t rowid;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_result_spec_denom_pub ("denom_pub",
                                      &denom_pub),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &amount_with_fee),
      GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                            &coin_pub),
      GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
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
      dsc->status = GNUNET_SYSERR;
      return;
    }
    ret = dsc->cb (dsc->cb_cls,
                   rowid,
                   &amount_with_fee,
                   &coin_pub,
                   &denom_pub);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select coin affected by purse refund.
 *
 * @param cls closure
 * @param purse_pub purse that was refunded
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_deposits_by_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  TALER_EXCHANGEDB_PurseRefundCoinCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct PurseRefundCoinContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_deposits_by_purse",
                                             params,
                                             &purse_refund_coin_helper_cb,
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
    bool full_refund;
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
    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_uint64 (&rowid),
        GNUNET_PQ_query_param_end
      };
      struct TALER_Amount amount_with_fee;
      uint64_t s_f;
      uint64_t s_v;
      struct GNUNET_PQ_ResultSpec rs2[] = {
        GNUNET_PQ_result_spec_uint64 ("s_v",
                                      &s_v),
        GNUNET_PQ_result_spec_uint64 ("s_f",
                                      &s_f),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &amount_with_fee),
        GNUNET_PQ_result_spec_end
      };
      enum GNUNET_DB_QueryStatus qs;

      qs = GNUNET_PQ_eval_prepared_singleton_select (
        pg->conn,
        "test_refund_full",
        params,
        rs2);
      if (qs <= 0)
      {
        GNUNET_break (0);
        rsc->status = GNUNET_SYSERR;
        return;
      }
      /* normalize */
      s_v += s_f / TALER_AMOUNT_FRAC_BASE;
      s_f %= TALER_AMOUNT_FRAC_BASE;
      full_refund = (s_v >= amount_with_fee.value) &&
                    (s_f >= amount_with_fee.fraction);
    }
    ret = rsc->cb (rsc->cb_cls,
                   rowid,
                   &denom_pub,
                   &refund.coin.coin_pub,
                   &refund.details.merchant_pub,
                   &refund.details.merchant_sig,
                   &refund.details.h_contract_terms,
                   refund.details.rtransaction_id,
                   full_refund,
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
 * @param cls a `struct GetWireFeesContext *`
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

  for (unsigned int retries = 0; retries<10; retries++)
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

      past = GNUNET_TIME_absolute_get ();
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
          struct GNUNET_TIME_Absolute now;
          struct GNUNET_PQ_QueryParam params[] = {
            GNUNET_PQ_query_param_string (job_name),
            GNUNET_PQ_query_param_absolute_time (&now),
            GNUNET_PQ_query_param_uint64 (start_row),
            GNUNET_PQ_query_param_uint64 (end_row),
            GNUNET_PQ_query_param_end
          };

          now = GNUNET_TIME_relative_to_absolute (delay);
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
      struct GNUNET_TIME_Absolute now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&now),
        GNUNET_PQ_query_param_uint64 (start_row),
        GNUNET_PQ_query_param_uint64 (end_row),
        GNUNET_PQ_query_param_end
      };

      now = GNUNET_TIME_relative_to_absolute (delay);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying to claim shard (%llu-%llu]\n",
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
 * Function called to abort work on a shard.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to abort a word shard for
 * @param start_row inclusive start row of the shard
 * @param end_row exclusive end row of the shard
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_abort_shard (void *cls,
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

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "abort_shard",
                                             params);
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
      struct GNUNET_TIME_Absolute now;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_string (job_name),
        GNUNET_PQ_query_param_absolute_time (&now),
        GNUNET_PQ_query_param_uint32 (start_row),
        GNUNET_PQ_query_param_uint32 (end_row),
        GNUNET_PQ_query_param_end
      };

      *end_row = GNUNET_MIN (shard_limit,
                             *start_row + shard_size - 1);
      now = GNUNET_TIME_absolute_get ();
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
enum GNUNET_GenericReturnValue
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
 * (age-restriction, peer2peer, ...).  After successful storage of the
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
  struct GNUNET_PQ_QueryParam pcfg =
    (NULL == config || 0 == *config)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (config);
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
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("config",
                                    config),
      &is_null),
    GNUNET_PQ_result_spec_end
  };

  *config = NULL;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_extension_config",
                                                   params,
                                                   rs);
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (master_pub),
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    GNUNET_PQ_query_param_relative_time (&wad_frequency),
    TALER_PQ_query_param_amount (wad_fee),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_string (partner_base_url),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_partner",
                                             params);
}


/**
 * Function called to retrieve an encrypted contract.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub key to lookup the contract by
 * @param[out] pub_ckey set to the ephemeral DH used to encrypt the contract
 * @param[out] econtract_sig set to the signature over the encrypted contract
 * @param[out] econtract_size set to the number of bytes in @a econtract
 * @param[out] econtract set to the encrypted contract on success, to be freed by the caller
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_contract (void *cls,
                          const struct TALER_ContractDiffiePublicP *pub_ckey,
                          struct TALER_PurseContractPublicKeyP *purse_pub,
                          struct TALER_PurseContractSignatureP *econtract_sig,
                          size_t *econtract_size,
                          void **econtract)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (pub_ckey),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                          purse_pub),
    GNUNET_PQ_result_spec_auto_from_type ("contract_sig",
                                          econtract_sig),
    GNUNET_PQ_result_spec_variable_size ("e_contract",
                                         econtract,
                                         econtract_size),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_contract",
                                                   params,
                                                   rs);

}


/**
 * Function called to retrieve an encrypted contract.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub key to lookup the contract by
 * @param[out] econtract set to the encrypted contract on success, to be freed by the caller
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_contract_by_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_EncryptedContract *econtract)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("pub_ckey",
                                          &econtract->contract_pub),
    GNUNET_PQ_result_spec_auto_from_type ("contract_sig",
                                          &econtract->econtract_sig),
    GNUNET_PQ_result_spec_variable_size ("e_contract",
                                         &econtract->econtract,
                                         &econtract->econtract_size),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_contract_by_purse",
                                                   params,
                                                   rs);

}


/**
 * Function called to persist an encrypted contract associated with a reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub the purse the contract is associated with (must exist)
 * @param econtract the encrypted contract
 * @param[out] in_conflict set to true if @a econtract
 *             conflicts with an existing contract;
 *             in this case, the return value will be
 *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_contract (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_EncryptedContract *econtract,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (&econtract->contract_pub),
    GNUNET_PQ_query_param_fixed_size (econtract->econtract,
                                      econtract->econtract_size),
    GNUNET_PQ_query_param_auto_from_type (&econtract->econtract_sig),
    GNUNET_PQ_query_param_end
  };

  *in_conflict = false;
  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "insert_contract",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs)
    return qs;
  {
    struct TALER_EncryptedContract econtract2;

    qs = postgres_select_contract_by_purse (pg,
                                            purse_pub,
                                            &econtract2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (0 == GNUNET_memcmp (&econtract->contract_pub,
                              &econtract2.contract_pub)) &&
         (econtract2.econtract_size ==
          econtract->econtract_size) &&
         (0 == memcmp (econtract2.econtract,
                       econtract->econtract,
                       econtract->econtract_size)) )
    {
      GNUNET_free (econtract2.econtract);
      return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    GNUNET_free (econtract2.econtract);
    *in_conflict = true;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
}


/**
 * Function called to return meta data about a purse by the
 * purse public key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse
 * @param[out] merge_pub public key representing the merge capability
 * @param[out] purse_expiration when would an unmerged purse expire
 * @param[out] h_contract_terms contract associated with the purse
 * @param[out] age_limit the age limit for deposits into the purse
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
  uint32_t *age_limit,
  struct TALER_Amount *target_amount,
  struct TALER_Amount *balance,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("merge_pub",
                                          merge_pub),
    GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                     purse_expiration),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          h_contract_terms),
    GNUNET_PQ_result_spec_uint32 ("age_limit",
                                  age_limit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 target_amount),
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 balance),
    GNUNET_PQ_result_spec_auto_from_type ("purse_sig",
                                          purse_sig),
    GNUNET_PQ_result_spec_end
  };
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse_request",
                                                   params,
                                                   rs);
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
 * @param flags flags for the operation
 * @param purse_fee fee we are allowed to charge to the reserve (depending on @a flags)
 * @param amount target amount (with fees) to be put into the purse
 * @param purse_sig signature with @a purse_pub's private key affirming the above
 * @param[out] in_conflict set to true if the meta data
 *             conflicts with an existing purse;
 *             in this case, the return value will be
 *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
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
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *purse_fee,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractSignatureP *purse_sig,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Timestamp now = GNUNET_TIME_timestamp_get ();
  uint32_t flags32 = (uint32_t) flags;
  bool in_reserve_quota = (TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA
                           == (flags & TALER_WAMF_MERGE_MODE_MASK));
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (merge_pub),
    GNUNET_PQ_query_param_timestamp (&now),
    GNUNET_PQ_query_param_timestamp (&purse_expiration),
    GNUNET_PQ_query_param_auto_from_type (h_contract_terms),
    GNUNET_PQ_query_param_uint32 (&age_limit),
    GNUNET_PQ_query_param_uint32 (&flags32),
    GNUNET_PQ_query_param_bool (in_reserve_quota),
    TALER_PQ_query_param_amount (amount),
    TALER_PQ_query_param_amount (purse_fee),
    GNUNET_PQ_query_param_auto_from_type (purse_sig),
    GNUNET_PQ_query_param_end
  };

  *in_conflict = false;
  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "insert_purse_request",
                                           params);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs)
    return qs;
  {
    struct TALER_PurseMergePublicKeyP merge_pub2;
    struct GNUNET_TIME_Timestamp purse_expiration2;
    struct TALER_PrivateContractHashP h_contract_terms2;
    uint32_t age_limit2;
    struct TALER_Amount amount2;
    struct TALER_Amount balance;
    struct TALER_PurseContractSignatureP purse_sig2;

    qs = postgres_select_purse_request (pg,
                                        purse_pub,
                                        &merge_pub2,
                                        &purse_expiration2,
                                        &h_contract_terms2,
                                        &age_limit2,
                                        &amount2,
                                        &balance,
                                        &purse_sig2);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (age_limit2 == age_limit) &&
         (0 == TALER_amount_cmp (amount,
                                 &amount2)) &&
         (0 == GNUNET_memcmp (&h_contract_terms2,
                              h_contract_terms)) &&
         (0 == GNUNET_memcmp (&merge_pub2,
                              merge_pub)) )
    {
      return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    *in_conflict = true;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
}


/**
 * Function called to clean up one expired purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_time select purse expired after this time
 * @param end_time select purse expired before this time
 * @return transaction status code (#GNUNET_DB_STATUS_SUCCESS_NO_RESULTS if no purse expired in the given time interval).
 */
static enum GNUNET_DB_QueryStatus
postgres_expire_purse (
  void *cls,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Absolute end_time)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_absolute_time (&start_time),
    GNUNET_PQ_query_param_absolute_time (&end_time),
    GNUNET_PQ_query_param_end
  };
  bool found = false;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("found",
                                &found),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "call_expire_purse",
                                                 params,
                                                 rs);
  if (qs < 0)
    return qs;
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  return found
         ? GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
         : GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


/**
 * Function called to obtain information about a purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the new purse
 * @param[out] purse_expiration set to time when the purse will expire
 * @param[out] amount set to target amount (with fees) to be put into the purse
 * @param[out] deposited set to actual amount put into the purse so far
 * @param[out] h_contract_terms set to hash of the contract for the purse
 * @param[out] merge_timestamp set to time when the purse was merged, or NEVER if not
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_Amount *amount,
  struct TALER_Amount *deposited,
  struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp *merge_timestamp)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                     purse_expiration),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 amount),
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 deposited),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          h_contract_terms),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                       merge_timestamp),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  *merge_timestamp = GNUNET_TIME_UNIT_FOREVER_TS;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse",
                                                   params,
                                                   rs);
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
 * @param[out] age_limit the age limit for deposits into the purse
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
  uint32_t *age_limit,
  struct TALER_Amount *target_amount,
  struct TALER_Amount *balance,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (merge_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                          purse_pub),
    GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                     purse_expiration),
    GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                          h_contract_terms),
    GNUNET_PQ_result_spec_uint32 ("age_limit",
                                  age_limit),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 target_amount),
    TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                 balance),
    GNUNET_PQ_result_spec_auto_from_type ("purse_sig",
                                          purse_sig),
    GNUNET_PQ_result_spec_end
  };
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse_by_merge_pub",
                                                   params,
                                                   rs);
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
 * @param amount_minus_fee amount to add to the purse
 * @param[out] balance_ok set to false if the coin's
 *        remaining balance is below @a amount;
 *             in this case, the return value will be
 *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
 * @param[out] conflict set to true if the deposit failed due to a conflict (coin already spent,
 *             or deposited into this purse with a different amount)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_do_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  const struct TALER_Amount *amount_minus_fee,
  bool *balance_ok,
  bool *conflict)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp reserve_expiration;
  uint64_t partner_id = 0; /* FIXME #7271: WAD support... */
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&partner_id),
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_sig),
    TALER_PQ_query_param_amount (amount_minus_fee),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("conflict",
                                conflict),
    GNUNET_PQ_result_spec_end
  };

  reserve_expiration
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                  pg->legal_reserve_expiration_time));
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_purse_deposit",
                                                   params,
                                                   rs);
}


/**
 * Set the current @a balance in the purse
 * identified by @a purse_pub. Used by the auditor
 * to update the balance as calculated by the auditor.
 *
 * @param cls closure
 * @param purse_pub public key of a purse
 * @param balance new balance to store under the purse
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_set_purse_balance (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *balance)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    TALER_PQ_query_param_amount (balance),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "set_purse_balance",
                                             params);
}


/**
 * Function called to obtain a coin deposit data from
 * depositing the coin into a purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to credit
 * @param coin_pub coin to deposit (debit)
 * @param[out] amount set fraction of the coin's value that was deposited (with fee)
 * @param[out] h_denom_pub set to hash of denomination of the coin
 * @param[out] phac set to hash of age restriction on the coin
 * @param[out] coin_sig set to signature affirming the operation
 * @param[out] partner_url set to the URL of the partner exchange, or NULL for ourselves, must be freed by caller
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_purse_deposit (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_Amount *amount,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_AgeCommitmentHash *phac,
  struct TALER_CoinSpendSignatureP *coin_sig,
  char **partner_url)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                          h_denom_pub),
    GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                          phac),
    GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                          coin_sig),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                 amount),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("partner_base_url",
                                    partner_url),
      &is_null),
    GNUNET_PQ_result_spec_end
  };

  *partner_url = NULL;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse_deposit_by_coin_pub",
                                                   params,
                                                   rs);
}


/**
 * Function called to approve merging a purse into a
 * reserve by the respective purse merge key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to merge
 * @param merge_sig signature affirming the merge
 * @param merge_timestamp time of the merge
 * @param reserve_sig signature of the reserve affirming the merge
 * @param partner_url URL of the partner exchange, can be NULL if the reserves lives with us
 * @param reserve_pub public key of the reserve to credit
 * @param[out] no_partner set to true if @a partner_url is unknown
 * @param[out] no_balance set to true if the @a purse_pub is not paid up yet
 * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
  * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_do_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const char *partner_url,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *no_partner,
  bool *no_balance,
  bool *in_conflict)
{
  struct PostgresClosure *pg = cls;
  struct TALER_PaytoHashP h_payto;
  struct GNUNET_TIME_Timestamp expiration
    = GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_YEARS); /* FIXME: make this configurable? */
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (merge_sig),
    GNUNET_PQ_query_param_timestamp (&merge_timestamp),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    (NULL == partner_url)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (partner_url),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&h_payto),
    GNUNET_PQ_query_param_timestamp (&expiration),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("no_partner",
                                no_partner),
    GNUNET_PQ_result_spec_bool ("no_balance",
                                no_balance),
    GNUNET_PQ_result_spec_bool ("conflict",
                                in_conflict),
    GNUNET_PQ_result_spec_end
  };

  {
    char *payto_uri;

    payto_uri = TALER_reserve_make_payto (pg->exchange_url,
                                          reserve_pub);
    TALER_payto_hash (payto_uri,
                      &h_payto);
    GNUNET_free (payto_uri);
  }
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_purse_merge",
                                                   params,
                                                   rs);
}


/**
 * Function called insert request to merge a purse into a reserve by the
 * respective purse merge key. The purse must not have been merged into a
 * different reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to merge
 * @param merge_sig signature affirming the merge
 * @param merge_timestamp time of the merge
 * @param reserve_sig signature of the reserve affirming the merge
 * @param purse_fee amount to charge the reserve for the purse creation, NULL to use the quota
 * @param reserve_pub public key of the reserve to credit
 * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
 * @param[out] no_reserve set to true if @a reserve_pub is not a known reserve
 * @param[out] insufficient_funds set to true if @a reserve_pub has insufficient capacity to create another purse
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_do_reserve_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_Amount *purse_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *in_conflict,
  bool *no_reserve,
  bool *insufficient_funds)
{
  struct PostgresClosure *pg = cls;
  struct TALER_Amount zero_fee;
  struct TALER_PaytoHashP h_payto;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_auto_from_type (merge_sig),
    GNUNET_PQ_query_param_timestamp (&merge_timestamp),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    GNUNET_PQ_query_param_bool (NULL == purse_fee),
    TALER_PQ_query_param_amount (NULL == purse_fee
                                 ? &zero_fee
                                 : purse_fee),
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&h_payto),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("insufficient_funds",
                                insufficient_funds),
    GNUNET_PQ_result_spec_bool ("conflict",
                                in_conflict),
    GNUNET_PQ_result_spec_bool ("no_reserve",
                                no_reserve),
    GNUNET_PQ_result_spec_end
  };

  {
    char *payto_uri;

    payto_uri = TALER_reserve_make_payto (pg->exchange_url,
                                          reserve_pub);
    TALER_payto_hash (payto_uri,
                      &h_payto);
    GNUNET_free (payto_uri);
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &zero_fee));
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_reserve_purse",
                                                   params,
                                                   rs);
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
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (purse_pub),
    GNUNET_PQ_query_param_end
  };
  bool is_null;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("merge_sig",
                                          merge_sig),
    GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                          reserve_pub),
    GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                     merge_timestamp),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("partner_base_url",
                                    partner_url),
      &is_null),
    GNUNET_PQ_result_spec_end
  };

  *partner_url = NULL;
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "select_purse_merge",
                                                   params,
                                                   rs);
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
 * @param[out] balance_ok set to TRUE if the reserve balance
 *         was sufficient
 * @param[out] idempotent set to TRUE if the request is already in the DB
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_history_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *history_fee,
  bool *balance_ok,
  bool *idempotent)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (reserve_sig),
    GNUNET_PQ_query_param_timestamp (&request_timestamp),
    TALER_PQ_query_param_amount (history_fee),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("balance_ok",
                                balance_ok),
    GNUNET_PQ_result_spec_bool ("idempotent",
                                idempotent),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_history_request",
                                                   params,
                                                   rs);
}


/**
 * Function called to persist a request to drain profits.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wtid wire transfer ID to use
 * @param account_section account to drain
 * @param payto_uri account to wire funds to
 * @param request_timestamp when was the request made
 * @param amount amount to wire
 * @param master_sig signature affirming the operation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_drain_profit (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const char *account_section,
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_string (account_section),
    GNUNET_PQ_query_param_string (payto_uri),
    GNUNET_PQ_query_param_timestamp (&request_timestamp),
    TALER_PQ_query_param_amount (amount),
    GNUNET_PQ_query_param_auto_from_type (master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "drain_profit_insert",
                                             params);
}


/**
 * Get profit drain operation ready to execute.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param[out] serial set to serial ID of the entry
 * @param[out] wtid set set to wire transfer ID to use
 * @param[out] account_section set to  account to drain
 * @param[out] payto_uri set to account to wire funds to
 * @param[out] request_timestamp set to time of the signature
 * @param[out] amount set to amount to wire
 * @param[out] master_sig set to signature affirming the operation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_profit_drains_get_pending (
  void *cls,
  uint64_t *serial,
  struct TALER_WireTransferIdentifierRawP *wtid,
  char **account_section,
  char **payto_uri,
  struct GNUNET_TIME_Timestamp *request_timestamp,
  struct TALER_Amount *amount,
  struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("profit_drain_serial_id",
                                  serial),
    GNUNET_PQ_result_spec_auto_from_type ("wtid",
                                          wtid),
    GNUNET_PQ_result_spec_string ("account_section",
                                  account_section),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  payto_uri),
    GNUNET_PQ_result_spec_timestamp ("trigger_date",
                                     request_timestamp),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                 amount),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_ready_profit_drain",
                                                   params,
                                                   rs);
}


/**
 * Function called to get information about a profit drain event.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wtid wire transfer ID to look up drain event for
 * @param[out] serial set to serial ID of the entry
 * @param[out] account_section set to account to drain
 * @param[out] payto_uri set to account to wire funds to
 * @param[out] request_timestamp set to time of the signature
 * @param[out] amount set to amount to wire
 * @param[out] master_sig set to signature affirming the operation
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_get_drain_profit (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t *serial,
  char **account_section,
  char **payto_uri,
  struct GNUNET_TIME_Timestamp *request_timestamp,
  struct TALER_Amount *amount,
  struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (wtid),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("profit_drain_serial_id",
                                  serial),
    GNUNET_PQ_result_spec_string ("account_section",
                                  account_section),
    GNUNET_PQ_result_spec_string ("payto_uri",
                                  payto_uri),
    GNUNET_PQ_result_spec_timestamp ("trigger_date",
                                     request_timestamp),
    TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                 amount),
    GNUNET_PQ_result_spec_auto_from_type ("master_sig",
                                          master_sig),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_profit_drain",
                                                   params,
                                                   rs);
}


/**
 * Set profit drain operation to finished.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param serial serial ID of the entry to mark finished
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_profit_drains_set_finished (
  void *cls,
  uint64_t serial)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "drain_profit_set_finished",
                                             params);
}


/**
 * Insert KYC requirement for @a h_payto account into table.
 *
 * @param cls closure
 * @param provider_section provider that must be checked
 * @param h_payto account that must be KYC'ed
 * @param[out] requirement_row set to legitimization requirement row for this check
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_kyc_requirement_for_account (
  void *cls,
  const char *provider_section,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *requirement_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (provider_section),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("legitimization_requirement_serial_id",
                                  requirement_row),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "insert_legitimization_requirement",
    params,
    rs);
}


/**
 * Begin KYC requirement process.
 *
 * @param cls closure
 * @param h_payto account that must be KYC'ed
 * @param provider_section provider that must be checked
 * @param provider_account_id provider account ID
 * @param provider_legitimization_id provider legitimization ID
 * @param[out] process_row row the process is stored under
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_insert_kyc_requirement_process (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  uint64_t *process_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (provider_section),
    (NULL != provider_account_id)
    ? GNUNET_PQ_query_param_string (provider_account_id)
    : GNUNET_PQ_query_param_null (),
    (NULL != provider_legitimization_id)
    ? GNUNET_PQ_query_param_string (provider_legitimization_id)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("legitimization_process_serial_id",
                                  process_row),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "insert_legitimization_process",
    params,
    rs);
}


/**
 * Update KYC requirement check with provider-linkage and/or
 * expiration data.
 *
 * @param cls closure
 * @param process_row row to select by
 * @param provider_section provider that must be checked (technically redundant)
 * @param h_payto account that must be KYC'ed (helps access by shard, otherwise also redundant)
 * @param provider_account_id provider account ID
 * @param provider_legitimization_id provider legitimization ID
 * @param expiration how long is this KYC check set to be valid (in the past if invalid)
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_update_kyc_process_by_row (
  void *cls,
  uint64_t process_row,
  const char *provider_section,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&process_row),
    GNUNET_PQ_query_param_string (provider_section),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    (NULL != provider_account_id)
    ? GNUNET_PQ_query_param_string (provider_account_id)
    : GNUNET_PQ_query_param_null (),
    (NULL != provider_legitimization_id)
    ? GNUNET_PQ_query_param_string (provider_legitimization_id)
    : GNUNET_PQ_query_param_null (),
    GNUNET_PQ_query_param_absolute_time (&expiration),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_non_select (
    pg->conn,
    "update_legitimization_process",
    params);
  if (qs <= 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to update legitimization process: %d\n",
                qs);
    return qs;
  }
  if (GNUNET_TIME_absolute_is_future (expiration))
  {
    enum GNUNET_DB_QueryStatus qs2;
    struct TALER_KycCompletedEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
      .h_payto = *h_payto
    };
    uint32_t trigger_type = 1;
    struct GNUNET_PQ_QueryParam params2[] = {
      GNUNET_PQ_query_param_auto_from_type (h_payto),
      GNUNET_PQ_query_param_uint32 (&trigger_type),
      GNUNET_PQ_query_param_end
    };

    postgres_event_notify (pg,
                           &rep.header,
                           NULL,
                           0);
    qs2 = GNUNET_PQ_eval_prepared_non_select (
      pg->conn,
      "alert_kyc_status_change",
      params2);
    if (qs2 < 0)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to store KYC alert: %d\n",
                  qs2);
  }
  return qs;
}


/**
 * Lookup KYC requirement.
 *
 * @param cls closure
 * @param requirement_row identifies requirement to look up
 * @param[out] requirements provider that must be checked
 * @param[out] h_payto account that must be KYC'ed
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_kyc_requirement_by_row (
  void *cls,
  uint64_t requirement_row,
  char **requirements,
  struct TALER_PaytoHashP *h_payto)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&requirement_row),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("required_checks",
                                  requirements),
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_legitimization_requirement_by_row",
    params,
    rs);
}


/**
 * Lookup KYC provider meta data.
 *
 * @param cls closure
 * @param provider_section provider that must be checked
 * @param h_payto account that must be KYC'ed
 * @param[out] process_row row with the legitimization data
 * @param[out] expiration how long is this KYC check set to be valid (in the past if invalid)
 * @param[out] provider_account_id provider account ID
 * @param[out] provider_legitimization_id provider legitimization ID
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_lookup_kyc_process_by_account (
  void *cls,
  const char *provider_section,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *process_row,
  struct GNUNET_TIME_Absolute *expiration,
  char **provider_account_id,
  char **provider_legitimization_id)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_string (provider_section),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("legitimization_process_serial_id",
                                  process_row),
    GNUNET_PQ_result_spec_absolute_time ("expiration_time",
                                         expiration),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("provider_user_id",
                                    provider_account_id),
      NULL),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_string ("provider_legitimization_id",
                                    provider_legitimization_id),
      NULL),
    GNUNET_PQ_result_spec_end
  };

  *provider_account_id = NULL;
  *provider_legitimization_id = NULL;
  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "lookup_process_by_account",
    params,
    rs);
}


/**
 * Lookup an
 * @a h_payto by @a provider_legitimization_id.
 *
 * @param cls closure
 * @param provider_section
 * @param provider_legitimization_id legi to look up
 * @param[out] h_payto where to write the result
 * @param[out] process_row where to write the row of the entry
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
postgres_kyc_provider_account_lookup (
  void *cls,
  const char *provider_section,
  const char *provider_legitimization_id,
  struct TALER_PaytoHashP *h_payto,
  uint64_t *process_row)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_string (provider_section),
    GNUNET_PQ_query_param_string (provider_legitimization_id),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_auto_from_type ("h_payto",
                                          h_payto),
    GNUNET_PQ_result_spec_uint64 ("legitimization_process_serial_id",
                                  process_row),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (
    pg->conn,
    "get_wire_target_by_legitimization_id",
    params,
    rs);
}


/**
 * Closure for #get_wire_fees_cb().
 */
struct GetLegitimizationsContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_SatisfiedProviderCallback cb;

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
 * @param cls a `struct GetLegitimizationsContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_legitimizations_cb (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct GetLegitimizationsContext *ctx = cls;

  for (unsigned int i = 0; i < num_results; i++)
  {
    char *provider_section;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_string ("provider_section",
                                    &provider_section),
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
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Found satisfied LEGI: %s\n",
                provider_section);
    ctx->cb (ctx->cb_cls,
             provider_section);
    GNUNET_PQ_cleanup_result (rs);
  }
}


/**
 * Call us on KYC processes satisfied for the given
 * account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param spc function to call for each satisfied KYC process
 * @param spc_cls closure for @a spc
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_satisfied_kyc_processes (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_SatisfiedProviderCallback spc,
  void *spc_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Absolute now
    = GNUNET_TIME_absolute_get ();
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&now),
    GNUNET_PQ_query_param_end
  };
  struct GetLegitimizationsContext ctx = {
    .cb = spc,
    .cb_cls = spc_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "get_satisfied_legitimizations",
    params,
    &get_legitimizations_cb,
    &ctx);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Satisfied LEGI check returned %d\n",
              qs);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Closure for #get_kyc_amounts_cb().
 */
struct KycAmountCheckContext
{
  /**
   * Function to call per result.
   */
  TALER_EXCHANGEDB_KycAmountCallback cb;

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
 * @param cls a `struct KycAmountCheckContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
get_kyc_amounts_cb (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct KycAmountCheckContext *ctx = cls;
  struct PostgresClosure *pg = ctx->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct GNUNET_TIME_Absolute date;
    struct TALER_Amount amount;
    struct GNUNET_PQ_ResultSpec rs[] = {
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                   &amount),
      GNUNET_PQ_result_spec_absolute_time ("date",
                                           &date),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_GenericReturnValue ret;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    ret = ctx->cb (ctx->cb_cls,
                   &amount,
                   date);
    GNUNET_PQ_cleanup_result (rs);
    switch (ret)
    {
    case GNUNET_OK:
      continue;
    case GNUNET_NO:
      break;
    case GNUNET_SYSERR:
      ctx->status = GNUNET_SYSERR;
      break;
    }
    break;
  }
}


/**
 * Call @a kac on withdrawn amounts after @a time_limit which are relevant
 * for a KYC trigger for a the (debited) account identified by @a h_payto.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param time_limit oldest transaction that could be relevant
 * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
 * @param kac_cls closure for @a kac
 * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
 */
static enum GNUNET_DB_QueryStatus
postgres_select_withdraw_amounts_for_kyc_check (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute time_limit,
  TALER_EXCHANGEDB_KycAmountCallback kac,
  void *kac_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&time_limit),
    GNUNET_PQ_query_param_end
  };
  struct KycAmountCheckContext ctx = {
    .cb = kac,
    .cb_cls = kac_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "select_kyc_relevant_withdraw_events",
    params,
    &get_kyc_amounts_cb,
    &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Call @a kac on deposited amounts after @a time_limit which are relevant for a
 * KYC trigger for a the (credited) account identified by @a h_payto.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param time_limit oldest transaction that could be relevant
 * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
 * @param kac_cls closure for @a kac
 * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
 */
static enum GNUNET_DB_QueryStatus
postgres_select_aggregation_amounts_for_kyc_check (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute time_limit,
  TALER_EXCHANGEDB_KycAmountCallback kac,
  void *kac_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&time_limit),
    GNUNET_PQ_query_param_end
  };
  struct KycAmountCheckContext ctx = {
    .cb = kac,
    .cb_cls = kac_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "select_kyc_relevant_aggregation_events",
    params,
    &get_kyc_amounts_cb,
    &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


/**
 * Call @a kac on merged reserve amounts after @a time_limit which are relevant for a
 * KYC trigger for a the wallet identified by @a h_payto.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param time_limit oldest transaction that could be relevant
 * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
 * @param kac_cls closure for @a kac
 * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
 */
static enum GNUNET_DB_QueryStatus
postgres_select_merge_amounts_for_kyc_check (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute time_limit,
  TALER_EXCHANGEDB_KycAmountCallback kac,
  void *kac_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_absolute_time (&time_limit),
    GNUNET_PQ_query_param_end
  };
  struct KycAmountCheckContext ctx = {
    .cb = kac,
    .cb_cls = kac_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (
    pg->conn,
    "select_kyc_relevant_merge_events",
    params,
    &get_kyc_amounts_cb,
    &ctx);
  if (GNUNET_OK != ctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
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
  unsigned long long dpl;

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
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchangedb",
                                           "AGGREGATOR_SHIFT",
                                           &pg->aggregator_shift))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "exchangedb",
                               "AGGREGATOR_SHIFT");
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "exchangedb",
                                             "DEFAULT_PURSE_LIMIT",
                                             &dpl))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               "exchangedb",
                               "DEFAULT_PURSE_LIMIT");
    pg->def_purse_limit = 1;
  }
  else
  {
    pg->def_purse_limit = (uint32_t) dpl;
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
  plugin->create_shard_tables = &postgres_create_shard_tables;
  plugin->setup_partitions = &postgres_setup_partitions;
  plugin->setup_foreign_servers = &postgres_setup_foreign_servers;
  plugin->start = &postgres_start;
  plugin->start_read_committed = &postgres_start_read_committed;
  plugin->start_read_only = &postgres_start_read_only;
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
  plugin->reserves_get = &postgres_reserves_get;
  plugin->reserves_get_origin = &postgres_reserves_get_origin;
  plugin->drain_kyc_alert = &postgres_drain_kyc_alert;
  plugin->reserves_in_insert = &postgres_reserves_in_insert;
  plugin->get_withdraw_info = &postgres_get_withdraw_info;
  plugin->do_withdraw = &postgres_do_withdraw;
  plugin->do_batch_withdraw = &postgres_do_batch_withdraw;
  plugin->do_batch_withdraw_insert = &postgres_do_batch_withdraw_insert;
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
  plugin->aggregate = &postgres_aggregate;
  plugin->create_aggregation_transient
    = &postgres_create_aggregation_transient;
  plugin->select_aggregation_transient
    = &postgres_select_aggregation_transient;
  plugin->find_aggregation_transient
    = &postgres_find_aggregation_transient;
  plugin->update_aggregation_transient
    = &postgres_update_aggregation_transient;
  plugin->delete_aggregation_transient
    = &postgres_delete_aggregation_transient;
  plugin->get_ready_deposit = &postgres_get_ready_deposit;
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
  plugin->select_purse_deposits_above_serial_id
    = &postgres_select_purse_deposits_above_serial_id;
  plugin->select_account_merges_above_serial_id
    = &postgres_select_account_merges_above_serial_id;
  plugin->select_purse_merges_above_serial_id
    = &postgres_select_purse_merges_above_serial_id;
  plugin->select_history_requests_above_serial_id
    = &postgres_select_history_requests_above_serial_id;
  plugin->select_purse_refunds_above_serial_id
    = &postgres_select_purse_refunds_above_serial_id;
  plugin->select_purse_deposits_by_purse
    = &postgres_select_purse_deposits_by_purse;
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
  plugin->begin_shard
    = &postgres_begin_shard;
  plugin->abort_shard
    = &postgres_abort_shard;
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
  plugin->select_contract_by_purse
    = &postgres_select_contract_by_purse;
  plugin->insert_purse_request
    = &postgres_insert_purse_request;
  plugin->select_purse_request
    = &postgres_select_purse_request;
  plugin->expire_purse
    = &postgres_expire_purse;
  plugin->select_purse
    = &postgres_select_purse;
  plugin->select_purse_by_merge_pub
    = &postgres_select_purse_by_merge_pub;
  plugin->do_purse_deposit
    = &postgres_do_purse_deposit;
  plugin->set_purse_balance
    = &postgres_set_purse_balance;
  plugin->get_purse_deposit
    = &postgres_get_purse_deposit;
  plugin->do_purse_merge
    = &postgres_do_purse_merge;
  plugin->do_reserve_purse
    = &postgres_do_reserve_purse;
  plugin->select_purse_merge
    = &postgres_select_purse_merge;
  plugin->insert_history_request
    = &postgres_insert_history_request;
  plugin->insert_drain_profit
    = &postgres_insert_drain_profit;
  plugin->profit_drains_get_pending
    = &postgres_profit_drains_get_pending;
  plugin->get_drain_profit
    = &postgres_get_drain_profit;
  plugin->profit_drains_set_finished
    = &postgres_profit_drains_set_finished;
  plugin->insert_kyc_requirement_for_account
    = &postgres_insert_kyc_requirement_for_account;
  plugin->insert_kyc_requirement_process
    = &postgres_insert_kyc_requirement_process;
  plugin->update_kyc_process_by_row
    = &postgres_update_kyc_process_by_row;
  plugin->lookup_kyc_requirement_by_row
    = &postgres_lookup_kyc_requirement_by_row;
  plugin->lookup_kyc_process_by_account
    = &postgres_lookup_kyc_process_by_account;
  plugin->kyc_provider_account_lookup
    = &postgres_kyc_provider_account_lookup;
  plugin->select_satisfied_kyc_processes
    = &postgres_select_satisfied_kyc_processes;
  plugin->select_withdraw_amounts_for_kyc_check
    = &postgres_select_withdraw_amounts_for_kyc_check;
  plugin->select_aggregation_amounts_for_kyc_check
    = &postgres_select_aggregation_amounts_for_kyc_check;
  plugin->select_merge_amounts_for_kyc_check
    = &postgres_select_merge_amounts_for_kyc_check;
  /* NEW style, sort alphabetically! */
  plugin->do_reserve_open
    = &TEH_PG_do_reserve_open;
  plugin->get_expired_reserves
    = &TEH_PG_get_expired_reserves;
  plugin->get_unfinished_close_requests
    = &TEH_PG_get_unfinished_close_requests;
  plugin->insert_records_by_table
    = &TEH_PG_insert_records_by_table;
  plugin->insert_reserve_open_deposit
    = &TEH_PG_insert_reserve_open_deposit;
  plugin->insert_close_request
    = &TEH_PG_insert_close_request;
  plugin->iterate_reserve_close_info
    = &TEH_PG_iterate_reserve_close_info;
  plugin->iterate_kyc_reference
    = &TEH_PG_iterate_kyc_reference;
  plugin->lookup_records_by_table
    = &TEH_PG_lookup_records_by_table;
  plugin->lookup_serial_by_table
    = &TEH_PG_lookup_serial_by_table;
  plugin->select_reserve_close_info
    = &TEH_PG_select_reserve_close_info;

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
