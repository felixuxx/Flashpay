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
 * @file testing/testing_api_cmd_reserve_get.c
 * @brief Implement the GET /reserve/$RID test command.
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
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
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
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve status" operation.
   */
  struct TALER_EXCHANGE_ReservesGetHandle *rsh;

  /**
   * Expected reserve balance.
   */
  const char *expected_balance;

  /**
   * Public key of the reserve being analyzed.
   */
  const struct TALER_ReservePublicKeyP *reserve_pubp;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

};


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
reserve_status_cb (void *cls,
                   const struct TALER_EXCHANGE_ReserveSummary *rs)
{
  struct StatusState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;
  struct TALER_Amount eb;

  ss->rsh = NULL;
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
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (ss->expected_balance,
                                           &eb));
    if (0 != TALER_amount_cmp (&eb,
                               &rs->details.ok.balance))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected amount %s in reserve, wanted %s\n",
                  TALER_amount_to_string (&rs->details.ok.balance),
                  ss->expected_balance);
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
  const struct TALER_TESTING_Command *create_reserve;
  const char *exchange_url;

  ss->is = is;
  exchange_url = TALER_TESTING_get_exchange_url (is);
  if (NULL == exchange_url)
  {
    GNUNET_break (0);
    return;
  }
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ss->reserve_reference);
  GNUNET_assert (NULL != create_reserve);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_pub (create_reserve,
                                           &ss->reserve_pubp))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find reserve_pub for status query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ss->rsh = TALER_EXCHANGE_reserves_get (
    TALER_TESTING_interpreter_get_context (is),
    exchange_url,
    ss->reserve_pubp,
    ss->timeout,
    &reserve_status_cb,
    ss);
  if (! GNUNET_TIME_relative_is_zero (ss->timeout))
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
}


/**
 * Cleanup the state from a "reserve status" CMD, and possibly
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

  if (NULL != ss->rsh)
  {
    TALER_TESTING_command_incomplete (ss->is,
                                      cmd->label);
    TALER_EXCHANGE_reserves_get_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          const char *reserve_reference,
                          const char *expected_balance,
                          unsigned int expected_response_code)
{
  struct StatusState *ss;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct StatusState);
  ss->reserve_reference = reserve_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_poll (const char *label,
                                const char *reserve_reference,
                                const char *expected_balance,
                                struct GNUNET_TIME_Relative timeout,
                                unsigned int expected_response_code)
{
  struct StatusState *ss;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct StatusState);
  ss->reserve_reference = reserve_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;
  ss->timeout = timeout;
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
  const struct TALER_TESTING_Command *poll_reserve;
  struct StatusState *ss;

  ps->is = is;
  poll_reserve
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ps->poll_reference);
  GNUNET_assert (NULL != poll_reserve);
  GNUNET_assert (poll_reserve->run == &status_run);
  ss = poll_reserve->cls;
  if (NULL == ss->rsh)
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
 * Cleanup the state from a "reserve finish" CMD.
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
TALER_TESTING_cmd_reserve_poll_finish (const char *label,
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
