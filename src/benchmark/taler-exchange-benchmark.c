/*
  This file is part of TALER
  (C) 2014-2020 Taler Systems SA

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
#include "taler_signatures.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "taler_wire_lib.h"
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
 * The whole benchmark is a repetition of a "unit".  Each
 * unit is a array containing a withdraw+deposit operation,
 * and _possibly_ a refresh of the deposited coin.
 */
#define UNITY_SIZE 6

#define FIRST_INSTRUCTION -1

#define CMD_TRANSFER_TO_EXCHANGE(label, amount) \
  TALER_TESTING_cmd_admin_add_incoming_retry \
    (TALER_TESTING_cmd_admin_add_incoming (label, amount, \
                                           exchange_bank_account.details.                                      \
                                           x_taler_bank.account_base_url, \
                                           NULL, \
                                           user_payto_url))


/**
 * What mode should the benchmark run in?
 */
enum BenchmarkMode
{
  /**
   * Run as client (with fakebank), also starts a remote exchange.
   */
  MODE_CLIENT = 1,

  /**
   * Run the the exchange.
   */
  MODE_EXCHANGE = 2,

  /**
   * Run both, for a local benchmark.
   */
  MODE_BOTH = 3,
};


/**
 * Hold information regarding which bank has the exchange account.
 */
static struct TALER_Account exchange_bank_account;

/**
 * Configuration of our exchange.
 */
static struct TALER_TESTING_ExchangeConfiguration ec;

/**
 * Hold information about a user at the bank.
 */
static char *user_payto_url;

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
 * Exit code.
 */
static int result;

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
 * Benchmarking mode (run as client, exchange, both) as string.
 */
static char *mode_str;

/**
 * Benchmarking mode (run as client, exchange, both).
 */
static enum BenchmarkMode mode;

/**
 * Config filename.
 */
static char *cfg_filename;

/**
 * payto://-URL of the exchange's bank account.
 */
static char *exchange_payto_url;

/**
 * Currency used.
 */
static char *currency;

/**
 * Remote host that runs the exchange.
 */
static char *remote_host;

/**
 * Remote benchmarking directory.
 */
static char *remote_dir;

/**
 * Don't kill exchange/fakebank/wirewatch until
 * requested by the user explicitly.
 */
static int linger;


/**
 * Decide which exchange account is going to be
 * used to address a wire transfer to.  Used at
 * withdrawal time.
 *
 * @param cls closure
 * @param section section name.
 */
static void
pick_exchange_account_cb (void *cls,
                          const char *section)
{
  if (0 == strncasecmp ("account-",
                        section,
                        strlen ("account-")))
  {
    const char **s = cls;

    *s = section;
  }
}


/**
 * Throw a weighted coin with @a probability.
 *
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
  random_01 = (double) random / UINT64_MAX;
  return (random_01 <= probability) ? GNUNET_OK : GNUNET_NO;
}


/**
 * Actual commands collection.
 */
static void
run (void *cls,
     struct TALER_TESTING_Interpreter *is)
{
  struct TALER_Amount total_reserve_amount;
  struct TALER_Amount withdraw_fee;
  char *withdraw_fee_str;
  struct TALER_TESTING_Command all_commands
  [howmany_reserves * (1     /* Withdraw block */
                       + howmany_coins)   /* All units */
   + 1 /* End CMD */];
  char *AMOUNT_5;
  char *AMOUNT_4;
  char *AMOUNT_1;

  (void) cls;
  GNUNET_asprintf (&AMOUNT_5, "%s:5", currency);
  GNUNET_asprintf (&AMOUNT_4, "%s:4", currency);
  GNUNET_asprintf (&AMOUNT_1, "%s:1", currency);

  GNUNET_assert (GNUNET_OK == TALER_amount_get_zero (currency,
                                                     &total_reserve_amount));
  total_reserve_amount.value = 5 * howmany_coins;

