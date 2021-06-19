/*
  This file is part of TALER
  (C) 2014-2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU Affero General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file benchmark/taler-bank-benchmark.c
 * @brief code to benchmark only the 'bank' and the 'taler-exchange-wirewatch' tool
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
// TODO:
// - use more than one 'client' bank account
// - also add taler-exchange-transfer to simulate outgoing payments
// - improve reporting logic (currently not working)
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include <sys/resource.h>
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"
#include "taler_error_codes.h"


/* Error codes.  */
enum BenchmarkError
{
  MISSING_BANK_URL,
  FAILED_TO_LAUNCH_BANK,
  BAD_CLI_ARG,
  BAD_CONFIG_FILE,
  NO_CONFIG_FILE_GIVEN
};


/**
 * What mode should the benchmark run in?
 */
enum BenchmarkMode
{
  /**
   * Run as client against the bank.
   */
  MODE_CLIENT = 1,

  /**
   * Run the bank.
   */
  MODE_BANK = 2,

  /**
   * Run both, for a local benchmark.
   */
  MODE_BOTH = 3,
};


/**
 * Hold information regarding which bank has the exchange account.
 */
static struct TALER_BANK_AuthenticationData exchange_bank_account;

/**
 * Time snapshot taken right before executing the CMDs.
 */
static struct GNUNET_TIME_Absolute start_time;

/**
 * Benchmark duration time taken right after the CMD interpreter
 * returns.
 */
static struct GNUNET_TIME_Relative duration;

/**
 * Array of all the commands the benchmark is running.
 */
static struct TALER_TESTING_Command *all_commands;

/**
 * Dummy keepalive task.
 */
static struct GNUNET_SCHEDULER_Task *keepalive;

/**
 * Name of our configuration file.
 */
static char *cfg_filename;

/**
 * Use the fakebank instead of LibEuFin.
 * NOTE: LibEuFin not yet supported! Set
 * to 0 once we do support it!
 */
static int use_fakebank = 1;

/**
 * Launch taler-exchange-wirewatch.
 */
static int start_wirewatch;

/**
 * Verbosity level.
 */
static unsigned int verbose;

/**
 * Size of the transaction history the fakebank
 * should keep in RAM.
 */
static unsigned long long history_size = 65536;

/**
 * How many reserves we want to create per client.
 */
static unsigned int howmany_reserves = 1;

/**
 * How many clients we want to create.
 */
static unsigned int howmany_clients = 1;

/**
 * How many bank worker threads do we want to create.
 */
static unsigned int howmany_threads;

/**
 * Log level used during the run.
 */
static char *loglev;

/**
 * Log file.
 */
static char *logfile;

/**
 * Benchmarking mode (run as client, exchange, both) as string.
 */
static char *mode_str;

/**
 * Benchmarking mode (run as client, bank, both).
 */
static enum BenchmarkMode mode;

/**
 * Don't kill exchange/fakebank/wirewatch until
 * requested by the user explicitly.
 */
static int linger;

/**
 * Configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Currency used.
 */
static char *currency;

/**
 * Array of command labels.
 */
static char **labels;

/**
 * Length of #labels.
 */
static unsigned int label_len;

/**
 * Offset in #labels.
 */
static unsigned int label_off;

/**
 * Performance counters.
 */
static struct TALER_TESTING_Timer timings[] = {
  { .prefix = "createreserve" },
  { .prefix = NULL }
};


/**
 * Add label to the #labels table and return it.
 *
 * @param label string to add to the table
 * @return same string, now stored in the table
 */
const char *
add_label (char *label)
{
  if (label_off == label_len)
    GNUNET_array_grow (labels,
                       label_len,
                       label_len * 2 + 4);
  labels[label_off++] = label;
  return label;
}


/**
 * Print performance statistics for this process.
 */
