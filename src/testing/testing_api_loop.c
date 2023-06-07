/*
  This file is part of TALER
  Copyright (C) 2018-2023 Taler Systems SA

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
#include "taler_extensions.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


struct TALER_TESTING_Interpreter
{

  /**
   * Commands the interpreter will run.
   */
  struct TALER_TESTING_Command *commands;

  /**
   * Interpreter task (if one is scheduled).
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Handle for the child management.
   */
  struct GNUNET_ChildWaitHandle *cwh;

  /**
   * Main execution context for the main loop.
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * Context for running the CURL event loop.
   */
  struct GNUNET_CURL_RescheduleContext *rc;

  /**
   * Hash map mapping variable names to commands.
   */
  struct GNUNET_CONTAINER_MultiHashMap *vars;

  /**
   * Task run on timeout.
   */
  struct GNUNET_SCHEDULER_Task *timeout_task;

  /**
   * Instruction pointer.  Tells #interpreter_run() which instruction to run
   * next.  Need (signed) int because it gets -1 when rewinding the
   * interpreter to the first CMD.
   */
  int ip;

  /**
   * Result of the testcases, #GNUNET_OK on success
   */
  enum GNUNET_GenericReturnValue result;

};


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
      struct TALER_TESTING_Command **batch;
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
           NULL != (icmd = &(*batch)[j])->label;
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


const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_get_command (struct TALER_TESTING_Interpreter *is,
                                       const char *name)
{
  const struct TALER_TESTING_Command *cmd;
  struct GNUNET_HashCode h_name;

  GNUNET_CRYPTO_hash (name,
                      strlen (name),
                      &h_name);
  cmd = GNUNET_CONTAINER_multihashmap_get (is->vars,
                                           &h_name);
  if (NULL == cmd)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Command not found by name: %s\n",
                name);
  return cmd;
}


struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context (struct TALER_TESTING_Interpreter *is)
{
  return is->ctx;
}


void
TALER_TESTING_touch_cmd (struct TALER_TESTING_Interpreter *is)
{
  is->commands[is->ip].last_req_time
    = GNUNET_TIME_absolute_get ();
}


void
TALER_TESTING_inc_tries (struct TALER_TESTING_Interpreter *is)
{
  is->commands[is->ip].num_tries++;
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
    if (TALER_TESTING_cmd_batch_next (is,
                                      cmd->cls))
    {
      cmd->finish_time = GNUNET_TIME_absolute_get ();
      is->ip++; /* batch is done */
    }
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


const char *
TALER_TESTING_interpreter_get_current_label (
  struct TALER_TESTING_Interpreter *is)
{
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  return cmd->label;
}


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
  if (NULL != cmd->name)
  {
    struct GNUNET_HashCode h_name;

    GNUNET_CRYPTO_hash (cmd->name,
                        strlen (cmd->name),
                        &h_name);
    (void) GNUNET_CONTAINER_multihashmap_put (
      is->vars,
      &h_name,
      cmd,
      GNUNET_CONTAINER_MULTIHASHMAPOPTION_REPLACE);
  }
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
    if (NULL != cmd->cleanup)
      cmd->cleanup (cmd->cls,
                    cmd);
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
  if (NULL != is->vars)
  {
    GNUNET_CONTAINER_multihashmap_destroy (is->vars);
    is->vars = NULL;
  }
  if (NULL != is->timeout_task)
  {
    GNUNET_SCHEDULER_cancel (is->timeout_task);
    is->timeout_task = NULL;
  }
  if (NULL != is->cwh)
  {
    GNUNET_wait_child_cancel (is->cwh);
    is->cwh = NULL;
  }
  GNUNET_free (is->commands);
}


/**
 * Function run when the test terminates (good or bad) with timeout.
 *
 * @param cls the `struct TALER_TESTING_Interpreter *`
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
 * @param cls the `struct TALER_TESTING_Interpreter *`
 * @param type type of the process
 * @param exit_code status code of the process
 */
