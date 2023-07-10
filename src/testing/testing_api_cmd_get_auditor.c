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
 * @file testing/testing_api_cmd_get_auditor.c
 * @brief Command to get an auditor handle
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "get auditor" CMD.
 */
struct GetAuditorState
{

  /**
   * Private key of the auditor.
   */
  struct TALER_AuditorPrivateKeyP auditor_priv;

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * Our interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Auditor handle used to get the configuration.
   */
  struct TALER_AUDITOR_GetConfigHandle *auditor;

  /**
   * URL of the auditor.
   */
  char *auditor_url;

  /**
   * Filename of the master private key of the auditor.
   */
  char *priv_file;

};


/**
 * Function called with information about the auditor.
 *
 * @param cls closure
 * @param vr response data
 */
static void
version_cb (
  void *cls,
  const struct TALER_AUDITOR_ConfigResponse *vr)
{
  struct GetAuditorState *gas = cls;

  gas->auditor = NULL;
  if (MHD_HTTP_OK != vr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (gas->is,
                                     vr->hr.http_status,
                                     MHD_HTTP_OK);
    return;
  }
  if ( (NULL != gas->priv_file) &&
       (0 != GNUNET_memcmp (&gas->auditor_pub,
                            &vr->details.ok.vi.auditor_pub)) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (gas->is);
    return;
  }
  TALER_TESTING_interpreter_next (gas->is);
}


/**
 * Run the "get_auditor" command.
 *
 * @param cls closure.
 * @param cmd the command currently being executed.
 * @param is the interpreter state.
 */
static void
get_auditor_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct GetAuditorState *gas = cls;

  (void) cmd;
  if (NULL == gas->auditor_url)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (NULL != gas->priv_file)
  {
    if (GNUNET_SYSERR ==
        GNUNET_CRYPTO_eddsa_key_from_file (gas->priv_file,
                                           GNUNET_YES,
                                           &gas->auditor_priv.eddsa_priv))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_CRYPTO_eddsa_key_get_public (&gas->auditor_priv.eddsa_priv,
                                        &gas->auditor_pub.eddsa_pub);
  }
  gas->is = is;
  gas->auditor
    = TALER_AUDITOR_get_config (TALER_TESTING_interpreter_get_context (is),
                                gas->auditor_url,
                                &version_cb,
                                gas);
  if (NULL == gas->auditor)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Cleanup the state.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
get_auditor_cleanup (void *cls,
                     const struct TALER_TESTING_Command *cmd)
{
  struct GetAuditorState *gas = cls;

  if (NULL != gas->auditor)
  {
    GNUNET_break (0);
    TALER_AUDITOR_get_config_cancel (gas->auditor);
    gas->auditor = NULL;
  }
  GNUNET_free (gas->priv_file);
  GNUNET_free (gas->auditor_url);
  GNUNET_free (gas);
}


/**
 * Offer internal data to a "get_auditor" CMD state to other commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
get_auditor_traits (void *cls,
                    const void **ret,
                    const char *trait,
                    unsigned int index)
{
  struct GetAuditorState *gas = cls;
  unsigned int off = (NULL == gas->priv_file) ? 2 : 0;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_auditor_priv (&gas->auditor_priv),
    TALER_TESTING_make_trait_auditor_pub (&gas->auditor_pub),
    TALER_TESTING_make_trait_auditor_url (gas->auditor_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (&traits[off],
                                  ret,
                                  trait,
                                  index);
}


/**
 * Get the base URL of the auditor from @a cfg.
 *
 * @param cfg configuration to evaluate
 * @return base URL of the auditor according to @a cfg
 */
static char *
get_auditor_base_url (
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *auditor_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &auditor_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    return NULL;
  }
  return auditor_url;
}


/**
 * Get the file name of the master private key file of the auditor from @a
 * cfg.
 *
 * @param cfg configuration to evaluate
 * @return base URL of the auditor according to @a cfg
 */
static char *
get_auditor_priv_file (
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  char *fn;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "auditor",
                                               "AUDITOR_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "AUDITOR_PRIV_FILE");
    return NULL;
  }
  return fn;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_get_auditor (
  const char *label,
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  bool load_auditor_keys)
{
  struct GetAuditorState *gas;

  gas = GNUNET_new (struct GetAuditorState);
  gas->auditor_url = get_auditor_base_url (cfg);
  if (load_auditor_keys)
    gas->priv_file = get_auditor_priv_file (cfg);
  {
    struct TALER_TESTING_Command cmd = {
      .cls = gas,
      .label = label,
      .run = &get_auditor_run,
      .cleanup = &get_auditor_cleanup,
      .traits = &get_auditor_traits,
      .name = "auditor"
    };

    return cmd;
  }
}
