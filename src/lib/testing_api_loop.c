/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file exchange-lib/testing_api_loop.c
 * @brief main interpreter loop for testcases
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"

/**
 * Pipe used to communicate child death via signal.
 * Must be global, as used in signal handler!
 */
static struct GNUNET_DISK_PipeHandle *sigpipe;

/**
 * Lookup command by label.
 *
 * @param is interpreter state to search
 * @param label label to look for
 * @return NULL if command was not found
 */
const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_lookup_command
  (struct TALER_TESTING_Interpreter *is,
  const char *label)
{
  if (NULL == label)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Attempt to lookup command for empty label\n");
    return NULL;
  }
  /* Search backwards as we most likely reference recent commands */
  for (int i = is->ip; i >= 0; i--)
  {
    const struct TALER_TESTING_Command *cmd = &is->commands[i];

    /* Give precedence to top-level commands.  */
    if ( (NULL != cmd->label) &&
         (0 == strcmp (cmd->label,
                       label)) )
      return cmd;

    if (TALER_TESTING_cmd_is_batch (cmd))
    {
#define BATCH_INDEX 1
      struct TALER_TESTING_Command *batch;

      GNUNET_assert (GNUNET_OK ==
                     TALER_TESTING_get_trait_cmd (cmd,
                                                  BATCH_INDEX,
                                                  &batch));
      for (unsigned int j = 0;
           NULL != (cmd = &batch[j])->label;
           j++)
      {
        if ( (NULL != cmd->label) &&
             (0 == strcmp (cmd->label,
                           label)) )
          return cmd;
      }
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Command not found: %s\n",
              label);
  return NULL;

}


/**
 * Obtain main execution context for the main loop.
 */
struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context
  (struct TALER_TESTING_Interpreter *is)
{
  return is->ctx;
}


struct TALER_FAKEBANK_Handle *
TALER_TESTING_interpreter_get_fakebank
  (struct TALER_TESTING_Interpreter *is)
{
  return is->fakebank;
}


/**
 * Run tests starting the "fakebank" first.  The "fakebank"
 * is a C minimalist version of the human-oriented Python bank,
 * which is also part of the Taler project.
 *
 * @param is pointer to the interpreter state
 * @param commands the list of commands to execute
 * @param bank_url the url the fakebank is supposed to run on
 */
void
TALER_TESTING_run_with_fakebank
  (struct TALER_TESTING_Interpreter *is,
  struct TALER_TESTING_Command *commands,
  const char *bank_url)
{
  const char *port;
  long pnum;

  port = strrchr (bank_url,
                  (unsigned char) ':');
  if (NULL == port)
    pnum = 80;
  else
    pnum = strtol (port + 1, NULL, 10);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting Fakebank on port %u (%s)\n",
              (unsigned int) pnum,
              bank_url);
  is->fakebank = TALER_FAKEBANK_start ((uint16_t) pnum);
  if (NULL == is->fakebank)
  {
    GNUNET_break (0);
    is->result = GNUNET_SYSERR;
    return;
  }
  TALER_TESTING_run (is,
                     commands);
}


/**
 * Run the main interpreter loop that performs exchange operations.
 *
 * @param cls contains the `struct InterpreterState`
 */
static void
interpreter_run (void *cls);


/**
 * Current command is done, run the next one.
 */
void
TALER_TESTING_interpreter_next (struct TALER_TESTING_Interpreter *is)
{
  static unsigned long long ipc;
  static struct GNUNET_TIME_Absolute last_report;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  if (GNUNET_SYSERR == is->result)
    return; /* ignore, we already failled! */
  if (TALER_TESTING_cmd_is_batch (cmd))
    TALER_TESTING_cmd_batch_next (is);
  else
    is->ip++;
  if (0 == (ipc % 1000))
  {
    if (0 != ipc)
      GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                  "Interpreter executed 1000 instructions in %s\n",
                  GNUNET_STRINGS_relative_time_to_string (
                    GNUNET_TIME_absolute_get_duration (last_report),
                    GNUNET_YES));
    last_report = GNUNET_TIME_absolute_get ();
  }
  ipc++;
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
}


/**
 * Current command failed, clean up and fail the test case.
 *
 * @param is interpreter of the test
 */
void
TALER_TESTING_interpreter_fail
  (struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Failed at command `%s'\n",
              cmd->label);
  while (TALER_TESTING_cmd_is_batch (cmd))
  {
    cmd = TALER_TESTING_cmd_batch_get_current (cmd);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Batch is at command `%s'\n",
                cmd->label);
  }
  is->result = GNUNET_SYSERR;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Create command array terminator.
 *
 * @return a end-command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_end (void)
{
  static struct TALER_TESTING_Command cmd;
  cmd.label = NULL;

  return cmd;
}


/**
 * Obtain current label.
 */
