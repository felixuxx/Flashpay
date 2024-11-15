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
 * @file benchmark/taler-exchange-benchmark.c
 * @brief HTTP serving layer intended to perform crypto-work and
 * communication with the exchange
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include <sys/resource.h>
#include "taler_util.h"
#include "taler_testing_lib.h"

/**
 * The whole benchmark is a repetition of a "unit".  Each
 * unit is a array containing a withdraw+deposit operation,
 * and _possibly_ a refresh of the deposited coin.
 */
#define UNITY_SIZE 6


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
 * How many coins we want to create per client and reserve.
 */
static unsigned int howmany_coins = 1;

/**
 * How many reserves we want to create per client.
 */
static unsigned int howmany_reserves = 1;

/**
 * Probability (in percent) of refreshing per spent coin.
 */
static unsigned int refresh_rate = 10;

/**
 * How many clients we want to create.
 */
static unsigned int howmany_clients = 1;

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
 * Should we create all of the reserves at the beginning?
 */
static int reserves_first;

/**
 * Are we running against 'fakebank'?
 */
static int use_fakebank;

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
  { .prefix = "withdraw" },
  { .prefix = "deposit" },
  { .prefix = "melt" },
  { .prefix = "reveal" },
  { .prefix = "link" },
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


static struct TALER_TESTING_Command
cmd_transfer_to_exchange (const char *label,
                          const char *amount)
{
  return TALER_TESTING_cmd_admin_add_incoming_retry (
    TALER_TESTING_cmd_admin_add_incoming (label,
                                          amount,
                                          &cred.ba_admin,
                                          cred.user42_payto));
}


/**
 * Throw a weighted coin with @a probability.
 *
 * @param probability weight of the coin flip
 * @return #GNUNET_OK with @a probability,
 *         #GNUNET_NO with 1 - @a probability
 */
