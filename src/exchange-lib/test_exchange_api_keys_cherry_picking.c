/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V. and Inria

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
 * @file exchange/test_exchange_api_keys_cherry_picking.c
 * @brief testcase to test exchange's /keys cherry picking ability
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>


/**
 * Main execution context for the main loop.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Handle to access the exchange.
 */
static struct TALER_EXCHANGE_Handle *exchange;

/**
 * Context for running the CURL event loop.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Handle to the exchange process.
 */
static struct GNUNET_OS_Process *exchanged;

/**
 * Task run on timeout.
 */
static struct GNUNET_SCHEDULER_Task *timeout_task;

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
   * Run a process.
   */
  OC_RUN_PROCESS,

  /**
   * Signal the exchange to reload the keys.
   */
  OC_SIGNAL_EXCHANGE,

  /**
   * Check the /keys.
   */
  OC_CHECK_KEYS

};


/**
 * Details for a exchange operation to execute.
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
   * Details about the command.
   */
  union
  {

    struct {

      /**
       * Binary to execute.
       */
      const char *binary;

      /**
       * Command-line arguments for the process to be run.
       */
      char *const *argv;

      /**
       * Process handle.
       */
      struct GNUNET_OS_Process *proc;

      /**
       * ID of task called whenever we get a SIGCHILD.
       */
      struct GNUNET_SCHEDULER_Task *child_death_task;

    } run_process;

    struct {

      /**
       * Expected number of denomination keys.
       */
      unsigned int num_denom_keys;

      /**
       * Which generation of /keys are we verifying here?
       * Used to make sure we got the right number of
       * interactions.
       */
      unsigned int generation;

    } check_keys;

  } details;

};


/**
 * State of the interpreter loop.
 */
struct InterpreterState
{
  /**
   * Keys from the exchange.
   */
  const struct TALER_EXCHANGE_Keys *keys;

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

  /**
   * Is the interpreter running (#GNUNET_YES) or waiting
   * for /keys (#GNUNET_NO)?
   */
  int working;

  /**
   * How often have we gotten a /keys response so far?
   */
  unsigned int key_generation;

};


/**
 * Pipe used to communicate child death via signal.
 */
static struct GNUNET_DISK_PipeHandle *sigpipe;


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


/**
 * Run the main interpreter loop that performs exchange operations.
 *
 * @param cls contains the `struct InterpreterState`
 */
static void
interpreter_run (void *cls);


/**
 * Run the next command with the interpreter.
 *
 * @param is current interpeter state.
 */
static void
next_command (struct InterpreterState *is)
{
  if (GNUNET_SYSERR == result)
    return; /* ignore, we already failed! */
  is->ip++;
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
}


/**
 * Task triggered whenever we receive a SIGCHLD (child
 * process died).
 *
 * @param cls closure, NULL if we need to self-restart
 */
static void
maint_child_death (void *cls)
{
  struct InterpreterState *is = cls;
  struct Command *cmd = &is->commands[is->ip];
  const struct GNUNET_DISK_FileHandle *pr;
  char c[16];

  switch (cmd->oc) {
  case OC_RUN_PROCESS:
    cmd->details.run_process.child_death_task = NULL;
    pr = GNUNET_DISK_pipe_handle (sigpipe, GNUNET_DISK_PIPE_END_READ);
    GNUNET_break (0 < GNUNET_DISK_file_read (pr, &c, sizeof (c)));
    GNUNET_OS_process_wait (cmd->details.run_process.proc);
    GNUNET_OS_process_destroy (cmd->details.run_process.proc);
    cmd->details.run_process.proc = NULL;
    break;
  default:
    GNUNET_break (0);
    fail (is);
    return;
  }
  next_command (is);
}


/**
 * Run the main interpreter loop that performs exchange operations.
 *
 * @param cls contains the `struct InterpreterState`
 */