  GNUNET_asprintf (&withdraw_fee_str,
                   "%s:0.1",
                   currency);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (withdraw_fee_str,
                                         &withdraw_fee));
  for (unsigned int i = 0; i < howmany_coins; i++)
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&total_reserve_amount,
                                     &total_reserve_amount,
                                     &withdraw_fee));
  for (unsigned int j = 0; j < howmany_reserves; j++)
  {
    char *create_reserve_label;

    GNUNET_asprintf (&create_reserve_label,
                     "create-reserve-%u",
                     j);
    {
      struct TALER_TESTING_Command make_reserve[] = {
        CMD_TRANSFER_TO_EXCHANGE
          (create_reserve_label,
          TALER_amount_to_string (&total_reserve_amount)),
        TALER_TESTING_cmd_end ()
      };
      char *batch_label;

      GNUNET_asprintf (&batch_label,
                       "batch-start-%u",
                       j);
      all_commands[j * (howmany_coins + 1)]
        = TALER_TESTING_cmd_batch (batch_label,
                                   make_reserve);
    }
    for (unsigned int i = 0; i < howmany_coins; i++)
    {
      char *withdraw_label;
      char *order_enc;
      struct TALER_TESTING_Command unit[UNITY_SIZE];
      char *unit_label;

      GNUNET_asprintf (&withdraw_label,
                       "withdraw-%u-%u",
                       i,
                       j);
      GNUNET_asprintf (&order_enc,
                       "{\"nonce\": %llu}",
                       i + (howmany_coins * j));
      unit[0] =
        TALER_TESTING_cmd_withdraw_with_retry
          (TALER_TESTING_cmd_withdraw_amount
            (withdraw_label,
            create_reserve_label,
            AMOUNT_5,
            MHD_HTTP_OK));
      unit[1] =
        TALER_TESTING_cmd_deposit_with_retry
          (TALER_TESTING_cmd_deposit
            ("deposit",
            withdraw_label,
            0, /* Index of the one withdrawn coin in the traits.  */
            TALER_TESTING_make_wire_details
              (42 /* FIXME: ugly! */,
              exchange_bank_account.details.x_taler_bank.hostname),
            order_enc,
            GNUNET_TIME_UNIT_ZERO,
            AMOUNT_1,
            MHD_HTTP_OK));

      if (eval_probability (refresh_rate / 100.0))
      {
        char *melt_label;
        char *reveal_label;

        GNUNET_asprintf (&melt_label,
                         "refresh-melt-%u-%u",
                         i,
                         j);
        GNUNET_asprintf (&reveal_label,
                         "refresh-reveal-%u-%u",
                         i,
                         j);
        unit[2] =
          TALER_TESTING_cmd_refresh_melt_with_retry
            (TALER_TESTING_cmd_refresh_melt
              (melt_label,
              withdraw_label,
              MHD_HTTP_OK,
              NULL));
        unit[3] =
          TALER_TESTING_cmd_refresh_reveal_with_retry
            (TALER_TESTING_cmd_refresh_reveal
              (reveal_label,
              melt_label,
              MHD_HTTP_OK));
        unit[4] =
          TALER_TESTING_cmd_refresh_link_with_retry
            (TALER_TESTING_cmd_refresh_link
              ("refresh-link",
              reveal_label,
              MHD_HTTP_OK));
        unit[5] = TALER_TESTING_cmd_end ();
      }
      else
        unit[2] = TALER_TESTING_cmd_end ();

      GNUNET_asprintf (&unit_label,
                       "unit-%u-%u",
                       i,
                       j);
      all_commands[j * (howmany_coins + 1) + (1 + i)]
        = TALER_TESTING_cmd_batch (unit_label,
                                   unit);
    }
  }
  all_commands[howmany_reserves * (1 + howmany_coins)]
    = TALER_TESTING_cmd_end ();
  TALER_TESTING_run2 (is,
                      all_commands,
                      GNUNET_TIME_UNIT_FOREVER_REL); /* no timeout */
  result = 1;
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

  TALER_FAKEBANK_stop (fakebank);
}


