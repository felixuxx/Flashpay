/*
  This file is part of TALER
  Copyright (C) 2022-2024 Taler Systems SA

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
 * @file kyclogic_api.c
 * @brief server-side KYC API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"

/**
 * Name of the KYC measure that may never be passed. Useful if some
 * operations/amounts are categorically forbidden.
 */
#define KYC_MEASURE_IMPOSSIBLE "verboten"

/**
 * Information about a KYC provider.
 */
struct TALER_KYCLOGIC_KycProvider
{

  /**
   * Name of the provider.
   */
  char *provider_name;

  /**
   * Logic to run for this provider.
   */
  struct TALER_KYCLOGIC_Plugin *logic;

  /**
   * Provider-specific details to pass to the @e logic functions.
   */
  struct TALER_KYCLOGIC_ProviderDetails *pd;

};


/**
 * Rule that triggers some measure(s).
 */
struct TALER_KYCLOGIC_KycRule
{

  /**
   * Name of the rule (configuration section name).
   * NULL if not from the configuration.
   */
  char *rule_name;

  /**
   * Rule set with custom measures that this KYC rule
   * is part of.
   */
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

  /**
   * Timeframe to consider for computing the amount
   * to compare against the @e limit.  Zero for the
   * wallet balance trigger (as not applicable).
   */
  struct GNUNET_TIME_Relative timeframe;

  /**
   * Maximum amount that can be transacted until
   * the rule triggers.
   */
  struct TALER_Amount threshold;

  /**
   * Array of names of measures to apply on this trigger.
   */
  char **next_measures;

  /**
   * Length of the @e next_measures array.
   */
  unsigned int num_measures;

  /**
   * Display priority for this rule.
   */
  uint32_t display_priority;

  /**
   * What operation type is this rule for?
   */
  enum TALER_KYCLOGIC_KycTriggerEvent trigger;

  /**
   * True if all @e next_measures will eventually need to
   * be satisfied, False if the user has a choice between them.
   */
  bool is_and_combinator;

  /**
   * True if this rule and the general nature of the next measures
   * should be exposed to the client.
   */
  bool exposed;

  /**
   * True if any of the measures is 'verboten' and
   * thus this rule cannot ever be satisfied.
   */
  bool verboten;

};


/**
 * Set of rules that applies to an account.
 */
struct TALER_KYCLOGIC_LegitimizationRuleSet
{

  /**
   * When does this rule set expire?
   */
  struct GNUNET_TIME_Timestamp expiration_time;

  /**
   * Name of the successor measure after expiration.
   * NULL to revert to default rules.
   */
  char *successor_measure;

  /**
   * This object in JSON format. Excludes *default* measures even
   * if these are the default rules.
   */
  json_t *jlrs;

  /**
   * Array of the rules.
   */
  struct TALER_KYCLOGIC_KycRule *kyc_rules;

  /**
   * Array of custom measures the @e kyc_rules may refer
   * to.
   */
  struct TALER_KYCLOGIC_Measure *custom_measures;

  /**
   * Length of the @e kyc_rules array.
   */
  unsigned int num_kyc_rules;

  /**
   * Length of the @e custom_measures array.
   */
  unsigned int num_custom_measures;

};


/**
 * AML program inputs as per "-i" option of the AML program.
 * This is a bitmask.
 */
enum AmlProgramInputs
{
  /**
   * No inputs are needed.
   */
  API_NONE = 0,

  /**
   * Context is needed.
   */
  API_CONTEXT = 1,

  /**
   * Current (just submitted) attributes needed.
   */
  API_ATTRIBUTES = 2,

  /**
   * Current AML rules are needed.
   */
  API_CURRENT_RULES = 4,

  /**
   * Default AML rules (that apply to fresh accounts) are needed.
   */
  API_DEFAULT_RULES = 8,

  /**
   * Account AML history is needed, possibly length-limited,
   * see ``aml_history_length_limit``.
   */
  API_AML_HISTORY = 16,

  /**
   * Account KYC history is needed, possibly length-limited,
   * see ``kyc_history_length_limit``
   */
  API_KYC_HISTORY = 32,

};


/**
 * AML programs.
 */
struct TALER_KYCLOGIC_AmlProgram
{

  /**
   * Name of the AML program configuration section.
   */
  char *program_name;

  /**
   * Name of the AML program (binary) to run.
   */
  char *command;

  /**
   * Human-readable description of what this AML helper
   * program will do.
   */
  char *description;

  /**
   * Name of an original measure to take in case the
   * @e command fails, NULL to fallback to default rules.
   */
  char *fallback;

  /**
   * Output of @e command "-r".
   */
  char **required_contexts;

  /**
   * Length of the @e required_contexts array.
   */
  unsigned int num_required_contexts;

  /**
   * Output of @e command "-a".
   */
  char **required_attributes;

  /**
   * Length of the @e required_attributes array.
   */
  unsigned int num_required_attributes;

  /**
   * Bitmask of inputs this AML program would like (based on '-i').
   */
  enum AmlProgramInputs input_mask;

  /**
   * How many entries of the AML history are requested;
   * negative number if we want the latest entries only.
   */
  long long aml_history_length_limit;

  /**
   * How many entries of the KYC history are requested;
   * negative number if we want the latest entries only.
   */
  long long kyc_history_length_limit;

};


/**
 * Array of @e num_kyc_logics KYC logic plugins we have loaded.
 */
static struct TALER_KYCLOGIC_Plugin **kyc_logics;

/**
 * Length of the #kyc_logics array.
 */
static unsigned int num_kyc_logics;

/**
 * Array of configured providers.
 */
static struct TALER_KYCLOGIC_KycProvider **kyc_providers;

/**
 * Length of the #kyc_providers array.
 */
static unsigned int num_kyc_providers;

/**
 * Array of @e num_kyc_checks known types of
 * KYC checks.
 */
static struct TALER_KYCLOGIC_KycCheck **kyc_checks;

/**
 * Length of the #kyc_checks array.
 */
static unsigned int num_kyc_checks;

/**
 * Rules that apply if we do not have an AMLA record.
 */
static struct TALER_KYCLOGIC_LegitimizationRuleSet default_rules;

/**
 * Array of available AML programs.
 */
static struct TALER_KYCLOGIC_AmlProgram **aml_programs;

/**
 * Length of the #aml_programs array.
 */
static unsigned int num_aml_programs;

/**
 * Name of our configuration file.
 */
static char *cfg_filename;

/**
 * Currency we expect to see in all rules.
 */
static char *my_currency;


struct GNUNET_TIME_Timestamp
TALER_KYCLOGIC_rules_get_expiration (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs)
{
  if (NULL == lrs)
    return GNUNET_TIME_UNIT_FOREVER_TS;
  return lrs->expiration_time;
}


const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_rules_get_successor (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs)
{
  const char *successor_measure_name = lrs->successor_measure;

  if (NULL == successor_measure_name)
  {
    return NULL;
  }
  return TALER_KYCLOGIC_get_measure (
    lrs,
    successor_measure_name);
}


/**
 * Lookup a KYC check by @a check_name
 *
 * @param check_name name to search for
 * @return NULL if not found
 */
static struct TALER_KYCLOGIC_KycCheck *
find_check (const char *check_name)
{
  for (unsigned int i = 0; i<num_kyc_checks; i++)
  {
    struct TALER_KYCLOGIC_KycCheck *kyc_check
      = kyc_checks[i];

    if (0 == strcasecmp (check_name,
                         kyc_check->check_name))
      return kyc_check;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Check `%s' unknown\n",
              check_name);
  return NULL;
}


/**
 * Lookup AML program by @a program_name
 *
 * @param program_name name to search for
 * @return NULL if not found
 */
static struct TALER_KYCLOGIC_AmlProgram *
find_program (const char *program_name)
{
  for (unsigned int i = 0; i<num_aml_programs; i++)
  {
    struct TALER_KYCLOGIC_AmlProgram *program
      = aml_programs[i];

    if (0 == strcasecmp (program_name,
                         program->program_name))
      return program;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "AML program `%s' unknown\n",
              program_name);
  return NULL;
}


/**
 * Lookup KYC provider by @a provider_name
 *
 * @param provider_name name to search for
 * @return NULL if not found
 */
static struct TALER_KYCLOGIC_KycProvider *
find_provider (const char *provider_name)
{
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *provider
      = kyc_providers[i];

    if (0 == strcasecmp (provider_name,
                         provider->provider_name))
      return provider;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "KYC provider `%s' unknown\n",
              provider_name);
  return NULL;
}


/**
 * Check that @a measure is well-formed and internally
 * consistent.
 *
 * @param measure measure to check
 * @return true if measure is well-formed
 */
static bool
check_measure (const struct TALER_KYCLOGIC_Measure *measure)
{
  const struct TALER_KYCLOGIC_KycCheck *check;
  const struct TALER_KYCLOGIC_AmlProgram *program;

  program = find_program (measure->prog_name);
  if (NULL == program)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unknown program `%s' used in measure `%s'\n",
                measure->prog_name,
                measure->measure_name);
    return false;
  }
  for (unsigned int j = 0; j<program->num_required_contexts; j++)
  {
    const char *required_context = program->required_contexts[j];

    if (NULL ==
        json_object_get (measure->context,
                         required_context))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Measure `%s' lacks required context `%s' for AML program `%s'\n",
                  measure->measure_name,
                  required_context,
                  program->program_name);
      return false;
    }
  }
  if (0 == strcasecmp (measure->check_name,
                       "SKIP"))
  {
    if (0 != program->num_required_attributes)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "AML program `%s' of measure `%s' has required attributes, but check is of type `SKIP' and thus cannot provide any!\n",
                  program->program_name,
                  measure->measure_name);
      return false;
    }
    return true;
  }
  check = find_check (measure->check_name);
  if (NULL == check)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unknown check `%s' used in measure `%s'\n",
                measure->check_name,
                measure->measure_name);
    return false;
  }
  for (unsigned int j = 0; j<program->num_required_attributes; j++)
  {
    const char *required_attribute = program->required_attributes[j];
    bool found = false;

    for (unsigned int i = 0; i<check->num_outputs; i++)
    {
      if (0 == strcasecmp (required_attribute,
                           check->outputs[i]))
      {
        found = true;
        break;
      }
    }
    if (! found)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Check `%s' of measure `%s' does not provide required output `%s' for AML program `%s'\n",
                  check->check_name,
                  measure->measure_name,
                  required_attribute,
                  program->program_name);
      return false;
    }
  }
  for (unsigned int j = 0; j<check->num_requires; j++)
  {
    const char *required_input = check->requires[j];

    if (NULL ==
        json_object_get (measure->context,
                         required_input))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Measure `%s' lacks required context `%s' for check `%s'\n",
                  measure->measure_name,
                  required_input,
                  check->check_name);
      return false;
    }
  }
  return true;
}


struct TALER_KYCLOGIC_LegitimizationRuleSet *
TALER_KYCLOGIC_rules_parse (const json_t *jlrs)
{
  struct GNUNET_TIME_Timestamp expiration_time;
  const char *successor_measure = NULL;
  const json_t *jrules;
  const json_t *jcustom_measures;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp (
      "expiration_time",
      &expiration_time),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_string (
        "successor_measure",
        &successor_measure),
      NULL),
    GNUNET_JSON_spec_array_const ("rules",
                                  &jrules),
    GNUNET_JSON_spec_object_const ("custom_measures",
                                   &jcustom_measures),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;
  const char *err;
  unsigned int line;

  if (NULL == jlrs)
  {
    GNUNET_break_op (0);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_JSON_parse (jlrs,
                         spec,
                         &err,
                         &line))
  {
    GNUNET_break_op (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Legitimization rules have incorrect input field `%s'\n",
                err);
    json_dumpf (jlrs,
                stderr,
                JSON_INDENT (2));
    return NULL;
  }
  lrs = GNUNET_new (struct TALER_KYCLOGIC_LegitimizationRuleSet);
  lrs->expiration_time = expiration_time;
  lrs->successor_measure
    = (NULL == successor_measure)
    ? NULL
    : GNUNET_strdup (successor_measure);
  lrs->num_kyc_rules
    = (unsigned int) json_array_size (jrules);
  if (((size_t) lrs->num_kyc_rules) !=
      json_array_size (jrules))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  lrs->num_custom_measures
    = (unsigned int) json_object_size (jcustom_measures);
  if (((size_t) lrs->num_custom_measures) !=
      json_object_size (jcustom_measures))
  {
    GNUNET_break (0);
    goto cleanup;
  }
  lrs->jlrs
    = json_incref ((json_t *) jlrs);
  lrs->kyc_rules
    = GNUNET_new_array (lrs->num_kyc_rules,
                        struct TALER_KYCLOGIC_KycRule);
  {
    const json_t *jrule;
    size_t off;

    json_array_foreach ((json_t *) jrules,
                        off,
                        jrule)
    {
      struct TALER_KYCLOGIC_KycRule *rule
        = &lrs->kyc_rules[off];
      const json_t *jmeasures;
      struct GNUNET_JSON_Specification ispec[] = {
        TALER_JSON_spec_kycte ("operation_type",
                               &rule->trigger),
        TALER_JSON_spec_amount ("threshold",
                                my_currency,
                                &rule->threshold),
        GNUNET_JSON_spec_relative_time ("timeframe",
                                        &rule->timeframe),
        GNUNET_JSON_spec_array_const ("measures",
                                      &jmeasures),
        GNUNET_JSON_spec_uint32 ("display_priority",
                                 &rule->display_priority),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("exposed",
                                 &rule->exposed),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("is_and_combinator",
                                 &rule->is_and_combinator),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jrule,
                             ispec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        goto cleanup;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Parsed KYC rule %u for %d with threshold %s\n",
                  (unsigned int) off,
                  (int) rule->trigger,
                  TALER_amount2s (&rule->threshold));
      rule->lrs = lrs;
      rule->num_measures = json_array_size (jmeasures);
      rule->next_measures
        = GNUNET_new_array (rule->num_measures,
                            char *);
      if (((size_t) rule->num_measures) !=
          json_array_size (jmeasures))
      {
        GNUNET_break (0);
        goto cleanup;
      }
      {
        size_t j;
        json_t *jmeasure;

        json_array_foreach (jmeasures,
                            j,
                            jmeasure)
        {
          const char *str;

          str = json_string_value (jmeasure);
          if (NULL == str)
          {
            GNUNET_break (0);
            goto cleanup;
          }
          if (0 == strcasecmp (str, KYC_MEASURE_IMPOSSIBLE))
          {
            rule->verboten = true;
          }
          rule->next_measures[j]
            = GNUNET_strdup (str);
        }
      }
    }
  }

  lrs->custom_measures
    = GNUNET_new_array (lrs->num_custom_measures,
                        struct TALER_KYCLOGIC_Measure);

  {
    const json_t *jmeasure;
    const char *measure_name;
    unsigned int off = 0;

    json_object_foreach ((json_t *) jcustom_measures,
                         measure_name,
                         jmeasure)
    {
      const char *check_name;
      const char *prog_name;
      const json_t *context = NULL;
      bool voluntary = false;
      struct TALER_KYCLOGIC_Measure *measure
        = &lrs->custom_measures[off++];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("check_name",
                                 &check_name),
        GNUNET_JSON_spec_string ("prog_name",
                                 &prog_name),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_object_const ("context",
                                         &context),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("voluntary",
                                 &voluntary),
          NULL),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jmeasure,
                             ispec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        goto cleanup;
      }
      measure->measure_name
        = GNUNET_strdup (measure_name);
      measure->check_name
        = GNUNET_strdup (check_name);
      measure->prog_name
        = GNUNET_strdup (prog_name);
      measure->voluntary
        = voluntary;
      if (NULL != context)
        measure->context
          = json_incref ((json_t*) context);
      if (! check_measure (measure))
      {
        GNUNET_break_op (0);
        goto cleanup;
      }
    }
  }
  return lrs;
