/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_check_aml_decisions.c
 * @brief command for testing GET /aml/$OFFICER_PUB/decisions
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_signatures.h"
#include "backoff.h"


/**
 * State for a "check_aml_decisions" CMD.
 */
struct AmlCheckState
{

  /**
   * Handle while operation is running.
   */
  struct TALER_EXCHANGE_LookupAmlDecisions *dh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to command to previous set officer.
   */
  const char *ref_officer;

  /**
   * Reference to a command with a trait of a payto-URI for an account we want
   * to get the status on; NULL to match all accounts.  If it has also a
   * justification trait, we check that this is the current justification for
   * the latest AML decision.
   */
  const char *ref_operation;

  /**
   * Expected HTTP status.
   */
  unsigned int expected_http_status;

};


/**
 * Callback to analyze the /aml/$OFFICER_PUB/$decision/$H_PAYTO response, just used to check
 * if the response code is acceptable.
 *
 * @param cls closure.
 * @param adr response details
 */
static void
check_aml_decisions_cb (
  void *cls,
  const struct TALER_EXCHANGE_AmlDecisionsResponse *adr)
{
  struct AmlCheckState *ds = cls;

  ds->dh = NULL;
  if (ds->expected_http_status != adr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ds->is,
                                     adr->hr.http_status,
                                     ds->expected_http_status);
    return;
  }
  if (MHD_HTTP_OK == adr->hr.http_status)
  {
    const struct TALER_TESTING_Command *ref;
    const char *justification;
    const struct TALER_EXCHANGE_AmlDecision *oldest = NULL;

    if (NULL != ds->ref_operation)
    {
      ref = TALER_TESTING_interpreter_lookup_command (
        ds->is,
        ds->ref_operation);
      if (NULL == ref)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (ds->is);
        return;
      }
      if (GNUNET_OK ==
          TALER_TESTING_get_trait_aml_justification (
            ref,
            &justification))
      {
        for (unsigned int i = 0; i<adr->details.ok.decisions_length; i++)
        {
          const struct TALER_EXCHANGE_AmlDecision *aml_history
            = &adr->details.ok.decisions[i];

          if ( (NULL == oldest) ||
               (GNUNET_TIME_timestamp_cmp (oldest->decision_time,
                                           >,
                                           aml_history->decision_time)) )
            oldest = aml_history;
        }
        if (NULL == oldest)
        {
          GNUNET_break (0);
          TALER_TESTING_interpreter_fail (ds->is);
          return;
        }
        if (0 != strcmp (oldest->justification,
                         justification) )
        {
          GNUNET_break (0);
          TALER_TESTING_interpreter_fail (ds->is);
          return;
        }
      }
    }
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
check_aml_decisions_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is)
{
  struct AmlCheckState *ds = cls;
  const struct TALER_NormalizedPaytoHashP *h_payto = NULL;
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv;
  const struct TALER_TESTING_Command *ref;
  const char *exchange_url;

  (void) cmd;
  ds->is = is;
  {
    const struct TALER_TESTING_Command *exchange_cmd;

    exchange_cmd
      = TALER_TESTING_interpreter_get_command (
          is,
          "exchange");
    if (NULL == exchange_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_assert (
      GNUNET_OK ==
      TALER_TESTING_get_trait_exchange_url (exchange_cmd,
                                            &exchange_url));
  }

  if (NULL != ds->ref_operation)
  {
    ref = TALER_TESTING_interpreter_lookup_command (
      is,
      ds->ref_operation);
    if (NULL == ref)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_h_normalized_payto (
                     ref,
                     &h_payto));
  }
  ref = TALER_TESTING_interpreter_lookup_command (
    is,
    ds->ref_officer);
  if (NULL == ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_officer_priv (
                   ref,
                   &officer_priv));
  ds->dh = TALER_EXCHANGE_lookup_aml_decisions (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    h_payto, /* NULL to return all */
    TALER_EXCHANGE_YNA_ALL,
    TALER_EXCHANGE_YNA_ALL,
    UINT64_MAX, /* offset */
    -1, /* limit */
    officer_priv,
    &check_aml_decisions_cb,
    ds);
  if (NULL == ds->dh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "check_aml_decision" CMD, and possibly cancel a
 * pending operation thereof.
 *
 * @param cls closure, must be a `struct AmlCheckState`.
 * @param cmd the command which is being cleaned up.
 */
static void
check_aml_decisions_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct AmlCheckState *ds = cls;

  if (NULL != ds->dh)
  {
    TALER_TESTING_command_incomplete (ds->is,
                                      cmd->label);
    TALER_EXCHANGE_lookup_aml_decisions_cancel (ds->dh);
    ds->dh = NULL;
  }
  GNUNET_free (ds);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_aml_decisions (
  const char *label,
  const char *ref_officer,
  const char *ref_operation,
  unsigned int expected_http_status)
{
  struct AmlCheckState *ds;

  ds = GNUNET_new (struct AmlCheckState);
  ds->ref_officer = ref_officer;
  ds->ref_operation = ref_operation;
  ds->expected_http_status = expected_http_status;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ds,
      .label = label,
      .run = &check_aml_decisions_run,
      .cleanup = &check_aml_decisions_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_check_aml_decisions.c */