static void
interpreter_run (void *cls)
{
  struct InterpreterState *is = cls;
  struct Command *cmd = &is->commands[is->ip];
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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Running command `%s'\n",
              cmd->label);
  switch (cmd->oc)
  {
  case OC_END:
    result = GNUNET_OK;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case OC_RUN_PROCESS:
    {
      const struct GNUNET_DISK_FileHandle *pr;

      cmd->details.run_process.proc
        = GNUNET_OS_start_process_vap (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       cmd->details.run_process.binary,
                                       cmd->details.run_process.argv);
      if (NULL == cmd->details.run_process.proc)
      {
        GNUNET_break (0);
        fail (is);
        return;
      }
      pr = GNUNET_DISK_pipe_handle (sigpipe,
                                    GNUNET_DISK_PIPE_END_READ);
      cmd->details.run_process.child_death_task
        = GNUNET_SCHEDULER_add_read_file (GNUNET_TIME_UNIT_FOREVER_REL,
                                          pr,
                                          &maint_child_death,
                                          is);
      return;
    }
  case OC_SIGNAL_EXCHANGE:
    {
      GNUNET_break (0 ==
                    GNUNET_OS_process_kill (exchanged,
                                            SIGUSR1));
      /* give exchange time to process the signal */
      sleep (1);
      next_command (is);
      return;
    }
  case OC_CHECK_KEYS:
    {
      if (is->key_generation < cmd->details.check_keys.generation)
      {
        /* Go back to waiting for /keys signal! */
        is->working = GNUNET_NO;
        GNUNET_break (0 ==
                      TALER_EXCHANGE_check_keys_current (exchange,
                                                         GNUNET_YES).abs_value_us);
        return;
      }
      if (is->key_generation > cmd->details.check_keys.generation)
      {
        /* We got /keys too often, strange. Fatal. May theoretically happen if
           somehow we were really unlucky and /keys expired "naturally", but
           obviously with a sane configuration this should also not be. */
        GNUNET_break (0);
        fail (is);
        return;
      }
      /* /keys was updated, let's check they were OK! */
      if (cmd->details.check_keys.num_denom_keys !=
          is->keys->num_denom_keys)
      {
        /* Did not get the expected number of denomination keys! */
        GNUNET_break (0);
        fprintf (stderr,
                 "Got %u keys in step %s\n",
                 is->keys->num_denom_keys,
                 cmd->label);
        fail (is);
        return;
      }
      next_command (is);
      return;
    }
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


/**
 * Function run when the test terminates (good or bad) with timeout.
 *
 * @param cls NULL
 */
static void
do_timeout (void *cls)
{
  timeout_task = NULL;
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
  struct Command *cmd;

  for (unsigned int i=0;OC_END != (cmd = &is->commands[i])->oc;i++)
  {
    switch (cmd->oc)
    {
    case OC_END:
      GNUNET_assert (0);
      break;
    case OC_RUN_PROCESS:
      if (NULL != cmd->details.run_process.proc)
      {
        GNUNET_break (0 ==
                      GNUNET_OS_process_kill (cmd->details.run_process.proc,
                                              SIGKILL));
        GNUNET_OS_process_wait (cmd->details.run_process.proc);
        GNUNET_OS_process_destroy (cmd->details.run_process.proc);
        cmd->details.run_process.proc = NULL;
      }
      if (NULL != cmd->details.run_process.child_death_task)
      {
        GNUNET_SCHEDULER_cancel (cmd->details.run_process.child_death_task);
        cmd->details.run_process.child_death_task = NULL;
      }
      break;
    case OC_SIGNAL_EXCHANGE:
      /* nothing to do */
      break;
    case OC_CHECK_KEYS:
      /* nothing to do */
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
  if (NULL != exchange)
  {
    TALER_EXCHANGE_disconnect (exchange);
    exchange = NULL;
  }
  if (NULL != ctx)
  {
    GNUNET_CURL_fini (ctx);
    ctx = NULL;
  }
  if (NULL != rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (rc);
    rc = NULL;
  }
  if (NULL != timeout_task)
  {
    GNUNET_SCHEDULER_cancel (timeout_task);
    timeout_task = NULL;
  }
}


/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the exchange.  No TALER_EXCHANGE_*() functions should be called
 * in this callback.
 *
 * @param cls closure
 * @param keys information about keys of the exchange
 * @param vc version compatibility
 */
static void
cert_cb (void *cls,
         const struct TALER_EXCHANGE_Keys *keys,
	 enum TALER_EXCHANGE_VersionCompatibility vc)
{
  struct InterpreterState *is = cls;

  /* check that keys is OK */
#define ERR(cond) do { if(!(cond)) break; GNUNET_break (0); GNUNET_SCHEDULER_shutdown(); return; } while (0)
  ERR (NULL == keys);
  ERR (0 == keys->num_sign_keys);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u signing keys\n",
              keys->num_sign_keys);
  ERR (0 == keys->num_denom_keys);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Read %u denomination keys\n",
              keys->num_denom_keys);
#undef ERR

  /* run actual tests via interpreter-loop */
  is->keys = keys;
  if (GNUNET_YES == is->working)
    return;
  is->working = GNUNET_YES;
  is->key_generation++;
  is->task = GNUNET_SCHEDULER_add_now (&interpreter_run,
                                       is);
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
  static char *keyup[] = {
    "taler-exchange-keyup",
    "-c", "test_exchange_api_keys_cherry_picking_extended.conf",
    "-o", "auditor.in",
    NULL
  };
  static char *auditorsign[] = {
    "taler-auditor-sign",
    "-c", "test_exchange_api_keys_cherry_picking.conf",
    "-u", "http://auditor/",
    "-m", "98NJW3CQHZQGQXTY3K85K531XKPAPAVV4Q5V8PYYRR00NJGZWNVG",
    "-r", "auditor.in",
    "-o", "test_exchange_api_home/.local/share/taler/auditors/auditor.out",
    NULL
  };
  static struct Command commands[] =
  {
    /* Test signal handling by itself */
    { .oc = OC_SIGNAL_EXCHANGE },
    /* Check we got /keys properly */
    { .oc = OC_CHECK_KEYS,
      .details.check_keys.generation = 1,
      .details.check_keys.num_denom_keys = 4
    },
    /* Generate more keys */
    { .oc = OC_RUN_PROCESS,
      .details.run_process.binary = "taler-exchange-keyup",
      .details.run_process.argv = keyup
    },
    /* Auditor-sign them */
    { .oc = OC_RUN_PROCESS,
      .details.run_process.binary = "taler-auditor-sign",
      .details.run_process.argv = auditorsign
    },
    /* Load new keys into exchange via signal */
    { .oc = OC_SIGNAL_EXCHANGE },
    /* Re-download and check /keys */
    { .oc = OC_CHECK_KEYS,
      .details.check_keys.generation = 2,
      .details.check_keys.num_denom_keys = 8
    },
    { .oc = OC_END }
  };

  is = GNUNET_new (struct InterpreterState);
  is->commands = commands;

  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  GNUNET_assert (NULL != ctx);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  exchange = TALER_EXCHANGE_connect (ctx,
                                     "http://localhost:8081",
                                     &cert_cb, is,
                                     TALER_EXCHANGE_OPTION_END);
  GNUNET_assert (NULL != exchange);
  timeout_task
    = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_relative_multiply
                                    (GNUNET_TIME_UNIT_SECONDS, 300),
                                    &do_timeout, NULL);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 is);
}


/**
 * Remove files from previous runs
 */
static void
cleanup_files ()
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  char *dir;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 "test_exchange_api.conf"))
  {
    GNUNET_break (0);
    GNUNET_CONFIGURATION_destroy (cfg);
    exit (77);
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                          "exchange",
                                                          "keydir",
                                                          &dir));
  if (GNUNET_YES ==
      GNUNET_DISK_directory_test (dir,
                                  GNUNET_NO))
    GNUNET_break (GNUNET_OK ==
                  GNUNET_DISK_directory_remove (dir));
  GNUNET_free (dir);
  GNUNET_CONFIGURATION_destroy (cfg);
}


/**
 * Main function for the testcase for the exchange API.
 *
 * @param argc expected to be 1
 * @param argv expected to only contain the program name
 */
int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *proc;
  struct GNUNET_SIGNAL_Context *shc_chld;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;
  unsigned int iter;

  /* These might get in the way... */
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-exchange-api-keys-cherry-picking",
                    "INFO",
                    NULL);
  if (GNUNET_OK !=
      GNUNET_NETWORK_test_port_free (IPPROTO_TCP,
				     8081))
  {
    fprintf (stderr,
             "Required port %u not available, skipping.\n",
	     8081);
    return 77;
  }
  cleanup_files ();

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-keyup",
                                  "taler-exchange-keyup",
                                  "-c", "test_exchange_api_keys_cherry_picking.conf",
                                  "-o", "auditor.in",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-keyup`, is your PATH correct?\n");
    return 77;
  }
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-auditor-sign",
                                  "taler-auditor-sign",
                                  "-c", "test_exchange_api_keys_cherry_picking.conf",
                                  "-u", "http://auditor/",
                                  "-m", "98NJW3CQHZQGQXTY3K85K531XKPAPAVV4Q5V8PYYRR00NJGZWNVG",
                                  "-r", "auditor.in",
                                  "-o", "test_exchange_api_home/.local/share/taler/auditors/auditor.out",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-keyup`, is your PATH correct?\n");
    return 77;
  }
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-dbinit",
                                  "taler-exchange-dbinit",
                                  "-c", "test_exchange_api_keys_cherry_picking.conf",
                                  "-r",
                                  NULL);
  if (NULL == proc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		"Failed to run `taler-exchange-dbinit`, is your PATH correct?\n");
    return 77;
  }
  if (GNUNET_SYSERR ==
      GNUNET_OS_process_wait_status (proc,
                                     &type,
                                     &code))
  {
    GNUNET_break (0);
    GNUNET_OS_process_destroy (proc);
    return 1;
  }
  GNUNET_OS_process_destroy (proc);
  if ( (type == GNUNET_OS_PROCESS_EXITED) &&
       (0 != code) )
  {
    fprintf (stderr,
             "Failed to setup database\n");
    return 77;
  }
  if ( (type != GNUNET_OS_PROCESS_EXITED) ||
       (0 != code) )
  {
    fprintf (stderr,
             "Unexpected error running `taler-exchange-dbinit'!\n");
    return 1;
  }
  exchanged = GNUNET_OS_start_process (GNUNET_NO,
                                       GNUNET_OS_INHERIT_STD_ALL,
                                       NULL, NULL, NULL,
                                       "taler-exchange-httpd",
                                       "taler-exchange-httpd",
                                       "-c", "test_exchange_api_keys_cherry_picking.conf",
                                       "-i",
                                       NULL);
  /* give child time to start and bind against the socket */
  fprintf (stderr,
           "Waiting for `taler-exchange-httpd' to be ready");
  iter = 0;
  do
    {
      if (10 == iter)
      {
	fprintf (stderr,
		 "Failed to launch `taler-exchange-httpd' (or `wget')\n");
	GNUNET_OS_process_kill (exchanged,
				SIGTERM);
	GNUNET_OS_process_wait (exchanged);
	GNUNET_OS_process_destroy (exchanged);
	return 77;
      }
      fprintf (stderr, ".");
      sleep (1);
      iter++;
    }
  while (0 != system ("wget -q -t 1 -T 1 http://127.0.0.1:8081/keys -o /dev/null -O /dev/null"));
  fprintf (stderr, "\n");
  result = GNUNET_NO;
  sigpipe = GNUNET_DISK_pipe (GNUNET_NO, GNUNET_NO, GNUNET_NO, GNUNET_NO);
  GNUNET_assert (NULL != sigpipe);
  shc_chld = GNUNET_SIGNAL_handler_install (GNUNET_SIGCHLD,
                                            &sighandler_child_death);
  GNUNET_SCHEDULER_run (&run, NULL);
  GNUNET_SIGNAL_handler_uninstall (shc_chld);
  shc_chld = NULL;
  GNUNET_DISK_pipe_close (sigpipe);
  GNUNET_break (0 ==
                GNUNET_OS_process_kill (exchanged,
                                        SIGTERM));
  GNUNET_break (GNUNET_OK ==
                GNUNET_OS_process_wait (exchanged));
  GNUNET_OS_process_destroy (exchanged);
  return (GNUNET_OK == result) ? 0 : 1;
}

/* end of test_exchange_api_keys_cherry_picking.c */
