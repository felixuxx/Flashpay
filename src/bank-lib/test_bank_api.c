/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank/test_bank_api.c
 * @brief testcase to test bank's HTTP API interface
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>


/**
 * Main execution context for the main loop.
 */
static struct TALER_BANK_Context *ctx;

/**
 * Task run on shutdown.
 */
static struct GNUNET_SCHEDULER_Task *shutdown_task;

/**
 * Task that runs the main event loop.
 */
static struct GNUNET_SCHEDULER_Task *ctx_task;

/**
 * Result of the testcases, #GNUNET_OK on success
 */
static int result;


/**
 * Opcodes for the interpreter.
 */
enum OpCode
{
  /**
   * Termination code, stops the interpreter loop (with success).
   */
  OC_END = 0,

  /**
   * Add funds to a reserve by (faking) incoming wire transfer.
   */
  OC_ADMIN_ADD_INCOMING

};


/**
 * Details for a bank operation to execute.
 */
struct Command
{
  /**
   * Opcode of the command.
   */
  enum OpCode oc;

  /**
   * Label for the command, can be NULL.
   */
  const char *label;

  /**
   * Which response code do we expect for this command?
   */
  unsigned int expected_response_code;

  /**
   * Details about the command.
   */
  union
  {

    /**
     * Information for a #OC_ADMIN_ADD_INCOMING command.
     */
    struct
    {

      /**
       * String describing the amount to add to the reserve.
       */
      const char *amount;

      /**
       * Credited account number.
       */
      uint64_t credit_account_no;

      /**
       * Debited account number.
       */
      uint64_t debit_account_no;

      /**
       * Wire transfer identifier to use.  Initialized to
       * a random value.
       */
      struct TALER_WireTransferIdentifierRawP wtid;

      /**
       * Set to the API's handle during the operation.
       */
      struct TALER_BANK_AdminAddIncomingHandle *aih;

    } admin_add_incoming;

  } details;

};


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
  struct Command *commands;

  /**
   * Interpreter task (if one is scheduled).
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Instruction pointer.  Tells #interpreter_run() which
   * instruction to run next.
   */
  unsigned int ip;

};


/**
 * Task that runs the context's event loop with the GNUnet scheduler.
 *
 * @param cls unused
 */
static void
context_task (void *cls);


/**
 * Run the context task, the working set has changed.
 */
static void
trigger_context_task ()
{
  GNUNET_SCHEDULER_cancel (ctx_task);
  ctx_task = GNUNET_SCHEDULER_add_now (&context_task,
                                       NULL);
}


/**
 * The testcase failed, return with an error code.
 *
 * @param is interpreter state to clean up
 */
static void
fail (struct InterpreterState *is)
{
  result = GNUNET_SYSERR;
  GNUNET_SCHEDULER_shutdown ();
}


#if 0
/**
 * Find a command by label.
 *
 * @param is interpreter state to search
 * @param label label to look for
 * @return NULL if command was not found
 */