static unsigned int
eval_probability (float probability)
{
  uint64_t random;
  float random_01;

  random = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                     UINT64_MAX);
  random_01 = (double) random / (double) UINT64_MAX;
  return (random_01 <= probability) ? GNUNET_OK : GNUNET_NO;
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
  struct TALER_Amount total_reserve_amount;
  struct TALER_Amount withdraw_fee;
  char *withdraw_fee_str;
  char *amount_5;
  char *amount_4;
  char *amount_1;

  (void) cls;
  all_commands = GNUNET_malloc_large (
    (1 /* exchange CMD */
     + howmany_reserves
     * (1 /* Withdraw block */
        + howmany_coins) /* All units */
     + 1 /* stat CMD */
     + 1 /* End CMD */) * sizeof (struct TALER_TESTING_Command));
  GNUNET_assert (NULL != all_commands);
  all_commands[0]
    = TALER_TESTING_cmd_get_exchange ("get-exchange",
                                      cred.cfg,
                                      NULL,
                                      true,
                                      true);
  GNUNET_asprintf (&amount_5, "%s:5", currency);
  GNUNET_asprintf (&amount_4, "%s:4", currency);
  GNUNET_asprintf (&amount_1, "%s:1", currency);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &total_reserve_amount));
  total_reserve_amount.value = 5 * howmany_coins;
  GNUNET_asprintf (&withdraw_fee_str,
                   "%s:0.1",
                   currency);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (withdraw_fee_str,
                                         &withdraw_fee));
  for (unsigned int i = 0; i < howmany_coins; i++)
    GNUNET_assert (0 <=
                   TALER_amount_add (&total_reserve_amount,
                                     &total_reserve_amount,
                                     &withdraw_fee));
  for (unsigned int j = 0; j < howmany_reserves; j++)
  {
    char *create_reserve_label;

    GNUNET_asprintf (&create_reserve_label,
                     "createreserve-%u",
                     j);
    {
      struct TALER_TESTING_Command make_reserve[] = {
        cmd_transfer_to_exchange (add_label (create_reserve_label),
                                  TALER_amount2s (&total_reserve_amount)),
        TALER_TESTING_cmd_end ()
      };
      char *batch_label;

      GNUNET_asprintf (&batch_label,
                       "batch-start-%u",
                       j);
      all_commands[1 + (reserves_first
                        ? j
                        : j * (howmany_coins + 1))]
        = TALER_TESTING_cmd_batch (add_label (batch_label),
                                   make_reserve);
    }
    for (unsigned int i = 0; i < howmany_coins; i++)
    {
      char *withdraw_label;
      char *order_enc;
      struct TALER_TESTING_Command unit[UNITY_SIZE];
      char *unit_label;
      const char *wl;

      GNUNET_asprintf (&withdraw_label,
                       "withdraw-%u-%u",
                       i,
                       j);
      wl = add_label (withdraw_label);
      GNUNET_asprintf (&order_enc,
                       "{\"nonce\": %llu}",
                       ((unsigned long long) i)
                       + (howmany_coins * (unsigned long long) j));
      unit[0] =
        TALER_TESTING_cmd_withdraw_with_retry (
          TALER_TESTING_cmd_withdraw_amount (wl,
                                             create_reserve_label,
                                             amount_5,
                                             0,  /* age restriction off */
                                             MHD_HTTP_OK));
      unit[1] =
        TALER_TESTING_cmd_deposit_with_retry (
          TALER_TESTING_cmd_deposit ("deposit",
                                     wl,
                                     0,  /* Index of the one withdrawn coin in the traits.  */
                                     cred.user43_payto,
                                     add_label (order_enc),
                                     GNUNET_TIME_UNIT_ZERO,
                                     amount_1,
                                     MHD_HTTP_OK));
      if (eval_probability (refresh_rate / 100.0d))
      {
        char *melt_label;
        char *reveal_label;
        const char *ml;
        const char *rl;

        GNUNET_asprintf (&melt_label,
                         "melt-%u-%u",
                         i,
                         j);
        ml = add_label (melt_label);
        GNUNET_asprintf (&reveal_label,
                         "reveal-%u-%u",
                         i,
                         j);
        rl = add_label (reveal_label);
        unit[2] =
          TALER_TESTING_cmd_melt_with_retry (
            TALER_TESTING_cmd_melt (ml,
                                    wl,
                                    MHD_HTTP_OK,
                                    NULL));
        unit[3] =
          TALER_TESTING_cmd_refresh_reveal_with_retry (
            TALER_TESTING_cmd_refresh_reveal (rl,
                                              ml,
                                              MHD_HTTP_OK));
        unit[4] =
          TALER_TESTING_cmd_refresh_link_with_retry (
            TALER_TESTING_cmd_refresh_link ("link",
                                            rl,
                                            MHD_HTTP_OK));
        unit[5] = TALER_TESTING_cmd_end ();
      }
      else
        unit[2] = TALER_TESTING_cmd_end ();

      GNUNET_asprintf (&unit_label,
                       "unit-%u-%u",
                       i,
                       j);
      all_commands[1 + (reserves_first
                        ? howmany_reserves + j * howmany_coins + i
                        : j * (howmany_coins + 1) + (1 + i))]
        = TALER_TESTING_cmd_batch (add_label (unit_label),
                                   unit);
    }
  }
  all_commands[1 + howmany_reserves * (1 + howmany_coins)]
    = TALER_TESTING_cmd_stat (timings);
  all_commands[1 + howmany_reserves * (1 + howmany_coins) + 1]
    = TALER_TESTING_cmd_end ();
  TALER_TESTING_run2 (is,
                      all_commands,
                      GNUNET_TIME_UNIT_FOREVER_REL); /* no timeout */
  GNUNET_free (amount_1);
  GNUNET_free (amount_4);
  GNUNET_free (amount_5);
  GNUNET_free (withdraw_fee_str);
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
 * Run the benchmark in parallel in many (client) processes
 * and summarize result.
 *
 * @param main_cb main function to run per process
 * @param main_cb_cls closure for @a main_cb
 * @param config_file configuration file to use
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parallel_benchmark (TALER_TESTING_Main main_cb,
                    void *main_cb_cls,
                    const char *config_file)
{
  enum GNUNET_GenericReturnValue result = GNUNET_OK;
  pid_t cpids[howmany_clients];

  if (1 == howmany_clients)
  {
    result = TALER_TESTING_loop (main_cb,
                                 main_cb_cls);
    print_stats ();
  }
  else
  {
    for (unsigned int i = 0; i<howmany_clients; i++)
    {
      if (0 == (cpids[i] = fork ()))
      {
        /* I am the child, do the work! */
        GNUNET_log_setup ("benchmark-worker",
                          loglev,
                          logfile);
        result = TALER_TESTING_loop (main_cb,
                                     main_cb_cls);
        print_stats ();
        if (GNUNET_OK != result)
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                      "Failure in child process %u test suite!\n",
                      i);
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

      waitpid (cpids[i],
               &wstatus,
               0);
      if ( (! WIFEXITED (wstatus)) ||
           (0 != WEXITSTATUS (wstatus)) )
      {
        GNUNET_break (0);
        result = GNUNET_SYSERR;
      }
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
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_mandatory (
      GNUNET_GETOPT_option_cfgfile (
        &cfg_filename)),
    GNUNET_GETOPT_option_version (
      PACKAGE_VERSION " " VCS_VERSION),
    GNUNET_GETOPT_option_flag (
      'f',
      "fakebank",
      "use fakebank for the banking system",
      &use_fakebank),
    GNUNET_GETOPT_option_flag (
      'F',
      "reserves-first",
      "should all reserves be created first, before starting normal operations",
      &reserves_first),
    GNUNET_GETOPT_option_help (
      TALER_EXCHANGE_project_data (),
      "Exchange benchmark"),
    GNUNET_GETOPT_option_string (
      'l',
      "logfile",
      "LF",
      "will log to file LF",
      &logfile),
    GNUNET_GETOPT_option_loglevel (
      &loglev),
    GNUNET_GETOPT_option_uint (
      'n',
      "coins-number",
      "CN",
      "How many coins we should instantiate per reserve",
      &howmany_coins),
    GNUNET_GETOPT_option_uint (
      'p',
      "parallelism",
      "NPROCS",
      "How many client processes we should run",
      &howmany_clients),
    GNUNET_GETOPT_option_uint (
      'r',
      "reserves",
      "NRESERVES",
      "How many reserves per client we should create",
      &howmany_reserves),
    GNUNET_GETOPT_option_uint (
      'R',
      "refresh-rate",
      "RATE",
      "Probability of refresh per coin (0-100)",
      &refresh_rate),
    GNUNET_GETOPT_option_string (
      'u',
      "exchange-account-section",
      "SECTION",
      "use exchange bank account configuration from the given SECTION",
      &exchange_bank_section),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue result;
  struct GNUNET_TIME_Relative duration;

  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  if (0 >=
      (result = GNUNET_GETOPT_run ("taler-exchange-benchmark",
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
  GNUNET_log_setup ("taler-exchange-benchmark",
                    loglev,
                    logfile);
  if (NULL == cfg_filename)
    cfg_filename = GNUNET_CONFIGURATION_default_filename (
      TALER_EXCHANGE_project_data ());
  if (NULL == cfg_filename)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Can't find default configuration file.\n");
    return EXIT_NOTCONFIGURED;
  }
  cfg = GNUNET_CONFIGURATION_create (TALER_EXCHANGE_project_data ());
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
                                 "exchange",
                                 &currency))
  {
    GNUNET_CONFIGURATION_destroy (cfg);
    GNUNET_free (cfg_filename);
    return EXIT_NOTCONFIGURED;
  }
  if (howmany_clients > 10240)
  {
    TALER_LOG_ERROR ("-p option value given is too large\n");
    return EXIT_INVALIDARGUMENT;
  }
  if (0 == howmany_clients)
  {
    TALER_LOG_ERROR ("-p option value must not be zero\n");
    GNUNET_free (cfg_filename);
    return EXIT_INVALIDARGUMENT;
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
    result = parallel_benchmark (&run,
                                 NULL,
                                 cfg_filename);
    duration = GNUNET_TIME_absolute_get_duration (start_time);
  }

  if (GNUNET_OK == result)
  {
    struct rusage usage;

    GNUNET_assert (0 == getrusage (RUSAGE_CHILDREN,
                                   &usage));
    fprintf (stdout,
             "Executed (Withdraw=%u, Deposit=%u, Refresh~=%5.2f)"
             " * Reserve=%u * Parallel=%u, operations in %s\n",
             howmany_coins,
             howmany_coins,
             howmany_coins * (refresh_rate / 100.0d),
             howmany_reserves,
             howmany_clients,
             GNUNET_STRINGS_relative_time_to_string (
               duration,
               false));
    fprintf (stdout,
             "(approximately %s/coin)\n",
             GNUNET_STRINGS_relative_time_to_string (
               GNUNET_TIME_relative_divide (
                 duration,
                 (unsigned long long) howmany_coins
                 * howmany_reserves
                 * howmany_clients),
               true));
    fprintf (stdout,
             "RAW: %04u %04u %04u %16llu\n",
             howmany_coins,
             howmany_reserves,
             howmany_clients,
             (unsigned long long) duration.rel_value_us);
    fprintf (stdout,
             "cpu time: sys %llu user %llu\n",
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
