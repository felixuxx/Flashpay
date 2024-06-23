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
 * Name of the KYC check that may never be passed. Useful if some
 * operations/amounts are categorically forbidden.
 */
#define KYC_CHECK_IMPOSSIBLE "verboten"

/**
 * Information about a KYC provider.
 */
struct TALER_KYCLOGIC_KycProvider
{

  /**
   * Cost of running this provider's KYC process.
   */
  struct TALER_Amount cost;

  /**
   * Name of the provider.
   */
  char *provider_name;

  /**
   * Name of a program to run to convert output of the
   * plugin into the desired set of attributes.
   */
  char *converter_name;

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
   * NULL for default rules.
   */
  char *successor_measure;

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
   * @e command fails.
   */
  char *fallback;

  /**
   * Output of @e command "--required-context".
   */
  char **required_contexts;

  /**
   * Length of the @e required_contexts array.
   */
  unsigned int num_required_contexts;

  /**
   * Output of @e command "--required-attributes".
   */
  char **required_attributes;

  /**
   * Length of the @e required_attributes array.
   */
  unsigned int num_required_attributes;
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


struct GNUNET_TIME_Timestamp
TALER_KYCLOGIC_rules_get_expiration (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs)
{
  return lrs->expiration_time;
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

    if (0 == strcmp (check_name,
                     kyc_check->check_name))
      return kyc_check;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Check `%s' unknown\n",
              check_name);
  return NULL;
}


struct TALER_KYCLOGIC_LegitimizationRuleSet *
TALER_KYCLOGIC_rules_parse (const json_t *jlrs)
{
  struct GNUNET_TIME_Timestamp expiration_time;
  const char *successor_measure = NULL;
  const json_t *jrules;
  const json_t *jcustom_measures = NULL;
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
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("custom_measures",
                                     &jcustom_measures),
      NULL),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (jrules,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
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
      const char *operation_type;
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("operation_type",
                                 &operation_type),
        TALER_JSON_spec_amount_any ("threshold",
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
      if (GNUNET_OK !=
          TALER_KYCLOGIC_kyc_trigger_from_string (
            operation_type,
            &rule->trigger))
      {
        GNUNET_break_op (0);
        goto cleanup;
      }
      rule->lrs = lrs;
      rule->num_measures = json_array_size (jmeasures);
      if (((size_t) rule->num_measures) !=
          json_object_size (jmeasures))
      {
        GNUNET_break (0);
        goto cleanup;
      }
      rule->next_measures
        = GNUNET_new_array (rule->num_measures,
                            char *);
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
          rule->next_measures[j] = GNUNET_strdup (str);
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
      struct TALER_KYCLOGIC_Measure *measure
        = &lrs->custom_measures[off++];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_string ("check_name",
                                 &check_name),
        GNUNET_JSON_spec_string ("prog_name",
                                 &prog_name),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_array_const ("context",
                                        &context),
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
      if (NULL != context)
        measure->context
          = json_incref ((json_t*) context);
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
  for (unsigned int i = 0; i<lrs->num_kyc_rules; i++)
  {
    struct TALER_KYCLOGIC_KycRule *rule
      = &lrs->kyc_rules[i];

    for (unsigned int j = 0; i<rule->num_measures; j++)
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
  GNUNET_free (lrs->custom_measures);
  GNUNET_free (lrs->successor_measure);
  GNUNET_free (lrs);
}


const char *
TALER_KYCLOGIC_rule2s (const struct TALER_KYCLOGIC_KycRule *r)
{
  return r->rule_name;
}


json_t *
TALER_KYCLOGIC_rules_to_limits (const json_t *jrules)
{
  json_t *limits;
  json_t *limit;
  json_t *rule;
  size_t idx;

  limits = json_array ();
  GNUNET_assert (NULL != limits);
  json_array_foreach ((json_t *) jrules, idx, rule)
  {
    const char *ots;
    struct GNUNET_TIME_Relative timeframe;
    struct TALER_Amount threshold;
    bool exposed = false;
    const json_t *jmeasures;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("operation_type",
                               &ots),
      GNUNET_JSON_spec_relative_time ("timeframe",
                                      &timeframe),
      TALER_JSON_spec_amount_any ("threshold",
                                  &threshold),
      GNUNET_JSON_spec_array_const ("measures",
                                    &jmeasures),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_bool ("exposed",
                               &exposed),
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
      if (0 == strcmp (KYC_CHECK_IMPOSSIBLE,
                       val))
        forbidden = true;
    }

    limit = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("operation_type",
                               ots),
      GNUNET_JSON_pack_time_rel ("timeframe",
                                 timeframe),
      TALER_JSON_pack_amount ("threshold",
                              &threshold),
      GNUNET_JSON_pack_bool ("soft_limit",
                             ! forbidden));
  }
  GNUNET_assert (0 ==
                 json_array_append_new (limits,
                                        limit));
  return limits;
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
find_measure (const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
              const char *measure_name)
{
  if (NULL != lrs)
  {
    for (unsigned int i = 0; i<lrs->num_custom_measures; i++)
    {
      const struct TALER_KYCLOGIC_Measure *cm
        = &lrs->custom_measures[i];

      if (0 == strcmp (measure_name,
                       cm->measure_name))
        return cm;
    }
  }
  /* Try measures from default rules */
  for (unsigned int i = 0; i<default_rules.num_custom_measures; i++)
  {
    const struct TALER_KYCLOGIC_Measure *cm
      = &default_rules.custom_measures[i];

    if (0 == strcmp (measure_name,
                     cm->measure_name))
      return cm;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Measure `%s' not found\n",
              measure_name);
  return NULL;
}


