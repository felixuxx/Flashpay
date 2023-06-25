/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file pg_lookup_serial_by_table.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_serial_by_table.h"
#include "pg_helper.h"


/**
 * Assign statement to @a n and PREPARE
 * @a sql under name @a n.
 */
#define XPREPARE(n,sql) \
  statement = n;        \
  PREPARE (pg, n, sql);


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_serial_by_table (void *cls,
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
  const char *statement = NULL;

  switch (table)
  {
  case TALER_EXCHANGEDB_RT_DENOMINATIONS:
    XPREPARE ("select_serial_by_table_denominations",
              "SELECT"
              " denominations_serial AS serial"
              " FROM denominations"
              " ORDER BY denominations_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_DENOMINATION_REVOCATIONS:
    XPREPARE ("select_serial_by_table_denomination_revocations",
              "SELECT"
              " denom_revocations_serial_id AS serial"
              " FROM denomination_revocations"
              " ORDER BY denom_revocations_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WIRE_TARGETS:
    XPREPARE ("select_serial_by_table_wire_targets",
              "SELECT"
              " wire_target_serial_id AS serial"
              " FROM wire_targets"
              " ORDER BY wire_target_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_PROCESSES:
    XPREPARE ("select_serial_by_table_legitimization_processes",
              "SELECT"
              " legitimization_process_serial_id AS serial"
              " FROM legitimization_processes"
              " ORDER BY legitimization_process_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_REQUIREMENTS:
    XPREPARE ("select_serial_by_table_legitimization_requiremetns",
              "SELECT"
              " legitimization_requirement_serial_id AS serial"
              " FROM legitimization_requirements"
              " ORDER BY legitimization_requirement_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RESERVES:
    XPREPARE ("select_serial_by_table_reserves",
              "SELECT"
              " reserve_uuid AS serial"
              " FROM reserves"
              " ORDER BY reserve_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_IN:
    XPREPARE ("select_serial_by_table_reserves_in",
              "SELECT"
              " reserve_in_serial_id AS serial"
              " FROM reserves_in"
              " ORDER BY reserve_in_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_CLOSE:
    XPREPARE ("select_serial_by_table_reserves_close",
              "SELECT"
              " close_uuid AS serial"
              " FROM reserves_close"
              " ORDER BY close_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OPEN_REQUESTS:
    XPREPARE ("select_serial_by_table_reserves_open_requests",
              "SELECT"
              " open_request_uuid AS serial"
              " FROM reserves_open_requests"
              " ORDER BY open_request_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OPEN_DEPOSITS:
    XPREPARE ("select_serial_by_table_reserves_open_deposits",
              "SELECT"
              " reserve_open_deposit_uuid AS serial"
              " FROM reserves_open_deposits"
              " ORDER BY reserve_open_deposit_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OUT:
    XPREPARE ("select_serial_by_table_reserves_out",
              "SELECT"
              " reserve_out_serial_id AS serial"
              " FROM reserves_out"
              " ORDER BY reserve_out_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_AUDITORS:
    XPREPARE ("select_serial_by_table_auditors",
              "SELECT"
              " auditor_uuid AS serial"
              " FROM auditors"
              " ORDER BY auditor_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_AUDITOR_DENOM_SIGS:
    XPREPARE ("select_serial_by_table_auditor_denom_sigs",
              "SELECT"
              " auditor_denom_serial AS serial"
              " FROM auditor_denom_sigs"
              " ORDER BY auditor_denom_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_EXCHANGE_SIGN_KEYS:
    XPREPARE ("select_serial_by_table_exchange_sign_keys",
              "SELECT"
              " esk_serial AS serial"
              " FROM exchange_sign_keys"
              " ORDER BY esk_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_SIGNKEY_REVOCATIONS:
    XPREPARE ("select_serial_by_table_signkey_revocations",
              "SELECT"
              " signkey_revocations_serial_id AS serial"
              " FROM signkey_revocations"
              " ORDER BY signkey_revocations_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_KNOWN_COINS:
    XPREPARE ("select_serial_by_table_known_coins",
              "SELECT"
              " known_coin_id AS serial"
              " FROM known_coins"
              " ORDER BY known_coin_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_COMMITMENTS:
    XPREPARE ("select_serial_by_table_refresh_commitments",
              "SELECT"
              " melt_serial_id AS serial"
              " FROM refresh_commitments"
              " ORDER BY melt_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_REVEALED_COINS:
    XPREPARE ("select_serial_by_table_refresh_revealed_coins",
              "SELECT"
              " rrc_serial AS serial"
              " FROM refresh_revealed_coins"
              " ORDER BY rrc_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_REFRESH_TRANSFER_KEYS:
    XPREPARE ("select_serial_by_table_refresh_transfer_keys",
              "SELECT"
              " rtc_serial AS serial"
              " FROM refresh_transfer_keys"
              " ORDER BY rtc_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_DEPOSITS:
    XPREPARE ("select_serial_by_table_deposits",
              "SELECT"
              " deposit_serial_id AS serial"
              " FROM deposits"
              " ORDER BY deposit_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_REFUNDS:
    XPREPARE ("select_serial_by_table_refunds",
              "SELECT"
              " refund_serial_id AS serial"
              " FROM refunds"
              " ORDER BY refund_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WIRE_OUT:
    XPREPARE ("select_serial_by_table_wire_out",
              "SELECT"
              " wireout_uuid AS serial"
              " FROM wire_out"
              " ORDER BY wireout_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_AGGREGATION_TRACKING:
    XPREPARE ("select_serial_by_table_aggregation_tracking",
              "SELECT"
              " aggregation_serial_id AS serial"
              " FROM aggregation_tracking"
              " ORDER BY aggregation_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WIRE_FEE:
    XPREPARE ("select_serial_by_table_wire_fee",
              "SELECT"
              " wire_fee_serial AS serial"
              " FROM wire_fee"
              " ORDER BY wire_fee_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_GLOBAL_FEE:
    XPREPARE ("select_serial_by_table_global_fee",
              "SELECT"
              " global_fee_serial AS serial"
              " FROM global_fee"
              " ORDER BY global_fee_serial DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RECOUP:
    XPREPARE ("select_serial_by_table_recoup",
              "SELECT"
              " recoup_uuid AS serial"
              " FROM recoup"
              " ORDER BY recoup_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_RECOUP_REFRESH:
    XPREPARE ("select_serial_by_table_recoup_refresh",
              "SELECT"
              " recoup_refresh_uuid AS serial"
              " FROM recoup_refresh"
              " ORDER BY recoup_refresh_uuid DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_EXTENSIONS:
    XPREPARE ("select_serial_by_table_extensions",
              "SELECT"
              " extension_id AS serial"
              " FROM extensions"
              " ORDER BY extension_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_POLICY_DETAILS:
    XPREPARE ("select_serial_by_table_policy_details",
              "SELECT"
              " policy_details_serial_id AS serial"
              " FROM policy_details"
              " ORDER BY policy_details_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_POLICY_FULFILLMENTS:
    XPREPARE ("select_serial_by_table_policy_fulfillments",
              "SELECT"
              " fulfillment_id AS serial"
              " FROM policy_fulfillments"
              " ORDER BY fulfillment_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_PURSE_REQUESTS:
    XPREPARE ("select_serial_by_table_purse_requests",
              "SELECT"
              " purse_requests_serial_id AS serial"
              " FROM purse_requests"
              " ORDER BY purse_requests_serial_id DESC"
              " LIMIT 1;")
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DECISION:
    XPREPARE ("select_serial_by_table_purse_decision",
              "SELECT"
              " purse_decision_serial_id AS serial"
              " FROM purse_decision"
              " ORDER BY purse_decision_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_PURSE_MERGES:
    XPREPARE ("select_serial_by_table_purse_merges",
              "SELECT"
              " purse_merge_request_serial_id AS serial"
              " FROM purse_merges"
              " ORDER BY purse_merge_request_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DEPOSITS:
    XPREPARE ("select_serial_by_table_purse_deposits",
              "SELECT"
              " purse_deposit_serial_id AS serial"
              " FROM purse_deposits"
              " ORDER BY purse_deposit_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_ACCOUNT_MERGES:
    XPREPARE ("select_serial_by_table_account_merges",
              "SELECT"
              " account_merge_request_serial_id AS serial"
              " FROM account_merges"
              " ORDER BY account_merge_request_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_HISTORY_REQUESTS:
    XPREPARE ("select_serial_by_table_history_requests",
              "SELECT"
              " history_request_serial_id AS serial"
              " FROM history_requests"
              " ORDER BY history_request_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_CLOSE_REQUESTS:
    XPREPARE ("select_serial_by_table_close_requests",
              "SELECT"
              " close_request_serial_id AS serial"
              " FROM close_requests"
              " ORDER BY close_request_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WADS_OUT:
    XPREPARE ("select_serial_by_table_wads_out",
              "SELECT"
              " wad_out_serial_id AS serial"
              " FROM wads_out"
              " ORDER BY wad_out_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WADS_OUT_ENTRIES:
    XPREPARE ("select_serial_by_table_wads_out_entries",
              "SELECT"
              " wad_out_entry_serial_id AS serial"
              " FROM wad_out_entries"
              " ORDER BY wad_out_entry_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WADS_IN:
    XPREPARE ("select_serial_by_table_wads_in",
              "SELECT"
              " wad_in_serial_id AS serial"
              " FROM wads_in"
              " ORDER BY wad_in_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_WADS_IN_ENTRIES:
    XPREPARE ("select_serial_by_table_wads_in_entries",
              "SELECT"
              " wad_in_entry_serial_id AS serial"
              " FROM wad_in_entries"
              " ORDER BY wad_in_entry_serial_id DESC"
              " LIMIT 1;");
    break;
  case TALER_EXCHANGEDB_RT_PROFIT_DRAINS:
    XPREPARE ("select_serial_by_table_profit_drains",
              "SELECT"
              " profit_drain_serial_id AS serial"
              " FROM profit_drains"
              " ORDER BY profit_drain_serial_id DESC"
              " LIMIT 1;");
    statement = "select_serial_by_table_profit_drains";
    break;
  case TALER_EXCHANGEDB_RT_AML_STAFF:
    XPREPARE ("select_serial_by_table_aml_staff",
              "SELECT"
              " aml_staff_uuid AS serial"
              " FROM aml_staff"
              " ORDER BY aml_staff_uuid DESC"
              " LIMIT 1;");
    statement = "select_serial_by_table_aml_staff";
    break;
  case TALER_EXCHANGEDB_RT_AML_HISTORY:
    XPREPARE ("select_serial_by_table_aml_history",
              "SELECT"
              " aml_history_serial_id AS serial"
              " FROM aml_history"
              " ORDER BY aml_history_serial_id DESC"
              " LIMIT 1;");
    statement = "select_serial_by_table_aml_history";
    break;
  case TALER_EXCHANGEDB_RT_KYC_ATTRIBUTES:
    XPREPARE ("select_serial_by_table_kyc_attributes",
              "SELECT"
              " kyc_attributes_serial_id AS serial"
              " FROM kyc_attributes"
              " ORDER BY kyc_attributes_serial_id DESC"
              " LIMIT 1;");
    statement = "select_serial_by_table_kyc_attributes";
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DELETION:
    XPREPARE ("select_serial_by_table_purse_deletion",
              "SELECT"
              " purse_deletion_serial_id AS serial"
              " FROM purse_deletion"
              " ORDER BY purse_deletion_serial_id DESC"
              " LIMIT 1;");
    statement = "select_serial_by_table_purse_deletion";
    break;
  case TALER_EXCHANGEDB_RT_AGE_WITHDRAW:
    XPREPARE ("select_serial_by_table_age_withdraw",
              "SELECT"
              " age_withdraw_id AS serial"
              " FROM age_withdraw"
              " ORDER BY age_withdraw_id DESC"
              " LIMIT 1;");
    statement = "select_serial_by_table_age_withdraw";
    break;
  }
  if (NULL == statement)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   statement,
                                                   params,
                                                   rs);
}


#undef XPREPARE
