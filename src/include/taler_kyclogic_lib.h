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
 * Types of KYC checks.
 */
enum TALER_KYCLOGIC_CheckType
{
  /**
   * Wait for staff or contact staff out-of-band.
   */
  TALER_KYCLOGIC_CT_INFO,

  /**
   * SPA should show an inline form.
   */
  TALER_KYCLOGIC_CT_FORM,

  /**
   * SPA may start external KYC process.
   */
  TALER_KYCLOGIC_CT_LINK
};


/**
 * Information about a KYC provider.
 */
struct TALER_KYCLOGIC_KycProvider;


/**
 * Abstract representation of a KYC check.
 */
struct TALER_KYCLOGIC_KycCheck
{
  /**
   * Human-readable name given to the KYC check.
   */
  char *check_name;

  /**
   * Human-readable description of the check in English.
   */
  char *description;

  /**
   * Optional translations of @e description, can be
   * NULL.
   */
  json_t *description_i18n;

  /**
   * Array of fields that the context must provide as
   * inputs for this check.
   */
  char **requires;

  /**
   * Name of an original measure to take as a fallback
   * in case the check fails.
   */
  char *fallback;

  /**
   * Array of outputs provided by the check. Names of the attributes provided
   * by the check for the AML program.  Either from the configuration or
   * obtained via the converter.
   */
  char **outputs;

  /**
   * Length of the @e requires array.
   */
  unsigned int num_requires;

  /**
   * Length of the @e outputs array.
   */
  unsigned int num_outputs;

  /**
   * True if clients can voluntarily trigger this check.
   */
  bool voluntary;

  /**
   * Type of the KYC check.
   */
  enum TALER_KYCLOGIC_CheckType type;

  /**
   * Details depending on @e type.
   */
  union
  {

    /**
     * Fields present only if @e type is #TALER_KYCLOGIC_CT_FORM.
     */
    struct
    {

      /**
       * Name of the form to render.
       */
      char *name;

    } form;

    /**
     * Fields present only if @e type is TALER_KYCLOGIC_CT_LINK.
     */
    struct
    {

      /**
       * Provider used.
       */
      const struct TALER_KYCLOGIC_KycProvider *provider;

    } link;

  } details;

};


/**
 * Rule that triggers some measure(s).
 */
struct TALER_KYCLOGIC_KycRule;

/**
 * Set of rules that applies to an account.
 */
struct TALER_KYCLOGIC_LegitimizationRuleSet;


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
 * Return JSON array with amounts with thresholds that
 * may change KYC requirements for the wallet.
 *
 * @return JSON array, NULL if no limits apply
 */
json_t *
TALER_KYCLOGIC_get_wallet_thresholds (void);


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
 * @return transaction status
 */
typedef enum GNUNET_DB_QueryStatus
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
 * Parse set of legitimization rules that applies to an account.
 *
 * @param jlrs JSON representation to parse
 * @return rule set, NULL if JSON is invalid
 */
struct TALER_KYCLOGIC_LegitimizationRuleSet *
TALER_KYCLOGIC_rules_parse (const json_t *jlrs);


/**
 * Free set of legitimization rules.
 *
 * @param[in] lrs set of rules to free
 */
void
TALER_KYCLOGIC_rules_free (struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs);


/**
 * Check if KYC is provided for a particular operation. Returns the set of
 * checks that still need to be satisfied.
 *
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param event what type of operation is triggering the
 *         test if KYC is required
 * @param lrs legitimization rules to apply;
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
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  const struct TALER_KYCLOGIC_KycRule **triggered_rule);


const char *
TALER_KYCLOGIC_rule2s (const struct TALER_KYCLOGIC_KycRule *r);


uint32_t
TALER_KYCLOGIC_rule2priority (const struct TALER_KYCLOGIC_KycRule *r);


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
 * Check if any KYC checks are enabled.
 *
 * @return true if KYC is enabled
 *         false if no KYC checks are possible
 */
bool
TALER_KYCLOGIC_is_enabled (void);


/**
 * A KYC rule @a r has been triggered. Convert the resulting requirements in
 * to JSON of type ``LegitimizationMeasures`` for the legitimization measures table.
 *
 * FIXME: not implemented!
 * @param r a rule that was triggered
 * @return JSON serialization of the corresponding
 *   ``LegitimizationMeasures``, NULL on error
 */
