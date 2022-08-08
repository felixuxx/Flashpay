/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
#include "taler_kyclogic_lib.h"

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
  char *name;

  /**
   * Array of @e num_providers providers that offer this type of KYC check.
   */
  struct TALER_KYCLOGIC_KycProvider **providers;

  /**
   * Length of the @e providers array.
   */
  unsigned int num_providers;

};


struct TALER_KYCLOGIC_KycProvider
{
  /**
   * Name of the provider (configuration section name).
   */
  const char *provider_section_name;

  /**
   * Array of @e num_checks checks performed by this provider.
   */
  struct TALER_KYCLOGIC_KycCheck **provided_checks;

  /**
   * Logic to run for this provider.
   */
  struct TALER_KYCLOGIC_Plugin *logic;

  /**
   * @e provider_section_name specific details to
   * pass to the @e logic functions.
   */
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Cost of running this provider's KYC.
   */
  unsigned long long cost;

  /**
   * Length of the @e checks array.
   */
  unsigned int num_checks;

  /**
   * Type of user this provider supports.
   */
  enum TALER_KYCLOGIC_KycUserType user_type;
};


/**
 * Condition that triggers a need to perform KYC.
 */
struct TALER_KYCLOGIC_KycTrigger
{

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
   * Array of @e num_checks checks to apply on this trigger.
   */
  struct TALER_KYCLOGIC_KycCheck **required_checks;

  /**
   * Length of the @e checks array.
   */
  unsigned int num_checks;

