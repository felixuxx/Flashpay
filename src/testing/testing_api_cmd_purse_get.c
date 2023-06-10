/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_purse_get.c
 * @brief Implement the GET /purse/$RID test command.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "poll" CMD.
 */
struct PollState
{

  /**
   * How long do we give the exchange to respond?
   */
  struct GNUNET_TIME_Relative timeout;

  /**
   * Label to the command which created the purse to check,
   * needed to resort the purse key.
   */
  const char *poll_reference;

  /**
   * Timeout to wait for at most.
   */
  struct GNUNET_SCHEDULER_Task *tt;

  /**
   * The interpreter we are using.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * State for a "status" CMD.
 */
struct StatusState
{

  /**
   * How long do we give the exchange to respond?
   */
  struct GNUNET_TIME_Relative timeout;

  /**
   * Poller waiting for us.
   */
  struct PollState *ps;

  /**
   * Label to the command which created the purse to check,
   * needed to resort the purse key.
   */
  const char *purse_reference;

  /**
   * Handle to the "purse status" operation.
   */
  struct TALER_EXCHANGE_PurseGetHandle *pgh;

  /**
   * Expected purse balance.
   */
  const char *expected_balance;

  /**
   * Public key of the purse being analyzed.
   */
  const struct TALER_PurseContractPublicKeyP *purse_pub;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Are we waiting for a merge or a deposit?
   */
  bool wait_for_merge;

};


/**
 * Check that the purse balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
purse_status_cb (void *cls,
                 const struct TALER_EXCHANGE_PurseGetResponse *rs)
{
  struct StatusState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;

  ss->pgh = NULL;
  if (ss->expected_response_code != rs->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected HTTP response code: %d in %s:%u\n",
                rs->hr.http_status,
                __FILE__,
                __LINE__);
    json_dumpf (rs->hr.reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }
  if (MHD_HTTP_OK == ss->expected_response_code)
  {
    struct TALER_Amount eb;

    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (ss->expected_balance,
                                           &eb));
    if (0 != TALER_amount_cmp (&eb,
                               &rs->details.ok.balance))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected amount in purse: %s\n",
                  TALER_amount_to_string (&rs->details.ok.balance));
      TALER_TESTING_interpreter_fail (ss->is);
      return;
    }
  }
  if (NULL != ss->ps)
  {
    /* force continuation on long poller */
    GNUNET_SCHEDULER_cancel (ss->ps->tt);
    ss->ps->tt = NULL;
    TALER_TESTING_interpreter_next (is);
    return;
  }
  if (GNUNET_TIME_relative_is_zero (ss->timeout))
    TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
status_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct StatusState *ss = cls;
  const struct TALER_TESTING_Command *create_purse;
  struct TALER_EXCHANGE_Handle *exchange
    = TALER_TESTING_get_exchange (is);

  if (NULL == exchange)
    return;
  ss->is = is;
  create_purse
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ss->purse_reference);
  GNUNET_assert (NULL != create_purse);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_purse_pub (create_purse,
                                         &ss->purse_pub))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find purse_pub for status query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ss->pgh = TALER_EXCHANGE_purse_get (exchange,
                                      ss->purse_pub,
                                      ss->timeout,
                                      ss->wait_for_merge,
                                      &purse_status_cb,
                                      ss);
  if (! GNUNET_TIME_relative_is_zero (ss->timeout))
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
}


/**
 * Cleanup the state from a "purse status" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
status_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct StatusState *ss = cls;

  if (NULL != ss->pgh)
  {
    TALER_TESTING_command_incomplete (ss->is,
                                      cmd->label);
    TALER_EXCHANGE_purse_get_cancel (ss->pgh);
    ss->pgh = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_poll (
  const char *label,
  unsigned int expected_http_status,
  const char *purse_ref,
  const char *expected_balance,
  bool wait_for_merge,
  struct GNUNET_TIME_Relative timeout)
{
  struct StatusState *ss;

  GNUNET_assert (NULL != purse_ref);
  ss = GNUNET_new (struct StatusState);
  ss->purse_reference = purse_ref;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_http_status;
  ss->timeout = timeout;
  ss->wait_for_merge = wait_for_merge;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &status_run,
      .cleanup = &status_cleanup
    };

    return cmd;
  }
}


/**
 * Long poller timed out. Fail the test.
 *
 * @param cls a `struct PollState`
 */
static void
finish_timeout (void *cls)
{
  struct PollState *ps = cls;

  ps->tt = NULL;
  GNUNET_break (0);
  TALER_TESTING_interpreter_fail (ps->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
finish_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct PollState *ps = cls;
  const struct TALER_TESTING_Command *poll_purse;
  struct StatusState *ss;

  ps->is = is;
  poll_purse
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ps->poll_reference);
  GNUNET_assert (NULL != poll_purse);
  GNUNET_assert (poll_purse->run == &status_run);
  ss = poll_purse->cls;
  if (NULL == ss->pgh)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  GNUNET_assert (NULL == ss->ps);
  ss->ps = ps;
  ps->tt = GNUNET_SCHEDULER_add_delayed (ps->timeout,
                                         &finish_timeout,
                                         ps);
}


/**
 * Cleanup the state from a "purse finish" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
finish_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct PollState *ps = cls;

  if (NULL != ps->tt)
  {
    GNUNET_SCHEDULER_cancel (ps->tt);
    ps->tt = NULL;
  }
  GNUNET_free (ps);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_purse_poll_finish (const char *label,
                                     struct GNUNET_TIME_Relative timeout,
                                     const char *poll_reference)
{
  struct PollState *ps;

  GNUNET_assert (NULL != poll_reference);
  ps = GNUNET_new (struct PollState);
  ps->timeout = timeout;
  ps->poll_reference = poll_reference;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ps,
      .label = label,
      .run = &finish_run,
      .cleanup = &finish_cleanup
    };

    return cmd;
  }
}
