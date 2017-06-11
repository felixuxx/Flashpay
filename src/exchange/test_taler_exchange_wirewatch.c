/*
  This file is part of TALER
  (C) 2016, 2017 Inria and GNUnet e.V.

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
 * @file exchange/test_taler_exchange_wirewatch.c
 * @brief Tests for taler-exchange-wirewatch and taler-exchange-aggregator logic;
 *        Performs an invalid wire transfer to the exchange, and then checks that
 *        wirewatch immediately sends the money back.
 *        Then performs a valid wire transfer, waits for the reserve to expire,
 *        and then checks that the aggregator sends the money back.
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>
#include "taler_fakebank_lib.h"



/**
 * Commands for the interpreter.
 */
enum OpCode {

  /**
   * Terminate testcase with 'skipped' result.
   */
  OPCODE_TERMINATE_SKIP,

  /**
   * Run taler-exchange-aggregator.
   */
  OPCODE_RUN_AGGREGATOR,

  /**
   * Expect that we have exhaustively gone over all transactions.
   */
  OPCODE_RUN_WIREWATCH,

  /**
   * Send money from bank to exchange.
   */
  OPCODE_RUN_TRANSFER,

  /**
   * Wait a certain amount of time.
   */
  OPCODE_WAIT,

  /**
   * Expect that we have received the specified transfer.
   */
  OPCODE_EXPECT_TRANSFER,

  /**
   * Expect that we have 'expected' all wire transfers.
   */
  OPCODE_EXPECT_TRANSFERS_EMPTY,

  /**
   * Finish testcase with success.
   */
  OPCODE_TERMINATE_SUCCESS
};


/**
 * Command state for the interpreter.
 */
struct Command
{

  /**
   * What instruction should we run?
   */
  enum OpCode opcode;

  /**
   * Human-readable label for the command.
   */
  const char *label;

  union {

    /**
     * If @e opcode is #OPCODE_EXPECT_TRANSFER, this
     * specifies which transaction we expected.  Note that
     * the WTID will be set, not checked!
     */
    struct {

      /**
       * Amount to be transferred.
       */
      const char *amount;

      /**
       * Account to debit.
       */
      uint64_t debit_account;

      /**
       * Account to credit.
       */
      uint64_t credit_account;

      /**
       * Expected base URL for the exchange.
       */
      const char *exchange_base_url;

      /**
       * Subject of the transfer, set by the command.
       */
      struct TALER_WireTransferIdentifierRawP wtid;

    } expect_transfer;


    /**
     * If @e opcode is #OPCODE_RUN_TRANSFER, this
     * specifies which transaction the bank should do.
     */
    struct {

      /**
       * Amount to be transferred.
       */
      const char *amount;

      /**
       * Account to debit.
       */
      uint64_t debit_account;

      /**
       * Account to credit.
       */
      uint64_t credit_account;

      /**
       * Subject of the transfer, set by the command.
       */
      const char *wtid;

    } run_transfer;

    struct {

      /**
       * The handle for the aggregator process that we are testing.
       */
      struct GNUNET_OS_Process *aggregator_proc;

      /**
       * ID of task called whenever we get a SIGCHILD.
       */
      struct GNUNET_SCHEDULER_Task *child_death_task;

    } aggregator;

    struct {

      /**
       * The handle for the wirewatch process that we are testing.
       */
      struct GNUNET_OS_Process *wirewatch_proc;

      /**
       * ID of task called whenever we get a SIGCHILD.
       */
      struct GNUNET_SCHEDULER_Task *child_death_task;

    } wirewatch;

    /**
     * How long should we wait if the opcode is #OPCODE_WAIT.
     */
    struct GNUNET_TIME_Relative wait_delay;

  } details;

};


/**
 * State of the interpreter.
 */
struct State
{
  /**
   * Array of commands to run.
   */
  struct Command* commands;

  /**
   * Offset of the next command to be run.
   */
  unsigned int ioff;
};


/**
 * Pipe used to communicate child death via signal.
 */
static struct GNUNET_DISK_PipeHandle *sigpipe;

/**
 * ID of task called whenever we time out.
 */
static struct GNUNET_SCHEDULER_Task *timeout_task;