const char *
TALER_TESTING_interpreter_get_current_label
  (struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  return cmd->label;
}


/**
 * Run the main interpreter loop that performs exchange operations.
 *
 * @param cls contains the `struct TALER_TESTING_Interpreter`
 */
static void
interpreter_run (void *cls)
{
  struct TALER_TESTING_Interpreter *is = cls;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  is->task = NULL;

  if (NULL == cmd->label)
  {

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Running command END\n");
    is->result = GNUNET_OK;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Running command `%s'\n",
              cmd->label);

  cmd->run (cmd->cls,
            cmd,
            is);
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
  struct TALER_TESTING_Interpreter *is = cls;
  struct TALER_TESTING_Command *cmd;
  const char *label;

  label = is->commands[is->ip].label;
  if (NULL == label)
    label = "END";

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Executing shutdown at `%s'\n",
              label);

  for (unsigned int j = 0;
       NULL != (cmd = &is->commands[j])->label;
       j++)
    cmd->cleanup (cmd->cls,
                  cmd);

  if (NULL != is->exchange)
  {
    TALER_LOG_DEBUG ("Disconnecting the exchange\n");
    TALER_EXCHANGE_disconnect (is->exchange);
    is->exchange = NULL;
  }
  if (NULL != is->task)
  {
    GNUNET_SCHEDULER_cancel (is->task);
    is->task = NULL;
  }
  if (NULL != is->ctx)
  {
    GNUNET_CURL_fini (is->ctx);
    is->ctx = NULL;
  }
  if (NULL != is->rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (is->rc);
    is->rc = NULL;
  }
  if (NULL != is->timeout_task)
  {
    GNUNET_SCHEDULER_cancel (is->timeout_task);
    is->timeout_task = NULL;
  }
  if (NULL != is->child_death_task)
  {
    GNUNET_SCHEDULER_cancel (is->child_death_task);
    is->child_death_task = NULL;
  }
  if (NULL != is->fakebank)
  {
    TALER_FAKEBANK_stop (is->fakebank);
    is->fakebank = NULL;
  }
  GNUNET_free_non_null (is->commands);
}


/**
 * Function run when the test terminates (good or bad) with timeout.
 *
 * @param cls NULL
 */
