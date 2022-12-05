/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file include/taler_auditordb_plugin.h
 * @brief Low-level (statement-level) database access for the auditor
 * @author Florian Dold
 * @author Christian Grothoff
 */
#ifndef TALER_AUDITORDB_PLUGIN_H
#define TALER_AUDITORDB_PLUGIN_H

#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_db_lib.h>
#include "taler_util.h"
#include "taler_auditordb_lib.h"
#include "taler_signatures.h"


/**
 * Function called with information about exchanges this
 * auditor is monitoring.
 *
 * @param cls closure
 * @param master_pub master public key of the exchange
 * @param exchange_url base URL of the exchange's API
 */
typedef void
(*TALER_AUDITORDB_ExchangeCallback)(
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const char *exchange_url);


/**
 * Function called with the results of select_historic_denom_revenue()
 *
 * @param cls closure
 * @param denom_pub_hash hash of the denomination key
 * @param revenue_timestamp when did this profit get realized
 * @param revenue_balance what was the total profit made from
 *                        deposit fees, melting fees, refresh fees
 *                        and coins that were never returned?
 * @param loss_balance what was the total loss
 * @return sets the return value of select_denomination_info(),
 *         #GNUNET_OK to continue,
 *         #GNUNET_NO to stop processing further rows
 *         #GNUNET_SYSERR or other values on error.
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_AUDITORDB_HistoricDenominationRevenueDataCallback)(
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct GNUNET_TIME_Timestamp revenue_timestamp,
  const struct TALER_Amount *revenue_balance,
  const struct TALER_Amount *loss_balance);


/**
 * Function called with the results of select_historic_reserve_revenue()
 *
 * @param cls closure
 * @param start_time beginning of aggregated time interval
 * @param end_time end of aggregated time interval
 * @param reserve_profits total profits made
 *
 * @return sets the return value of select_denomination_info(),
 *         #GNUNET_OK to continue,
 *         #GNUNET_NO to stop processing further rows
 *         #GNUNET_SYSERR or other values on error.
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_AUDITORDB_HistoricReserveRevenueDataCallback)(
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_Amount *reserve_profits);


/**
 * Structure for remembering the wire auditor's progress over the
 * various tables and (auditor) transactions.
 */
struct TALER_AUDITORDB_WireProgressPoint
{

  /**
   * Time until which we have confirmed that all wire transactions
   * that the exchange should do, have indeed been done.
   */
  struct GNUNET_TIME_Timestamp last_timestamp;

  /**
   * reserves_close uuid until which we have checked
   * reserve closures.
   */
  uint64_t last_reserve_close_uuid;
};


/**
 * Structure for remembering the wire auditor's progress over the
 * various tables and (auditor) transactions per wire account.
 */
struct TALER_AUDITORDB_WireAccountProgressPoint
{
  /**
   * serial ID of the last reserve_in transfer the wire auditor processed
   */
  uint64_t last_reserve_in_serial_id;

  /**
   * serial ID of the last wire_out the wire auditor processed
   */
  uint64_t last_wire_out_serial_id;

};


/**
 * Structure for remembering the wire auditor's progress
 * with respect to the bank transaction histories.
 */
struct TALER_AUDITORDB_BankAccountProgressPoint
{
  /**
   * How far are we in the incoming wire transaction history
   */
  uint64_t in_wire_off;

  /**
   * How far are we in the outgoing wire transaction history
   */
  uint64_t out_wire_off;

};


/**
 * Structure for remembering the auditor's progress over the various
 * tables and (auditor) transactions when analyzing reserves.
 */
struct TALER_AUDITORDB_ProgressPointReserve
{
  /**
   * serial ID of the last reserve_in transfer the auditor processed
   */
  uint64_t last_reserve_in_serial_id;

  /**
   * serial ID of the last reserve_out (withdraw) the auditor processed
   */
  uint64_t last_reserve_out_serial_id;

