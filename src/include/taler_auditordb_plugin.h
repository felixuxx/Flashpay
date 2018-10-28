/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
(*TALER_AUDITORDB_ExchangeCallback)(void *cls,
                                    const struct TALER_MasterPublicKeyP *master_pub,
                                    const char *exchange_url);


/**
 * Function called with the results of select_denomination_info()
 *
 * @param cls closure
 * @param issue issuing information with value, fees and other info about the denomination.
 *
 * @return sets the return value of select_denomination_info(),
 *         #GNUNET_OK to continue,
 *         #GNUNET_NO to stop processing further rows
 *         #GNUNET_SYSERR or other values on error.
 */
typedef int
(*TALER_AUDITORDB_DenominationInfoDataCallback)(void *cls,
                                                const struct TALER_DenominationKeyValidityPS *issue);


/**
 * Function called with the results of select_historic_denom_revenue()
 *
 * @param cls closure
 * @param denom_pub_hash hash of the denomination key
 * @param revenue_timestamp when did this profit get realized
 * @param revenue_balance what was the total profit made from
 *                        deposit fees, melting fees, refresh fees
 *                        and coins that were never returned?
 * @return sets the return value of select_denomination_info(),
 *         #GNUNET_OK to continue,
 *         #GNUNET_NO to stop processing further rows
 *         #GNUNET_SYSERR or other values on error.
 */
typedef int
(*TALER_AUDITORDB_HistoricDenominationRevenueDataCallback)(void *cls,
                                                           const struct GNUNET_HashCode *denom_pub_hash,
                                                           struct GNUNET_TIME_Absolute revenue_timestamp,
                                                           const struct TALER_Amount *revenue_balance);


/**
 * Function called with the results of select_historic_losses()
 *
 * @param cls closure
 * @param denom_pub_hash hash of the denomination key
 * @param loss_timestamp when did this profit get realized
 * @param loss_balance what was the total loss
 *
 * @return sets the return value of select_denomination_info(),
 *         #GNUNET_OK to continue,
 *         #GNUNET_NO to stop processing further rows
 *         #GNUNET_SYSERR or other values on error.
 */
