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
  struct TEH_KycCheck *provided_checks;

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
  struct TALER_Amount limit;

  /**
   * Array of @e num_checks checks to apply on this trigger.
   */
  struct TEH_KycCheck *required_checks;

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
static struct TEH_KYCLOGIC_Plugin *kyc_logics;

/**
 * Length of the #kyc_logics array.
 */
static unsigned in num_kyc_logics;

/**
 * Array of @e num_kyc_checks known types of
 * KYC checks.
 */
static struct TEH_KycCheck *kyc_checks;

/**
 * Length of the #kyc_checks array.
 */
static unsigned int num_kyc_checks;

/**
 * Array of configured triggers.
 */
static struct TEH_KycTrigger *kyc_triggers;

/**
 * Length of the #kyc_triggers array.
 */
static unsigned int num_kyc_triggers;

/**
 * Array of configured providers.
 */
static struct TEH_KycProviders *kyc_providers;

/**
 * Length of the #kyc_providers array.
 */
static unsigned int num_kyc_providers;


enum GNUNET_GenericReturnValue
TEH_kyc_trigger_from_string (const char *trigger_s,
                             enum TEH_KycTriggerEvent *trigger)
{
  GNUNET_break (0);
  return GNUNET_SYSERR;
}


const char *
TEH_kyc_trigger2s (enum TEH_KycTriggerEvent trigger)
{
  GNUNET_break (0);
  return NULL;
}


enum GNUNET_GenericReturnValue
TEH_kyc_user_type_from_string (const char *ut_s,
                               enum TEH_KycUserType *ut)
{
  GNUNET_break (0);
  return GNUNET_SYSERR;
}


const char *
TEH_kyc_user_type2s (enum TEH_KycUserType ut)
{
  GNUNET_break (0);
  return NULL;
}


enum GNUNET_GenericReturnValue
TEH_kyc_init (void)
{
  GNUNET_break (0);
  // iterate over configuration sections,
  // initialize arrays above
  // sanity check: ensure at least one provider exists
  // for any trigger and indidivual or business.

  return GNUNET_OK;
}


void
TEH_kyc_done (void)
{
  // unload plugins
  // free arrays
}


const char *
TEH_kyc_test_required (enum TEH_KycTriggerEvent event,
                       const struct TALER_PaytoHashP *h_payto,
                       TEH_KycAmountIterator ai,
                       void *cls)
{
  // Check if event(s) may at all require KYC.
  // If so, check what provider checks are
  // already satisified for h_payto (with database)
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
  // lookup provider by section name in array,
  // return internal plugin/pd fields.
  GNUNET_break (0);
  return GNUNET_SYSERR;
}
