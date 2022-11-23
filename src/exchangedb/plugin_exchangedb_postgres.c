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
#include "plugin_exchangedb_common.h"
#include "pg_delete_aggregation_transient.h"
#include "pg_get_link_data.h"
#include "pg_helper.h"
#include "pg_do_reserve_open.h"
#include "pg_do_withdraw.h"
#include "pg_get_coin_transactions.h"
#include "pg_get_expired_reserves.h"
#include "pg_get_purse_request.h"
#include "pg_get_reserve_history.h"
#include "pg_get_unfinished_close_requests.h"
#include "pg_insert_close_request.h"
#include "pg_insert_records_by_table.h"
#include "pg_insert_reserve_open_deposit.h"
#include "pg_iterate_kyc_reference.h"
#include "pg_iterate_reserve_close_info.h"
#include "pg_lookup_records_by_table.h"
#include "pg_lookup_serial_by_table.h"
#include "pg_select_account_merges_above_serial_id.h"
#include "pg_select_all_purse_decisions_above_serial_id.h"
#include "pg_select_purse.h"
#include "pg_select_purse_deposits_above_serial_id.h"
#include "pg_select_purse_merges_above_serial_id.h"
#include "pg_select_purse_requests_above_serial_id.h"
#include "pg_select_reserve_close_info.h"
#include "pg_select_reserve_closed_above_serial_id.h"
#include "pg_select_reserve_open_above_serial_id.h"
#include <poll.h>
#include <pthread.h>
#include <libpq-fe.h>

