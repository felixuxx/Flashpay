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
 * @file testing/testing_api_cmd_take_aml_decision.c
 * @brief command for testing /aml/$OFFICER_PUB/decision
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "take_aml_decision" CMD.
 */
struct AmlDecisionState
{

  /**
   * Auditor enable handle while operation is running.
   */
  struct TALER_EXCHANGE_AddAmlDecision *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to command to previous set officer command that gives
   * us an officer_priv trait.
   */
  const char *officer_ref_cmd;

  /**
   * Reference to command to previous AML-triggering event that gives
   * us a payto-hash trait.
   */
  const char *account_ref_cmd;

  /**
   * Payto hash of the account we are manipulating the AML settings for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * New AML state to use.
   */
  enum TALER_AmlDecisionState new_state;

  /**
   * Justification given.
   */
  const char *justification;

  /**
   * KYC requirement to add.
   */
  const char *kyc_requirement;

  /**
   * Threshold transaction amount.
   */
  struct TALER_Amount new_threshold;

  /**
   * Expected response code.
   */
  unsigned int expected_response;
};


/**
 * Callback to analyze the /management/XXX response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param hr HTTP response details
 */
static void
take_aml_decision_cb (void *cls,
                      const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct AmlDecisionState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_response != hr->http_status)
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
take_aml_decision_run (void *cls,
                       const struct TALER_TESTING_Command *cmd,
                       struct TALER_TESTING_Interpreter *is)
{
  struct AmlDecisionState *ds = cls;
  struct GNUNET_TIME_Timestamp now;
  const struct TALER_PaytoHashP *h_payto;
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv;
  const struct TALER_TESTING_Command *ref;
  json_t *kyc_requirements = NULL;

  (void) cmd;
  now = GNUNET_TIME_timestamp_get ();
  ds->is = is;
  ref = TALER_TESTING_interpreter_lookup_command (is,
                                                  ds->account_ref_cmd);
  if (NULL == ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_h_payto (ref,
                                                  &h_payto));
  ref = TALER_TESTING_interpreter_lookup_command (is,
                                                  ds->officer_ref_cmd);
  if (NULL == ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_officer_priv (ref,
                                                       &officer_priv));
  ds->h_payto = *h_payto;
  if (NULL != ds->kyc_requirement)
  {
    kyc_requirements = json_array ();
    GNUNET_assert (NULL != kyc_requirements);
    GNUNET_assert (0 ==
                   json_array_append (kyc_requirements,
                                      json_string (ds->kyc_requirement)));
  }

  ds->dh = TALER_EXCHANGE_add_aml_decision (
    is->ctx,
    is->exchange_url,
    ds->justification,
    now,
    &ds->new_threshold,
    h_payto,
    ds->new_state,
    kyc_requirements,
    officer_priv,
    &take_aml_decision_cb,
    ds);
  json_decref (kyc_requirements);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "take_aml_decision" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct AmlDecisionState`.
 * @param cmd the command which is being cleaned up.
 */
static void
take_aml_decision_cleanup (void *cls,
                           const struct TALER_TESTING_Command *cmd)
{
  struct AmlDecisionState *ds = cls;

  if (NULL != ds->dh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ds->is->ip,
                cmd->label);
    TALER_EXCHANGE_add_aml_decision_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


/**
 * Offer internal data of a "AML decision" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
take_aml_decision_traits (void *cls,
                          const void **ret,
                          const char *trait,
                          unsigned int index)
{
  struct AmlDecisionState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_h_payto (&ws->h_payto),
    TALER_TESTING_make_trait_aml_justification (&ws->justification),
    TALER_TESTING_make_trait_aml_decision (&ws->new_state),
    TALER_TESTING_make_trait_amount (&ws->new_threshold),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_take_aml_decision (
  const char *label,
  const char *ref_officer,
  const char *ref_operation,
  const char *new_threshold,
  const char *justification,
  enum TALER_AmlDecisionState new_state,
  const char *kyc_requirement,
  unsigned int expected_response)
{
  struct AmlDecisionState *ds;

  ds = GNUNET_new (struct AmlDecisionState);
  ds->officer_ref_cmd = ref_officer;
  ds->account_ref_cmd = ref_operation;
  ds->kyc_requirement = kyc_requirement;
  if (GNUNET_OK !=
      TALER_string_to_amount (new_threshold,
                              &ds->new_threshold))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %s\n",
                new_threshold,
                label);
    GNUNET_assert (0);
  }
  ds->new_state = new_state;
  ds->justification = justification;
  ds->expected_response = expected_response;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &take_aml_decision_run,
      .cleanup = &take_aml_decision_cleanup,
      .traits = &take_aml_decision_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_take_aml_decision.c */
