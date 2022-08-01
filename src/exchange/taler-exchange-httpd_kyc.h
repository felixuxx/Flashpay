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
 * @file taler-exchange-httpd_kyc.h
 * @brief KYC API for the exchange
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_KYC_H
#define TALER_EXCHANGE_HTTPD_KYC_H

#include <microhttpd.h>
#include "taler_kyclogic_plugin.h"


/**
 * Enumeration for our KYC user types.
 */
enum TEH_KycUserType
{
  /**
   * KYC rule is for an individual.
   */
  TEH_KYC_INDIVIDUAL = 0,

  /**
   * KYC rule is for a business.
   */
  TEH_KYC_BUSINESS = 1
};


/**
 * Enumeration of possible events that may trigger
 * KYC requirements.
 */
enum TEH_KycTriggerEvent
{

  /**
   * Customer withdraws coins.
   */
  TEH_KYC_TRIGGER_WITHDRAW = 0,

  /**
   * Merchant deposits coins.
   */
  TEH_KYC_TRIGGER_DEPOSIT = 1,

  /**
   * Wallet receives P2P payment.
   */
  TEH_KYC_TRIGGER_P2P_RECEIVE = 2,

  /**
   * Wallet balance exceeds threshold.
   */
  TEH_KYC_TRIGGER_WALLET_BALANCE = 3

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
TEH_kyc_trigger_from_string (const char *trigger_s,
                             enum TEH_KycTriggerEvent *trigger);


/**
 * Convert KYC trigger value to human-readable string.
 *
 * @param trigger value to convert
 * @return human-readable representation of the @a trigger
 */
const char *
TEH_kyc_trigger2s (enum TEH_KycTriggerEvent trigger);


/**
 * Parse user type string into enumeration value.
 *
 * @param ut_s string to parse
 * @param[out] ut set to the value found
 * @return #GNUNET_OK on success, #GNUNET_NO if option
 *         does not exist, #GNUNET_SYSERR if option is
 *         malformed
 */
enum GNUNET_GenericReturnValue
TEH_kyc_user_type_from_string (const char *ut_s,
                               enum TEH_KycUserType *ut);


/**
 * Convert KYC user type to human-readable string.
 *
 * @param ut value to convert
 * @return human-readable representation of the @a ut
 */
const char *
TEH_kyc_user_type2s (enum TEH_KycUserType ut);


/**
 * Initialize KYC subsystem. Loads the KYC
 * configuration.
 *
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_kyc_init (void);


/**
 * Shut down the KYC subsystem.
 */
void
TEH_kyc_done (void);


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
enum GNUNET_GenericReturnValue
(*TEH_KycAmountCallback)(void *cls,
                         const struct TALER_Amount *amount,
                         struct GNUNET_TIME_Absolute date);


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
void
(*TEH_KycAmountIterator)(void *cls,
                         struct GNUNET_TIME_Absolute limit,
                         TEH_KycAmountCallback cb,
                         void *cb_cls);


/**
 * Check if KYC is provided for a particular operation. Returns the best
 * provider (configuration section name) that could perform the required
 * check.
 *
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param event what type of operation is triggering the
 *         test if KYC is required
 * @param h_payto account the event is about
 * @param ai callback offered to inquire about historic
 *         amounts involved in this type of operation
 *         at the given account
 * @param cls closure for @a pi and @a ai
 * @return NULL if no check is needed
 */
const char *
TEH_kyc_test_required (enum TEH_KycTriggerEvent event,
                       const struct TALER_PaytoHashP *h_payto,
                       TEH_KycAmountIterator ai,
                       void *cls);


/**
 * Obtain the provider logic for a given
 * @a provider_section_name.
 *
 * @param provider_section_name identifies a KYC provider process
 * @param[out] plugin set to the KYC logic API
 * @param[out] pd set to the specific operation context
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_kyc_get_logic (const char *provider_section_name,
                   struct TEH_KYCLOGIC_Plugin **plugin,
                   struct TEH_KYCLOGIC_ProviderDetails **pd);


#endif