/**WHAT I ADD**/
#include "pg_insert_purse_request.h"
#include "pg_iterate_active_signkeys.h"
#include "pg_preflight.h"
#include "pg_commit.h"
#include "pg_create_shard_tables.h"
#include "pg_insert_aggregation_tracking.h"
#include "pg_drop_tables.h"
#include "pg_setup_partitions.h"
#include "pg_select_satisfied_kyc_processes.h"
#include "pg_select_aggregation_amounts_for_kyc_check.h"
#include "pg_kyc_provider_account_lookup.h"
#include "pg_lookup_kyc_requirement_by_row.h"
#include "pg_insert_kyc_requirement_for_account.h"
#include "pg_lookup_kyc_process_by_account.h"
#include "pg_update_kyc_process_by_row.h"
#include "pg_insert_kyc_requirement_process.h"
#include "pg_select_withdraw_amounts_for_kyc_check.h"
#include "pg_select_merge_amounts_for_kyc_check.h"
#include "pg_profit_drains_set_finished.h"
#include "pg_profit_drains_get_pending.h"
#include "pg_get_drain_profit.h"
#include "pg_get_purse_deposit.h"
#include "pg_insert_contract.h"
#include "pg_select_contract.h"
#include "pg_select_purse_merge.h"
#include "pg_select_contract_by_purse.h"
#include "pg_insert_drain_profit.h"
#include "pg_do_reserve_purse.h"
#include "pg_lookup_global_fee_by_time.h"
#include "pg_do_purse_deposit.h"
#include "pg_activate_signing_key.h"
#include "pg_update_auditor.h"
#include "pg_begin_revolving_shard.h"
#include "pg_get_extension_manifest.h"
#include "pg_insert_history_request.h"
#include "pg_do_purse_merge.h"
#include "pg_start_read_committed.h"
#include "pg_start_read_only.h"
#include "pg_insert_denomination_info.h"
#include "pg_do_batch_withdraw_insert.h"
#include "pg_lookup_wire_fee_by_time.h"
#include "pg_start.h"
#include "pg_rollback.h"
#include "pg_create_tables.h"
#include "pg_setup_foreign_servers.h"
#include "pg_event_listen.h"
#include "pg_event_listen_cancel.h"
#include "pg_event_notify.h"
#include "pg_get_denomination_info.h"
#include "pg_iterate_denomination_info.h"
#include "pg_iterate_denominations.h"
#include "pg_iterate_active_auditors.h"
#include "pg_iterate_auditor_denominations.h"
#include "pg_reserves_get.h"
#include "pg_reserves_get_origin.h"
#include "pg_drain_kyc_alert.h"
#include "pg_reserves_in_insert.h"
#include "pg_get_withdraw_info.h"
#include "pg_do_batch_withdraw.h"
#include "pg_get_policy_details.h"
#include "pg_persist_policy_details.h"
#include "pg_do_deposit.h"
#include "pg_add_policy_fulfillment_proof.h"
#include "pg_do_melt.h"
#include "pg_do_refund.h"
#include "pg_do_recoup.h"
#include "pg_do_recoup_refresh.h"
#include "pg_get_reserve_balance.h"
#include "pg_count_known_coins.h"
#include "pg_ensure_coin_known.h"
#include "pg_get_known_coin.h"
#include "pg_get_coin_denomination.h"
#include "pg_have_deposit2.h"
#include "pg_aggregate.h"
#include "pg_create_aggregation_transient.h"
#include "pg_select_aggregation_transient.h"
#include "pg_find_aggregation_transient.h"
#include "pg_update_aggregation_transient.h"
#include "pg_get_ready_deposit.h"
#include "pg_insert_deposit.h"
#include "pg_insert_refund.h"
#include "pg_select_refunds_by_coin.h"
#include "pg_get_melt.h"
#include "pg_insert_refresh_reveal.h"
#include "pg_get_refresh_reveal.h"
#include "pg_lookup_wire_transfer.h"
#include "pg_lookup_transfer_by_deposit.h"
#include "pg_insert_wire_fee.h"
#include "pg_insert_global_fee.h"
#include "pg_get_wire_fee.h"
#include "pg_get_global_fee.h"
#include "pg_get_global_fees.h"
#include "pg_insert_reserve_closed.h"
#include "pg_wire_prepare_data_insert.h"
#include "pg_wire_prepare_data_mark_finished.h"
#include "pg_wire_prepare_data_mark_failed.h"
#include "pg_wire_prepare_data_get.h"
#include "pg_start_deferred_wire_out.h"
#include "pg_store_wire_transfer_out.h"
#include "pg_gc.h"
#include "pg_select_deposits_above_serial_id.h"
#include "pg_select_history_requests_above_serial_id.h"
#include "pg_select_purse_decisions_above_serial_id.h"
#include "pg_select_purse_deposits_by_purse.h"
#include "pg_select_refreshes_above_serial_id.h"
#include "pg_select_refunds_above_serial_id.h"
#include "pg_select_reserves_in_above_serial_id.h"
#include "pg_select_reserves_in_above_serial_id_by_account.h"
#include "pg_select_withdrawals_above_serial_id.h"
#include "pg_select_wire_out_above_serial_id.h"
#include "pg_select_wire_out_above_serial_id_by_account.h"
#include "pg_select_recoup_above_serial_id.h"
#include "pg_select_recoup_refresh_above_serial_id.h"
#include "pg_get_reserve_by_h_blind.h"
#include "pg_get_old_coin_by_h_blind.h"
#include "pg_insert_denomination_revocation.h"
#include "pg_get_denomination_revocation.h"
#include "pg_select_deposits_missing_wire.h"
#include "pg_lookup_auditor_timestamp.h"
#include "pg_lookup_auditor_status.h"
#include "pg_insert_auditor.h"
#include "pg_lookup_wire_timestamp.h"
#include "pg_insert_wire.h"
#include "pg_update_wire.h"
#include "pg_get_wire_accounts.h"
#include "pg_get_wire_fees.h"
#include "pg_insert_signkey_revocation.h"
#include "pg_lookup_signkey_revocation.h"
#include "pg_lookup_denomination_key.h"
#include "pg_insert_auditor_denom_sig.h"
#include "pg_select_auditor_denom_sig.h"
#include "pg_add_denomination_key.h"
#include "pg_lookup_signing_key.h"
#include "pg_begin_shard.h"
#include "pg_abort_shard.h"
#include "pg_complete_shard.h"
#include "pg_release_revolving_shard.h"
#include "pg_delete_shard_locks.h"
#include "pg_set_extension_manifest.h"
#include "pg_insert_partner.h"
#include "pg_expire_purse.h"
#include "pg_select_purse_by_merge_pub.h"
#include "pg_set_purse_balance.h"
#include "pg_reserves_update.h"
#include "pg_setup_wire_target.h"
#include "pg_compute_shard.h"
#include "pg_batch_reserves_in_insert.h"
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
 * Initialize prepared statements for @a pg.
 *
 * @param[in,out] pg connection to initialize
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
prepare_statements (struct PostgresClosure *pg)
{
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare (
      "get_kyc_h_payto",
      "SELECT"
      " wire_target_h_payto"
      " FROM wire_targets"
      " WHERE wire_target_h_payto=$1"
      " LIMIT 1;"),


    /* Used in #postgres_ensure_coin_known() */
    GNUNET_PQ_make_prepare (
      "get_known_coin_dh",
      "SELECT"
      " denominations.denom_pub_hash"
      " FROM known_coins"
      " JOIN denominations USING (denominations_serial)"
      " WHERE coin_pub=$1;"),
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
    /* Used in #postgres_do_account_merge() */
    GNUNET_PQ_make_prepare (
      "call_account_merge",
      "SELECT 1"
      " FROM exchange_do_account_merge"
      "  ($1, $2, $3);"),
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
enum GNUNET_GenericReturnValue
TEH_PG_internal_setup (struct PostgresClosure *pg,
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





/* Get the details of a policy, referenced by its hash code
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param hc The hash code under which the details to a particular policy should be found
 * @param[out] details The found details
 * @return query execution status
 * */
static enum GNUNET_DB_QueryStatus
postgres_get_policy_details (
  void *cls,
  const struct GNUNET_HashCode *hc,
  struct TALER_PolicyDetails *details)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (hc),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("deadline",
                                     &details->deadline),
    TALER_PQ_RESULT_SPEC_AMOUNT ("commitment",
                                 &details->commitment),
    TALER_PQ_RESULT_SPEC_AMOUNT ("accumulated_total",
                                 &details->accumulated_total),
    TALER_PQ_RESULT_SPEC_AMOUNT ("policy_fee",
                                 &details->policy_fee),
    TALER_PQ_RESULT_SPEC_AMOUNT ("transferable_amount",
                                 &details->transferable_amount),
    GNUNET_PQ_result_spec_auto_from_type ("state",
                                          &details->fulfillment_state),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_uint64 ("policy_fulfillment_id",
                                    &details->policy_fulfillment_id),
      &details->no_policy_fulfillment_id),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "get_policy_details",
                                                   params,
                                                   rs);
}


