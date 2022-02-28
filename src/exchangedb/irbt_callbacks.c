/*
   This file is part of GNUnet
   Copyright (C) 2020, 2021 Taler Systems SA

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
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.wire_targets.kyc_ok),
    NULL == td->details.wire_targets.external_id
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (
      td->details.wire_targets.external_id),
    GNUNET_PQ_query_param_end
  };

  TALER_payto_hash (
    td->details.wire_targets.payto_uri,
    &payto_hash);
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wire_targets",
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
    TALER_PQ_query_param_amount (&td->details.reserves.current_balance),
    GNUNET_PQ_query_param_timestamp (&td->details.reserves.expiration_date),
    GNUNET_PQ_query_param_timestamp (&td->details.reserves.gc_date),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_uint64 (&td->details.reserves_in.sender_account),
    GNUNET_PQ_query_param_string (
      td->details.reserves_in.exchange_account_section),
    GNUNET_PQ_query_param_timestamp (
      &td->details.reserves_in.execution_date),
    GNUNET_PQ_query_param_auto_from_type (&td->details.reserves_in.reserve_pub),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_reserves_in",
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
    GNUNET_PQ_query_param_uint64 (
      &td->details.reserves_close.wire_target_serial_id),
    TALER_PQ_query_param_amount (&td->details.reserves_close.amount),
    TALER_PQ_query_param_amount (&td->details.reserves_close.closing_fee),
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.reserves_close.reserve_pub),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_bool (&td->details.auditors.is_active),
    GNUNET_PQ_query_param_timestamp (&td->details.auditors.last_change),
    GNUNET_PQ_query_param_end
  };

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
    TALER_PQ_query_param_amount (
      &td->details.known_coins.remaining),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_auto_from_type (
      &td->details.refresh_commitments.h_age_commitment),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_uint64 (&td->details.deposits.wire_target_serial_id),
    GNUNET_PQ_query_param_bool (td->details.deposits.tiny),
    GNUNET_PQ_query_param_bool (td->details.deposits.done),
    GNUNET_PQ_query_param_bool (td->details.deposits.extension_blocked),
    0 == td->details.deposits.extension_details_serial_id
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_uint64 (
      &td->details.deposits.extension_details_serial_id),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_auto_from_type (&td->details.refunds.merchant_sig),
    GNUNET_PQ_query_param_uint64 (&td->details.refunds.rtransaction_id),
    TALER_PQ_query_param_amount (&td->details.refunds.amount_with_fee),
    GNUNET_PQ_query_param_uint64 (&td->details.refunds.deposit_serial_id),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_uint64 (&td->details.wire_out.wire_target_serial_id),
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
    TALER_PQ_query_param_amount (&td->details.wire_fee.wire_fee),
    TALER_PQ_query_param_amount (&td->details.wire_fee.closing_fee),
    GNUNET_PQ_query_param_auto_from_type (&td->details.wire_fee.master_sig),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_wire_fee",
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
    GNUNET_PQ_query_param_uint64 (&td->details.recoup.known_coin_id),
    GNUNET_PQ_query_param_uint64 (&td->details.recoup.reserve_out_serial_id),
    GNUNET_PQ_query_param_end
  };

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
    GNUNET_PQ_query_param_uint64 (&td->details.recoup_refresh.rrc_serial),
    GNUNET_PQ_query_param_end
  };

  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "insert_into_table_recoup_refresh",
                                             params);
}


/* end of irbt_callbacks.c */
