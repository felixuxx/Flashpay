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
 * @file taler-exchange-httpd_kyc.c
 * @brief KYC API for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-exchange-httpd_kyc.h"

/**
 * Information about a KYC provider.
 */
struct TEH_KycProvider;


/**
 * Abstract representation of a KYC check.
 */
struct TEH_KycCheck
{
  /**
   * Human-readable name given to the KYC check.
   */
  char *name;

  /**
   * Array of @e num_providers providers that offer this type of KYC check.
   */
  struct TEH_KycProvider *providers;

  /**
   * Length of the @e providers array.
   */
  unsigned int num_providers;

};


struct TEH_KycProvider
{
  /**
   * Name of the provider (configuration section name).
   */
  const char *provider_section_name;

  /**
   * Array of @e num_checks checks performed by this provider.
   */
  struct TEH_KycCheck **provided_checks;

  /**
   * Logic to run for this provider.
   */
  struct TEH_KYCLOGIC_Plugin *logic;

  /**
   * @e provider_section_name specific details to
   * pass to the @e logic functions.
   */
  struct TEH_KYCLOGIC_ProviderDetails *pd;

  /**
   * Length of the @e checks array.
   */
  unsigned int num_checks;

  /**
   * Type of user this provider supports.
   */
  enum TEH_KycUserType user_type;
};


/**
 * Condition that triggers a need to perform KYC.
 */
struct TEH_KycTrigger
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
  struct TEH_KycCheck **required_checks;

  /**
   * Length of the @e checks array.
   */
  unsigned int num_checks;

  /**
   * What event is this trigger for?
   */
  enum TEH_KycTriggerEvent trigger;

};


/**
 * Array of @e num_kyc_logics KYC logic plugins we have loaded.
 */
static struct TEH_KYCLOGIC_Plugin **kyc_logics;

/**
 * Length of the #kyc_logics array.
 */
static unsigned in num_kyc_logics;

/**
 * Array of @e num_kyc_checks known types of
 * KYC checks.
 */
static struct TEH_KycCheck **kyc_checks;

/**
 * Length of the #kyc_checks array.
 */
static unsigned int num_kyc_checks;

/**
 * Array of configured triggers.
 */
static struct TEH_KycTrigger **kyc_triggers;

/**
 * Length of the #kyc_triggers array.
 */
static unsigned int num_kyc_triggers;

/**
 * Array of configured providers.
 */
static struct TEH_KycProvider *kyc_providers;

/**
 * Length of the #kyc_providers array.
 */
static unsigned int num_kyc_providers;