/**
 * Return value from main().
 */
static int result;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;

/**
 * Task running the interpreter().
 */
static struct GNUNET_SCHEDULER_Task *int_task;

/**
 * Handle for our fake bank.
 */
static struct TALER_FAKEBANK_Handle *fb;


/**
 * Interprets the commands from the test program.
 *
 * @param cls the `struct State` of the interpreter
 */
static void
interpreter (void *cls);


/**
 * Advance the IP and run the next command.
 *
 * @param state interpreter to advance.
 */
static void
next_command (struct State *state)
{
  state->ioff++;
  int_task = GNUNET_SCHEDULER_add_now (&interpreter,
                                       state);
}


/**
 * Fail the testcase at the current command.
 */
static void
fail (struct Command *cmd)
{
  fprintf (stderr,
           "Testcase failed at command `%s'\n",
           cmd->label);
  result = 2;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Task triggered whenever we are to shutdown.
 *
 * @param cls closure, NULL if we need to self-restart
 */
static void
timeout_action (void *cls)
{
  timeout_task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Test failed: timeout\n");
  result = 2;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Task triggered whenever we are to shutdown.
 *
 * @param cls our `struct State`
 */
static void
shutdown_action (void *cls)
{
  struct State *state = cls;

  if (NULL != timeout_task)
  {
    GNUNET_SCHEDULER_cancel (timeout_task);
    timeout_task = NULL;
  }
  if (NULL != int_task)
  {
    GNUNET_SCHEDULER_cancel (int_task);
    int_task = NULL;
  }
  if (NULL != fb)
  {
    TALER_FAKEBANK_stop (fb);
    fb = NULL;
  }
  for (unsigned int i=0;i<=state->ioff;i++)
  {
    struct Command *cmd = &state->commands[i];

    switch (cmd->opcode)
    {
    case OPCODE_TERMINATE_SKIP:
      break;
    case OPCODE_RUN_AGGREGATOR:
      if (NULL != cmd->details.aggregator.child_death_task)
      {
        GNUNET_SCHEDULER_cancel (cmd->details.aggregator.child_death_task);
        cmd->details.aggregator.child_death_task = NULL;
      }
      if (NULL != cmd->details.aggregator.aggregator_proc)
      {
        GNUNET_break (0 == GNUNET_OS_process_kill (cmd->details.aggregator.aggregator_proc,
                                                   SIGKILL));
        GNUNET_OS_process_wait (cmd->details.aggregator.aggregator_proc);
        GNUNET_OS_process_destroy (cmd->details.aggregator.aggregator_proc);
        cmd->details.aggregator.aggregator_proc = NULL;
      }
      break;
    case OPCODE_RUN_WIREWATCH:
      if (NULL != cmd->details.wirewatch.child_death_task)
      {
        GNUNET_SCHEDULER_cancel (cmd->details.wirewatch.child_death_task);
        cmd->details.wirewatch.child_death_task = NULL;
      }
      if (NULL != cmd->details.wirewatch.wirewatch_proc)
      {
        GNUNET_break (0 == GNUNET_OS_process_kill (cmd->details.wirewatch.wirewatch_proc,
                                                   SIGKILL));
        GNUNET_OS_process_wait (cmd->details.wirewatch.wirewatch_proc);
        GNUNET_OS_process_destroy (cmd->details.wirewatch.wirewatch_proc);
        cmd->details.wirewatch.wirewatch_proc = NULL;
      }
      break;
    case OPCODE_RUN_TRANSFER:
      break;
    case OPCODE_WAIT:
      state->ioff++;
      int_task = GNUNET_SCHEDULER_add_delayed (cmd->details.wait_delay,
                                               &interpreter,
                                               state);
      break;
    case OPCODE_EXPECT_TRANSFER:
      break;
    case OPCODE_EXPECT_TRANSFERS_EMPTY:
      break;
    case OPCODE_TERMINATE_SUCCESS:
      break;
    }
  }
}


/**
 * Task triggered whenever we receive a SIGCHLD (child
 * process died).
 *
 * @param cls our `struct State`
 */
static void
maint_child_death (void *cls)
{
  struct State *state = cls;
  const struct GNUNET_DISK_FileHandle *pr;
  struct Command *cmd = &state->commands[state->ioff];
  char c[16];

  pr = GNUNET_DISK_pipe_handle (sigpipe,
                                GNUNET_DISK_PIPE_END_READ);
  GNUNET_break (0 < GNUNET_DISK_file_read (pr,
                                           &c,
                                           sizeof (c)));
  switch (cmd->opcode)
  {
  case OPCODE_RUN_AGGREGATOR:
    cmd->details.aggregator.child_death_task = NULL;
    GNUNET_OS_process_wait (cmd->details.aggregator.aggregator_proc);
    GNUNET_OS_process_destroy (cmd->details.aggregator.aggregator_proc);
    cmd->details.aggregator.aggregator_proc = NULL;
    break;
  case OPCODE_RUN_WIREWATCH:
    cmd->details.wirewatch.child_death_task = NULL;
    GNUNET_OS_process_wait (cmd->details.wirewatch.wirewatch_proc);
    GNUNET_OS_process_destroy (cmd->details.wirewatch.wirewatch_proc);
    cmd->details.wirewatch.wirewatch_proc = NULL;
    break;
  default:
    fail (cmd);
    return;
  }
  next_command (state);
}



/**
 * Interprets the commands from the test program.
 *
 * @param cls the `struct State` of the interpreter
 */
static void
interpreter (void *cls)
{
  struct State *state = cls;
  struct Command *cmd = &state->commands[state->ioff];

  int_task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running command %u (%s)\n",
              state->ioff,
              cmd->label);
  switch (cmd->opcode)
  {
  case OPCODE_TERMINATE_SKIP:
    /* return skip: test not finished, but did not fail either */
    result = 77;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case OPCODE_RUN_AGGREGATOR:
    cmd->details.aggregator.child_death_task =
      GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                      GNUNET_DISK_pipe_handle (sigpipe,
                                                               GNUNET_DISK_PIPE_END_READ),
                                      &maint_child_death,
                                      state);
    cmd->details.aggregator.aggregator_proc
      = GNUNET_OS_start_process (GNUNET_NO,
                                 GNUNET_OS_INHERIT_STD_ALL,
                                 NULL, NULL, NULL,
                                 "taler-exchange-aggregator",
                                 "taler-exchange-aggregator",
                                 "-c", config_filename,
                                 "-t", /* enable temporary tables */
                                 NULL);
    if (NULL == cmd->details.aggregator.aggregator_proc)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to start taler-exchange-aggregator. Check $PATH.\n");
      GNUNET_break (0);
      fail (cmd);
      return;
    }
    return;
  case OPCODE_RUN_WIREWATCH:
    cmd->details.wirewatch.child_death_task =
      GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                      GNUNET_DISK_pipe_handle (sigpipe,
                                                               GNUNET_DISK_PIPE_END_READ),
                                      &maint_child_death,
                                      state);
    cmd->details.wirewatch.wirewatch_proc
      = GNUNET_OS_start_process (GNUNET_NO,
                                 GNUNET_OS_INHERIT_STD_ALL,
                                 NULL, NULL, NULL,
                                 "taler-exchange-wirewatch",
                                 "taler-exchange-wirewatch",
                                 "-c", config_filename,
                                 "-t", "test",
                                 NULL);
    if (NULL == cmd->details.wirewatch.wirewatch_proc)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to start taler-exchange-wirewatch. Check $PATH.\n");
      GNUNET_break (0);
      fail (cmd);
      return;
    }
    return;
  case OPCODE_RUN_TRANSFER:
    GNUNET_break (0); // FIXME: not implemented!
    return;
  case OPCODE_WAIT:
    next_command (state);
    return;
  case OPCODE_EXPECT_TRANSFER:
    {
      struct TALER_Amount want_amount;

      if (GNUNET_OK !=
          TALER_string_to_amount (cmd->details.expect_transfer.amount,
                                  &want_amount))
      {
        GNUNET_break (0);
        fail (cmd);
        return;
      }
      if (GNUNET_OK !=
          TALER_FAKEBANK_check (fb,
                                &want_amount,
                                cmd->details.expect_transfer.debit_account,
                                cmd->details.expect_transfer.credit_account,
                                cmd->details.expect_transfer.exchange_base_url,
                                &cmd->details.expect_transfer.wtid))
      {
        fail (cmd);
        return;
      }
      next_command (state);
      return;
    }
  case OPCODE_EXPECT_TRANSFERS_EMPTY:
    if (GNUNET_OK != TALER_FAKEBANK_check_empty (fb))
    {
      fail (cmd);
      return;
    }
    next_command (state);
    break;
  case OPCODE_TERMINATE_SUCCESS:
    result = 0;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with configuration
 */
