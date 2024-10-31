/*
   This file is part of TALER
   Copyright (C) 2014--2023 Taler Systems SA

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
 * @author Özgür Kesim
 */
#include "platform.h"
#include <poll.h>
#include <pthread.h>
#include <libpq-fe.h>
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
#include "pg_select_aml_decisions.h"
#include "plugin_exchangedb_common.h"
#include "pg_delete_aggregation_transient.h"
#include "pg_get_link_data.h"
#include "pg_helper.h"
#include "pg_do_check_deposit_idempotent.h"
#include "pg_do_reserve_open.h"
#include "pg_get_coin_transactions.h"
#include "pg_get_expired_reserves.h"
#include "pg_lookup_rules_by_access_token.h"
#include "pg_lookup_h_payto_by_access_token.h"
#include "pg_get_purse_request.h"
#include "pg_get_reserve_history.h"
#include "pg_get_unfinished_close_requests.h"
#include "pg_insert_close_request.h"
#include "pg_insert_records_by_table.h"
#include "pg_insert_programmatic_legitimization_outcome.h"
#include "pg_insert_reserve_open_deposit.h"
#include "pg_get_pending_kyc_requirement_process.h"
#include "pg_iterate_kyc_reference.h"
#include "pg_iterate_reserve_close_info.h"
#include "pg_lookup_records_by_table.h"
#include "pg_lookup_kyc_status_by_token.h"
#include "pg_lookup_serial_by_table.h"
#include "pg_select_deposit_amounts_for_kyc_check.h"
#include "pg_lookup_pending_legitimization.h"
#include "pg_lookup_completed_legitimization.h"
#include "pg_lookup_active_legitimization.h"
#include "pg_select_account_merges_above_serial_id.h"
#include "pg_select_all_purse_decisions_above_serial_id.h"
#include "pg_select_purse.h"
#include "pg_select_aml_attributes.h"
#include "pg_trigger_kyc_rule_for_account.h"
#include "pg_select_purse_deposits_above_serial_id.h"
#include "pg_select_purse_merges_above_serial_id.h"
#include "pg_select_purse_requests_above_serial_id.h"
#include "pg_select_reserve_close_info.h"
#include "pg_select_reserve_closed_above_serial_id.h"
#include "pg_select_reserve_open_above_serial_id.h"
#include "pg_insert_purse_request.h"
#include "pg_iterate_active_signkeys.h"
#include "pg_preflight.h"
#include "pg_select_aml_statistics.h"
#include "pg_commit.h"
#include "pg_wad_in_insert.h"
#include "pg_kycauth_in_insert.h"
#include "pg_drop_tables.h"
#include "pg_get_kyc_rules.h"
#include "pg_select_aggregation_amounts_for_kyc_check.h"
#include "pg_kyc_provider_account_lookup.h"
#include "pg_lookup_kyc_process_by_account.h"
#include "pg_update_kyc_process_by_row.h"
#include "pg_insert_kyc_requirement_process.h"
#include "pg_select_withdraw_amounts_for_kyc_check.h"
#include "pg_insert_active_legitimization_measure.h"
#include "pg_select_merge_amounts_for_kyc_check.h"
#include "pg_profit_drains_set_finished.h"
#include "pg_profit_drains_get_pending.h"
#include "pg_get_drain_profit.h"
#include "pg_get_purse_deposit.h"
#include "pg_insert_contract.h"
#include "pg_insert_kyc_failure.h"
#include "pg_select_contract.h"
#include "pg_select_purse_merge.h"
#include "pg_select_contract_by_purse.h"
#include "pg_insert_drain_profit.h"
#include "pg_do_reserve_purse.h"
#include "pg_lookup_aml_history.h"
#include "pg_lookup_kyc_history.h"
#include "pg_lookup_global_fee_by_time.h"
#include "pg_do_purse_deposit.h"
#include "pg_activate_signing_key.h"
#include "pg_update_auditor.h"
#include "pg_begin_revolving_shard.h"
#include "pg_get_extension_manifest.h"
#include "pg_do_purse_delete.h"
#include "pg_do_purse_merge.h"
#include "pg_start_read_committed.h"
#include "pg_start_read_only.h"
#include "pg_insert_denomination_info.h"
#include "pg_do_batch_withdraw_insert.h"
#include "pg_lookup_wire_fee_by_time.h"
#include "pg_start.h"
#include "pg_rollback.h"
#include "pg_create_tables.h"
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
#include "pg_get_age_withdraw.h"
#include "pg_do_batch_withdraw.h"
#include "pg_do_age_withdraw.h"
#include "pg_get_policy_details.h"
#include "pg_persist_policy_details.h"
#include "pg_do_deposit.h"
#include "pg_get_wire_hash_for_contract.h"
#include "pg_add_policy_fulfillment_proof.h"
#include "pg_do_melt.h"
#include "pg_do_refund.h"
#include "pg_do_recoup.h"
#include "pg_do_recoup_refresh.h"
#include "pg_get_reserve_balance.h"
#include "pg_count_known_coins.h"
#include "pg_ensure_coin_known.h"
#include "pg_get_known_coin.h"
#include "pg_get_signature_for_known_coin.h"
#include "pg_get_coin_denomination.h"
#include "pg_have_deposit2.h"
#include "pg_aggregate.h"
#include "pg_create_aggregation_transient.h"
#include "pg_select_aggregation_transient.h"
#include "pg_find_aggregation_transient.h"
#include "pg_update_aggregation_transient.h"
#include "pg_get_ready_deposit.h"
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
#include "pg_inject_auditor_triggers.h"
#include "pg_select_coin_deposits_above_serial_id.h"
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
#include "pg_select_batch_deposits_missing_wire.h"
#include "pg_select_aggregations_above_serial.h"
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
#include "pg_compute_shard.h"
#include "pg_insert_kyc_attributes.h"
#include "pg_select_kyc_attributes.h"
#include "pg_insert_aml_officer.h"
#include "pg_test_aml_officer.h"
#include "pg_lookup_aml_officer.h"
#include "pg_lookup_kyc_requirement_by_row.h"
#include "pg_insert_aml_decision.h"
#include "pg_batch_ensure_coin_known.h"
#include "plugin_exchangedb_postgres.h"