  /**
   * serial ID of the last recoup entry the auditor processed when
   * considering reserves.
   */
  uint64_t last_reserve_recoup_serial_id;

  /**
   * serial ID of the last open_requests entry the auditor processed.
   */
  uint64_t last_reserve_open_serial_id;

  /**
   * serial ID of the last reserve_close entry the auditor processed.
   */
  uint64_t last_reserve_close_serial_id;

  /**
   * Serial ID of the last purse_decisions entry the auditor processed.
   */
  uint64_t last_purse_decisions_serial_id;

  /**
   * serial ID of the last account_merges entry the auditor processed.
   */
  uint64_t last_account_merges_serial_id;

  /**
   * serial ID of the last history_requests entry the auditor processed.
   */
  uint64_t last_history_requests_serial_id;

};


/**
 * Structure for remembering the auditor's progress over the various
 * tables and (auditor) transactions when analyzing purses.
 */
struct TALER_AUDITORDB_ProgressPointPurse
{
  /**
   * serial ID of the last purse_request transfer the auditor processed
   */
  uint64_t last_purse_request_serial_id;

  /**
   * serial ID of the last purse_decision the auditor processed
   */
  uint64_t last_purse_decision_serial_id;

  /**
   * serial ID of the last purse_merge entry the auditor processed when
   * considering reserves.
   */
  uint64_t last_purse_merge_serial_id;

  /**
   * serial ID of the last account_merge entry the auditor processed.
   */
  uint64_t last_account_merge_serial_id;

  /**
   * serial ID of the last purse_deposits entry the auditor processed.
   */
  uint64_t last_purse_deposits_serial_id;

};


/**
 * Global statistics about purses.
 */
struct TALER_AUDITORDB_PurseBalance
{
  /**
   * Balance in all unmerged and unexpired purses.
   */
  struct TALER_Amount balance;

  /**
   * Total number of open purses.
   */
  uint64_t open_purses;
};


/**
 * Structure for remembering the auditor's progress over the various
 * tables and (auditor) transactions when analyzing reserves.
 */
struct TALER_AUDITORDB_ProgressPointDepositConfirmation
{
  /**
   * serial ID of the last deposit_confirmation the auditor processed
   */
  uint64_t last_deposit_confirmation_serial_id;

};


/**
 * Structure for remembering the auditor's progress over the various
 * tables and (auditor) transactions when analyzing aggregations.
 */
struct TALER_AUDITORDB_ProgressPointAggregation
{

  /**
   * serial ID of the last prewire transfer the auditor processed
   */
  uint64_t last_wire_out_serial_id;
};


/**
 * Structure for remembering the auditor's progress over the various
 * tables and (auditor) transactions when analyzing coins.
 */
struct TALER_AUDITORDB_ProgressPointCoin
{
  /**
   * serial ID of the last withdraw the auditor processed
   */
  uint64_t last_withdraw_serial_id;

  /**
   * serial ID of the last deposit the auditor processed
   */
  uint64_t last_deposit_serial_id;

  /**
   * serial ID of the last refresh the auditor processed
   */
  uint64_t last_melt_serial_id;

  /**
   * serial ID of the last refund the auditor processed
   */
  uint64_t last_refund_serial_id;

  /**
   * Serial ID of the last recoup operation the auditor processed.
   */
  uint64_t last_recoup_serial_id;

  /**
   * Serial ID of the last recoup-of-refresh operation the auditor processed.
   */
  uint64_t last_recoup_refresh_serial_id;

  /**
   * Serial ID of the last reserve_open_deposits operation the auditor processed.
   */
  uint64_t last_open_deposits_serial_id;

  /**
   * Serial ID of the last purse_deposits operation the auditor processed.
   */
  uint64_t last_purse_deposits_serial_id;

  /**
   * Serial ID of the last purse_refunds operation the auditor processed.
   */
  uint64_t last_purse_refunds_serial_id;

};


/**
 * Information about a signing key of an exchange.
 */
