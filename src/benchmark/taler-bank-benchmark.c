/*
  This file is part of TALER
  (C) 2014-2023 Taler Systems SA

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
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include <sys/resource.h>
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_exchangedb_lib.h"
#include "taler_fakebank_lib.h"
#include "taler_testing_lib.h"
#include "taler_error_codes.h"

#define SHARD_SIZE "1024"

/**
 * Credentials to use for the benchmark.
 */
static struct TALER_TESTING_Credentials cred;

/**
 * Array of all the commands the benchmark is running.
 */
static struct TALER_TESTING_Command *all_commands;

/**
 * Name of our configuration file.
 */
static char *cfg_filename;

/**
 * Use the fakebank instead of LibEuFin.
 */
static int use_fakebank;

/**
 * Verbosity level.
 */
static unsigned int verbose;

/**
 * How many reserves we want to create per client.
 */
static unsigned int howmany_reserves = 1;

/**
 * How many clients we want to create.
 */
static unsigned int howmany_clients = 1;

/**
 * How many wirewatch processes do we want to create.
 */
static unsigned int start_wirewatch;

/**
 * Log level used during the run.
 */
static char *loglev;

/**
 * Log file.
 */
static char *logfile;

/**
 * Configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Section with the configuration data for the exchange
 * bank account.
 */