static void
print_stats (void)
{
  for (unsigned int i = 0; NULL != timings[i].prefix; i++)
  {
    char *total;
    char *latency;

    total = GNUNET_strdup (
      GNUNET_STRINGS_relative_time_to_string (timings[i].total_duration,
                                              GNUNET_YES));
    latency = GNUNET_strdup (
      GNUNET_STRINGS_relative_time_to_string (timings[i].success_latency,
                                              GNUNET_YES));
    fprintf (stderr,
             "%s-%d took %s in total with %s for latency for %u executions (%u repeats)\n",
             timings[i].prefix,
             (int) getpid (),
             total,
             latency,
             timings[i].num_commands,
             timings[i].num_retries);
    GNUNET_free (total);
    GNUNET_free (latency);
  }
}


/**
 * Decide which exchange account is going to be used to address a wire
 * transfer to.  Used at withdrawal time.
 *
 * @param cls closure
 * @param section section name.
 */
static void
pick_exchange_account_cb (void *cls,
                          const char *section)
{
  const char **s = cls;

  if (0 == strncasecmp ("exchange-account-",
                        section,
                        strlen ("exchange-account-")))
    *s = section;
}


/**
 * Actual commands construction and execution.
 *
 * @param cls unused
 * @param is interpreter to run commands with
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  char *total_reserve_amount;
  size_t len;

  (void) cls;
  len = howmany_reserves + 2;
  all_commands = GNUNET_new_array (len,
                                   struct TALER_TESTING_Command);
  GNUNET_asprintf (&total_reserve_amount,
                   "%s:5",
                   currency);
  for (unsigned int j = 0; j < howmany_reserves; j++)
  {
    char *create_reserve_label;
    char *user_payto_uri;

    // FIXME: vary user accounts more...
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONFIGURATION_get_value_string (cfg,
                                                          "benchmark",
                                                          "USER_PAYTO_URI",
                                                          &user_payto_uri));
    GNUNET_asprintf (&create_reserve_label,
                     "createreserve-%u",
                     j);
    all_commands[j]
      = TALER_TESTING_cmd_admin_add_incoming_retry (
          TALER_TESTING_cmd_admin_add_incoming (add_label (
                                                  create_reserve_label),
                                                total_reserve_amount,
                                                &exchange_bank_account,
                                                add_label (user_payto_uri)));
  }
  GNUNET_free (total_reserve_amount);
  all_commands[howmany_reserves]
    = TALER_TESTING_cmd_stat (timings);
  all_commands[howmany_reserves + 1]
    = TALER_TESTING_cmd_end ();
  TALER_TESTING_run2 (is,
                      all_commands,
                      GNUNET_TIME_UNIT_FOREVER_REL); /* no timeout */
}


/**
 * Starts #howmany_clients workers to run the client logic from #run().
 */
static enum GNUNET_GenericReturnValue
launch_clients (void)
{
  enum GNUNET_GenericReturnValue result = GNUNET_OK;
  pid_t cpids[howmany_clients];

  start_time = GNUNET_TIME_absolute_get ();
  if (1 == howmany_clients)
  {
    /* do everything in this process */
    result = TALER_TESTING_setup (&run,
                                  NULL,
                                  cfg,
                                  NULL,
                                  GNUNET_NO);
    if (verbose)
      print_stats ();
    return result;
  }
  /* start work processes */
  for (unsigned int i = 0; i<howmany_clients; i++)
  {
    if (0 == (cpids[i] = fork ()))
    {
      /* I am the child, do the work! */
      GNUNET_log_setup ("benchmark-worker",
                        NULL == loglev ? "INFO" : loglev,
                        logfile);
      result = TALER_TESTING_setup (&run,
                                    NULL,
                                    cfg,
                                    NULL,
                                    GNUNET_NO);
      if (verbose)
        print_stats ();
      if (GNUNET_OK != result)
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failure in child process test suite!\n");
      if (GNUNET_OK == result)
        exit (0);
      else
        exit (1);
    }
    if (-1 == cpids[i])
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "fork");
      howmany_clients = i;
      result = GNUNET_SYSERR;
      break;
    }
    /* fork() success, continue starting more processes! */
  }
  /* collect all children */
  for (unsigned int i = 0; i<howmany_clients; i++)
  {
    int wstatus;

again:
    if (cpids[i] !=
        waitpid (cpids[i],
                 &wstatus,
                 0))
    {
      if (EINTR == errno)
        goto again;
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "waitpid");
      return GNUNET_SYSERR;
    }
    if ( (! WIFEXITED (wstatus)) ||
         (0 != WEXITSTATUS (wstatus)) )
    {
      GNUNET_break (0);
      result = GNUNET_SYSERR;
    }
  }
  return result;
}


