/*
  This file is part of GNU Taler
  Copyright (C) 2022 Taler Systems SA

  Taler is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  Taler is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  Taler; see the file COPYING.GPL.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file plugin_kyclogic_oauth2.c
 * @brief oauth2.0 based authentication flow logic
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_kyclogic_plugin.h"
#include <taler/taler_mhd_lib.h>
#include <taler/taler_json_lib.h>
#include <regex.h>
#include "taler_util.h"

/**
 * Keeps the plugin-specific state for
 * a given configuration section.
 */
struct TALER_KYCLOGIC_ProviderDetails
{

};


/**
 * Handle for an initiation operation.
 */
struct TALER_KYCLOGIC_InitiateHandle
{
};


/**
 * Handle for an KYC proof operation.
 */
struct TALER_KYCLOGIC_ProofHandle
{
};


/**
 * Handle for an KYC Web hook operation.
 */
struct TALER_KYCLOGIC_WebhookHandle
{
};


/**
 * Saves the state of a plugin.
 */
struct PluginState
{

  /**
   * Our global configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

};


/**
 * Load the configuration of the KYC provider.
 *
 * @param cls closure
 * @param provider_section_name configuration section to parse
 * @return NULL if configuration is invalid
 */
static struct TALER_KYCLOGIC_ProviderDetails *
oauth2_load_configuration (void *cls,
                           const char *provider_section_name)
{
  return NULL;
}


/**
 * Release configuration resources previously loaded
 *
 * @param[in] pd configuration to release
 */
static void
oauth2_unload_configuration (struct TALER_KYCLOGIC_ProviderDetails *pd)
{
}


/**
 * Initiate KYC check.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param account_id which account to trigger process for
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_InitiateHandle *
oauth2_initiate (void *cls,
                 const struct TALER_KYCLOGIC_ProviderDetails *pd,
                 const struct TALER_PaytoHashP *account_id,
                 TALER_KYCLOGIC_InitiateCallback cb,
                 void *cb_cls)
{
  return NULL;
}


/**
 * Cancel KYC check initiation.
 *
 * @param[in] ih handle of operation to cancel
 */
static void
oauth2_initiate_cancel (struct TALER_KYCLOGIC_InitiateHandle *ih)
{
}


/**
 * Check KYC status and return status to human.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pd provider configuration details
 * @param account_id which account to trigger process for
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel operation early
 */
static struct TALER_KYCLOGIC_ProofHandle *
oauth2_proof (void *cls,
              const struct TALER_KYCLOGIC_ProviderDetails *pd,
              const struct TALER_PaytoHashP *account_id,
              const char *provider_user_id,
              const char *provider_legitimization_id,
              TALER_KYCLOGIC_ProofCallback cb,
              void *cb_cls)
{
  return NULL;
}


/**
 * Cancel KYC proof.
 *
 * @param[in] ph handle of operation to cancel
 */
static void
oauth2_proof_cancel (struct TALER_KYCLOGIC_ProofHandle *ph)
{
}


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
static struct TALER_KYCLOGIC_InitiateHandle *
oauth2_webhook (void *cls,
                const struct TALER_KYCLOGIC_ProviderDetails *pd,
                TALER_KYCLOGIC_ProviderLookupCallback plc,
                void *plc_cls,
                const char *http_method,
                const char *url_path,
                struct MHD_Connection *connection,
                size_t body_size,
                const void *body,
                TALER_KYCLOGIC_WebhookCallback cb,
                void *cb_cls)
{
  GNUNET_break_op (0);
  return NULL;
}


/**
 * Cancel KYC webhook execution.
 *
 * @param[in] wh handle of operation to cancel
 */
static void
oauth2_webhook_cancel (struct TALER_KYCLOGIC_WebhookHandle *wh)
{
}


/**
 * Initialize OAuth2.0 KYC logic plugin
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_KYCLOGIC_Plugin`
 */
void *
libtaler_plugin_kyclogic_oauth2_init (void *cls)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_KYCLOGIC_Plugin *plugin;
  struct PluginState *ps;

  ps = GNUNET_new (struct PluginState);
  ps->cfg = cfg;
  plugin = GNUNET_new (struct TALER_KYCLOGIC_Plugin);
  plugin->cls = ps;
  plugin->load_configuration
    = &oauth2_load_configuration;
  plugin->unload_configuration
    = &oauth2_unload_configuration;
  plugin->initiate
    = &oauth2_initiate;
  plugin->initiate_cancel
    = &oauth2_initiate_cancel;
  plugin->proof
    = &oauth2_proof;
  plugin->proof_cancel
    = &oauth2_proof_cancel;
  plugin->webhook
    = &oauth2_webhook;
  plugin->webhook_cancel
    = &oauth2_webhook_cancel;
  return plugin;
}


/**
 * Unload authorization plugin
 *
 * @param cls a `struct TALER_KYCLOGIC_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_kyclogic_oauth2_done (void *cls)
{
  struct TALER_KYCLOGIC_Plugin *plugin = cls;
  struct PluginState *ps = plugin->cls;

  GNUNET_free (ps);
  GNUNET_free (plugin);
  return NULL;
}