static void
run (void *cls)
{
  static struct Command commands[] = {
    /* test running with empty DB */
    {
      .opcode = OPCODE_EXPECT_TRANSFERS_EMPTY,
      .label = "expect-empty-transactions-on-start"
    },
    {
      .opcode = OPCODE_RUN_AGGREGATOR,
      .label = "run-aggregator-on-empty"
    },
    {
      .opcode = OPCODE_RUN_WIREWATCH,
      .label = "run-wirewatch-on-empty"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSFERS_EMPTY,
      .label = "expect-empty-transactions-after-dry-run"
    },
    {
      .opcode = OPCODE_TERMINATE_SUCCESS,
      .label = "testcase-complete-terminating-with-success"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSFER,
      .label = "expect-deposit-1",
      .details.expect_transfer.debit_account = 3,
      .details.expect_transfer.credit_account = 4,
      .details.expect_transfer.exchange_base_url = "https://exchange.taler.net/",
      .details.expect_transfer.amount = "EUR:0.89"
    },
    {
      .opcode = OPCODE_EXPECT_TRANSFERS_EMPTY,
      .label = "expect-empty-transactions-on-start"
    },
    {
      .opcode = OPCODE_TERMINATE_SUCCESS,
      .label = "testcase-complete-terminating-with-success"
    }
  };
  static struct State state = {
    .commands = commands
  };

  GNUNET_SCHEDULER_add_shutdown (&shutdown_action,
                                 &state);
  timeout_task = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_MINUTES,
                                               &timeout_action,
                                               &state);
  result = 1; /* test failed for undefined reason */
  fb = TALER_FAKEBANK_start (8082);
  if (NULL == fb)
  {
    GNUNET_SCHEDULER_shutdown ();
    result = 77;
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching interpreter\n");
  int_task = GNUNET_SCHEDULER_add_now (&interpreter,
                                       &state);
}


