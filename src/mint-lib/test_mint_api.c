/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint/test_mint_api.c
 * @brief testcase to test mint's HTTP API interface
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_mint_service.h"

/**
 * Main execution context for the main loop.
 */
static struct TALER_MINT_Context *ctx;

/**
 * Handle to access the mint.
 */
static struct TALER_MINT_Handle *mint;

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
 * Function run when the test terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls NULL
 * @param tc unused
 */
static void
do_shutdown (void *cls,
             const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  shutdown_task = NULL;
  if (NULL != ctx_task)
  {
    GNUNET_SCHEDULER_cancel (ctx_task);
    ctx_task = NULL;
  }
  if (NULL != mint)
  {
    TALER_MINT_disconnect (mint);
    mint = NULL;
  }
  if (NULL != ctx)
  {
    TALER_MINT_fini (ctx);
    ctx = NULL;
  }
}


/**
 * Functions of this type are called to provide the retrieved signing and
 * denomination keys of the mint.  No TALER_MINT_*() functions should be called
 * in this callback.
 *
 * @param cls closure
 * @param keys information about keys of the mint
 */
static void
cert_cb (void *cls,
         const struct TALER_MINT_Keys *keys)
{
  GNUNET_assert (NULL == cls);
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
  /* TODO: start running rest of test suite here! */
  result = GNUNET_OK;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Task that runs the context's event loop with the GNUnet scheduler.
 *
 * @param cls unused
 * @param tc scheduler context (unused)
 */
static void
context_task (void *cls,
              const struct GNUNET_SCHEDULER_TaskContext *tc)
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
  TALER_MINT_perform (ctx);
  max_fd = -1;
  timeout = -1;
  FD_ZERO (&read_fd_set);
  FD_ZERO (&write_fd_set);
  FD_ZERO (&except_fd_set);
  TALER_MINT_get_select_info (ctx,
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
                                    max_fd);
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
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param config configuration
 */
static void
run (void *cls,
     const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  ctx = TALER_MINT_init ();
  GNUNET_assert (NULL != ctx);
  ctx_task = GNUNET_SCHEDULER_add_now (&context_task,
                                       ctx);
  mint = TALER_MINT_connect (ctx,
                             "http://localhost:8081",
                             &cert_cb, NULL,
                             TALER_MINT_OPTION_END);
  GNUNET_assert (NULL != mint);
  shutdown_task =
      GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_relative_multiply
                                    (GNUNET_TIME_UNIT_SECONDS, 5),
                                    &do_shutdown, NULL);
}


/**
 * Main function for the testcase for the mint API.
 *
 * @param argc expected to be 1
 * @param argv expected to only contain the program name
 */
int
main (int argc,
      char * const *argv)
{
  struct GNUNET_OS_Process *mintd;

  GNUNET_log_setup ("test-mint-api",
                    "WARNING",
                    NULL);
  mintd = GNUNET_OS_start_process (GNUNET_NO,
                                   GNUNET_OS_INHERIT_STD_ALL,
                                   NULL, NULL, NULL,
                                   "taler-mint-httpd",
                                   "taler-mint-httpd",
                                   "-d", "test-mint-home",
                                   NULL);
  sleep (1);
  result = GNUNET_SYSERR;
  GNUNET_SCHEDULER_run (&run, NULL);
  sleep (60);
  GNUNET_OS_process_kill (mintd,
                          SIGTERM);
  GNUNET_OS_process_wait (mintd);
  GNUNET_OS_process_destroy (mintd);
  return (GNUNET_OK == result) ? 0 : 1;
}

/* end of test_mint_api.c */
