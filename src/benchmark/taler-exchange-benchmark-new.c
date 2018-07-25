/*
  This file is part of TALER
  (C) 2014-2018 Taler Systems SA

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
 * @file merchant/backend/taler-merchant-httpd.c
 * @brief HTTP serving layer intended to perform crypto-work and
 * communication with the exchange
 * @author Marcello Stanisci
 */

#include "platform.h"
#include <taler/taler_util.h>
#include <taler/taler_signatures.h>
#include <taler/taler_exchange_service.h>
#include <taler/taler_json_lib.h>
#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include <taler/taler_bank_service.h>
#include <taler/taler_fakebank_lib.h>
#include <taler/taler_testing_lib.h>
#include <taler/taler_testing_bank_lib.h>
#include <taler/taler_error_codes.h>

/* Error codes.  */
enum BenchmarkError {

  MISSING_BANK_URL,
  FAILED_TO_LAUNCH_BANK,
  BAD_CLI_ARG,
  BAD_CONFIG_FILE,
  NO_CONFIG_FILE_GIVEN
};

/**
 * Probability that a spent coin will be refreshed.
 */
#define REFRESH_PROBABILITY 0.1

/**
 * The whole benchmark is a repetition of a "unit".  Each
 * unit is a array containing a withdraw+deposit operation,
 * and _possibly_ a refresh of the deposited coin.
 */
#define UNITY_SIZE 6

/* Hard-coded params.  Note, the bank is expected to
 * have the Tor user with account number 3 and password 'x'.
 *
 * This is not a problem _so far_, as the fakebank mocks logins,
 * and the Python bank makes that account by default.  */
#define USER_ACCOUNT_NO 3
#define EXCHANGE_ACCOUNT_NO 2
#define USER_LOGIN_NAME "Tor"
#define USER_LOGIN_PASS "x"
#define EXCHANGE_URL "http://example.com/"

#define FIRST_INSTRUCTION -1

#define CMD_TRANSFER_TO_EXCHANGE(label,amount) \
   TALER_TESTING_cmd_fakebank_transfer (label, amount, \
     bank_url, USER_ACCOUNT_NO, EXCHANGE_ACCOUNT_NO, \
     USER_LOGIN_NAME, USER_LOGIN_PASS, EXCHANGE_URL)


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
static unsigned int result;

/**
 * Bank process.
 */
static struct GNUNET_OS_Process *bankd;

/**
 * How many refreshes got executed.
 */
static unsigned int howmany_refreshes;

/**
 * How many coins we want to create.
 */
static unsigned int howmany_coins = 1;

/**
 * Log level used during the run.
 */
static char *loglev;

/**
 * Log file.
 */
static char *logfile;

/**
 * Config filename.
 */
static char *cfg_filename;

/**
 * Bank base URL.
 */
static char *bank_url;

/**
 * Currency used.
 */
static char *currency;

/**
 * Convenience macros to allocate all the currency-dependant
 * strings;  note that the argument list of the macro is ignored.
 * It is kept as a way to make the macro more auto-descriptive
 * where it is called.
 */

#define ALLOCATE_AMOUNTS(...) \
  char *AMOUNT_5; \
  char *AMOUNT_4; \
  char *AMOUNT_1; \
  \
  GNUNET_asprintf (&AMOUNT_5, \
                   "%s:5", \
                   currency); \
  GNUNET_asprintf (&AMOUNT_4, \
                   "%s:4", \
                   currency); \
  GNUNET_asprintf (&AMOUNT_1, \
                   "%s:1", \
                   currency);

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
  #define APIKEY_SANDBOX "Authorization: ApiKey sandbox"
  struct TALER_Amount total_reserve_amount;
  struct TALER_Amount withdraw_fee;
  char *withdraw_fee_str;

  struct TALER_TESTING_Command all_commands
    [1 + /* Withdraw block */
     howmany_coins + /* All units */
     1 /* End CMD */];

  /* Will be freed by testing-lib.  */
  GNUNET_assert
    (GNUNET_OK == GNUNET_CURL_append_header
      (is->ctx, APIKEY_SANDBOX));

  ALLOCATE_AMOUNTS
    (AMOUNT_5,
     AMOUNT_4,
     AMOUNT_1);

  strcpy (total_reserve_amount.currency,
          currency);
  total_reserve_amount.value = 5 * howmany_coins;
  GNUNET_asprintf (&withdraw_fee_str,
                   "%s:0.1",
                   currency);
  TALER_string_to_amount (withdraw_fee_str,
                          &withdraw_fee);
  for (unsigned int i = 0; i < howmany_coins; i++)
    TALER_amount_add (&total_reserve_amount,
                      &total_reserve_amount,
                      &withdraw_fee);

  struct TALER_TESTING_Command make_reserve[] = {

    CMD_TRANSFER_TO_EXCHANGE
      ("create-reserve",
       TALER_amount_to_string (&total_reserve_amount)),

    TALER_TESTING_cmd_exec_wirewatch
      ("wirewatch",
       cfg_filename),

    TALER_TESTING_cmd_end ()

  };

  all_commands[0] = TALER_TESTING_cmd_batch ("make-reserve",
                                             make_reserve);
  for (unsigned int i = 0; i < howmany_coins; i++)
  {
    char *withdraw_label;
    char *order_enc;
    struct TALER_TESTING_Command unit[UNITY_SIZE];

    GNUNET_asprintf (&withdraw_label,
                     "withdraw-%u",
                     i);

    GNUNET_asprintf (&order_enc,
                     "{\"nonce\": %u}",
                     i);

    unit[0] = TALER_TESTING_cmd_withdraw_amount
      (withdraw_label,
       is->exchange,
       "create-reserve",
       AMOUNT_5,
       MHD_HTTP_OK);

    unit[1] = TALER_TESTING_cmd_deposit
      ("deposit",
       is->exchange,
       withdraw_label,
       0, /* Index of the one withdrawn coin in the traits.  */
       TALER_TESTING_make_wire_details
         (24,
          "no-aggregation"),
       order_enc,
       GNUNET_TIME_UNIT_ZERO,
       AMOUNT_1,
       MHD_HTTP_OK);

    if (eval_probability (REFRESH_PROBABILITY))
    {
      char *melt_label;
      char *reveal_label;

      howmany_refreshes++;
      GNUNET_asprintf (&melt_label,
                       "refresh-melt-%u",
                       i);

      GNUNET_asprintf (&reveal_label,
                       "refresh-reveal-%u",
                       i);

      unit[2] = TALER_TESTING_cmd_refresh_melt
        (melt_label,
         is->exchange,
         AMOUNT_4,
         withdraw_label,
         MHD_HTTP_OK);

      unit[3] = TALER_TESTING_cmd_refresh_reveal
        (reveal_label,
         is->exchange,
         melt_label,
         MHD_HTTP_OK);

      unit[4] = TALER_TESTING_cmd_refresh_link
        ("refresh-link",
         is->exchange,
         reveal_label,
         MHD_HTTP_OK);

      unit[5] = TALER_TESTING_cmd_end ();
    }
    else unit[2] = TALER_TESTING_cmd_end ();
    
    all_commands[1 + i] = TALER_TESTING_cmd_batch ("unit",
                                                   unit);
  }
  all_commands[1 + howmany_coins] = TALER_TESTING_cmd_end ();

  start_time = GNUNET_TIME_absolute_get ();
  TALER_TESTING_run (is,
                     all_commands);
  result = 1;
}