enum GNUNET_GenericReturnValue
TEH_kyc_trigger_from_string (const char *trigger_s,
                             enum TEH_KycTriggerEvent *trigger)
{
  struct
  {
    const char *in;
    enum TEH_KycTriggerEvent out;
  } map [] = {
    { "withdraw", TEH_KYC_TRIGGER_WITHDRAW },
    { "deposit", TEH_KYC_TRIGGER_DEPOSIT  },
    { "merge", TEH_KYC_TRIGGER_P2P_RECEIVE },
    { "balance", TEH_KYC_TRIGGER_WALLET_BALANCE },
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
TEH_kyc_trigger2s (enum TEH_KycTriggerEvent trigger)
{
  switch (trigger)
  {
  case TEH_KYC_TRIGGER_WITHDRAW:
    return "withdraw";
  case TEH_KYC_TRIGGER_DEPOSIT:
    return "deposit";
  case TEH_KYC_TRIGGER_P2P_RECEIVE:
    return "merge";
  case TEH_KYC_TRIGGER_WALLET_BALANCE:
    return "balance";
  }
  GNUNET_break (0);
  return NULL;
}


enum GNUNET_GenericReturnValue
TEH_kyc_user_type_from_string (const char *ut_s,
                               enum TEH_KycUserType *ut)
{
  struct
  {
    const char *in;
    enum TEH_KycTriggerEvent out;
  } map [] = {
    { "individual", TEH_KYC_UT_INDIVIDUAL },
    { "business", TEH_KYC_UT_BUSINESS  },
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
TEH_kyc_user_type2s (enum TEH_KycUserType ut)
{
  switch (ut)
  {
  case TEH_KYC_UT_INDIVIDUAL:
    return "individual";
  case TEH_KYC_UT_BUSINESS:
    return "business";
  }
  GNUNET_break (0);
  return NULL;
}


/**
 * Load KYC logic plugin.
 *
 * @param name name of the plugin
 * @return NULL on error
 */
static struct TEH_KYCLOGIC_Plugin *
load_logic (const char *name)
{
  GNUNET_break (0);
  return NULL;
}


/**
 * Add check type to global array of checks.
 * First checks if the type already exists, otherwise
 * adds a new one.
 *
 * @param check name of the check
 * @return pointer into the global list
 */
static struct TEH_KycCheck *
add_check (const char *check)
{
  struct TEH_KycCheck *kc;

  for (unsigned int i = 0; i<num_kyc_checks; i++)
    if (0 == strcasecmp (check,
                         kyc_checks[i]->name))
      return kyc_checks[i];
  kc = GNUNET_new (struct TEH_KycCheck);
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
            struct TEH_KycCheck **p_checks,
            unsigned int *num_p_checks)
{
  char *sptr;
  struct TEH_KycCheck *rchecks = NULL;
  unsigned int num_rchecks = 0;

  for (char *tok = strtok_r (checks, " ", &sptr);
       NULL != tok;
       tok = strtok_r (checks, NULL, &sptr))
  {
    struct TEH_KycCheck *kc;

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
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
add_provider (const char *section)
{
  unsigned long long cost;
  char *logic;
  char *ut_s;
  enum TEH_KycUserType ut;
  char *checks;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (TEH_cfg,
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
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
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
      TEH_kyc_user_type_from_string (ut_s,
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
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
                                             section,
                                             "LOGIC",
                                             &logic))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "LOGIC");
    return GNUNET_SYSERR;
  }
  lp = load_logic (logic);
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
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
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
    struct TEH_KycProvider *kp;

    kp = GNUNET_new (struct TEH_KycProvider);
    kp->provider_section_name = section;
    kp->user_type = ut;
    kp->logic = lp;
    add_checks (checks,
                &kp->provided_checks,
                &kp->num_checks);
    GNUNET_free (checks);
    kp->pd = lp->load (lp->cls,
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
      struct TEH_KycCheck *kc = kp->provided_checks[i];

      GNUNET_array_append (kc->providers,
                           kc->num_providers,
                           kp);
    }
  }
  return GNUNET_OK;
}


static enum GNUNET_GenericReturnValue
add_trigger (const char *section)
{
  char *ot_s;
  struct TALER_Amount threshold;
  struct GNUNET_TIME_Relative timeframe;
  char *checks;
  enum TEH_KycTriggerEvent ot;

  if (GNUNET_OK !=
      TALER_CONFIGURATION_get_value_amount (TEH_cfg,
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
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
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
      TEH_kyc_trigger_from_string (ot_s,
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
      GNUNET_CONFIGURATION_get_value_time (TEH_cfg,
                                           section,
                                           "TIMEFRAME",
                                           &timeframe))
  {
    if (TEH_KYC_TRIGGER_WALLET_BALANCE == ot)
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
      GNUNET_CONFIGURATION_get_value_string (TEH_cfg,
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
    struct TEH_KycTrigger *kt;

    kt = GNUNET_new (struct TEH_KycTrigger);
    kt->timeframe = timeframe;
    kt->threshold = threshold;
    kt->trigger = ot;
    add_checks (checks,
                &kt->required_checks,
                &kt->num_checks);
    GNUNET_free (checks);
    GNUNET_array_append (kyc_checks,
                         num_kyc_checks,
                         kt);
  }
  return GNUNET_OK;
}


/**
 * Function to iterate over configuration sections.
 *
 * @param cls closure, `boolean *`, set to false on failure
 * @param section name of the section
 */
static void
handle_section (void *cls,
                const char *section)
{
  bool *ok = cls;

  if (0 == strncasecmp (section,
                        "kyc-provider-",
                        strlen ("kyc-provider-")))
  {
    if (GNUNET_OK !=
        add_provider (section))
      *ok = false;
    return;
  }
  if (0 == strncasecmp (section,
                        "kyc-legitimization-",
                        strlen ("kyc-legitimization-")))
  {
    if (GNUNET_OK !=
        add_trigger (section))
      *ok = false;
    return;
  }
}


enum GNUNET_GenericReturnValue
TEH_kyc_init (void)
{
  book ok = true;

  GNUNET_CONFIGURATION_iterate_sections (TEH_cfg,
                                         &handle_section,
                                         &ok);
  if (! ok)
  {
    TEH_kyc_done ();
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
      TEH_kyc_done ();
      return GNUNET_SYSERR;
    }

  return GNUNET_OK;
}


void
TEH_kyc_done (void)
{
  for (unsigned int i = 0; i<num_kyc_triggers; i++)
  {
    struct TEH_KycTrigger *kt = kyc_triggers[i];

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
    struct TEH_KycProvider *kp = kyc_providers[i];

    kp->logic->unload (kp->pd);
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
    struct TEH_KYCLOGIC_Plugin *lp = kyc_logics[i];

    unload_plugin (lp);
  }
  GNUNET_array_grow (kyc_logics,
                     num_kyc_logics,
                     0);
  for (unsigned int i = 0; i<num_kyc_checks; i++)
  {
    struct TEH_KycCheck *kc = kyc_checks[i];

    GNUNET_free (kc->name);
    GNUNET_free (kc);
  }
  GNUNET_array_grow (kyc_checks,
                     num_kyc_checks,
                     0);
}


const char *
TEH_kyc_test_required (enum TEH_KycTriggerEvent event,
                       const struct TALER_PaytoHashP *h_payto,
                       TEH_KycAmountIterator ai,
                       void *cls)
{
  // Check if event(s) may at all require KYC.
  // If so, check what provider checks are
  // already satisfied for h_payto (with database)
  // If unsatisfied checks are left, use 'ai'
  // to check if amount is high enough to trigger them.
  // If it is, find cheapest provider that satisfies
  // all of them (or, if multiple providers would be
  // needed, return one of them).
  GNUNET_break (0);
  return NULL;
}


enum GNUNET_GenericReturnValue
TEH_kyc_get_logic (const char *provider_section_name,
                   struct TEH_KYCLOGIC_Plugin **plugin,
                   struct TEH_KYCLOGIC_ProviderDetails **pd)
{
  for (unsigned int i = 0; i<num_kyc_providers; i++)
  {
    struct TEH_KycProvider *kp = kyc_providers[i];

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