cleanup:
  TALER_KYCLOGIC_rules_free (lrs);
  return NULL;
}


void
TALER_KYCLOGIC_rules_free (struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs)
{
  if (NULL == lrs)
    return;
  for (unsigned int i = 0; i<lrs->num_kyc_rules; i++)
  {
    struct TALER_KYCLOGIC_KycRule *rule
      = &lrs->kyc_rules[i];

    for (unsigned int j = 0; j<rule->num_measures; j++)
      GNUNET_free (rule->next_measures[j]);
    GNUNET_free (rule->next_measures);
    GNUNET_free (rule->rule_name);
  }
  for (unsigned int i = 0; i<lrs->num_custom_measures; i++)
  {
    struct TALER_KYCLOGIC_Measure *measure
      = &lrs->custom_measures[i];

    GNUNET_free (measure->measure_name);
    GNUNET_free (measure->check_name);
    GNUNET_free (measure->prog_name);
    json_decref (measure->context);
  }
  GNUNET_free (lrs->kyc_rules);
  json_decref (lrs->jlrs);
  GNUNET_free (lrs->custom_measures);
  GNUNET_free (lrs->successor_measure);
  GNUNET_free (lrs);
}


const char *
TALER_KYCLOGIC_rule2s (
  const struct TALER_KYCLOGIC_KycRule *r)
{
  return r->rule_name;
}


const char *
TALER_KYCLOGIC_status2s (enum TALER_KYCLOGIC_KycStatus status)
{
  switch (status)
  {
  case TALER_KYCLOGIC_STATUS_SUCCESS:
    return "success";
  case TALER_KYCLOGIC_STATUS_USER:
    return "user";
  case TALER_KYCLOGIC_STATUS_PROVIDER:
    return "provider";
  case TALER_KYCLOGIC_STATUS_FAILED:
    return "failed";
  case TALER_KYCLOGIC_STATUS_PENDING:
    return "pending";
  case TALER_KYCLOGIC_STATUS_ABORTED:
    return "aborted";
  case TALER_KYCLOGIC_STATUS_USER_PENDING:
    return "pending with user";
  case TALER_KYCLOGIC_STATUS_PROVIDER_PENDING:
    return "pending at provider";
  case TALER_KYCLOGIC_STATUS_USER_ABORTED:
    return "aborted by user";
  case TALER_KYCLOGIC_STATUS_PROVIDER_FAILED:
    return "failed by provider";
  case TALER_KYCLOGIC_STATUS_KEEP:
    return "keep";
  case TALER_KYCLOGIC_STATUS_INTERNAL_ERROR:
    return "internal error";
  }
  return "unknown status";
}


json_t *
TALER_KYCLOGIC_rules_to_limits (const json_t *jrules)
{
  if (NULL == jrules)
  {
    /* default limits apply */
    const struct TALER_KYCLOGIC_KycRule *rules
      = default_rules.kyc_rules;
    unsigned int num_rules
      = default_rules.num_kyc_rules;
    json_t *jlimits;

    jlimits = json_array ();
    GNUNET_assert (NULL != jlimits);
    for (unsigned int i = 0; i<num_rules; i++)
    {
      const struct TALER_KYCLOGIC_KycRule *rule = &rules[i];
      json_t *limit;

      if (! rule->exposed)
        continue;
      limit = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_string ("rule_name",
                                   rule->rule_name)),
        GNUNET_JSON_pack_bool ("soft_limit",
                               ! rule->verboten),
        TALER_JSON_pack_kycte ("operation_type",
                               rule->trigger),
        GNUNET_JSON_pack_time_rel ("timeframe",
                                   rule->timeframe),
        TALER_JSON_pack_amount ("threshold",
                                &rule->threshold)
        );
      GNUNET_assert (0 ==
                     json_array_append_new (jlimits,
                                            limit));
    }
    return jlimits;
  }

  {
    json_t *limits;
    json_t *limit;
    json_t *rule;
    size_t idx;

    limits = json_array ();
    GNUNET_assert (NULL != limits);
    json_array_foreach ((json_t *) jrules, idx, rule)
    {
      struct GNUNET_TIME_Relative timeframe;
      struct TALER_Amount threshold;
      bool exposed = false;
      const json_t *jmeasures;
      const char *rule_name;
      enum TALER_KYCLOGIC_KycTriggerEvent operation_type;
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_kycte ("operation_type",
                               &operation_type),
        GNUNET_JSON_spec_relative_time ("timeframe",
                                        &timeframe),
        TALER_JSON_spec_amount ("threshold",
                                my_currency,
                                &threshold),
        GNUNET_JSON_spec_array_const ("measures",
                                      &jmeasures),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_bool ("exposed",
                                 &exposed),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_string ("rule_name",
                                   &rule_name),
          NULL),
        GNUNET_JSON_spec_end ()
      };
      bool forbidden = false;
      size_t i;
      json_t *jmeasure;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jrules,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        json_decref (limits);
        return NULL;
      }
      if (! exposed)
        continue;
      json_array_foreach (jmeasures, i, jmeasure)
      {
        const char *val;

        val = json_string_value (jmeasure);
        if (NULL == val)
        {
          GNUNET_break_op (0);
          json_decref (limits);
          return NULL;
        }
        if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                             val))
          forbidden = true;
      }

      limit = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_string ("rule_name",
                                   rule_name)),
        TALER_JSON_pack_kycte (
          "operation_type",
          operation_type),
        GNUNET_JSON_pack_time_rel (
          "timeframe",
          timeframe),
        TALER_JSON_pack_amount (
          "threshold",
          &threshold),
        /* optional since v21, defaults to 'false' */
        GNUNET_JSON_pack_bool (
          "soft_limit",
          ! forbidden));
      GNUNET_assert (0 ==
                     json_array_append_new (limits,
                                            limit));
    }
    return limits;
  }
}


/**
 * Find measure @a measure_name in @a lrs.
 * If measure is not found in @a lrs, fall back to
 * default measures.
 *
 * @param lrs rule set to search, can be NULL to only search default measures
 * @param measure_name name of measure to find
 * @return NULL if not found, otherwise the measure
 */