  /**
   * What event is this trigger for?
   */
  enum TALER_KYCLOGIC_KycTriggerEvent trigger;

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
 * Array of @e num_kyc_checks known types of
 * KYC checks.
 */
static struct TALER_KYCLOGIC_KycCheck **kyc_checks;

/**
 * Length of the #kyc_checks array.
 */
static unsigned int num_kyc_checks;

/**
 * Array of configured triggers.
 */
static struct TALER_KYCLOGIC_KycTrigger **kyc_triggers;

/**
 * Length of the #kyc_triggers array.
 */
static unsigned int num_kyc_triggers;

/**
 * Array of configured providers.
 */
static struct TALER_KYCLOGIC_KycProvider **kyc_providers;

/**
 * Length of the #kyc_providers array.
 */
static unsigned int num_kyc_providers;


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_trigger_from_string (const char *trigger_s,
                                        enum TALER_KYCLOGIC_KycTriggerEvent *
                                        trigger)
{
  struct
  {
    const char *in;
    enum TALER_KYCLOGIC_KycTriggerEvent out;
  } map [] = {
    { "withdraw", TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW },
    { "deposit", TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT  },
    { "merge", TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE },
    { "balance", TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE },
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
TALER_KYCLOGIC_kyc_trigger2s (enum TALER_KYCLOGIC_KycTriggerEvent trigger)
{
  switch (trigger)
  {
  case TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW:
    return "withdraw";
  case TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT:
    return "deposit";
  case TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE:
    return "merge";
  case TALER_KYCLOGIC_KYC_TRIGGER_WALLET_BALANCE:
    return "balance";
  }
  GNUNET_break (0);
  return NULL;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_user_type_from_string (const char *ut_s,
                                          enum TALER_KYCLOGIC_KycUserType *ut)
{
  struct
  {
    const char *in;
    enum TALER_KYCLOGIC_KycTriggerEvent out;
  } map [] = {
    { "individual", TALER_KYCLOGIC_KYC_UT_INDIVIDUAL },
    { "business", TALER_KYCLOGIC_KYC_UT_BUSINESS  },
    { NULL, 0 }
  };

  for (unsigned int i = 0; NULL != map[i].in; i++)
    if (0 == strcasecmp (map[i].in,
                         ut_s))
    {
      *ut = map[i].out;
      return GNUNET_OK;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Invalid user type `%s'\n",
              ut_s);
  return GNUNET_SYSERR;
}


const char *
TALER_KYCLOGIC_kyc_user_type2s (enum TALER_KYCLOGIC_KycUserType ut)
{
  switch (ut)
  {
  case TALER_KYCLOGIC_KYC_UT_INDIVIDUAL:
    return "individual";
  case TALER_KYCLOGIC_KYC_UT_BUSINESS:
    return "business";
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
  plugin = GNUNET_PLUGIN_load (lib_name,
                               (void *) cfg);
  if (NULL != plugin)
    plugin->library_name = lib_name;
  else
    GNUNET_free (lib_name);
  return plugin;
}


/**
 * Add check type to global array of checks.
 * First checks if the type already exists, otherwise
 * adds a new one.
 *
 * @param check name of the check
 * @return pointer into the global list
 */
static struct TALER_KYCLOGIC_KycCheck *
add_check (const char *check)
{
  struct TALER_KYCLOGIC_KycCheck *kc;

  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == strcasecmp (check,
                         kyc_checks[i]->name))
      return kyc_checks[i];
  kc = GNUNET_new (struct TALER_KYCLOGIC_KycCheck);
  kc->name = GNUNET_strdup (check);
  GNUNET_array_append (kyc_checks,
                       num_kyc_checks,
                       kc);
  return kc;
}


/**
 * Parse list of checks from @a checks and build an
 * array of aliases into the global checks array
 * in @a provided_checks.
 *
 * @param[in,out] checks list of checks; clobbered
 * @param[out] p_checks where to put array of aliases
 * @param[out] num_p_checks set to length of @a p_checks array
 */
static void
add_checks (char *checks,
            struct TALER_KYCLOGIC_KycCheck ***p_checks,
            unsigned int *num_p_checks)
{
  char *sptr;
  struct TALER_KYCLOGIC_KycCheck **rchecks = NULL;
  unsigned int num_rchecks = 0;

  for (char *tok = strtok_r (checks, " ", &sptr);
       NULL != tok;
       tok = strtok_r (NULL, " ", &sptr))
  {
    struct TALER_KYCLOGIC_KycCheck *kc;

    kc = add_check (tok);
    GNUNET_array_append (rchecks,
                         num_rchecks,
                         kc);
  }
  *p_checks = rchecks;
  *num_p_checks = num_rchecks;
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
  unsigned long long cost;
  char *logic;
  char *ut_s;
  enum TALER_KYCLOGIC_KycUserType ut;
  char *checks;
  struct TALER_KYCLOGIC_Plugin *lp;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             section,
                                             "COST",
                                             &cost))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "COST",
                               "number required");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "USER_TYPE",
                                             &ut_s))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "USER_TYPE");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_KYCLOGIC_kyc_user_type_from_string (ut_s,
                                                &ut))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "USER_TYPE",
                               "valid user type required");
    GNUNET_free (ut_s);
    return GNUNET_SYSERR;
  }
  GNUNET_free (ut_s);
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
    GNUNET_free (logic);
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "LOGIC",
                               "logic plugin could not be loaded");
    return GNUNET_SYSERR;
  }
  GNUNET_free (logic);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "PROVIDED_CHECKS",
                                             &checks))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "PROVIDED_CHECKS");
    return GNUNET_SYSERR;
  }
  {
    struct TALER_KYCLOGIC_KycProvider *kp;

    kp = GNUNET_new (struct TALER_KYCLOGIC_KycProvider);
    kp->provider_section_name = section;
    kp->user_type = ut;
    kp->logic = lp;
    kp->cost = cost;
    add_checks (checks,
                &kp->provided_checks,
                &kp->num_checks);
    GNUNET_free (checks);
    kp->pd = lp->load_configuration (lp->cls,
                                     section);
    if (NULL == kp->pd)
    {
      GNUNET_free (kp);
      return GNUNET_SYSERR;
    }
    GNUNET_array_append (kyc_providers,
                         num_kyc_providers,
                         kp);
    for (unsigned int i = 0; i<kp->num_checks; i++)
    {
      struct TALER_KYCLOGIC_KycCheck *kc = kp->provided_checks[i];

      GNUNET_array_append (kc->providers,
                           kc->num_providers,
                           kp);
    }
  }
  return GNUNET_OK;
}


static enum GNUNET_GenericReturnValue
add_trigger (const struct GNUNET_CONFIGURATION_Handle *cfg,
             const char *section)
{
  char *ot_s;
  struct TALER_Amount threshold;
  struct GNUNET_TIME_Relative timeframe;
  char *checks;
  enum TALER_KYCLOGIC_KycTriggerEvent ot;

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
                                             "REQUIRED_CHECKS",
                                             &checks))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "REQUIRED_CHECKS");
    return GNUNET_SYSERR;
  }

  {
    struct TALER_KYCLOGIC_KycTrigger *kt;

    kt = GNUNET_new (struct TALER_KYCLOGIC_KycTrigger);
    kt->timeframe = timeframe;
    kt->threshold = threshold;
    kt->trigger = ot;
    add_checks (checks,
                &kt->required_checks,
                &kt->num_checks);
    GNUNET_free (checks);
    GNUNET_array_append (kyc_triggers,
                         num_kyc_triggers,
                         kt);
  }
  return GNUNET_OK;
}


/**
 * Closure for #handle_section().
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
handle_section (void *cls,
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
      sc->result = false;
    return;
  }
  if (0 == strncasecmp (section,
                        "kyc-legitimization-",
                        strlen ("kyc-legitimization-")))
  {
    if (GNUNET_OK !=
        add_trigger (sc->cfg,
                     section))
      sc->result = false;
    return;
  }
}


/**
 * Comparator for qsort. Compares two triggers
 * by timeframe to sort triggers by time.
 *
 * @param p1 first trigger to compare
 * @param p2 second trigger to compare
 * @return -1 if p1 < p2, 0 if p1==p2, 1 if p1 > p2.
 */
static int
sort_by_timeframe (const void *p1,
                   const void *p2)
{
  struct TALER_KYCLOGIC_KycTrigger **t1 = (struct
                                           TALER_KYCLOGIC_KycTrigger **) p1;
  struct TALER_KYCLOGIC_KycTrigger **t2 = (struct
                                           TALER_KYCLOGIC_KycTrigger **) p2;

  if (GNUNET_TIME_relative_cmp ((*t1)->timeframe,
                                <,
                                (*t2)->timeframe))
    return -1;
  if (GNUNET_TIME_relative_cmp ((*t1)->timeframe,
                                >,
                                (*t2)->timeframe))
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
                                         &handle_section,
                                         &sc);
  if (! sc.result)
  {
    TALER_KYCLOGIC_kyc_done ();
    return GNUNET_SYSERR;
  }

  /* sanity check: ensure at least one provider exists
     for any trigger and indidivual or business. */
  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == kyc_checks[i]->num_providers)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "No provider available for required KYC check `%s'\n",
                  kyc_checks[i]->name);
      TALER_KYCLOGIC_kyc_done ();
      return GNUNET_SYSERR;
    }
  qsort (kyc_triggers,
         num_kyc_triggers,
         sizeof (struct TALER_KYCLOGIC_KycTrigger *),
         &sort_by_timeframe);
  return GNUNET_OK;
}


void
TALER_KYCLOGIC_kyc_done (void)
{
  for (unsigned int i = 0; i<num_kyc_triggers; i++)
  {
    struct TALER_KYCLOGIC_KycTrigger *kt = kyc_triggers[i];

    GNUNET_array_grow (kt->required_checks,
                       kt->num_checks,
                       0);
    GNUNET_free (kt);
  }
  GNUNET_array_grow (kyc_triggers,
                     num_kyc_triggers,
                     0);
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    kp->logic->unload_configuration (kp->pd);
    GNUNET_array_grow (kp->provided_checks,
                       kp->num_checks,
                       0);
    GNUNET_free (kp);
  }
  GNUNET_array_grow (kyc_providers,
                     num_kyc_providers,
                     0);
  for (unsigned int i = 0; i<num_kyc_logics; i++)
  {
    struct TALER_KYCLOGIC_Plugin *lp = kyc_logics[i];
    char *lib_name = lp->library_name;

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

    GNUNET_free (kc->name);
    GNUNET_free (kc);
  }
  GNUNET_array_grow (kyc_checks,
                     num_kyc_checks,
                     0);
}


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
  }
  for (unsigned int i = ttc->start; i<num_kyc_triggers; i++)
  {
    const struct TALER_KYCLOGIC_KycTrigger *kt = kyc_triggers[i];

    if (ttc->event != kt->trigger)
      continue;
    duration = GNUNET_TIME_relative_max (duration,
                                         kt->timeframe);
    if (GNUNET_TIME_relative_cmp (kt->timeframe,
                                  >,
                                  duration))
    {
      if (bump)
        ttc->start = i;
      return GNUNET_OK;
    }
    if (-1 ==
        TALER_amount_cmp (&ttc->total,
                          &kt->threshold))
    {
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
          found = true;
          break;
        }
      if (! found)
      {
        ttc->needed[*ttc->needed_cnt] = rc;
        (*ttc->needed_cnt)++;
      }
    }
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
    for (unsigned int j = 0; j<kp->num_checks; j++)
    {
      const struct TALER_KYCLOGIC_KycCheck *kc = kp->provided_checks[j];

      for (unsigned int k = 0; k<*rc->needed_cnt; k++)
        if (kc == rc->needed[k])
        {
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


const char *
TALER_KYCLOGIC_kyc_test_required (enum TALER_KYCLOGIC_KycTriggerEvent event,
                                  const struct TALER_PaytoHashP *h_payto,
                                  TALER_KYCLOGIC_KycSatisfiedIterator ki,
                                  void *ki_cls,
                                  TALER_KYCLOGIC_KycAmountIterator ai,
                                  void *ai_cls)
{
  struct TALER_KYCLOGIC_KycCheck *needed[num_kyc_checks];
  unsigned int needed_cnt = 0;
  struct GNUNET_TIME_Relative timeframe;
  unsigned long long min_cost = ULONG_LONG_MAX;
  unsigned int max_checks = 0;
  const struct TALER_KYCLOGIC_KycProvider *kp_best = NULL;

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
    return NULL;
  {
    struct RemoveContext rc = {
      .needed = needed,
      .needed_cnt = &needed_cnt
    };
    enum GNUNET_DB_QueryStatus qs;

    /* Check what provider checks are already satisfied for h_payto (with
       database), remove those from the 'needed' array. */
    GNUNET_break (0);
    // FIXME: do via callback!
    qs = ki (ki_cls,
             h_payto,
             &
             remove_satisfied,
             &rc);
    GNUNET_break (qs >= 0);  // FIXME: handle DB failure more nicely?
  }

  /* Count maximum number of remaining checks covered by any
     provider */
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    const struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];
    unsigned int matched = 0;

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

  /* Find min-cost provider covering max_checks. */
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    const struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];
    unsigned int matched = 0;

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
  return kp_best->provider_section_name;
}


enum GNUNET_GenericReturnValue
TALER_KYCLOGIC_kyc_get_logic (const char *provider_section_name,
                              struct TALER_KYCLOGIC_Plugin **plugin,
                              struct TALER_KYCLOGIC_ProviderDetails **pd)
{
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TALER_KYCLOGIC_KycProvider *kp = kyc_providers[i];

    if (0 !=
        strcasecmp (provider_section_name,
                    kp->provider_section_name))
      continue;
    *plugin = kp->logic;
    *pd = kp->pd;
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Provider `%s' unknown\n",
              provider_section_name);
  return GNUNET_SYSERR;
}


/* end of taler-exchange-httpd_kyc.c */
