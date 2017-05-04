/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank/test_bank_interpreter.c
 * @brief interpreter for tests of the bank's HTTP API interface
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include "test_bank_interpreter.h"
#include "taler_fakebank_lib.h"


/**
 * State of the interpreter loop.
 */
struct InterpreterState
{
  /**
   * Keys from the bank.
   */
  const struct TALER_BANK_Keys *keys;

  /**
   * Commands the interpreter will run.
   */
  struct TBI_Command *commands;

  /**
   * Interpreter task (if one is scheduled).
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Main execution context for the main loop.
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * Task run on timeout.
   */
  struct GNUNET_SCHEDULER_Task *timeout_task;

  /**
   * Context for running the main loop with GNUnet's SCHEDULER API.
   */
  struct GNUNET_CURL_RescheduleContext *rc;

  /**
   * Where to store the final result.
   */
  int *resultp;

  /**
   * Fakebank, or NULL if we are not using the fakebank.
   */
  struct TALER_FAKEBANK_Handle *fakebank;

  /**
   * Instruction pointer.  Tells #interpreter_run() which
   * instruction to run next.
   */
  unsigned int ip;

};


/**
 * The testcase failed, return with an error code.
 *
 * @param is interpreter state to clean up
 */
static void
fail (struct InterpreterState *is)
{
  *is->resultp = GNUNET_SYSERR;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Find a command by label.
 *
 * @param is interpreter state to search
 * @param label label to look for
 * @return NULL if command was not found
 */
static const struct TBI_Command *
find_command (const struct InterpreterState *is,
              const char *label)
{
  unsigned int i;
  const struct TBI_Command *cmd;

  if (NULL == label)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Attempt to lookup command for empty label\n");
    return NULL;
  }
  for (i=0;TBI_OC_END != (cmd = &is->commands[i])->oc;i++)
    if ( (NULL != cmd->label) &&
         (0 == strcmp (cmd->label,
                       label)) )
      return cmd;
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Command not found: %s\n",
              label);
  return NULL;
}


/**
 * Run the main interpreter loop that performs bank operations.
 *
 * @param cls contains the `struct InterpreterState`
 */
static void
interpreter_run (void *cls);


/**
 * Function called upon completion of our /admin/add/incoming request.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol)
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
static void
add_incoming_cb (void *cls,
                 unsigned int http_status,
                 const json_t *json)
{
  struct InterpreterState *is = cls;
  struct TBI_Command *cmd = &is->commands[is->ip];

  cmd->details.admin_add_incoming.aih = NULL;
  if (cmd->details.admin_add_incoming.expected_response_code != http_status)
  {
    GNUNET_break (0);
    fprintf (stderr,
             "Unexpected response code %u:\n",
             http_status);
    if (NULL != json)
    {
      json_dumpf (json, stderr, 0);
      fprintf (stderr, "\n");
    }
    fail (is);
    return;
  }
  is->ip++;
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
}


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param dir direction of the transfer
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
static void
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_BANK_Direction dir,
            uint64_t serial_id,
            const struct TALER_BANK_TransferDetails *details,
            const json_t *json)
{
  struct InterpreterState *is = cls;
  struct TBI_Command *cmd = &is->commands[is->ip];

  if (MHD_HTTP_OK != http_status)
  {
    cmd->details.history.hh = NULL;
    is->ip++;
    is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
    return;
  }
  /* FIXME: check history data is OK! */
}


/**
 * Run the main interpreter loop that performs bank operations.
 *
 * @param cls contains the `struct InterpreterState`
 */