static const struct TALER_KYCLOGIC_Measure *
find_measure (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measure_name)
{
  if (NULL != lrs)
  {
    for (unsigned int i = 0; i<lrs->num_custom_measures; i++)
    {
      const struct TALER_KYCLOGIC_Measure *cm
        = &lrs->custom_measures[i];

      if (0 == strcasecmp (measure_name,
                           cm->measure_name))
        return cm;
    }
  }
  if (lrs != &default_rules)
  {
    /* Try measures from default rules */
    for (unsigned int i = 0; i<default_rules.num_custom_measures; i++)
    {
      const struct TALER_KYCLOGIC_Measure *cm
        = &default_rules.custom_measures[i];

      if (0 == strcasecmp (measure_name,
                           cm->measure_name))
        return cm;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Measure `%s' not found\n",
              measure_name);
  return NULL;
}


const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_rule_get_instant_measure (
  const struct TALER_KYCLOGIC_KycRule *r)
{
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs
    = r->lrs;

  if (r->verboten)
    return NULL;
  for (unsigned int i = 0; i<r->num_measures; i++)
  {
    const char *measure_name = r->next_measures[i];
    const struct TALER_KYCLOGIC_Measure *ms;

    if (0 == strcasecmp (measure_name,
                         KYC_MEASURE_IMPOSSIBLE))
    {
      /* If any of the measures if verboten, we do not even
      consider execution of the instant measure. */
      return NULL;
    }

    ms = find_measure (lrs,
                       measure_name);
    if (NULL == ms)
    {
      GNUNET_break (0);
      return NULL;
    }
    if (0 == strcasecmp (ms->check_name,
                         "SKIP"))
      return ms;
  }
  return NULL;
}


json_t *
TALER_KYCLOGIC_rule_to_measures (
  const struct TALER_KYCLOGIC_KycRule *r)
{
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs
    = r->lrs;
  json_t *jmeasures;

  jmeasures = json_array ();
  GNUNET_assert (NULL != jmeasures);
  if (! r->verboten)
  {
    for (unsigned int i = 0; i<r->num_measures; i++)
    {
      const char *measure_name = r->next_measures[i];
      const struct TALER_KYCLOGIC_Measure *ms;
      json_t *mi;

      ms = find_measure (lrs,
                         measure_name);
      if (NULL == ms)
      {
        GNUNET_break (0);
        json_decref (jmeasures);
        return NULL;
      }
      mi = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_string ("check_name",
                                 ms->check_name),
        GNUNET_JSON_pack_string ("prog_name",
                                 ms->prog_name),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("context",
                                          ms->context)));
      GNUNET_assert (0 ==
                     json_array_append_new (jmeasures,
                                            mi));
    }
  }

  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("measures",
                                  jmeasures),
    GNUNET_JSON_pack_bool ("is_and_combinator",
                           r->is_and_combinator),
    GNUNET_JSON_pack_bool ("verboten",
                           r->verboten));
}


json_t *
TALER_KYCLOGIC_zero_measures (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs)
{
  json_t *zero_measures;
  const struct TALER_KYCLOGIC_KycRule *rules;
  unsigned int num_rules;

  if (NULL == lrs)
    lrs = &default_rules;
  rules = lrs->kyc_rules;
  num_rules = lrs->num_kyc_rules;
  zero_measures = json_array ();
  GNUNET_assert (NULL != zero_measures);
  for (unsigned int i = 0; i<num_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule = &rules[i];

    if (! rule->exposed)
      continue;
    if (rule->verboten)
      continue; /* see: hard_limits */
    if (! TALER_amount_is_zero (&rule->threshold))
      continue;
    for (unsigned int j = 0; j<rule->num_measures; j++)
    {
      const struct TALER_KYCLOGIC_Measure *ms;
      json_t *mi;

      ms = find_measure (lrs,
                         rule->next_measures[j]);
      if (NULL == ms)
      {
        GNUNET_break (0);
        json_decref (zero_measures);
        return NULL;
      }
      if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                           ms->check_name))
        continue; /* not a measure to be selected */
      mi = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_string ("rule_name",
                                   rule->rule_name)),
        TALER_JSON_pack_kycte ("operation_type",
                               rule->trigger),
        GNUNET_JSON_pack_string ("check_name",
                                 ms->check_name),
        GNUNET_JSON_pack_string ("prog_name",
                                 ms->prog_name),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("context",
                                          ms->context)));
      GNUNET_assert (0 ==
                     json_array_append_new (zero_measures,
                                            mi));
    }
  }
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("measures",
                                  zero_measures),
    /* Zero-measures are always OR */
    GNUNET_JSON_pack_bool ("is_and_combinator",
                           false),
    /* OR means verboten measures do not matter */
    GNUNET_JSON_pack_bool ("verboten",
                           false));
}


/**
 * Check if @a ms is a voluntary measure, and if so
 * convert to JSON and append to @a voluntary_measures.
 *
 * @param[in,out] voluntary_measures JSON array of MeasureInformation
 * @param ms a measure to possibly append
 */
static void
append_voluntary_measure (
  json_t *voluntary_measures,
  const struct TALER_KYCLOGIC_Measure *ms)
{
#if 0
  json_t *mj;
#endif

  if (! ms->voluntary)
    return;
  if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                       ms->check_name))
    return; /* very strange configuration */
#if 0
  /* TODO: support vATTEST-9048 (this API in kyclogic!) */
  // NOTE: need to convert ms to "KycRequirementInformation"
  // *and* in particular generate "id" values that
  // are then understood to refer to the voluntary measures
  // by the rest of the API (which is the hard part!)
  // => need to change the API to encode the
  // legitimization_outcomes row ID of the lrs from
  // which the voluntary 'ms' originated, and
  // then update the kyc-upload/kyc-start endpoints
  // to recognize the new ID format!
  mj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("check_name",
                             ms->check_name),
    GNUNET_JSON_pack_string ("prog_name",
                             ms->prog_name),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_incref ("context",
                                      ms->context)));
  GNUNET_assert (0 ==
                 json_array_append_new (voluntary_measures,
                                        mj));
#endif
}


json_t *
TALER_KYCLOGIC_voluntary_measures (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs)
{
  json_t *voluntary_measures;

  voluntary_measures = json_array ();
  GNUNET_assert (NULL != voluntary_measures);
  if (NULL != lrs)
  {
    for (unsigned int i = 0; i<lrs->num_custom_measures; i++)
    {
      const struct TALER_KYCLOGIC_Measure *ms
        = &lrs->custom_measures[i];

      append_voluntary_measure (voluntary_measures,
                                ms);
    }
  }
  for (unsigned int i = 0; i<default_rules.num_custom_measures; i++)
  {
    const struct TALER_KYCLOGIC_Measure *ms
      = &default_rules.custom_measures[i];

    append_voluntary_measure (voluntary_measures,
                              ms);
  }
  return voluntary_measures;
}


const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_get_instant_measure (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measures_spec)
{
  char *nm;
  const struct TALER_KYCLOGIC_Measure *ret = NULL;

  GNUNET_assert (NULL != measures_spec);

  if ('+' == measures_spec[0])
  {
    nm = GNUNET_strdup (&measures_spec[1]);
  }
  else
  {
    nm = GNUNET_strdup (measures_spec);
  }
  for (const char *tok = strtok (nm, " ");
       NULL != tok;
       tok = strtok (NULL, " "))
  {
    const struct TALER_KYCLOGIC_Measure *ms;

    if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                         tok))
    {
      continue;
    }
    ms = find_measure (lrs,
                       tok);
    if (NULL == ms)
    {
      GNUNET_break (0);
      continue;
    }
    if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                         ms->check_name))
    {
      continue;
    }
    if (0 == strcasecmp ("SKIP",
                         ms->check_name))
    {
      ret = ms;
      goto done;
    }
  }
done:
  GNUNET_free (nm);
  return ret;
}


const struct TALER_KYCLOGIC_Measure *
TALER_KYCLOGIC_get_measure (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measure_name)
{
  return find_measure (lrs,
                       measure_name);
}


json_t *
TALER_KYCLOGIC_get_jmeasures (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const char *measures_spec)
{
  json_t *jmeasures;
  char *nm;
  bool verboten = false;
  bool is_and = false;

  if ('+' == measures_spec[0])
  {
    nm = GNUNET_strdup (&measures_spec[1]);
    is_and = true;
  }
  else
  {
    nm = GNUNET_strdup (measures_spec);
  }
  jmeasures = json_array ();
  GNUNET_assert (NULL != jmeasures);
  for (const char *tok = strtok (nm, " ");
       NULL != tok;
       tok = strtok (NULL, " "))
  {
    const struct TALER_KYCLOGIC_Measure *ms;
    json_t *mi;

    if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                         tok))
    {
      verboten = true;
      continue;
    }
    ms = find_measure (lrs,
                       tok);
    if (NULL == ms)
    {
      GNUNET_break (0);
      GNUNET_free (nm);
      json_decref (jmeasures);
      return NULL;
    }
    mi = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("check_name",
                               ms->check_name),
      GNUNET_JSON_pack_string ("prog_name",
                               ms->prog_name),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("context",
                                        ms->context)));
    GNUNET_assert (0 ==
                   json_array_append_new (jmeasures,
                                          mi));
  }
  GNUNET_free (nm);
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("measures",
                                  jmeasures),
    GNUNET_JSON_pack_bool ("is_and_combinator",
                           is_and),
    GNUNET_JSON_pack_bool ("verboten",
                           verboten));
}


json_t *
TALER_KYCLOGIC_check_to_jmeasures (
  const struct TALER_KYCLOGIC_KycCheckContext *kcc)
{
  const struct TALER_KYCLOGIC_KycCheck *check
    = kcc->check;
  json_t *jmeasures;
  json_t *mi;

  mi = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("check_name",
                             NULL == check
                             ? "SKIP"
                             : check->check_name),
    GNUNET_JSON_pack_string ("prog_name",
                             kcc->prog_name),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_incref ("context",
                                      (json_t *) kcc->context)));
  jmeasures = json_array ();
  GNUNET_assert (NULL != jmeasures);
  GNUNET_assert (0 ==
                 json_array_append_new (jmeasures,
                                        mi));
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("measures",
                                  jmeasures),
    GNUNET_JSON_pack_bool ("is_and_combinator",
                           true),
    GNUNET_JSON_pack_bool ("verboten",
                           false));
}


json_t *
TALER_KYCLOGIC_measure_to_jmeasures (
  const struct TALER_KYCLOGIC_Measure *m)
{
  json_t *jmeasures;
  json_t *mi;

  mi = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("check_name",
                             m->check_name),
    GNUNET_JSON_pack_string ("prog_name",
                             m->prog_name),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_incref ("context",
                                      (json_t *) m->context)));
  jmeasures = json_array ();
  GNUNET_assert (NULL != jmeasures);
  GNUNET_assert (0 ==
                 json_array_append_new (jmeasures,
                                        mi));
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("measures",
                                  jmeasures),
    GNUNET_JSON_pack_bool ("is_and_combinator",
                           false),
    GNUNET_JSON_pack_bool ("verboten",
                           false));
}


uint32_t
TALER_KYCLOGIC_rule2priority (
  const struct TALER_KYCLOGIC_KycRule *r)
{
  return r->display_priority;
}


/**
 * Perform very primitive word splitting of a command.
 *
 * @param command command to split
 * @param extra_args extra arguments to append after the word
 * @returns NULL-terminated array of words
 */
static char **
split_words (const char *command,
             const char **extra_args)
{
  unsigned int i = 0;
  unsigned int j = 0;
  unsigned int n = 0;
  char **res = NULL;

  /* Result is always NULL-terminated */
  GNUNET_array_append (res, n, NULL);

  /* Split command into words */
  while (1)
  {
    char *c;

    /* Skip initial whitespace before word */
    while (' ' == command[i])
      i++;

    /* Start of new word */
    j = i;

    /* Scan to end of word */
    while ( (0 != command[j]) && (' ' != command[j]) )
      j++;

    /* No new word found */
    if (i == j)
      break;

    /* Append word to result */
    c = GNUNET_malloc (j - i + 1);
    memcpy (c, &command[i], j - i);
    c[j - i] = 0;
    res[n - 1] = c;
    GNUNET_array_append (res, n, NULL);

    /* Continue at end of word */
    i = j;
  }

  /* Append extra args */
  if (NULL != extra_args)
  {
    for (const char **m = extra_args; *m; m++)
    {
      res[n - 1] = GNUNET_strdup (*m);
      GNUNET_array_append (res, n, NULL);
    }
  }

  return res;
}


/**
 * Free arguments allocated with split_words.
 *
 * @param args NULL-terminated array of strings to free.
 */
static void
destroy_words (char **args)
{
  if (NULL == args)
    return;
  for (char **m = args; *m; m++)
  {
    GNUNET_free (*m);
    *m = NULL;
  }
  GNUNET_free (args);
}


/**
 * Run @a command with @a argument and return the
 * respective output from stdout.
 *
 * @param command binary to run
 * @param argument command-line argument to pass
 * @return NULL if @a command failed
 */
static char *
command_output (const char *command,
                const char *argument)
{
  char *rval;
  unsigned int sval;
  size_t soff;
  ssize_t ret;
  int sout[2];
  pid_t chld;
  const char *extra_args[] = {
    argument,
    "-c",
    cfg_filename,
    NULL,
  };

  if (0 != pipe (sout))
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "pipe");
    return NULL;
  }
  chld = fork ();
  if (-1 == chld)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "fork");
    return NULL;
  }
  if (0 == chld)
  {
    char **argv;

    argv = split_words (command,
                        extra_args);

    GNUNET_break (0 ==
                  close (sout[0]));
    GNUNET_break (0 ==
                  close (STDOUT_FILENO));
    GNUNET_assert (STDOUT_FILENO ==
                   dup2 (sout[1],
                         STDOUT_FILENO));
    GNUNET_break (0 ==
                  close (sout[1]));
    execvp (argv[0],
            argv);
    destroy_words (argv);
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "exec",
                              command);
    exit (EXIT_FAILURE);
  }
  GNUNET_break (0 ==
                close (sout[1]));
  sval = 1024;
  rval = GNUNET_malloc (sval);
  soff = 0;
  while (0 < (ret = read (sout[0],
                          rval + soff,
                          sval - soff)) )
  {
    soff += ret;
    if (soff == sval)
    {
      GNUNET_array_grow (rval,
                         sval,
                         sval * 2);
    }
  }
  GNUNET_break (0 == close (sout[0]));
  {
    int wstatus;

    GNUNET_break (chld ==
                  waitpid (chld,
                           &wstatus,
                           0));
    if ( (! WIFEXITED (wstatus)) ||
         (0 != WEXITSTATUS (wstatus)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Command `%s' %s failed with status %d\n",
                  command,
                  argument,
                  wstatus);
      GNUNET_array_grow (rval,
                         sval,
                         0);
      return NULL;
    }
  }
  GNUNET_array_grow (rval,
                     sval,
                     soff + 1);
  rval[soff] = '\0';
  return rval;
}


/**
 * Convert check type @a ctype_s into @a ctype.
 *
 * @param ctype_s check type as a string
 * @param[out] ctype set to check type as enum
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
check_type_from_string (
  const char *ctype_s,
  enum TALER_KYCLOGIC_CheckType *ctype)
{
  struct
  {
    const char *in;
    enum TALER_KYCLOGIC_CheckType out;
  } map [] = {
    { "INFO", TALER_KYCLOGIC_CT_INFO },
    { "LINK", TALER_KYCLOGIC_CT_LINK },
    { "FORM", TALER_KYCLOGIC_CT_FORM  },
    { NULL, 0 }
  };

  for (unsigned int i = 0; NULL != map[i].in; i++)
    if (0 == strcasecmp (map[i].in,
                         ctype_s))
    {
      *ctype = map[i].out;
      return GNUNET_OK;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Invalid check type `%s'\n",
              ctype_s);
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_trigger_from_string (
  const char *trigger_s,
  enum TALER_KYCLOGIC_KycTriggerEvent *trigger)
{
  /* NOTE: if you change this, also change
     the code in src/json/json_helper.c! */
  struct
  {
    const char *in;
    enum TALER_KYCLOGIC_KycTriggerEvent out;
  } map [] = {
    { "WITHDRAW", TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW },
    { "DEPOSIT", TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT  },
    { "MERGE", TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE },
    { "BALANCE", TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE },
    { "CLOSE", TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE },
    { "AGGREGATE", TALER_KYCLOGIC_KYC_TRIGGER_AGGREGATE },
    { "TRANSACTION", TALER_KYCLOGIC_KYC_TRIGGER_TRANSACTION },
    { "REFUND", TALER_KYCLOGIC_KYC_TRIGGER_REFUND },
    { NULL, 0 }
  };

  for (unsigned int i = 0; NULL != map[i].in; i++)
    if (0 == strcasecmp (map[i].in,
                         trigger_s))
    {
      *trigger = map[i].out;
      return GNUNET_OK;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Invalid KYC trigger `%s'\n",
              trigger_s);
  return GNUNET_SYSERR;
}


json_t *
TALER_KYCLOGIC_get_wallet_thresholds (void)
{
  json_t *ret;

  ret = json_array ();
  GNUNET_assert (NULL != ret);
  for (unsigned int i = 0; i<default_rules.num_kyc_rules; i++)
  {
    struct TALER_KYCLOGIC_KycRule *rule
      = &default_rules.kyc_rules[i];

    if (TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE != rule->trigger)
      continue;
    GNUNET_assert (
      0 ==
      json_array_append_new (
        ret,
        TALER_JSON_from_amount (
          &rule->threshold)));
  }
  return ret;
}


/**
 * Load KYC logic plugin.
 *
 * @param cfg configuration to use
 * @param name name of the plugin
 * @return NULL on error
 */
static struct TALER_KYCLOGIC_Plugin *
load_logic (const struct GNUNET_CONFIGURATION_Handle *cfg,
            const char *name)
{
  char *lib_name;
  struct TALER_KYCLOGIC_Plugin *plugin;


  GNUNET_asprintf (&lib_name,
                   "libtaler_plugin_kyclogic_%s",
                   name);
  for (unsigned int i = 0; i<num_kyc_logics; i++)
    if (0 == strcasecmp (lib_name,
                         kyc_logics[i]->library_name))
    {
      GNUNET_free (lib_name);
      return kyc_logics[i];
    }
  plugin = GNUNET_PLUGIN_load (TALER_EXCHANGE_project_data (),
                               lib_name,
                               (void *) cfg);
  if (NULL == plugin)
  {
    GNUNET_free (lib_name);
    return NULL;
  }
  plugin->library_name = lib_name;
  plugin->name = GNUNET_strdup (name);
  GNUNET_array_append (kyc_logics,
                       num_kyc_logics,
                       plugin);
  return plugin;
}


/**
 * Parse configuration of a KYC provider.
 *
 * @param cfg configuration to parse
 * @param section name of the section to analyze
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
add_provider (const struct GNUNET_CONFIGURATION_Handle *cfg,
              const char *section)
{
  char *logic;
  struct TALER_KYCLOGIC_Plugin *lp;
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Parsing KYC provider %s\n",
              section);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "LOGIC",
                                             &logic))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "LOGIC");
    return GNUNET_SYSERR;
  }
  lp = load_logic (cfg,
                   logic);
  if (NULL == lp)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "LOGIC",
                               "logic plugin could not be loaded");
    GNUNET_free (logic);
    return GNUNET_SYSERR;
  }
  GNUNET_free (logic);
  pd = lp->load_configuration (lp->cls,
                               section);
  if (NULL == pd)
    return GNUNET_SYSERR;

  {
    struct TALER_KYCLOGIC_KycProvider *kp;

    kp = GNUNET_new (struct TALER_KYCLOGIC_KycProvider);
    kp->provider_name
      = GNUNET_strdup (&section[strlen ("kyc-provider-")]);
    kp->logic = lp;
    kp->pd = pd;
    GNUNET_array_append (kyc_providers,
                         num_kyc_providers,
                         kp);
  }
  return GNUNET_OK;
}


/**
 * Tokenize @a input along @a token
 * and build an array of the tokens.
 *
 * @param[in,out] input the input to tokenize; clobbered
 * @param sep separator between tokens to separate @a input on
 * @param[out] p_strs where to put array of tokens
 * @param[out] num_strs set to length of @a p_strs array
 */
static void
add_tokens (char *input,
            const char *sep,
            char ***p_strs,
            unsigned int *num_strs)
{
  char *sptr;
  char **rstr = NULL;
  unsigned int num_rstr = 0;

  for (char *tok = strtok_r (input, sep, &sptr);
       NULL != tok;
       tok = strtok_r (NULL, sep, &sptr))
  {
    GNUNET_array_append (rstr,
                         num_rstr,
                         GNUNET_strdup (tok));
  }
  *p_strs = rstr;
  *num_strs = num_rstr;
}


/**
 * Closure for the handle_XXX_section functions
 * that parse configuration sections matching certain
 * prefixes.
 */
struct SectionContext
{
  /**
   * Configuration to handle.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Result to return, set to false on failures.
   */
  bool result;
};


/**
 * Function to iterate over configuration sections.
 *
 * @param cls a `struct SectionContext *`
 * @param section name of the section
 */
static void
handle_provider_section (void *cls,
                         const char *section)
{
  struct SectionContext *sc = cls;

  if (0 == strncasecmp (section,
                        "kyc-provider-",
                        strlen ("kyc-provider-")))
  {
    if (GNUNET_OK !=
        add_provider (sc->cfg,
                      section))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Setup failed in configuration section `%s'\n",
                  section);
      sc->result = false;
    }
    return;
  }
}


