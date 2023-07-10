/*
  This file is part of TALER
  (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_get_exchange.c
 * @brief Command to get an exchange handle
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "get exchange" CMD.
 */
struct GetExchangeState
{

  /**
   * Master private key of the exchange.
   */
  struct TALER_MasterPrivateKeyP master_priv;

  /**
   * Our interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Exchange handle we produced.
   */
  struct TALER_EXCHANGE_GetKeysHandle *exchange;

  /**
   * Keys of the exchange.
   */
  struct TALER_EXCHANGE_Keys *keys;

  /**
   * URL of the exchange.
   */
  char *exchange_url;

  /**
   * Filename of the master private key of the exchange.
   */
  char *master_priv_file;

  /**
   * Label of a command to use to obtain existing
   * keys.
   */
  const char *last_keys_ref;

  /**
   * Last denomination date we received when doing this request.
   */
  struct GNUNET_TIME_Timestamp my_denom_date;

  /**
   * Are we waiting for /keys before continuing?
   */
  bool wait_for_keys;
};


/**
 * Function called with information about who is auditing
 * a particular exchange and what keys the exchange is using.
 *
 * @param cls closure
 * @param kr response from /keys
 * @param[in] keys the keys of the exchange
 */
static void
cert_cb (void *cls,
         const struct TALER_EXCHANGE_KeysResponse *kr,
         struct TALER_EXCHANGE_Keys *keys)
{
  struct GetExchangeState *ges = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &kr->hr;
  struct TALER_TESTING_Interpreter *is = ges->is;

  ges->exchange = NULL;
  ges->keys = keys;
  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    if (ges->wait_for_keys)
    {
      ges->wait_for_keys = false;
      TALER_TESTING_interpreter_next (is);
      return;
    }
    ges->my_denom_date = kr->details.ok.keys->last_denom_issue_date;
    return;
  default:
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "/keys responded with HTTP status %u\n",
                hr->http_status);
    if (ges->wait_for_keys)
    {
      ges->wait_for_keys = false;
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    return;
  }
}


/**
 * Run the "get_exchange" command.
 *
 * @param cls closure.
 * @param cmd the command currently being executed.
 * @param is the interpreter state.
 */
static void
get_exchange_run (void *cls,
                  const struct TALER_TESTING_Command *cmd,
                  struct TALER_TESTING_Interpreter *is)
{
  struct GetExchangeState *ges = cls;
  struct TALER_EXCHANGE_Keys *xkeys = NULL;

  (void) cmd;
  if (NULL == ges->exchange_url)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (NULL != ges->last_keys_ref)
  {
    const struct TALER_TESTING_Command *state_cmd;
    struct TALER_EXCHANGE_Keys *old_keys;
    const char *exchange_url;
    json_t *s_keys;

    state_cmd
      = TALER_TESTING_interpreter_lookup_command (is,
                                                  ges->last_keys_ref);
    if (NULL == state_cmd)
    {
      /* Command providing serialized keys not found.  */
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_keys (state_cmd,
                                      &old_keys))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (NULL == old_keys)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_exchange_url (state_cmd,
                                              &exchange_url))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (0 != strcmp (exchange_url,
                     ges->exchange_url))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    s_keys = TALER_EXCHANGE_keys_to_json (old_keys);
    if (NULL == s_keys)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    xkeys = TALER_EXCHANGE_keys_from_json (s_keys);
    if (NULL == xkeys)
    {
      GNUNET_break (0);
      json_dumpf (s_keys,
                  stderr,
                  JSON_INDENT (2));
      json_decref (s_keys);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    json_decref (s_keys);
  }
  if (NULL != ges->master_priv_file)
  {
    if (GNUNET_SYSERR ==
        GNUNET_CRYPTO_eddsa_key_from_file (ges->master_priv_file,
                                           GNUNET_YES,
                                           &ges->master_priv.eddsa_priv))
    {
      GNUNET_break (0);
      TALER_EXCHANGE_keys_decref (xkeys);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }
  ges->is = is;
  ges->exchange
    = TALER_EXCHANGE_get_keys (TALER_TESTING_interpreter_get_context (is),
                               ges->exchange_url,
                               xkeys,
                               &cert_cb,
                               ges);
  TALER_EXCHANGE_keys_decref (xkeys);
  if (NULL == ges->exchange)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (! ges->wait_for_keys)
    TALER_TESTING_interpreter_next (is);
}


/**
 * Cleanup the state.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
get_exchange_cleanup (void *cls,
                      const struct TALER_TESTING_Command *cmd)
{
  struct GetExchangeState *ges = cls;

  if (NULL != ges->exchange)
  {
    TALER_EXCHANGE_get_keys_cancel (ges->exchange);
    ges->exchange = NULL;
  }
  TALER_EXCHANGE_keys_decref (ges->keys);
  ges->keys = NULL;
  GNUNET_free (ges->master_priv_file);
  GNUNET_free (ges->exchange_url);
  GNUNET_free (ges);
}


/**
 * Offer internal data to a "get_exchange" CMD state to other commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
get_exchange_traits (void *cls,
                     const void **ret,
                     const char *trait,
                     unsigned int index)
{
  struct GetExchangeState *ges = cls;
  unsigned int off = (NULL == ges->master_priv_file) ? 1 : 0;

  if (NULL != ges->keys)
  {
    struct TALER_TESTING_Trait traits[] = {
      TALER_TESTING_make_trait_master_priv (&ges->master_priv),
      TALER_TESTING_make_trait_master_pub (&ges->keys->master_pub),
      TALER_TESTING_make_trait_keys (ges->keys),
      TALER_TESTING_make_trait_exchange_url (ges->exchange_url),
      TALER_TESTING_make_trait_timestamp (0,
                                          &ges->my_denom_date),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait (&traits[off],
                                    ret,
                                    trait,
                                    index);
  }
  else
  {
    struct TALER_TESTING_Trait traits[] = {
      TALER_TESTING_make_trait_master_priv (&ges->master_priv),
      TALER_TESTING_make_trait_exchange_url (ges->exchange_url),
      TALER_TESTING_make_trait_timestamp (0,
                                          &ges->my_denom_date),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait (&traits[off],
                                    ret,
                                    trait,
                                    index);
  }
}


/**
 * Get the base URL of the exchange from @a cfg.
 *
 * @param cfg configuration to evaluate
 * @return base URL of the exchange according to @a cfg
 */
static char *
get_exchange_base_url (
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *exchange_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return NULL;
  }
  return exchange_url;
}


/**
 * Get the file name of the master private key file of the exchange from @a
 * cfg.
 *
 * @param cfg configuration to evaluate
 * @return base URL of the exchange according to @a cfg
 */
static char *
get_exchange_master_priv_file (
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *fn;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchange-offline",
                                               "MASTER_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-offline",
                               "MASTER_PRIV_FILE");
    return NULL;
  }
  return fn;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_get_exchange (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  const char *last_keys_ref,
  bool wait_for_keys,
  bool load_private_key)
{
  struct GetExchangeState *ges;

  ges = GNUNET_new (struct GetExchangeState);
  ges->exchange_url = get_exchange_base_url (cfg);
  ges->last_keys_ref = last_keys_ref;
  if (load_private_key)
    ges->master_priv_file = get_exchange_master_priv_file (cfg);
  ges->wait_for_keys = wait_for_keys;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ges,
      .label = label,
      .run = &get_exchange_run,
      .cleanup = &get_exchange_cleanup,
      .traits = &get_exchange_traits,
      .name = "exchange"
    };

    return cmd;
  }
}