/**
 * Signal handler called for SIGCHLD.  Triggers the
 * respective handler by writing to the trigger pipe.
 */
static void
sighandler_child_death ()
{
  static char c;
  int old_errno = errno;	/* back-up errno */

  GNUNET_break (1 ==
		GNUNET_DISK_file_write (GNUNET_DISK_pipe_handle
					(sigpipe, GNUNET_DISK_PIPE_END_WRITE),
					&c, sizeof (c)));
  errno = old_errno;		/* restore errno */
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *testname;
  struct GNUNET_OS_Process *proc;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct GNUNET_SIGNAL_Context *shc_chld;

  result = -1;
  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-taler-exchange-wirewatch-%s",
                          plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf",
                          testname);
  /* these might get in the way */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test_taler_exchange_wirewatch",
                    "WARNING",
                    NULL);
  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-keyup",
                                  "taler-exchange-keyup",
                                  "-c", config_filename,
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-keyup`, is your PATH correct?\n");
    return 77;
  }
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     8082))
  {
    fprintf (stderr,
             "Required port %u not available, skipping.\n",
	     8082);
    return 77;
  }
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_filename))
  {
    GNUNET_break (0);
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 2;
  }
  sigpipe = GNUNET_DISK_pipe (GNUNET_NO, GNUNET_NO,
                              GNUNET_NO, GNUNET_NO);
  GNUNET_assert (NULL != sigpipe);
  shc_chld =
    GNUNET_SIGNAL_handler_install (GNUNET_SIGCHLD,
                                   &sighandler_child_death);
  GNUNET_SCHEDULER_run (&run,
                        cfg);
  GNUNET_SIGNAL_handler_uninstall (shc_chld);
  GNUNET_DISK_pipe_close (sigpipe);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}

/* end of test_taler_exchange_wirewatch.c */
