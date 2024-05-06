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
   * Reserved value for invalid event types.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_NONE = 0,

  /**
   * Customer withdraws coins.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW = 1,

  /**
   * Merchant deposits coins.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT = 2,

  /**
   * Wallet receives P2P payment.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE = 3,

  /**
   * Wallet balance exceeds threshold.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE = 4,

  /**
   * Reserve is being closed by force.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE = 5,

  /**
   * Customer withdraws coins via age-withdraw.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_AGE_WITHDRAW = 6,
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
 * Rule that triggers some measure(s).
 */
struct TALER_KYCLOGIC_KycRule;

/**
 * Set of rules that applies to an account.
 */
struct TALER_KYCLOGIC_LegitimizationRuleSet;


/**
 * Parse set of rules that applies to an account.
 *
 * @param jrules JSON representation to parse
 * @return rule set, NULL if JSON is invalid
 */
struct TALER_KYCLOGIC_LegitimizationRuleSet *
TALER_KYCLOGIC_rules_parse (const json_t *jrules);


/**
 * Free set of legitimization rules.
 *
 * @param[in] lrs set of rules to free
 */
void
TALER_KYCLOGIC_rules_free (struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs);


/**
 * Check if KYC is provided for a particular operation. Returns the set of checks that still need to be satisfied.
 *
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param event what type of operation is triggering the
 *         test if KYC is required
 * @param h_payto account the event is about
 * @param lrs legitimization rules for @a h_payto,
 *         NULL to use default rules
 * @param ai callback offered to inquire about historic
 *         amounts involved in this type of operation
 *         at the given account
 * @param ai_cls closure for @a ai
 * @param[out] triggered_rule set to NULL if no rule
 *   is triggered, otherwise the rule with measures
 *   that must be satisfied (will be the highest
 *   applicable rule by display priority)
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_kyc_test_required (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  struct TALER_KYCLOGIC_KycRule **triggered_rule);


const char *
TALER_KYCLOGIC_rule2s (struct TALER_KYCLOGIC_KycRule *r);


json_t *
TALER_KYCLOGIC_rule2j (struct TALER_KYCLOGIC_KycRule *r);


uint32_t
TALER_KYCLOGIC_rule2priority (struct TALER_KYCLOGIC_KycRule *r);

/**
 * Iterate over all thresholds that are applicable to a particular type of @a
 * event under exposed global rules.
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
 * Check if a given @a rule can be satisfied in principle.
 *
 * @param rule the rule to check if it is verboten
 * @return true if the check can be satisfied,
 *         false if the check can never be satisfied,
 */
bool
TALER_KYCLOGIC_is_satisfiable (
  const struct TALER_KYCLOGIC_KycRule *rule);


/**
 * Obtain the provider logic for a given set of @a lrs
 * and a specific @a kyc_rule from @a lrs that was
 * triggered and the choosen @a measure_name from the
 * list of measures of that @a kyc_rule.
 *
 * FIXME: we probably want to instead set up the logic
 * with the context instead of just returning it here!
 *
 * @param requirements space-separated list of required checks
 * @param ut type of the entity performing the check
 * @param[out] plugin set to the KYC logic API
 * @param[out] pd set to the specific operation context
 * @param[out] configuration_section set to the name of the KYC logic configuration section * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_requirements_to_logic (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const struct TALER_KYCLOGIC_KycRule *kyc_rule,
  const char *measure_name,
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


// FIXME: we probably want to instead have some
// functionality that returns information that
// is more directly applicable for /keys or /config
// and not this:
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