/**
 * Parse configuration @a cfg in section @a section for
 * the specification of a KYC check.
 *
 * @param cfg configuration to parse
 * @param section configuration section to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
add_check (const struct GNUNET_CONFIGURATION_Handle *cfg,
           const char *section)
{
  enum TALER_KYCLOGIC_CheckType ct;
  char *description = NULL;
  json_t *description_i18n = NULL;
  char *requires = NULL;
  char *outputs = NULL;
  char *fallback = NULL;

  if (0 == strcasecmp (&section[strlen ("kyc-check-")],
                       "SKIP"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "The kyc-check-skip section must not exist, 'skip' is reserved name for a built-in check\n");
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Parsing KYC check %s\n",
              section);
  {
    char *type_s;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               section,
                                               "TYPE",
                                               &type_s))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "TYPE");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        check_type_from_string (type_s,
                                &ct))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "TYPE",
                                 "valid check type required");
      GNUNET_free (type_s);
      return GNUNET_SYSERR;
    }
    GNUNET_free (type_s);
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "DESCRIPTION",
                                             &description))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "DESCRIPTION");
    goto fail;
  }

  {
    char *tmp;

    if (GNUNET_OK ==
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               section,
                                               "DESCRIPTION_I18N",
                                               &tmp))
    {
      json_error_t err;

      description_i18n = json_loads (tmp,
                                     JSON_REJECT_DUPLICATES,
                                     &err);
      GNUNET_free (tmp);
      if (NULL == description_i18n)
      {
        GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                   section,
                                   "DESCRIPTION_I18N",
                                   err.text);
        goto fail;
      }
      if (! TALER_JSON_check_i18n (description_i18n) )
      {
        GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                   section,
                                   "DESCRIPTION_I18N",
                                   "JSON with internationalization map required");
        goto fail;
      }
    }
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "REQUIRES",
                                             &requires))
  {
    /* no requirements is OK */
    requires = GNUNET_strdup ("");
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "OUTPUTS",
                                             &outputs))
  {
    /* no outputs is OK */
    outputs = GNUNET_strdup ("");
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "FALLBACK",
                                             &fallback))
  {
    /* We do *not* allow NULL to fall back to default rules because fallbacks
       are used when there is actually a serious error and thus some action
       (usually an investigation) is always in order, and that's basically
       never the default. And as fallbacks should be rare, we really insist on
       them at least being explicitly configured. Otherwise these errors may
       go undetected simply because someone forgot to configure a fallback and
       then nothing happens. */
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FALLBACK");
    goto fail;
  }

  {
    struct TALER_KYCLOGIC_KycCheck *kc;

    kc = GNUNET_new (struct TALER_KYCLOGIC_KycCheck);
    switch (ct)
    {
    case TALER_KYCLOGIC_CT_INFO:
      /* nothing to do */
      break;
    case TALER_KYCLOGIC_CT_FORM:
      {
        char *form_name;

        if (GNUNET_OK !=
            GNUNET_CONFIGURATION_get_value_string (cfg,
                                                   section,
                                                   "FORM_NAME",
                                                   &form_name))
        {
          GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                     section,
                                     "FORM_NAME");
          GNUNET_free (requires);
          GNUNET_free (outputs);
          GNUNET_free (kc);
          return GNUNET_SYSERR;
        }
        kc->details.form.name = form_name;
      }
      break;
    case TALER_KYCLOGIC_CT_LINK:
      {
        char *provider_id;

        if (GNUNET_OK !=
            GNUNET_CONFIGURATION_get_value_string (cfg,
                                                   section,
                                                   "PROVIDER_ID",
                                                   &provider_id))
        {
          GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                     section,
                                     "PROVIDER_ID");
          GNUNET_free (requires);
          GNUNET_free (outputs);
          GNUNET_free (kc);
          return GNUNET_SYSERR;
        }
        kc->details.link.provider = find_provider (provider_id);
        if (NULL == kc->details.link.provider)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Unknown KYC provider `%s' used in check `%s'\n",
                      provider_id,
                      &section[strlen ("kyc-check-")]);
          GNUNET_free (provider_id);
          GNUNET_free (requires);
          GNUNET_free (outputs);
          GNUNET_free (kc);
          return GNUNET_SYSERR;
        }
        GNUNET_free (provider_id);
      }
      break;
    }
    kc->check_name = GNUNET_strdup (&section[strlen ("kyc-check-")]);
    kc->description = description;
    kc->description_i18n = description_i18n;
    kc->fallback = fallback;
    kc->type = ct;
    add_tokens (requires,
                "; \n\t",
                &kc->requires,
                &kc->num_requires);
    GNUNET_free (requires);
    add_tokens (outputs,
                "; \n\t",
                &kc->outputs,
                &kc->num_outputs);
    GNUNET_free (outputs);
    GNUNET_array_append (kyc_checks,
                         num_kyc_checks,
                         kc);
  }

  return GNUNET_OK;
fail:
  GNUNET_free (description);
  json_decref (description_i18n);
  GNUNET_free (requires);
  GNUNET_free (outputs);
  GNUNET_free (fallback);
  return GNUNET_SYSERR;
}


/**
 * Function to iterate over configuration sections.
 *
 * @param cls a `struct SectionContext *`
 * @param section name of the section
 */
static void
handle_check_section (void *cls,
                      const char *section)
{
  struct SectionContext *sc = cls;

  if (0 == strncasecmp (section,
                        "kyc-check-",
                        strlen ("kyc-check-")))
  {
    if (GNUNET_OK !=
        add_check (sc->cfg,
                   section))
      sc->result = false;
    return;
  }
}


/**
 * Parse configuration @a cfg in section @a section for
 * the specification of a KYC rule.
 *
 * @param cfg configuration to parse
 * @param section configuration section to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
add_rule (const struct GNUNET_CONFIGURATION_Handle *cfg,
          const char *section)
{
  struct TALER_Amount threshold;
  struct GNUNET_TIME_Relative timeframe;
  enum TALER_KYCLOGIC_KycTriggerEvent ot;
  char *measures;
  bool exposed;
  bool is_and;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Parsing KYC rule from %s\n",
              section);
  if (GNUNET_YES !=
      GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                            section,
                                            "ENABLED"))
    return GNUNET_OK;
  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               section,
                               "THRESHOLD",
                               &threshold))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "THRESHOLD",
                               "amount required");
    return GNUNET_SYSERR;
  }
  exposed = (GNUNET_YES ==
             GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                                   section,
                                                   "EXPOSED"));
  {
    enum GNUNET_GenericReturnValue r;

    r = GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                              section,
                                              "IS_AND_COMBINATOR");
    if (GNUNET_SYSERR == r)
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "IS_AND_COMBINATOR",
                                 "YES or NO required");
      return GNUNET_SYSERR;
    }
    is_and = (GNUNET_YES == r);
  }

  {
    char *ot_s;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               section,
                                               "OPERATION_TYPE",
                                               &ot_s))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "OPERATION_TYPE");
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        TALER_KYCLOGIC_kyc_trigger_from_string (ot_s,
                                                &ot))
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "OPERATION_TYPE",
                                 "valid trigger type required");
      GNUNET_free (ot_s);
      return GNUNET_SYSERR;
    }
    GNUNET_free (ot_s);
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           section,
                                           "TIMEFRAME",
                                           &timeframe))
  {
    if (TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE == ot)
    {
      timeframe = GNUNET_TIME_UNIT_ZERO;
    }
    else
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "TIMEFRAME",
                                 "duration required");
      return GNUNET_SYSERR;
    }
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "NEXT_MEASURES",
                                             &measures))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "NEXT_MEASURES");
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Adding KYC rule %s for trigger %d with threshold %s\n",
              section,
              (int) ot,
              TALER_amount2s (&threshold));
  {
    struct TALER_KYCLOGIC_KycRule kt = {
      .lrs = &default_rules,
      .rule_name = GNUNET_strdup (&section[strlen ("kyc-rule-")]),
      .timeframe = timeframe,
      .threshold = threshold,
      .trigger = ot,
      .is_and_combinator = is_and,
      .exposed = exposed,
      .display_priority = 0,
      .verboten = false
    };

    add_tokens (measures,
                "; \n\t",
                &kt.next_measures,
                &kt.num_measures);
    for (unsigned int i=0; i<kt.num_measures; i++)
      if (0 == strcasecmp (KYC_MEASURE_IMPOSSIBLE,
                           kt.next_measures[i]))
        kt.verboten = true;
    GNUNET_free (measures);
    GNUNET_array_append (default_rules.kyc_rules,
                         default_rules.num_kyc_rules,
                         kt);
  }
  return GNUNET_OK;
}


/**
 * Function to iterate over configuration sections.
 *
 * @param cls a `struct SectionContext *`
 * @param section name of the section
 */
static void
handle_rule_section (void *cls,
                     const char *section)
{
  struct SectionContext *sc = cls;

  if (0 == strncasecmp (section,
                        "kyc-rule-",
                        strlen ("kyc-rule-")))
  {
    if (GNUNET_OK !=
        add_rule (sc->cfg,
                  section))
      sc->result = false;
    return;
  }
}


/**
 * Parse array dimension argument of @a tok (if present)
 * and store result in @a dimp. Does nothing if
 * @a tok does not contain '['. Otherwise does some input
 * validation.
 *
 * @param section name of configuration section for logging
 * @param tok input to parse, of form "text[$DIM]"
 * @param[out] dimp set to value of $DIM
 * @return true on success
 */
static bool
parse_dim (const char *section,
           const char *tok,
           long long *dimp)
{
  const char *dim = strchr (tok,
                            '[');
  char dummy;

  if (NULL == dim)
    return true;
  if (1 !=
      sscanf (dim,
              "[%lld]%c",
              dimp,
              &dummy))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "output for -i invalid (bad dimension given)");
    return false;
  }
  return true;
}