/**
 * Send SIGTERM and wait for process termination.
 *
 * @param process process to terminate.
 */
void
terminate_process (struct GNUNET_OS_Process *process)
{
  GNUNET_OS_process_kill (process, SIGTERM);
  GNUNET_OS_process_wait (process);
  GNUNET_OS_process_destroy (process);
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

  loglev = NULL;
  GNUNET_log_setup ("taler-exchange-benchmark",
                    loglev,
                    logfile);

  struct GNUNET_GETOPT_CommandLineOption options[] = {

    GNUNET_GETOPT_option_cfgfile
      (&cfg_filename),

    GNUNET_GETOPT_option_version
      (PACKAGE_VERSION " " VCS_VERSION),

    GNUNET_GETOPT_option_help
      ("Exchange benchmark"),

    GNUNET_GETOPT_option_loglevel
      (&loglev),

    GNUNET_GETOPT_option_uint
      ('n',
       "coins-number",
       "CN",
       "How many coins we should instantiate",
       &howmany_coins),

    GNUNET_GETOPT_option_string
      ('b',
       "bank-url",
       "BU",
       "bank base url, mandatory",
       &bank_url),

    GNUNET_GETOPT_option_string
      ('l',
       "logfile",
       "LF",
       "will log to file LF",
       &logfile),

    GNUNET_GETOPT_OPTION_END
  };
  
  if (GNUNET_SYSERR == (result = GNUNET_GETOPT_run
      ("taler-exchange-benchmark",
       options,
       argc,
       argv))) 
  {
    TALER_LOG_ERROR ("Unparsable CLI options\n");
    return BAD_CLI_ARG;
  }

  if (NULL == cfg_filename)
  {
    TALER_LOG_ERROR ("-c option is mandatory\n");
    return NO_CONFIG_FILE_GIVEN;
  }

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK != GNUNET_CONFIGURATION_load
      (cfg,
       cfg_filename))
  {
    TALER_LOG_ERROR ("Could not parse configuration\n");
    return BAD_CONFIG_FILE;
  }
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_string
      (cfg,
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
  GNUNET_CONFIGURATION_destroy (cfg);

  if (NULL == bank_url)
  {
    TALER_LOG_ERROR ("Option -b is mandatory!\n");
    return MISSING_BANK_URL;
  }

  if (NULL == (bankd = TALER_TESTING_run_bank
    (cfg_filename,
     bank_url)))
  {
    TALER_LOG_ERROR ("Failed to run the bank\n");
    return FAILED_TO_LAUNCH_BANK;
  }

  result = TALER_TESTING_setup_with_exchange
    (run,
     NULL,
     cfg_filename);

  duration = GNUNET_TIME_absolute_get_duration (start_time);
  terminate_process (bankd);

  TALER_LOG_INFO ("Executed W=%u, D=%u, R=%u, operations in %s\n",
                  howmany_coins,
                  howmany_coins,
                  howmany_refreshes,
                  GNUNET_STRINGS_relative_time_to_string
                    (duration,
                     GNUNET_YES));

  return (GNUNET_OK == result) ? 0 : result;
}