/**
 * Stop the fakebank.
 *
 * @param cls fakebank handle
 */
static void
stop_fakebank (void *cls)
{
  struct TALER_FAKEBANK_Handle *fakebank = cls;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Stopping fakebank\n");
  TALER_FAKEBANK_stop (fakebank);
  GNUNET_SCHEDULER_cancel (keepalive);
  keepalive = NULL;
}


/**
 * Dummy task that is never run.
 */
static void
never_task (void *cls)
{
  GNUNET_assert (0);
}


/**
 * Start the fakebank.
 *
 * @param cls NULL
 */
static void
launch_fakebank (void *cls)
{
  struct TALER_FAKEBANK_Handle *fakebank;
  unsigned long long pnum;

  (void) cls;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "bank",
                                             "HTTP_PORT",
                                             &pnum))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "bank",
                               "HTTP_PORT",
                               "must be valid port number");
    return;
  }
  fakebank
    = TALER_FAKEBANK_start2 ((uint16_t) pnum,
                             currency,
                             history_size,
                             howmany_threads,
                             false);
  if (NULL == fakebank)
  {
    GNUNET_break (0);
    return;
  }
  keepalive
    = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_FOREVER_REL,
                                    &never_task,
                                    NULL);
  GNUNET_SCHEDULER_add_shutdown (&stop_fakebank,
                                 fakebank);
}


/**
 * Run the benchmark in parallel in many (client) processes
 * and summarize result.
 *
 * @return #GNUNET_OK on success
 */
static int
parallel_benchmark (void)
{
  enum GNUNET_GenericReturnValue result = GNUNET_OK;
  pid_t fakebank = -1;
  struct GNUNET_OS_Process *bankd = NULL;
  struct GNUNET_OS_Process *wirewatch = NULL;

  if ( (MODE_BANK == mode) ||
       (MODE_BOTH == mode) )
  {
    if (use_fakebank)
    {
      /* start fakebank */
      fakebank = fork ();
      if (0 == fakebank)
      {
        GNUNET_log_setup ("benchmark-fakebank",
                          NULL == loglev ? "INFO" : loglev,
                          logfile);
        GNUNET_SCHEDULER_run (&launch_fakebank,
                              NULL);
        exit (0);
      }
      if (-1 == fakebank)
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                             "fork");
        return GNUNET_SYSERR;
      }
      /* wait for fakebank to be ready */
      sleep (1);
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "FIXME: launching LibEuFin not yet supported\n");
      bankd = NULL; // FIXME
      return GNUNET_SYSERR;
    }

    {
      struct GNUNET_OS_Process *dbinit;

      dbinit = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                        NULL, NULL, NULL,
                                        "taler-exchange-dbinit",
                                        "taler-exchange-dbinit",
                                        "-c", cfg_filename,
                                        "-r",
                                        NULL);
      GNUNET_break (GNUNET_OK ==
                    GNUNET_OS_process_wait (dbinit));
      GNUNET_OS_process_destroy (dbinit);
    }
    if (start_wirewatch)
    {
      /* start exchange wirewatch */
      wirewatch = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                           NULL, NULL, NULL,
                                           "taler-exchange-wirewatch",
                                           "taler-exchange-wirewatch",
                                           "-c", cfg_filename,
                                           NULL);
      if (NULL == wirewatch)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Failed to launch wirewatch, aborting benchmark\n");
        if (-1 != fakebank)
        {
          int wstatus;

          kill (fakebank,
                SIGTERM);
          if (fakebank !=
              waitpid (fakebank,
                       &wstatus,
                       0))
          {
            GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                                 "waitpid");
          }
          fakebank = -1;
        }
        if (NULL != bankd)
        {
          GNUNET_OS_process_kill (bankd,
                                  SIGTERM);
          GNUNET_OS_process_destroy (bankd);
          bankd = NULL;
        }
        return GNUNET_SYSERR;
      }
    }
  }

  if ( (MODE_CLIENT == mode) ||
       (MODE_BOTH == mode) )
    result = launch_clients ();
  if ( (GNUNET_YES == linger) ||
       (MODE_BANK == mode) )
  {
    printf ("Press ENTER to stop!\n");
    (void) getchar ();
  }

  if ( (MODE_BANK == mode) ||
       (MODE_BOTH == mode) )
  {
    if (NULL != wirewatch)
    {
      /* stop wirewatch */
      GNUNET_break (0 ==
                    GNUNET_OS_process_kill (wirewatch,
                                            SIGTERM));
      GNUNET_break (GNUNET_OK ==
                    GNUNET_OS_process_wait (wirewatch));
      GNUNET_OS_process_destroy (wirewatch);
      wirewatch = NULL;
    }
    /* stop fakebank */
    if (-1 != fakebank)
    {
      int wstatus;

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Telling fakebank to shut down\n");
      kill (fakebank,
            SIGTERM);
      if (fakebank !=
          waitpid (fakebank,
                   &wstatus,
                   0))
      {
        GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                             "waitpid");
      }
      else
      {
        if ( (! WIFEXITED (wstatus)) ||
             (0 != WEXITSTATUS (wstatus)) )
        {
          GNUNET_break (0);
          result = GNUNET_SYSERR;
        }
      }
      fakebank = -1;
    }
    if (NULL != bankd)
    {
      GNUNET_OS_process_kill (bankd,
                              SIGTERM);
      GNUNET_OS_process_destroy (bankd);
    }
  }
  return result;
}