struct TALER_AUDITORDB_ExchangeSigningKey
{
  /**
   * Public master key of the exchange that certified @e master_sig.
   */
  struct TALER_MasterPublicKeyP master_public_key;

  /**
   * When does @e exchange_pub start to be used?
   */
  struct GNUNET_TIME_Timestamp ep_start;

  /**
   * When will the exchange stop signing with @e exchange_pub?
   */
  struct GNUNET_TIME_Timestamp ep_expire;

  /**
   * When does the signing key expire (for legal disputes)?
   */
  struct GNUNET_TIME_Timestamp ep_end;

  /**
   * What is the public offline signing key this is all about?
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Signature by the offline master key affirming the above.
   */
  struct TALER_MasterSignatureP master_sig;
};


/**
 * Information about a deposit confirmation we received from
 * a merchant.
 */
struct TALER_AUDITORDB_DepositConfirmation
{

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Hash over the policy extension for the deposit.
   */
  struct TALER_ExtensionPolicyHashP h_policy;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * Time when this deposit confirmation was generated by the exchange.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * How much time does the @e merchant have to issue a refund
   * request?  Zero if refunds are not allowed.  After this time, the
   * coin cannot be refunded.  Note that the wire transfer will not be
   * performed by the exchange until the refund deadline.  This value
   * is taken from the original deposit request.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * How much time does the @e exchange have to wire the funds?
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * Amount to be deposited, excluding fee.  Calculated from the
   * amount with fee and the fee from the deposit request.
   */
  struct TALER_Amount amount_without_fee;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.  The deposit request is to be
   * signed by the corresponding private key (using EdDSA).
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * Signature from the exchange of type
   * #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * Public signing key from the exchange matching @e exchange_sig.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Exchange master signature over @e exchange_sig.
   */
  struct TALER_MasterSignatureP master_sig;

  /**
   * Master public key of the exchange corresponding to @e master_sig.
   * Identifies the exchange this is about.
   */
  struct TALER_MasterPublicKeyP master_public_key;

};


/**
 * Balance values for a reserve (or all reserves).
 */
struct TALER_AUDITORDB_ReserveFeeBalance
{
  /**
   * Remaining funds.
   */
  struct TALER_Amount reserve_balance;

  /**
   * Losses from operations that should not have
   * happened (e.g. negative balance).
   */
  struct TALER_Amount reserve_loss;

  /**
   * Fees charged for withdraw.
   */
  struct TALER_Amount withdraw_fee_balance;

  /**
   * Fees charged for closing.
   */
  struct TALER_Amount close_fee_balance;

  /**
   * Fees charged for purse creation.
   */
  struct TALER_Amount purse_fee_balance;

  /**
   * Opening fees charged.
   */
  struct TALER_Amount open_fee_balance;

  /**
   * History fees charged.
   */
  struct TALER_Amount history_fee_balance;
};


/**
 * Balance data for denominations in circulation.
 */
struct TALER_AUDITORDB_DenominationCirculationData
{
  /**
   * Amount of outstanding coins in circulation.
   */
  struct TALER_Amount denom_balance;

  /**
   * Amount lost due coins illicitly accepted (effectively, a
   * negative @a denom_balance).
   */
  struct TALER_Amount denom_loss;

  /**
   * Total amount that could still be theoretically lost in the future due to
   * recoup operations.  (Total put into circulation minus @e recoup_loss).
   */
  struct TALER_Amount denom_risk;

  /**
   * Amount lost due to recoups.
   */
  struct TALER_Amount recoup_loss;

  /**
   * Number of coins of this denomination that the exchange signed into
   * existence.
   */
  uint64_t num_issued;
};


/**
 * Balance values for all denominations.
 */
struct TALER_AUDITORDB_GlobalCoinBalance
{
  /**
   * Amount of outstanding coins in circulation.
   */
  struct TALER_Amount total_escrowed;

  /**
   * Amount collected in deposit fees.
   */
  struct TALER_Amount deposit_fee_balance;

