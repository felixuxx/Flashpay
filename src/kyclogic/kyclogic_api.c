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
   * Name of the provider (configuration section name).
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
 * Types of KYC checks.
 */
enum CheckType
{
  /**
   * Wait for staff or contact staff out-of-band.
   */
  CT_INFO,

  /**
   * SPA should show an inline form.
   */
  CT_FORM,

  /**
   * SPA may start external KYC process.
   */
  CT_LINK
};

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
   * Length of the @e requires array.
   */
  unsigned int num_requires;

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
  enum CheckType type;

  /**
   * Details depending on @e type.
   */
  union
  {

    /**
     * Fields present only if @e type is #CT_FORM.
     */
    struct
    {

      /**
       * Name of the form to render.
       */
      char *name;

    } form;

    /**
     * Fields present only if @e type is CT_LINK.
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
struct TALER_KYCLOGIC_KycRule
{

  /**
   * Name of the rule (configuration section name).
   */
  char *rule_name;

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
   * NULL for default rules.
   */
  char *successor_measure;

  /**
   * Array of the rules.
   */
  struct TALER_KYCLOGIC_KycRule **kyc_rules;

  /**
   * Array of custom measures the @e kyc_rules may refer
   * to.
   */
  struct TALER_KYCLOGIC_Measures *custom_measures;

  /**
   * Length of the @e kyc_rules array.
   */
  unsigned int num_kyc_rules;

  /**
   * Length of the @e custom_measures array.
   */
  unsigned int num_custom_measures;

};


struct TALER_KYCLOGIC_LegitimizationRuleSet *
TALER_KYCLOGIC_rules_parse (const json_t *jrules)
{
  // FIXME!
  GNUNET_break (0);
  return NULL;
}


void
TALER_KYCLOGIC_rules_free (struct TALER_KYCLOGIC_LegitimizationRuleSet *krs)
{
  // FIXME
  GNUNET_break (0);
  GNUNET_free (krs);
}


const char *
TALER_KYCLOGIC_rule2s (struct TALER_KYCLOGIC_KycRule *r)
{
  return r->rule_name;
}


json_t *
TALER_KYCLOGIC_rule2j (struct TALER_KYCLOGIC_KycRule *r)
{
  // FIXME!
  GNUNET_break (0);
  return NULL;
}


