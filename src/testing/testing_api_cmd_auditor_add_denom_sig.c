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
 * @param hr HTTP response details
 */
static void
denom_sig_add_cb (void *cls,
                  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct AuditorAddDenomSigState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response_code != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
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
auditor_add_run (void *cls,
                 const struct TALER_TESTING_Command *cmd,
                 struct TALER_TESTING_Interpreter *is)
{
  struct AuditorAddDenomSigState *ds = cls;
  struct TALER_AuditorSignatureP auditor_sig;
  struct GNUNET_HashCode h_denom_pub;
  const struct TALER_EXCHANGE_DenomPublicKey *dk;

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
  if (ds->bad_sig)
  {
    memset (&auditor_sig,
            42,
            sizeof (auditor_sig));
  }
  else
  {
    struct TALER_MasterPublicKeyP master_pub;

    GNUNET_CRYPTO_eddsa_key_get_public (&is->master_priv.eddsa_priv,
                                        &master_pub.eddsa_pub);
    TALER_auditor_denom_validity_sign (
      is->auditor_url,
      &dk->h_key,
      &master_pub,
      dk->valid_from,
      dk->withdraw_valid_until,
      dk->expire_deposit,
      dk->expire_legal,
      &dk->value,
      &dk->fee_withdraw,
      &dk->fee_deposit,
      &dk->fee_refresh,
      &dk->fee_refund,
      &is->auditor_priv,
      &auditor_sig);
  }
  ds->dh = TALER_EXCHANGE_add_auditor_denomination (
    is->ctx,
    is->exchange_url,
    &h_denom_pub,
    &is->auditor_pub,
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
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_add_auditor_denomination_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "auditor_add" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 *
 * @return #GNUNET_OK on success.
 */
static int
auditor_add_traits (void *cls,
                    const void **ret,
                    const char *trait,
                    unsigned int index)
{
  return GNUNET_NO;
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
      .cleanup = &auditor_add_cleanup,
      .traits = &auditor_add_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_auditor_add_denom_sig.c */