static void
interpreter_run (void *cls)
{
  struct InterpreterState *is = cls;
  struct TBI_Command *cmd = &is->commands[is->ip];
  const struct TBI_Command *ref;
  struct TALER_WireTransferIdentifierRawP wtid;
  struct TALER_Amount amount;
  const struct GNUNET_SCHEDULER_TaskContext *tc;
  struct TALER_BANK_AuthenticationData auth;

  is->task = NULL;
  tc = GNUNET_SCHEDULER_get_task_context ();
  if (0 != (tc->reason & GNUNET_SCHEDULER_REASON_SHUTDOWN))
  {
    fprintf (stderr,
             "Test aborted by shutdown request\n");
    fail (is);
    return;
  }
  auth.method = TALER_BANK_AUTH_BASIC; /* or "NONE"? */
  auth.details.basic.username = "user";
  auth.details.basic.password = "pass";
  switch (cmd->oc)
  {
  case TBI_OC_END:
    *is->resultp = GNUNET_OK;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case TBI_OC_ADMIN_ADD_INCOMING:
    if (GNUNET_OK !=
        TALER_string_to_amount (cmd->details.admin_add_incoming.amount,
                                &amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %u\n",
                  cmd->details.admin_add_incoming.amount,
                  is->ip);
      fail (is);
      return;
    }
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &cmd->details.admin_add_incoming.wtid,
                                sizeof (cmd->details.admin_add_incoming.wtid));
    cmd->details.admin_add_incoming.aih
      = TALER_BANK_admin_add_incoming (is->ctx,
                                       "http://localhost:8081",
                                       &auth,
                                       cmd->details.admin_add_incoming.exchange_base_url,
                                       &cmd->details.admin_add_incoming.wtid,
                                       &amount,
                                       cmd->details.admin_add_incoming.debit_account_no,
                                       cmd->details.admin_add_incoming.credit_account_no,
                                       &add_incoming_cb,
                                       is);
    if (NULL == cmd->details.admin_add_incoming.aih)
    {
      GNUNET_break (0);
      fail (is);
      return;
    }
    return;
  case TBI_OC_HISTORY:
    cmd->details.history.hh
      = TALER_BANK_history (is->ctx,
                            "http://localhost:8081",
                            &auth,
                            cmd->details.history.account_number,
                            cmd->details.history.direction,
                            cmd->details.history.start_row,
                            cmd->details.history.num_results,
                            &history_cb,
                            is);
    if (NULL == cmd->details.history.hh)
    {
      GNUNET_break (0);
      fail (is);
      return;
    }
    return;
  case TBI_OC_EXPECT_TRANSFER:
    ref = find_command (is,
                        cmd->details.expect_transfer.cmd_ref);
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (ref->details.admin_add_incoming.amount,
                                           &amount));
    if (GNUNET_OK !=
        TALER_FAKEBANK_check (is->fakebank,
                              &amount,
                              ref->details.admin_add_incoming.debit_account_no,
                              ref->details.admin_add_incoming.credit_account_no,
                              ref->details.admin_add_incoming.exchange_base_url,
                              &wtid))
    {
      GNUNET_break (0);
      fail (is);
      return;
    }
    if (0 != memcmp (&wtid,
                     &ref->details.admin_add_incoming.wtid,
                     sizeof (wtid)))
    {
      GNUNET_break (0);
      fail (is);
      return;
    }
    is->ip++;
    is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                         is);
   return;
  case TBI_OC_EXPECT_TRANSFERS_EMPTY:
    if (GNUNET_OK != TALER_FAKEBANK_check_empty (is->fakebank))
    {
      GNUNET_break (0);
      fail (is);
      return;
    }
    is->ip++;
    is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                         is);
    return;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unknown instruction %d at %u (%s)\n",
                cmd->oc,
                is->ip,
                cmd->label);
    fail (is);
    return;
  }
}


/**
 * Function run on timeout.
 *
 * @param cls the `struct InterpreterState`
 */
static void
do_timeout (void *cls)
{
  struct InterpreterState *is = cls;

  is->timeout_task = NULL;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Function run when the test terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls the interpreter state.
 */
static void
do_shutdown (void *cls)
{
  struct InterpreterState *is = cls;
  struct TBI_Command *cmd;
  unsigned int i;

  if (NULL != is->timeout_task)
  {
    GNUNET_SCHEDULER_cancel (is->timeout_task);
    is->timeout_task = NULL;
  }

  for (i=0;TBI_OC_END != (cmd = &is->commands[i])->oc;i++)
  {
    switch (cmd->oc)
    {
    case TBI_OC_END:
      GNUNET_assert (0);
      break;
    case TBI_OC_ADMIN_ADD_INCOMING:
      if (NULL != cmd->details.admin_add_incoming.aih)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Command %u (%s) did not complete\n",
                    i,
                    cmd->label);
        TALER_BANK_admin_add_incoming_cancel (cmd->details.admin_add_incoming.aih);
        cmd->details.admin_add_incoming.aih = NULL;
      }
      break;
    case TBI_OC_HISTORY:
      if (NULL != cmd->details.history.hh)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Command %u (%s) did not complete\n",
                    i,
                    cmd->label);
        TALER_BANK_history_cancel (cmd->details.history.hh);
        cmd->details.history.hh = NULL;
      }
      break;
    case TBI_OC_EXPECT_TRANSFER:
      break;
    case TBI_OC_EXPECT_TRANSFERS_EMPTY:
      break;
    default:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unknown instruction %d at %u (%s)\n",
                  cmd->oc,
                  i,
                  cmd->label);
      break;
    }
  }
  if (NULL != is->task)
  {
    GNUNET_SCHEDULER_cancel (is->task);
    is->task = NULL;
  }
  if (NULL != is->fakebank)
  {
    TALER_FAKEBANK_stop (is->fakebank);
    is->fakebank = NULL;
  }
  GNUNET_CURL_fini (is->ctx);
  is->ctx = NULL;
  GNUNET_CURL_gnunet_rc_destroy (is->rc);
  GNUNET_free (is);
}


/**
 * Entry point to the interpeter.
 *
 * @param resultp where to store the final result
 * @param run_bank #GNUNET_YES to run the fakebank
 * @param commands list of commands to run
 */
void
TBI_run_interpreter (int *resultp,
                     int run_bank,
                     struct TBI_Command *commands)
{
  struct InterpreterState *is;

  is = GNUNET_new (struct InterpreterState);
  if (GNUNET_YES == run_bank)
    is->fakebank = TALER_FAKEBANK_start (8081);
  is->resultp = resultp;
  is->commands = commands;
  is->ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                              &is->rc);
  GNUNET_assert (NULL != is->ctx);
  is->rc = GNUNET_CURL_gnunet_rc_create (is->ctx);
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
  is->timeout_task
    = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_relative_multiply
                                    (GNUNET_TIME_UNIT_SECONDS, 150),
                                    &do_timeout, is);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown, is);
}

/* end of test_bank_interpeter.c */
