/*
  This file is part of TALER
  Copyright (C) 2014--2019 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-wire.c
 * @brief Utility performing wire transfers.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_bank_service.h"

/**
 * If set to #GNUNET_YES, then we'll ask the bank for a list
 * of transactions from the account mentioned in the config
 * section.
 */
static int history;

/**
 * If set to #GNUNET_YES, then we'll ask the bank to execute a
 * wire transfer.
 */
static int transfer;

/**
 * Global return code.
 */
static unsigned int global_ret = 1;

/**
 * When a wire transfer is being performed, this value
 * specifies the amount to wire-transfer.  It's given in
 * the usual CURRENCY:X[.Y] format.
 */
static char *amount;

/**
 * Starting row.
 */
static unsigned long long start_row;

/**
 * Which config section has the credentials to access the bank.
 */
static char *account_section;

/**
 * URL identifying the account that is going to receive the
 * wire transfer.
 */
static char *destination_account_url;

/**
 * Handle for executing the wire transfer.
 */
static struct TALER_BANK_WireExecuteHandle *eh;

/**
 * Handle to ongoing history operation.
 */
static struct TALER_BANK_CreditHistoryHandle *hh;

/**
 * For authentication.
 */
static struct TALER_BANK_AuthenticationData auth;

/**
 * Handle to the context for interacting with the bank.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Scheduler context for running the @e ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;


/**
 * Callback used to process ONE entry in the transaction
 * history returned by the bank.
 *
 * @param cls closure
 * @param http_status HTTP status code from server
 * @param ec taler error code
 * @param serial_id identification of the position at
 *        which we are returning data
 * @param details details about the wire transfer
 * @param json original full response from server
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to
 *         abort iteration
 */
static int
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            uint64_t serial_id,
            const struct TALER_BANK_CreditDetails *details,
            const json_t *json)
{
  (void) cls;
  (void) ec;
  (void) http_status;
  if (NULL == details)
  {
    fprintf (stdout,
             "End of transactions list.\n");
    global_ret = 0;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_NO;
  }

  fprintf (stdout,
           "%llu\n",
           (unsigned long long) serial_id);
  return GNUNET_OK;
}


/**
 * Callback that processes the outcome of a wire transfer
 * execution.
 *
 * @param cls closure
 * @param response_code HTTP status code
 * @param ec taler error code
 * @param row_id unique ID of the wire transfer in the bank's records
 * @param timestamp when did the transaction go into effect
 */
static void
confirmation_cb (void *cls,
                 unsigned int response_code,
                 enum TALER_ErrorCode ec,
                 uint64_t row_id,
                 struct GNUNET_TIME_Absolute timestamp)
{
  if (MHD_HTTP_OK != response_code)
  {
    fprintf (stderr,
             "The wire transfer didn't execute correctly (%d).\n",
             ec);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  fprintf (stdout,
           "Wire transfer executed successfully.\n");
  global_ret = 0;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Ask the bank to execute a wire transfer.
 */
static void
execute_wire_transfer ()
{
  struct TALER_Amount a;
  struct TALER_WireTransferIdentifierRawP wtid;
  void *buf;
  size_t buf_size;

  if (NULL == amount)
  {
    fprintf (stderr,
             "The option -a: AMOUNT, is mandatory.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_OK != TALER_string_to_amount (amount,
                                           &a))
  {
    fprintf (stderr,
             "Amount string incorrect.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (NULL == destination_account_url)
  {
    fprintf (stderr,
             "Please give destination"
             " account URL (--destination/-d)\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  TALER_BANK_prepare_wire_transfer (destination_account_url,
                                    &a,
                                    "http://exchange.example.com/",
                                    &wtid,
                                    &buf,
                                    &buf_size);
  eh = TALER_BANK_execute_wire_transfer (ctx,
                                         &auth,
                                         buf,
                                         buf_size,
                                         &confirmation_cb,
                                         NULL);
  if (NULL == eh)
  {
    fprintf (stderr,
             "Could not execute the wire transfer\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Ask the bank the list of transactions for the bank account
 * mentioned in the config section given by the user.
 */
static void
execute_history ()
{
  hh = TALER_BANK_credit_history (ctx,
                                  destination_account_url,
                                  &auth,
                                  start_row,
                                  -10,
                                  &history_cb,
                                  NULL);
  if (NULL == hh)
  {
    fprintf (stderr,
             "Could not request the transaction history.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Gets executed upon shutdown.  Main duty is wire-plugin unloading.
 *
 * @param cls closure.
 */
static void
do_shutdown (void *cls)
{
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
  if (NULL != hh)
  {
    TALER_BANK_credit_history_cancel (hh);
    hh = NULL;
  }
  if (NULL != eh)
  {
    TALER_BANK_execute_wire_transfer_cancel (eh);
    eh = NULL;
  }
  TALER_BANK_auth_free (&auth);
}


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used
 *        (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  if (NULL == account_section)
  {
    fprintf (stderr,
             "The option: -s ACCOUNT-SECTION, is mandatory.\n");
    return;
  }
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (cfg,
                                 account_section,
                                 &auth))
  {
    fprintf (stderr,
             "Authentication information not found in configuration section `%s'\n",
             account_section);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }


  if (GNUNET_YES == history)
    execute_history ();
  else if (GNUNET_YES == transfer)
    execute_wire_transfer ();
  else
    fprintf (stderr,
             "Please give either --history/-H or --transfer/t\n");

  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    return;
  }
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
}


/**
 * Main function of taler-wire.  This tool is used to command the
 * execution of wire transfers from the command line.  Its main
 * purpose is to test whether the bank and exchange can speak the
 * same protocol of a certain wire plugin.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('H',
                               "history",
                               "Ask to get a list of 10 transactions.",
                               &history),
    GNUNET_GETOPT_option_flag ('t',
                               "transfer",
                               "Execute a wire transfer.",
                               &transfer),
    GNUNET_GETOPT_option_ulong ('w',
                                "since-when",
                                "SW",
                                "When asking the bank for"
                                " transactions history, this"
                                " option commands that all the"
                                " results should have IDs settled"
                                " after SW.  If not given, then"
                                " the 10 youngest transactions"
                                " are returned.",
                                &start_row),
    GNUNET_GETOPT_option_mandatory
      (GNUNET_GETOPT_option_string ('s',
                                    "section",
                                    "ACCOUNT-SECTION",
                                    "Which config section has the credentials to access the bank.  Mandatory.\n",
                                    &account_section)),
    GNUNET_GETOPT_option_string ('a',
                                 "amount",
                                 "AMOUNT",
                                 "Specify the amount to transfer.",
                                 &amount),
    GNUNET_GETOPT_option_string ('d',
                                 "destination",
                                 "PAYTO-URL",
                                 "Destination account for the wire transfer.",
                                 &destination_account_url),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  GNUNET_assert
    (GNUNET_OK == GNUNET_log_setup ("taler-wire",
                                    "WARNING",
                                    NULL)); /* filename */
  ret = GNUNET_PROGRAM_run
          (argc,
          argv,
          "taler-wire",
          "CLI bank client.",
          options,
          &run,
          NULL);
  if (GNUNET_OK != ret)
    return ret;
  return global_ret;
}


/* end of taler-wire.c */
