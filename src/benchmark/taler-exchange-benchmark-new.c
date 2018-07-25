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
 * Exit code.
 */
static unsigned int result;

/**
 * Bank process.
 */
static struct GNUNET_OS_Process *bankd;

/**
 * How many coins we want to create.
 */
static unsigned int howmany_coins;

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
  char *CURRENCY_10_02; \
  char *CURRENCY_10; \
  char *CURRENCY_9_98; \
  char *CURRENCY_5_01; \
  char *CURRENCY_5; \
  char *CURRENCY_4_99; \
  char *CURRENCY_0_02; \
  char *CURRENCY_0_01; \
  \
  GNUNET_asprintf (&CURRENCY_10_02, \
                   "%s:10.02", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_10, \
                   "%s:10", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_9_98, \
                   "%s:9.98", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_5_01, \
                   "%s:5.01", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_5, \
                   "%s:5", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_4_99, \
                   "%s:4.99", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_0_02, \
                   "%s:0.02", \
                   currency); \
  GNUNET_asprintf (&CURRENCY_0_01, \
                   "%s:0.01", \
                   currency);

#define ALLOCATE_ORDERS(...) \
  char *order_worth_5; \
  char *order_worth_5_track; \
  char *order_worth_5_unaggregated; \
  char *order_worth_10_2coins; \
  \
  GNUNET_asprintf \
    (&order_worth_5, \
     "{\"max_fee\":\
       {\"currency\":\"%s\",\
        \"value\":0,\
        \"fraction\":50000000},\
       \"refund_deadline\":\"\\/Date(0)\\/\",\
       \"pay_deadline\":\"\\/Date(99999999999)\\/\",\
       \"amount\":\
         {\"currency\":\"%s\",\
          \"value\":5,\
          \"fraction\":0},\
        \"summary\": \"merchant-lib testcase\",\
        \"fulfillment_url\": \"https://example.com/\",\
        \"products\": [ {\"description\":\"ice cream\",\
                         \"value\":\"{%s:5}\"} ] }", \
     currency, \
     currency, \
     currency); \
  GNUNET_asprintf \
    (&order_worth_5_track, \
     "{\"max_fee\":\
       {\"currency\":\"%s\",\
        \"value\":0,\
        \"fraction\":50000000},\
       \"refund_deadline\":\"\\/Date(0)\\/\",\
       \"pay_deadline\":\"\\/Date(99999999999)\\/\",\
       \"amount\":\
         {\"currency\":\"%s\",\
          \"value\":5,\
          \"fraction\":0},\
        \"summary\": \"ice track cream!\",\
        \"fulfillment_url\": \"https://example.com/\",\
        \"products\": [ {\"description\":\"ice track cream\",\
                         \"value\":\"{%s:5}\"} ] }", \
     currency, \
     currency, \
     currency); \
  GNUNET_asprintf \
    (&order_worth_5_unaggregated, \
     "{\"max_fee\":\
       {\"currency\":\"%s\",\
        \"value\":0,\
        \"fraction\":50000000},\
       \"wire_transfer_delay\":\"\\/Delay(30000)\\/\",\
       \"refund_deadline\":\"\\/Date(22)\\/\",\
       \"pay_deadline\":\"\\/Date(1)\\/\",\
       \"amount\":\
         {\"currency\":\"%s\",\
          \"value\":5,\
          \"fraction\":0},\
        \"summary\": \"unaggregated deposit!\",\
        \"fulfillment_url\": \"https://example.com/\",\
        \"products\": [ {\"description\":\"unaggregated cream\",\
                         \"value\":\"{%s:5}\"} ] }", \
     currency, \
     currency, \
     currency); \
  GNUNET_asprintf \
    (&order_worth_10_2coins, \
     "{\"max_fee\":\
       {\"currency\":\"%s\",\
        \"value\":0,\
        \"fraction\":50000000},\
       \"refund_deadline\":\"\\/Date(0)\\/\",\
       \"pay_deadline\":\"\\/Date(99999999999)\\/\",\
       \"amount\":\
         {\"currency\":\"%s\",\
          \"value\":10,\
          \"fraction\":0},\
        \"summary\": \"2-coins payment\",\
        \"fulfillment_url\": \"https://example.com/\",\
        \"products\": [ {\"description\":\"2-coins payment\",\
                         \"value\":\"{%s:10}\"} ] }", \
     currency, \
     currency, \
     currency);


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

  #define APIKEY_SANDBOX "Authorization: ApiKey sandbox"

  /* Will be freed by testing-lib.  */
  GNUNET_assert
    (GNUNET_OK == GNUNET_CURL_append_header
      (is->ctx, APIKEY_SANDBOX));

  ALLOCATE_AMOUNTS
      (CURRENCY_10_02,
       CURRENCY_9_98,
       CURRENCY_5_01,
       CURRENCY_5,
       CURRENCY_4_99,
       CURRENCY_0_02,
       CURRENCY_0_01);

  ALLOCATE_ORDERS
    (order_worth_5,
     order_worth_5_track,
     order_worth_5_unaggregated,
     order_worth_10_2coins);

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

  /* 1st, calculate how much money should be held in
   * reserve.  Being all 5-valued coins, the overall
   * value should be: 5 times `howmany_coins' */

  struct TALER_TESTING_Command commands[] = {

    CMD_TRANSFER_TO_EXCHANGE
      ("create-reserve-1",
       CURRENCY_10_02),

    TALER_TESTING_cmd_exec_wirewatch
      ("wirewatch-1",
       cfg_filename),

    TALER_TESTING_cmd_withdraw_amount
      ("withdraw-coin-1",
       is->exchange, // picks port from config's [exchange].
       "create-reserve-1",
       CURRENCY_5,
       MHD_HTTP_OK),

    TALER_TESTING_cmd_withdraw_amount
      ("withdraw-coin-2",
       is->exchange,
       "create-reserve-1",
       CURRENCY_5,
       MHD_HTTP_OK),

    TALER_TESTING_cmd_end ()
  };

  #if 0
  TALER_TESTING_run (is,
                     commands);
  #endif
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

  terminate_process (bankd);

  return (GNUNET_OK == result) ? 0 : result;
}