json_t *
TALER_KYCLOGIC_rule_to_measures (const struct TALER_KYCLOGIC_KycRule *r)
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


uint32_t
TALER_KYCLOGIC_rule2priority (const struct TALER_KYCLOGIC_KycRule *r)
{
  return r->display_priority;
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
    GNUNET_break (0 ==
                  close (sout[0]));
    GNUNET_break (0 ==
                  close (STDOUT_FILENO));
    GNUNET_assert (STDOUT_FILENO ==
                   dup2 (sout[1],
                         STDOUT_FILENO));
    GNUNET_break (0 ==
                  close (sout[1]));
    execlp (command,
            command,
            argument,
            NULL);
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
  struct
  {
    const char *in;
    enum TALER_KYCLOGIC_KycTriggerEvent out;
  } map [] = {
    { "withdraw", TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW },
    { "age-withdraw", TALER_KYCLOGIC_KYC_TRIGGER_AGE_WITHDRAW },
    { "deposit", TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT  },
    { "merge", TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE },
    { "balance", TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE },
    { "close", TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE },
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


const char *
TALER_KYCLOGIC_kyc_trigger2s (
  enum TALER_KYCLOGIC_KycTriggerEvent trigger)
{
  switch (trigger)
  {
  case TALER_KYCLOGIC_KYC_TRIGGER_NONE:
    GNUNET_break (0);
    return NULL;
  case TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW:
    return "withdraw";
  case TALER_KYCLOGIC_KYC_TRIGGER_AGE_WITHDRAW:
    return "age-withdraw";
  case TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT:
    return "deposit";
  case TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE:
    return "merge";
  case TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE:
    return "balance";
  case TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE:
    return "close";
  }
  GNUNET_break (0);
  return NULL;
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
    if (0 == strcmp (lib_name,
                     kyc_logics[i]->library_name))
    {
      GNUNET_free (lib_name);
      return kyc_logics[i];
    }
  plugin = GNUNET_PLUGIN_load (lib_name,
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
  struct TALER_Amount cost;
  char *logic;
  char *converter;
  struct TALER_KYCLOGIC_Plugin *lp;
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               section,
                               "COST",
                               &cost))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COST",
                               "amount required");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "CONVERTER",
                                             &converter))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "CONVERTER");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "LOGIC",
                                             &logic))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "LOGIC");
    GNUNET_free (converter);
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
    GNUNET_free (converter);
    return GNUNET_SYSERR;
  }
  GNUNET_free (logic);
  pd = lp->load_configuration (lp->cls,
                               section);
  if (NULL == pd)
  {
    GNUNET_free (converter);
    return GNUNET_SYSERR;
  }

  {
    struct TALER_KYCLOGIC_KycProvider *kp;

    kp = GNUNET_new (struct TALER_KYCLOGIC_KycProvider);
    kp->cost = cost;
    kp->provider_name
      = GNUNET_strdup (&section[strlen ("kyc-provider-")]);
    kp->converter_name = converter;
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
 * @param[out] num_p_strs set to length of @a p_strs array
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
  bool voluntary;
  enum TALER_KYCLOGIC_CheckType ct;
  char *form_name = NULL;
  char *description = NULL;
  json_t *description_i18n = NULL;
  char *requires = NULL;
  char *outputs = NULL;
  char *fallback = NULL;

  voluntary = (GNUNET_YES ==
               GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                                     section,
                                                     "VOLUNTARY"));

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
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "DESCRIPTION",
                               "description required");
    goto fail;
  }

  {
    char *tmp;

    if (GNUNET_OK !=
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
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FALLBACK",
                               "fallback measure required");
    goto fail;
  }

  {
    struct TALER_KYCLOGIC_KycCheck *kc;

    kc = GNUNET_new (struct TALER_KYCLOGIC_KycCheck);
    kc->check_name = GNUNET_strdup (&section[strlen ("kyc-check-")]);
    kc->voluntary = voluntary;
    kc->description = description;
    kc->description_i18n = description_i18n;
    kc->fallback = fallback;
    add_tokens (requires,
                ";",
                &kc->requires,
                &kc->num_requires);
    GNUNET_free (requires);
    add_tokens (outputs,
                " ",
                &kc->outputs,
                &kc->num_outputs);
    GNUNET_free (outputs);
    GNUNET_array_append (kyc_checks,
                         num_kyc_checks,
                         kc);
  }
  return GNUNET_OK;
