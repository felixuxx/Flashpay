/*
  This file is part of TALER
  Copyright (C) 2022, 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler_kyclogic_lib.h
 * @brief server-side KYC API
 * @author Christian Grothoff
 */
#ifndef TALER_KYCLOGIC_LIB_H
#define TALER_KYCLOGIC_LIB_H

#include <microhttpd.h>
#include "taler_exchangedb_plugin.h"
#include "taler_kyclogic_plugin.h"


/**
 * Enumeration of possible events that may trigger
 * KYC requirements.
 */
enum TALER_KYCLOGIC_KycTriggerEvent
{

  /**
   * Customer withdraws coins.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW = 0,

  /**
   * Merchant deposits coins.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT = 1,

  /**
   * Wallet receives P2P payment.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE = 2,

  /**
   * Wallet balance exceeds threshold.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE = 3,

  /**
   * Reserve is being closed by force.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE = 4,

  /**
   * Customer withdraws coins via age-withdraw.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_AGE_WITHDRAW = 5,
};


/**
 * Parse KYC trigger string value from a string
 * into enumeration value.
 *
 * @param trigger_s string to parse
 * @param[out] trigger set to the value found
 * @return #GNUNET_OK on success, #GNUNET_NO if option
 *         does not exist, #GNUNET_SYSERR if option is
 *         malformed
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_trigger_from_string (
  const char *trigger_s,
  enum TALER_KYCLOGIC_KycTriggerEvent *trigger);


/**
 * Convert KYC trigger value to human-readable string.
 *
 * @param trigger value to convert
 * @return human-readable representation of the @a trigger
 */
const char *
TALER_KYCLOGIC_kyc_trigger2s (enum TALER_KYCLOGIC_KycTriggerEvent trigger);


/**
 * Initialize KYC subsystem. Loads the KYC configuration.
 *
 * @param cfg configuration to parse
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_init (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shut down the KYC subsystem.
 */
void
TALER_KYCLOGIC_kyc_done (void);


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls closure, identifies the event type and
 *        account to iterate over events for
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 */
typedef void
(*TALER_KYCLOGIC_KycAmountIterator)(
  void *cls,
  struct GNUNET_TIME_Absolute limit,
  TALER_EXCHANGEDB_KycAmountCallback cb,
  void *cb_cls);


/**
 * Function called to iterate over KYC-relevant
 * transaction thresholds amounts.
 *
 * @param cls closure, identifies the event type and
 *        account to iterate over events for
 * @param threshold a relevant threshold amount
 */
typedef void
(*TALER_KYCLOGIC_KycThresholdIterator)(
  void *cls,
  const struct TALER_Amount *threshold);


/**
 * Call us on KYC processes satisfied for the given
 * account. Must match the ``select_satisfied_kyc_processes`` of the exchange database plugin.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param spc function to call for each satisfied KYC process
 * @param spc_cls closure for @a spc
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*TALER_KYCLOGIC_KycSatisfiedIterator)(
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_SatisfiedProviderCallback spc,
  void *spc_cls);


/**
 * Check if KYC is provided for a particular operation. Returns the set of checks that still need to be satisfied.
 *
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param event what type of operation is triggering the
 *         test if KYC is required
 * @param h_payto account the event is about
 * @param ki callback that returns list of already
 *    satisfied KYC checks, implemented by ``select_satisfied_kyc_processes`` of the exchangedb
 * @param ki_cls closure for @a ki
 * @param ai callback offered to inquire about historic
 *         amounts involved in this type of operation
 *         at the given account
 * @param ai_cls closure for @a ai
 * @param[out] required set to NULL if no check is needed,
 *   otherwise space-separated list of required checks
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_kyc_test_required (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  const struct TALER_PaytoHashP *h_payto,
  TALER_KYCLOGIC_KycSatisfiedIterator ki,
  void *ki_cls,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  char **required);


/**
 * Check if the @a requirements are now satsified for
 * @a h_payto account.
 *
 * @param[in,out] requirements space-spearated list of requirements,
 *       already satisfied requirements are removed from the list
 * @param h_payto hash over the account
 * @param[out] kyc_details if satisfied, set to what kind of
 *             KYC information was collected
 * @param ki iterator over satisfied providers
 * @param ki_cls closure for @a ki
 * @param[out] satisfied set to true if the KYC check was satisfied
 * @return transaction status (from @a ki)
 */
enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_check_satisfied (
  char **requirements,
  const struct TALER_PaytoHashP *h_payto,
  json_t **kyc_details,
  TALER_KYCLOGIC_KycSatisfiedIterator ki,
  void *ki_cls,
  bool *satisfied);


/**
 * Iterate over all thresholds that are applicable
 * to a particular type of @a event
 *
 * @param event thresholds to look up
 * @param it function to call on each
 * @param it_cls closure for @a it
 */
void
TALER_KYCLOGIC_kyc_iterate_thresholds (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  TALER_KYCLOGIC_KycThresholdIterator it,
  void *it_cls);


/**
 * Function called with the provider details and
 * associated plugin closures for matching logics.
 *
 * @param cls closure
 * @param pd provider details of a matching logic
 * @param plugin_cls closure of the plugin
 * @return #GNUNET_OK to continue to iterate
 */
typedef enum GNUNET_GenericReturnValue
(*TALER_KYCLOGIC_DetailsCallback)(
  void *cls,
  const struct TALER_KYCLOGIC_ProviderDetails *pd,
  void *plugin_cls);


/**
 * Call @a cb for all logics with name @a logic_name,
 * providing the plugin closure and the @a pd configurations.
 *
 * @param logic_name name of the logic to match
 * @param cb function to call on matching results
 * @param cb_cls closure for @a cb
 */
void
TALER_KYCLOGIC_kyc_get_details (
  const char *logic_name,
  TALER_KYCLOGIC_DetailsCallback cb,
  void *cb_cls);


/**
 * Check if a given @a check_name is a legal name (properly
 * configured) and can be satisfied in principle.
 *
 * @param check_name name of the check to see if it is configured
 * @return #GNUNET_OK if the check can be satisfied,
 *         #GNUNET_NO if the check can never be satisfied,
 *         #GNUNET_SYSERR if the type of the check is unknown
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_check_satisfiable (
  const char *check_name);


/**
 * Return list of all KYC checks that are possible.
 *
 * @return JSON array of strings with the allowed KYC checks
 */
json_t *
TALER_KYCLOGIC_get_satisfiable (void);


/**
 * Obtain the provider logic for a given set of @a requirements.
 *
 * @param requirements space-separated list of required checks
 * @param ut type of the entity performing the check
 * @param[out] plugin set to the KYC logic API
 * @param[out] pd set to the specific operation context
 * @param[out] configuration_section set to the name of the KYC logic configuration section * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_requirements_to_logic (
  const char *requirements,
  enum TALER_KYCLOGIC_KycUserType ut,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **configuration_section);


/**
 * Obtain the provider logic for a given @a name.
 *
 * @param name name of the logic or provider section
 * @param[out] plugin set to the KYC logic API
 * @param[out] pd set to the specific operation context
 * @param[out] configuration_section set to the name of the KYC logic configuration section
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_lookup_logic (
  const char *name,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **configuration_section);


/**
 * Obtain array of KYC checks provided by the provider
 * configured in @a section_name.
 *
 * @param section_name configuration section name
 * @param[out] num_checks set to the length of the array
 * @param[out] provided_checks set to an array with the
 *   names of the checks provided by this KYC provider
 */
void
TALER_KYCLOGIC_lookup_checks (
  const char *section_name,
  unsigned int *num_checks,
  char ***provided_checks);

#endif
