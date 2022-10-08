/*
   This file is part of GNUnet
   Copyright (C) 2020, 2021, 2022 Taler Systems SA

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
 * @file exchangedb/irbt_callbacks.c
 * @brief callbacks used by postgres_insert_records_by_table, to be
 *        inlined into the plugin
 * @author Christian Grothoff
 */
#include "pg_helper.h"


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
    TALER_PQ_query_param_amount (&td->details.denominations.coin),
    TALER_PQ_query_param_amount (
      &td->details.denominations.fees.withdraw),
    TALER_PQ_query_param_amount (
      &td->details.denominations.fees.deposit),
    TALER_PQ_query_param_amount (
      &td->details.denominations.fees.refresh),
    TALER_PQ_query_param_amount (
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
           " $11, $12, $13, $14, $15, $16, $17, $18, $19, $20);");

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
  struct TALER_PaytoHashP payto_hash;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (&payto_hash),
    GNUNET_PQ_query_param_string (
      td->details.wire_targets.payto_uri),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wire_targets",
           "INSERT INTO wire_targets"
           "(wire_target_serial_id"
           ",wire_target_h_payto"
           ",payto_uri"
           ") VALUES "
           "($1, $2, $3);");
  TALER_payto_hash (
    td->details.wire_targets.payto_uri,
    &payto_hash);
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
irbt_cb_table_legitimization_processes (struct PostgresClosure *pg,
                                        const struct
                                        TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.legitimization_processes.h_payto),
    GNUNET_PQ_query_param_timestamp (
      &td->details.legitimization_processes.expiration_time),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.provider_section),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.provider_user_id),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_processes.provider_legitimization_id),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_legitimization_processes",
                                             params);
}


/**
 * Function called with records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_legitimization_requirements (struct PostgresClosure *pg,
                                           const struct
                                           TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.legitimization_requirements.h_payto),
    GNUNET_PQ_query_param_string (
      td->details.legitimization_requirements.required_checks),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_legitimization_requirements",
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
    TALER_PQ_query_param_amount (&td->details.reserves_in.credit),
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
           ",credit_val"
           ",credit_frac"
           ",wire_source_h_payto"
           ",exchange_account_section"
           ",execution_date"
           ",reserve_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_in",
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
      &td->details.reserves_open_requests.request_timestamp),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_open_requests.expiration_date),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_requests.reserve_sig),
    TALER_PQ_query_param_amount (
      &td->details.reserves_open_requests.reserve_payment),
    GNUNET_PQ_query_param_uint32 (
      &td->details.reserves_open_requests.requested_purse_limit),
    GNUNET_PQ_query_param_end
  };

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
irbt_cb_table_reserves_open_deposits (struct PostgresClosure *pg,
                                      const struct
                                      TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_open_deposits.request_timestamp),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_deposits.coin_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_deposits.coin_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_open_deposits.reserve_sig),
    TALER_PQ_query_param_amount (
      &td->details.reserves_open_deposits.contribution),
    GNUNET_PQ_query_param_end
  };

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
irbt_cb_table_reserves_close_requests (struct PostgresClosure *pg,
                                       const struct
                                       TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close_requests.reserve_pub),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_close_requests.execution_date),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close_requests.reserve_sig),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close_requests.wire_target_h_payto),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_close_requests",
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
    TALER_PQ_query_param_amount (&td->details.reserves_close.amount),
    TALER_PQ_query_param_amount (&td->details.reserves_close.closing_fee),
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
           ",amount_val"
           ",amount_frac"
           ",closing_fee_val"
           ",closing_fee_frac"
           ",reserve_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);");
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
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);");
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
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",noreveal_index"
           ",old_coin_pub"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
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
 * Function called with deposits records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_deposits (struct PostgresClosure *pg,
                        const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_uint64 (&td->details.deposits.shard),
    GNUNET_PQ_query_param_uint64 (&td->details.deposits.known_coin_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.deposits.coin_pub),
    TALER_PQ_query_param_amount (&td->details.deposits.amount_with_fee),
    GNUNET_PQ_query_param_timestamp (&td->details.deposits.wallet_timestamp),
    GNUNET_PQ_query_param_timestamp (
      &td->details.deposits.exchange_timestamp),
    GNUNET_PQ_query_param_timestamp (&td->details.deposits.refund_deadline),
    GNUNET_PQ_query_param_timestamp (&td->details.deposits.wire_deadline),
    GNUNET_PQ_query_param_auto_from_type (&td->details.deposits.merchant_pub),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.deposits.h_contract_terms),
    GNUNET_PQ_query_param_auto_from_type (&td->details.deposits.coin_sig),
    GNUNET_PQ_query_param_auto_from_type (&td->details.deposits.wire_salt),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.deposits.wire_target_h_payto),
    GNUNET_PQ_query_param_bool (td->details.deposits.extension_blocked),
    0 == td->details.deposits.extension_details_serial_id
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_uint64 (
      &td->details.deposits.extension_details_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
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
           ",extension_blocked"
           ",extension_details_serial_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,"
           " $11, $12, $13, $14, $15, $16, $17);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_deposits",
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
    TALER_PQ_query_param_amount (&td->details.refunds.amount_with_fee),
    GNUNET_PQ_query_param_uint64 (&td->details.refunds.deposit_serial_id),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_refunds",
           "INSERT INTO refunds"
           "(refund_serial_id"
           ",coin_pub"
           ",merchant_sig"
           ",rtransaction_id"
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",deposit_serial_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
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
    TALER_PQ_query_param_amount (&td->details.wire_out.amount),
    GNUNET_PQ_query_param_end
  };


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
      &td->details.aggregation_tracking.deposit_serial_id),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.aggregation_tracking.wtid_raw),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_aggregation_tracking",
           "INSERT INTO aggregation_tracking"
           "(aggregation_serial_id"
           ",deposit_serial_id"
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
    TALER_PQ_query_param_amount (&td->details.wire_fee.fees.wire),
    TALER_PQ_query_param_amount (&td->details.wire_fee.fees.closing),
    TALER_PQ_query_param_amount (&td->details.wire_fee.fees.wad),
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
           ",wire_fee_val"
           ",wire_fee_frac"
           ",closing_fee_val"
           ",closing_fee_frac"
           ",wad_fee_val"
           ",wad_fee_frac"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);");
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
      &td->details.global_fee.fees.history),
    TALER_PQ_query_param_amount (
      &td->details.global_fee.fees.kyc),
    TALER_PQ_query_param_amount (
      &td->details.global_fee.fees.account),
    TALER_PQ_query_param_amount (
      &td->details.global_fee.fees.purse),
    GNUNET_PQ_query_param_relative_time (
      &td->details.global_fee.purse_timeout),
    GNUNET_PQ_query_param_relative_time (
      &td->details.global_fee.kyc_timeout),
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
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16);");
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
    TALER_PQ_query_param_amount (&td->details.recoup.amount),
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
           ",amount_val"
           ",amount_frac"
           ",recoup_timestamp"
           ",coin_pub"
           ",reserve_out_serial_id"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);");
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
    TALER_PQ_query_param_amount (&td->details.recoup_refresh.amount),
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
           ",amount_val"
           ",amount_frac"
           ",recoup_timestamp"
           ",known_coin_id"
           ",coin_pub"
           ",rrc_serial"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9);");
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
    NULL == td->details.extensions.config ?
    GNUNET_PQ_query_param_null () :
    GNUNET_PQ_query_param_string (td->details.extensions.config),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_extensions",
           "INSERT INTO extensions"
           "(extension_id"
           ",name"
           ",config"
           ") VALUES "
           "($1, $2, $3);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_extensions",
                                             params);
}


/**
 * Function called with extension_details records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_extension_details (struct PostgresClosure *pg,
                                 const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    NULL ==
    td->details.extension_details.extension_options ?
    GNUNET_PQ_query_param_null () :
    GNUNET_PQ_query_param_string (
      td->details.extension_details.extension_options),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_extension_details",
           "INSERT INTO extension_details"
           "(extension_details_serial_id"
           ",extension_options"
           ") VALUES "
           "($1, $2);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_extension_details",
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
    TALER_PQ_query_param_amount (&td->details.purse_requests.amount_with_fee),
    TALER_PQ_query_param_amount (&td->details.purse_requests.purse_fee),
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
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",purse_fee_val"
           ",purse_fee_frac"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_requests",
                                             params);
}


/**
 * Function called with purse_refunds records to insert into table.
 *
 * @param pg plugin context
 * @param td record to insert
 */
