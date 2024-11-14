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
   * Wallet balance exceeds threshold. The timeframe is
   * irrelevant for this limit.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE = 4,

  /**
   * Reserve is being closed by force.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE = 5,

  /**
   * Deposits have been aggregated, we are wiring a
   * certain amount into a (merchant) bank account.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_AGGREGATE = 6,

  /**
   * Limit per transaction.  The timeframe is
   * irrelevant for this limit.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_TRANSACTION = 7,

  /**
   * Limit per refund.  The timeframe is
   * irrelevant for this limit.
   */
  TALER_KYCLOGIC_KYC_TRIGGER_REFUND = 8

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
 * KYC measure that can be taken.
 */
struct TALER_KYCLOGIC_Measure
{
  /**
   * Name of the KYC measure.
   */
  char *measure_name;

  /**
   * Name of the KYC check.
   */
  char *check_name;

  /**
   * Name of the AML program.
   */
  char *prog_name;

  /**
   * Context for the check. Can be NULL.
   */
  json_t *context;

  /**
   * Can this measure be triggered voluntarily?
   */
  bool voluntary;
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
 * Initialize KYC subsystem. Loads the KYC configuration.
 *
 * @param cfg configuration to parse
 * @param cfg_fn configuration filename for AML helpers
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_init (const struct GNUNET_CONFIGURATION_Handle *cfg,
                         const char *cfg_fn);


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
 * @param[out] next_threshold set to the next amount
 *   that may trigger a KYC check (note: only really
 *   useful for the wallet balance right now, as we
 *   cannot easily state the applicable timeframe)
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_kyc_test_required (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  const struct TALER_KYCLOGIC_KycRule **triggered_rule,
  struct TALER_Amount *next_threshold);


/**
 * Return JSON array of AccountLimit objects with hard limits of this exchange
 * suitable for the "hard_limits" field of the "/keys" response.
 *
 * @return the JSON array of AccountLimit objects,
 *   empty array if there are no hard limits
 */
json_t *
TALER_KYCLOGIC_get_hard_limits (void);


/**
 * Return JSON array of ZeroLimitedOperation objects with
 * operations for which this exchange has a limit
 * of zero, that means KYC is always required (or
 * the operation is categorically forbidden).
 *
 * @return the JSON array of ZeroLimitedOperation objects,
 *   empty array if there are no hard limits
 */
json_t *
TALER_KYCLOGIC_get_zero_limits (void);


/**
 * Obtain set of all measures that
 * could be triggered at an amount of zero and that
 * thus might be requested before a client even
 * has performed any operation.
 *
 * @param lrs rule set to investigate, NULL for default
 * @return LegitimizationMeasures, NULL on error
 */
json_t *
TALER_KYCLOGIC_zero_measures (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs);


/**
 * Obtain set of all voluntary measures that
 * could be triggered by clients at will.
 *
 * @param lrs rule set to investigate, NULL for default
 * @return array of MeasureInformation, never NULL
 */
json_t *
TALER_KYCLOGIC_voluntary_measures (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs);


/**
 * Get human-readable name of KYC rule.
 *
 * @param r rule to convert
 * @return name of the rule
 */
const char *
TALER_KYCLOGIC_rule2s (const struct TALER_KYCLOGIC_KycRule *r);


/**
 * Convert KYC status to human-readable string.
 *
 * @param status status to convert
 * @return human-readable string
 */
const char *
TALER_KYCLOGIC_status2s (enum TALER_KYCLOGIC_KycStatus status);


/**
 * Get priority of KYC rule.
 *
 * @param r rule to convert
 * @return priority of the rule
 */
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
 * A KYC rule @a r has been triggered. Convert the resulting requirements into
 * JSON of type ``LegitimizationMeasures`` for the legitimization measures table.
 *
 * @param r a rule that was triggered
 * @return JSON serialization of the corresponding
 *   ``LegitimizationMeasures``, NULL on error
 */
json_t *
TALER_KYCLOGIC_rule_to_measures (
  const struct TALER_KYCLOGIC_KycRule *r);


/**
 * Tuple with information about a KYC check to perform.  Note that it will
 * have references into the legitimization rule set provided to
 * #TALER_KYCLOGIC_requirements_to_check() and thus has a lifetime that
 * matches the legitimization rule set.
 *
 * FIXME(fdold, 2024-11-07): Consider not making this public,
 * instead use struct TALER_KYCLOGIC_Measure.
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
 * A KYC check @a kcc has been triggered. Convert the resulting singular
 * requirement (only a single check is possible, not multiple alternatives)
 * into JSON of type ``LegitimizationMeasures`` for the legitimization
 * measures table.
 *
 * @param kcc check that was triggered
 * @return JSON serialization of the corresponding
 *   ``LegitimizationMeasures``
 */
json_t *
TALER_KYCLOGIC_check_to_jmeasures (
  const struct TALER_KYCLOGIC_KycCheckContext *kcc);


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
 * Check if the form data matches the requirements
 * of the selected measure.
 *
 * @param jmeasures a LegitimizationMeasures object
 * @param measure_index an index into the measures
 * @param form_data form data submitted for the measure
 * @param[out] error_message set to error details
 * @return #TALER_EC_NONE if the form data matches the measure
 */
enum TALER_ErrorCode
TALER_KYCLOGIC_check_form (
  const json_t *jmeasures,
  size_t measure_index,
  const json_t *form_data,
  const char **error_message);


/**
 * Convert MeasureInformation into the
 * KycRequirementInformation used by the client.
 *
 * @param check_name the prescribed check
 * @param prog_name the program to run
 * @param context context to return, can be NULL
 * @param access_token access token for the measure
 * @param offset offset of the measure
 * @param legitimization_measure_row_id row in the legitimization_measures table
 * @return JSON object with matching KycRequirementInformation
 */
json_t *
TALER_KYCLOGIC_measure_to_requirement (
  const char *check_name,
  const char *prog_name,
  const json_t *context,
  const struct TALER_AccountAccessTokenP *access_token,
  size_t offset,
  uint64_t legitimization_measure_row_id);


/**
 * Lookup measures from @a measures_spec in @a lrs and create JSON object with
 * the corresponding LegitimizationMeasures.
 *
 * @param lrs set of legitimization rules
 * @param measures_spec space-separated set of a measures to trigger from @a lrs; "+"-prefixed if AND-cominbation applies
 * @return JSON object of type LegitimizationMeasures
 */
json_t *
TALER_KYCLOGIC_get_jmeasures (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measures_spec);

/**
 * Lookup the provider for the given @a check_name.
 *
 * @param check_name check to lookup provider for
 * @return NULL on error (@a check_name unknown or
 *    not a check that has a provider)
 */
const struct TALER_KYCLOGIC_KycProvider *
TALER_KYCLOGIC_check_to_provider (const char *check_name);


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
 * Find default measure @a measure_name.
 *
 * @param measure_name name of measure to find
 * @param[out] kcc initialized with KYC check data
 *    for the default measure
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_get_original_measure (
  const char *measure_name,
  struct TALER_KYCLOGIC_KycCheckContext *kcc);


/**
 * Obtain the provider logic for a given set of @a lrs
 * and a specific @a kyc_rule from @a lrs that was
 * triggered and the chosen @a measure_name from the
 * list of measures of that @a kyc_rule.  Can also be
 * used to obtain the "current" check of a @a lrs if
 * no trigger has been hit.
 *
 * @param lrs rule set
 * @param kyc_rule rule that was triggered, NULL
 *   to merely lookup the measure without any trigger
 * @param measure_name selected measure,
 *   NULL to return the "new_check" set by the @a lrs
 * @param[out] kcc set to check to run;
 *   kcc->check will be NULL if the "skip" check is used
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
 * Return successor measure for the given @a lrs
 *
 * @param lrs legitimization rules to inspect
 * @return successor measure;
 *    NULL to fall back to default rules;
 *    pointer will be valid as long as @a lrs is valid
 */
const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_rules_get_successor (
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
 * triggered and the chosen @a measure_name from the
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


/**
 * Check if there is a measure triggered by the
 * KYC rule @a r that has a check name of "SKIP" and
 * thus should be immediately executed. If such a
 * measure exists, return it.
 *
 * @param r rule to check for instant measures
 * @return NULL if there is no instant measure
 */
const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_rule_get_instant_measure (
  const struct TALER_KYCLOGIC_KycRule *r);


/**
 * Check if there is a measure in @a lrs
 * that is included in @a measure_spec
 * and a SKIP measure, and thus should be immediately
 * executed.
 *
 * @param lrs legitimization rule set
 * @param measures_spec measures spec
 * @returns NULL if there is no instant measure
 */
const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_get_instant_measure (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measures_spec);


/**
 * Check if there is a measure in @a lrs that is named @a measure.
 *
 * @param lrs legitimization rule set
 * @param measure_name measures spec
 * @returns NULL if not found
 */
const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_get_measure (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measure_name);


/**
 * Convert a measure to JSON.
 *
 * @param m measure to convert to JSON
 * @returns JSON representation of the measure
 */
json_t *
TALER_KYCLOGIC_measure_to_jmeasures (
  const struct TALER_KYCLOGIC_Measure *m);


/**
 * Handle to manage a running AML program.
 */
struct TALER_KYCLOGIC_AmlProgramRunnerHandle;


/**
 * Result from running an AML program.
 */
struct TALER_KYCLOGIC_AmlProgramResult
{
  /**
   * Possible outcomes from running the AML program.
   */
  enum
  {
    /**
     * The AML program completed successfully.
     */
    TALER_KYCLOGIC_AMLR_SUCCESS,

    /**
     * The AML program failed.
     */
    TALER_KYCLOGIC_AMLR_FAILURE

  } status;

  /**
   * Detailed results depending on @e status.
   */
  union
  {
    /**
     * Results if @e status is #TALER_KYCLOGIC_AMLR_SUCCESS.
     */
    struct
    {
      /**
       * New account properties to set for the account.
       */
      const json_t *account_properties;

      /**
       * Array of events to trigger.
       */
      const char **events;

      /**
       * New AML/KYC rules to apply to the account.
       */
      const json_t *new_rules;

      /**
       * Length of the @e events array.
       */
      unsigned int num_events;

      /**
       * True if AML staff should investigate the account.
       */
      bool to_investigate;
    } success;

    /**
     * Results if @e status is #TALER_KYCLOGIC_AMLR_FAILURE.
     */
    struct
    {
      /**
       * Fallback measure to trigger.
       */
      const char *fallback_measure;

      /**
       * Human-readable error message describing the
       * failure (for logging).
       */
      const char *error_message;

      /**
       * Error code for the failure.
       */
      enum TALER_ErrorCode ec;

    } failure;

  } details;

};


/**
 * Type of function called after AML program was run.
 *
 * @param cls closure
 * @param apr result of the AML program.
 */
typedef void
(*TALER_KYCLOGIC_AmlProgramResultCallback) (
  void *cls,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr);


/**
 * Run AML program based on @a jmeasures using
 * the the given inputs.
 *
 * @param attributes KYC attributes newly obtained
 * @param aml_history AML history of the account
 * @param kyc_history KYC history of the account
 * @param jmeasures current KYC/AML rules to apply;
 *           they determine also the AML program and
 *           provide the context
 * @param measure_index which KYC measure yielded the
 *       @a attributes
 * @param aprc function to call with the result
 * @param aprc_cls closure for @a aprc
 * @return NULL if @a jmeasures is invalid for the
 *   selected @a measure_index or @a attributes
 */
struct TALER_KYCLOGIC_AmlProgramRunnerHandle *
TALER_KYCLOGIC_run_aml_program (
  const json_t *attributes,
  const json_t *aml_history,
  const json_t *kyc_history,
  const json_t *jmeasures,
  unsigned int measure_index,
  TALER_KYCLOGIC_AmlProgramResultCallback aprc,
  void *aprc_cls);


/**
 * Run AML program @a prog_name with the given @a context.
 *
 * @param prog_name name of AML program to run
 * @param attributes attributes to run with
 * @param aml_history AML history of the account
 * @param kyc_history KYC history of the account
 * @param context context to run with
 * @param aprc function to call with the result
 * @param aprc_cls closure for @a aprc
 * @return NULL if @a jmeasures is invalid for the
 *   selected @a measure_index or @a attributes
 */
struct TALER_KYCLOGIC_AmlProgramRunnerHandle *
TALER_KYCLOGIC_run_aml_program2 (
  const char *prog_name,
  const json_t *attributes,
  const json_t *aml_history,
  const json_t *kyc_history,
  const json_t *context,
  TALER_KYCLOGIC_AmlProgramResultCallback aprc,
  void *aprc_cls);


/**
 * Run AML program specified by the given
 * measure.
 *
 * @param measure measure with program name and context
 *         to run
 * @param attributes attributes to run with
 * @param aml_history AML history of the account
 * @param kyc_history KYC history of the account
 * @param aprc function to call with the result
 * @param aprc_cls closure for @a aprc
 * @return NULL if @a jmeasures is invalid for the
 *   selected @a measure_index or @a attributes
 */
struct TALER_KYCLOGIC_AmlProgramRunnerHandle *
TALER_KYCLOGIC_run_aml_program3 (
  const struct TALER_KYCLOGIC_Measure *measure,
  const json_t *attributes,
  const json_t *aml_history,
  const json_t *kyc_history,
  TALER_KYCLOGIC_AmlProgramResultCallback aprc,
  void *aprc_cls);


/**
 * Cancel running AML program.
 *
 * @param[in] aprh handle of program to cancel
 */
void
TALER_KYCLOGIC_run_aml_program_cancel (
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh);

#endif