  /**
   * Amount collected in melt fees.
   */
  struct TALER_Amount melt_fee_balance;

  /**
   * Amount collected in refund fees.
   */
  struct TALER_Amount refund_fee_balance;

  /**
   * Amount collected in purse fees from coins.
   */
  struct TALER_Amount purse_fee_balance;

  /**
   * Amount collected in reserve open deposit fees from coins.
   */
  struct TALER_Amount open_deposit_fee_balance;

  /**
   * Total amount that could still be theoretically
   * lost in the future due to recoup operations.
   * (Total put into circulation minus @e loss
   * and @e irregular_recoup.)
   */
  struct TALER_Amount risk;

  /**
   * Amount lost due to recoups.
   */
  struct TALER_Amount loss;

  /**
   * Amount lost due to coin operations that the exchange
   * should not have permitted.
   */
  struct TALER_Amount irregular_loss;
};


/**
 * Function called with deposit confirmations stored in
 * the auditor's database.
 *
 * @param cls closure
 * @param serial_id location of the @a dc in the database
 * @param dc the deposit confirmation itself
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_AUDITORDB_DepositConfirmationCallback)(
  void *cls,
  uint64_t serial_id,
  const struct TALER_AUDITORDB_DepositConfirmation *dc);


/**
 * Function called on expired purses.
 *
 * @param cls closure
 * @param purse_pub public key of the purse
 * @param balance amount of money in the purse
 * @param expiration_date when did the purse expire?
 * @return #GNUNET_OK to continue to iterate
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_AUDITORDB_ExpiredPurseCallback)(
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *balance,
  struct GNUNET_TIME_Timestamp expiration_date);


/**
 * @brief The plugin API, returned from the plugin's "init" function.
 * The argument given to "init" is simply a configuration handle.
 *
 * Functions starting with "get_" return one result, functions starting
 * with "select_" return multiple results via callbacks.
 */
struct TALER_AUDITORDB_Plugin
{

  /**
   * Closure for all callbacks.
   */
  void *cls;

  /**
   * Name of the library which generated this plugin.  Set by the
   * plugin loader.
   */
  char *library_name;

  /**
   * Fully connect to the db if the connection does not exist yet
   * and check that there is no transaction currently running.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK on success
   *         #GNUNET_NO if we rolled back an earlier transaction
   *         #GNUNET_SYSERR if we have no DB connection
   */
  enum GNUNET_GenericReturnValue
  (*preflight)(void *cls);


  /**
   * Drop all auditor tables OR deletes recoverable auditor state.
   * This should only be used by testcases or when restarting the
   * auditor from scratch.
   *
   * @param cls the `struct PostgresClosure` with the plugin-specific state
   * @param drop_exchangelist drop all tables, including schema versioning
   *        and the exchange and deposit_confirmations table; NOT to be
   *        used when restarting the auditor
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  enum GNUNET_GenericReturnValue
  (*drop_tables)(void *cls,
                 bool drop_exchangelist);


  /**
   * Create the necessary tables if they are not present
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  enum GNUNET_GenericReturnValue
  (*create_tables)(void *cls);


  /**
   * Start a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue
  (*start)(void *cls);


  /**
   * Commit a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*commit)(void *cls);


  /**
   * Abort/rollback a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   */
  void
  (*rollback) (void *cls);


  /**
   * Function called to perform "garbage collection" on the
   * database, expiring records we no longer require.
   *
   * @param cls closure
   * @return #GNUNET_OK on success,
   *         #GNUNET_SYSERR on DB errors
   */
  enum GNUNET_GenericReturnValue
  (*gc)(void *cls);


