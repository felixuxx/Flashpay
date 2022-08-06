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
#include <gnunet/gnunet_db_lib.h>
#include "taler_util.h"


/**
 * Possible states of a KYC check.
 */
enum TALER_KYCLOGIC_KycStatus
{

  /**
   * The provider has passed the customer.
   */
  TALER_KYCLOGIC_STATUS_SUCCESS = 0,

  /**
   * Something to do with the user (bit!).
   */
  TALER_KYCLOGIC_STATUS_USER = 1,

  /**
   * Something to do with the provider (bit!).
   */
  TALER_KYCLOGIC_STATUS_PROVIDER = 2,

  /**
   * The interaction ended in definitive failure.
   * (kind of with both parties).
   */
  TALER_KYCLOGIC_STATUS_FAILED
    = TALER_KYCLOGIC_STATUS_USER
      | TALER_KYCLOGIC_STATUS_PROVIDER,

  /**
   * The interaction is still ongoing.
   */
  TALER_KYCLOGIC_STATUS_PENDING = 4,

  /**
   * One of the parties hat a temporary failure.
   */
  TALER_KYCLOGIC_STATUS_ABORTED = 8,

  /**
   * The interaction with the user is ongoing.
   */
  TALER_KYCLOGIC_STATUS_USER_PENDING
    = TALER_KYCLOGIC_STATUS_USER
      | TALER_KYCLOGIC_STATUS_PENDING,

  /**
   * The provider is still checking.
   */
  TALER_KYCLOGIC_STATUS_PROVIDER_PENDING
    = TALER_KYCLOGIC_STATUS_PROVIDER
      | TALER_KYCLOGIC_STATUS_PENDING,

  /**
   * The user aborted the check (possibly recoverable)
   * or made some other type of (recoverable) mistake.
   */
  TALER_KYCLOGIC_STATUS_USER_ABORTED
    = TALER_KYCLOGIC_STATUS_USER
      | TALER_KYCLOGIC_STATUS_ABORTED,

  /**
   * The provider had an (internal) failure.
   */
  TALER_KYCLOGIC_STATUS_PROVIDER_FAILED
    = TALER_KYCLOGIC_STATUS_PROVIDER
      | TALER_KYCLOGIC_STATUS_ABORTED,

  /**
   * Return code set to not update the KYC status
   * at all.
   */
  TALER_KYCLOGIC_STATUS_KEEP = 16
};


/**
 * Plugin-internal specification of the configuration
 * of the plugin for a given KYC provider.
 */
struct TALER_KYCLOGIC_ProviderDetails;

/**
 * Handle for an initiation operation.
 */
struct TALER_KYCLOGIC_InitiateHandle;

/**
 * Handle for an KYC proof operation.
 */
struct TALER_KYCLOGIC_ProofHandle;

/**
 * Handle for an KYC Web hook operation.
 */
struct TALER_KYCLOGIC_WebhookHandle;


/**
 * Function called with the result of a KYC initiation
 * operation.
 *
 * @param cls closure
 * @param ec #TALER_EC_NONE on success
 * @param redirect_url set to where to redirect the user on success, NULL on failure
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param error_msg_hint set to additional details to return to user, NULL on success
 */
typedef void
(*TALER_KYCLOGIC_InitiateCallback)(
  void *cls,
  enum TALER_ErrorCode ec,
  const char *redirect_url,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_msg_hint);


/**
 * Function called with the result of a proof check
 * operation.
 *
 * Note that the "decref" for the @a response
 * will be done by the plugin.
 *
 * @param cls closure
 * @param status KYC status
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param expiration until when is the KYC check valid
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 */
typedef void
(*TALER_KYCLOGIC_ProofCallback)(
  void *cls,
  enum TALER_KYCLOGIC_KycStatus status,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration,
  unsigned int http_status,
  struct MHD_Response *response);


/**
 * Function called with the result of a webhook
 * operation.
 *
 * Note that the "decref" for the @a response
 * will be done by the plugin.
 *
 * @param cls closure
 * @param account_id account the webhook was about
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param status KYC status
 * @param expiration until when is the KYC check valid
 * @param http_status HTTP status code of @a response
 * @param[in] response to return to the HTTP client
 */
typedef void
(*TALER_KYCLOGIC_WebhookCallback)(
  void *cls,
  const struct TALER_PaytoHashP *account_id,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  enum TALER_KYCLOGIC_KycStatus status,
  struct GNUNET_TIME_Absolute expiration,
  unsigned int http_status,
  struct MHD_Response *response);


