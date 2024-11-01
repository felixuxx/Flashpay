/*
   This file is part of GNUnet
   Copyright (C) 2020-2024 Taler Systems SA

   GNUnet is free software: you can redistribute it and/or modify it
   under the terms of the GNU Affero General Public License as published
   by the Free Software Foundation, either version 3 of the License,
   or (at your option) any later version.

   GNUnet is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.

     SPDX-License-Identifier: AGPL3.0-or-later
 */
/**
 * @file exchangedb/pg_insert_records_by_table.c
 * @brief replicate_records_by_table implementation
 * @author Christian Grothoff
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_records_by_table.h"
#include "pg_helper.h"
#include <gnunet/gnunet_pq_lib.h>


/**
 * Signature of helper functions of #TEH_PG_insert_records_by_table().
 *
 * @param pg plugin context
 * @param td record to insert
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*InsertRecordCallback)(struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td);


/**
 * Function called with denominations records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_denominations (struct PostgresClosure *pg,
                             const struct TALER_EXCHANGEDB_TableData *td)
{
  struct TALER_DenominationHashP denom_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&denom_hash),
    GNUNET_PQ_query_param_uint32 (
      &td->details.denominations.denom_type),
    GNUNET_PQ_query_param_uint32 (
      &td->details.denominations.age_mask),
    TALER_PQ_query_param_denom_pub (
      &td->details.denominations.denom_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.denominations.master_sig),
    GNUNET_PQ_query_param_timestamp (
      &td->details.denominations.valid_from),
    GNUNET_PQ_query_param_timestamp (
      &td->details.denominations.expire_withdraw),
    GNUNET_PQ_query_param_timestamp (
      &td->details.denominations.expire_deposit),
    GNUNET_PQ_query_param_timestamp (
      &td->details.denominations.expire_legal),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.denominations.coin),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.denominations.fees.withdraw),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.denominations.fees.deposit),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.denominations.fees.refresh),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.denominations.fees.refund),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
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
           ",coin"
           ",fee_withdraw"
           ",fee_deposit"
           ",fee_refresh"
           ",fee_refund"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13, $14, $15);");

  TALER_denom_pub_hash (
    &td->details.denominations.denom_pub,
    &denom_hash);

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_denominations",
                                             params);
}


/**
 * Function called with denomination_revocations records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_denomination_revocations (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.denomination_revocations.master_sig),
    GNUNET_PQ_query_param_uint64 (
      &td->details.denomination_revocations.denominations_serial),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_denomination_revocations",
           "INSERT INTO denomination_revocations"
           "(denom_revocations_serial_id"
           ",master_sig"
           ",denominations_serial"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_denomination_revocations",
                                             params);
}


/**
 * Function called with denominations records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wire_targets (struct PostgresClosure *pg,
                            const struct TALER_EXCHANGEDB_TableData *td)
{
  struct TALER_NormalizedPaytoHashP normalized_payto_hash;
  struct TALER_FullPaytoHashP full_payto_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&full_payto_hash),
    GNUNET_PQ_query_param_auto_from_type (&normalized_payto_hash),
    GNUNET_PQ_query_param_string (
      td->details.wire_targets.full_payto_uri.full_payto),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wire_targets.access_token),
    td->details.wire_targets.no_account
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (
      &td->details.wire_targets.target_pub),
    GNUNET_PQ_query_param_end
  };

  TALER_full_payto_hash (
    td->details.wire_targets.full_payto_uri,
    &full_payto_hash);
  TALER_full_payto_normalize_and_hash (
    td->details.wire_targets.full_payto_uri,
    &normalized_payto_hash);
  PREPARE (pg,
           "insert_into_table_wire_targets",
           "INSERT INTO wire_targets"
           "(wire_target_serial_id"
           ",wire_target_h_payto"
           ",h_normalized_payto"
           ",payto_uri"
           ",access_token"
           ",target_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wire_targets",
                                             params);
}


/**
 * Function called with records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_legitimization_measures (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.legitimization_measures.target_token),
    GNUNET_PQ_query_param_timestamp (
      &td->details.legitimization_measures.start_time),
    TALER_PQ_query_param_json (
      td->details.legitimization_measures.measures),
    GNUNET_PQ_query_param_uint32 (
      &td->details.legitimization_measures.display_priority),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_legitimization_measures",
           "INSERT INTO legitimization_measures"
           "(legitimization_measure_serial_id"
           ",access_token"
           ",start_time"
           ",jmeasures"
           ",display_priority"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_legitimization_measures",
                                             params);
}


/**
 * Function called with records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_legitimization_outcomes (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.legitimization_outcomes.h_payto),
    GNUNET_PQ_query_param_timestamp (
      &td->details.legitimization_outcomes.decision_time),
    GNUNET_PQ_query_param_timestamp (
      &td->details.legitimization_outcomes.expiration_time),
    TALER_PQ_query_param_json (
      td->details.legitimization_outcomes.properties),
    GNUNET_PQ_query_param_bool (
      td->details.legitimization_outcomes.to_investigate),
    TALER_PQ_query_param_json (
      td->details.legitimization_outcomes.new_rules),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_legitimization_outcomes",
           "INSERT INTO legitimization_outcomes"
           "(outcome_serial_id"
           ",h_payto"
           ",decision_time"
           ",expiration_time"
           ",jproperties"
           ",to_investigate"
           ",jnew_rules"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_legitimization_outcomes",
                                             params);
}


/**
 * Function called with records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_legitimization_processes (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.legitimization_processes.h_payto),
    GNUNET_PQ_query_param_timestamp (
      &td->details.legitimization_processes.start_time),
    GNUNET_PQ_query_param_timestamp (
      &td->details.legitimization_processes.expiration_time),
    GNUNET_PQ_query_param_uint64 (
      &td->details.legitimization_processes.legitimization_measure_serial_id),
    GNUNET_PQ_query_param_uint32 (
      &td->details.legitimization_processes.measure_index),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.provider_name),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.provider_user_id),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.provider_legitimization_id),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.redirect_url),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_legitimization_processes",
           "INSERT INTO legitimization_processes"
           "(legitimization_process_serial_id"
           ",h_payto"
           ",start_time"
           ",expiration_time"
           ",legitimization_measure_serial_id"
           ",measure_index"
           ",provider_name"
           ",provider_user_id"
           ",provider_legitimization_id"
           ",redirect_url"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_legitimization_processes",
                                             params);
}


/**
 * Function called with reserves records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves (struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.reserves.reserve_pub),
    GNUNET_PQ_query_param_timestamp (&td->details.reserves.expiration_date),
    GNUNET_PQ_query_param_timestamp (&td->details.reserves.gc_date),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_reserves",
           "INSERT INTO reserves"
           "(reserve_uuid"
           ",reserve_pub"
           ",expiration_date"
           ",gc_date"
           ") VALUES "
           "($1, $2, $3, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves",
                                             params);
}


/**
 * Function called with reserves_in records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_in (struct PostgresClosure *pg,
                           const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.reserves_in.wire_reference),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_in.credit),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_in.sender_account_h_payto),
    GNUNET_PQ_query_param_string (
      td->details.reserves_in.exchange_account_section),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_in.execution_date),
    GNUNET_PQ_query_param_auto_from_type (&td->details.reserves_in.reserve_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_reserves_in",
           "INSERT INTO reserves_in"
           "(reserve_in_serial_id"
           ",wire_reference"
           ",credit"
           ",wire_source_h_payto"
           ",exchange_account_section"
           ",execution_date"
           ",reserve_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_in",
                                             params);
}


/**
 * Function called with kycauth_in records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_kycauths_in (struct PostgresClosure *pg,
                           const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.kycauth_in.wire_reference),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_in.credit),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_in.sender_account_h_payto),
    GNUNET_PQ_query_param_string (
      td->details.reserves_in.exchange_account_section),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_in.execution_date),
    GNUNET_PQ_query_param_auto_from_type (&td->details.kycauth_in.account_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_kycauth_in",
           "INSERT INTO kycauths_in"
           "(kycauth_in_serial_id"
           ",wire_reference"
           ",credit"
           ",wire_source_h_payto"
           ",exchange_account_section"
           ",execution_date"
           ",account_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_kycauth_in",
                                             params);
}


/**
 * Function called with reserves_open_requests records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_open_requests (struct PostgresClosure *pg,
                                      const struct
                                      TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_open_requests.expiration_date),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_requests.reserve_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_open_requests.reserve_payment),
    GNUNET_PQ_query_param_uint32 (
      &td->details.reserves_open_requests.requested_purse_limit),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_reserves_open_requests",
           "INSERT INTO reserves_open_requests"
           "(open_request_uuid"
           ",reserve_pub"
           ",request_timestamp"
           ",expiration_date"
           ",reserve_sig"
           ",reserve_payment"
           ",requested_purse_limit"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_open_requests",
                                             params);
}


/**
 * Function called with reserves_open_requests records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_open_deposits (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_deposits.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_deposits.coin_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_deposits.reserve_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_open_deposits.contribution),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_reserves_open_deposits",
           "INSERT INTO reserves_open_deposits"
           "(reserve_open_deposit_uuid"
           ",reserve_sig"
           ",reserve_pub"
           ",coin_pub"
           ",coin_sig"
           ",contribution"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_open_deposits",
                                             params);
}


/**
 * Function called with reserves_close records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_close (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_close.execution_date),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close.wtid),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close.sender_account_h_payto),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_close.amount),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_close.closing_fee),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close.reserve_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_reserves_close",
           "INSERT INTO reserves_close"
           "(close_uuid"
           ",execution_date"
           ",wtid"
           ",wire_target_h_payto"
           ",amount"
           ",closing_fee"
           ",reserve_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_close",
                                             params);
}


/**
 * Function called with reserves_out records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_reserves_out (struct PostgresClosure *pg,
                            const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_out.h_blind_ev),
    GNUNET_PQ_query_param_uint64 (
      &td->details.reserves_out.denominations_serial),
    TALER_PQ_query_param_blinded_denom_sig (
      &td->details.reserves_out.denom_sig),
    GNUNET_PQ_query_param_uint64 (
      &td->details.reserves_out.reserve_uuid),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_out.reserve_sig),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_out.execution_date),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.reserves_out.amount_with_fee),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_reserves_out",
           "INSERT INTO reserves_out"
           "(reserve_out_serial_id"
           ",h_blind_ev"
           ",denominations_serial"
           ",denom_sig"
           ",reserve_uuid"
           ",reserve_sig"
           ",execution_date"
           ",amount_with_fee"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_out",
                                             params);
}


/**
 * Function called with auditors records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_auditors (struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.auditors.auditor_pub),
    GNUNET_PQ_query_param_string (td->details.auditors.auditor_name),
    GNUNET_PQ_query_param_string (td->details.auditors.auditor_url),
    GNUNET_PQ_query_param_bool (td->details.auditors.is_active),
    GNUNET_PQ_query_param_timestamp (&td->details.auditors.last_change),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_auditors",
           "INSERT INTO auditors"
           "(auditor_uuid"
           ",auditor_pub"
           ",auditor_name"
           ",auditor_url"
           ",is_active"
           ",last_change"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_auditors",
                                             params);
}


/**
 * Function called with auditor_denom_sigs records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_auditor_denom_sigs (struct PostgresClosure *pg,
                                  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.auditor_denom_sigs.auditor_uuid),
    GNUNET_PQ_query_param_uint64 (
      &td->details.auditor_denom_sigs.denominations_serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.auditor_denom_sigs.auditor_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_auditor_denom_sigs",
           "INSERT INTO auditor_denom_sigs"
           "(auditor_denom_serial"
           ",auditor_uuid"
           ",denominations_serial"
           ",auditor_sig"
           ") VALUES "
           "($1, $2, $3, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_auditor_denom_sigs",
                                             params);
}


/**
 * Function called with exchange_sign_keys records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_exchange_sign_keys (struct PostgresClosure *pg,
                                  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.exchange_sign_keys.exchange_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.exchange_sign_keys.master_sig),
    GNUNET_PQ_query_param_timestamp (
      &td->details.exchange_sign_keys.meta.start),
    GNUNET_PQ_query_param_timestamp (
      &td->details.exchange_sign_keys.meta.expire_sign),
    GNUNET_PQ_query_param_timestamp (
      &td->details.exchange_sign_keys.meta.expire_legal),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_exchange_sign_keys",
           "INSERT INTO exchange_sign_keys"
           "(esk_serial"
           ",exchange_pub"
           ",master_sig"
           ",valid_from"
           ",expire_sign"
           ",expire_legal"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_exchange_sign_keys",
                                             params);
}


/**
 * Function called with signkey_revocations records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_signkey_revocations (struct PostgresClosure *pg,
                                   const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.signkey_revocations.esk_serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.signkey_revocations.master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_signkey_revocations",
           "INSERT INTO signkey_revocations"
           "(signkey_revocations_serial_id"
           ",esk_serial"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_signkey_revocations",
                                             params);
}


/**
 * Function called with known_coins records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_known_coins (struct PostgresClosure *pg,
                           const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.known_coins.coin_pub),
    TALER_PQ_query_param_denom_sig (
      &td->details.known_coins.denom_sig),
    GNUNET_PQ_query_param_uint64 (
      &td->details.known_coins.denominations_serial),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_known_coins",
           "INSERT INTO known_coins"
           "(known_coin_id"
           ",coin_pub"
           ",denom_sig"
           ",denominations_serial"
           ") VALUES "
           "($1, $2, $3, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_known_coins",
                                             params);
}


/**
 * Function called with refresh_commitments records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refresh_commitments (struct PostgresClosure *pg,
                                   const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.refresh_commitments.rc),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.refresh_commitments.old_coin_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.refresh_commitments.amount_with_fee),
    GNUNET_PQ_query_param_uint32 (
      &td->details.refresh_commitments.noreveal_index),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.refresh_commitments.old_coin_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_refresh_commitments",
           "INSERT INTO refresh_commitments"
           "(melt_serial_id"
           ",rc"
           ",old_coin_sig"
           ",amount_with_fee"
           ",noreveal_index"
           ",old_coin_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_refresh_commitments",
                                             params);
}


/**
 * Function called with refresh_revealed_coins records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refresh_revealed_coins (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_HashCode h_coin_ev;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint32 (
      &td->details.refresh_revealed_coins.freshcoin_index),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.refresh_revealed_coins.link_sig),
    GNUNET_PQ_query_param_fixed_size (
      td->details.refresh_revealed_coins.coin_ev,
      td->details.refresh_revealed_coins.
      coin_ev_size),
    GNUNET_PQ_query_param_auto_from_type (&h_coin_ev),
    TALER_PQ_query_param_blinded_denom_sig (
      &td->details.refresh_revealed_coins.ev_sig),
    TALER_PQ_query_param_exchange_withdraw_values (
      &td->details.refresh_revealed_coins.ewv),
    GNUNET_PQ_query_param_uint64 (
      &td->details.refresh_revealed_coins.denominations_serial),
    GNUNET_PQ_query_param_uint64 (
      &td->details.refresh_revealed_coins.melt_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
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
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);");
  GNUNET_CRYPTO_hash (td->details.refresh_revealed_coins.coin_ev,
                      td->details.refresh_revealed_coins.coin_ev_size,
                      &h_coin_ev);
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_refresh_revealed_coins",
                                             params);
}


/**
 * Function called with refresh_transfer_keys records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refresh_transfer_keys (
  struct PostgresClosure *pg,
  const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.refresh_transfer_keys.tp),
    GNUNET_PQ_query_param_fixed_size (
      &td->details.refresh_transfer_keys.tprivs[0],
      (TALER_CNC_KAPPA - 1)
      * sizeof (struct TALER_TransferPrivateKeyP)),
    GNUNET_PQ_query_param_uint64 (
      &td->details.refresh_transfer_keys.melt_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_refresh_transfer_keys",
           "INSERT INTO refresh_transfer_keys"
           "(rtc_serial"
           ",transfer_pub"
           ",transfer_privs"
           ",melt_serial_id"
           ") VALUES "
           "($1, $2, $3, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_refresh_transfer_keys",
                                             params);
}


/**
 * Function called with batch deposits records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_batch_deposits (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.batch_deposits.shard),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.batch_deposits.merchant_pub),
    GNUNET_PQ_query_param_timestamp (
      &td->details.batch_deposits.wallet_timestamp),
    GNUNET_PQ_query_param_timestamp (
      &td->details.batch_deposits.exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (
      &td->details.batch_deposits.refund_deadline),
    GNUNET_PQ_query_param_timestamp (&td->details.batch_deposits.wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.batch_deposits.h_contract_terms),
    td->details.batch_deposits.no_wallet_data_hash
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (
      &td->details.batch_deposits.wallet_data_hash),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.batch_deposits.wire_salt),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.batch_deposits.wire_target_h_payto),
    GNUNET_PQ_query_param_bool (td->details.batch_deposits.policy_blocked),
    td->details.batch_deposits.no_policy_details
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_uint64 (
      &td->details.batch_deposits.policy_details_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_batch_deposits",
           "INSERT INTO batch_deposits"
           "(batch_deposit_serial_id"
           ",shard"
           ",merchant_pub"
           ",wallet_timestamp"
           ",exchange_timestamp"
           ",refund_deadline"
           ",wire_deadline"
           ",h_contract_terms"
           ",wallet_data_hash"
           ",wire_salt"
           ",wire_target_h_payto"
           ",policy_blocked"
           ",policy_details_serial_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_batch_deposits",
                                             params);
}


/**
 * Function called with deposits records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_coin_deposits (struct PostgresClosure *pg,
                             const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (
      &td->details.coin_deposits.batch_deposit_serial_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.coin_deposits.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.coin_deposits.coin_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.coin_deposits.amount_with_fee),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_coin_deposits",
           "INSERT INTO coin_deposits"
           "(coin_deposit_serial_id"
           ",batch_deposit_serial_id"
           ",coin_pub"
           ",coin_sig"
           ",amount_with_fee"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_coin_deposits",
                                             params);
}


/**
 * Function called with refunds records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_refunds (struct PostgresClosure *pg,
                       const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.refunds.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&td->details.refunds.merchant_sig),
    GNUNET_PQ_query_param_uint64 (&td->details.refunds.rtransaction_id),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.refunds.amount_with_fee),
    GNUNET_PQ_query_param_uint64 (
      &td->details.refunds.batch_deposit_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_refunds",
           "INSERT INTO refunds"
           "(refund_serial_id"
           ",coin_pub"
           ",merchant_sig"
           ",rtransaction_id"
           ",amount_with_fee"
           ",batch_deposit_serial_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_refunds",
                                             params);
}


/**
 * Function called with wire_out records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wire_out (struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_timestamp (&td->details.wire_out.execution_date),
    GNUNET_PQ_query_param_auto_from_type (&td->details.wire_out.wtid_raw),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wire_out.wire_target_h_payto),
    GNUNET_PQ_query_param_string (
      td->details.wire_out.exchange_account_section),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wire_out.amount),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wire_out",
           "INSERT INTO wire_out"
           "(wireout_uuid"
           ",execution_date"
           ",wtid_raw"
           ",wire_target_h_payto"
           ",exchange_account_section"
           ",amount"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wire_out",
                                             params);
}


/**
 * Function called with aggregation_tracking records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_aggregation_tracking (struct PostgresClosure *pg,
                                    const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (
      &td->details.aggregation_tracking.batch_deposit_serial_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aggregation_tracking.wtid_raw),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_aggregation_tracking",
           "INSERT INTO aggregation_tracking"
           "(aggregation_serial_id"
           ",batch_deposit_serial_id"
           ",wtid_raw"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_aggregation_tracking",
                                             params);
}


/**
 * Function called with wire_fee records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wire_fee (struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_string (td->details.wire_fee.wire_method),
    GNUNET_PQ_query_param_timestamp (&td->details.wire_fee.start_date),
    GNUNET_PQ_query_param_timestamp (&td->details.wire_fee.end_date),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wire_fee.fees.wire),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wire_fee.fees.closing),
    GNUNET_PQ_query_param_auto_from_type (&td->details.wire_fee.master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wire_fee",
           "INSERT INTO wire_fee"
           "(wire_fee_serial"
           ",wire_method"
           ",start_date"
           ",end_date"
           ",wire_fee"
           ",closing_fee"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wire_fee",
                                             params);
}


/**
 * Function called with wire_fee records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_global_fee (struct PostgresClosure *pg,
                          const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (
      &td->serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.global_fee.start_date),
    GNUNET_PQ_query_param_timestamp (
      &td->details.global_fee.end_date),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.global_fee.fees.history),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.global_fee.fees.account),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.global_fee.fees.purse),
    GNUNET_PQ_query_param_relative_time (
      &td->details.global_fee.purse_timeout),
    GNUNET_PQ_query_param_relative_time (
      &td->details.global_fee.history_expiration),
    GNUNET_PQ_query_param_uint32 (
      &td->details.global_fee.purse_account_limit),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.global_fee.master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_global_fee",
           "INSERT INTO global_fee"
           "(global_fee_serial"
           ",start_date"
           ",end_date"
           ",history_fee"
           ",account_fee"
           ",purse_fee"
           ",purse_timeout"
           ",history_expiration"
           ",purse_account_limit"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_global_fee",
                                             params);
}


/**
 * Function called with recoup records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_recoup (struct PostgresClosure *pg,
                      const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.recoup.coin_sig),
    GNUNET_PQ_query_param_auto_from_type (&td->details.recoup.coin_blind),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.recoup.amount),
    GNUNET_PQ_query_param_timestamp (&td->details.recoup.timestamp),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.recoup.coin_pub),
    GNUNET_PQ_query_param_uint64 (&td->details.recoup.reserve_out_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_recoup",
           "INSERT INTO recoup"
           "(recoup_uuid"
           ",coin_sig"
           ",coin_blind"
           ",amount"
           ",recoup_timestamp"
           ",coin_pub"
           ",reserve_out_serial_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_recoup",
                                             params);
}


/**
 * Function called with recoup_refresh records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_recoup_refresh (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.recoup_refresh.coin_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.recoup_refresh.coin_blind),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.recoup_refresh.amount),
    GNUNET_PQ_query_param_timestamp (&td->details.recoup_refresh.timestamp),
    GNUNET_PQ_query_param_uint64 (&td->details.recoup_refresh.known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.recoup.coin_pub),
    GNUNET_PQ_query_param_uint64 (&td->details.recoup_refresh.rrc_serial),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_recoup_refresh",
           "INSERT INTO recoup_refresh"
           "(recoup_refresh_uuid"
           ",coin_sig"
           ",coin_blind"
           ",amount"
           ",recoup_timestamp"
           ",known_coin_id"
           ",coin_pub"
           ",rrc_serial"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_recoup_refresh",
                                             params);
}


/**
 * Function called with extensions records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_extensions (struct PostgresClosure *pg,
                          const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_string (td->details.extensions.name),
    NULL == td->details.extensions.manifest ?
    GNUNET_PQ_query_param_null () :
    GNUNET_PQ_query_param_string (td->details.extensions.manifest),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_extensions",
           "INSERT INTO extensions"
           "(extension_id"
           ",name"
           ",manifest"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_extensions",
                                             params);
}


/**
 * Function called with policy_details records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_policy_details (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.policy_details.hash_code),
    (td->details.policy_details.no_policy_json)
      ? GNUNET_PQ_query_param_null ()
      : TALER_PQ_query_param_json (td->details.policy_details.policy_json),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.policy_details.commitment),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.policy_details.accumulated_total),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.policy_details.fee),
    TALER_PQ_query_param_amount (pg->conn,
                                 &td->details.policy_details.transferable),
    GNUNET_PQ_query_param_timestamp (&td->details.policy_details.deadline),
    GNUNET_PQ_query_param_uint16 (
      &td->details.policy_details.fulfillment_state),
    (td->details.policy_details.no_fulfillment_id)
      ? GNUNET_PQ_query_param_null ()
      : GNUNET_PQ_query_param_uint64 (
      &td->details.policy_details.fulfillment_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_policy_details",
           "INSERT INTO policy_details"
           "(policy_details_serial_id"
           ",policy_hash_code"
           ",policy_json"
           ",deadline"
           ",commitment"
           ",accumulated_total"
           ",fee"
           ",transferable"
           ",fulfillment_state"
           ",fulfillment_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_policy_details",
                                             params);
}


/**
 * Function called with policy_fulfillment records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_policy_fulfillments (struct PostgresClosure *pg,
                                   const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.policy_fulfillments.fulfillment_timestamp),
    (NULL == td->details.policy_fulfillments.fulfillment_proof)
      ? GNUNET_PQ_query_param_null ()
      : GNUNET_PQ_query_param_string (
      td->details.policy_fulfillments.fulfillment_proof),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.policy_fulfillments.h_fulfillment_proof),
    GNUNET_PQ_query_param_fixed_size (
      td->details.policy_fulfillments.policy_hash_codes,
      td->details.policy_fulfillments.policy_hash_codes_count),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_policy_fulfillments",
           "INSERT INTO policy_fulfillments "
           "(fulfillment_id"
           ",fulfillment_timestamp"
           ",fulfillment_proof"
           ",h_fulfillment_proof"
           ",policy_hash_codes"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_policy_fulfillments",
                                             params);
}


/**
 * Function called with purse_requests records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_purse_requests (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_requests.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_requests.merge_pub),
    GNUNET_PQ_query_param_timestamp (
      &td->details.purse_requests.purse_creation),
    GNUNET_PQ_query_param_timestamp (
      &td->details.purse_requests.purse_expiration),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_requests.h_contract_terms),
    GNUNET_PQ_query_param_uint32 (&td->details.purse_requests.age_limit),
    GNUNET_PQ_query_param_uint32 (&td->details.purse_requests.flags),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.purse_requests.amount_with_fee),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.purse_requests.purse_fee),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_requests.purse_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_purse_requests",
           "INSERT INTO purse_requests"
           "(purse_requests_serial_id"
           ",purse_pub"
           ",merge_pub"
           ",purse_creation"
           ",purse_expiration"
           ",h_contract_terms"
           ",age_limit"
           ",flags"
           ",amount_with_fee"
           ",purse_fee"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_requests",
                                             params);
}


/**
 * Function called with purse_decision records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_purse_decision (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_decision.purse_pub),
    GNUNET_PQ_query_param_timestamp (
      &td->details.purse_decision.action_timestamp),
    GNUNET_PQ_query_param_bool (
      td->details.purse_decision.refunded),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_purse_refunds",
           "INSERT INTO purse_refunds"
           "(purse_refunds_serial_id"
           ",purse_pub"
           ",action_timestamp"
           ",refunded"
           ") VALUES "
           "($1, $2, $3, $4);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_decision",
                                             params);
}


/**
 * Function called with purse_merges records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_purse_merges (struct PostgresClosure *pg,
                            const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.purse_merges.partner_serial_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_merges.reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (&td->details.purse_merges.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (&td->details.purse_merges.merge_sig),
    GNUNET_PQ_query_param_timestamp (&td->details.purse_merges.merge_timestamp),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_purse_merges",
           "INSERT INTO purse_merges"
           "(purse_merge_request_serial_id"
           ",partner_serial_id"
           ",reserve_pub"
           ",purse_pub"
           ",merge_sig"
           ",merge_timestamp"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_merges",
                                             params);
}


/**
 * Function called with purse_deposits records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_purse_deposits (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (
      &td->details.purse_deposits.partner_serial_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_deposits.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (&td->details.purse_deposits.coin_pub),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.purse_deposits.amount_with_fee),
    GNUNET_PQ_query_param_auto_from_type (&td->details.purse_deposits.coin_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_purse_deposits",
           "INSERT INTO purse_deposits"
           "(purse_deposit_serial_id"
           ",partner_serial_id"
           ",purse_pub"
           ",coin_pub"
           ",amount_with_fee"
           ",coin_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_deposits",
                                             params);
}


/**
x * Function called with account_mergers records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_account_mergers (struct PostgresClosure *pg,
                               const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.account_merges.reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.account_merges.reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.account_merges.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.account_merges.wallet_h_payto),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_account_merges",
           "INSERT INTO account_merges"
           "(account_merge_request_serial_id"
           ",reserve_pub"
           ",reserve_sig"
           ",purse_pub"
           ",wallet_h_payto"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_account_merges",
                                             params);
}


/**
 * Function called with history_requests records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_history_requests (struct PostgresClosure *pg,
                                const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.history_requests.reserve_pub),
    GNUNET_PQ_query_param_timestamp (
      &td->details.history_requests.request_timestamp),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.history_requests.reserve_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.history_requests.history_fee),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_history_requests",
           "INSERT INTO history_requests"
           "(history_request_serial_id"
           ",reserve_pub"
           ",request_timestamp"
           ",reserve_sig"
           ",history_fee"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_history_requests",
                                             params);
}


/**
 * Function called with close_requests records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_close_requests (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.close_requests.reserve_pub),
    GNUNET_PQ_query_param_timestamp (
      &td->details.close_requests.close_timestamp),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.close_requests.reserve_sig),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.close_requests.close),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.close_requests.close_fee),
    GNUNET_PQ_query_param_string (
      td->details.close_requests.payto_uri.full_payto),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_close_requests",
           "INSERT INTO close_requests"
           "(close_request_serial_id"
           ",reserve_pub"
           ",close_timestamp"
           ",reserve_sig"
           ",close"
           ",close_fee"
           ",payto_uri"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_close_requests",
                                             params);
}


/**
 * Function called with wads_out records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wads_out (struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.wads_out.wad_id),
    GNUNET_PQ_query_param_uint64 (&td->details.wads_out.partner_serial_id),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_out.amount),
    GNUNET_PQ_query_param_timestamp (&td->details.wads_out.execution_time),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wads_out",
           "INSERT INTO wads_out"
           "(wad_out_serial_id"
           ",wad_id"
           ",partner_serial_id"
           ",amount"
           ",execution_time"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wads_out",
                                             params);
}


/**
 * Function called with wads_out_entries records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wads_out_entries (struct PostgresClosure *pg,
                                const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (
      &td->details.wads_out_entries.wad_out_serial_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_out_entries.reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_out_entries.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_out_entries.h_contract),
    GNUNET_PQ_query_param_timestamp (
      &td->details.wads_out_entries.purse_expiration),
    GNUNET_PQ_query_param_timestamp (
      &td->details.wads_out_entries.merge_timestamp),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_out_entries.amount_with_fee),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_out_entries.wad_fee),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_out_entries.deposit_fees),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_out_entries.reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_out_entries.purse_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wad_out_entries",
           "INSERT INTO wad_out_entries"
           "(wad_out_entry_serial_id"
           ",wad_out_serial_id"
           ",reserve_pub"
           ",purse_pub"
           ",h_contract"
           ",purse_expiration"
           ",merge_timestamp"
           ",amount_with_fee"
           ",wad_fee"
           ",deposit_fees"
           ",reserve_sig"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wads_out_entries",
                                             params);
}


/**
 * Function called with wads_in records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wads_in (struct PostgresClosure *pg,
                       const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&td->details.wads_in.wad_id),
    GNUNET_PQ_query_param_string (td->details.wads_in.origin_exchange_url),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_in.amount),
    GNUNET_PQ_query_param_timestamp (&td->details.wads_in.arrival_time),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wads_in",
           "INSERT INTO wads_in"
           "(wad_in_serial_id"
           ",wad_id"
           ",origin_exchange_url"
           ",amount"
           ",arrival_time"
           ") VALUES "
           "($1, $2, $3, $4, $5);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wads_in",
                                             params);
}


/**
 * Function called with wads_in_entries records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_wads_in_entries (struct PostgresClosure *pg,
                               const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_in_entries.reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_in_entries.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_in_entries.h_contract),
    GNUNET_PQ_query_param_timestamp (
      &td->details.wads_in_entries.purse_expiration),
    GNUNET_PQ_query_param_timestamp (
      &td->details.wads_in_entries.merge_timestamp),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_in_entries.amount_with_fee),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_in_entries.wad_fee),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.wads_in_entries.deposit_fees),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_in_entries.reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wads_in_entries.purse_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wad_in_entries",
           "INSERT INTO wad_in_entries"
           "(wad_in_entry_serial_id"
           ",wad_in_serial_id"
           ",reserve_pub"
           ",purse_pub"
           ",h_contract"
           ",purse_expiration"
           ",merge_timestamp"
           ",amount_with_fee"
           ",wad_fee"
           ",deposit_fees"
           ",reserve_sig"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wads_in_entries",
                                             params);
}


/**
 * Function called with profit_drains records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_profit_drains (struct PostgresClosure *pg,
                             const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.profit_drains.wtid),
    GNUNET_PQ_query_param_string (
      td->details.profit_drains.account_section),
    GNUNET_PQ_query_param_string (
      td->details.profit_drains.payto_uri.full_payto),
    GNUNET_PQ_query_param_timestamp (
      &td->details.profit_drains.trigger_date),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.profit_drains.amount),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.profit_drains.master_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_profit_drains",
           "INSERT INTO profit_drains"
           "(profit_drain_serial_id"
           ",wtid"
           ",account_section"
           ",payto_uri"
           ",trigger_date"
           ",amount"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_profit_drains",
                                             params);
}


/**
 * Function called with aml_staff records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_aml_staff (struct PostgresClosure *pg,
                         const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aml_staff.decider_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aml_staff.master_sig),
    GNUNET_PQ_query_param_string (
      td->details.aml_staff.decider_name),
    GNUNET_PQ_query_param_bool (
      td->details.aml_staff.is_active),
    GNUNET_PQ_query_param_bool (
      td->details.aml_staff.read_only),
    GNUNET_PQ_query_param_timestamp (
      &td->details.aml_staff.last_change),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_aml_staff",
           "INSERT INTO aml_staff"
           "(aml_staff_uuid"
           ",decider_pub"
           ",master_sig"
           ",decider_name"
           ",is_active"
           ",read_only"
           ",last_change"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_aml_staff",
                                             params);
}


/**
 * Function called with kyc_attributes records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_kyc_attributes (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.kyc_attributes.h_payto),
    GNUNET_PQ_query_param_uint64 (
      &td->details.kyc_attributes.legitimization_serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.kyc_attributes.collection_time),
    GNUNET_PQ_query_param_timestamp (
      &td->details.kyc_attributes.expiration_time),
    GNUNET_PQ_query_param_uint64 (
      &td->details.kyc_attributes.trigger_outcome_serial),
    GNUNET_PQ_query_param_fixed_size (
      &td->details.kyc_attributes.encrypted_attributes,
      td->details.kyc_attributes.encrypted_attributes_size),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_kyc_attributes",
           "INSERT INTO kyc_attributes"
           "(kyc_attributes_serial_id"
           ",h_payto"
           ",legitimization_serial"
           ",collection_time"
           ",expiration_time"
           ",trigger_outcome_serial"
           ",encrypted_attributes"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_kyc_attributes",
                                             params);
}


/**
 * Function called with aml_history records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_aml_history (struct PostgresClosure *pg,
                           const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aml_history.h_payto),
    GNUNET_PQ_query_param_uint64 (
      &td->details.aml_history.outcome_serial_id),
    GNUNET_PQ_query_param_string (
      td->details.aml_history.justification),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aml_history.decider_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aml_history.decider_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_aml_history",
           "INSERT INTO aml_history"
           "(aml_history_serial_id"
           ",h_payto"
           ",outcome_serial_id"
           ",justification"
           ",decider_pub"
           ",decider_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_aml_history",
                                             params);
}


/**
 * Function called with kyc_event records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_kyc_events (struct PostgresClosure *pg,
                          const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.kyc_events.event_timestamp),
    GNUNET_PQ_query_param_string (
      td->details.kyc_events.event_type),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_kyc_events",
           "INSERT INTO kyc_events"
           "(kyc_event_serial_id"
           ",event_timestamp"
           ",event_type"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_kyc_events",
                                             params);
}


/**
 * Function called with purse_deletion records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_purse_deletion (struct PostgresClosure *pg,
                              const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_deletion.purse_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_deletion.purse_sig),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_purse_deletion",
           "INSERT INTO purse_deletion"
           "(purse_deletion_serial_id"
           ",purse_pub"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_deletion",
                                             params);
}


/**
 * Function called with age_withdraw records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_age_withdraw (struct PostgresClosure *pg,
                            const struct
                            TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.age_withdraw.h_commitment),
    TALER_PQ_query_param_amount (
      pg->conn,
      &td->details.age_withdraw.amount_with_fee),
    GNUNET_PQ_query_param_uint16 (
      &td->details.age_withdraw.max_age),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.age_withdraw.reserve_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.age_withdraw.reserve_sig),
    GNUNET_PQ_query_param_uint32 (
      &td->details.age_withdraw.noreveal_index),
    /* TODO: other fields, too! */
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_age_withdraw",
           "INSERT INTO age_withdraw"
           "(age_withdraw_commitment_id"
           ",h_commitment"
           ",amount_with_fee"
           ",max_age"
           ",reserve_pub"
           ",reserve_sig"
           ",noreveal_index"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_age_withdraw",
                                             params);
}