/**
 * Start the fakebank.
 *
 * @param cls the URL of the fakebank
 */
static void
launch_fakebank (void *cls)
{
  const char *hostname = cls;
  const char *port;
  long pnum;
  struct TALER_FAKEBANK_Handle *fakebank;

  port = strrchr (hostname,
                  (unsigned char) ':');
  if (NULL == port)
    pnum = 80;
  else
    pnum = strtol (port + 1, NULL, 10);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Starting Fakebank on port %u (%s)\n",
              (unsigned int) pnum,
              hostname);
  fakebank = TALER_FAKEBANK_start ((uint16_t) pnum);
  if (NULL == fakebank)
  {
    GNUNET_break (0);
    return;
  }
  GNUNET_SCHEDULER_add_shutdown (&stop_fakebank,
                                 fakebank);
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
static int
parallel_benchmark (TALER_TESTING_Main main_cb,
                    void *main_cb_cls,
                    const char *config_file)
{
  int result = GNUNET_OK;
  pid_t cpids[howmany_clients];
  pid_t fakebank = -1;
  int wstatus;
  struct GNUNET_OS_Process *exchanged = NULL;
  struct GNUNET_OS_Process *wirewatch = NULL;
  struct GNUNET_OS_Process *exchange_slave = NULL;
  struct GNUNET_DISK_PipeHandle *exchange_slave_pipe;

  if ( (MODE_CLIENT == mode) || (MODE_BOTH == mode) )
  {
    /* start fakebank */
    fakebank = fork ();
    if (0 == fakebank)
    {
      GNUNET_log_setup ("benchmark-fakebank",
                        NULL == loglev ? "INFO" : loglev,
                        logfile);
      GNUNET_SCHEDULER_run (&launch_fakebank,
                            exchange_bank_account.details.x_taler_bank.hostname);
      exit (0);
    }
    if (-1 == fakebank)
    {
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                           "fork");
      return GNUNET_SYSERR;
    }
  }

  if ( (MODE_EXCHANGE == mode) || (MODE_BOTH == mode) )
  {
    /* start exchange */
    exchanged = GNUNET_OS_start_process (GNUNET_NO,
                                         GNUNET_OS_INHERIT_STD_ALL,
                                         NULL, NULL, NULL,
                                         "taler-exchange-httpd",
                                         "taler-exchange-httpd",
                                         "-c", config_file,
                                         "-i",
                                         "-C",
                                         NULL);
    if ( (NULL == exchanged) && (MODE_BOTH == mode) )
    {
      GNUNET_assert (-1 != fakebank);
      kill (fakebank,
            SIGTERM);
      waitpid (fakebank,
               &wstatus,
               0);
      return 77;
    }
    /* start exchange wirewatch */
    wirewatch = GNUNET_OS_start_process (GNUNET_NO,
                                         GNUNET_OS_INHERIT_STD_ALL,
                                         NULL, NULL, NULL,
                                         "taler-exchange-wirewatch",
                                         "taler-exchange-wirewatch",
                                         "-c", config_file,
                                         NULL);
    if (NULL == wirewatch)
    {
      GNUNET_OS_process_kill (exchanged,
                              SIGTERM);
      if (MODE_BOTH == mode)
      {
        GNUNET_assert (-1 != fakebank);
        kill (fakebank,
              SIGTERM);
        waitpid (fakebank,
                 &wstatus,
                 0);
      }
      GNUNET_OS_process_destroy (exchanged);
      return 77;
    }
  }

  if (MODE_CLIENT == mode)
  {
    char *remote_cmd;

    GNUNET_asprintf (&remote_cmd,
                     ("cd '%s'; "
                      "taler-exchange-benchmark --mode=exchange -c '%s'"),
                     remote_dir,
                     config_file);

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "remote command: %s\n",
                remote_cmd);

    GNUNET_assert (NULL != (exchange_slave_pipe =
                              GNUNET_DISK_pipe (GNUNET_YES,
                                                GNUNET_YES,
                                                0, 0)));

    exchange_slave = GNUNET_OS_start_process (GNUNET_NO,
                                              GNUNET_OS_INHERIT_STD_OUT_AND_ERR,
                                              exchange_slave_pipe, NULL, NULL,
                                              "ssh",
                                              "ssh",
                                              /* Don't ask for pw/passphrase, rather fail */
                                              "-oBatchMode=yes",
                                              remote_host,
                                              remote_cmd,
                                              NULL);
    GNUNET_free (remote_cmd);
  }

  /* We always wait for the exchange, no matter if it's running locally or
     remotely */
  if (0 != TALER_TESTING_wait_exchange_ready (ec.exchange_url))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to detect running exchange at `%s'\n",
                ec.exchange_url);
    GNUNET_OS_process_kill (exchanged,
                            SIGTERM);
    if ( (MODE_BOTH == mode) || (MODE_CLIENT == mode))
    {
      GNUNET_assert (-1 != fakebank);
      kill (fakebank,
            SIGTERM);
      waitpid (fakebank,
               &wstatus,
               0);
    }
    GNUNET_OS_process_wait (exchanged);
    GNUNET_OS_process_destroy (exchanged);
    if (NULL != wirewatch)
    {
      GNUNET_OS_process_kill (wirewatch,
                              SIGTERM);
      GNUNET_OS_process_wait (wirewatch);
      GNUNET_OS_process_destroy (wirewatch);
    }
    return 77;
  }
  if ( (MODE_CLIENT == mode) || (MODE_BOTH == mode) )
  {
    sleep (1); /* make sure fakebank process is ready before continuing */

    start_time = GNUNET_TIME_absolute_get ();
    result = GNUNET_OK;
    for (unsigned int i = 0; i<howmany_clients; i++)
    {
      if (0 == (cpids[i] = fork ()))
      {
        /* I am the child, do the work! */
        GNUNET_log_setup ("benchmark-worker",
                          NULL == loglev ? "INFO" : loglev,
                          logfile);

        result = TALER_TESTING_setup
                   (main_cb,
                   main_cb_cls,
                   cfg_filename,
                   exchanged,
                   GNUNET_YES);
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

  /* Wait for our master to die or to tell us to die */
  if (MODE_EXCHANGE == mode)
    (void) getchar ();

  if ( (GNUNET_YES == linger) && ( ((mode == MODE_BOTH) || (mode ==
                                                            MODE_CLIENT) ) ) )
  {
    printf ("press ENTER to stop\n");
    (void) getchar ();
  }

  if (MODE_CLIENT == mode)
  {
    char c = 'q';

    GNUNET_assert (NULL != exchange_slave);

    /* Write a character to the pipe to end the exchange slave.
     * We can't send a signal here, as it would just kill SSH and
     * not necessarily the process on the other machine. */
    GNUNET_DISK_file_write (GNUNET_DISK_pipe_handle
                              (exchange_slave_pipe, GNUNET_DISK_PIPE_END_WRITE),
                            &c, sizeof (c));

    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (exchange_slave));
    GNUNET_OS_process_destroy (exchange_slave);
  }

  if ( (MODE_EXCHANGE == mode) || (MODE_BOTH == mode) )
  {
    GNUNET_assert (NULL != wirewatch);
    GNUNET_assert (NULL != exchanged);
    /* stop wirewatch */
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (wirewatch,
                                          SIGTERM));
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (wirewatch));
    GNUNET_OS_process_destroy (wirewatch);
    /* stop exchange */
    GNUNET_break (0 ==
                  GNUNET_OS_process_kill (exchanged,
                                          SIGTERM));
    GNUNET_break (GNUNET_OK ==
                  GNUNET_OS_process_wait (exchanged));
    GNUNET_OS_process_destroy (exchanged);
  }

  if ( (MODE_CLIENT == mode) || (MODE_BOTH == mode) )
  {
    /* stop fakebank */
    GNUNET_assert (-1 != fakebank);
    if (0 != kill (fakebank,
                   SIGTERM))
      GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                           "kill");
    waitpid (fakebank,
             &wstatus,
             0);
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
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_mandatory
      (GNUNET_GETOPT_option_cfgfile (&cfg_filename)),
    GNUNET_GETOPT_option_version (PACKAGE_VERSION " " VCS_VERSION),
    GNUNET_GETOPT_option_help ("Exchange benchmark"),
    GNUNET_GETOPT_option_loglevel (&loglev),
    GNUNET_GETOPT_option_uint ('n',
                               "coins-number",
                               "CN",
                               "How many coins we should instantiate per reserve",
                               &howmany_coins),
    GNUNET_GETOPT_option_uint ('p',
                               "parallelism",
                               "NPROCS",
                               "How many client processes we should run",
                               &howmany_clients),
    GNUNET_GETOPT_option_uint ('r',
                               "reserves",
                               "NRESERVES",
                               "How many reserves per client we should create",
                               &howmany_reserves),
    GNUNET_GETOPT_option_uint ('R',
                               "refresh-rate",
                               "RATE",
                               "Probability of refresh per coin (0-100)",
                               &refresh_rate),
    GNUNET_GETOPT_option_string ('m',
                                 "mode",
                                 "MODE",
                                 "run as exchange, clients or both",
                                 &mode_str),
    GNUNET_GETOPT_option_string ('l',
                                 "logfile",
                                 "LF",
                                 "will log to file LF",
                                 &logfile),
    GNUNET_GETOPT_option_flag ('K',
                               "linger",
                               "linger around until key press",
                               &linger),
    GNUNET_GETOPT_OPTION_END
  };

  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  if (0 >=
      (result = GNUNET_GETOPT_run ("taler-exchange-benchmark",
                                   options,
                                   argc,
                                   argv)))
  {
    return BAD_CLI_ARG;
  }
  GNUNET_log_setup ("taler-exchange-benchmark",
                    NULL == loglev ? "INFO" : loglev,
                    logfile);
  if (NULL == mode_str)
    mode = MODE_BOTH;
  else if (0 == strcmp (mode_str, "exchange"))
    mode = MODE_EXCHANGE;
  else if (0 == strcmp (mode_str, "client"))
    mode = MODE_CLIENT;
  else if (0 == strcmp (mode_str, "both"))
    mode = MODE_BOTH;
  else
  {
    TALER_LOG_ERROR ("Unknown mode given: '%s'\n", mode_str);
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
    return BAD_CONFIG_FILE;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "currency",
                                             &currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "currency");
    GNUNET_CONFIGURATION_destroy (cfg);
    return BAD_CONFIG_FILE;
  }
  if (howmany_clients > 10240)
  {
    TALER_LOG_ERROR ("-p option value given is too large\n");
    return BAD_CLI_ARG;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string
        (cfg,
        "benchmark",
        "user-url",
        &user_payto_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "benchmark",
                               "user-url");
    return BAD_CONFIG_FILE;
  }

  {
    const char *bank_details_section;

    GNUNET_CONFIGURATION_iterate_sections (cfg,
                                           &pick_exchange_account_cb,
                                           &bank_details_section);
    if (NULL == bank_details_section)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  _ (
                    "Missing specification of bank account in configuration\n"));
      return BAD_CONFIG_FILE;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string
          (cfg,
          bank_details_section,
          "url",
          &exchange_payto_url))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 bank_details_section,
                                 "url");
      return BAD_CONFIG_FILE;
    }

    if (TALER_EC_NONE !=
        TALER_WIRE_payto_to_account (exchange_payto_url,
                                     &exchange_bank_account))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  _ ("Malformed payto:// URL `%s' in configuration\n"),
                  exchange_payto_url);
      GNUNET_free (exchange_payto_url);
      return BAD_CONFIG_FILE;
    }
    if (TALER_PAC_X_TALER_BANK != exchange_bank_account.type)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  _ (
                    "Malformed payto:// URL `%s' in configuration: x-taler-bank required\n"),
                  exchange_payto_url);
      GNUNET_free (exchange_payto_url);
      return BAD_CONFIG_FILE;
    }
  }
  if ( (MODE_EXCHANGE == mode) || (MODE_BOTH == mode) )
  {
    struct GNUNET_OS_Process *compute_wire_response;

    compute_wire_response = GNUNET_OS_start_process
                              (GNUNET_NO,
                              GNUNET_OS_INHERIT_STD_ALL,
                              NULL, NULL, NULL,
                              "taler-exchange-wire",
                              "taler-exchange-wire",
                              "-c", cfg_filename,
                              NULL);
    if (NULL == compute_wire_response)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to run `taler-exchange-wire`,"
                  " is your PATH correct?\n");
      return GNUNET_NO;
    }
    GNUNET_OS_process_wait (compute_wire_response);
    GNUNET_OS_process_destroy (compute_wire_response);

    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_prepare_exchange (cfg_filename,
                                                   &ec));
  }
  else
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "BASE_URL",
                                               &ec.exchange_url))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "base_url");
      GNUNET_CONFIGURATION_destroy (cfg);
      return BAD_CONFIG_FILE;
    }

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "benchmark-remote-exchange",
                                               "host",
                                               &remote_host))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "benchmark-remote-exchange",
                                 "host");
      GNUNET_CONFIGURATION_destroy (cfg);
      return BAD_CONFIG_FILE;
    }

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "benchmark-remote-exchange",
                                               "dir",
                                               &remote_dir))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "benchmark-remote-exchange",
                                 "dir");
      GNUNET_CONFIGURATION_destroy (cfg);
      return BAD_CONFIG_FILE;
    }
  }
  GNUNET_CONFIGURATION_destroy (cfg);

  result = parallel_benchmark (&run,
                               NULL,
                               cfg_filename);

  /* If we're the exchange worker, we're done now.  No need to print results */
  if (MODE_EXCHANGE == mode)
    return (GNUNET_OK == result) ? 0 : result;

  duration = GNUNET_TIME_absolute_get_duration (start_time);
  if (GNUNET_OK == result)
  {
    struct rusage usage;
    GNUNET_assert (0 == getrusage (RUSAGE_CHILDREN, &usage));
    fprintf (stdout,
             "Executed (Withdraw=%u, Deposit=%u, Refresh~=%5.2f) * Reserve=%u * Parallel=%u, operations in %s\n",
             howmany_coins,
             howmany_coins,
             (float) howmany_coins * (refresh_rate / 100.0),
             howmany_reserves,
             howmany_clients,
             GNUNET_STRINGS_relative_time_to_string
               (duration,
               GNUNET_NO));
    fprintf (stdout,
             "(approximately %s/coin)\n",
             GNUNET_STRINGS_relative_time_to_string
               (GNUNET_TIME_relative_divide (duration,
                                             (unsigned long long) howmany_coins
                                             * howmany_reserves
                                             * howmany_clients),
               GNUNET_YES));
    fprintf (stdout,
             "RAW: %04u %04u %04u %16llu\n",
             howmany_coins,
             howmany_reserves,
             howmany_clients,
             (unsigned long long) duration.rel_value_us);
    fprintf (stdout, "cpu time: sys %llu user %llu\n", \
             (unsigned long long) (usage.ru_stime.tv_sec * 1000 * 1000
                                   + usage.ru_stime.tv_usec),
             (unsigned long long) (usage.ru_utime.tv_sec * 1000 * 1000
                                   + usage.ru_utime.tv_usec));
  }
  return (GNUNET_OK == result) ? 0 : result;
}