/**
 * The main function of the serve tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, or `enum PaymentGeneratorError` on error
 */
int
main (int argc,
      char *const *argv)
{
  enum GNUNET_GenericReturnValue result;
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_mandatory (
      GNUNET_GETOPT_option_cfgfile (&cfg_filename)),
#if FIXME_SUPPORT_LIBEUFIN
    GNUNET_GETOPT_option_flag ('f',
                               "fakebank",
                               "start a fakebank instead of the Python bank",
                               &use_fakebank),
#endif
    GNUNET_GETOPT_option_help ("taler-bank benchmark"),
    GNUNET_GETOPT_option_flag ('K',
                               "linger",
                               "linger around until key press",
                               &linger),
    GNUNET_GETOPT_option_string ('l',
                                 "logfile",
                                 "LF",
                                 "will log to file LF",
                                 &logfile),
    GNUNET_GETOPT_option_loglevel (&loglev),
    GNUNET_GETOPT_option_string ('m',
                                 "mode",
                                 "MODE",
                                 "run as bank, client or both",
                                 &mode_str),
    GNUNET_GETOPT_option_uint ('p',
                               "worker-parallelism",
                               "NPROCS",
                               "How many client processes we should run",
                               &howmany_clients),
    GNUNET_GETOPT_option_uint ('P',
                               "service-parallelism",
                               "NTHREADS",
                               "How many service threads we should create",
                               &howmany_threads),
    GNUNET_GETOPT_option_uint ('r',
                               "reserves",
                               "NRESERVES",
                               "How many reserves per client we should create",
                               &howmany_reserves),
    GNUNET_GETOPT_option_ulong ('s',
                                "size",
                                "HISTORY_SIZE",
                                "Maximum history size kept in memory by the fakebank",
                                &history_size),
    GNUNET_GETOPT_option_version (PACKAGE_VERSION " " VCS_VERSION),
    GNUNET_GETOPT_option_verbose (&verbose),
    GNUNET_GETOPT_option_flag ('w',
                               "wirewatch",
                               "run taler-exchange-wirewatch",
                               &start_wirewatch),
    GNUNET_GETOPT_OPTION_END
  };

  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  if (0 >=
      (result = GNUNET_GETOPT_run ("taler-bank-benchmark",
                                   options,
                                   argc,
                                   argv)))
  {
    GNUNET_free (cfg_filename);
    if (GNUNET_NO == result)
      return 0;
    return BAD_CLI_ARG;
  }
  GNUNET_log_setup ("taler-bank-benchmark",
                    NULL == loglev ? "INFO" : loglev,
                    logfile);
  if (history_size < 10)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "History size too small, this can hardly work\n");
    return BAD_CLI_ARG;
  }
  if (NULL == mode_str)
    mode = MODE_BOTH;
  else if (0 == strcasecmp (mode_str,
                            "bank"))
    mode = MODE_BANK;
  else if (0 == strcasecmp (mode_str,
                            "client"))
    mode = MODE_CLIENT;
  else if (0 == strcasecmp (mode_str,
                            "both"))
    mode = MODE_BOTH;
  else
  {
    TALER_LOG_ERROR ("Unknown mode given: '%s'\n",
                     mode_str);
    GNUNET_free (cfg_filename);
    return BAD_CONFIG_FILE;
  }
  if (NULL == cfg_filename)
    cfg_filename = GNUNET_strdup (
      GNUNET_OS_project_data_get ()->user_config_file);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 cfg_filename))
  {
    TALER_LOG_ERROR ("Could not parse configuration\n");
    GNUNET_free (cfg_filename);
    return BAD_CONFIG_FILE;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency))
  {
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (cfg_filename);
    return BAD_CONFIG_FILE;
  }
  if (MODE_BANK != mode)
  {
    if (howmany_clients > 10240)
    {
      TALER_LOG_ERROR ("-p option value given is too large\n");
      return BAD_CLI_ARG;
    }
    if (0 == howmany_clients)
    {
      TALER_LOG_ERROR ("-p option value must not be zero\n");
      GNUNET_free (cfg_filename);
      return BAD_CLI_ARG;
    }
  }
  {
    const char *bank_details_section;

    GNUNET_CONFIGURATION_iterate_sections (cfg,
                                           &pick_exchange_account_cb,
                                           &bank_details_section);
    if (NULL == bank_details_section)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Missing specification of bank account in configuration\n");
      GNUNET_free (cfg_filename);
      return BAD_CONFIG_FILE;
    }
    if (GNUNET_OK !=
        TALER_BANK_auth_parse_cfg (cfg,
                                   bank_details_section,
                                   &exchange_bank_account))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Configuration fails to provide exchange bank details in section `%s'\n",
                  bank_details_section);
      GNUNET_free (cfg_filename);
      return BAD_CONFIG_FILE;
    }
  }
  result = parallel_benchmark ();
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (cfg_filename);

  if (MODE_BANK == mode)
  {
    /* If we're the bank, we're done now.  No need to print results. */
    return (GNUNET_OK == result) ? 0 : result;
  }
  duration = GNUNET_TIME_absolute_get_duration (start_time);
  if (GNUNET_OK == result)
  {
    struct rusage usage;
    unsigned long long tps;

    GNUNET_assert (0 == getrusage (RUSAGE_CHILDREN,
                                   &usage));
    fprintf (stdout,
             "Executed Reserve=%u * Parallel=%u, operations in %s\n",
             howmany_reserves,
             howmany_clients,
             GNUNET_STRINGS_relative_time_to_string (duration,
                                                     GNUNET_YES));
    tps = ((unsigned long long) howmany_reserves) * howmany_clients * 1000LLU
          / (duration.rel_value_us / 1000LL);
    fprintf (stdout,
             "RAW: %04u %04u %16llu (%llu TPS)\n",
             howmany_reserves,
             howmany_clients,
             (unsigned long long) duration.rel_value_us,
             tps);
    fprintf (stdout,
             "CPU time: sys %llu user %llu\n",                          \
             (unsigned long long) (usage.ru_stime.tv_sec * 1000 * 1000
                                   + usage.ru_stime.tv_usec),
             (unsigned long long) (usage.ru_utime.tv_sec * 1000 * 1000
                                   + usage.ru_utime.tv_usec));
  }
  for (unsigned int i = 0; i<label_off; i++)
    GNUNET_free (labels[i]);
  GNUNET_array_grow (labels,
                     label_len,
                     0);
  return (GNUNET_OK == result) ? 0 : result;
}