enum GNUNET_DB_QueryStatus
TEH_PG_insert_records_by_table (void *cls,
                                const struct TALER_EXCHANGEDB_TableData *td)
{
  struct PostgresClosure *pg = cls;
  InsertRecordCallback rh = NULL;

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
  case TALER_EXCHANGEDB_RT_KYCAUTHS_IN:
    rh = &irbt_cb_table_kycauths_in;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_CLOSE:
    rh = &irbt_cb_table_reserves_close;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OPEN_REQUESTS:
    rh = &irbt_cb_table_reserves_open_requests;
    break;
  case TALER_EXCHANGEDB_RT_RESERVES_OPEN_DEPOSITS:
    rh = &irbt_cb_table_reserves_open_deposits;
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
  case TALER_EXCHANGEDB_RT_BATCH_DEPOSITS:
    rh = &irbt_cb_table_batch_deposits;
    break;
  case TALER_EXCHANGEDB_RT_COIN_DEPOSITS:
    rh = &irbt_cb_table_coin_deposits;
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
  case TALER_EXCHANGEDB_RT_POLICY_DETAILS:
    rh = &irbt_cb_table_policy_details;
    break;
  case TALER_EXCHANGEDB_RT_POLICY_FULFILLMENTS:
    rh = &irbt_cb_table_policy_fulfillments;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_REQUESTS:
    rh = &irbt_cb_table_purse_requests;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DECISION:
    rh = &irbt_cb_table_purse_decision;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_MERGES:
    rh = &irbt_cb_table_purse_merges;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DEPOSITS:
    rh = &irbt_cb_table_purse_deposits;
    break;
  case TALER_EXCHANGEDB_RT_ACCOUNT_MERGES:
    rh = &irbt_cb_table_account_mergers;
    break;
  case TALER_EXCHANGEDB_RT_HISTORY_REQUESTS:
    rh = &irbt_cb_table_history_requests;
    break;
  case TALER_EXCHANGEDB_RT_CLOSE_REQUESTS:
    rh = &irbt_cb_table_close_requests;
    break;
  case TALER_EXCHANGEDB_RT_WADS_OUT:
    rh = &irbt_cb_table_wads_out;
    break;
  case TALER_EXCHANGEDB_RT_WADS_OUT_ENTRIES:
    rh = &irbt_cb_table_wads_out_entries;
    break;
  case TALER_EXCHANGEDB_RT_WADS_IN:
    rh = &irbt_cb_table_wads_in;
    break;
  case TALER_EXCHANGEDB_RT_WADS_IN_ENTRIES:
    rh = &irbt_cb_table_wads_in_entries;
    break;
  case TALER_EXCHANGEDB_RT_PROFIT_DRAINS:
    rh = &irbt_cb_table_profit_drains;
    break;
  case TALER_EXCHANGEDB_RT_AML_STAFF:
    rh = &irbt_cb_table_aml_staff;
    break;
  case TALER_EXCHANGEDB_RT_PURSE_DELETION:
    rh = &irbt_cb_table_purse_deletion;
    break;
  case TALER_EXCHANGEDB_RT_AGE_WITHDRAW:
    rh = &irbt_cb_table_age_withdraw;
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_MEASURES:
    rh = &irbt_cb_table_legitimization_measures;
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_OUTCOMES:
    rh = &irbt_cb_table_legitimization_outcomes;
    break;
  case TALER_EXCHANGEDB_RT_LEGITIMIZATION_PROCESSES:
    rh = &irbt_cb_table_legitimization_processes;
    break;
  case TALER_EXCHANGEDB_RT_KYC_ATTRIBUTES:
    rh = &irbt_cb_table_kyc_attributes;
    break;
  case TALER_EXCHANGEDB_RT_AML_HISTORY:
    rh = &irbt_cb_table_aml_history;
    break;
  case TALER_EXCHANGEDB_RT_KYC_EVENTS:
    rh = &irbt_cb_table_kyc_events;
    break;
  }
  if (NULL == rh)
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return rh (pg,
             td);
}


/* end of pg_insert_records_by_table.c */
