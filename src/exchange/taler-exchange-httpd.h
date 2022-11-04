/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file taler-exchange-httpd.h
 * @brief Global declarations for the exchange
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_H
#define TALER_EXCHANGE_HTTPD_H

#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_crypto_lib.h"
#include "taler_kyclogic_plugin.h"
#include "taler_extensions.h"
#include <gnunet/gnunet_mhd_compat.h>


/* ************* NOTE: OLD KYC logic,***********
   new logic is in taler-exchange-httpd_kyc.h!
   ********************************************* */

/**
 * Enumeration for our KYC modes.
 */
enum TEH_KycMode
{
  /**
   * KYC is disabled.
   */
  TEH_KYC_NONE = 0,

  /**
   * We use Oauth2.0.
   */
  TEH_KYC_OAUTH2 = 1
};


/**
 * Structure describing our KYC configuration.
 */
struct TEH_KycOptions
{
  /**
   * What KYC mode are we in?
   */
  enum TEH_KycMode mode;

  /**
   * Maximum amount that can be withdrawn in @e withdraw_period without
   * needing KYC.
   * Only valid if @e mode is not #TEH_KYC_NONE and
   * if @e withdraw_period is non-zero.
   */
  struct TALER_Amount withdraw_limit;

  /**
   * Maximum balance a wallet can hold without
   * needing KYC.
   * Only valid if @e mode is not #TEH_KYC_NONE and
   * if the amount specified is valid.
   */
  struct TALER_Amount wallet_balance_limit;

  /**
   * Time period over which @e withdraw_limit applies.
   * Only valid if @e mode is not #TEH_KYC_NONE.
   */
  struct GNUNET_TIME_Relative withdraw_period;

  /**
   * Details depending on @e mode.
   */
  union
  {

    /**
     * Configuration details if @e mode is #TEH_KYC_OAUTH2.
     */
    struct
    {

      /**
       * URL of the OAuth2.0 endpoint for KYC checks.
       * (token/auth)
       */
      char *auth_url;

      /**
       * URL of the OAuth2.0 endpoint for KYC checks.
       */
      char *login_url;

      /**
       * URL of the user info access endpoint.
       */
      char *info_url;

      /**
       * Our client ID for OAuth2.0.
       */
      char *client_id;

      /**
       * Our client secret for OAuth2.0.
       */
      char *client_secret;

      /**
       * Where to redirect clients after the
       * Web-based KYC process is done?
       */
      char *post_kyc_redirect_url;

    } oauth2;

  } details;
};


extern struct TEH_KycOptions TEH_kyc_config;

/**
 * How long is caching /keys allowed at most?
 */
extern struct GNUNET_TIME_Relative TEH_max_keys_caching;

/**
 * How long is the delay before we close reserves?
 */
extern struct GNUNET_TIME_Relative TEH_reserve_closing_delay;

/**
 * The exchange's configuration.
 */
extern const struct GNUNET_CONFIGURATION_Handle *TEH_cfg;

/**
 * Main directory with exchange data.
 */
extern char *TEH_exchange_directory;

/**
 * -I command-line flag given?
 */
extern int TEH_check_invariants_flag;

/**
 * Are clients allowed to request /keys for times other than the
 * current time? Allowing this could be abused in a DoS-attack
 * as building new /keys responses is expensive. Should only be
 * enabled for testcases, development and test systems.
 */
extern int TEH_allow_keys_timetravel;

/**
 * Main directory with revocation data.
 */
extern char *TEH_revocation_directory;

/**
 * True if we should commit suicide once all active
 * connections are finished. Also forces /keys requests
 * to terminate if they are long-polling.
 */
extern bool TEH_suicide;

/**
 * Master public key (according to the
 * configuration in the exchange directory).
 */
extern struct TALER_MasterPublicKeyP TEH_master_public_key;

/**
 * Our DB plugin.
 */
extern struct TALER_EXCHANGEDB_Plugin *TEH_plugin;

/**
 * Our currency.
 */
extern char *TEH_currency;

/**
 * Our (externally visible) base URL.
 */
extern char *TEH_base_url;

/**
 * Are we shutting down?
 */
extern volatile bool MHD_terminating;

/**
 * Context for all CURL operations (useful to the event loop)
 */
extern struct GNUNET_CURL_Context *TEH_curl_ctx;

/*
 * Signature of the offline master key of all enabled extensions' configuration
 */
extern struct TALER_MasterSignatureP TEH_extensions_sig;
extern bool TEH_extensions_signed;

/**
 * @brief Struct describing an URL and the handler for it.
 */
struct TEH_RequestHandler;


/**
 * @brief Context in which the exchange is processing
 *        all requests
 */
struct TEH_RequestContext
{

  /**
   * Async Scope ID associated with this request.
   */
  struct GNUNET_AsyncScopeId async_scope_id;

  /**
   * When was this request started?
   */
  struct GNUNET_TIME_Absolute start_time;

  /**
   * Opaque parsing context.
   */
  void *opaque_post_parsing_context;

  /**
   * Request handler responsible for this request.
   */
  const struct TEH_RequestHandler *rh;

  /**
   * Request URL (for logging).
   */
  const char *url;

  /**
   * Connection we are processing.
   */
  struct MHD_Connection *connection;

  /**
   * @e rh-specific cleanup routine. Function called
   * upon completion of the request that should
   * clean up @a rh_ctx. Can be NULL.
   */
  void
  (*rh_cleaner)(struct TEH_RequestContext *rc);

  /**
   * @e rh-specific context. Place where the request
   * handler can associate state with this request.
   * Can be NULL.
   */
  void *rh_ctx;
};


/**
 * @brief Struct describing an URL and the handler for it.
 */
struct TEH_RequestHandler
{

  /**
   * URL the handler is for (first part only).
   */
  const char *url;

  /**
   * Method the handler is for.
   */
  const char *method;

  /**
   * Callbacks for handling of the request. Which one is used
   * depends on @e method.
   */
  union
  {
    /**
     * Function to call to handle a GET requests (and those
     * with @e method NULL).
     *
     * @param rc context for the request
     * @param mime_type the @e mime_type for the reply (hint, can be NULL)
     * @param args array of arguments, needs to be of length @e args_expected
     * @return MHD result code
     */
    MHD_RESULT
    (*get)(struct TEH_RequestContext *rc,
           const char *const args[]);


    /**
     * Function to call to handle a POST request.
     *
     * @param rc context for the request
     * @param json uploaded JSON data
     * @param args array of arguments, needs to be of length @e args_expected
     * @return MHD result code
     */
    MHD_RESULT
    (*post)(struct TEH_RequestContext *rc,
            const json_t *root,
            const char *const args[]);

  } handler;

  /**
   * Number of arguments this handler expects in the @a args array.
   */
  unsigned int nargs;

  /**
   * Is the number of arguments given in @e nargs only an upper bound,
   * and calling with fewer arguments could be OK?
   */
  bool nargs_is_upper_bound;

  /**
   * Mime type to use in reply (hint, can be NULL).
   */
  const char *mime_type;

  /**
   * Raw data for the @e handler, can be NULL for none provided.
   */
  const void *data;

  /**
   * Number of bytes in @e data, 0 for data is 0-terminated (!).
   */
  size_t data_size;

  /**
   * Default response code. 0 for none provided.
   */
  unsigned int response_code;
};


/* Age restriction configuration */
extern bool TEH_age_restriction_enabled;
extern struct TALER_AgeRestrictionConfig TEH_age_restriction_config;

#endif
