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
  const struct TALER_TESTING_Command *cmd;

  if (NULL == label)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Attempt to lookup command for empty label\n");
    return NULL;
  }
  for (unsigned int i=0;
       NULL != (cmd = &is->commands[i])->label;
       i++)
  {
    /* Give precedence to top-level commands.  */
    if ( (NULL != cmd->label) &&
         (0 == strcmp (cmd->label,
                       label)) )
      return cmd;

    if (GNUNET_YES == cmd->meta)
    {
      #define BATCH_INDEX 1
      struct TALER_TESTING_Command *batch;

      GNUNET_assert
        (GNUNET_OK == TALER_TESTING_get_trait_cmd
          (cmd, BATCH_INDEX, &batch));

      for (unsigned int i=0;
           NULL != (cmd = &batch[i])->label;
           i++) 
      {
        if ( (NULL != cmd->label) &&
            (0 == strcmp (cmd->label,
                          label)) )
          return cmd;
      }
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
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
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  if (GNUNET_SYSERR == is->result)
    return; /* ignore, we already failed! */

  if (GNUNET_YES == cmd->meta)
  {
    #define CURRENT_BATCH_SUBCMD_INDEX 0
    struct TALER_TESTING_Command *sub_cmd;

    GNUNET_assert (GNUNET_OK == TALER_TESTING_get_trait_cmd
      (cmd, CURRENT_BATCH_SUBCMD_INDEX, &sub_cmd));
      
      if (NULL == sub_cmd->label)
        is->ip++;
  }
  else
    is->ip++;

  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run, is);
}


/**
 * Current command failed, clean up and fail the test case.
 */
void
TALER_TESTING_interpreter_fail
  (struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Failed at command `%s'\n",
              cmd->label);

  is->result = GNUNET_SYSERR;
  // this cleans up too.
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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Executing shutdown at `%s'\n",
              is->commands[is->ip].label);
  for (unsigned int j=0;NULL != (cmd = &is->commands[j])->label;j++)
    cmd->cleanup (cmd->cls,
                  cmd);
  if (NULL != is->exchange)
  {
    TALER_EXCHANGE_disconnect (is->exchange);
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

  if (GNUNET_YES == cmd->meta)
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
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Triggering key state reload at exchange\n");
    GNUNET_break (0 == GNUNET_OS_process_kill
    (is->exchanged, SIGUSR1));
    sleep (5); /* make sure signal was received and processed */
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
 *
 * @param is the interpreter state
 * @param commands the list of command to execute
 */
void
TALER_TESTING_run (struct TALER_TESTING_Interpreter *is,
                   struct TALER_TESTING_Command *commands)
{
  unsigned int i;
  /* get the number of commands */
  for (i=0;NULL != commands[i].label;i++) ;

  is->commands = GNUNET_new_array (i + 1,
                                   struct TALER_TESTING_Command);
  memcpy (is->commands,
          commands,
          sizeof (struct TALER_TESTING_Command) * i);
  is->timeout_task = GNUNET_SCHEDULER_add_delayed
    (GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_SECONDS, 300),
     &do_timeout, is);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown, is);
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run, is);
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
   * Closure for "run".
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

};


/**
 * Signal handler called for SIGCHLD.  Triggers the
 * respective handler by writing to the trigger pipe.
 */
static void
sighandler_child_death ()
{
  static char c;
  int old_errno = errno;	/* back-up errno */

  GNUNET_break (1 == GNUNET_DISK_file_write
    (GNUNET_DISK_pipe_handle (sigpipe, GNUNET_DISK_PIPE_END_WRITE),
     &c, sizeof (c)));
  errno = old_errno;		/* restore errno */
}


/**
 * Called once a connection to the exchange has been
 * established.
 *
 * @param cls closure, typically, the "run" method containing
 *        all the commands to be run, and a closure for it.
 * @param keys the exchange's keys.
 * @param compat protocol compatibility information.
 */
void
cert_cb (void *cls,
         const struct TALER_EXCHANGE_Keys *keys,
	 enum TALER_EXCHANGE_VersionCompatibility compat)
{
  struct MainContext *main_ctx = cls;

  if (NULL == keys)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Got NULL response for /keys\n");

  }
  else
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Got %d DK from /keys\n",
                keys->num_denom_keys);

  main_ctx->is->key_generation++;
  main_ctx->is->keys = keys;

  /* /keys has been called for some reason and
   * the interpreter is already running. */
  if (GNUNET_YES == main_ctx->is->working)
    return;

  main_ctx->is->working = GNUNET_YES;

  /* Very first start of tests, call "run()" */
  if (1 == main_ctx->is->key_generation)
  {
    main_ctx->main_cb (main_ctx->main_cb_cls,
                       main_ctx->is);
    return;
  }

  /* Tests already started, just trigger the
   * next command. */
  GNUNET_SCHEDULER_add_now (&interpreter_run,
                            main_ctx->is);
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
 * Initialize scheduler loop and curl context for the testcase,
 * and responsible to run the "run" method.
 *
 * @param cls closure, typically the "run" method, the
 *        interpreter state and a closure for "run".
 */
static void
main_wrapper_exchange_connect (void *cls)
{
  struct MainContext *main_ctx = cls;
  struct TALER_TESTING_Interpreter *is = main_ctx->is;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *exchange_url;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load
    (cfg, main_ctx->config_filename))
    return;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    GNUNET_CONFIGURATION_destroy (cfg);
    return;
  }
  GNUNET_assert ( NULL !=
    (is->exchange = TALER_EXCHANGE_connect (is->ctx,
                                            exchange_url,
                                            cert_cb,
                                            main_ctx)) );
  GNUNET_free (exchange_url);
  GNUNET_CONFIGURATION_destroy (cfg);
}


/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which coontains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param config_filename configuration filename.
 * @param exchanged exchange process handle: will be put in the
 *        state as some commands - e.g. revoke - need to send
 *        signal to it, for example to let it know to reload the
 *        key state.. if NULL, the interpreter will run without
 *        trying to connect to the exchange first.
 *
 * @return GNUNET_OK if all is okay, != GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are GNUNET_SYSERR most of the
 *         times.
 */
int
TALER_TESTING_setup (TALER_TESTING_Main main_cb,
                     void *main_cb_cls,
                     const char *config_filename,
                     struct GNUNET_OS_Process *exchanged)
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
  /* zero-ing the state */
  memset (&is,
          0,
          sizeof (is));
  is.exchanged = exchanged;
  sigpipe = GNUNET_DISK_pipe (GNUNET_NO, GNUNET_NO,
                              GNUNET_NO, GNUNET_NO);
  GNUNET_assert (NULL != sigpipe);
  shc_chld = GNUNET_SIGNAL_handler_install
    (GNUNET_SIGCHLD, &sighandler_child_death);

  is.ctx = GNUNET_CURL_init
    (&GNUNET_CURL_gnunet_scheduler_reschedule, &is.rc);
  GNUNET_assert (NULL != is.ctx);
  is.rc = GNUNET_CURL_gnunet_rc_create (is.ctx);

  /* Blocking */

  if (NULL != exchanged)
    GNUNET_SCHEDULER_run (&main_wrapper_exchange_connect,
                          &main_ctx);
  else
     GNUNET_SCHEDULER_run (&main_wrapper_exchange_agnostic,
                           &main_ctx);

  GNUNET_SIGNAL_handler_uninstall (shc_chld);
  GNUNET_DISK_pipe_close (sigpipe);
  sigpipe = NULL;

  return is.result;
}

/* end of testing_api_loop.c */
