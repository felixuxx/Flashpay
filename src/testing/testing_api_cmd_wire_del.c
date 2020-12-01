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
 * @file testing/testing_api_cmd_wire_del.c
 * @brief command for testing POST to /management/wire
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "wire_del" CMD.
 */
struct WireDelState
{

  /**
   * Wire enable handle while operation is running.
   */
  struct TALER_EXCHANGE_ManagementWireDisableHandle *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Account to del.
   */
  const char *payto_uri;

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
 * Callback to analyze the /management/wire response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param hr HTTP response details
 */
static void
wire_del_cb (void *cls,
             const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct WireDelState *ds = cls;

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
wire_del_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct WireDelState *ds = cls;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Absolute now;

  (void) cmd;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  ds->is = is;
  if (ds->bad_sig)
  {
    memset (&master_sig,
            42,
            sizeof (master_sig));
  }
  else
  {
    struct TALER_MasterDelWirePS kv = {
      .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DEL_WIRE),
      .purpose.size = htonl (sizeof (kv)),
      .end_date = GNUNET_TIME_absolute_hton (now),
    };

    TALER_exchange_wire_signature_hash (ds->payto_uri,
                                        &kv.h_wire);
    GNUNET_CRYPTO_eddsa_sign (&is->master_priv.eddsa_priv,
                              &kv,
                              &master_sig.eddsa_signature);
  }
  ds->dh = TALER_EXCHANGE_management_disable_wire (
    is->ctx,
    is->exchange_url,
    ds->payto_uri,
    now,
    &master_sig,
    &wire_del_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "wire_del" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct WireDelState`.
 * @param cmd the command which is being cleaned up.
 */
static void
wire_del_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct WireDelState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_management_disable_wire_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


/**
 * Offer internal data from a "wire_del" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 *
 * @return #GNUNET_OK on success.
 */
static int
wire_del_traits (void *cls,
                 const void **ret,
                 const char *trait,
                 unsigned int index)
{
  return GNUNET_NO;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_wire_del (const char *label,
                            const char *payto_uri,
                            unsigned int expected_http_status,
                            bool bad_sig)
{
  struct WireDelState *ds;

  ds = GNUNET_new (struct WireDelState);
  ds->expected_response_code = expected_http_status;
  ds->bad_sig = bad_sig;
  ds->payto_uri = payto_uri;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &wire_del_run,
      .cleanup = &wire_del_cleanup,
      .traits = &wire_del_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_wire_del.c */
