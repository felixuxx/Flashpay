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
 * @file taler-exchange-router.c
 * @brief Process that routes P2P payments. Responsible for
 *   (1) refunding coins in unmerged purses, (2) merging purses into local reserves;
 *   (3) aggregating remote payments into the respective wad transfers.
 *   Execution of actual wad transfers is still to be done by taler-exchange-transfer,
 *   and watching for incoming wad transfers is done by taler-exchange-wirewatch.
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
  uint32_t shard_start;

  /**
   * Inclusive end row of the shard.
   */
  uint32_t shard_end;

  /**
   * Number of starting points found in the shard.
   */
  uint64_t work_counter;

};


/**
 * What is the smallest unit we support for wire transfers?
 * We will need to round down to a multiple of this amount.
 */
static struct TALER_Amount currency_round_unit;

/**
 * What is the base URL of this exchange?  Used in the
 * wire transfer subjects so that merchants and governments
 * can ask for the list of aggregated deposits.
 */
static char *exchange_base_url;

/**
 * Set to #GNUNET_YES if this exchange does not support KYC checks
 * and thus P2P transfers are to be made regardless of the
 * KYC status of the target reserve.
 */
static int kyc_off;

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
 * How long should we sleep when idle before trying to find more work?
 */
static struct GNUNET_TIME_Relative router_idle_sleep_interval;

/**
 * How big are the shards we are processing? Is an inclusive offset, so every
 * shard ranges from [X,X+shard_size) exclusive.  So a shard covers
 * shard_size slots.  The maximum value for shard_size is INT32_MAX+1.
 */
static uint32_t shard_size;

/**
 * Value to return from main(). 0 on success, non-zero on errors.
 */
static int global_ret;

/**
 * #GNUNET_YES if we are in test mode and should exit when idle.
 */
static int test_mode;


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
  TALER_EXCHANGEDB_unload_accounts ();
  cfg = NULL;
}


/**
 * Parse the configuration for wirewatch.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_wirewatch_config (void)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_base_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchange",
                                           "ROUTER_IDLE_SLEEP_INTERVAL",
                                           &router_idle_sleep_interval))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "ROUTER_IDLE_SLEEP_INTERVAL");
    return GNUNET_SYSERR;
  }
  if ( (GNUNET_OK !=
        TALER_config_get_amount (cfg,
                                 "taler",
                                 "CURRENCY_ROUND_UNIT",
                                 &currency_round_unit)) ||
       ( (0 != currency_round_unit.fraction) &&
         (0 != currency_round_unit.value) ) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need non-zero value in section `TALER' under `CURRENCY_ROUND_UNIT'\n");
    return GNUNET_SYSERR;
  }

  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (cfg,
                                      TALER_EXCHANGEDB_ALO_DEBIT))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No wire accounts configured for debit!\n");
    TALER_EXCHANGEDB_plugin_unload (db_plugin);
    db_plugin = NULL;
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

  qs = db_plugin->release_revolving_shard (
    db_plugin->cls,
    "router",
    s->shard_start,
    s->shard_end);
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
    /* normal case */
    break;
  }
}


static void
run_routing (void *cls)
{
  struct Shard *s = cls;

  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking for ready P2P transfers to route\n");
  // FIXME: do actual work here!
  commit_or_warn ();
  release_shard (s);
  task = GNUNET_SCHEDULER_add_now (&run_shard,
                                   NULL);
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
  qs = db_plugin->begin_revolving_shard (db_plugin->cls,
                                         "router",
                                         shard_size,
                                         1U + INT32_MAX,
                                         &s->shard_start,
                                         &s->shard_end);
  if (0 >= qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      static struct GNUNET_TIME_Relative delay;

      GNUNET_free (s);
      delay = GNUNET_TIME_randomized_backoff (delay,
                                              GNUNET_TIME_UNIT_SECONDS);
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting shard [%u:%u]!\n",
              (unsigned int) s->shard_start,
              (unsigned int) s->shard_end);
  task = GNUNET_SCHEDULER_add_now (&run_routing,
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
  unsigned long long ass;
  (void) cls;
  (void) args;
  (void) cfgfile;

  cfg = c;
  if (GNUNET_OK != parse_wirewatch_config ())
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "exchange",
                                             "ROUTER_SHARD_SIZE",
                                             &ass))
  {
    cfg = NULL;
    global_ret = EXIT_NOTCONFIGURED;
    return;
  }
  if ( (0 == ass) ||
       (ass > INT32_MAX) )
    shard_size = 1U + INT32_MAX;
  else
    shard_size = (uint32_t) ass;
  GNUNET_assert (NULL == task);
  task = GNUNET_SCHEDULER_add_now (&run_shard,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
}


/**
 * The main function of the taler-exchange-router.
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
    GNUNET_GETOPT_option_flag ('y',
                               "kyc-off",
                               "perform wire transfers without KYC checks",
                               &kyc_off),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-exchange-router",
    gettext_noop (
      "background process that routes P2P transfers"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-exchange-router.c */
