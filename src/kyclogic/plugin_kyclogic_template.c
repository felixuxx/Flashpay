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
 * @file plugin_kyclogic_template.c
 * @brief template for an authentication flow logic
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_kyclogic_plugin.h"
#include <taler/taler_mhd_lib.h>
#include <taler/taler_json_lib.h>
#include <regex.h>
#include "taler_util.h"


/**
 * Saves the state of a plugin.
 */
struct PluginState
{

  /**
   * Our base URL.
   */
  char *exchange_base_url;

  /**
   * Our global configuration.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Context for CURL operations (useful to the event loop)
   */
  struct GNUNET_CURL_Context *curl_ctx;

  /**
   * Context for integrating @e curl_ctx with the
   * GNUnet event loop.
   */
  struct GNUNET_CURL_RescheduleContext *curl_rc;

};


/**
 * Keeps the plugin-specific state for
 * a given configuration section.
 */
struct TALER_KYCLOGIC_ProviderDetails
{

  /**
   * Overall plugin state.
   */
  struct PluginState *ps;

};


/**
 * Handle for an initiation operation.
 */
struct TALER_KYCLOGIC_InitiateHandle
{

  /**
   * Hash of the payto:// URI we are initiating
   * the KYC for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * UUID being checked.
   */
  uint64_t legitimization_uuid;

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Continuation to call.
   */
  TALER_KYCLOGIC_InitiateCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;
};


/**
 * Handle for an KYC proof operation.
 */
struct TALER_KYCLOGIC_ProofHandle
{

  /**
   * Overall plugin state.
   */
  struct PluginState *ps;

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

  /**
   * Continuation to call.
   */
  TALER_KYCLOGIC_ProofCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;
};


/**
 * Handle for an KYC Web hook operation.
 */
struct TALER_KYCLOGIC_WebhookHandle
{

  /**
   * Continuation to call when done.
   */
  TALER_KYCLOGIC_WebhookCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Task for asynchronous execution.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Overall plugin state.
   */
  struct PluginState *ps;

  /**
   * Our configuration details.
   */
  const struct TALER_KYCLOGIC_ProviderDetails *pd;

};


/**
 * Load the configuration of the KYC provider.
 *
 * @param cls closure
 * @param provider_section_name configuration section to parse
 * @return NULL if configuration is invalid
 */
static struct TALER_KYCLOGIC_ProviderDetails *
template_load_configuration (void *cls,
                             const char *provider_section_name)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_ProviderDetails *pd;

  pd = GNUNET_new (struct TALER_KYCLOGIC_ProviderDetails);
  pd->ps = ps;
  GNUNET_break (0); // FIXME: parse config here!
  return pd;
}


/**
 * Release configuration resources previously loaded
 *
 * @param[in] pd configuration to release
 */
static void
template_unload_configuration (struct TALER_KYCLOGIC_ProviderDetails *pd)
{
  GNUNET_free (pd);
}


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
static struct TALER_KYCLOGIC_InitiateHandle *
template_initiate (void *cls,
                   const struct TALER_KYCLOGIC_ProviderDetails *pd,
                   const struct TALER_PaytoHashP *account_id,
                   uint64_t legitimization_uuid,
                   TALER_KYCLOGIC_InitiateCallback cb,
                   void *cb_cls)
{
  struct TALER_KYCLOGIC_InitiateHandle *ih;

  ih = GNUNET_new (struct TALER_KYCLOGIC_InitiateHandle);
  ih->legitimization_uuid = legitimization_uuid;
  ih->cb = cb;
  ih->cb_cls = cb_cls;
  ih->h_payto = *account_id;
  ih->pd = pd;
  GNUNET_break (0); // FIXME: add actual initiation logic!
  return ih;
}


/**
 * Cancel KYC check initiation.
 *
 * @param[in] ih handle of operation to cancel
 */