static enum GNUNET_DB_QueryStatus
irbt_cb_table_purse_refunds (struct PostgresClosure *pg,
                             const struct TALER_EXCHANGEDB_TableData *td)
{
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&td->serial),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.purse_refunds.purse_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_purse_refunds",
           "INSERT INTO purse_refunds"
           "(purse_refunds_serial_id"
           ",purse_pub"
           ") VALUES "
           "($1, $2);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_purse_refunds",
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
    TALER_PQ_query_param_amount (&td->details.purse_deposits.amount_with_fee),
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
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",coin_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7);");
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
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_account_mergers",
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
           ",history_fee_val"
           ",history_fee_frac"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
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
      &td->details.close_requests.close),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_close_requests",
           "INSERT INTO close_requests"
           "(close_request_serial_id"
           ",reserve_pub"
           ",close_timestamp"
           ",reserve_sig"
           ",close_val"
           ",close_frac"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
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
    TALER_PQ_query_param_amount (&td->details.wads_out.amount),
    GNUNET_PQ_query_param_timestamp (&td->details.wads_out.execution_time),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wads_out",
           "INSERT INTO wads_out"
           "(wad_out_serial_id"
           ",wad_id"
           ",partner_serial_id"
           ",amount_val"
           ",amount_frac"
           ",execution_time"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
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
      &td->details.wads_out_entries.amount_with_fee),
    TALER_PQ_query_param_amount (
      &td->details.wads_out_entries.wad_fee),
    TALER_PQ_query_param_amount (
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
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",wad_fee_val"
           ",wad_fee_frac"
           ",deposit_fees_val"
           ",deposit_fees_frac"
           ",reserve_sig"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15);");
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
    TALER_PQ_query_param_amount (&td->details.wads_in.amount),
    GNUNET_PQ_query_param_timestamp (&td->details.wads_in.arrival_time),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "insert_into_table_wads_in",
           "INSERT INTO wads_in"
           "(wad_in_serial_id"
           ",wad_id"
           ",origin_exchange_url"
           ",amount_val"
           ",amount_frac"
           ",arrival_time"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6);");
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
      &td->details.wads_in_entries.amount_with_fee),
    TALER_PQ_query_param_amount (
      &td->details.wads_in_entries.wad_fee),
    TALER_PQ_query_param_amount (
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
           ",amount_with_fee_val"
           ",amount_with_fee_frac"
           ",wad_fee_val"
           ",wad_fee_frac"
           ",deposit_fees_val"
           ",deposit_fees_frac"
           ",reserve_sig"
           ",purse_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15);");
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
      td->details.profit_drains.payto_uri),
    GNUNET_PQ_query_param_timestamp (
      &td->details.profit_drains.trigger_date),
    TALER_PQ_query_param_amount (
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
           ",amount_val"
           ",amount_frac"
           ",master_sig"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6, $7, $8);");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_profit_drains",
                                             params);
}


/* end of irbt_callbacks.c */