static const struct Command *
find_command (const struct InterpreterState *is,
              const char *label)
{
  unsigned int i;
  const struct Command *cmd;

  if (NULL == label)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Attempt to lookup command for empty label\n");
    return NULL;
  }
  for (i=0;OC_END != (cmd = &is->commands[i])->oc;i++)
    if ( (NULL != cmd->label) &&
         (0 == strcmp (cmd->label,
                       label)) )
      return cmd;
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Command not found: %s\n",
              label);
  return NULL;
}
#endif


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
                 json_t *json)
{
  struct InterpreterState *is = cls;
  struct Command *cmd = &is->commands[is->ip];

  cmd->details.admin_add_incoming.aih = NULL;
  if (cmd->expected_response_code != http_status)
  {
    GNUNET_break (0);
    if (NULL != json)
    {
      fprintf (stderr,
               "Unexpected response code %u:\n",
               http_status);
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
 * Run the main interpreter loop that performs bank operations.
 *
 * @param cls contains the `struct InterpreterState`
 */
static void
interpreter_run (void *cls)
{
  struct InterpreterState *is = cls;
  struct Command *cmd = &is->commands[is->ip];
  struct TALER_Amount amount;
  const struct GNUNET_SCHEDULER_TaskContext *tc;

  is->task = NULL;
  tc = GNUNET_SCHEDULER_get_task_context ();
  if (0 != (tc->reason & GNUNET_SCHEDULER_REASON_SHUTDOWN))
  {
    fprintf (stderr,
             "Test aborted by shutdown request\n");
    fail (is);
    return;
  }
  switch (cmd->oc)
  {
  case OC_END:
    result = GNUNET_OK;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case OC_ADMIN_ADD_INCOMING:

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
      = TALER_BANK_admin_add_incoming (ctx,
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
    trigger_context_task ();
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
 * Function run when the test terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls the interpreter state.
 */
static void
do_shutdown (void *cls)
{
  struct InterpreterState *is = cls;
  struct Command *cmd;
  unsigned int i;

  shutdown_task = NULL;
  for (i=0;OC_END != (cmd = &is->commands[i])->oc;i++)
  {
    switch (cmd->oc)
    {
    case OC_END:
      GNUNET_assert (0);
      break;
    case OC_ADMIN_ADD_INCOMING:
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
  GNUNET_free (is);
  if (NULL != ctx_task)
  {
    GNUNET_SCHEDULER_cancel (ctx_task);
    ctx_task = NULL;
  }
  if (NULL != ctx)
  {
    TALER_BANK_fini (ctx);
    ctx = NULL;
  }
}


/**
 * Task that runs the context's event loop with the GNUnet scheduler.
 *
 * @param cls unused
 */
static void
context_task (void *cls)
{
  long timeout;
  int max_fd;
  fd_set read_fd_set;
  fd_set write_fd_set;
  fd_set except_fd_set;
  struct GNUNET_NETWORK_FDSet *rs;
  struct GNUNET_NETWORK_FDSet *ws;
  struct GNUNET_TIME_Relative delay;

  ctx_task = NULL;
  TALER_BANK_perform (ctx);
  max_fd = -1;
  timeout = -1;
  FD_ZERO (&read_fd_set);
  FD_ZERO (&write_fd_set);
  FD_ZERO (&except_fd_set);
  TALER_BANK_get_select_info (ctx,
                              &read_fd_set,
                              &write_fd_set,
                              &except_fd_set,
                              &max_fd,
                              &timeout);
  if (timeout >= 0)
    delay = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                           timeout);
  else
    delay = GNUNET_TIME_UNIT_FOREVER_REL;
  rs = GNUNET_NETWORK_fdset_create ();
  GNUNET_NETWORK_fdset_copy_native (rs,
                                    &read_fd_set,
                                    max_fd + 1);
  ws = GNUNET_NETWORK_fdset_create ();
  GNUNET_NETWORK_fdset_copy_native (ws,
                                    &write_fd_set,
                                    max_fd + 1);
  ctx_task = GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_DEFAULT,
                                          delay,
                                          rs,
                                          ws,
                                          &context_task,
                                          cls);
  GNUNET_NETWORK_fdset_destroy (rs);
  GNUNET_NETWORK_fdset_destroy (ws);
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 */
static void
run (void *cls)
{
  struct InterpreterState *is;
  static struct Command commands[] =
  {
    /* Add EUR:5.01 to account 42 */
    { .oc = OC_ADMIN_ADD_INCOMING,
      .label = "deposit-1",
      .expected_response_code = MHD_HTTP_OK,
      .details.admin_add_incoming.credit_account_no = 0,
      .details.admin_add_incoming.debit_account_no = 1,
      .details.admin_add_incoming.amount = "EUR:5.01" },

    { .oc = OC_END }
  };

  is = GNUNET_new (struct InterpreterState);
  is->commands = commands;

  ctx = TALER_BANK_init ("http://localhost:8081");
  GNUNET_assert (NULL != ctx);
  ctx_task = GNUNET_SCHEDULER_add_now (&context_task,
                                       ctx);
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
  shutdown_task
    = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_relative_multiply
                                    (GNUNET_TIME_UNIT_SECONDS, 150),
                                    &do_shutdown, is);
}


/**
 * Main function for the testcase for the bank API.
 *
 * @param argc expected to be 1
 * @param argv expected to only contain the program name
 */
int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *bankd;
  unsigned int cnt;

  GNUNET_log_setup ("test-bank-api",
                    "WARNING",
                    NULL);
  bankd = GNUNET_OS_start_process (GNUNET_NO,
                                   GNUNET_OS_INHERIT_STD_ALL,
                                   NULL, NULL, NULL,
                                   "taler-bank-manage",
                                   "taler-bank-manage",
                                   "--bareserver", "8081",
                                   NULL);
  if (NULL == bankd)
  {
    fprintf (stderr,
             "taler-bank-manage not found, skipping test\n");
    return 77; /* report 'skip' */
  }
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for taler-bank-manage to be ready");
  cnt = 0;
  do
    {
      fprintf (stderr, ".");
      sleep (1);
      cnt++;
      if (cnt > 30)
        break;
    }
  while (0 != system ("wget -q -t 1 -T 1 http://127.0.0.1:8081/ -o /dev/null -O /dev/null"));
  fprintf (stderr, "\n");
  result = GNUNET_SYSERR;
  if (cnt <= 30)
    GNUNET_SCHEDULER_run (&run, NULL);
  GNUNET_OS_process_kill (bankd,
                          SIGTERM);
  GNUNET_OS_process_wait (bankd);
  GNUNET_OS_process_destroy (bankd);
  if (cnt > 30)
  {
    fprintf (stderr,
             "taler-bank-manage failed to start properly.\n");
    return 77;
  }
  return (GNUNET_OK == result) ? 0 : 1;
}

/* end of test_bank_api.c */