/**
 * Parse configuration @a cfg in section @a section for
 * the specification of an AML program.
 *
 * @param cfg configuration to parse
 * @param section configuration section to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
add_program (const struct GNUNET_CONFIGURATION_Handle *cfg,
             const char *section)
{
  char *command = NULL;
  char *description = NULL;
  char *fallback = NULL;
  char *required_contexts = NULL;
  char *required_attributes = NULL;
  char *required_inputs = NULL;
  enum AmlProgramInputs input_mask = API_NONE;
  long long aml_history_length_limit = INT64_MAX;
  long long kyc_history_length_limit = INT64_MAX;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Parsing KYC program %s\n",
              section);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "COMMAND",
                                             &command))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "command required");
    goto fail;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "DESCRIPTION",
                                             &description))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "DESCRIPTION",
                               "description required");
    goto fail;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "FALLBACK",
                                             &fallback))
  {
    /* We do *not* allow NULL to fall back to default rules because fallbacks
       are used when there is actually a serious error and thus some action
       (usually an investigation) is always in order, and that's basically
       never the default. And as fallbacks should be rare, we really insist on
       them at least being explicitly configured. Otherwise these errors may
       go undetected simply because someone forgot to configure a fallback and
       then nothing happens. */
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FALLBACK",
                               "fallback measure name required");
    goto fail;
  }

  required_contexts = command_output (command,
                                      "-r");
  if (NULL == required_contexts)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "output for -r invalid");
    goto fail;
  }
  required_attributes = command_output (command,
                                        "-a");
  if (NULL == required_attributes)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "output for -a invalid");
    goto fail;
  }

  required_inputs = command_output (command,
                                    "-i");
  if (NULL == required_inputs)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "output for -i invalid");
    goto fail;
  }
  {
    char *sptr;

    for (char *tok = strtok_r (required_inputs,
                               ";\n \t",
                               &sptr);
         NULL != tok;
         tok = strtok_r (NULL,
                         ";\n \t",
                         &sptr) )
    {
      if (0 == strcasecmp (tok,
                           "context"))
        input_mask |= API_CONTEXT;
      else if (0 == strcasecmp (tok,
                                "attributes"))
        input_mask |= API_ATTRIBUTES;
      else if (0 == strcasecmp (tok,
                                "current_rules"))
        input_mask |= API_CURRENT_RULES;
      else if (0 == strcasecmp (tok,
                                "default_rules"))
        input_mask |= API_DEFAULT_RULES;
      else if (0 == strncasecmp (tok,
                                 "aml_history",
                                 strlen ("aml_history")))
      {
        input_mask |= API_AML_HISTORY;
        if (! parse_dim (section,
                         tok,
                         &aml_history_length_limit))
          goto fail;
      }
      else if (0 == strncasecmp (tok,
                                 "kyc_history",
                                 strlen ("kyc_history")))
      {
        input_mask |= API_KYC_HISTORY;
        if (! parse_dim (section,
                         tok,
                         &kyc_history_length_limit))
          goto fail;
      }
      else
      {
        GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                   section,
                                   "COMMAND",
                                   "output for -i invalid (unsupported input)");
        goto fail;
      }
    }
  }
  GNUNET_free (required_inputs);

  {
    struct TALER_KYCLOGIC_AmlProgram *ap;

    ap = GNUNET_new (struct TALER_KYCLOGIC_AmlProgram);
    ap->program_name = GNUNET_strdup (&section[strlen ("aml-program-")]);
    ap->command = command;
    ap->description = description;
    ap->fallback = fallback;
    ap->input_mask = input_mask;
    ap->aml_history_length_limit = aml_history_length_limit;
    ap->kyc_history_length_limit = kyc_history_length_limit;
    add_tokens (required_contexts,
                "; \n\t",
                &ap->required_contexts,
                &ap->num_required_contexts);
    GNUNET_free (required_contexts);
    add_tokens (required_attributes,
                "; \n\t",
                &ap->required_attributes,
                &ap->num_required_attributes);
    GNUNET_free (required_attributes);
    GNUNET_array_append (aml_programs,
                         num_aml_programs,
                         ap);
  }
  return GNUNET_OK;
fail:
  GNUNET_free (command);
  GNUNET_free (description);
  GNUNET_free (required_inputs);
  GNUNET_free (required_contexts);
  GNUNET_free (required_attributes);
  GNUNET_free (fallback);
  return GNUNET_SYSERR;
}


/**
 * Function to iterate over configuration sections.
 *
 * @param cls a `struct SectionContext *`
 * @param section name of the section
 */
static void
handle_program_section (void *cls,
                        const char *section)
{
  struct SectionContext *sc = cls;

  if (0 == strncasecmp (section,
                        "aml-program-",
                        strlen ("aml-program-")))
  {
    if (GNUNET_OK !=
        add_program (sc->cfg,
                     section))
      sc->result = false;
    return;
  }
}


/**
 * Parse configuration @a cfg in section @a section for
 * the specification of a KYC measure.
 *
 * @param cfg configuration to parse
 * @param section configuration section to parse
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
add_measure (const struct GNUNET_CONFIGURATION_Handle *cfg,
             const char *section)
{
  bool voluntary;
  char *check_name = NULL;
  char *context_str = NULL;
  char *program = NULL;
  json_t *context;
  json_error_t err;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Parsing KYC measure %s\n",
              section);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "CHECK_NAME",
                                             &check_name))
  {
    check_name = GNUNET_strdup ("SKIP");
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "PROGRAM",
                                             &program))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "PROGRAM");
    goto fail;
  }
  voluntary = (GNUNET_YES ==
               GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                                     section,
                                                     "VOLUNTARY"));

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "CONTEXT",
                                             &context_str))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "CONTEXT");
    goto fail;
  }
  context = json_loads (context_str,
                        JSON_REJECT_DUPLICATES,
                        &err);
  GNUNET_free (context_str);
  if (NULL == context)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "CONTEXT",
                               err.text);
    goto fail;
  }

  {
    struct TALER_KYCLOGIC_Measure m;

    m.measure_name = GNUNET_strdup (&section[strlen ("kyc-measure-")]);
    m.check_name = check_name;
    m.prog_name = program;
    m.context = context;
    m.voluntary = voluntary;
    GNUNET_array_append (default_rules.custom_measures,
                         default_rules.num_custom_measures,
                         m);
  }
  return GNUNET_OK;
fail:
  GNUNET_free (check_name);
  GNUNET_free (program);
  GNUNET_free (context_str);
  return GNUNET_SYSERR;
}


/**
 * Function to iterate over configuration sections.
 *
 * @param cls a `struct SectionContext *`
 * @param section name of the section
 */
static void
handle_measure_section (void *cls,
                        const char *section)
{
  struct SectionContext *sc = cls;

  if (0 == strncasecmp (section,
                        "kyc-measure-",
                        strlen ("kyc-measure-")))
  {
    if (GNUNET_OK !=
        add_measure (sc->cfg,
                     section))
      sc->result = false;
    return;
  }
}


/**
 * Comparator for qsort. Compares two rules
 * by timeframe to sort rules by time.
 *
 * @param p1 first trigger to compare
 * @param p2 second trigger to compare
 * @return -1 if p1 < p2, 0 if p1==p2, 1 if p1 > p2.
 */
static int
sort_by_timeframe (const void *p1,
                   const void *p2)
{
  struct TALER_KYCLOGIC_KycRule *r1
    = (struct TALER_KYCLOGIC_KycRule *) p1;
  struct TALER_KYCLOGIC_KycRule *r2
    = (struct TALER_KYCLOGIC_KycRule *) p2;

  if (GNUNET_TIME_relative_cmp (r1->timeframe,
                                <,
                                r2->timeframe))
    return -1;
  if (GNUNET_TIME_relative_cmp (r1->timeframe,
                                >,
                                r2->timeframe))
    return 1;
  return 0;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_init (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *cfg_fn)
{
  struct SectionContext sc = {
    .cfg = cfg,
    .result = true
  };
  json_t *jkyc_rules;

  cfg_filename = GNUNET_strdup (cfg_fn);
  GNUNET_assert (GNUNET_OK ==
                 TALER_config_get_currency (cfg,
                                            "exchange",
                                            &my_currency));
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &handle_provider_section,
                                         &sc);
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &handle_check_section,
                                         &sc);
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &handle_rule_section,
                                         &sc);
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &handle_program_section,
                                         &sc);
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &handle_measure_section,
                                         &sc);
  if (! sc.result)
  {
    TALER_KYCLOGIC_kyc_done ();
    return GNUNET_SYSERR;
  }

  if (0 != default_rules.num_kyc_rules)
    qsort (default_rules.kyc_rules,
           default_rules.num_kyc_rules,
           sizeof (struct TALER_KYCLOGIC_KycRule),
           &sort_by_timeframe);
  jkyc_rules = json_array ();
  GNUNET_assert (NULL != jkyc_rules);

  for (unsigned int i=0; i<default_rules.num_kyc_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule
      = &default_rules.kyc_rules[i];
    json_t *jrule;
    json_t *jmeasures;

    jmeasures = json_array ();
    GNUNET_assert (NULL != jmeasures);
    for (unsigned int j=0; j<rule->num_measures; j++)
    {
      const char *measure_name = rule->next_measures[j];
      const struct TALER_KYCLOGIC_Measure *m;

      if (0 == strcmp (KYC_MEASURE_IMPOSSIBLE,
                       measure_name))
        continue;
      m = find_measure (&default_rules,
                        measure_name);
      if (NULL == m)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Unknown measure `%s' used in rule `%s'\n",
                    measure_name,
                    rule->rule_name);
        return GNUNET_SYSERR;
      }
      GNUNET_assert (0 ==
                     json_array_append_new (jmeasures,
                                            json_string (measure_name)));
    }
    jrule = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("rule_name",
                                 rule->rule_name)),
      TALER_JSON_pack_kycte ("operation_type",
                             rule->trigger),
      TALER_JSON_pack_amount ("threshold",
                              &rule->threshold),
      GNUNET_JSON_pack_time_rel ("timeframe",
                                 rule->timeframe),
      GNUNET_JSON_pack_array_steal ("measures",
                                    jmeasures),
      GNUNET_JSON_pack_uint64 ("display_priority",
                               rule->display_priority),
      GNUNET_JSON_pack_bool ("exposed",
                             rule->exposed),
      GNUNET_JSON_pack_bool ("is_and_combinator",
                             rule->is_and_combinator)
      );
    GNUNET_assert (0 ==
                   json_array_append_new (jkyc_rules,
                                          jrule));
  }
  default_rules.jlrs
    = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_timestamp ("expiration_time",
                                    GNUNET_TIME_UNIT_FOREVER_TS),
        GNUNET_JSON_pack_array_steal ("rules",
                                      jkyc_rules)
        );

  for (unsigned int i=0; i<default_rules.num_custom_measures; i++)
  {
    const struct TALER_KYCLOGIC_Measure *measure
      = &default_rules.custom_measures[i];

    if (! check_measure (measure))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Configuration of AML measures incorrect. Exiting.\n");
      return GNUNET_SYSERR;
    }
  }

  for (unsigned int i=0; i<num_aml_programs; i++)
  {
    const struct TALER_KYCLOGIC_AmlProgram *program
      = aml_programs[i];
    const struct TALER_KYCLOGIC_Measure *m;
    const struct TALER_KYCLOGIC_AmlProgram *fprogram;

    m = find_measure (&default_rules,
                      program->fallback);
    if (NULL == m)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unknown fallback measure `%s' used in program `%s'\n",
                  program->fallback,
                  program->program_name);
      return GNUNET_SYSERR;
    }
    if (0 != strcasecmp (m->check_name,
                         "SKIP"))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fallback measure `%s' used in AML program `%s' has a check `%s' but fallbacks must have a check of type 'SKIP'\n",
                  program->fallback,
                  program->program_name,
                  m->check_name);
      return GNUNET_SYSERR;
    }
    fprogram = find_program (m->prog_name);
    GNUNET_assert (NULL != fprogram);
    if (API_NONE != fprogram->input_mask)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fallback program %s of fallback measure `%s' used in AML program `%s' has required inputs, but fallback measures must not require any inputs\n",
                  m->prog_name,
                  program->program_name,
                  m->check_name);
      return GNUNET_SYSERR;
    }
  }

  for (unsigned int i = 0; i<num_kyc_checks; i++)
  {
    struct TALER_KYCLOGIC_KycCheck *kyc_check
      = kyc_checks[i];
    const struct TALER_KYCLOGIC_Measure *measure;
    const struct TALER_KYCLOGIC_AmlProgram *fprogram;

    measure = find_measure (&default_rules,
                            kyc_check->fallback);
    if (NULL == measure)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unknown fallback measure `%s' used in check `%s'\n",
                  kyc_check->fallback,
                  kyc_check->check_name);
      return GNUNET_SYSERR;
    }
    if (0 != strcasecmp (measure->check_name,
                         "SKIP"))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fallback measure `%s' used in KYC check `%s' has a check `%s' but fallbacks must have a check of type 'SKIP'\n",
                  kyc_check->fallback,
                  kyc_check->check_name,
                  measure->check_name);
      return GNUNET_SYSERR;
    }
    fprogram = find_program (measure->prog_name);
    GNUNET_assert (NULL != fprogram);
    if (API_NONE != fprogram->input_mask)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "AML program `%s' used fallback measure `%s' of KYC check `%s' has required inputs, but fallback measures must not require any inputs\n",
                  measure->prog_name,
                  kyc_check->fallback,
                  kyc_check->check_name);
      return GNUNET_SYSERR;
    }
  }

  return GNUNET_OK;
}