  /**
   * Insert information about an exchange this auditor will be auditing.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param exchange_url public (base) URL of the API of the exchange
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_exchange)(void *cls,
                     const struct TALER_MasterPublicKeyP *master_pub,
                     const char *exchange_url);


  /**
   * Delete an exchange from the list of exchanges this auditor is auditing.
   * Warning: this will cascade and delete all knowledge of this auditor related
   * to this exchange!
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*delete_exchange)(void *cls,
                     const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Obtain information about exchanges this auditor is auditing.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*list_exchanges)(void *cls,
                    TALER_AUDITORDB_ExchangeCallback cb,
                    void *cb_cls);

  /**
   * Insert information about a signing key of the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param sk signing key information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_exchange_signkey)(
    void *cls,
    const struct TALER_AUDITORDB_ExchangeSigningKey *sk);


  /**
   * Insert information about a deposit confirmation into the database.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param dc deposit confirmation information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_deposit_confirmation)(
    void *cls,
    const struct TALER_AUDITORDB_DepositConfirmation *dc);


  /**
   * Get information about deposit confirmations from the database.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_public_key for which exchange do we want to get deposit confirmations
   * @param start_id row/serial ID where to start the iteration (0 from
   *                  the start, exclusive, i.e. serial_ids must start from 1)
   * @param cb function to call with results
   * @param cb_cls closure for @a cb
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*get_deposit_confirmations)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_public_key,
    uint64_t start_id,
    TALER_AUDITORDB_DepositConfirmationCallback cb,
    void *cb_cls);


  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_coin)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointCoin *ppc);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_coin)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointCoin *ppc);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] ppc set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_coin)(void *cls,
                               const struct TALER_MasterPublicKeyP *master_pub,
                               struct TALER_AUDITORDB_ProgressPointCoin *ppc);

  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppr where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_reserve)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointReserve *ppr);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppr where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_reserve)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointReserve *ppr);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] ppr set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_reserve)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    struct TALER_AUDITORDB_ProgressPointReserve *ppr);

  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppp where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_purse)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointPurse *ppp);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppp where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_purse)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointPurse *ppp);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] ppp set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_purse)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    struct TALER_AUDITORDB_ProgressPointPurse *ppp);


  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppdc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_deposit_confirmation)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppdc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_deposit_confirmation)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] ppdc set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_deposit_confirmation)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc);


  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppa where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_aggregation)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointAggregation *ppa);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param ppa where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_aggregation)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ProgressPointAggregation *ppa);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] ppa set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_aggregation)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    struct TALER_AUDITORDB_ProgressPointAggregation *ppa);


  /**
   * Insert information about the wire auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param pp where is the auditor in processing
   * @param bapp progress in wire transaction histories
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire_auditor_account_progress)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const char *account_name,
    const struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
    const struct TALER_AUDITORDB_BankAccountProgressPoint *bapp);


  /**
   * Update information about the progress of the wire auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param pp where is the auditor in processing
   * @param bapp progress in wire transaction histories
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_wire_auditor_account_progress)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const char *account_name,
    const struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
    const struct TALER_AUDITORDB_BankAccountProgressPoint *bapp);


  /**
   * Get information about the progress of the wire auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param[out] pp where is the auditor in processing
   * @param[out] bapp how far are we in the wire transaction histories
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_auditor_account_progress)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const char *account_name,
    struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
    struct TALER_AUDITORDB_BankAccountProgressPoint *bapp);


  /**
   * Insert information about the wire auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param pp where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire_auditor_progress)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_WireProgressPoint *pp);


  /**
   * Update information about the progress of the wire auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param pp where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_wire_auditor_progress)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_WireProgressPoint *pp);


  /**
   * Get information about the progress of the wire auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param[out] pp set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_auditor_progress)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    struct TALER_AUDITORDB_WireProgressPoint *pp);


  /**
   * Insert information about a reserve.  There must not be an
   * existing record for the reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param rfb balance amounts for the reserve
   * @param expiration_date expiration date of the reserve
   * @param origin_account where did the money in the reserve originally come from
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_reserve_info)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
    struct GNUNET_TIME_Timestamp expiration_date,
    const char *origin_account);


  /**
   * Update information about a reserve.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param rfb balance amounts for the reserve
   * @param expiration_date expiration date of the reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_reserve_info)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
    struct GNUNET_TIME_Timestamp expiration_date);


  /**
   * Get information about a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param[out] rowid which row did we get the information from
   * @param[out] rfb set to balances associated with the reserve
   * @param[out] expiration_date expiration date of the reserve
   * @param[out] sender_account from where did the money in the reserve originally come from
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_reserve_info)(
    void *cls,
    const struct TALER_ReservePublicKeyP *reserve_pub,
    const struct TALER_MasterPublicKeyP *master_pub,
    uint64_t *rowid,
    struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
    struct GNUNET_TIME_Timestamp *expiration_date,
    char **sender_account);


  /**
   * Delete information about a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*del_reserve_info)(void *cls,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Insert information about a purse.  There must not be an
   * existing record for the purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the purse
   * @param master_pub master public key of the exchange
   * @param balance balance of the purse
   * @param expiration_date expiration date of the purse
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_purse_info)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_Amount *balance,
    struct GNUNET_TIME_Timestamp expiration_date);


  /**
   * Update information about a purse.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the purse
   * @param master_pub master public key of the exchange
   * @param balance new balance for the purse
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_purse_info)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_Amount *balance);


  /**
   * Get information about a purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the purse
   * @param master_pub master public key of the exchange
   * @param[out] rowid which row did we get the information from
   * @param[out] balance set to balance of the purse
   * @param[out] expiration_date expiration date of the purse
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_purse_info)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_MasterPublicKeyP *master_pub,
    uint64_t *rowid,
    struct TALER_Amount *balance,
    struct GNUNET_TIME_Timestamp *expiration_date);


  /**
   * Delete information about a purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*delete_purse_info)(
    void *cls,
    const struct TALER_PurseContractPublicKeyP *purse_pub,
    const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Get information about expired purses.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param cb function to call on expired purses
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_purse_expired)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    TALER_AUDITORDB_ExpiredPurseCallback cb,
    void *cb_cls);


  /**
   * Delete information about a purse.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param purse_pub public key of the purse
   * @param master_pub master public key of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*del_purse_info)(void *cls,
                    const struct TALER_PurseContractPublicKeyP *purse_pub,
                    const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Insert information about all reserves.  There must not be an
   * existing record for the @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param rfb reserve balances summary to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_reserve_summary)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ReserveFeeBalance *rfb);


  /**
   * Update information about all reserves.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param rfb reserve balances summary to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_reserve_summary)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_ReserveFeeBalance *rfb);


  /**
   * Get summary information about all reserves.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param[out] rfb reserve balances summary to initialize
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_reserve_summary)(void *cls,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct TALER_AUDITORDB_ReserveFeeBalance *rfb);


  /**
   * Insert information about all purses.  There must not be an
   * existing record for the @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param sum purse balance summary to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_purse_summary)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_PurseBalance *sum);


  /**
   * Update information about all purses.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param sum purse balances summary to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_purse_summary)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_PurseBalance *sum);


  /**
   * Get summary information about all purses.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param[out] sum purse balances summary to initialize
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_purse_summary)(void *cls,
                       const struct TALER_MasterPublicKeyP *master_pub,
                       struct TALER_AUDITORDB_PurseBalance *sum);


  /**
   * Insert information about exchange's wire fee balance. There must not be an
   * existing record for the same @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param wire_fee_balance amount the exchange gained in wire fees
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire_fee_summary)(void *cls,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *wire_fee_balance);


  /**
   * Insert information about exchange's wire fee balance.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param wire_fee_balance amount the exchange gained in wire fees
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_wire_fee_summary)(void *cls,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *wire_fee_balance);


  /**
   * Get summary information about an exchanges wire fee balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master public key of the exchange
   * @param[out] wire_fee_balance set amount the exchange gained in wire fees
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_fee_summary)(void *cls,
                          const struct TALER_MasterPublicKeyP *master_pub,
                          struct TALER_Amount *wire_fee_balance);


  /**
   * Insert information about a denomination key's balances.  There
   * must not be an existing record for the denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param denom_pub_hash hash of the denomination public key
   * @param dcd denomination circulation data to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_denomination_balance)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash,
    const struct TALER_AUDITORDB_DenominationCirculationData *dcd);


  /**
   * Update information about a denomination key's balances.  There
   * must be an existing record for the denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param denom_pub_hash hash of the denomination public key
   * @param dcd denomination circulation data to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_denomination_balance)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash,
    const struct TALER_AUDITORDB_DenominationCirculationData *dcd);


  /**
   * Get information about a denomination key's balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param denom_pub_hash hash of the denomination public key
   * @param[out] dcd denomination circulation data to initialize
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_denomination_balance)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash,
    struct TALER_AUDITORDB_DenominationCirculationData *dcd);


  /**
   * Delete information about a denomination key's balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param denom_pub_hash hash of the denomination public key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*del_denomination_balance)(
    void *cls,
    const struct TALER_DenominationHashP *denom_pub_hash);


  /**
   * Insert information about an exchange's denomination balances.  There
   * must not be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param dfb denomination balance data to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_balance_summary)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_GlobalCoinBalance *dfb);


  /**
   * Update information about an exchange's denomination balances.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param dfb denomination balance data to store
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_balance_summary)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_AUDITORDB_GlobalCoinBalance *dfb);


  /**
   * Get information about an exchange's denomination balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] dfb where to return the denomination balances
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_balance_summary)(void *cls,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct TALER_AUDITORDB_GlobalCoinBalance *dfb);


  /**
   * Insert information about an exchange's historic
   * revenue about a denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param denom_pub_hash hash of the denomination key
   * @param revenue_timestamp when did this profit get realized
   * @param revenue_balance what was the total profit made from
   *                        deposit fees, melting fees, refresh fees
   *                        and coins that were never returned?
   * @param recoup_loss_balance total losses from recoups of revoked denominations
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_historic_denom_revenue)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    const struct TALER_DenominationHashP *denom_pub_hash,
    struct GNUNET_TIME_Timestamp revenue_timestamp,
    const struct TALER_Amount *revenue_balance,
    const struct TALER_Amount *recoup_loss_balance);


  /**
   * Obtain all of the historic denomination key revenue
   * of the given @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_historic_denom_revenue)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb,
    void *cb_cls);


  /**
   * Insert information about an exchange's historic revenue from reserves.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param start_time beginning of aggregated time interval
   * @param end_time end of aggregated time interval
   * @param reserve_profits total profits made
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_historic_reserve_revenue)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    struct GNUNET_TIME_Timestamp start_time,
    struct GNUNET_TIME_Timestamp end_time,
    const struct TALER_Amount *reserve_profits);


  /**
   * Return information about an exchange's historic revenue from reserves.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param cb function to call with results
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_historic_reserve_revenue)(
    void *cls,
    const struct TALER_MasterPublicKeyP *master_pub,
    TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb,
    void *cb_cls);


  /**
   * Insert information about the predicted exchange's bank
   * account balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param balance what the bank account balance of the exchange should show
   * @param drained_profits total profits drained by the exchange so far
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_predicted_result)(void *cls,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *balance,
                             const struct TALER_Amount *drained_profits);


  /**
   * Update information about an exchange's predicted balance.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param balance what the bank account balance of the exchange should show
   * @param drained_profits total profits drained by the exchange so far
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_predicted_result)(void *cls,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *balance,
                             const struct TALER_Amount *drained_profits);


  /**
   * Get an exchange's predicted balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param master_pub master key of the exchange
   * @param[out] balance expected bank account balance of the exchange
   * @param[out] drained_profits total profits drained by the exchange so far
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_predicted_balance)(void *cls,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           struct TALER_Amount *balance,
                           struct TALER_Amount *drained_profits);


};


#endif /* _TALER_AUDITOR_DB_H */