static void
do_timeout (void *cls)
{
  struct TALER_TESTING_Interpreter *is = cls;

  is->timeout_task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Terminating test due to timeout\n");
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Task triggered whenever we receive a SIGCHLD (child
 * process died).
 *
 * @param cls closure
 */
static void
maint_child_death (void *cls)
{
  struct TALER_TESTING_Interpreter *is = cls;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];
  const struct GNUNET_DISK_FileHandle *pr;

  struct GNUNET_OS_Process **processp;
  char c[16];

  if (TALER_TESTING_cmd_is_batch (cmd))
  {
    struct TALER_TESTING_Command *batch_cmd;

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_get_trait_cmd
        (cmd, 0, &batch_cmd)); /* bad? */
    cmd = batch_cmd;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Got SIGCHLD for `%s'.\n",
              cmd->label);

  is->child_death_task = NULL;
  pr = GNUNET_DISK_pipe_handle (sigpipe,
                                GNUNET_DISK_PIPE_END_READ);
  GNUNET_break (0 <
                GNUNET_DISK_file_read (pr,
                                       &c,
                                       sizeof (c)));
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_process (cmd,
                                       0,
                                       &processp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Got the dead child process handle"
              ", waiting for termination ...\n");

  GNUNET_OS_process_wait (*processp);
  GNUNET_OS_process_destroy (*processp);
  *processp = NULL;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "... definitively terminated\n");

  if (GNUNET_OK == is->reload_keys)
  {
    if (NULL == is->exchanged)
    {
      GNUNET_break (0);
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Triggering key state reload at exchange\n");
      GNUNET_break (0 == GNUNET_OS_process_kill
                      (is->exchanged, SIGUSR1));
      sleep (5); /* make sure signal was received and processed */
    }
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Dead child, go on with next command.\n");
  TALER_TESTING_interpreter_next (is);
}


/**
 * Wait until we receive SIGCHLD signal.
 * Then obtain the process trait of the current
 * command, wait on the the zombie and continue
 * with the next command.
 */
void
TALER_TESTING_wait_for_sigchld
  (struct TALER_TESTING_Interpreter *is)
{
  const struct GNUNET_DISK_FileHandle *pr;

  GNUNET_assert (NULL == is->child_death_task);
  pr = GNUNET_DISK_pipe_handle (sigpipe,
                                GNUNET_DISK_PIPE_END_READ);
  is->child_death_task
    = GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                      pr,
                                      &maint_child_death,
                                      is);
}


/**
 * Run the testsuite.  Note, CMDs are copied into
 * the interpreter state because they are _usually_
 * defined into the "run" method that returns after
 * having scheduled the test interpreter.
 *
 * @param is the interpreter state
 * @param commands the list of command to execute
 * @param timeout how long to wait
 */
void
TALER_TESTING_run2 (struct TALER_TESTING_Interpreter *is,
                    struct TALER_TESTING_Command *commands,
                    struct GNUNET_TIME_Relative timeout)
{
  unsigned int i;

  if (NULL != is->timeout_task)
  {
    GNUNET_SCHEDULER_cancel (is->timeout_task);
    is->timeout_task = NULL;
  }
  /* get the number of commands */
  for (i = 0; NULL != commands[i].label; i++);
  is->commands = GNUNET_new_array (i + 1,
                                   struct TALER_TESTING_Command);
  memcpy (is->commands,
          commands,
          sizeof (struct TALER_TESTING_Command) * i);
  is->timeout_task = GNUNET_SCHEDULER_add_delayed
                       (timeout,
                       &do_timeout,
                       is);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown, is);
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run, is);
}


/**
 * Run the testsuite.  Note, CMDs are copied into
 * the interpreter state because they are _usually_
 * defined into the "run" method that returns after
 * having scheduled the test interpreter.
 *
 * @param is the interpreter state
 * @param commands the list of command to execute
 */
void
TALER_TESTING_run (struct TALER_TESTING_Interpreter *is,
                   struct TALER_TESTING_Command *commands)
{
  TALER_TESTING_run2 (is,
                      commands,
                      GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES,
                                                     5));
}


/**
 * Information used by the wrapper around the main
 * "run" method.
 */
struct MainContext
{
  /**
   * Main "run" method.
   */
  TALER_TESTING_Main main_cb;

  /**
   * Closure for @e main_cb.
   */
  void *main_cb_cls;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Configuration filename.  The wrapper uses it to fetch
   * the exchange port number; We could have passed the port
   * number here, but having the config filename seems more
   * generic.
   */
  const char *config_filename;

  /**
   * URL of the exchange.
   */
  char *exchange_url;

};


/**
 * Signal handler called for SIGCHLD.  Triggers the
 * respective handler by writing to the trigger pipe.
 */
static void
sighandler_child_death ()
{
  static char c;
  int old_errno = errno;  /* back-up errno */

  GNUNET_break (1 == GNUNET_DISK_file_write
                  (GNUNET_DISK_pipe_handle (sigpipe,
                                            GNUNET_DISK_PIPE_END_WRITE),
                  &c, sizeof (c)));
  errno = old_errno;    /* restore errno */
}


/**
 * "Canonical" cert_cb used when we are connecting to the
 * Exchange.
 *
 * @param cls closure, typically, the "run" method containing
 *        all the commands to be run, and a closure for it.
 * @param keys the exchange's keys.
 * @param compat protocol compatibility information.
 */
void
TALER_TESTING_cert_cb
  (void *cls,
  const struct TALER_EXCHANGE_Keys *keys,
  enum TALER_EXCHANGE_VersionCompatibility compat)
{
  struct MainContext *main_ctx = cls;
  struct TALER_TESTING_Interpreter *is = main_ctx->is;

  if (NULL == keys)
  {
    if (GNUNET_NO == is->working)
    {
      GNUNET_log
        (GNUNET_ERROR_TYPE_WARNING,
        "Got NULL response for /keys"
        " during startup, retrying!\n");
      TALER_EXCHANGE_disconnect (is->exchange);
      GNUNET_assert
        (NULL != (is->exchange = TALER_EXCHANGE_connect
                                   (is->ctx,
                                   main_ctx->exchange_url,
                                   &TALER_TESTING_cert_cb,
                                   main_ctx,
                                   TALER_EXCHANGE_OPTION_END)));
      return;
    }
    else
      GNUNET_log
        (GNUNET_ERROR_TYPE_ERROR,
        "Got NULL response for /keys"
        " during execution!\n");
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Got %d DK from /keys in generation %u\n",
                keys->num_denom_keys,
                is->key_generation + 1);
  }
  is->key_generation++;
  is->keys = keys;

  /* /keys has been called for some reason and
   * the interpreter is already running. */
  if (GNUNET_YES == is->working)
    return;

  is->working = GNUNET_YES;

  /* Very first start of tests, call "run()" */
  if (1 == is->key_generation)
  {
    main_ctx->main_cb (main_ctx->main_cb_cls,
                       is);
    return;
  }

  /* Tests already started, just trigger the
   * next command. */
  TALER_LOG_DEBUG ("Cert_cb, scheduling CMD (ip: %d)\n",
                   is->ip);
  GNUNET_SCHEDULER_add_now (&interpreter_run,
                            is);
}


/**
 * Initialize scheduler loop and curl context for the testcase,
 * and responsible to run the "run" method.
 *
 * @param cls closure, typically the "run" method, the
 *        interpreter state and a closure for "run".
 */
static void
main_wrapper_exchange_agnostic (void *cls)
{
  struct MainContext *main_ctx = cls;

  main_ctx->main_cb (main_ctx->main_cb_cls,
                     main_ctx->is);
}


/**
 * Function run when the test is aborted before we launch the actual
 * interpreter.  Cleans up our state.
 *
 * @param cls the main context
 */
static void
do_abort (void *cls)
{
  struct MainContext *main_ctx = cls;
  struct TALER_TESTING_Interpreter *is = main_ctx->is;

  is->timeout_task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Executing abort prior to interpreter launch\n");
  if (NULL != is->exchange)
  {
    TALER_EXCHANGE_disconnect (is->exchange);
    is->exchange = NULL;
  }
}


/**
 * Initialize scheduler loop and curl context for the testcase,
 * and responsible to run the "run" method.
 *
 * @param cls a `struct MainContext *`
 * @param cfg configuration to use
 */
static int
main_exchange_connect_with_cfg
  (void *cls,
  const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct MainContext *main_ctx = cls;
  struct TALER_TESTING_Interpreter *is = main_ctx->is;
  char *exchange_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  main_ctx->exchange_url = exchange_url;
  is->cfg = cfg;
  is->timeout_task = GNUNET_SCHEDULER_add_shutdown (&do_abort,
                                                    main_ctx);
  GNUNET_break
    (NULL != (is->exchange = TALER_EXCHANGE_connect
                               (is->ctx,
                               exchange_url,
                               &TALER_TESTING_cert_cb,
                               main_ctx,
                               TALER_EXCHANGE_OPTION_END)));
  is->cfg = NULL;
  return GNUNET_OK;
}


/**
 * Initialize scheduler loop and curl context for the testcase,
 * and responsible to run the "run" method.
 *
 * @param cls a `struct MainContext *`
 */
static void
main_wrapper_exchange_connect (void *cls)
{
  struct MainContext *main_ctx = cls;

  GNUNET_break (GNUNET_OK ==
                GNUNET_CONFIGURATION_parse_and_run (main_ctx->config_filename,
                                                    &
                                                    main_exchange_connect_with_cfg,
                                                    main_ctx));
}


/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which contains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param config_filename configuration filename.
 * @param exchanged exchange process handle: will be put in the
 *        state as some commands - e.g. revoke - need to send
 *        signal to it, for example to let it know to reload the
 *        key state.. if NULL, the interpreter will run without
 *        trying to connect to the exchange first.
 * @param exchange_connect #GNUNET_YES if the test should connect
 *        to the exchange, #GNUNET_NO otherwise
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         times.
 */
int
TALER_TESTING_setup (TALER_TESTING_Main main_cb,
                     void *main_cb_cls,
                     const char *config_filename,
                     struct GNUNET_OS_Process *exchanged,
                     int exchange_connect)
{
  struct TALER_TESTING_Interpreter is;
  struct MainContext main_ctx = {
    .main_cb = main_cb,
    .main_cb_cls = main_cb_cls,
    /* needed to init the curl ctx */
    .is = &is,
    /* needed to read values like exchange port
     * number to construct the exchange url.*/
    .config_filename = config_filename
  };
  struct GNUNET_SIGNAL_Context *shc_chld;

  memset (&is,
          0,
          sizeof (is));
  is.exchanged = exchanged;
  sigpipe = GNUNET_DISK_pipe (GNUNET_NO, GNUNET_NO,
                              GNUNET_NO, GNUNET_NO);
  GNUNET_assert (NULL != sigpipe);
  shc_chld = GNUNET_SIGNAL_handler_install
               (GNUNET_SIGCHLD,
               &sighandler_child_death);
  is.ctx = GNUNET_CURL_init
             (&GNUNET_CURL_gnunet_scheduler_reschedule,
             &is.rc);
  GNUNET_CURL_enable_async_scope_header (is.ctx, "Taler-Correlation-Id");
  GNUNET_assert (NULL != is.ctx);
  is.rc = GNUNET_CURL_gnunet_rc_create (is.ctx);

  /* Blocking */

  if (GNUNET_YES == exchange_connect)
    GNUNET_SCHEDULER_run (&main_wrapper_exchange_connect,
                          &main_ctx);
  else
    GNUNET_SCHEDULER_run (&main_wrapper_exchange_agnostic,
                          &main_ctx);
  if (NULL != is.final_cleanup_cb)
    is.final_cleanup_cb (is.final_cleanup_cb_cls);
  GNUNET_free_non_null (main_ctx.exchange_url);
  GNUNET_SIGNAL_handler_uninstall (shc_chld);
  GNUNET_DISK_pipe_close (sigpipe);
  sigpipe = NULL;
  return is.result;
}

/* end of testing_api_loop.c */
