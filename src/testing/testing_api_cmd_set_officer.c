/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_set_officer.c
 * @brief command for testing /management/aml-officers
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "set_officer" CMD.
 */
struct SetOfficerState
{

  /**
   * Update AML officer handle while operation is running.
   */
  struct TALER_EXCHANGE_ManagementUpdateAmlOfficer *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to command to previous set officer
   * to update, or NULL.
   */
  const char *ref_cmd;

  /**
   * Name to use for the officer.
   */
  const char *name;

  /**
   * Private key of the AML officer.
   */
  struct TALER_AmlOfficerPrivateKeyP officer_priv;

  /**
   * Public key of the AML officer.
   */
  struct TALER_AmlOfficerPublicKeyP officer_pub;

  /**
   * Is the officer supposed to be enabled?
   */
  bool is_active;

  /**
   * Is access supposed to be read-only?
   */
  bool read_only;

};


/**
 * Callback to analyze the /management/XXX response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param hr HTTP response details
 */
static void
set_officer_cb (void *cls,
                const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct SetOfficerState *ds = cls;

  ds->dh = NULL;
  if (MHD_HTTP_NO_CONTENT != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Unexpected response code %u to command %s in %s:%u\n",
                hr->http_status,
                ds->is->commands[ds->is->ip].label,
                __FILE__,
                __LINE__);
    json_dumpf (hr->reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (ds->is);
    return;
  }
  TALER_TESTING_interpreter_next (ds->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
set_officer_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct SetOfficerState *ds = cls;
  struct GNUNET_TIME_Timestamp now;
  struct TALER_MasterSignatureP master_sig;

  (void) cmd;
  now = GNUNET_TIME_timestamp_get ();
  ds->is = is;
  if (NULL == ds->ref_cmd)
  {
    GNUNET_CRYPTO_eddsa_key_create (&ds->officer_priv.eddsa_priv);
    GNUNET_CRYPTO_eddsa_key_get_public (&ds->officer_priv.eddsa_priv,
                                        &ds->officer_pub.eddsa_pub);
  }
  else
  {
    const struct TALER_TESTING_Command *ref;
    const struct TALER_AmlOfficerPrivateKeyP *officer_priv;
    const struct TALER_AmlOfficerPublicKeyP *officer_pub;

    ref = TALER_TESTING_interpreter_lookup_command (is,
                                                    ds->ref_cmd);
    if (NULL == ref)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_officer_pub (ref,
                                                        &officer_pub));
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_officer_priv (ref,
                                                         &officer_priv));
    ds->officer_pub = *officer_pub;
    ds->officer_priv = *officer_priv;
  }
  TALER_exchange_offline_aml_officer_status_sign (&ds->officer_pub,
                                                  ds->name,
                                                  now,
                                                  ds->is_active,
                                                  ds->read_only,
                                                  &is->master_priv,
                                                  &master_sig);
  ds->dh = TALER_EXCHANGE_management_update_aml_officer (
    is->ctx,
    is->exchange_url,
    &ds->officer_pub,
    ds->name,
    now,
    ds->is_active,
    ds->read_only,
    &master_sig,
    &set_officer_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "set_officer" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct SetOfficerState`.
 * @param cmd the command which is being cleaned up.
 */
static void
set_officer_cleanup (void *cls,
                     const struct TALER_TESTING_Command *cmd)
{
  struct SetOfficerState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_management_update_aml_officer_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


/**
 * Offer internal data to a "set officer" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
set_officer_traits (void *cls,
                    const void **ret,
                    const char *trait,
                    unsigned int index)
{
  struct SetOfficerState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_officer_pub (&ws->officer_pub),
    TALER_TESTING_make_trait_officer_priv (&ws->officer_priv),
    TALER_TESTING_make_trait_officer_name (&ws->name),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_set_officer (
  const char *label,
  const char *ref_cmd,
  const char *name,
  bool is_active,
  bool read_only)
{
  struct SetOfficerState *ds;

  ds = GNUNET_new (struct SetOfficerState);
  ds->ref_cmd = ref_cmd;
  ds->name = name;
  ds->is_active = is_active;
  ds->read_only = read_only;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &set_officer_run,
      .cleanup = &set_officer_cleanup,
      .traits = &set_officer_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_set_officer.c */