static char *exchange_bank_section;

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
static const char *
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
                                              true));
    latency = GNUNET_strdup (
      GNUNET_STRINGS_relative_time_to_string (timings[i].success_latency,
                                              true));
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
  all_commands = GNUNET_malloc_large ((1 + len)
                                      * sizeof (struct TALER_TESTING_Command));
  GNUNET_assert (NULL != all_commands);
  all_commands[0]
    = TALER_TESTING_cmd_get_exchange ("get-exchange",
                                      cred.cfg,
                                      NULL,
                                      true,
                                      true);

  GNUNET_asprintf (&total_reserve_amount,
                   "%s:5",
                   currency);
  for (unsigned int j = 0; j < howmany_reserves; j++)
  {
    char *create_reserve_label;

    GNUNET_asprintf (&create_reserve_label,
                     "createreserve-%u",
                     j);
    // TODO: vary user accounts more...
    all_commands[1 + j]
      = TALER_TESTING_cmd_admin_add_incoming_retry (
          TALER_TESTING_cmd_admin_add_incoming (add_label (
                                                  create_reserve_label),
                                                total_reserve_amount,
                                                &cred.ba_admin,
                                                cred.user42_payto));
  }
  GNUNET_free (total_reserve_amount);
  all_commands[1 + howmany_reserves]
    = TALER_TESTING_cmd_stat (timings);
  all_commands[1 + howmany_reserves + 1]
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

  if (1 == howmany_clients)
  {
    /* do everything in this process */
    result = TALER_TESTING_loop (&run,
                                 NULL);
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
      result = TALER_TESTING_loop (&run,
                                   NULL);
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
 * Run the benchmark in parallel in many (client) processes
 * and summarize result.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parallel_benchmark (void)
{
  enum GNUNET_GenericReturnValue result = GNUNET_OK;
  struct GNUNET_OS_Process *wirewatch[GNUNET_NZL (start_wirewatch)];

  memset (wirewatch,
          0,
          sizeof (wirewatch));
  /* start exchange wirewatch */
  for (unsigned int w = 0; w<start_wirewatch; w++)
  {
    wirewatch[w] = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                            NULL, NULL, NULL,
                                            "taler-exchange-wirewatch",
                                            "taler-exchange-wirewatch",
                                            "-c", cfg_filename,
                                            "-a", exchange_bank_section,
                                            "-S", SHARD_SIZE,
                                            (NULL != loglev) ? "-L" : NULL,
                                            loglev,
                                            NULL);
    if (NULL == wirewatch[w])
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to launch wirewatch, aborting benchmark\n");
      for (unsigned int x = 0; x<w; x++)
      {
        GNUNET_break (0 ==
                      GNUNET_OS_process_kill (wirewatch[x],
                                              SIGTERM));
        GNUNET_break (GNUNET_OK ==
                      GNUNET_OS_process_wait (wirewatch[x]));
        GNUNET_OS_process_destroy (wirewatch[x]);
        wirewatch[x] = NULL;
      }
      return GNUNET_SYSERR;
    }
  }
  result = launch_clients ();
  /* Ensure wirewatch runs to completion! */
  if (0 != start_wirewatch)
  {
    /* replace ONE of the wirewatchers with one that is in test-mode */
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (wirewatch[0],
                                          SIGTERM));
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (wirewatch[0]));
    GNUNET_OS_process_destroy (wirewatch[0]);
    wirewatch[0] = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                            NULL, NULL, NULL,
                                            "taler-exchange-wirewatch",
                                            "taler-exchange-wirewatch",
                                            "-c", cfg_filename,
                                            "-a", exchange_bank_section,
                                            "-S", SHARD_SIZE,
                                            "-t",
                                            (NULL != loglev) ? "-L" : NULL,
                                            loglev,
                                            NULL);
    /* wait for it to finish! */
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (wirewatch[0]));
    GNUNET_OS_process_destroy (wirewatch[0]);
    wirewatch[0] = NULL;
    /* Then stop the rest, which should basically also be finished */
    for (unsigned int w = 1; w<start_wirewatch; w++)
    {
      GNUNET_break (0 ==
                    GNUNET_OS_process_kill (wirewatch[w],
                                            SIGTERM));
      GNUNET_break (GNUNET_OK ==
                    GNUNET_OS_process_wait (wirewatch[w]));
      GNUNET_OS_process_destroy (wirewatch[w]);
    }

    /* But be extra sure we did finish all shards by doing one more */
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Shard check phase\n");
    wirewatch[0] = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ALL,
                                            NULL, NULL, NULL,
                                            "taler-exchange-wirewatch",
                                            "taler-exchange-wirewatch",
                                            "-c", cfg_filename,
                                            "-a", exchange_bank_section,
                                            "-S", SHARD_SIZE,
                                            "-t",
                                            (NULL != loglev) ? "-L" : NULL,
                                            loglev,
                                            NULL);
    /* wait for it to finish! */
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (wirewatch[0]));
    GNUNET_OS_process_destroy (wirewatch[0]);
    wirewatch[0] = NULL;
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
    GNUNET_GETOPT_option_flag ('f',
                               "fakebank",
                               "we are using fakebank",
                               &use_fakebank),
    GNUNET_GETOPT_option_help ("taler-bank benchmark"),
    GNUNET_GETOPT_option_string ('l',
                                 "logfile",
                                 "LF",
                                 "will log to file LF",
                                 &logfile),
    GNUNET_GETOPT_option_loglevel (&loglev),
    GNUNET_GETOPT_option_uint ('p',
                               "worker-parallelism",
                               "NPROCS",
                               "How many client processes we should run",
                               &howmany_clients),
    GNUNET_GETOPT_option_uint ('r',
                               "reserves",
                               "NRESERVES",
                               "How many reserves per client we should create",
                               &howmany_reserves),
    GNUNET_GETOPT_option_mandatory (
      GNUNET_GETOPT_option_string (
        'u',
        "exchange-account-section",
        "SECTION",
        "use exchange bank account configuration from the given SECTION",
        &exchange_bank_section)),
    GNUNET_GETOPT_option_version (PACKAGE_VERSION " " VCS_VERSION),
    GNUNET_GETOPT_option_verbose (&verbose),
    GNUNET_GETOPT_option_uint ('w',
                               "wirewatch",
                               "NPROC",
                               "run NPROC taler-exchange-wirewatch processes",
                               &start_wirewatch),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_TIME_Relative duration;

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
    return EXIT_INVALIDARGUMENT;
  }
  if (NULL == exchange_bank_section)
    exchange_bank_section = "exchange-account-1";
  if (NULL == loglev)
    loglev = "INFO";
  GNUNET_log_setup ("taler-bank-benchmark",
                    loglev,
                    logfile);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 cfg_filename))
  {
    TALER_LOG_ERROR ("Could not parse configuration\n");
    GNUNET_free (cfg_filename);
    return EXIT_NOTCONFIGURED;
  }
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency))
  {
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (cfg_filename);
    return EXIT_NOTCONFIGURED;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_credentials (
        cfg_filename,
        exchange_bank_section,
        use_fakebank
        ? TALER_TESTING_BS_FAKEBANK
        : TALER_TESTING_BS_IBAN,
        &cred))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Required bank credentials not given in configuration\n");
    GNUNET_free (cfg_filename);
    return EXIT_NOTCONFIGURED;
  }

  {
    struct GNUNET_TIME_Absolute start_time;

    start_time = GNUNET_TIME_absolute_get ();
    result = parallel_benchmark ();
    duration = GNUNET_TIME_absolute_get_duration (start_time);
  }

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
    if (! GNUNET_TIME_relative_is_zero (duration))
    {
      tps = ((unsigned long long) howmany_reserves) * howmany_clients * 1000LLU
            / (duration.rel_value_us / 1000LL);
      fprintf (stdout,
               "RAW: %04u %04u %16llu (%llu TPS)\n",
               howmany_reserves,
               howmany_clients,
               (unsigned long long) duration.rel_value_us,
               tps);
    }
    fprintf (stdout,
             "CPU time: sys %llu user %llu\n",
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
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (cfg_filename);
  return (GNUNET_OK == result) ? 0 : result;
}