static void
maint_child_death (void *cls,
                   enum GNUNET_OS_ProcessStatusType type,
                   long unsigned int code)
{
  struct TALER_TESTING_Interpreter *is = cls;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];
  struct GNUNET_OS_Process **processp;

  is->cwh = NULL;
  while (TALER_TESTING_cmd_is_batch (cmd))
    cmd = TALER_TESTING_cmd_batch_get_current (cmd);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got SIGCHLD for `%s'.\n",
              cmd->label);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_process (cmd,
                                       &processp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Got the dead child process handle, waiting for termination ...\n");
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
  struct GNUNET_OS_Process **processp;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  while (TALER_TESTING_cmd_is_batch (cmd))
    cmd = TALER_TESTING_cmd_batch_get_current (cmd);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_process (cmd,
                                       &processp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (NULL == is->cwh);
  is->cwh
    = GNUNET_wait_child (*processp,
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
  is->commands = GNUNET_malloc_large ( (i + 1)
                                       * sizeof (struct TALER_TESTING_Command));
  GNUNET_assert (NULL != is->commands);
  GNUNET_memcpy (is->commands,
                 commands,
                 sizeof (struct TALER_TESTING_Command) * i);
  is->timeout_task = GNUNET_SCHEDULER_add_delayed (
    timeout,
    &do_timeout,
    is);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 is);
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
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
 * Initialize scheduler loop and curl context for the testcase,
 * and responsible to run the "run" method.
 *
 * @param cls closure, typically the "run" method, the
 *        interpreter state and a closure for "run".
 */
static void
main_wrapper (void *cls)
{
  struct MainContext *main_ctx = cls;

  main_ctx->main_cb (main_ctx->main_cb_cls,
                     main_ctx->is);
}


enum GNUNET_GenericReturnValue
TALER_TESTING_loop (TALER_TESTING_Main main_cb,
                    void *main_cb_cls)
{
  struct TALER_TESTING_Interpreter is;
  struct MainContext main_ctx = {
    .main_cb = main_cb,
    .main_cb_cls = main_cb_cls,
    /* needed to init the curl ctx */
    .is = &is,
  };

  memset (&is,
          0,
          sizeof (is));
  is.ctx = GNUNET_CURL_init (
    &GNUNET_CURL_gnunet_scheduler_reschedule,
    &is.rc);
  GNUNET_CURL_enable_async_scope_header (is.ctx,
                                         "Taler-Correlation-Id");
  GNUNET_assert (NULL != is.ctx);
  is.rc = GNUNET_CURL_gnunet_rc_create (is.ctx);
  is.vars = GNUNET_CONTAINER_multihashmap_create (1024,
                                                  false);
  /* Blocking */
  GNUNET_SCHEDULER_run (&main_wrapper,
                        &main_ctx);
  return is.result;
}


int
TALER_TESTING_main (char *const *argv,
                    const char *loglevel,
                    const char *cfg_file,
                    const char *exchange_account_section,
                    enum TALER_TESTING_BankSystem bs,
                    struct TALER_TESTING_Credentials *cred,
                    TALER_TESTING_Main main_cb,
                    void *main_cb_cls)
{
  enum GNUNET_GenericReturnValue ret;

  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup (argv[0],
                    loglevel,
                    NULL);
  if (GNUNET_OK !=
      TALER_TESTING_get_credentials (cfg_file,
                                     exchange_account_section,
                                     bs,
                                     cred))
  {
    GNUNET_break (0);
    return 77;
  }
  if (GNUNET_OK !=
      TALER_TESTING_cleanup_files_cfg (NULL,
                                       cred->cfg))
  {
    GNUNET_break (0);
    return 77;
  }
  if (GNUNET_OK !=
      TALER_extensions_init (cred->cfg))
  {
    GNUNET_break (0);
    return 77;
  }
  ret = TALER_TESTING_loop (main_cb,
                            main_cb_cls);
  /* TODO: should we free 'cred' resources here? */
  return (GNUNET_OK == ret) ? 0 : 1;
}


/* ************** iterate over commands ********* */


void
TALER_TESTING_iterate (struct TALER_TESTING_Interpreter *is,
                       bool asc,
                       TALER_TESTING_CommandIterator cb,
                       void *cb_cls)
{
  unsigned int start;
  unsigned int end;
  int inc;

  if (asc)
  {
    inc = 1;
    start = 0;
    end = is->ip;
  }
  else
  {
    inc = -1;
    start = is->ip;
    end = 0;
  }
  for (unsigned int off = start; off != end + inc; off += inc)
  {
    const struct TALER_TESTING_Command *cmd = &is->commands[off];

    cb (cb_cls,
        cmd);
  }
}


/* ************** special commands ********* */


struct TALER_TESTING_Command
TALER_TESTING_cmd_end (void)
{
  static struct TALER_TESTING_Command cmd;
  cmd.label = NULL;

  return cmd;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_set_var (const char *name,
                           struct TALER_TESTING_Command cmd)
{
  cmd.name = name;
  return cmd;
}


/**
 * State for a "rewind" CMD.
 */
struct RewindIpState
{
  /**
   * Instruction pointer to set into the interpreter.
   */
  const char *target_label;

  /**
   * How many times this set should take place.  However, this value lives at
   * the calling process, and this CMD is only in charge of checking and
   * decremeting it.
   */
  unsigned int counter;
};


/**
 * Seek for the @a target command in @a batch (and rewind to it
 * if successful).
 *
 * @param is the interpreter state (for failures)
 * @param cmd batch to search for @a target
 * @param target command to search for
 * @return #GNUNET_OK on success, #GNUNET_NO if target was not found,
 *         #GNUNET_SYSERR if target is in the future and we failed
 */
static enum GNUNET_GenericReturnValue
seek_batch (struct TALER_TESTING_Interpreter *is,
            const struct TALER_TESTING_Command *cmd,
            const struct TALER_TESTING_Command *target)
{
  unsigned int new_ip;
  struct TALER_TESTING_Command **batch;
  struct TALER_TESTING_Command *current;
  struct TALER_TESTING_Command *icmd;
  struct TALER_TESTING_Command *match;

  current = TALER_TESTING_cmd_batch_get_current (cmd);
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_batch_cmds (cmd,
                                                     &batch));
  match = NULL;
  for (new_ip = 0;
       NULL != (icmd = &(*batch)[new_ip]);
       new_ip++)
  {
    if (current == target)
      current = NULL;
    if (icmd == target)
    {
      match = icmd;
      break;
    }
    if (TALER_TESTING_cmd_is_batch (icmd))
    {
      int ret = seek_batch (is,
                            icmd,
                            target);
      if (GNUNET_SYSERR == ret)
        return GNUNET_SYSERR; /* failure! */
      if (GNUNET_OK == ret)
      {
        match = icmd;
        break;
      }
    }
  }
  if (NULL == current)
  {
    /* refuse to jump forward */
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return GNUNET_SYSERR;
  }
  if (NULL == match)
    return GNUNET_NO; /* not found */
  TALER_TESTING_cmd_batch_set_current (cmd,
                                       new_ip);
  return GNUNET_OK;
}


/**
 * Run the "rewind" CMD.
 *
 * @param cls closure.
 * @param cmd command being executed now.
 * @param is the interpreter state.
 */
static void
rewind_ip_run (void *cls,
               const struct TALER_TESTING_Command *cmd,
               struct TALER_TESTING_Interpreter *is)
{
  struct RewindIpState *ris = cls;
  const struct TALER_TESTING_Command *target;
  unsigned int new_ip;

  (void) cmd;
  if (0 == ris->counter)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  target
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ris->target_label);
  if (NULL == target)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ris->counter--;
  for (new_ip = 0;
       NULL != is->commands[new_ip].label;
       new_ip++)
  {
    const struct TALER_TESTING_Command *cmd = &is->commands[new_ip];

    if (cmd == target)
      break;
    if (TALER_TESTING_cmd_is_batch (cmd))
    {
      int ret = seek_batch (is,
                            cmd,
                            target);
      if (GNUNET_SYSERR == ret)
        return;   /* failure! */
      if (GNUNET_OK == ret)
        break;
    }
  }
  if (new_ip > (unsigned int) is->ip)
  {
    /* refuse to jump forward */
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  is->ip = new_ip - 1; /* -1 because the next function will advance by one */
  TALER_TESTING_interpreter_next (is);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_rewind_ip (const char *label,
                             const char *target_label,
                             unsigned int counter)
{
  struct RewindIpState *ris;

  ris = GNUNET_new (struct RewindIpState);
  ris->target_label = target_label;
  ris->counter = counter;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ris,
      .label = label,
      .run = &rewind_ip_run
    };

    return cmd;
  }
}


/**
 * State for a "authchange" CMD.
 */
struct AuthchangeState
{

  /**
   * What is the new authorization token to send?
   */
  const char *auth_token;

  /**
   * Old context, clean up on termination.
   */
  struct GNUNET_CURL_Context *old_ctx;
};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
authchange_run (void *cls,
                const struct TALER_TESTING_Command *cmd,
                struct TALER_TESTING_Interpreter *is)
{
  struct AuthchangeState *ss = cls;

  (void) cmd;
  ss->old_ctx = is->ctx;
  if (NULL != is->rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (is->rc);
    is->rc = NULL;
  }
  is->ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                              &is->rc);
  GNUNET_CURL_enable_async_scope_header (is->ctx,
                                         "Taler-Correlation-Id");
  GNUNET_assert (NULL != is->ctx);
  is->rc = GNUNET_CURL_gnunet_rc_create (is->ctx);
  if (NULL != ss->auth_token)
  {
    char *authorization;

    GNUNET_asprintf (&authorization,
                     "%s: %s",
                     MHD_HTTP_HEADER_AUTHORIZATION,
                     ss->auth_token);
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CURL_append_header (is->ctx,
                                              authorization));
    GNUNET_free (authorization);
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Call GNUNET_CURL_fini(). Done as a separate task to
 * ensure that all of the command's cleanups have been
 * executed first.  See #7151.
 *
 * @param cls a `struct GNUNET_CURL_Context *` to clean up.
 */
static void
deferred_cleanup_cb (void *cls)
{
  struct GNUNET_CURL_Context *ctx = cls;

  GNUNET_CURL_fini (ctx);
}


/**
 * Cleanup the state from a "authchange" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
authchange_cleanup (void *cls,
                    const struct TALER_TESTING_Command *cmd)
{
  struct AuthchangeState *ss = cls;

  (void) cmd;
  if (NULL != ss->old_ctx)
  {
    (void) GNUNET_SCHEDULER_add_now (&deferred_cleanup_cb,
                                     ss->old_ctx);
    ss->old_ctx = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_set_authorization (const char *label,
                                     const char *auth_token)
{
  struct AuthchangeState *ss;

  ss = GNUNET_new (struct AuthchangeState);
  ss->auth_token = auth_token;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &authchange_run,
      .cleanup = &authchange_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_loop.c */