json_t *
TALER_KYCLOGIC_rule_to_measures (const struct TALER_KYCLOGIC_KycRule *r);


/**
 * Convert (internal) @a jrules to (public) @a jlimits.
 *
 * @param jrules a ``LegitimizationRuleSet`` with KYC rules;
 *     NULL to use default rules
 * @return set to JSON array with public limits
 *   of type ``AccountLimit``
 */
json_t *
TALER_KYCLOGIC_rules_to_limits (const json_t *jrules);


/**
 * Parse the given @a jmeasures and return the measure
 * at the @a measure_index.
 *
 * @param jmeasures a LegitimizationMeasures object
 * @param measure_index an index into the measures
 * @param[out] check_name set to the name of the check
 * @param[out] prog_name set to the name of the program
 * @param[out] context set to the measure context
 *   (or NULL if there is no context)
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_KYCLOGIC_select_measure (
  const json_t *jmeasures,
  size_t measure_index,
  const char **check_name,
  const char **prog_name,
  const json_t **context);


/**
 * Convert MeasureInformation into the
 * KycRequirementInformation used by the client.
 *
 * @param check_name the prescribed check
 * @param prog_name the program to run
 * @param access_token access token for the measure
 * @param offset offset of the measure
 * @param row_id row in the legitimization_measures table
 * @return JSON object with matching KycRequirementInformation
 */
json_t *
TALER_KYCLOGIC_measure_to_requirement (
  const char *check_name,
  const char *prog_name,
  const struct TALER_AccountAccessTokenP *access_token,
  size_t offset,
  uint64_t row_id);


/**
 * Extract logic data from a KYC @a provider.
 *
 * @param provider provider to get logic data from
 * @param[out] plugin set to the KYC logic API
 * @param[out] pd set to the specific operation context
 * @param[out] provider_name set to the name
 *    of the KYC provider
 */
void
TALER_KYCLOGIC_provider_to_logic (
  const struct TALER_KYCLOGIC_KycProvider *provider,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **provider_name);


/**
 * Tuple with information about a KYC check to perform.  Note that it will
 * have references into the legitimization rule set provided to
 * #TALER_KYCLOGIC_requirements_to_check() and thus has a lifetime that
 * matches the legitimization rule set.
 */
struct TALER_KYCLOGIC_KycCheckContext
{
  /**
   * KYC check to perform.
   */
  const struct TALER_KYCLOGIC_KycCheck *check;

  /**
   * Context for the check. Can be NULL.
   */
  const json_t *context;

  /**
   * Name of the AML program.
   */
  char *prog_name;
};


/**
 * Obtain the provider logic for a given set of @a lrs
 * and a specific @a kyc_rule from @a lrs that was
 * triggered and the choosen @a measure_name from the
 * list of measures of that @a kyc_rule.
 *
 * @param lrs rule set
 * @param kyc_rule rule that was triggered
 * @param measure_name selected measure
 * @param[out] kcc set to check to run
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_requirements_to_check (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const struct TALER_KYCLOGIC_KycRule *kyc_rule,
  const char *measure_name,
  struct TALER_KYCLOGIC_KycCheckContext *kcc);


/**
 * Obtain the provider logic for a given @a name.
 *
 * @param name name of the logic or provider
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
 * Return expiration time for the given @a lrs
 *
 * @param lrs legitimization rules to inspect
 * @return expiration time
 */
struct GNUNET_TIME_Timestamp
TALER_KYCLOGIC_rules_get_expiration (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs);


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
 * Obtain the provider logic for a given set of @a lrs
 * and a specific @a kyc_rule from @a lrs that was
 * triggered and the choosen @a measure_name from the
 * list of measures of that @a kyc_rule.
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
 * Return configuration data useful for the
 * /aml/$PUB/measures endpoint.
 *
 * @param[out] proots set to the root measures
 * @param[out] pprograms set to available AML programs
 * @param[out] pchecks set to available KYC checks
 */
void
TALER_KYCLOGIC_get_measure_configuration (
  json_t **proots,
  json_t **pprograms,
  json_t **pchecks);

#endif