static void
template_initiate_cancel (struct TALER_KYCLOGIC_InitiateHandle *ih)
{
  GNUNET_break (0); // FIXME: add cancel logic here
  GNUNET_free (ih);
}


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
static struct TALER_KYCLOGIC_ProofHandle *
template_proof (void *cls,
                const struct TALER_KYCLOGIC_ProviderDetails *pd,
                const char *url_path,
                struct MHD_Connection *connection,
                const struct TALER_PaytoHashP *account_id,
                const char *provider_user_id,
                const char *provider_legitimization_id,
                TALER_KYCLOGIC_ProofCallback cb,
                void *cb_cls)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_ProofHandle *ph;

  ph = GNUNET_new (struct TALER_KYCLOGIC_ProofHandle);
  ph->ps = ps;
  ph->pd = pd;
  ph->cb = cb;
  ph->cb_cls = cb_cls;

  GNUNET_break (0); // FIXME: start check!
  return ph;
}


/**
 * Cancel KYC proof.
 *
 * @param[in] ph handle of operation to cancel
 */
static void
template_proof_cancel (struct TALER_KYCLOGIC_ProofHandle *ph)
{
  GNUNET_break (0); // FIXME: stop activities...
  GNUNET_free (ph);
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
static struct TALER_KYCLOGIC_WebhookHandle *
template_webhook (void *cls,
                  const struct TALER_KYCLOGIC_ProviderDetails *pd,
                  TALER_KYCLOGIC_ProviderLookupCallback plc,
                  void *plc_cls,
                  const char *http_method,
                  const char *const url_path[],
                  struct MHD_Connection *connection,
                  const json_t *body,
                  TALER_KYCLOGIC_WebhookCallback cb,
                  void *cb_cls)
{
  struct PluginState *ps = cls;
  struct TALER_KYCLOGIC_WebhookHandle *wh;

  wh = GNUNET_new (struct TALER_KYCLOGIC_WebhookHandle);
  wh->cb = cb;
  wh->cb_cls = cb_cls;
  wh->ps = ps;
  wh->pd = pd;
  GNUNET_break (0); /* FIXME: start activity */
  return wh;
}


/**
 * Cancel KYC webhook execution.
 *
 * @param[in] wh handle of operation to cancel
 */
static void
template_webhook_cancel (struct TALER_KYCLOGIC_WebhookHandle *wh)
{
  GNUNET_break (0); /*  FIXME: stop activity */
  GNUNET_free (wh);
}


/**
 * Initialize Template.0 KYC logic plugin
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_KYCLOGIC_Plugin`
 */
void *
libtaler_plugin_kyclogic_template_init (void *cls)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_KYCLOGIC_Plugin *plugin;
  struct PluginState *ps;

  ps = GNUNET_new (struct PluginState);
  ps->cfg = cfg;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &ps->exchange_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    GNUNET_free (ps);
    return NULL;
  }

  ps->curl_ctx
    = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                        &ps->curl_rc);
  if (NULL == ps->curl_ctx)
  {
    GNUNET_break (0);
    GNUNET_free (ps->exchange_base_url);
    GNUNET_free (ps);
    return NULL;
  }
  ps->curl_rc = GNUNET_CURL_gnunet_rc_create (ps->curl_ctx);

  plugin = GNUNET_new (struct TALER_KYCLOGIC_Plugin);
  plugin->cls = ps;
  plugin->load_configuration
    = &template_load_configuration;
  plugin->unload_configuration
    = &template_unload_configuration;
  plugin->initiate
    = &template_initiate;
  plugin->initiate_cancel
    = &template_initiate_cancel;
  plugin->proof
    = &template_proof;
  plugin->proof_cancel
    = &template_proof_cancel;
  plugin->webhook
    = &template_webhook;
  plugin->webhook_cancel
    = &template_webhook_cancel;
  return plugin;
}


/**
 * Unload authorization plugin
 *
 * @param cls a `struct TALER_KYCLOGIC_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_kyclogic_template_done (void *cls)
{
  struct TALER_KYCLOGIC_Plugin *plugin = cls;
  struct PluginState *ps = plugin->cls;

  if (NULL != ps->curl_ctx)
  {
    GNUNET_CURL_fini (ps->curl_ctx);
    ps->curl_ctx = NULL;
  }
  if (NULL != ps->curl_rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (ps->curl_rc);
    ps->curl_rc = NULL;
  }
  GNUNET_free (ps->exchange_base_url);
  GNUNET_free (ps);
  GNUNET_free (plugin);
  return NULL;
}