typedef int
(*TALER_AUDITORDB_HistoricLossesDataCallback)(void *cls,
                                              const struct GNUNET_HashCode *denom_pub_hash,
                                              struct GNUNET_TIME_Absolute loss_timestamp,
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
typedef int
(*TALER_AUDITORDB_HistoricReserveRevenueDataCallback)(void *cls,
                                                      struct GNUNET_TIME_Absolute start_time,
                                                      struct GNUNET_TIME_Absolute end_time,
                                                      const struct TALER_Amount *reserve_profits);


/**
 * Structure for remembering the wire auditor's progress over the
 * various tables and (auditor) transactions.
 */
struct TALER_AUDITORDB_WireProgressPoint
{
  /**
   * serial ID of the last reserve_in transfer the wire auditor processed
   */
  uint64_t last_reserve_in_serial_id;

  /**
   * serial ID of the last wire_out the wire auditor processed
   */
  uint64_t last_wire_out_serial_id;

  /**
   * Time until which we have confirmed that all wire transactions
   * that the exchange should do, have indeed been done.
   */
  struct GNUNET_TIME_Absolute last_timestamp;
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
   * serial ID of the last reserve_out the auditor processed
   */
  uint64_t last_reserve_out_serial_id;

  /**
   * serial ID of the last payback entry the auditor processed when
   * considering reserves.
   */
  uint64_t last_reserve_payback_serial_id;

  /**
   * serial ID of the last reserve_close
   * entry the auditor processed.
   */
  uint64_t last_reserve_close_serial_id;

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
  struct GNUNET_TIME_Absolute ep_start;

  /**
   * When will the exchange stop signing with @e exchange_pub?
   */
  struct GNUNET_TIME_Absolute ep_expire;

  /**
   * When does the signing key expire (for legal disputes)?
   */
  struct GNUNET_TIME_Absolute ep_end;

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
  struct GNUNET_HashCode h_contract_terms;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Time when this confirmation was generated.
   */
  struct GNUNET_TIME_Absolute timestamp;

  /**
   * How much time does the @e merchant have to issue a refund
   * request?  Zero if refunds are not allowed.  After this time, the
   * coin cannot be refunded.  Note that the wire transfer will not be
   * performed by the exchange until the refund deadline.  This value
   * is taken from the original deposit request.
   */
  struct GNUNET_TIME_Absolute refund_deadline;

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
 * Handle for one session with the database.
 */
struct TALER_AUDITORDB_Session;


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
   * Get the thread-local database-handle.
   * Connect to the db if the connection does not exist yet.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param the database connection, or NULL on error
   */
  struct TALER_AUDITORDB_Session *
  (*get_session) (void *cls);


  /**
   * Drop the Taler tables.  This should only be used in testcases.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  int
  (*drop_tables) (void *cls);


  /**
   * Create the necessary tables if they are not present
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
   */
  int
  (*create_tables) (void *cls);


  /**
   * Start a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @return #GNUNET_OK on success
   */
  int
  (*start) (void *cls,
            struct TALER_AUDITORDB_Session *session);


  /**
   * Commit a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*commit) (void *cls,
             struct TALER_AUDITORDB_Session *session);


  /**
   * Abort/rollback a transaction.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   */
  void
  (*rollback) (void *cls,
               struct TALER_AUDITORDB_Session *session);


  /**
   * Function called to perform "garbage collection" on the
   * database, expiring records we no longer require.
   *
   * @param cls closure
   * @return #GNUNET_OK on success,
   *         #GNUNET_SYSERR on DB errors
   */
  int
  (*gc) (void *cls);


  /**
   * Insert information about an exchange this auditor will be auditing.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param master_pub master public key of the exchange
   * @param exchange_url public (base) URL of the API of the exchange
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_exchange) (void *cls,
                      struct TALER_AUDITORDB_Session *session,
                      const struct TALER_MasterPublicKeyP *master_pub,
                      const char *exchange_url);


  /**
   * Delete an exchange from the list of exchanges this auditor is auditing.
   * Warning: this will cascade and delete all knowledge of this auditor related
   * to this exchange!
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param master_pub master public key of the exchange
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*delete_exchange) (void *cls,
                      struct TALER_AUDITORDB_Session *session,
                      const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Obtain information about exchanges this auditor is auditing.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param master_pub master public key of the exchange
   * @param exchange_url public (base) URL of the API of the exchange
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*list_exchanges) (void *cls,
                     struct TALER_AUDITORDB_Session *session,
                     TALER_AUDITORDB_ExchangeCallback cb,
                     void *cb_cls);

  /**
   * Insert information about a signing key of the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param sk signing key information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_exchange_signkey) (void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_AUDITORDB_ExchangeSigningKey *sk);


  /**
   * Insert information about a deposit confirmation into the database.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to the database
   * @param dc deposit confirmation information to store
   * @return query result status
   */
  enum GNUNET_DB_QueryStatus
  (*insert_deposit_confirmation) (void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_AUDITORDB_DepositConfirmation *dc);


  /**
   * Insert information about a denomination key and in particular
   * the properties (value, fees, expiration times) the coins signed
   * with this key have.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param issue issuing information with value, fees and other info about the denomination
   * @return status of database operation
   */
  enum GNUNET_DB_QueryStatus
  (*insert_denomination_info)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_DenominationKeyValidityPS *issue);


  /**
   * Get information about denomination keys of a particular exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_denomination_info)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              TALER_AUDITORDB_DenominationInfoDataCallback cb,
                              void *cb_cls);


  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_coin)(void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_AUDITORDB_ProgressPointCoin *ppc);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_coin)(void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const struct TALER_AUDITORDB_ProgressPointCoin *ppc);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] ppc set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_coin)(void *cls,
                               struct TALER_AUDITORDB_Session *session,
                               const struct TALER_MasterPublicKeyP *master_pub,
                               struct TALER_AUDITORDB_ProgressPointCoin *ppc);

    /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppr where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_reserve)(void *cls,
                                     struct TALER_AUDITORDB_Session *session,
                                     const struct TALER_MasterPublicKeyP *master_pub,
                                     const struct TALER_AUDITORDB_ProgressPointReserve *ppr);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppr where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_reserve)(void *cls,
                                     struct TALER_AUDITORDB_Session *session,
                                     const struct TALER_MasterPublicKeyP *master_pub,
                                     const struct TALER_AUDITORDB_ProgressPointReserve *ppr);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] ppr set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_reserve)(void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  struct TALER_AUDITORDB_ProgressPointReserve *ppr);

  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppdc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_deposit_confirmation)(void *cls,
                                                  struct TALER_AUDITORDB_Session *session,
                                                  const struct TALER_MasterPublicKeyP *master_pub,
                                                  const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppdc where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_deposit_confirmation)(void *cls,
                                                  struct TALER_AUDITORDB_Session *session,
                                                  const struct TALER_MasterPublicKeyP *master_pub,
                                                  const struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] ppdc set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_deposit_confirmation)(void *cls,
                                               struct TALER_AUDITORDB_Session *session,
                                               const struct TALER_MasterPublicKeyP *master_pub,
                                               struct TALER_AUDITORDB_ProgressPointDepositConfirmation *ppdc);


  /**
   * Insert information about the auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppa where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_auditor_progress_aggregation)(void *cls,
                                         struct TALER_AUDITORDB_Session *session,
                                         const struct TALER_MasterPublicKeyP *master_pub,
                                         const struct TALER_AUDITORDB_ProgressPointAggregation *ppa);


  /**
   * Update information about the progress of the auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param ppa where is the auditor in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_auditor_progress_aggregation)(void *cls,
                                         struct TALER_AUDITORDB_Session *session,
                                         const struct TALER_MasterPublicKeyP *master_pub,
                                         const struct TALER_AUDITORDB_ProgressPointAggregation *ppa);


  /**
   * Get information about the progress of the auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] ppa set to where the auditor is in processing
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_auditor_progress_aggregation)(void *cls,
                                      struct TALER_AUDITORDB_Session *session,
                                      const struct TALER_MasterPublicKeyP *master_pub,
                                      struct TALER_AUDITORDB_ProgressPointAggregation *ppa);


  /**
   * Insert information about the wire auditor's progress with an exchange's
   * data.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param pp where is the auditor in processing
   * @param in_wire_off how far are we in the incoming wire transaction history
   * @param out_wire_off how far are we in the outgoing wire transaction history
   * @param wire_off_size how many bytes do @a in_wire_off and @a out_wire_off take?
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire_auditor_progress)(void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const char *account_name,
                                  const struct TALER_AUDITORDB_WireProgressPoint *pp,
                                  const void *in_wire_off,
                                  const void *out_wire_off,
                                  size_t wire_off_size);


  /**
   * Update information about the progress of the wire auditor.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param pp where is the auditor in processing
   * @param in_wire_off how far are we in the incoming wire transaction history
   * @param out_wire_off how far are we in the outgoing wire transaction history
   * @param wire_off_size how many bytes do @a in_wire_off and @a out_wire_off take?
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_wire_auditor_progress)(void *cls,
                                  struct TALER_AUDITORDB_Session *session,
                                  const struct TALER_MasterPublicKeyP *master_pub,
                                  const char *account_name,
                                  const struct TALER_AUDITORDB_WireProgressPoint *pp,
                                  const void *in_wire_off,
                                  const void *out_wire_off,
                                  size_t wire_off_size);



  /**
   * Get information about the progress of the wire auditor.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param account_name name of the wire account we are auditing
   * @param[out] pp set to where the auditor is in processing
   * @param[out] in_wire_off how far are we in the incoming wire transaction history
   * @param[out] out_wire_off how far are we in the outgoing wire transaction history
   * @param[out] wire_off_size how many bytes do @a in_wire_off and @a out_wire_off take?
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_auditor_progress)(void *cls,
                               struct TALER_AUDITORDB_Session *session,
                               const struct TALER_MasterPublicKeyP *master_pub,
                               const char *account_name,
                               struct TALER_AUDITORDB_WireProgressPoint *pp,
                               void **in_wire_off,
                               void **out_wire_off,
                               size_t *wire_off_size);


  /**
   * Insert information about a reserve.  There must not be an
   * existing record for the reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param reserve_balance amount stored in the reserve
   * @param withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @param expiration_date expiration date of the reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_reserve_info)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         const struct TALER_Amount *reserve_balance,
                         const struct TALER_Amount *withdraw_fee_balance,
                         struct GNUNET_TIME_Absolute expiration_date);


  /**
   * Update information about a reserve.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param reserve_balance amount stored in the reserve
   * @param withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @param expiration_date expiration date of the reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_reserve_info)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         const struct TALER_Amount *reserve_balance,
                         const struct TALER_Amount *withdraw_fee_balance,
                         struct GNUNET_TIME_Absolute expiration_date);


  /**
   * Get information about a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param[out] rowid which row did we get the information from
   * @param[out] reserve_balance amount stored in the reserve
   * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @param[out] expiration_date expiration date of the reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_reserve_info)(void *cls,
                      struct TALER_AUDITORDB_Session *session,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const struct TALER_MasterPublicKeyP *master_pub,
                      uint64_t *rowid,
                      struct TALER_Amount *reserve_balance,
                      struct TALER_Amount *withdraw_fee_balance,
                      struct GNUNET_TIME_Absolute *expiration_date);


  /**
   * Delete information about a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*del_reserve_info)(void *cls,
                      struct TALER_AUDITORDB_Session *session,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const struct TALER_MasterPublicKeyP *master_pub);


  /**
   * Insert information about all reserves.  There must not be an
   * existing record for the @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param reserve_balance amount stored in the reserve
   * @param withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_reserve_summary)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            const struct TALER_Amount *reserve_balance,
                            const struct TALER_Amount *withdraw_fee_balance);


  /**
   * Update information about all reserves.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param reserve_balance amount stored in the reserve
   * @param withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_reserve_summary)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            const struct TALER_Amount *reserve_balance,
                            const struct TALER_Amount *withdraw_fee_balance);


  /**
   * Get summary information about all reserves.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param[out] reserve_balance amount stored in the reserve
   * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_reserve_summary)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct TALER_Amount *reserve_balance,
                         struct TALER_Amount *withdraw_fee_balance);


  /**
   * Insert information about exchange's wire fee balance. There must not be an
   * existing record for the same @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param wire_fee_balance amount the exchange gained in wire fees
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_wire_fee_summary)(void *cls,
                             struct TALER_AUDITORDB_Session *session,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *wire_fee_balance);


  /**
   * Insert information about exchange's wire fee balance.  Destructively updates an
   * existing record, which must already exist.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param wire_fee_balance amount the exchange gained in wire fees
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_wire_fee_summary)(void *cls,
                             struct TALER_AUDITORDB_Session *session,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *wire_fee_balance);


  /**
   * Get summary information about an exchanges wire fee balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master public key of the exchange
   * @param[out] wire_fee_balance set amount the exchange gained in wire fees
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_wire_fee_summary)(void *cls,
                          struct TALER_AUDITORDB_Session *session,
                          const struct TALER_MasterPublicKeyP *master_pub,
                          struct TALER_Amount *wire_fee_balance);


  /**
   * Insert information about a denomination key's balances.  There
   * must not be an existing record for the denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @param denom_balance value of coins outstanding with this denomination key
   * @param denom_risk value of coins issued with this denomination key
   * @param num_issued how many coins of this denomination did the exchange blind-sign
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_denomination_balance)(void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *denom_risk,
                                 uint64_t num_issued);


  /**
   * Update information about a denomination key's balances.  There
   * must be an existing record for the denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @param denom_balance value of coins outstanding with this denomination key
   * @param denom_risk value of coins issued with this denomination key
   * @param num_issued how many coins of this denomination did the exchange blind-sign
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_denomination_balance)(void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *denom_risk,
                                 uint64_t num_issued);


  /**
   * Get information about a denomination key's balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @param[out] denom_balance value of coins outstanding with this denomination key
   * @param[out] denom_risk value of coins issued with this denomination key
   * @param[out] num_issued how many coins of this denomination did the exchange blind-sign
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_denomination_balance)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct GNUNET_HashCode *denom_pub_hash,
                              struct TALER_Amount *denom_balance,
                              struct TALER_Amount *denom_risk,
                              uint64_t *num_issued);


  /**
   * Delete information about a denomination key's balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*del_denomination_balance)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct GNUNET_HashCode *denom_pub_hash);


  /**
   * Insert information about an exchange's denomination balances.  There
   * must not be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param denom_balance value of coins outstanding with this denomination key
   * @param deposit_fee_balance total deposit fees collected for this DK
   * @param melt_fee_balance total melt fees collected for this DK
   * @param refund_fee_balance total refund fees collected for this DK
   * @param risk maximum risk exposure of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_balance_summary)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            const struct TALER_Amount *denom_balance,
                            const struct TALER_Amount *deposit_fee_balance,
                            const struct TALER_Amount *melt_fee_balance,
                            const struct TALER_Amount *refund_fee_balance,
                            const struct TALER_Amount *risk);


  /**
   * Update information about an exchange's denomination balances.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param denom_balance value of coins outstanding with this denomination key
   * @param deposit_fee_balance total deposit fees collected for this DK
   * @param melt_fee_balance total melt fees collected for this DK
   * @param refund_fee_balance total refund fees collected for this DK
   * @param risk maximum risk exposure of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_balance_summary)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            const struct TALER_Amount *denom_balance,
                            const struct TALER_Amount *deposit_fee_balance,
                            const struct TALER_Amount *melt_fee_balance,
                            const struct TALER_Amount *refund_fee_balance,
                            const struct TALER_Amount *risk);


  /**
   * Get information about an exchange's denomination balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] denom_balance value of coins outstanding with this denomination key
   * @param[out] deposit_fee_balance total deposit fees collected for this DK
   * @param[out] melt_fee_balance total melt fees collected for this DK
   * @param[out] refund_fee_balance total refund fees collected for this DK
   * @param[out] risk maximum risk exposure of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_balance_summary)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct TALER_Amount *denom_balance,
                         struct TALER_Amount *deposit_fee_balance,
                         struct TALER_Amount *melt_fee_balance,
                         struct TALER_Amount *refund_fee_balance,
                         struct TALER_Amount *risk);


  /**
   * Insert information about an exchange's historic
   * revenue about a denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param denom_pub_hash hash of the denomination key
   * @param revenue_timestamp when did this profit get realized
   * @param revenue_balance what was the total profit made from
   *                        deposit fees, melting fees, refresh fees
   *                        and coins that were never returned?
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_historic_denom_revenue)(void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   const struct GNUNET_HashCode *denom_pub_hash,
                                   struct GNUNET_TIME_Absolute revenue_timestamp,
                                   const struct TALER_Amount *revenue_balance);


  /**
   * Obtain all of the historic denomination key revenue
   * of the given @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_historic_denom_revenue)(void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   TALER_AUDITORDB_HistoricDenominationRevenueDataCallback cb,
                                   void *cb_cls);


  /**
   * Insert information about an exchange's historic
   * losses (from compromised denomination keys).
   *
   * Note yet used, need to implement exchange's bankrupcy
   * protocol (and tables!) first.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param denom_pub_hash hash of the denomination key
   * @param loss_timestamp when did this profit get realized
   * @param loss_balance what was the total loss
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_historic_losses)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            const struct GNUNET_HashCode *denom_pub_hash,
                            struct GNUNET_TIME_Absolute loss_timestamp,
                            const struct TALER_Amount *loss_balance);

  /**
   * Obtain all of the historic denomination key losses
   * of the given @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_historic_losses)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            TALER_AUDITORDB_HistoricLossesDataCallback cb,
                            void *cb_cls);


  /**
   * Insert information about an exchange's historic revenue from reserves.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param start_time beginning of aggregated time interval
   * @param end_time end of aggregated time interval
   * @param reserve_profits total profits made
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_historic_reserve_revenue)(void *cls,
                                     struct TALER_AUDITORDB_Session *session,
                                     const struct TALER_MasterPublicKeyP *master_pub,
                                     struct GNUNET_TIME_Absolute start_time,
                                     struct GNUNET_TIME_Absolute end_time,
                                     const struct TALER_Amount *reserve_profits);


  /**
   * Return information about an exchange's historic revenue from reserves.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param cb function to call with results
   * @param cb_cls closure for @a cb
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*select_historic_reserve_revenue)(void *cls,
                                     struct TALER_AUDITORDB_Session *session,
                                     const struct TALER_MasterPublicKeyP *master_pub,
                                     TALER_AUDITORDB_HistoricReserveRevenueDataCallback cb,
                                     void *cb_cls);



  /**
   * Insert information about the predicted exchange's bank
   * account balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param balance what the bank account balance of the exchange should show
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*insert_predicted_result)(void *cls,
                             struct TALER_AUDITORDB_Session *session,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *balance);


  /**
   * Update information about an exchange's predicted balance.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param balance what the bank account balance of the exchange should show
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*update_predicted_result)(void *cls,
                             struct TALER_AUDITORDB_Session *session,
                             const struct TALER_MasterPublicKeyP *master_pub,
                             const struct TALER_Amount *balance);


  /**
   * Get an exchange's predicted balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] balance expected bank account balance of the exchange
   * @return transaction status code
   */
  enum GNUNET_DB_QueryStatus
  (*get_predicted_balance)(void *cls,
                           struct TALER_AUDITORDB_Session *session,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           struct TALER_Amount *balance);


};


#endif /* _TALER_AUDITOR_DB_H */