void
TALER_KYCLOGIC_kyc_done (void)
{
  for (unsigned int i = 0; i<default_rules.num_kyc_rules; i++)
  {
    struct TALER_KYCLOGIC_KycRule *kt
      = &default_rules.kyc_rules[i];

    for (unsigned int j = 0; j<kt->num_measures; j++)
      GNUNET_free (kt->next_measures[j]);
    GNUNET_array_grow (kt->next_measures,
                       kt->num_measures,
                       0);
    GNUNET_free (kt->rule_name);
  }
  GNUNET_array_grow (default_rules.kyc_rules,
                     default_rules.num_kyc_rules,
                     0);
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    kp->logic->unload_configuration (kp->pd);
    GNUNET_free (kp->provider_name);
    GNUNET_free (kp);
  }
  GNUNET_array_grow (kyc_providers,
                     num_kyc_providers,
                     0);
  for (unsigned int i = 0; i<num_kyc_logics; i++)
  {
    struct TALER_KYCLOGIC_Plugin *lp = kyc_logics[i];
    char *lib_name = lp->library_name;

    GNUNET_free (lp->name);
    GNUNET_assert (NULL == GNUNET_PLUGIN_unload (lib_name,
                                                 lp));
    GNUNET_free (lib_name);
  }
  GNUNET_array_grow (kyc_logics,
                     num_kyc_logics,
                     0);
  for (unsigned int i = 0; i<num_kyc_checks; i++)
  {
    struct TALER_KYCLOGIC_KycCheck *kc = kyc_checks[i];

    GNUNET_free (kc->check_name);
    GNUNET_free (kc->description);
    json_decref (kc->description_i18n);
    for (unsigned int j = 0; j<kc->num_requires; j++)
      GNUNET_free (kc->requires[j]);
    GNUNET_array_grow (kc->requires,
                       kc->num_requires,
                       0);
    GNUNET_free (kc->fallback);
    for (unsigned int j = 0; j<kc->num_outputs; j++)
      GNUNET_free (kc->outputs[j]);
    GNUNET_array_grow (kc->outputs,
                       kc->num_outputs,
                       0);
    switch (kc->type)
    {
    case TALER_KYCLOGIC_CT_INFO:
      break;
    case TALER_KYCLOGIC_CT_FORM:
      GNUNET_free (kc->details.form.name);
      break;
    case TALER_KYCLOGIC_CT_LINK:
      break;
    }
    GNUNET_free (kc);
  }
  GNUNET_array_grow (kyc_checks,
                     num_kyc_checks,
                     0);
  for (unsigned int i = 0; i<num_aml_programs; i++)
  {
    struct TALER_KYCLOGIC_AmlProgram *ap = aml_programs[i];

    GNUNET_free (ap->program_name);
    GNUNET_free (ap->command);
    GNUNET_free (ap->description);
    GNUNET_free (ap->fallback);
    for (unsigned int j = 0; j<ap->num_required_contexts; j++)
      GNUNET_free (ap->required_contexts[j]);
    GNUNET_array_grow (ap->required_contexts,
                       ap->num_required_contexts,
                       0);
    for (unsigned int j = 0; j<ap->num_required_attributes; j++)
      GNUNET_free (ap->required_attributes[j]);
    GNUNET_array_grow (ap->required_attributes,
                       ap->num_required_attributes,
                       0);
    GNUNET_free (ap);
  }
  GNUNET_array_grow (aml_programs,
                     num_aml_programs,
                     0);
  GNUNET_free (cfg_filename);
}


void
TALER_KYCLOGIC_provider_to_logic (
  const struct TALER_KYCLOGIC_KycProvider *provider,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **provider_name)
{
  *plugin = provider->logic;
  *pd = provider->pd;
  *provider_name = provider->provider_name;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_get_original_measure (
  const char *measure_name,
  struct TALER_KYCLOGIC_KycCheckContext *kcc)
{
  const struct TALER_KYCLOGIC_Measure *measure;

  measure = find_measure (&default_rules,
                          measure_name);
  if (NULL == measure)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Default measure `%s' unknown\n",
                measure_name);
    return GNUNET_SYSERR;
  }
  if (0 == strcasecmp (measure->check_name,
                       "SKIP"))
  {
    kcc->check = NULL;
    kcc->prog_name = measure->prog_name;
    kcc->context = measure->context;
    return GNUNET_OK;
  }

  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == strcasecmp (measure->check_name,
                         kyc_checks[i]->check_name))
    {
      kcc->check = kyc_checks[i];
      kcc->prog_name = measure->prog_name;
      kcc->context = measure->context;
      return GNUNET_OK;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Check `%s' unknown (but required by measure %s)\n",
              measure->check_name,
              measure_name);
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_requirements_to_check (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const struct TALER_KYCLOGIC_KycRule *kyc_rule,
  const char *measure_name,
  struct TALER_KYCLOGIC_KycCheckContext *kcc)
{
  bool found = false;
  const struct TALER_KYCLOGIC_Measure *measure = NULL;

  if (NULL == lrs)
    lrs = &default_rules;
  if (NULL == measure_name)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (NULL != kyc_rule)
  {
    for (unsigned int i = 0; i<kyc_rule->num_measures; i++)
    {
      if (0 != strcasecmp (measure_name,
                           kyc_rule->next_measures[i]))
        continue;
      found = true;
      break;
    }
    if (! found)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Measure `%s' not allowed for rule `%s'\n",
                  measure_name,
                  kyc_rule->rule_name);
      return GNUNET_SYSERR;
    }
    if (kyc_rule->verboten)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Rule says operation is categorically is verboten, cannot take measures\n");
      return GNUNET_SYSERR;
    }
  }
  measure = find_measure (lrs,
                          measure_name);
  if (NULL == measure)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Measure `%s' unknown (but allowed by rule `%s')\n",
                measure_name,
                NULL != kyc_rule
                ? kyc_rule->rule_name
                : "<NONE>");
    return GNUNET_SYSERR;
  }

  if (0 == strcasecmp (measure->check_name,
                       "SKIP"))
  {
    kcc->check = NULL;
    kcc->prog_name = measure->prog_name;
    kcc->context = measure->context;
    return GNUNET_OK;
  }

  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == strcasecmp (measure->check_name,
                         kyc_checks[i]->check_name))
    {
      kcc->check = kyc_checks[i];
      kcc->prog_name = measure->prog_name;
      kcc->context = measure->context;
      return GNUNET_OK;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Check `%s' unknown (but required by measure %s)\n",
              measure->check_name,
              measure_name);
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_lookup_logic (
  const char *name,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **provider_name)
{
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    if (0 !=
        strcasecmp (name,
                    kp->provider_name))
      continue;
    *plugin = kp->logic;
    *pd = kp->pd;
    *provider_name = kp->provider_name;
    return GNUNET_OK;
  }
  for (unsigned int i = 0; i<num_kyc_logics; i++)
  {
    struct TALER_KYCLOGIC_Plugin *logic = kyc_logics[i];

    if (0 !=
        strcasecmp (logic->name,
                    name))
      continue;
    *plugin = logic;
    *pd = NULL;
    *provider_name = NULL;
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Provider `%s' unknown\n",
              name);
  return GNUNET_SYSERR;
}


void
TALER_KYCLOGIC_kyc_get_details (
  const char *logic_name,
  TALER_KYCLOGIC_DetailsCallback cb,
  void *cb_cls)
{
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp
      = kyc_providers[i];

    if (0 !=
        strcasecmp (kp->logic->name,
                    logic_name))
      continue;
    if (GNUNET_OK !=
        cb (cb_cls,
            kp->pd,
            kp->logic->cls))
      return;
  }
}


/**
 * Closure for check_amount().
 */
struct KycTestContext
{
  /**
   * Rule set we apply.
   */
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

  /**
   * Events we care about.
   */
  enum TALER_KYCLOGIC_KycTriggerEvent event;

  /**
   * Total amount encountered so far, invalid if zero.
   */
  struct TALER_Amount sum;

  /**
   * Set to the triggered rule.
   */
  const struct TALER_KYCLOGIC_KycRule *triggered_rule;

};


/**
 * Function called on each @a amount that was found to
 * be relevant for a KYC check.  Evaluates the given
 * @a amount and @a date against all the applicable
 * rules in the legitimization rule set.
 *
 * @param cls our `struct KycTestContext *`
 * @param amount encountered transaction amount
 * @param date when was the amount encountered
 * @return #GNUNET_OK to continue to iterate,
 *         #GNUNET_NO to abort iteration,
 *         #GNUNET_SYSERR on internal error (also abort itaration)
 */
static enum GNUNET_GenericReturnValue
check_amount (
  void *cls,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Absolute date)
{
  struct KycTestContext *ktc = cls;
  struct GNUNET_TIME_Relative dur;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC checking transaction amount %s from %s against %u rules\n",
              TALER_amount2s (amount),
              GNUNET_TIME_absolute2s (date),
              ktc->lrs->num_kyc_rules);
  dur = GNUNET_TIME_absolute_get_duration (date);
  if (GNUNET_OK !=
      TALER_amount_is_valid (&ktc->sum))
    ktc->sum = *amount;
  else
    GNUNET_assert (0 <=
                   TALER_amount_add (&ktc->sum,
                                     &ktc->sum,
                                     amount));
  for (unsigned int i=0; i<ktc->lrs->num_kyc_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule
      = &ktc->lrs->kyc_rules[i];

    if (ktc->event != rule->trigger)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Wrong event type (%d) for rule %u (%d)\n",
                  (int) ktc->event,
                  i,
                  (int) rule->trigger);
      continue; /* wrong trigger event type */
    }
    if (GNUNET_TIME_relative_cmp (dur,
                                  >,
                                  rule->timeframe))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Out of time range for rule %u\n",
                  i);
      continue; /* out of time range for rule */
    }
    if (-1 == TALER_amount_cmp (&ktc->sum,
                                &rule->threshold))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Below threshold of %s for rule %u\n",
                  TALER_amount2s (&rule->threshold),
                  i);
      continue; /* sum < threshold */
    }
    if ( (NULL != ktc->triggered_rule) &&
         (1 == TALER_amount_cmp (&ktc->triggered_rule->threshold,
                                 &rule->threshold)) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Higher than threshold of already triggered rule\n");
      continue; /* threshold of triggered_rule > rule */
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Remembering rule %s as triggered\n",
                rule->rule_name);
    ktc->triggered_rule = rule;
  }
  return GNUNET_OK;
}


enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_kyc_test_required (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  const struct TALER_KYCLOGIC_KycRule **triggered_rule,
  struct TALER_Amount *next_threshold)
{
  struct GNUNET_TIME_Relative range
    = GNUNET_TIME_UNIT_ZERO;
  enum GNUNET_DB_QueryStatus qs;
  bool have_threshold = false;

  memset (next_threshold,
          0,
          sizeof (struct TALER_Amount));
  if (NULL == lrs)
    lrs = &default_rules;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Testing %u KYC rules for trigger %d\n",
              lrs->num_kyc_rules,
              event);
  for (unsigned int i=0; i<lrs->num_kyc_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule
      = &lrs->kyc_rules[i];

    if (event != rule->trigger)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Rule %u is for a different trigger (%d/%d)\n",
                  i,
                  (int) event,
                  (int) rule->trigger);
      continue;
    }
    if (have_threshold)
    {
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_max (next_threshold,
                                       next_threshold,
                                       &rule->threshold));
    }
    else
    {
      *next_threshold = rule->threshold;
      have_threshold = true;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Matched rule %u with timeframe %s and threshold %s\n",
                i,
                GNUNET_TIME_relative2s (rule->timeframe,
                                        true),
                TALER_amount2s (&rule->threshold));
    range = GNUNET_TIME_relative_max (range,
                                      rule->timeframe);
  }

  if (! have_threshold)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No rules apply\n");
    *triggered_rule = NULL;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  {
    struct GNUNET_TIME_Absolute now
      = GNUNET_TIME_absolute_get ();
    struct KycTestContext ktc = {
      .lrs = lrs,
      .event = event
    };

    qs = ai (ai_cls,
             GNUNET_TIME_absolute_subtract (now,
                                            range),
             &check_amount,
             &ktc);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Triggered rule is %s\n",
                (NULL == ktc.triggered_rule)
                ? "NONE"
                : ktc.triggered_rule->rule_name);
    *triggered_rule = ktc.triggered_rule;
  }
  return qs;
}


json_t *
TALER_KYCLOGIC_measure_to_requirement (
  const char *check_name,
  const char *prog_name,
  const json_t *context,
  const struct TALER_AccountAccessTokenP *access_token,
  size_t offset,
  uint64_t legitimization_measure_row_id)
{
  struct TALER_KYCLOGIC_KycCheck *kc;
  json_t *kri;
  struct TALER_KycMeasureAuthorizationHash shv;
  char *ids;
  char *xids;

  kc = find_check (check_name);
  if (NULL == kc)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (offset <= UINT32_MAX);
  TALER_kyc_measure_authorization_hash (access_token,
                                        legitimization_measure_row_id,
                                        (uint32_t) offset,
                                        &shv);
  switch (kc->type)
  {
  case TALER_KYCLOGIC_CT_INFO:
    return GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("form",
                               "INFO"),
      GNUNET_JSON_pack_string ("description",
                               kc->description),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("description_i18n",
                                        (json_t *) kc->description_i18n)));
  case TALER_KYCLOGIC_CT_FORM:
    GNUNET_assert (offset <= UINT_MAX);
    ids = GNUNET_STRINGS_data_to_string_alloc (&shv,
                                               sizeof (shv));
    GNUNET_asprintf (&xids,
                     "%s-%u-%llu",
                     ids,
                     (unsigned int) offset,
                     (unsigned long long) legitimization_measure_row_id);
    GNUNET_free (ids);
    kri = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("form",
                               kc->details.form.name),
      GNUNET_JSON_pack_string ("id",
                               xids),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("context",
                                        (json_t *) context)),
      GNUNET_JSON_pack_string ("description",
                               kc->description),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("description_i18n",
                                        (json_t *) kc->description_i18n)));
    GNUNET_free (xids);
    return kri;
  case TALER_KYCLOGIC_CT_LINK:
    GNUNET_assert (offset <= UINT_MAX);
    ids = GNUNET_STRINGS_data_to_string_alloc (&shv,
                                               sizeof (shv));
    GNUNET_asprintf (&xids,
                     "%s-%u-%llu",
                     ids,
                     (unsigned int) offset,
                     (unsigned long long) legitimization_measure_row_id);
    GNUNET_free (ids);
    kri = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("form",
                               "LINK"),
      GNUNET_JSON_pack_string ("id",
                               xids),
      GNUNET_JSON_pack_string ("description",
                               kc->description),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("description_i18n",
                                        (json_t *) kc->description_i18n)));
    GNUNET_free (xids);
    return kri;
  }
  GNUNET_break (0); /* invalid type */
  return NULL;
}