uint32_t
TALER_KYCLOGIC_rule2priority (struct TALER_KYCLOGIC_KycRule *r)
{
  return r->display_priority;
}


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
  enum CheckType *ctype)
{
  struct
  {
    const char *in;
    enum CheckType out;
  } map [] = {
    { "INFO", CT_INFO },
    { "LINK", CT_LINK },
    { "FORM", CT_FORM  },
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
  enum CheckType ct;
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
    struct TALER_KYCLOGIC_KycRule *kt;

    kt = GNUNET_new (struct TALER_KYCLOGIC_KycRule);
    kt->rule_name = GNUNET_strdup (&section[strlen ("kyc-rule-")]);
    kt->timeframe = timeframe;
    kt->threshold = threshold;
    kt->trigger = ot;
    kt->is_and_combinator = is_and;
    kt->exposed = exposed;
    add_tokens (measures,
                " ",
                &kt->next_measures,
                &kt->num_measures);
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


void
TALER_KYCLOGIC_kyc_done (void)
{
  for (unsigned int i = 0; i<default_rules.num_kyc_rules; i++)
  {
    struct TALER_KYCLOGIC_KycRule *kt
      = default_rules.kyc_rules[i];

    for (unsigned int j = 0; j<kt->num_measures; j++)
      GNUNET_free (kt->next_measures[j]);
    GNUNET_array_grow (kt->next_measures,
                       kt->num_measures,
                       0);
    GNUNET_free (kt->rule_name);
    GNUNET_free (kt);
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
    case CT_INFO:
      break;
    case CT_FORM:
      GNUNET_free (kc->details.form.name);
      break;
    case CT_LINK:
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


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_requirements_to_logic (
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  const struct TALER_KYCLOGIC_KycRule *kyc_rule,
  const char *measure_name,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **configuration_section)
{
#if FIXME
  struct TALER_KYCLOGIC_KycCheck *needed[num_kyc_checks];
  unsigned int needed_cnt = 0;
  unsigned long long min_cost = ULLONG_MAX;
  unsigned int max_checks = 0;
  const struct TALER_KYCLOGIC_KycProvider *kp_best = NULL;

  if (NULL == requirements)
    return GNUNET_NO;
  {
    char *req = GNUNET_strdup (requirements);

    for (const char *tok = strtok (req, " ");
         NULL != tok;
         tok = strtok (NULL, " "))
      needed[needed_cnt++] = add_check (tok);
    GNUNET_free (req);
  }

  /* Count maximum number of remaining checks covered by any
     provider */
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    const struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];
    unsigned int matched = 0;

    if (kp->user_type != ut)
      continue;
    for (unsigned int j = 0; j<kp->num_checks; j++)
    {
      const struct TALER_KYCLOGIC_KycCheck *kc = kp->provided_checks[j];

      for (unsigned int k = 0; k<needed_cnt; k++)
        if (kc == needed[k])
        {
          matched++;
          break;
        }
    }
    max_checks = GNUNET_MAX (max_checks,
                             matched);
  }
  if (0 == max_checks)
    return GNUNET_SYSERR;

  /* Find min-cost provider covering max_checks. */
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    const struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];
    unsigned int matched = 0;

    if (kp->user_type != ut)
      continue;
    for (unsigned int j = 0; j<kp->num_checks; j++)
    {
      const struct TALER_KYCLOGIC_KycCheck *kc = kp->provided_checks[j];

      for (unsigned int k = 0; k<needed_cnt; k++)
        if (kc == needed[k])
        {
          matched++;
          break;
        }
    }
    if ( (max_checks == matched) &&
         (kp->cost < min_cost) )
    {
      min_cost = kp->cost;
      kp_best = kp;
    }
  }
  GNUNET_assert (NULL != kp_best);
  *plugin = kp_best->logic;
  *pd = kp_best->pd;
  *configuration_section = kp_best->provider_section_name;
  return GNUNET_OK;
#else
  GNUNET_break (0);
  return GNUNET_SYSERR;
#endif
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_lookup_logic (
  const char *name,
  struct TALER_KYCLOGIC_Plugin **plugin,
  struct TALER_KYCLOGIC_ProviderDetails **pd,
  const char **provider_section)
{
#if FIXME
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    if (0 !=
        strcasecmp (name,
                    kp->provider_section_name))
      continue;
    *plugin = kp->logic;
    *pd = kp->pd;
    *provider_section = kp->provider_section_name;
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
    *provider_section = NULL;
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Provider `%s' unknown\n",
              name);
#else
  GNUNET_break (0);
#endif
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


enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_kyc_test_required (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs,
  TALER_KYCLOGIC_KycAmountIterator ai,
  void *ai_cls,
  struct TALER_KYCLOGIC_KycRule **triggered_rule)
{
#if FIXME
  struct TALER_KYCLOGIC_KycCheck *needed[num_kyc_checks];
  unsigned int needed_cnt = 0;
  char *ret;
  struct GNUNET_TIME_Relative timeframe;

  timeframe = GNUNET_TIME_UNIT_ZERO;
  for (unsigned int i = 0; i<num_kyc_triggers; i++)
  {
    const struct TALER_KYCLOGIC_KycTrigger *kt = kyc_triggers[i];

    if (event != kt->trigger)
      continue;
    timeframe = GNUNET_TIME_relative_max (timeframe,
                                          kt->timeframe);
  }
  {
    struct GNUNET_TIME_Absolute now;
    struct ThresholdTestContext ttc = {
      .event = event,
      .needed = needed,
      .needed_cnt = &needed_cnt
    };

    now = GNUNET_TIME_absolute_get ();
    ai (ai_cls,
        GNUNET_TIME_absolute_subtract (now,
                                       timeframe),
        &eval_trigger,
        &ttc);
  }
  if (0 == needed_cnt)
  {
    *required = NULL;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  timeframe = GNUNET_TIME_UNIT_ZERO;
  for (unsigned int i = 0; i<num_kyc_triggers; i++)
  {
    const struct TALER_KYCLOGIC_KycTrigger *kt = kyc_triggers[i];

    if (event != kt->trigger)
      continue;
    timeframe = GNUNET_TIME_relative_max (timeframe,
                                          kt->timeframe);
  }
  {
    struct GNUNET_TIME_Absolute now;
    struct ThresholdTestContext ttc = {
      .event = event,
      .needed = needed,
      .needed_cnt = &needed_cnt
    };

    now = GNUNET_TIME_absolute_get ();
    ai (ai_cls,
        GNUNET_TIME_absolute_subtract (now,
                                       timeframe),
        &eval_trigger,
        &ttc);
  }
  if (0 == needed_cnt)
  {
    *required = NULL;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  {
    struct RemoveContext rc = {
      .needed = needed,
      .needed_cnt = &needed_cnt
    };
    enum GNUNET_DB_QueryStatus qs;

    /* Check what provider checks are already satisfied for h_payto (with
       database), remove those from the 'needed' array. */
    qs = ki (ki_cls,
             h_payto,
             &remove_satisfied,
             &rc);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
  }
  if (0 == needed_cnt)
  {
    *required = NULL;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  {
    struct RemoveContext rc = {
      .needed = needed,
      .needed_cnt = &needed_cnt
    };
    enum GNUNET_DB_QueryStatus qs;

    /* Check what provider checks are already satisfied for h_payto (with
       database), remove those from the 'needed' array. */
    qs = ki (ki_cls,
             h_payto,
             &remove_satisfied,
             &rc);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
  }
  if (0 == needed_cnt)
  {
    *required = NULL;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  ret = NULL;
  for (unsigned int k = 0; k<needed_cnt; k++)
  {
    const struct TALER_KYCLOGIC_KycCheck *kc = needed[k];

    if (NULL == ret)
    {
      ret = GNUNET_strdup (kc->name);
    }
    else /* append */
    {
      char *tmp = ret;

      GNUNET_asprintf (&ret,
                       "%s %s",
                       tmp,
                       kc->name);
      GNUNET_free (tmp);
    }
  }
  *required = ret;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
#else
  GNUNET_break (0);
  return GNUNET_DB_STATUS_HARD_ERROR;
#endif
}


/* end of kyclogic_api.c */

#if 0
// FIXME from here...


/**
 * Closure for the #eval_trigger().
 */
struct ThresholdTestContext
{
  /**
   * Total amount so far.
   */
  struct TALER_Amount total;

  /**
   * Trigger event to evaluate triggers of.
   */
  enum TALER_KYCLOGIC_KycTriggerEvent event;

  /**
   * Offset in the triggers array where we need to start
   * checking for triggers. All trigges below this
   * offset were already hit.
   */
  unsigned int start;

  /**
   * Array of checks needed so far.
   */
  struct TALER_KYCLOGIC_KycCheck **needed;

  /**
   * Pointer to number of entries used in @a needed.
   */
  unsigned int *needed_cnt;

  /**
   * Has @e total been initialized yet?
   */
  bool have_total;
};


/**
 * Function called on each @a amount that was found to
 * be relevant for a KYC check.
 *
 * @param cls closure to allow the KYC module to
 *        total up amounts and evaluate rules
 * @param amount encountered transaction amount
 * @param date when was the amount encountered
 * @return #GNUNET_OK to continue to iterate,
 *         #GNUNET_NO to abort iteration
 *         #GNUNET_SYSERR on internal error (also abort itaration)
 */
static enum GNUNET_GenericReturnValue
eval_trigger (void *cls,
              const struct TALER_Amount *amount,
              struct GNUNET_TIME_Absolute date)
{
  struct ThresholdTestContext *ttc = cls;
  struct GNUNET_TIME_Relative duration;
  bool bump = true;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC check with new amount %s\n",
              TALER_amount2s (amount));
  duration = GNUNET_TIME_absolute_get_duration (date);
  if (ttc->have_total)
  {
    if (0 >
        TALER_amount_add (&ttc->total,
                          &ttc->total,
                          amount))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  else
  {
    ttc->total = *amount;
    ttc->have_total = true;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC check: new total is %s\n",
              TALER_amount2s (&ttc->total));
  for (unsigned int i = ttc->start; i<num_kyc_triggers; i++)
  {
    const struct TALER_KYCLOGIC_KycTrigger *kt = kyc_triggers[i];

    if (ttc->event != kt->trigger)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "KYC check #%u: trigger type does not match\n",
                  i);
      continue;
    }
    duration = GNUNET_TIME_relative_max (duration,
                                         kt->timeframe);
    if (GNUNET_TIME_relative_cmp (kt->timeframe,
                                  >,
                                  duration))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "KYC check #%u: amount is beyond time limit\n",
                  i);
      if (bump)
        ttc->start = i;
      return GNUNET_OK;
    }
    if (-1 ==
        TALER_amount_cmp (&ttc->total,
                          &kt->threshold))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "KYC check #%u: amount is below threshold\n",
                  i);
      if (bump)
        ttc->start = i;
      bump = false;
      continue; /* amount too low to trigger */
    }
    /* add check to list of required checks, unless
       already present... */
    for (unsigned int j = 0; j<kt->num_checks; j++)
    {
      struct TALER_KYCLOGIC_KycCheck *rc = kt->required_checks[j];
      bool found = false;

      for (unsigned int k = 0; k<*ttc->needed_cnt; k++)
        if (ttc->needed[k] == rc)
        {
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "KYC rule #%u already listed\n",
                      j);
          found = true;
          break;
        }
      if (! found)
      {
        ttc->needed[*ttc->needed_cnt] = rc;
        (*ttc->needed_cnt)++;
      }
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC check #%u (%s) is applicable, %u checks needed so far\n",
                i,
                ttc->needed[(*ttc->needed_cnt) - 1]->name,
                *ttc->needed_cnt);
  }
  if (bump)
    return GNUNET_NO; /* we hit all possible triggers! */
  return GNUNET_OK;
}


/**
 * Closure for the #remove_satisfied().
 */
struct RemoveContext
{

  /**
   * Array of checks needed so far.
   */
  struct TALER_KYCLOGIC_KycCheck **needed;

  /**
   * Pointer to number of entries used in @a needed.
   */
  unsigned int *needed_cnt;

  /**
   * Object with information about collected KYC data.
   */
  json_t *kyc_details;
};


/**
 * Remove all checks satisfied by @a provider_name from
 * our list of checks.
 *
 * @param cls a `struct RemoveContext`
 * @param provider_name section name of provider that was already run previously
 */
static void
remove_satisfied (void *cls,
                  const char *provider_name)
{
  struct RemoveContext *rc = cls;

  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    const struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    if (0 != strcasecmp (provider_name,
                         kp->provider_section_name))
      continue;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Provider `%s' satisfied\n",
                provider_name);
    for (unsigned int j = 0; j<kp->num_checks; j++)
    {
      const struct TALER_KYCLOGIC_KycCheck *kc = kp->provided_checks[j];

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Provider satisfies check `%s'\n",
                  kc->name);
      if (NULL != rc->kyc_details)
      {
        GNUNET_assert (0 ==
                       json_object_set_new (
                         rc->kyc_details,
                         kc->name,
                         json_object ()));
      }
      for (unsigned int k = 0; k<*rc->needed_cnt; k++)
        if (kc == rc->needed[k])
        {
          GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                      "Removing check `%s' from list\n",
                      kc->name);
          rc->needed[k] = rc->needed[*rc->needed_cnt - 1];
          (*rc->needed_cnt)--;
          if (0 == *rc->needed_cnt)
            return; /* for sure finished */
          break;
        }
    }
    break;
  }
}