/* Persist the details to a policy in the policy_details table.  If there
 * already exists a policy, update the fields accordingly.
 *
 * @param details The policy details that should be persisted.  If an entry for
 *        the given details->hash_code exists, the values will be updated.
 * @param[out] policy_details_serial_id The row ID of the policy details
 * @param[out] accumulated_total The total amount accumulated in that policy
 * @param[out] fulfillment_state The state of policy.  If the state was Insufficient prior to the call and the provided deposit raises the accumulated_total above the commitment, it will be set to Ready.
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_persist_policy_details (
  void *cls,
  const struct TALER_PolicyDetails *details,
  uint64_t *policy_details_serial_id,
  struct TALER_Amount *accumulated_total,
  enum TALER_PolicyFulfillmentState *fulfillment_state)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&details->hash_code),
    TALER_PQ_query_param_json (details->policy_json),
    GNUNET_PQ_query_param_timestamp (&details->deadline),
    TALER_PQ_query_param_amount (&details->commitment),
    TALER_PQ_query_param_amount (&details->accumulated_total),
    TALER_PQ_query_param_amount (&details->policy_fee),
    TALER_PQ_query_param_amount (&details->transferable_amount),
    GNUNET_PQ_query_param_auto_from_type (&details->fulfillment_state),
    (details->no_policy_fulfillment_id)
     ?  GNUNET_PQ_query_param_null ()
     : GNUNET_PQ_query_param_uint64 (&details->policy_fulfillment_id),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_uint64 ("policy_details_serial_id",
                                  policy_details_serial_id),
    TALER_PQ_RESULT_SPEC_AMOUNT ("accumulated_total",
                                 accumulated_total),
    GNUNET_PQ_result_spec_uint32 ("fulfillment_state",
                                  fulfillment_state),
    GNUNET_PQ_result_spec_end
  };

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "call_insert_or_update_policy_details",
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
  uint64_t deposit_shard = TEH_PG_compute_shard (&refund->details.merchant_pub);
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
 * Compares two indices into an array of hash codes according to
 * GNUNET_CRYPTO_hash_cmp of the content at those index positions.
 *
 * Used in a call qsort_t in order to generate sorted policy_hash_codes.
 */
static int
hash_code_cmp (
  const void *hc1,
  const void *hc2,
  void *arg)
{
  size_t i1 = *(size_t *) hc1;
  size_t i2 = *(size_t *) hc2;
  const struct TALER_PolicyDetails *d = arg;

  return GNUNET_CRYPTO_hash_cmp (&d[i1].hash_code,
                                 &d[i2].hash_code);
}


/**
 * Add a proof of fulfillment into the policy_fulfillments table
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param fulfillment fullfilment transaction data to be added
 * @return query execution status
 */
static enum GNUNET_DB_QueryStatus
postgres_add_policy_fulfillment_proof (
  void *cls,
  struct TALER_PolicyFulfillmentTransactionData *fulfillment)
{
  enum GNUNET_DB_QueryStatus qs;
  struct PostgresClosure *pg = cls;
  size_t count = fulfillment->details_count;
  struct GNUNET_HashCode hcs[count];