void
TALER_KYCLOGIC_get_measure_configuration (
  json_t **proots,
  json_t **pprograms,
  json_t **pchecks)
{
  json_t *roots;
  json_t *programs;
  json_t *checks;

  roots = json_object ();
  for (unsigned int i = 0; i<default_rules.num_custom_measures; i++)
  {
    const struct TALER_KYCLOGIC_Measure *m
      = &default_rules.custom_measures[i];
    json_t *jm;

    jm = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("check_name",
                               m->check_name),
      GNUNET_JSON_pack_string ("prog_name",
                               m->prog_name),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("context",
                                        m->context)));
    GNUNET_assert (0 ==
                   json_object_set_new (roots,
                                        m->measure_name,
                                        jm));
  }

  programs = json_object ();
  for (unsigned int i = 0; i<num_aml_programs; i++)
  {
    const struct TALER_KYCLOGIC_AmlProgram *ap
      = aml_programs[i];
    json_t *jp;
    json_t *ctx;
    json_t *inp;

    ctx = json_array ();
    GNUNET_assert (NULL != ctx);
    for (unsigned int j = 0; j<ap->num_required_contexts; j++)
    {
      const char *rc = ap->required_contexts[j];

      GNUNET_assert (0 ==
                     json_array_append_new (ctx,
                                            json_string (rc)));
    }
    inp = json_array ();
    GNUNET_assert (NULL != inp);
    for (unsigned int j = 0; j<ap->num_required_attributes; j++)
    {
      const char *ra = ap->required_attributes[j];

      GNUNET_assert (0 ==
                     json_array_append_new (inp,
                                            json_string (ra)));
    }

    jp = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("description",
                               ap->description),
      GNUNET_JSON_pack_array_steal ("context",
                                    ctx),
      GNUNET_JSON_pack_array_steal ("inputs",
                                    inp));
    GNUNET_assert (0 ==
                   json_object_set_new (programs,
                                        ap->program_name,
                                        jp));
  }

  checks = json_object ();
  for (unsigned int i = 0; i<num_kyc_checks; i++)
  {
    const struct TALER_KYCLOGIC_KycCheck *ck
      = kyc_checks[i];
    json_t *jc;
    json_t *requires;
    json_t *outputs;

    requires = json_array ();
    GNUNET_assert (NULL != requires);
    for (unsigned int j = 0; j<ck->num_requires; j++)
    {
      const char *ra = ck->requires[j];

      GNUNET_assert (0 ==
                     json_array_append_new (requires,
                                            json_string (ra)));
    }
    outputs = json_array ();
    GNUNET_assert (NULL != outputs);
    for (unsigned int j = 0; j<ck->num_outputs; j++)
    {
      const char *out = ck->outputs[j];

      GNUNET_assert (0 ==
                     json_array_append_new (outputs,
                                            json_string (out)));
    }

    jc = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("description",
                               ck->description),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("description_i18n",
                                        ck->description_i18n)),
      GNUNET_JSON_pack_array_steal ("requires",
                                    requires),
      GNUNET_JSON_pack_array_steal ("outputs",
                                    outputs),
      GNUNET_JSON_pack_string ("fallback",
                               ck->fallback));
    GNUNET_assert (0 ==
                   json_object_set_new (checks,
                                        ck->check_name,
                                        jc));
  }

  *proots = roots;
  *pprograms = programs;
  *pchecks = checks;
}


enum TALER_ErrorCode
TALER_KYCLOGIC_select_measure (
  const json_t *jmeasures,
  size_t measure_index,
  const char **check_name,
  const char **prog_name,
  const json_t **context)
{
  const json_t *jmeasure_arr;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("measures",
                                  &jmeasure_arr),
    GNUNET_JSON_spec_end ()
  };
  const json_t *jmeasure;
  struct GNUNET_JSON_Specification ispec[] = {
    GNUNET_JSON_spec_string ("check_name",
                             check_name),
    GNUNET_JSON_spec_string ("prog_name",
                             prog_name),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("context",
                                     context),
      NULL),
    GNUNET_JSON_spec_end ()
  };

  *check_name = NULL;
  *prog_name = NULL;
  *context = NULL;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (jmeasures,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break (0);
    return TALER_EC_EXCHANGE_KYC_MEASURES_MALFORMED;
  }
  if (measure_index >= json_array_size (jmeasure_arr))
  {
    GNUNET_break_op (0);
    return TALER_EC_EXCHANGE_KYC_MEASURE_INDEX_INVALID;
  }
  jmeasure = json_array_get (jmeasure_arr,
                             measure_index);
  if (GNUNET_OK !=
      GNUNET_JSON_parse (jmeasure,
                         ispec,
                         NULL, NULL))
  {
    GNUNET_break (0);
    return TALER_EC_EXCHANGE_KYC_MEASURES_MALFORMED;
  }
  return TALER_EC_NONE;
}


enum TALER_ErrorCode
TALER_KYCLOGIC_check_form (
  const json_t *jmeasures,
  size_t measure_index,
  const json_t *form_data,
  const char **error_message)
{
  const char *check_name;
  const char *prog_name;
  const json_t *context;
  struct TALER_KYCLOGIC_KycCheck *kc;
  struct TALER_KYCLOGIC_AmlProgram *prog;

  *error_message = NULL;
  if (TALER_EC_NONE !=
      TALER_KYCLOGIC_select_measure (jmeasures,
                                     measure_index,
                                     &check_name,
                                     &prog_name,
                                     &context))
  {
    GNUNET_break_op (0);
    return TALER_EC_EXCHANGE_KYC_MEASURE_INDEX_INVALID;
  }
  kc = find_check (check_name);
  if (NULL == kc)
  {
    GNUNET_break (0);
    *error_message = check_name;
    return TALER_EC_EXCHANGE_KYC_GENERIC_CHECK_GONE;
  }
  if (TALER_KYCLOGIC_CT_FORM != kc->type)
  {
    GNUNET_break_op (0);
    return TALER_EC_EXCHANGE_KYC_NOT_A_FORM;
  }
  prog = find_program (prog_name);
  if (NULL == prog)
  {
    GNUNET_break (0);
    *error_message = prog_name;
    return TALER_EC_EXCHANGE_KYC_GENERIC_AML_PROGRAM_GONE;
  }
  for (unsigned int i = 0; i<prog->num_required_attributes; i++)
  {
    const char *rattr = prog->required_attributes[i];

    if (NULL == json_object_get (form_data,
                                 rattr))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Form data lacks required attribute `%s' for AML program %s\n",
                  rattr,
                  prog_name);
      *error_message = rattr;
      return TALER_EC_EXCHANGE_KYC_AML_FORM_INCOMPLETE;
    }
  }
  return TALER_EC_NONE;
}


const char *
TALER_KYCLOGIC_get_aml_program_fallback (const char *prog_name)
{
  struct TALER_KYCLOGIC_AmlProgram *prog;

  prog = find_program (prog_name);
  if (NULL == prog)
  {
    GNUNET_break (0);
    return NULL;
  }
  return prog->fallback;
}


const struct TALER_KYCLOGIC_KycProvider *
TALER_KYCLOGIC_check_to_provider (const char *check_name)
{
  struct TALER_KYCLOGIC_KycCheck *kc;

  if (NULL == check_name)
    return NULL;
  if (0 == strcasecmp (check_name,
                       "SKIP"))
    return NULL;
  kc = find_check (check_name);
  switch (kc->type)
  {
  case TALER_KYCLOGIC_CT_FORM:
  case TALER_KYCLOGIC_CT_INFO:
    return NULL;
  case TALER_KYCLOGIC_CT_LINK:
    break;
  }
  return kc->details.link.provider;
}


struct TALER_KYCLOGIC_AmlProgramRunnerHandle
{
  /**
   * Function to call back with the result.
   */
  TALER_KYCLOGIC_AmlProgramResultCallback aprc;

  /**
   * Closure for @e aprc.
   */
  void *aprc_cls;

  /**
   * Handle to an external process.
   */
  struct TALER_JSON_ExternalConversion *proc;

  /**
   * AML program to turn.
   */
  const struct TALER_KYCLOGIC_AmlProgram *program;

  /**
   * Task to return @e apr result asynchronously.
   */
  struct GNUNET_SCHEDULER_Task *async_cb;

  /**
   * Result returned to the client.
   */
  struct TALER_KYCLOGIC_AmlProgramResult apr;

  /**
   * How long do we allow the AML program to run?
   */
  struct GNUNET_TIME_Relative timeout;

};


/**
 * Function that that receives a JSON @a result from
 * the AML program.
 *
 * @param cls closure of type `struct TALER_KYCLOGIC_AmlProgramRunnerHandle`
 * @param status_type how did the process die
 * @param code termination status code from the process,
 *        non-zero if AML checks are required next
 * @param result some JSON result, NULL if we failed to get an JSON output
 */
static void
handle_aml_output (
  void *cls,
  enum GNUNET_OS_ProcessStatusType status_type,
  unsigned long code,
  const json_t *result)
{
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh = cls;
  const char *fallback_measure = aprh->program->fallback;
  struct TALER_KYCLOGIC_AmlProgramResult *apr = &aprh->apr;
  const char **evs = NULL;

  aprh->proc = NULL;
  if (NULL != aprh->async_cb)
  {
    GNUNET_SCHEDULER_cancel (aprh->async_cb);
    aprh->async_cb = NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "AML program output is:\n");
  json_dumpf (result,
              stderr,
              JSON_INDENT (2));
  memset (apr,
          0,
          sizeof (*apr));
  if ( (GNUNET_OS_PROCESS_EXITED != status_type) ||
       (0 != code) )
  {
    apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
    apr->details.failure.fallback_measure
      = fallback_measure;
    apr->details.failure.error_message
      = "AML program returned non-zero exit code";
    apr->details.failure.ec
      = TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE;
    goto ready;
  }

  {
    const json_t *jevents = NULL;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_bool (
          "to_investigate",
          &apr->details.success.to_investigate),
        NULL),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_object_const (
          "properties",
          &apr->details.success.account_properties),
        NULL),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_array_const (
          "events",
          &jevents),
        NULL),
      GNUNET_JSON_spec_object_const (
        "new_rules",
        &apr->details.success.new_rules),
      GNUNET_JSON_spec_end ()
    };
    const char *err;
    unsigned int line;

    if (GNUNET_OK !=
        GNUNET_JSON_parse (result,
                           spec,
                           &err,
                           &line))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "AML program output is malformed at `%s'\n",
                  err);
      json_dumpf (result,
                  stderr,
                  JSON_INDENT (2));
      apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
      apr->details.failure.fallback_measure
        = fallback_measure;
      apr->details.failure.error_message
        = err;
      apr->details.failure.ec
        = TALER_EC_EXCHANGE_KYC_AML_PROGRAM_MALFORMED_RESULT;
      goto ready;
    }
    apr->details.success.num_events
      = json_array_size (jevents);

    GNUNET_assert (((size_t) apr->details.success.num_events) ==
                   json_array_size (jevents));
    evs = GNUNET_new_array (
      apr->details.success.num_events,
      const char *);
    for (unsigned int i = 0; i<apr->details.success.num_events; i++)
    {
      evs[i] = json_string_value (
        json_array_get (jevents,
                        i));
      if (NULL == evs[i])
      {
        apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
        apr->details.failure.fallback_measure
          = fallback_measure;
        apr->details.failure.error_message
          = "events";
        apr->details.failure.ec
          = TALER_EC_EXCHANGE_KYC_AML_PROGRAM_MALFORMED_RESULT;
        goto ready;
      }
    }
    apr->status = TALER_KYCLOGIC_AMLR_SUCCESS;
    apr->details.success.events = evs;
    {
      /* check new_rules */
      struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

      lrs = TALER_KYCLOGIC_rules_parse (
        apr->details.success.new_rules);
      if (NULL == lrs)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "AML program output is malformed at `%s'\n",
                    "new_rules");

        apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
        apr->details.failure.fallback_measure
          = fallback_measure;
        apr->details.failure.error_message
          = "new_rules";
        apr->details.failure.ec
          = TALER_EC_EXCHANGE_KYC_AML_PROGRAM_MALFORMED_RESULT;
        goto ready;
      }
      apr->details.success.expiration_time
        = lrs->expiration_time;
      TALER_KYCLOGIC_rules_free (lrs);
    }
  }
ready:
  aprh->aprc (aprh->aprc_cls,
              &aprh->apr);
  GNUNET_free (evs);
  TALER_KYCLOGIC_run_aml_program_cancel (aprh);
}


/**
 * Helper function to asynchronously return the result.
 *
 * @param[in] cls a `struct TALER_KYCLOGIC_AmlProgramRunnerHandle` to return results for
 */
static void
async_return_task (void *cls)
{
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh = cls;

  aprh->async_cb = NULL;
  aprh->aprc (aprh->aprc_cls,
              &aprh->apr);
  TALER_KYCLOGIC_run_aml_program_cancel (aprh);
}


/**
 * Helper function called on timeout on the fallback measure.
 *
 * @param[in] cls a `struct TALER_KYCLOGIC_AmlProgramRunnerHandle` to return results for
 */
static void
handle_aml_timeout2 (void *cls)
{
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh = cls;
  struct TALER_KYCLOGIC_AmlProgramResult *apr = &aprh->apr;
  const char *fallback_measure = aprh->program->fallback;

  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Fallback measure %s ran into timeout (!)\n",
              aprh->program->program_name);
  if (NULL != aprh->proc)
  {
    TALER_JSON_external_conversion_stop (aprh->proc);
    aprh->proc = NULL;
  }
  apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
  apr->details.failure.fallback_measure
    = fallback_measure;
  apr->details.failure.error_message
    = aprh->program->program_name;
  apr->details.failure.ec
    = TALER_EC_EXCHANGE_KYC_GENERIC_AML_PROGRAM_TIMEOUT;
  async_return_task (aprh);
}


