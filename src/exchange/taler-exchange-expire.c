/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-exchange-expire.c
 * @brief Process that cleans up expired purses
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"


/**
 * Work shard we are processing.
 */
struct Shard
{

  /**
   * When did we start processing the shard?
   */
  struct GNUNET_TIME_Timestamp start_time;

  /**
   * Starting row of the shard.
   */
  struct GNUNET_TIME_Absolute shard_start;

  /**
   * Inclusive end row of the shard.
   */
  struct GNUNET_TIME_Absolute shard_end;

  /**
   * Number of starting points found in the shard.
   */
  uint64_t work_counter;

};


/**
 * The exchange's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our database plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *db_plugin;

/**
 * Next task to run, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * How big are the shards we are processing? Is an inclusive offset, so every
 * shard ranges from [X,X+shard_size) exclusive.  So a shard covers
 * shard_size slots.
 */
static struct GNUNET_TIME_Relative shard_size;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static int global_ret;

/**
 * #GNUNET_YES if we are in test mode and should exit when idle.
 */
static int test_mode;

/**
 * If this is a first-time run, we immediately
 * try to catch up with the present.
 */
static bool jump_mode;


/**
 * Select a shard to work on.
 *
 * @param cls NULL
 */
static void
run_shard (void *cls);


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Running shutdown\n");
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  cfg = NULL;
}


/**
 * Parse the configuration for expire.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_expire_config (void)
{
  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg,
                                                 false)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Perform a database commit. If it fails, print a warning.
 *
 * @return status of commit
 */
static enum GNUNET_DB_QueryStatus
commit_or_warn (void)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->commit (db_plugin->cls);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return qs;
  GNUNET_log ((GNUNET_DB_STATUS_SOFT_ERROR == qs)
              ? GNUNET_ERROR_TYPE_INFO
              : GNUNET_ERROR_TYPE_ERROR,
              "Failed to commit database transaction!\n");
  return qs;
}


/**
 * Release lock on shard @a s in the database.
 * On error, terminates this process.
 *
 * @param[in] s shard to free (and memory to release)
 */
static void
release_shard (struct Shard *s)
{
  enum GNUNET_DB_QueryStatus qs;
  unsigned long long wc = (unsigned long long) s->work_counter;

  qs = db_plugin->complete_shard (
    db_plugin->cls,
    "expire",
    s->shard_start.abs_value_us,
    s->shard_end.abs_value_us);
  GNUNET_free (s);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    GNUNET_break (0);
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    /* Strange, but let's just continue */
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Purse expiration shard completed with %llu purses\n",
                wc);
    /* normal case */
    break;
  }
  if ( (0 == wc) &&
       (test_mode) &&
       (! jump_mode) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "In test-mode without work. Terminating.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Release lock on shard @a s in the database due to an abort of the
 * operation.  On error, terminates this process.
 *
 * @param[in] s shard to free (and memory to release)
 */
static void
abort_shard (struct Shard *s)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = db_plugin->abort_shard (db_plugin->cls,
                               "expire",
                               s->shard_start.abs_value_us,
                               s->shard_end.abs_value_us);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to abort shard (%d)!\n",
                qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Main function that processes the work in one shard.
 *
 * @param[in] cls a `struct Shard` to process
 */
static void
run_expire (void *cls)
{
  struct Shard *s = cls;
  enum GNUNET_DB_QueryStatus qs;

  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for expired purses\n");
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    abort_shard (s);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        "expire-purse"))
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls);
    abort_shard (s);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  qs = db_plugin->expire_purse (db_plugin->cls,
                                s->shard_start,
                                s->shard_end);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls);
    abort_shard (s);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    db_plugin->rollback (db_plugin->cls);
    abort_shard (s);
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_shard,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    if (0 > commit_or_warn ())
    {
      db_plugin->rollback (db_plugin->cls);
      abort_shard (s);
    }
    else
    {
      release_shard (s);
    }
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_shard,
                                     NULL);
    return;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* commit, and go again immediately */
    s->work_counter++;
    (void) commit_or_warn ();
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&run_expire,
                                     s);
  }
}


/**
 * Select a shard to work on.
 *
 * @param cls NULL
 */
static void
run_shard (void *cls)
{
  struct Shard *s;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  task = NULL;
  if (GNUNET_SYSERR ==
      db_plugin->preflight (db_plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database connection!\n");
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  s = GNUNET_new (struct Shard);
  s->start_time = GNUNET_TIME_timestamp_get ();
  qs = db_plugin->begin_shard (db_plugin->cls,
                               "expire",
                               shard_size,
                               jump_mode
                               ? GNUNET_TIME_absolute_subtract (
                                 GNUNET_TIME_absolute_get (),
                                 shard_size).
                               abs_value_us
                               : shard_size.rel_value_us,
                               &s->shard_start.abs_value_us,
                               &s->shard_end.abs_value_us);
  jump_mode = false;
  if (0 >= qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      static struct GNUNET_TIME_Relative delay;

      GNUNET_free (s);
      delay = GNUNET_TIME_randomized_backoff (delay,
                                              GNUNET_TIME_UNIT_SECONDS);
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_delayed (delay,
                                           &run_shard,
                                           NULL);
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to begin shard (%d)!\n",
                qs);
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_TIME_absolute_is_future (s->shard_end))
  {
    abort_shard (s);
    if (test_mode)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "In test-mode without work. Terminating.\n");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_at (s->shard_end,
                                    &run_shard,
                                    NULL);
    return;
  }
  /* If this is a first-time run, we immediately
     try to catch up with the present */
  if (GNUNET_TIME_absolute_is_zero (s->shard_start))
    jump_mode = true;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting shard [%llu:%llu)!\n",
              (unsigned long long) s->shard_start.abs_value_us,
              (unsigned long long) s->shard_end.abs_value_us);
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_expire,
                                   s);
}


/**
 * First task.
 *
 * @param cls closure, NULL
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param c configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *c)
{
  (void) cls;
  (void) args;
  (void) cfgfile;

  cfg = c;
  if (GNUNET_OK != parse_expire_config ())
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange",
                                           "EXPIRE_SHARD_SIZE",
                                           &shard_size))
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_shard,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
}


/**
 * The main function of the taler-exchange-expire.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, non-zero on error, see #global_ret
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-expire",
    gettext_noop (
      "background process that expires purses"),
    options,
    &run, NULL);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-expire.c */
