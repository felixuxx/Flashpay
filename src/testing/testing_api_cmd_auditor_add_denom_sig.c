/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file testing/testing_api_cmd_auditor_add_denom_sig.c
 * @brief command for testing POST to /auditor/$AUDITOR_PUB/$H_DENOM_PUB
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "auditor_add" CMD.
 */
struct AuditorAddDenomSigState
{

  /**
   * Auditor enable handle while operation is running.
   */
  struct TALER_EXCHANGE_AuditorAddDenominationHandle *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to command identifying denomination to add.
   */
  const char *denom_ref;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Should we make the request with a bad master_sig signature?
   */
  bool bad_sig;
};


/**
 * Callback to analyze the /management/auditor response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param adr response details
 */
static void
denom_sig_add_cb (
  void *cls,
  const struct TALER_EXCHANGE_AuditorAddDenominationResponse *adr)
{
  struct AuditorAddDenomSigState *ds = cls;
  const struct TALER_EXCHANGE_HttpResponse *hr = &adr->hr;

  ds->dh = NULL;
  if (ds->expected_response_code != hr->http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     hr->http_status,
                                     ds->expected_response_code);
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
auditor_add_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct AuditorAddDenomSigState *ds = cls;
  struct TALER_AuditorSignatureP auditor_sig;
  struct TALER_DenominationHashP h_denom_pub;
  const struct TALER_EXCHANGE_DenomPublicKey *dk;
  const struct TALER_AuditorPublicKeyP *auditor_pub;
  const struct TALER_TESTING_Command *auditor_cmd;
  const struct TALER_TESTING_Command *exchange_cmd;
  const char *exchange_url;
  const char *auditor_url;

  (void) cmd;
  /* Get denom pub from trait */
  {
    const struct TALER_TESTING_Command *denom_cmd;

    denom_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                          ds->denom_ref);
    if (NULL == denom_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_denom_pub (denom_cmd,
                                                      0,
                                                      &dk));
  }
  ds->is = is;
  auditor_cmd = TALER_TESTING_interpreter_get_command (is,
                                                       "auditor");
  if (NULL == auditor_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_auditor_pub (auditor_cmd,
                                                      &auditor_pub));
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_auditor_url (auditor_cmd,
                                                      &auditor_url));
  exchange_cmd = TALER_TESTING_interpreter_get_command (is,
                                                        "exchange");
  if (NULL == exchange_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_exchange_url (exchange_cmd,
                                                       &exchange_url));
  if (ds->bad_sig)
  {
    memset (&auditor_sig,
            42,
            sizeof (auditor_sig));
  }
  else
  {
    const struct TALER_MasterPublicKeyP *master_pub;
    const struct TALER_AuditorPrivateKeyP *auditor_priv;

    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_master_pub (exchange_cmd,
                                                       &master_pub));
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_auditor_priv (auditor_cmd,
                                                         &auditor_priv));
    TALER_auditor_denom_validity_sign (
      auditor_url,
      &dk->h_key,
      master_pub,
      dk->valid_from,
      dk->withdraw_valid_until,
      dk->expire_deposit,
      dk->expire_legal,
      &dk->value,
      &dk->fees,
      auditor_priv,
      &auditor_sig);
  }
  ds->dh = TALER_EXCHANGE_add_auditor_denomination (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    &h_denom_pub,
    auditor_pub,
    &auditor_sig,
    &denom_sig_add_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "auditor_add" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct AuditorAddDenomSigState`.
 * @param cmd the command which is being cleaned up.
 */
static void
auditor_add_cleanup (void *cls,
                     const struct TALER_TESTING_Command *cmd)
{
  struct AuditorAddDenomSigState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_add_auditor_denomination_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_auditor_add_denom_sig (const char *label,
                                         unsigned int expected_http_status,
                                         const char *denom_ref,
                                         bool bad_sig)
{
  struct AuditorAddDenomSigState *ds;

  ds = GNUNET_new (struct AuditorAddDenomSigState);
  ds->expected_response_code = expected_http_status;
  ds->bad_sig = bad_sig;
  ds->denom_ref = denom_ref;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &auditor_add_run,
      .cleanup = &auditor_add_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_auditor_add_denom_sig.c */