  /* Create the sorted policy_hash_codes */
  {
    size_t idx[count];
    for (size_t i = 0; i < count; i++)
      idx[i] = i;

    /* Sort the indices according to the hash codes of the corresponding
     * details. */
    qsort_r (idx,
             count,
             sizeof(size_t),
             hash_code_cmp,
             fulfillment->details);

    /* Finally, concatenate all hash_codes in sorted order */
    for (size_t i = 0; i < count; i++)
      hcs[i] = fulfillment->details[idx[i]].hash_code;
  }


  /* Now, add the proof to the policy_fulfillments table, retrieve the
   * record_id */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_timestamp (&fulfillment->timestamp),
      TALER_PQ_query_param_json (fulfillment->proof),
      GNUNET_PQ_query_param_auto_from_type (&fulfillment->h_proof),
      GNUNET_PQ_query_param_fixed_size (hcs,
                                        count * sizeof(struct GNUNET_HashCode)),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("fulfillment_id",
                                    &fulfillment->fulfillment_id),
      GNUNET_PQ_result_spec_end
    };

    qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "insert_proof_into_policy_fulfillments",
                                                   params,
                                                   rs);
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
      return qs;
  }

  /* Now, set the states of each entry corresponding to the hash_codes in
   * policy_details accordingly */
  for (size_t i = 0; i < count; i++)
  {
    struct TALER_PolicyDetails *pos = &fulfillment->details[i];
    {
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (&pos->hash_code),
        GNUNET_PQ_query_param_timestamp (&pos->deadline),
        TALER_PQ_query_param_amount (&pos->commitment),
        TALER_PQ_query_param_amount (&pos->accumulated_total),
        TALER_PQ_query_param_amount (&pos->policy_fee),
        TALER_PQ_query_param_amount (&pos->transferable_amount),
        GNUNET_PQ_query_param_auto_from_type (&pos->fulfillment_state),
        GNUNET_PQ_query_param_end
      };

      qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                               "update_policy_details",
                                               params);
      if (qs < 0)
        return qs;
    }
  }

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

enum GNUNET_DB_QueryStatus
setup_wire_target(
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

  PREPARE (pg,
           "insert_kyc_status",
           "INSERT INTO wire_targets"
           "  (wire_target_h_payto"
           "  ,payto_uri"
           "  ) VALUES "
           "  ($1, $2)"
           " ON CONFLICT DO NOTHING");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_kyc_status",
                                             iparams);
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
    uint64_t shard = TEH_PG_compute_shard (&deposit->merchant_pub);
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
    TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                 &fees->account),
    TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                 &fees->purse),
    GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                         purse_timeout),
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
      TALER_PQ_RESULT_SPEC_AMOUNT ("account_fee",
                                   &fees.account),
      TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                   &fees.purse),
      GNUNET_PQ_result_spec_relative_time ("purse_timeout",
                                           &purse_timeout),
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
                            struct GNUNET_TIME_Relative history_expiration,
                            uint32_t purse_account_limit,
                            const struct TALER_MasterSignatureP *master_sig)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&start_date),
    GNUNET_PQ_query_param_timestamp (&end_date),
    TALER_PQ_query_param_amount (&fees->history),
    TALER_PQ_query_param_amount (&fees->account),
    TALER_PQ_query_param_amount (&fees->purse),
    GNUNET_PQ_query_param_relative_time (&purse_timeout),
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
  struct GNUNET_TIME_Relative he;
  uint32_t pal;

  qs = postgres_get_global_fee (pg,
                                start_date,
                                &sd,
                                &ed,
                                &wx,
                                &pt,
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
 * @param close_request_row identifies explicit close request, 0 for none
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
  const struct TALER_Amount *closing_fee,
  uint64_t close_request_row)
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
      GNUNET_PQ_query_param_uint64 (&close_request_row),
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
      (qs = TEH_PG_reserves_get (cls,
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
  return TEH_PG_reserves_update (cls,
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
      TEH_PG_preflight (pg))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      GNUNET_PQ_exec_statements (pg->conn,
                                 es))
  {
    TALER_LOG_ERROR (
      "Failed to defer wire_out_ref constraint on transaction\n");
    GNUNET_break (0);
    TEH_PG_rollback (pg);
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
 * Closure for #purse_decision_serial_helper_cb().
 */
struct PurseDecisionSerialContext
{

  /**
   * Callback to call.
   */
  TALER_EXCHANGEDB_PurseDecisionCallback cb;

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
purse_decision_serial_helper_cb (void *cls,
                                 PGresult *result,
                                 unsigned int num_results)
{
  struct PurseDecisionSerialContext *dsc = cls;
  struct PostgresClosure *pg = dsc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_PurseContractPublicKeyP purse_pub;
    struct TALER_ReservePublicKeyP reserve_pub;
    bool no_reserve = true;
    uint64_t rowid;
    struct TALER_Amount val;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                            &purse_pub),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &reserve_pub),
        &no_reserve),
      TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                   &val),
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
                   &purse_pub,
                   no_reserve ? NULL : &reserve_pub,
                   &val);
    GNUNET_PQ_cleanup_result (rs);
    if (GNUNET_OK != ret)
      break;
  }
}


