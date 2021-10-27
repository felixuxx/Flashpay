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
 * @file testing/testing_api_loop.c
 * @brief main interpreter loop for testcases
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
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
TALER_TESTING_interpreter_lookup_command (struct TALER_TESTING_Interpreter *is,
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
      struct TALER_TESTING_Command *batch;
      struct TALER_TESTING_Command *current;
      struct TALER_TESTING_Command *icmd;
      const struct TALER_TESTING_Command *match;

      current = TALER_TESTING_cmd_batch_get_current (cmd);
      GNUNET_assert (GNUNET_OK ==
                     TALER_TESTING_get_trait_batch_cmds (cmd,
                                                         &batch));
      /* We must do the loop forward, but we can find the last match */
      match = NULL;
      for (unsigned int j = 0;
           NULL != (icmd = &batch[j])->label;
           j++)
      {
        if (current == icmd)
          break; /* do not go past current command */
        if ( (NULL != icmd->label) &&
             (0 == strcmp (icmd->label,
                           label)) )
          match = icmd;
      }
      if (NULL != match)
        return match;
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
TALER_TESTING_interpreter_get_fakebank (struct TALER_TESTING_Interpreter *is)
{
  return is->fakebank;
}


void
TALER_TESTING_run_with_fakebank (struct TALER_TESTING_Interpreter *is,
                                 struct TALER_TESTING_Command *commands,
                                 const char *bank_url)
{
  char *currency;

  if (GNUNET_OK !=
      TALER_config_get_currency (is->cfg,
                                 &currency))
  {
    is->result = GNUNET_SYSERR;
    return;
  }
  is->fakebank = TALER_TESTING_run_fakebank (bank_url,
                                             currency);
  GNUNET_free (currency);
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


void
TALER_TESTING_interpreter_next (struct TALER_TESTING_Interpreter *is)
{
  static unsigned long long ipc;
  static struct GNUNET_TIME_Absolute last_report;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  if (GNUNET_SYSERR == is->result)
    return; /* ignore, we already failed! */
  if (TALER_TESTING_cmd_is_batch (cmd))
  {
    TALER_TESTING_cmd_batch_next (is);
  }
  else
  {
    cmd->finish_time = GNUNET_TIME_absolute_get ();
    is->ip++;
  }
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


void
TALER_TESTING_interpreter_fail (struct TALER_TESTING_Interpreter *is)
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_end (void)
{
  static struct TALER_TESTING_Command cmd;
  cmd.label = NULL;

  return cmd;
}


const char *
TALER_TESTING_interpreter_get_current_label (struct
                                             TALER_TESTING_Interpreter *is)
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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running command `%s'\n",
              cmd->label);
  cmd->start_time
    = cmd->last_req_time
      = GNUNET_TIME_absolute_get ();
  cmd->num_tries = 1;
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
  GNUNET_free (is->commands);
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
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;

  while (TALER_TESTING_cmd_is_batch (cmd))
    cmd = TALER_TESTING_cmd_batch_get_current (cmd);
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
              "Got the dead child process handle, waiting for termination ...\n");
  GNUNET_OS_process_wait_status (*processp,
                                 &type,
                                 &code);
  GNUNET_OS_process_destroy (*processp);
  *processp = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "... definitively terminated\n");
  switch (type)
  {
  case GNUNET_OS_PROCESS_UNKNOWN:
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  case GNUNET_OS_PROCESS_RUNNING:
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  case GNUNET_OS_PROCESS_STOPPED:
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  case GNUNET_OS_PROCESS_EXITED:
    if (0 != code)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Process exited with unexpected status %u\n",
                  (unsigned int) code);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    break;
  case GNUNET_OS_PROCESS_SIGNALED:
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Dead child, go on with next command.\n");
  TALER_TESTING_interpreter_next (is);
}


void
TALER_TESTING_wait_for_sigchld (struct TALER_TESTING_Interpreter *is)
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
  for (i = 0; NULL != commands[i].label; i++)
    ;
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
   * URL of the exchange.
   */
  char *exchange_url;

};


/**
 * Signal handler called for SIGCHLD.  Triggers the
 * respective handler by writing to the trigger pipe.
 */
static void
sighandler_child_death (void)
{
  static char c;
  int old_errno = errno;  /* back-up errno */

  GNUNET_break (1 == GNUNET_DISK_file_write
                  (GNUNET_DISK_pipe_handle (sigpipe,
                                            GNUNET_DISK_PIPE_END_WRITE),
                  &c, sizeof (c)));
  errno = old_errno;    /* restore errno */
}


void
TALER_TESTING_cert_cb (void *cls,
                       const struct TALER_EXCHANGE_HttpResponse *hr,
                       const struct TALER_EXCHANGE_Keys *keys,
                       enum TALER_EXCHANGE_VersionCompatibility compat)
{
  struct MainContext *main_ctx = cls;
  struct TALER_TESTING_Interpreter *is = main_ctx->is;

  (void) compat;
  if (NULL == keys)
  {
    if (GNUNET_NO == is->working)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Got NULL response for /keys during startup (%u/%d), retrying!\n",
                  hr->http_status,
                  (int) hr->ec);
      TALER_EXCHANGE_disconnect (is->exchange);
      GNUNET_assert (NULL != (is->exchange
                                = TALER_EXCHANGE_connect (is->ctx,
                                                          main_ctx->exchange_url,
                                                          &TALER_TESTING_cert_cb,
                                                          main_ctx,
                                                          TALER_EXCHANGE_OPTION_END)));
      return;
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Got NULL response for /keys during execution (%u/%d)!\n",
                  hr->http_status,
                  (int) hr->ec);
    }
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
  /* Trigger the next command. */
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
  struct TALER_TESTING_Interpreter *is = main_ctx->is;
  char *exchange_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (is->cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return;
  }
  main_ctx->exchange_url = exchange_url;
  is->timeout_task = GNUNET_SCHEDULER_add_shutdown (&do_abort,
                                                    main_ctx);
  is->working = GNUNET_YES;
  GNUNET_break
    (NULL != (is->exchange =
                TALER_EXCHANGE_connect (is->ctx,
                                        exchange_url,
                                        &TALER_TESTING_cert_cb,
                                        main_ctx,
                                        TALER_EXCHANGE_OPTION_END)));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting main test loop\n");
  main_ctx->main_cb (main_ctx->main_cb_cls,
                     is);
}


/**
 * Load the exchange and auditor key material into @a is.
 *
 * @param[in,out] is state to initialize
 */
static int
load_keys (struct TALER_TESTING_Interpreter *is)
{
  char *fn;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (is->cfg,
                                               "exchange-offline",
                                               "MASTER_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange-offline",
                               "MASTER_PRIV_FILE");
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      GNUNET_DISK_directory_create_for_file (fn))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not setup directory for master private key file `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                         GNUNET_YES,
                                         &is->master_priv.eddsa_priv))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not load master private key from `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  GNUNET_free (fn);
  GNUNET_CRYPTO_eddsa_key_get_public (&is->master_priv.eddsa_priv,
                                      &is->master_pub.eddsa_pub);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (is->cfg,
                                               "auditor",
                                               "AUDITOR_PRIV_FILE",
                                               &fn))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "AUDITOR_PRIV_FILE");
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      GNUNET_DISK_directory_create_for_file (fn))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not setup directory for auditor private key file `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                         GNUNET_YES,
                                         &is->auditor_priv.eddsa_priv))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not load auditor private key from `%s'\n",
                fn);
    GNUNET_free (fn);
    return GNUNET_SYSERR;
  }
  GNUNET_free (fn);
  GNUNET_CRYPTO_eddsa_key_get_public (&is->auditor_priv.eddsa_priv,
                                      &is->auditor_pub.eddsa_pub);
  return GNUNET_OK;
}


/**
 * Load the exchange and auditor URLs from the configuration into @a is.
 *
 * @param[in,out] is state to initialize
 */
static int
load_urls (struct TALER_TESTING_Interpreter *is)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (is->cfg,
                                             "auditor",
                                             "BASE_URL",
                                             &is->auditor_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "auditor",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (is->cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &is->exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    GNUNET_free (is->auditor_url);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


int
TALER_TESTING_setup (TALER_TESTING_Main main_cb,
                     void *main_cb_cls,
                     const struct GNUNET_CONFIGURATION_Handle *cfg,
                     struct GNUNET_OS_Process *exchanged,
                     int exchange_connect)
{
  struct TALER_TESTING_Interpreter is;
  struct MainContext main_ctx = {
    .main_cb = main_cb,
    .main_cb_cls = main_cb_cls,
    /* needed to init the curl ctx */
    .is = &is,
  };
  struct GNUNET_SIGNAL_Context *shc_chld;

  memset (&is,
          0,
          sizeof (is));
  is.exchanged = exchanged;
  is.cfg = cfg;
  if (GNUNET_OK !=
      load_keys (&is))
    return GNUNET_SYSERR;
  if (GNUNET_OK !=
      load_urls (&is))
    return GNUNET_SYSERR;
  sigpipe = GNUNET_DISK_pipe (GNUNET_DISK_PF_NONE);
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
  GNUNET_free (main_ctx.exchange_url);
  GNUNET_SIGNAL_handler_uninstall (shc_chld);
  GNUNET_DISK_pipe_close (sigpipe);
  sigpipe = NULL;
  GNUNET_free (is.auditor_url);
  GNUNET_free (is.exchange_url);
  return is.result;
}


/* end of testing_api_loop.c */
