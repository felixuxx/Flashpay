/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file include/taler_kyclogic_plugin.h
 * @brief KYC API specific logic C interface
 * @author Christian Grothoff
 */
#ifndef TALER_KYCLOGIC_PLUGIN_H
#define TALER_KYCLOGIC_PLUGIN_H

#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>


/**
 * Plugin-internal specification of the configuration
 * of the plugin for a given KYC provider.
 */
struct TEH_KYCLOGIC_ProviderDetails;

/**
 * Handle for an initiation operation.
 */
struct TEH_KYCLOGIC_InitiateHandle;


/**
 * Function called with the result of a KYC initiation
 * operation.
 *
 * @param ec #TALER_EC_NONE on success
 * @param redirect_url set to where to redirect the user on success, NULL on failure
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param error_msg_hint set to additional details to return to user, NULL on success
 */
typedef void
(*TEH_KYCLOGIC_InitiateCallback)(
  enum TALER_ErrorCode ec,
  const char *redirect_url,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_msg_hint);


/**
 * @brief The plugin API, returned from the plugin's "init" function.
 * The argument given to "init" is simply a configuration handle.
 */
struct TALER_KYCLOGIC_Plugin
{

  /**
   * Closure for all callbacks.
   */
  void *cls;

  /**
   * Name of the library which generated this plugin.  Set by the
   * plugin loader.
   */
  char *library_name;

  /**
   * Load the configuration of the KYC provider.
   *
   * @param provider_section_name configuration section to parse
   * @return NULL if configuration is invalid
   */
  struct TEH_KYCLOGIC_ProviderDetails *
  (*load_configuration)(const char *provider_section_name);

  /**
   * Release configuration resources previously loaded
   *
   * @param[in] pd configuration to release
   */
  void
  (*unload_configuration)(struct TEH_KYCLOGIC_ProviderDetails *pd);


  /**
   * Initiate KYC check.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param pd provider configuration details
   * @param account_id which account to trigger process for
   * @return handle to cancel operation early
   */
  struct TEH_KYCLOGIC_InitiateHandle *
  (*initiate)(void *cls,
              const struct TEH_KYCLOGIC_ProviderDetails *pd,
              const struct TALER_PaytoHashP *account_id,
              TEH_KYCLOGIC_InitiateCallback cb,
              void *cb_cls);

  /**
   * Cancel KYC check initiation.
   *
   * @param[in] ih handle of operation to cancel
   */
  void
  (*initiate_cancel) (struct TEH_KYCLOGIC_InitiateHandle *ih);

  // FIXME: add callback pair for kyc_proof

  // FIXME: add callback pair for kyc_webhook

};


#endif /* _TALER_KYCLOGIC_PLUGIN_H */
