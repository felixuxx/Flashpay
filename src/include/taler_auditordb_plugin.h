/*
  This file is part of TALER
  Copyright (C) 2014-2016 GNUnet e.V.

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
#include "taler_auditordb_lib.h"
#include "taler_signatures.h"


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
   * @return #GNUNET_OK on success, #GNUNET_NO if the transaction
   *         can be retried, #GNUNET_SYSERR on hard failures
   */
  int
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
   * Insert information about a denomination key and in particular
   * the properties (value, fees, expiration times) the coins signed
   * with this key have.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param issue issuing information with value, fees and other info about the denomination
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*select_denomination_info)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              void *cb, /* FIXME: type! */
                              void *cb_cls);


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
   * @param last_reserve_in_serial_id up to which point did we consider
   *                 incoming transfers for the above information
   * @param last_reserve_out_serial_id up to which point did we consider
   *                 withdrawals for the above information
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*insert_reserve_info)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         const struct TALER_Amount *reserve_balance,
                         const struct TALER_Amount *withdraw_fee_balance,
                         struct GNUNET_TIME_Absolute expiration_date,
                         uint64_t last_reserve_in_serial_id,
                         uint64_t last_reserve_out_serial_id);


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
   * @param last_reserve_in_serial_id up to which point did we consider
   *                 incoming transfers for the above information
   * @param last_reserve_out_serial_id up to which point did we consider
   *                 withdrawals for the above information
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*update_reserve_info)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_ReservePublicKeyP *reserve_pub,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         const struct TALER_Amount *reserve_balance,
                         const struct TALER_Amount *withdraw_fee_balance,
                         struct GNUNET_TIME_Absolute expiration_date,
                         uint64_t last_reserve_in_serial_id,
                         uint64_t last_reserve_out_serial_id);


  /**
   * Get information about a reserve.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param reserve_pub public key of the reserve
   * @param master_pub master public key of the exchange
   * @param[out] reserve_balance amount stored in the reserve
   * @param[out] withdraw_fee_balance amount the exchange gained in withdraw fees
   *                             due to withdrawals from this reserve
   * @param[out] expiration_date expiration date of the reserve
   * @param[out] last_reserve_in_serial_id up to which point did we consider
   *                 incoming transfers for the above information
   * @param[out] last_reserve_out_serial_id up to which point did we consider
   *                 withdrawals for the above information
   * @return #GNUNET_OK on success; #GNUNET_NO if there is no known
   *         record about this reserve; #GNUNET_SYSERR on failure
   */
  int
  (*get_reserve_info)(void *cls,
                      struct TALER_AUDITORDB_Session *session,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const struct TALER_MasterPublicKeyP *master_pub,
                      struct TALER_Amount *reserve_balance,
                      struct TALER_Amount *withdraw_fee_balance,
                      struct GNUNET_TIME_Absolute *expiration_date,
                      uint64_t *last_reserve_in_serial_id,
                      uint64_t *last_reserve_out_serial_id);



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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success; #GNUNET_NO if there is no known
   *         record about this exchange; #GNUNET_SYSERR on failure
   */
  int
  (*get_reserve_summary)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct TALER_Amount *reserve_balance,
                         struct TALER_Amount *withdraw_fee_balance);


  /**
   * Insert information about a denomination key's balances.  There
   * must not be an existing record for the denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @param denom_balance value of coins outstanding with this denomination key
   * @param deposit_fee_balance total deposit fees collected for this DK
   * @param melt_fee_balance total melt fees collected for this DK
   * @param refund_fee_balance total refund fees collected for this DK
   * @param last_reserve_out_serial_id up to which point did we consider
   *                 withdrawals for the above information
   * @param last_deposit_serial_id up to which point did we consider
   *                 deposits for the above information
   * @param last_melt_serial_id up to which point did we consider
   *                 melts for the above information
   * @param last_refund_serial_id up to which point did we consider
   *                 refunds for the above information
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*insert_denomination_balance)(void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *deposit_fee_balance,
                                 const struct TALER_Amount *melt_fee_balance,
                                 const struct TALER_Amount *refund_fee_balance,
                                 uint64_t last_reserve_out_serial_id,
                                 uint64_t last_deposit_serial_id,
                                 uint64_t last_melt_serial_id,
                                 uint64_t last_refund_serial_id);


  /**
   * Update information about a denomination key's balances.  There
   * must be an existing record for the denomination key.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @param denom_balance value of coins outstanding with this denomination key
   * @param deposit_fee_balance total deposit fees collected for this DK
   * @param melt_fee_balance total melt fees collected for this DK
   * @param refund_fee_balance total refund fees collected for this DK
   * @param last_reserve_out_serial_id up to which point did we consider
   *                 withdrawals for the above information
   * @param last_deposit_serial_id up to which point did we consider
   *                 deposits for the above information
   * @param last_melt_serial_id up to which point did we consider
   *                 melts for the above information
   * @param last_refund_serial_id up to which point did we consider
   *                 refunds for the above information
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*update_denomination_balance)(void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct GNUNET_HashCode *denom_pub_hash,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *deposit_fee_balance,
                                 const struct TALER_Amount *melt_fee_balance,
                                 const struct TALER_Amount *refund_fee_balance,
                                 uint64_t last_reserve_out_serial_id,
                                 uint64_t last_deposit_serial_id,
                                 uint64_t last_melt_serial_id,
                                 uint64_t last_refund_serial_id);


  /**
   * Get information about a denomination key's balances.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param denom_pub_hash hash of the denomination public key
   * @param[out] denom_balance value of coins outstanding with this denomination key
   * @param[out] deposit_fee_balance total deposit fees collected for this DK
   * @param[out] melt_fee_balance total melt fees collected for this DK
   * @param[out] refund_fee_balance total refund fees collected for this DK
   * @param[out] last_reserve_out_serial_id up to which point did we consider
   *                 withdrawals for the above information
   * @param[out] last_deposit_serial_id up to which point did we consider
   *                 deposits for the above information
   * @param[out] last_melt_serial_id up to which point did we consider
   *                 melts for the above information
   * @param[out] last_refund_serial_id up to which point did we consider
   *                 refunds for the above information
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*get_denomination_balance)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct GNUNET_HashCode *denom_pub_hash,
                              struct TALER_Amount *denom_balance,
                              struct TALER_Amount *deposit_fee_balance,
                              struct TALER_Amount *melt_fee_balance,
                              struct TALER_Amount *refund_fee_balance,
                              uint64_t *last_reserve_out_serial_id,
                              uint64_t *last_deposit_serial_id,
                              uint64_t *last_melt_serial_id,
                              uint64_t *last_refund_serial_id);


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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*insert_denomination_summary)(void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *deposit_fee_balance,
                                 const struct TALER_Amount *melt_fee_balance,
                                 const struct TALER_Amount *refund_fee_balance);


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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*update_denomination_summary)(void *cls,
                                 struct TALER_AUDITORDB_Session *session,
                                 const struct TALER_MasterPublicKeyP *master_pub,
                                 const struct TALER_Amount *denom_balance,
                                 const struct TALER_Amount *deposit_fee_balance,
                                 const struct TALER_Amount *melt_fee_balance,
                                 const struct TALER_Amount *refund_fee_balance);


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
   * @return #GNUNET_OK on success; #GNUNET_NO if there is no entry
   *           for this @a master_pub; #GNUNET_SYSERR on failure
   */
  int
  (*get_denomination_summary)(void *cls,
                              struct TALER_AUDITORDB_Session *session,
                              const struct TALER_MasterPublicKeyP *master_pub,
                              struct TALER_Amount *denom_balance,
                              struct TALER_Amount *deposit_fee_balance,
                              struct TALER_Amount *melt_fee_balance,
                              struct TALER_Amount *refund_fee_balance);


  /**
   * Insert information about an exchange's risk exposure.  There
   * must not be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param risk maximum risk exposure of the exchange
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*insert_risk_summary)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         const struct TALER_Amount *risk);


  /**
   * Update information about an exchange's risk exposure.  There
   * must be an existing record for the exchange.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param risk maximum risk exposure of the exchange
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*update_risk_summary)(void *cls,
                         struct TALER_AUDITORDB_Session *session,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         const struct TALER_Amount *risk);


  /**
   * Get information about an exchange's risk exposure.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param[out] risk maximum risk exposure of the exchange
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure;
   *         #GNUNET_NO if we have no records for the @a master_pub
   */
  int
  (*get_risk_summary)(void *cls,
                      struct TALER_AUDITORDB_Session *session,
                      const struct TALER_MasterPublicKeyP *master_pub,
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
   * @param deposit_fee_balance total profits from deposit fees
   * @param melt_fee_balance total profits from melting fees
   * @param refund_fee_balance total profits from refund fees
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*insert_historic_denom_revenue)(void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   const struct GNUNET_HashCode *denom_pub_hash,
                                   struct GNUNET_TIME_Absolute revenue_timestamp,
                                   const struct TALER_Amount *revenue_balance,
                                   const struct TALER_Amount *deposit_fee_balance,
                                   const struct TALER_Amount *melt_fee_balance,
                                   const struct TALER_Amount *refund_fee_balance);

  /**
   * Obtain all of the historic denomination key revenue
   * of the given @a master_pub.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param cb function to call with the results
   * @param cb_cls closure for @a cb
   * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
   */
  int
  (*select_historic_denom_revenue)(void *cls,
                                   struct TALER_AUDITORDB_Session *session,
                                   const struct TALER_MasterPublicKeyP *master_pub,
                                   void *cb, /* FIXME: fix type */
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
   */
  int
  (*select_historic_losses)(void *cls,
                            struct TALER_AUDITORDB_Session *session,
                            const struct TALER_MasterPublicKeyP *master_pub,
                            void *cb, /* FIXME: fix type */
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
  (*select_historic_reserve_revenue)(void *cls,
                                     struct TALER_AUDITORDB_Session *session,
                                     const struct TALER_MasterPublicKeyP *master_pub,
                                     void *cb, /* FIXME: type */
                                     void *cb_cls);



  /**
   * Insert information about the predicted exchange's bank
   * account balance.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param session connection to use
   * @param master_pub master key of the exchange
   * @param balance what the bank account balance of the exchange should show
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure
   */
  int
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
   * @return #GNUNET_OK on success; #GNUNET_SYSERR on failure;
   *         #GNUNET_NO if we have no records for the @a master_pub
   */
  int
  (*get_predicted_balance)(void *cls,
                           struct TALER_AUDITORDB_Session *session,
                           const struct TALER_MasterPublicKeyP *master_pub,
                           struct TALER_Amount *balance);

};


#endif /* _TALER_AUDITOR_DB_H */