fail:
  GNUNET_free (form_name);
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
  if (GNUNET_YES !=
      GNUNET_CONFIGURATION_get_value_yesno (cfg,
                                            section,
                                            "EXPOSED"))
    exposed = false;
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

  {
    struct TALER_KYCLOGIC_KycRule kt;

    kt.lrs = &default_rules;
    kt.rule_name = GNUNET_strdup (&section[strlen ("kyc-rule-")]);
    kt.timeframe = timeframe;
    kt.threshold = threshold;
    kt.trigger = ot;
    kt.is_and_combinator = is_and;
    kt.exposed = exposed;
    add_tokens (measures,
                " ",
                &kt.next_measures,
                &kt.num_measures);
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
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FALLBACK",
                               "fallback measure name required");
    goto fail;
  }

  required_contexts = command_output (command,
                                      "--required-context");
  if (NULL == required_contexts)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "output for --required-context invalid");
    goto fail;
  }
  required_attributes = command_output (command,
                                        "--required-attributes");
  if (NULL == required_attributes)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COMMAND",
                               "output for --required-attributes invalid");
    goto fail;
  }

  {
    struct TALER_KYCLOGIC_AmlProgram *ap;

    ap = GNUNET_new (struct TALER_KYCLOGIC_AmlProgram);
    ap->program_name = GNUNET_strdup (&section[strlen ("kyc-check-")]);
    ap->command = command;
    ap->description = description;
    ap->fallback = fallback;
    add_tokens (required_contexts,
                "\n",
                &ap->required_contexts,
                &ap->num_required_contexts);
    GNUNET_free (required_contexts);
    add_tokens (required_attributes,
                "\n",
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
  struct TALER_KYCLOGIC_KycRule **r1
    = (struct TALER_KYCLOGIC_KycRule **) p1;
  struct TALER_KYCLOGIC_KycRule **r2
    = (struct TALER_KYCLOGIC_KycRule **) p2;

  if (GNUNET_TIME_relative_cmp ((*r1)->timeframe,
                                <,
                                (*r2)->timeframe))
    return -1;
  if (GNUNET_TIME_relative_cmp ((*r1)->timeframe,
                                >,
                                (*r2)->timeframe))
    return 1;
  return 0;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_init (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct SectionContext sc = {
    .cfg = cfg,
    .result = true
  };

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
  if (! sc.result)
  {
    TALER_KYCLOGIC_kyc_done ();
    return GNUNET_SYSERR;
  }

  if (0 != default_rules.num_kyc_rules)
    qsort (default_rules.kyc_rules,
           default_rules.num_kyc_rules,
           sizeof (struct TALER_KYCLOGIC_KycRule *),
           &sort_by_timeframe);
  // FIXME: add configuration sanity checking!
  return GNUNET_OK;
}


/**
 * Check if any KYC checks are enabled.
 *
 * @return true if KYC is enabled
 *         false if no KYC checks are possible
 */
bool
TALER_KYCLOGIC_is_enabled (void)
{
  return 0 != num_kyc_providers;
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
    GNUNET_free (kp->converter_name);
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
    for (unsigned int j = 0; i<kc->num_requires; j++)
      GNUNET_free (kc->requires[j]);
    GNUNET_array_grow (kc->requires,
                       kc->num_requires,
                       0);
    GNUNET_free (kc->fallback);
    for (unsigned int j = 0; i<kc->num_outputs; j++)
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
    for (unsigned int j = 0; i<ap->num_required_contexts; j++)
      GNUNET_free (ap->required_contexts[j]);
    GNUNET_array_grow (ap->required_contexts,
                       ap->num_required_contexts,
                       0);
    for (unsigned int j = 0; i<ap->num_required_attributes; j++)
      GNUNET_free (ap->required_attributes[j]);
    GNUNET_array_grow (ap->required_attributes,
                       ap->num_required_attributes,
                       0);
    GNUNET_free (ap);
  }
  GNUNET_array_grow (aml_programs,
                     num_aml_programs,
                     0);
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
TALER_KYCLOGIC_requirements_to_check (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const struct TALER_KYCLOGIC_KycRule *kyc_rule,
  const char *measure_name,
  struct TALER_KYCLOGIC_KycCheckContext *kcc)
{
  bool found = false;
  const struct TALER_KYCLOGIC_Measure *measure = NULL;

  for (unsigned int i = 0; i<kyc_rule->num_measures; i++)
  {
    if (0 != strcmp (measure_name,
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
  measure = find_measure (lrs,
                          measure_name);
  if (NULL == measure)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Measure `%s' unknown (but allowed by rule `%s')\n",
                measure_name,
                kyc_rule->rule_name);
    return GNUNET_SYSERR;
  }

  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == strcmp (measure->check_name,
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
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    if (0 !=
        strcmp (kp->logic->name,
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
      continue; /* wrong trigger event type */
    if (GNUNET_TIME_relative_cmp (dur,
                                  >,
                                  rule->timeframe))
      continue; /* out of time range for rule */
    if (-1 == TALER_amount_cmp (&ktc->sum,
                                &rule->threshold))
      continue; /* sum < threshold */
    if ( (NULL != ktc->triggered_rule) &&
         (1 == TALER_amount_cmp (&ktc->triggered_rule->threshold,
                                 &rule->threshold)) )
      continue; /* threshold of triggered_rule > rule */
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
  const struct TALER_KYCLOGIC_KycRule **triggered_rule)
{
  struct GNUNET_TIME_Relative range
    = GNUNET_TIME_UNIT_ZERO;
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == lrs)
    lrs = &default_rules;
  for (unsigned int i=0; i<lrs->num_kyc_rules; i++)
  {
    const struct TALER_KYCLOGIC_KycRule *rule
      = &lrs->kyc_rules[i];

    if (event != rule->trigger)
      continue;
    range = GNUNET_TIME_relative_max (range,
                                      rule->timeframe);
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
    *triggered_rule = ktc.triggered_rule;
  }
  return qs;
}


json_t *
TALER_KYCLOGIC_measure_to_requirement (
  const char *check_name,
  const char *prog_name,
  const struct TALER_AccountAccessTokenP *access_token,
  size_t offset,
  uint64_t row_id)
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
                                        row_id,
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
      GNUNET_JSON_pack_object_incref ("description_i18n",
                                      (json_t *) kc->description_i18n));
  case TALER_KYCLOGIC_CT_FORM:
    GNUNET_assert (offset <= UINT_MAX);
    ids = GNUNET_STRINGS_data_to_string_alloc (&shv,
                                               sizeof (shv));
    GNUNET_asprintf (&xids,
                     "%llu/%u/%s",
                     (unsigned long long) row_id,
                     (unsigned int) offset,
                     ids);
    GNUNET_free (ids);
    kri = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("form",
                               kc->details.form.name),
      GNUNET_JSON_pack_string ("id",
                               xids),
      GNUNET_JSON_pack_string ("description",
                               kc->description),
      GNUNET_JSON_pack_object_steal ("description_i18n",
                                     (json_t *) kc->description_i18n));
    GNUNET_free (xids);
    return kri;
  case TALER_KYCLOGIC_CT_LINK:
    GNUNET_assert (offset <= UINT_MAX);
    ids = GNUNET_STRINGS_data_to_string_alloc (&shv,
                                               sizeof (shv));
    GNUNET_asprintf (&xids,
                     "%llu/%u/%s",
                     (unsigned long long) row_id,
                     (unsigned int) offset,
                     ids);
    GNUNET_free (ids);
    kri = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("form",
                               "LINK"),
      GNUNET_JSON_pack_string ("id",
                               xids),
      GNUNET_JSON_pack_string ("description",
                               kc->description),
      GNUNET_JSON_pack_object_steal ("description_i18n",
                                     (json_t *) kc->description_i18n));
    GNUNET_free (xids);
    return kri;
  }
  GNUNET_break (0); /* invalid type */
  return NULL;
}


/* end of kyclogic_api.c */