/**
 * Function the plugin can use to lookup an
 * @a h_payto by @a provider_legitimization_id.
 * Must match the `kyc_provider_account_lookup`
 * of the exchange's database plugin.
 *
 * @param cls closure
 * @param provider_section
 * @param provider_legitimization_id legi to look up
 * @param[out] h_payto where to write the result
 * @return database transaction status
 */
typedef enum GNUNET_DB_QueryStatus
(*TALER_KYCLOGIC_ProviderLookupCallback)(
  void *cls,
  const char *provider_section,
  const char *provider_legitimization_id,
  struct TALER_PaytoHashP *h_payto);


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
   * @param cls closure
   * @param provider_section_name configuration section to parse
   * @return NULL if configuration is invalid
   */
  struct TALER_KYCLOGIC_ProviderDetails *
  (*load_configuration)(void *cls,
                        const char *provider_section_name);

  /**
   * Release configuration resources previously loaded
   *
   * @param[in] pd configuration to release
   */
  void
  (*unload_configuration)(struct TALER_KYCLOGIC_ProviderDetails *pd);


  /**
   * Initiate KYC check.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param pd provider configuration details
   * @param account_id which account to trigger process for
   * @param legitimization_uuid unique ID for the legitimization process
   * @param cb function to call with the result
   * @param cb_cls closure for @a cb
   * @return handle to cancel operation early
   */
  struct TALER_KYCLOGIC_InitiateHandle *
  (*initiate)(void *cls,
              const struct TALER_KYCLOGIC_ProviderDetails *pd,
              const struct TALER_PaytoHashP *account_id,
              uint64_t legitimization_uuid,
              TALER_KYCLOGIC_InitiateCallback cb,
              void *cb_cls);


  /**
   * Cancel KYC check initiation.
   *
   * @param[in] ih handle of operation to cancel
   */
  void
  (*initiate_cancel) (struct TALER_KYCLOGIC_InitiateHandle *ih);


  /**
   * Check KYC status and return status to human.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param pd provider configuration details
   * @param url_path rest of the URL after `/kyc-webhook/`
   * @param connection MHD connection object (for HTTP headers)
   * @param account_id which account to trigger process for
   * @param provider_user_id user ID (or NULL) the proof is for
   * @param provider_legitimization_id legitimization ID the proof is for
   * @param cb function to call with the result
   * @param cb_cls closure for @a cb
   * @return handle to cancel operation early
  */
  struct TALER_KYCLOGIC_ProofHandle *
  (*proof)(void *cls,
           const struct TALER_KYCLOGIC_ProviderDetails *pd,
           const char *url_path,
           struct MHD_Connection *connection,
           const struct TALER_PaytoHashP *account_id,
           const char *provider_user_id,
           const char *provider_legitimization_id,
           TALER_KYCLOGIC_ProofCallback cb,
           void *cb_cls);


  /**
   * Cancel KYC proof.
   *
   * @param[in] ph handle of operation to cancel
   */
  void
  (*proof_cancel) (struct TALER_KYCLOGIC_ProofHandle *ph);


  /**
   * Check KYC status and return result for Webhook.
   *
   * @param cls the @e cls of this struct with the plugin-specific state
   * @param pd provider configuration details
   * @param plc callback to lookup accounts with
   * @param plc_cls closure for @a plc
   * @param http_method HTTP method used for the webhook
   * @param url_path rest of the URL after `/kyc-webhook/`
   * @param connection MHD connection object (for HTTP headers)
   * @param body_size number of bytes in @a body
   * @param body HTTP request body
   * @param cb function to call with the result
   * @param cb_cls closure for @a cb
   * @return handle to cancel operation early
   */
  struct TALER_KYCLOGIC_WebhookHandle *
  (*webhook)(void *cls,
             const struct TALER_KYCLOGIC_ProviderDetails *pd,
             TALER_KYCLOGIC_ProviderLookupCallback plc,
             void *plc_cls,
             const char *http_method,
             const char *url_path,
             struct MHD_Connection *connection,
             size_t body_size,
             const void *body,
             TALER_KYCLOGIC_WebhookCallback cb,
             void *cb_cls);


  /**
   * Cancel KYC webhook execution.
   *
   * @param[in] wh handle of operation to cancel
   */
  void
  (*webhook_cancel) (struct TALER_KYCLOGIC_WebhookHandle *wh);

};


#endif /* _TALER_KYCLOGIC_PLUGIN_H */