/**
 * Helper function called on timeout of an AML program.
 * Runs the fallback measure.
 *
 * @param[in] cls a `struct TALER_KYCLOGIC_AmlProgramRunnerHandle` to return results for
 */
static void
handle_aml_timeout (void *cls)
{
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh = cls;
  struct TALER_KYCLOGIC_AmlProgramResult *apr = &aprh->apr;
  const char *fallback_measure = aprh->program->fallback;
  const struct TALER_KYCLOGIC_Measure *m;
  const struct TALER_KYCLOGIC_AmlProgram *fprogram;

  aprh->async_cb = NULL;
  GNUNET_assert (NULL != fallback_measure);
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "AML program %s ran into timeout\n",
              aprh->program->program_name);
  if (NULL != aprh->proc)
  {
    TALER_JSON_external_conversion_stop (aprh->proc);
    aprh->proc = NULL;
  }

  m = TALER_KYCLOGIC_get_measure (&default_rules,
                                  fallback_measure);
  /* Fallback program could have "disappeared" due to configuration change,
     as we do not check all rule sets in the database when our configuration
     is updated... */
  if (NULL == m)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fallback measure `%s' does not exist (anymore?).\n",
                fallback_measure);
    apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
    apr->details.failure.fallback_measure
      = fallback_measure;
    apr->details.failure.error_message
      = aprh->program->program_name;
    apr->details.failure.ec
      = TALER_EC_EXCHANGE_KYC_GENERIC_AML_PROGRAM_TIMEOUT;
    async_return_task (aprh);
    return;
  }
  /* We require fallback measures to have a 'SKIP' check */
  GNUNET_break (0 ==
                strcasecmp (m->check_name,
                            "SKIP"));
  fprogram = find_program (m->prog_name);
  /* Program associated with an original measure must exist */
  GNUNET_assert (NULL != fprogram);
  if (API_NONE != fprogram->input_mask)
  {
    /* We might not have recognized the fallback measure as such
       because it was not used as such in the plain configuration,
       and legitimization rule sets might have referred to an older
       configuration. So this should be super-rare but possible. */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Program `%s' used in fallback measure `%s' requires inputs and is thus unsuitable as a fallback measure!\n",
                m->prog_name,
                fallback_measure);
    apr->status = TALER_KYCLOGIC_AMLR_FAILURE;
    apr->details.failure.fallback_measure
      = fallback_measure;
    apr->details.failure.error_message
      = aprh->program->program_name;
    apr->details.failure.ec
      = TALER_EC_EXCHANGE_KYC_GENERIC_AML_PROGRAM_TIMEOUT;
    async_return_task (aprh);
    return;
  }
  {
    /* Run fallback AML program */
    json_t *input = json_object ();
    const char *extra_args[] = {
      "-c",
      cfg_filename,
      NULL,
    };
    char **args;

    args = split_words (fprogram->command,
                        extra_args);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Running fallback measure `%s' (%s)\n",
                fallback_measure,
                fprogram->command);
    aprh->proc = TALER_JSON_external_conversion_start (
      input,
      &handle_aml_output,
      aprh,
      args[0],
      (const char **) args);
    destroy_words (args);
    json_decref (input);
  }
  aprh->async_cb = GNUNET_SCHEDULER_add_delayed (aprh->timeout,
                                                 &handle_aml_timeout2,
                                                 aprh);
}


struct TALER_KYCLOGIC_AmlProgramRunnerHandle *
TALER_KYCLOGIC_run_aml_program (
  const json_t *jmeasures,
  unsigned int measure_index,
  TALER_KYCLOGIC_HistoryBuilderCallback current_attributes_cb,
  void *current_attributes_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback current_rules_cb,
  void *current_rules_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback aml_history_cb,
  void *aml_history_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback kyc_history_cb,
  void *kyc_history_cb_cls,
  struct GNUNET_TIME_Relative timeout,
  TALER_KYCLOGIC_AmlProgramResultCallback aprc,
  void *aprc_cls)
{
  const json_t *context;
  const char *check_name;
  const char *prog_name;

  {
    enum TALER_ErrorCode ec;

    ec = TALER_KYCLOGIC_select_measure (jmeasures,
                                        measure_index,
                                        &check_name,
                                        &prog_name,
                                        &context);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      return NULL;
    }
  }
  return TALER_KYCLOGIC_run_aml_program2 (prog_name,
                                          context,
                                          current_attributes_cb,
                                          current_attributes_cb_cls,
                                          current_rules_cb,
                                          current_rules_cb_cls,
                                          aml_history_cb,
                                          aml_history_cb_cls,
                                          kyc_history_cb,
                                          kyc_history_cb_cls,
                                          timeout,
                                          aprc,
                                          aprc_cls);
}


struct TALER_KYCLOGIC_AmlProgramRunnerHandle *
TALER_KYCLOGIC_run_aml_program2 (
  const char *prog_name,
  const json_t *context,
  TALER_KYCLOGIC_HistoryBuilderCallback current_attributes_cb,
  void *current_attributes_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback current_rules_cb,
  void *current_rules_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback aml_history_cb,
  void *aml_history_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback kyc_history_cb,
  void *kyc_history_cb_cls,
  struct GNUNET_TIME_Relative timeout,
  TALER_KYCLOGIC_AmlProgramResultCallback aprc,
  void *aprc_cls)
{
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh;
  struct TALER_KYCLOGIC_AmlProgram *prog;
  const json_t *jdefault_rules;
  json_t *current_rules;
  json_t *aml_history;
  json_t *kyc_history;
  json_t *attributes;

  prog = find_program (prog_name);
  if (NULL == prog)
  {
    GNUNET_break (0);
    return NULL;
  }
  aprh = GNUNET_new (struct TALER_KYCLOGIC_AmlProgramRunnerHandle);
  aprh->aprc = aprc;
  aprh->aprc_cls = aprc_cls;
  aprh->program = prog;
  if (0 != (API_ATTRIBUTES & prog->input_mask))
  {
    attributes = current_attributes_cb (current_attributes_cb_cls);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC attributes for AML program %s are:\n",
                prog_name);
    json_dumpf (attributes,
                stderr,
                JSON_INDENT (2));
    fprintf (stderr,
             "\n");
    for (unsigned int i = 0; i<prog->num_required_attributes; i++)
    {
      const char *rattr = prog->required_attributes[i];

      if (NULL == json_object_get (attributes,
                                   rattr))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "KYC attributes lack required attribute `%s' for AML program %s\n",
                    rattr,
                    prog->program_name);
        json_dumpf (attributes,
                    stderr,
                    JSON_INDENT (2));
        aprh->apr.status = TALER_KYCLOGIC_AMLR_FAILURE;
        aprh->apr.details.failure.fallback_measure
          = prog->fallback;
        aprh->apr.details.failure.error_message
          = rattr;
        aprh->apr.details.failure.ec
          = TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_INCOMPLETE_REPLY;
        aprh->async_cb
          = GNUNET_SCHEDULER_add_now (&async_return_task,
                                      aprh);
        return aprh;
      }
    }
  }
  else
  {
    attributes = NULL;
  }
  if (0 != (API_CONTEXT & prog->input_mask))
  {
    for (unsigned int i = 0; i<prog->num_required_contexts; i++)
    {
      const char *rctx = prog->required_contexts[i];

      if (NULL == json_object_get (context,
                                   rctx))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Context lacks required field `%s' for AML program %s\n",
                    rctx,
                    prog->program_name);
        json_dumpf (context,
                    stderr,
                    JSON_INDENT (2));
        aprh->apr.status = TALER_KYCLOGIC_AMLR_FAILURE;
        aprh->apr.details.failure.fallback_measure
          = prog->fallback;
        aprh->apr.details.failure.error_message
          = rctx;
        aprh->apr.details.failure.ec
          = TALER_EC_EXCHANGE_KYC_GENERIC_PROVIDER_INCOMPLETE_CONTEXT;
        aprh->async_cb
          = GNUNET_SCHEDULER_add_now (&async_return_task,
                                      aprh);
        return aprh;
      }
    }
  }
  else
  {
    context = NULL;
  }
  if (0 == (API_AML_HISTORY & prog->input_mask))
    aml_history = NULL;
  else
    aml_history = aml_history_cb (aml_history_cb_cls);
  if (0 == (API_KYC_HISTORY & prog->input_mask))
    kyc_history = NULL;
  else
    kyc_history = kyc_history_cb (kyc_history_cb_cls);
  if (0 == (API_CURRENT_RULES & prog->input_mask))
    current_rules = NULL;
  else
    current_rules = current_rules_cb (current_rules_cb_cls);
  if (0 != (API_DEFAULT_RULES & prog->input_mask))
    jdefault_rules = default_rules.jlrs;
  else
    jdefault_rules = NULL;
  {
    json_t *input;
    const char *extra_args[] = {
      "-c",
      cfg_filename,
      NULL,
    };
    char **args;

    input = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_steal ("current_rules",
                                       current_rules)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("default_rules",
                                        (json_t *) jdefault_rules)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("context",
                                        (json_t *) context)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_object_incref ("attributes",
                                        (json_t *) attributes)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_array_steal ("aml_history",
                                      aml_history)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_array_steal ("kyc_history",
                                      kyc_history))
      );
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Running AML program %s\n",
                prog->command);
    args = split_words (prog->command,
                        extra_args);
    GNUNET_assert (NULL != args);
    GNUNET_assert (NULL != args[0]);
    json_dumpf (input,
                stderr,
                JSON_INDENT (2));
    aprh->proc = TALER_JSON_external_conversion_start (
      input,
      &handle_aml_output,
      aprh,
      args[0],
      (const char **) args);
    destroy_words (args);
    json_decref (input);
  }
  aprh->timeout = timeout;
  aprh->async_cb = GNUNET_SCHEDULER_add_delayed (timeout,
                                                 &handle_aml_timeout,
                                                 aprh);
  return aprh;
}


struct TALER_KYCLOGIC_AmlProgramRunnerHandle *
TALER_KYCLOGIC_run_aml_program3 (
  const struct TALER_KYCLOGIC_Measure *measure,
  TALER_KYCLOGIC_HistoryBuilderCallback current_attributes_cb,
  void *current_attributes_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback current_rules_cb,
  void *current_rules_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback aml_history_cb,
  void *aml_history_cb_cls,
  TALER_KYCLOGIC_HistoryBuilderCallback kyc_history_cb,
  void *kyc_history_cb_cls,
  struct GNUNET_TIME_Relative timeout,
  TALER_KYCLOGIC_AmlProgramResultCallback aprc,
  void *aprc_cls)
{
  return TALER_KYCLOGIC_run_aml_program2 (
    measure->prog_name,
    measure->context,
    current_attributes_cb,
    current_attributes_cb_cls,
    current_rules_cb,
    current_rules_cb_cls,
    aml_history_cb,
    aml_history_cb_cls,
    kyc_history_cb,
    kyc_history_cb_cls,
    timeout,
    aprc,
    aprc_cls);
}


const char *
TALER_KYCLOGIC_run_aml_program_get_name (
  const struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh)
{
  return aprh->program->program_name;
}


void
TALER_KYCLOGIC_run_aml_program_cancel (
  struct TALER_KYCLOGIC_AmlProgramRunnerHandle *aprh)
{
  if (NULL != aprh->proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Killing AML program\n");
    TALER_JSON_external_conversion_stop (aprh->proc);
    aprh->proc = NULL;
  }
  if (NULL != aprh->async_cb)
  {
    GNUNET_SCHEDULER_cancel (aprh->async_cb);
    aprh->async_cb = NULL;
  }
  GNUNET_free (aprh);
}


json_t *
TALER_KYCLOGIC_get_hard_limits ()
{
  const struct TALER_KYCLOGIC_KycRule *rules
    = default_rules.kyc_rules;
  unsigned int num_rules
    = default_rules.num_kyc_rules;
  json_t *hard_limits;

  hard_limits = json_array ();
  GNUNET_assert (NULL != hard_limits);
  for (unsigned int i = 0; i<num_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule = &rules[i];
    json_t *hard_limit;

    if (! rule->verboten)
      continue;
    if (! rule->exposed)
      continue;
    hard_limit = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("rule_name",
                                 rule->rule_name)),
      TALER_JSON_pack_kycte ("operation_type",
                             rule->trigger),
      GNUNET_JSON_pack_time_rel ("timeframe",
                                 rule->timeframe),
      TALER_JSON_pack_amount ("threshold",
                              &rule->threshold)
      );
    GNUNET_assert (0 ==
                   json_array_append_new (hard_limits,
                                          hard_limit));
  }
  return hard_limits;
}


json_t *
TALER_KYCLOGIC_get_zero_limits ()
{
  const struct TALER_KYCLOGIC_KycRule *rules
    = default_rules.kyc_rules;
  unsigned int num_rules
    = default_rules.num_kyc_rules;
  json_t *zero_limits;

  zero_limits = json_array ();
  GNUNET_assert (NULL != zero_limits);
  for (unsigned int i = 0; i<num_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule = &rules[i];
    json_t *zero_limit;

    if (! rule->exposed)
      continue;
    if (rule->verboten)
      continue; /* see: hard_limits */
    if (! TALER_amount_is_zero (&rule->threshold))
      continue;
    zero_limit = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("rule_name",
                                 rule->rule_name)),
      TALER_JSON_pack_kycte ("operation_type",
                             rule->trigger));
    GNUNET_assert (0 ==
                   json_array_append_new (zero_limits,
                                          zero_limit));
  }
  return zero_limits;
}


const json_t *
TALER_KYCLOGIC_get_default_legi_rules ()
{
  return default_rules.jlrs;
}


/* end of kyclogic_api.c */