/**
 * Set to 1 to enable Postgres auto_explain module. This will
 * slow down things a _lot_, but also provide extensive logging
 * in the Postgres database logger for performance analysis.
 */
#define AUTO_EXPLAIN 0


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
 * Connect to the database if the connection does not exist yet.
 *
 * @param pg the plugin-specific state
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_PG_internal_setup (struct PostgresClosure *pg)
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
      /* Mergejoin causes issues, see Postgres #18380 */
      GNUNET_PQ_make_try_execute ("SET enable_mergejoin=OFF;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };
#else
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute (
        "SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;"),
      GNUNET_PQ_make_try_execute ("SET enable_sort=OFF;"),
      GNUNET_PQ_make_try_execute ("SET enable_seqscan=OFF;"),
      /* Mergejoin causes issues, see Postgres #18380 */
      GNUNET_PQ_make_try_execute ("SET enable_mergejoin=OFF;"),
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
  return GNUNET_OK;
}


/**
 * Initialize Postgres database subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct
 *         TALER_EXCHANGEDB_Plugin`
 */
void *
libtaler_plugin_exchangedb_postgres_init (void *cls);

/* Declaration used to squash compiler warning */
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
                               "SQL_DIR");
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
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchangedb",
                                           "IDLE_RESERVE_EXPIRATION_TIME",
                                           &pg->idle_reserve_expiration_time))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "IDLE_RESERVE_EXPIRATION_TIME");
    GNUNET_free (pg->exchange_url);
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchangedb",
                                           "LEGAL_RESERVE_EXPIRATION_TIME",
                                           &pg->legal_reserve_expiration_time))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "LEGAL_RESERVE_EXPIRATION_TIME");
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
      TEH_PG_internal_setup (pg))
  {
    GNUNET_free (pg->exchange_url);
    GNUNET_free (pg->currency);
    GNUNET_free (pg->sql_dir);
    GNUNET_free (pg);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_EXCHANGEDB_Plugin);
  plugin->cls = pg;
  plugin->do_reserve_open
    = &TEH_PG_do_reserve_open;
  plugin->drop_tables
    = &TEH_PG_drop_tables;
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
  plugin->insert_purse_request
    = &TEH_PG_insert_purse_request;
  plugin->iterate_active_signkeys
    = &TEH_PG_iterate_active_signkeys;
  plugin->commit
    = &TEH_PG_commit;
  plugin->preflight
    = &TEH_PG_preflight;
  plugin->select_aggregation_amounts_for_kyc_check
    = &TEH_PG_select_aggregation_amounts_for_kyc_check;
  plugin->get_kyc_rules
    = &TEH_PG_get_kyc_rules;
  plugin->kyc_provider_account_lookup
    = &TEH_PG_kyc_provider_account_lookup;
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
  plugin->do_purse_merge
    = &TEH_PG_do_purse_merge;
  plugin->do_purse_delete
    = &TEH_PG_do_purse_delete;
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
  plugin->lookup_rules_by_access_token
    = &TEH_PG_lookup_rules_by_access_token;
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
  plugin->do_age_withdraw
    = &TEH_PG_do_age_withdraw;
  plugin->get_age_withdraw
    = &TEH_PG_get_age_withdraw;
  plugin->wad_in_insert
    = &TEH_PG_wad_in_insert;
  plugin->kycauth_in_insert
    = &TEH_PG_kycauth_in_insert;
  plugin->get_policy_details
    = &TEH_PG_get_policy_details;
  plugin->persist_policy_details
    = &TEH_PG_persist_policy_details;
  plugin->do_deposit
    = &TEH_PG_do_deposit;
  plugin->get_wire_hash_for_contract
    = &TEH_PG_get_wire_hash_for_contract;
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
  plugin->get_signature_for_known_coin
    = &TEH_PG_get_signature_for_known_coin;
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
  plugin->select_coin_deposits_above_serial_id
    = &TEH_PG_select_coin_deposits_above_serial_id;
  plugin->lookup_aml_history
    = &TEH_PG_lookup_aml_history;
  plugin->lookup_kyc_history
    = &TEH_PG_lookup_kyc_history;
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
  plugin->select_batch_deposits_missing_wire
    = &TEH_PG_select_batch_deposits_missing_wire;
  plugin->select_aggregations_above_serial
    = &TEH_PG_select_aggregations_above_serial;
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
  plugin->select_aml_decisions
    = &TEH_PG_select_aml_decisions;
  plugin->select_deposit_amounts_for_kyc_check
    = &TEH_PG_select_deposit_amounts_for_kyc_check;
  plugin->do_check_deposit_idempotent
    = &TEH_PG_do_check_deposit_idempotent;
  plugin->insert_signkey_revocation
    = &TEH_PG_insert_signkey_revocation;
  plugin->select_aml_attributes
    = &TEH_PG_select_aml_attributes;
  plugin->select_aml_statistics
    = &TEH_PG_select_aml_statistics;
  plugin->lookup_signkey_revocation
    = &TEH_PG_lookup_signkey_revocation;
  plugin->lookup_denomination_key
    = &TEH_PG_lookup_denomination_key;
  plugin->lookup_completed_legitimization
    = &TEH_PG_lookup_completed_legitimization;
  plugin->lookup_pending_legitimization
    = &TEH_PG_lookup_pending_legitimization;
  plugin->lookup_active_legitimization
    = &TEH_PG_lookup_active_legitimization;
  plugin->insert_auditor_denom_sig
    = &TEH_PG_insert_auditor_denom_sig;
  plugin->select_auditor_denom_sig
    = &TEH_PG_select_auditor_denom_sig;
  plugin->add_denomination_key
    = &TEH_PG_add_denomination_key;
  plugin->lookup_signing_key
    = &TEH_PG_lookup_signing_key;
  plugin->lookup_h_payto_by_access_token
    = &TEH_PG_lookup_h_payto_by_access_token;
  plugin->begin_shard
    = &TEH_PG_begin_shard;
  plugin->abort_shard
    = &TEH_PG_abort_shard;
  plugin->insert_kyc_failure
    = &TEH_PG_insert_kyc_failure;
  plugin->insert_programmatic_legitimization_outcome
    = &TEH_PG_insert_programmatic_legitimization_outcome;
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
  plugin->get_pending_kyc_requirement_process
    = &TEH_PG_get_pending_kyc_requirement_process;
  plugin->insert_kyc_attributes
    = &TEH_PG_insert_kyc_attributes;
  plugin->select_kyc_attributes
    = &TEH_PG_select_kyc_attributes;
  plugin->insert_aml_officer
    = &TEH_PG_insert_aml_officer;
  plugin->test_aml_officer
    = &TEH_PG_test_aml_officer;
  plugin->lookup_aml_officer
    = &TEH_PG_lookup_aml_officer;
  plugin->insert_active_legitimization_measure
    = &TEH_PG_insert_active_legitimization_measure;
  plugin->insert_aml_decision
    = &TEH_PG_insert_aml_decision;
  plugin->lookup_kyc_requirement_by_row
    = &TEH_PG_lookup_kyc_requirement_by_row;
  plugin->trigger_kyc_rule_for_account
    = &TEH_PG_trigger_kyc_rule_for_account;
  plugin->lookup_kyc_status_by_token
    = &TEH_PG_lookup_kyc_status_by_token;
  plugin->batch_ensure_coin_known
    = &TEH_PG_batch_ensure_coin_known;
  plugin->inject_auditor_triggers
    = &TEH_PG_inject_auditor_triggers;

  return plugin;
}


/**
 * Shutdown Postgres database subsystem.
 *
 * @param cls a `struct TALER_EXCHANGEDB_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_exchangedb_postgres_done (void *cls);

/* Declaration used to squash compiler warning */
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