enum GNUNET_DB_QueryStatus
TALER_KYCLOGIC_check_satisfied (
  char **requirements,
  const struct TALER_PaytoHashP *h_payto,
  json_t **kyc_details,
  TALER_KYCLOGIC_KycSatisfiedIterator ki,
  void *ki_cls,
  bool *satisfied)
{
  struct TALER_KYCLOGIC_KycCheck *needed[num_kyc_checks];
  unsigned int needed_cnt = 0;

  if (NULL == requirements)
  {
    *satisfied = true;
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  {
    char *req = *requirements;

    for (const char *tok = strtok (req, " ");
         NULL != tok;
         tok = strtok (NULL, " "))
      needed[needed_cnt++] = add_check (tok);
    GNUNET_free (req);
    *requirements = NULL;
  }

  {
    struct RemoveContext rc = {
      .needed = needed,
      .needed_cnt = &needed_cnt,
    };
    enum GNUNET_DB_QueryStatus qs;

    rc.kyc_details = json_object ();
    GNUNET_assert (NULL != rc.kyc_details);

    /* Check what provider checks are already satisfied for h_payto (with
       database), remove those from the 'needed' array. */
    qs = ki (ki_cls,
             h_payto,
             &remove_satisfied,
             &rc);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      *satisfied = false;
      return qs;
    }
    if (0 != needed_cnt)
    {
      json_decref (rc.kyc_details);
      *kyc_details = NULL;
    }
    else
    {
      *kyc_details = rc.kyc_details;
    }
  }
  *satisfied = (0 == needed_cnt);

  {
    char *res = NULL;

    for (unsigned int i = 0; i<needed_cnt; i++)
    {
      const struct TALER_KYCLOGIC_KycCheck *need = needed[i];

      if (NULL == res)
      {
        res = GNUNET_strdup (need->name);
      }
      else
      {
        char *tmp;

        GNUNET_asprintf (&tmp,
                         "%s %s",
                         res,
                         need->name);
        GNUNET_free (res);
        res = tmp;
      }
    }
    *requirements = res;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


void
TALER_KYCLOGIC_kyc_iterate_thresholds (
  enum TALER_KYCLOGIC_KycTriggerEvent event,
  TALER_KYCLOGIC_KycThresholdIterator it,
  void *it_cls)
{
  for (unsigned int i = 0; i<num_kyc_triggers; i++)
  {
    const struct TALER_KYCLOGIC_KycTrigger *kt = kyc_triggers[i];

    if (event != kt->trigger)
      continue;
    it (it_cls,
        &kt->threshold);
  }
}


void
TALER_KYCLOGIC_lookup_checks (const char *section_name,
                              unsigned int *num_checks,
                              char ***provided_checks)
{
  *num_checks = 0;
  *provided_checks = NULL;
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    if (0 !=
        strcasecmp (section_name,
                    kp->provider_section_name))
      continue;
    *num_checks = kp->num_checks;
    if (0 != kp->num_checks)
    {
      char **pc = GNUNET_new_array (kp->num_checks,
                                    char *);
      for (unsigned int i = 0; i<kp->num_checks; i++)
        pc[i] = GNUNET_strdup (kp->provided_checks[i]->name);
      *provided_checks = pc;
    }
    return;
  }
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_check_satisfiable (
  const char *check_name)
{
  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == strcmp (check_name,
                     kyc_checks[i]->name))
      return GNUNET_OK;
  if (0 == strcmp (check_name,
                   KYC_CHECK_IMPOSSIBLE))
    return GNUNET_NO;
  return GNUNET_SYSERR;
}


json_t *
TALER_KYCLOGIC_get_satisfiable ()
{
  json_t *requirements;

  requirements = json_array ();
  GNUNET_assert (NULL != requirements);
  for (unsigned int i = 0; i<num_kyc_checks; i++)
    GNUNET_assert (
      0 ==
      json_array_append_new (
        requirements,
        json_string (kyc_checks[i]->name)));
  return requirements;
}


#endif