/**
 * Select purse decisions above @a serial_id in monotonically increasing
 * order.
 *
 * @param cls closure
 * @param serial_id highest serial ID to exclude (select strictly larger)
 * @param refunded which refund status to select for
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
postgres_select_purse_decisions_above_serial_id (
  void *cls,
  uint64_t serial_id,
  bool refunded,
  TALER_EXCHANGEDB_PurseDecisionCallback cb,
  void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_bool (refunded),
    GNUNET_PQ_query_param_end
  };
  struct PurseDecisionSerialContext dsc = {
    .cb = cb,
    .cb_cls = cb_cls,
    .pg = pg,
    .status = GNUNET_OK
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "audit_get_purse_decisions_incr",
                                             params,
                                             &purse_decision_serial_helper_cb,
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
      TEH_PG_internal_setup (pg,
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
  plugin->get_policy_details = &postgres_get_policy_details;
  plugin->persist_policy_details = &postgres_persist_policy_details;
  plugin->add_policy_fulfillment_proof = &postgres_add_policy_fulfillment_proof;
  plugin->do_melt = &postgres_do_melt;
  plugin->do_refund = &postgres_do_refund;
  plugin->do_recoup = &postgres_do_recoup;
  plugin->do_recoup_refresh = &postgres_do_recoup_refresh;
  plugin->get_reserve_balance = &postgres_get_reserve_balance;
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
  plugin->get_ready_deposit = &postgres_get_ready_deposit;
  plugin->insert_deposit = &postgres_insert_deposit;
  plugin->insert_refund = &postgres_insert_refund;
  plugin->select_refunds_by_coin = &postgres_select_refunds_by_coin;
  plugin->get_melt = &postgres_get_melt;
  plugin->insert_refresh_reveal = &postgres_insert_refresh_reveal;
  plugin->get_refresh_reveal = &postgres_get_refresh_reveal;
  plugin->lookup_wire_transfer = &postgres_lookup_wire_transfer;
  plugin->lookup_transfer_by_deposit = &postgres_lookup_transfer_by_deposit;
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
  plugin->select_history_requests_above_serial_id
    = &postgres_select_history_requests_above_serial_id;
  plugin->select_purse_decisions_above_serial_id
    = &postgres_select_purse_decisions_above_serial_id;
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
  plugin->get_reserve_by_h_blind
    = &postgres_get_reserve_by_h_blind;

  /* New style, sort alphabetically! */
  plugin->do_reserve_open
    = &TEH_PG_do_reserve_open;
  plugin->drop_tables
    = &TEH_PG_drop_tables;
  plugin->do_withdraw
    = &TEH_PG_do_withdraw;
  plugin->free_coin_transaction_list
    = &TEH_COMMON_free_coin_transaction_list;
  plugin->free_reserve_history
    = &TEH_COMMON_free_reserve_history;
  plugin->get_coin_transactions
    = &TEH_PG_get_coin_transactions;
  plugin->get_expired_reserves
    = &TEH_PG_get_expired_reserves;
  plugin->get_purse_request
    = &TEH_PG_get_purse_request;
  plugin->get_reserve_history
    = &TEH_PG_get_reserve_history;
  plugin->get_reserve_status
    = &TEH_PG_get_reserve_status;
  plugin->get_unfinished_close_requests
    = &TEH_PG_get_unfinished_close_requests;
  plugin->insert_records_by_table
    = &TEH_PG_insert_records_by_table;
  plugin->insert_reserve_open_deposit
    = &TEH_PG_insert_reserve_open_deposit;
  plugin->insert_close_request
    = &TEH_PG_insert_close_request;
  plugin->delete_aggregation_transient
    = &TEH_PG_delete_aggregation_transient;
  plugin->get_link_data
    = &TEH_PG_get_link_data;
  plugin->iterate_reserve_close_info
    = &TEH_PG_iterate_reserve_close_info;
  plugin->iterate_kyc_reference
    = &TEH_PG_iterate_kyc_reference;
  plugin->lookup_records_by_table
    = &TEH_PG_lookup_records_by_table;
  plugin->lookup_serial_by_table
    = &TEH_PG_lookup_serial_by_table;
  plugin->select_account_merges_above_serial_id
    = &TEH_PG_select_account_merges_above_serial_id;
  plugin->select_all_purse_decisions_above_serial_id
    = &TEH_PG_select_all_purse_decisions_above_serial_id;
  plugin->select_purse
    = &TEH_PG_select_purse;
  plugin->select_purse_deposits_above_serial_id
    = &TEH_PG_select_purse_deposits_above_serial_id;
  plugin->select_purse_merges_above_serial_id
    = &TEH_PG_select_purse_merges_above_serial_id;
  plugin->select_purse_requests_above_serial_id
    = &TEH_PG_select_purse_requests_above_serial_id;
  plugin->select_reserve_close_info
    = &TEH_PG_select_reserve_close_info;
  plugin->select_reserve_closed_above_serial_id
    = &TEH_PG_select_reserve_closed_above_serial_id;
  plugin->select_reserve_open_above_serial_id
    = &TEH_PG_select_reserve_open_above_serial_id;
  /*need to sort*/
  plugin->insert_purse_request
    = &TEH_PG_insert_purse_request;
  plugin->iterate_active_signkeys
    = &TEH_PG_iterate_active_signkeys;
  plugin->commit
    = &TEH_PG_commit;
  plugin->preflight
    = &TEH_PG_preflight;
  plugin->create_shard_tables
    = &TEH_PG_create_shard_tables;
  plugin->insert_aggregation_tracking
    = &TEH_PG_insert_aggregation_tracking;
  plugin->setup_partitions
    = &TEH_PG_setup_partitions;
  plugin->select_aggregation_amounts_for_kyc_check
    = &TEH_PG_select_aggregation_amounts_for_kyc_check;

  plugin->select_satisfied_kyc_processes
    = &TEH_PG_select_satisfied_kyc_processes;
  plugin->kyc_provider_account_lookup
    = &TEH_PG_kyc_provider_account_lookup;
  plugin->lookup_kyc_requirement_by_row
    = &TEH_PG_lookup_kyc_requirement_by_row;
  plugin->insert_kyc_requirement_for_account
    = &TEH_PG_insert_kyc_requirement_for_account;
  plugin->lookup_kyc_process_by_account
    = &TEH_PG_lookup_kyc_process_by_account;
  plugin->update_kyc_process_by_row
    = &TEH_PG_update_kyc_process_by_row;
  plugin->insert_kyc_requirement_process
    = &TEH_PG_insert_kyc_requirement_process;
  plugin->select_withdraw_amounts_for_kyc_check
    = &TEH_PG_select_withdraw_amounts_for_kyc_check;
  plugin->select_merge_amounts_for_kyc_check
    = &TEH_PG_select_merge_amounts_for_kyc_check;
  plugin->profit_drains_set_finished
    = &TEH_PG_profit_drains_set_finished;
  plugin->profit_drains_get_pending
    = &TEH_PG_profit_drains_get_pending;
  plugin->get_drain_profit
    = &TEH_PG_get_drain_profit;
  plugin->get_purse_deposit
    = &TEH_PG_get_purse_deposit;
  plugin->insert_contract
    = &TEH_PG_insert_contract;
  plugin->select_contract
    = &TEH_PG_select_contract;
  plugin->select_purse_merge
    = &TEH_PG_select_purse_merge;
  plugin->select_contract_by_purse
    = &TEH_PG_select_contract_by_purse;
  plugin->insert_drain_profit
    = &TEH_PG_insert_drain_profit;
  plugin->do_reserve_purse
    = &TEH_PG_do_reserve_purse;
  plugin->lookup_global_fee_by_time
    = &TEH_PG_lookup_global_fee_by_time;
  plugin->do_purse_deposit
    = &TEH_PG_do_purse_deposit;
  plugin->activate_signing_key
    = &TEH_PG_activate_signing_key;
  plugin->update_auditor
    = &TEH_PG_update_auditor;
  plugin->begin_revolving_shard
    = &TEH_PG_begin_revolving_shard;
  plugin->get_extension_manifest
    = &TEH_PG_get_extension_manifest;
  plugin->insert_history_request
    = &TEH_PG_insert_history_request;
  plugin->do_purse_merge
    = &TEH_PG_do_purse_merge;
  plugin->start_read_committed
    = &TEH_PG_start_read_committed;
  plugin->start_read_only
    = &TEH_PG_start_read_only;
  plugin->insert_denomination_info
    = &TEH_PG_insert_denomination_info;
  plugin->do_batch_withdraw_insert
    = &TEH_PG_do_batch_withdraw_insert;
  plugin->lookup_wire_fee_by_time
    = &TEH_PG_lookup_wire_fee_by_time;
  plugin->start
    = &TEH_PG_start;
  plugin->rollback
    = &TEH_PG_rollback;

 plugin->create_tables
    = &TEH_PG_create_tables;
  plugin->setup_foreign_servers
    = &TEH_PG_setup_foreign_servers;
  plugin->event_listen
    = &TEH_PG_event_listen;
  plugin->event_listen_cancel
    = &TEH_PG_event_listen_cancel;
  plugin->event_notify
    = &TEH_PG_event_notify;
  plugin->get_denomination_info
    = &TEH_PG_get_denomination_info;
  plugin->iterate_denomination_info
    = &TEH_PG_iterate_denomination_info;
  plugin->iterate_denominations
    = &TEH_PG_iterate_denominations;
  plugin->iterate_active_auditors
    = &TEH_PG_iterate_active_auditors;
  plugin->iterate_auditor_denominations
    = &TEH_PG_iterate_auditor_denominations;
  plugin->reserves_get
    = &TEH_PG_reserves_get;
  plugin->reserves_get_origin
    = &TEH_PG_reserves_get_origin;
  plugin->drain_kyc_alert
    = &TEH_PG_drain_kyc_alert;
  plugin->reserves_in_insert
    = &TEH_PG_reserves_in_insert;
  plugin->get_withdraw_info
    = &TEH_PG_get_withdraw_info;
  plugin->do_batch_withdraw
    = &TEH_PG_do_batch_withdraw;
  plugin->get_policy_details
    = &TEH_PG_get_policy_details;
  plugin->persist_policy_details
    = &TEH_PG_persist_policy_details;
  plugin->do_deposit
    = &TEH_PG_do_deposit;
  plugin->add_policy_fulfillment_proof
    = &TEH_PG_add_policy_fulfillment_proof;
  plugin->do_melt
    = &TEH_PG_do_melt;
  plugin->do_refund
    = &TEH_PG_do_refund;
  plugin->do_recoup
    = &TEH_PG_do_recoup;
  plugin->do_recoup_refresh
    = &TEH_PG_do_recoup_refresh;
  plugin->get_reserve_balance
    = &TEH_PG_get_reserve_balance;
  plugin->count_known_coins
    = &TEH_PG_count_known_coins;
  plugin->ensure_coin_known
    = &TEH_PG_ensure_coin_known;
  plugin->get_known_coin
    = &TEH_PG_get_known_coin;
  plugin->get_coin_denomination
    = &TEH_PG_get_coin_denomination;
  plugin->have_deposit2
    = &TEH_PG_have_deposit2;
  plugin->aggregate
    = &TEH_PG_aggregate;
  plugin->create_aggregation_transient
    = &TEH_PG_create_aggregation_transient;
  plugin->select_aggregation_transient
    = &TEH_PG_select_aggregation_transient;
  plugin->find_aggregation_transient
    = &TEH_PG_find_aggregation_transient;
  plugin->update_aggregation_transient
    = &TEH_PG_update_aggregation_transient;
  plugin->get_ready_deposit
    = &TEH_PG_get_ready_deposit;
  plugin->insert_deposit
    = &TEH_PG_insert_deposit;
  plugin->insert_refund
    = &TEH_PG_insert_refund;
  plugin->select_refunds_by_coin
    = &TEH_PG_select_refunds_by_coin;
  plugin->get_melt
    = &TEH_PG_get_melt;
  plugin->insert_refresh_reveal
    = &TEH_PG_insert_refresh_reveal;
  plugin->get_refresh_reveal
    = &TEH_PG_get_refresh_reveal;
  plugin->lookup_wire_transfer
    = &TEH_PG_lookup_wire_transfer;
  plugin->lookup_transfer_by_deposit
    = &TEH_PG_lookup_transfer_by_deposit;
  plugin->insert_wire_fee
    = &TEH_PG_insert_wire_fee;
  plugin->insert_global_fee
    = &TEH_PG_insert_global_fee;
  plugin->get_wire_fee
    = &TEH_PG_get_wire_fee;
  plugin->get_global_fee
    = &TEH_PG_get_global_fee;
  plugin->get_global_fees
    = &TEH_PG_get_global_fees;
  plugin->insert_reserve_closed
    = &TEH_PG_insert_reserve_closed;
  plugin->wire_prepare_data_insert
    = &TEH_PG_wire_prepare_data_insert;
  plugin->wire_prepare_data_mark_finished
    = &TEH_PG_wire_prepare_data_mark_finished;
  plugin->wire_prepare_data_mark_failed
    = &TEH_PG_wire_prepare_data_mark_failed;
  plugin->wire_prepare_data_get
    = &TEH_PG_wire_prepare_data_get;
  plugin->start_deferred_wire_out
    = &TEH_PG_start_deferred_wire_out;
  plugin->store_wire_transfer_out
    = &TEH_PG_store_wire_transfer_out;
  plugin->gc
    = &TEH_PG_gc;
  plugin->select_deposits_above_serial_id
    = &TEH_PG_select_deposits_above_serial_id;
  plugin->select_history_requests_above_serial_id
    = &TEH_PG_select_history_requests_above_serial_id;
  plugin->select_purse_decisions_above_serial_id
    = &TEH_PG_select_purse_decisions_above_serial_id;
  plugin->select_purse_deposits_by_purse
    = &TEH_PG_select_purse_deposits_by_purse;
  plugin->select_refreshes_above_serial_id
    = &TEH_PG_select_refreshes_above_serial_id;
  plugin->select_refunds_above_serial_id
    = &TEH_PG_select_refunds_above_serial_id;
  plugin->select_reserves_in_above_serial_id
    = &TEH_PG_select_reserves_in_above_serial_id;
  plugin->select_reserves_in_above_serial_id_by_account
    = &TEH_PG_select_reserves_in_above_serial_id_by_account;
  plugin->select_withdrawals_above_serial_id
    = &TEH_PG_select_withdrawals_above_serial_id;
  plugin->select_wire_out_above_serial_id
    = &TEH_PG_select_wire_out_above_serial_id;
  plugin->select_wire_out_above_serial_id_by_account
    = &TEH_PG_select_wire_out_above_serial_id_by_account;
  plugin->select_recoup_above_serial_id
    = &TEH_PG_select_recoup_above_serial_id;
  plugin->select_recoup_refresh_above_serial_id
    = &TEH_PG_select_recoup_refresh_above_serial_id;
  plugin->get_reserve_by_h_blind
    = &TEH_PG_get_reserve_by_h_blind;
  plugin->get_old_coin_by_h_blind
    = &TEH_PG_get_old_coin_by_h_blind;
  plugin->insert_denomination_revocation
    = &TEH_PG_insert_denomination_revocation;
  plugin->get_denomination_revocation
    = &TEH_PG_get_denomination_revocation;
  plugin->select_deposits_missing_wire
    = &TEH_PG_select_deposits_missing_wire;
  plugin->lookup_auditor_timestamp
    = &TEH_PG_lookup_auditor_timestamp;
  plugin->lookup_auditor_status
    = &TEH_PG_lookup_auditor_status;
  plugin->insert_auditor
    = &TEH_PG_insert_auditor;
  plugin->lookup_wire_timestamp
    = &TEH_PG_lookup_wire_timestamp;
  plugin->insert_wire
    = &TEH_PG_insert_wire;
  plugin->update_wire
    = &TEH_PG_update_wire;
  plugin->get_wire_accounts
    = &TEH_PG_get_wire_accounts;
  plugin->get_wire_fees
    = &TEH_PG_get_wire_fees;
  plugin->insert_signkey_revocation
    = &TEH_PG_insert_signkey_revocation;
  plugin->lookup_signkey_revocation
    = &TEH_PG_lookup_signkey_revocation;
  plugin->lookup_denomination_key
    = &TEH_PG_lookup_denomination_key;
  plugin->insert_auditor_denom_sig
    = &TEH_PG_insert_auditor_denom_sig;
  plugin->select_auditor_denom_sig
    = &TEH_PG_select_auditor_denom_sig;
  plugin->add_denomination_key
    = &TEH_PG_add_denomination_key;
  plugin->lookup_signing_key
    = &TEH_PG_lookup_signing_key;
  plugin->begin_shard
    = &TEH_PG_begin_shard;
  plugin->abort_shard
    = &TEH_PG_abort_shard;
  plugin->complete_shard
    = &TEH_PG_complete_shard;
  plugin->release_revolving_shard
    = &TEH_PG_release_revolving_shard;
  plugin->delete_shard_locks
    = &TEH_PG_delete_shard_locks;
  plugin->set_extension_manifest
    = &TEH_PG_set_extension_manifest;
  plugin->insert_partner
    = &TEH_PG_insert_partner;
  plugin->expire_purse
    = &TEH_PG_expire_purse;
  plugin->select_purse_by_merge_pub
    = &TEH_PG_select_purse_by_merge_pub;
  plugin->set_purse_balance
    = &TEH_PG_set_purse_balance;

  plugin->batch_reserves_in_insert
    = &TEH_PG_batch_reserves_in_insert;

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
