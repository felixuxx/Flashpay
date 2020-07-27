/*
  This file is part of TALER
  Copyright (C) 2017-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-bank-transfer.c
 * @brief Execute wire transfer.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include "taler_bank_service.h"

/**
 * If set to #GNUNET_YES, then we'll ask the bank for a list
 * of incoming transactions from the account.
 */
static int incoming_history;

/**
 * If set to #GNUNET_YES, then we'll ask the bank for a list
 * of outgoing transactions from the account.
 */
static int outgoing_history;

/**
 * Amount to transfer.
 */
static struct TALER_Amount amount;

/**
 * Credit account payto://-URI.
 */
static char *credit_account;

/**
 * Debit account payto://-URI.
 */
static char *debit_account;

/**
 * Wire transfer subject.
 */
static char *subject;

/**
 * Which config section has the credentials to access the bank.
 */
static char *account_section;

/**
 * Starting row.
 */
static unsigned long long start_row;

/**
 * Authentication data.
 */
static struct TALER_BANK_AuthenticationData auth;

/**
 * Return value from main().
 */
static int global_ret = 1;

/**
 * Main execution context for the main loop.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Handle to ongoing credit history operation.
 */
static struct TALER_BANK_CreditHistoryHandle *chh;

/**
 * Handle to ongoing debit history operation.
 */
static struct TALER_BANK_DebitHistoryHandle *dhh;

/**
 * Handle for executing the wire transfer.
 */
static struct TALER_BANK_TransferHandle *eh;

/**
 * Handle to access the exchange.
 */
static struct TALER_BANK_AdminAddIncomingHandle *op;

/**
 * Context for running the CURL event loop.
 */
static struct GNUNET_CURL_RescheduleContext *rc;


/**
 * Function run when the test terminates (good or bad).
 * Cleans up our state.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  if (NULL != op)
  {
    TALER_BANK_admin_add_incoming_cancel (op);
    op = NULL;
  }
  if (NULL != chh)
  {
    TALER_BANK_credit_history_cancel (chh);
    chh = NULL;
  }
  if (NULL != dhh)
  {
    TALER_BANK_debit_history_cancel (dhh);
    dhh = NULL;
  }
  if ( (NULL != eh) && (0 != global_ret))
  {
    TALER_BANK_transfer_cancel (eh);
    eh = NULL;
  }
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
  TALER_BANK_auth_free (&auth);
}


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
credit_history_cb (void *cls,
                   unsigned int http_status,
                   enum TALER_ErrorCode ec,
                   uint64_t serial_id,
                   const struct TALER_BANK_CreditDetails *details,
                   const json_t *json)
{
  (void) cls;

  if (MHD_HTTP_OK != http_status)
  {
    if ( (MHD_HTTP_NO_CONTENT != http_status) ||
         (TALER_EC_NONE != ec) ||
         (NULL == details) )
    {
      fprintf (stderr,
               "Failed to obtain credit history: %u/%d\n",
               http_status,
               ec);
      if (NULL != json)
        json_dumpf (json,
                    stderr,
                    JSON_INDENT (2));
      global_ret = 2;
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_NO;
    }
    fprintf (stdout,
             "End of transactions list.\n");
    global_ret = 0;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_NO;
  }

  /* If credit/debit accounts were specified, use as a filter */
  if ( (NULL != credit_account) &&
       (0 != strcasecmp (credit_account,
                         details->credit_account_url) ) )
    return GNUNET_OK;
  if ( (NULL != debit_account) &&
       (0 != strcasecmp (debit_account,
                         details->debit_account_url) ) )
    return GNUNET_OK;

  fprintf (stdout,
           "%llu: %s->%s (%s) over %s at %s\n",
           (unsigned long long) serial_id,
           details->debit_account_url,
           details->credit_account_url,
           TALER_B2S (&details->reserve_pub),
           TALER_amount2s (&details->amount),
           GNUNET_STRINGS_absolute_time_to_string (details->execution_date));
  return GNUNET_OK;
}


/**
 * Ask the bank the list of transactions for the bank account
 * mentioned in the config section given by the user.
 */
static void
execute_credit_history ()
{
  if (NULL != subject)
  {
    fprintf (stderr,
             "Specifying subject is not supported when inspecting credit history\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  chh = TALER_BANK_credit_history (ctx,
                                   &auth,
                                   start_row,
                                   -10,
                                   &credit_history_cb,
                                   NULL);
  if (NULL == chh)
  {
    fprintf (stderr,
             "Could not request the credit transaction history.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Function with the debit debit transaction history.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param ec detailed error code
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
debit_history_cb (void *cls,
                  unsigned int http_status,
                  enum TALER_ErrorCode ec,
                  uint64_t serial_id,
                  const struct TALER_BANK_DebitDetails *details,
                  const json_t *json)
{
  (void) cls;

  if (MHD_HTTP_OK != http_status)
  {
    if ( (MHD_HTTP_NO_CONTENT != http_status) ||
         (TALER_EC_NONE != ec) ||
         (NULL == details) )
    {
      fprintf (stderr,
               "Failed to obtain debit history: %u/%d\n",
               http_status,
               ec);
      if (NULL != json)
        json_dumpf (json,
                    stderr,
                    JSON_INDENT (2));
      global_ret = 2;
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_NO;
    }
    fprintf (stdout,
             "End of transactions list.\n");
    global_ret = 0;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_NO;
  }

  /* If credit/debit accounts were specified, use as a filter */
  if ( (NULL != credit_account) &&
       (0 != strcasecmp (credit_account,
                         details->credit_account_url) ) )
    return GNUNET_OK;
  if ( (NULL != debit_account) &&
       (0 != strcasecmp (debit_account,
                         details->debit_account_url) ) )
    return GNUNET_OK;

  fprintf (stdout,
           "%llu: %s->%s (%s) over %s at %s\n",
           (unsigned long long) serial_id,
           details->debit_account_url,
           details->credit_account_url,
           TALER_B2S (&details->wtid),
           TALER_amount2s (&details->amount),
           GNUNET_STRINGS_absolute_time_to_string (details->execution_date));
  return GNUNET_OK;
}


/**
 * Ask the bank the list of transactions for the bank account
 * mentioned in the config section given by the user.
 */
static void
execute_debit_history ()
{
  if (NULL != subject)
  {
    fprintf (stderr,
             "Specifying subject is not supported when inspecting debit history\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  dhh = TALER_BANK_debit_history (ctx,
                                  &auth,
                                  start_row,
                                  -10,
                                  &debit_history_cb,
                                  NULL);
  if (NULL == dhh)
  {
    fprintf (stderr,
             "Could not request the debit transaction history.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  (void) cls;
  if (MHD_HTTP_OK != response_code)
  {
    fprintf (stderr,
             "The wire transfer didn't execute correctly (%u/%d).\n",
             response_code,
             ec);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  fprintf (stdout,
           "Wire transfer #%llu executed successfully at %s.\n",
           (unsigned long long) row_id,
           GNUNET_STRINGS_absolute_time_to_string (timestamp));
  global_ret = 0;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Ask the bank to execute a wire transfer.
 */
static void
execute_wire_transfer ()
{
  struct TALER_WireTransferIdentifierRawP wtid;
  void *buf;
  size_t buf_size;

  if (NULL != debit_account)
  {
    fprintf (stderr,
             "Invalid option -C specified, conflicts with -D\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  // See if subject was given as a payto-parameter.
  if (NULL == subject)
    subject = TALER_payto_get_subject (credit_account);
  if (NULL != subject)
  {
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (subject,
                                       strlen (subject),
                                       &wtid,
                                       sizeof (wtid)))
    {
      fprintf (stderr,
               "Error: wire transfer subject must be a WTID\n");
      return;
    }
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  else
  {
    /* pick one at random */
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &wtid,
                                sizeof (wtid));
  }
  TALER_BANK_prepare_transfer (credit_account,
                               &amount,
                               "http://exchange.example.com/",
                               &wtid,
                               &buf,
                               &buf_size);
  eh = TALER_BANK_transfer (ctx,
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
 * Function called with the result of the operation.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol)
 * @param ec detailed error code
 * @param serial_id unique ID of the wire transfer in the bank's records; UINT64_MAX on error
 * @param timestamp timestamp when the transaction got settled at the bank.
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
static void
res_cb (void *cls,
        unsigned int http_status,
        enum TALER_ErrorCode ec,
        uint64_t serial_id,
        struct GNUNET_TIME_Absolute timestamp,
        const json_t *json)
{
  (void) cls;
  (void) timestamp;
  op = NULL;
  switch (ec)
  {
  case TALER_EC_NONE:
    global_ret = 0;
    fprintf (stdout,
             "%llu\n",
             (unsigned long long) serial_id);
    break;
  default:
    fprintf (stderr,
             "Operation failed with status code %u/%u\n",
             (unsigned int) ec,
             http_status);
    if (NULL != json)
      json_dumpf (json,
                  stderr,
                  JSON_INDENT (2));
    break;
  }
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Ask the bank to execute a wire transfer to the exchange.
 */
static void
execute_admin_transfer ()
{
  struct TALER_ReservePublicKeyP reserve_pub;

  if (NULL != subject)
  {
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (subject,
                                       strlen (subject),
                                       &reserve_pub,
                                       sizeof (reserve_pub)))
    {
      fprintf (stderr,
               "Error: wire transfer subject must be a reserve public key\n");
      return;
    }
  }
  else
  {
    /* pick one that is kind-of well-formed at random */
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &reserve_pub,
                                sizeof (reserve_pub));
  }
  op = TALER_BANK_admin_add_incoming (ctx,
                                      &auth,
                                      &reserve_pub,
                                      &amount,
                                      credit_account,
                                      &res_cb,
                                      NULL);
  if (NULL == op)
  {
    fprintf (stderr,
             "Could not execute the wire transfer to the exchange\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  (void) cls;
  (void) args;
  (void) cfgfile;
  (void) cfg;

  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  GNUNET_assert (NULL != ctx);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL != account_section)
  {
    if ( (NULL != auth.wire_gateway_url) ||
         (NULL != auth.details.basic.username) ||
         (NULL != auth.details.basic.password) )
    {
      fprintf (stderr,
               "Conflicting authentication options provided. Please only use one method.\n");
      GNUNET_SCHEDULER_shutdown ();
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
  }
  else
  {
    if ( (NULL != auth.wire_gateway_url) &&
         (NULL != auth.details.basic.username) &&
         (NULL != auth.details.basic.password) )
    {
      auth.method = TALER_BANK_AUTH_BASIC;
    }
    else if (NULL == auth.wire_gateway_url)
    {
      fprintf (stderr,
               "No account specified (use -b or -s options).\n");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  if ( (GNUNET_YES == incoming_history) &&
       (GNUNET_YES == incoming_history) )
  {
    fprintf (stderr,
             "Please specify only -i or -o, but not both.\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_YES == incoming_history)
  {
    execute_credit_history ();
    return;
  }
  if (GNUNET_YES == outgoing_history)
  {
    execute_debit_history ();
    return;
  }
  if (NULL != credit_account)
  {
    execute_wire_transfer ();
    return;
  }
  if (NULL != debit_account)
  {
    execute_admin_transfer ();
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "No operation specified.\n");
  global_ret = 0;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * The main function of the taler-bank-transfer tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    TALER_getopt_get_amount ('a',
                             "amount",
                             "VALUE",
                             "value to transfer",
                             &amount),
    GNUNET_GETOPT_option_string ('b',
                                 "bank",
                                 "URL",
                                 "Wire gateway URL to use to talk to the bank",
                                 &auth.wire_gateway_url),
    GNUNET_GETOPT_option_help ("Deposit funds into a Taler reserve"),
    GNUNET_GETOPT_option_string ('C',
                                 "credit",
                                 "ACCOUNT",
                                 "payto URI of the bank account to credit (when making outgoing transfers)",
                                 &credit_account),
    GNUNET_GETOPT_option_string ('D',
                                 "debit",
                                 "PAYTO-URL",
                                 "payto URI of the bank account to debit (when making incoming transfers)",
                                 &debit_account),
    GNUNET_GETOPT_option_flag ('i',
                               "credit-history",
                               "Ask to get a list of 10 incoming transactions.",
                               &incoming_history),
    GNUNET_GETOPT_option_flag ('o',
                               "debit-history",
                               "Ask to get a list of 10 outgoing transactions.",
                               &outgoing_history),
    GNUNET_GETOPT_option_string ('p',
                                 "pass",
                                 "PASSPHRASE",
                                 "passphrase to use for authentication",
                                 &auth.details.basic.password),
    GNUNET_GETOPT_option_string ('s',
                                 "section",
                                 "ACCOUNT-SECTION",
                                 "Which config section has the credentials to access the bank. Conflicts with -b -u and -p options.\n",
                                 &account_section),
    GNUNET_GETOPT_option_string ('S',
                                 "subject",
                                 "SUBJECT",
                                 "specifies the wire transfer subject",
                                 &subject),
    GNUNET_GETOPT_option_string ('u',
                                 "user",
                                 "USERNAME",
                                 "username to use for authentication",
                                 &auth.details.basic.username),
    GNUNET_GETOPT_option_ulong ('w',
                                "since-when",
                                "ROW",
                                "When asking the bank for transactions history, this option commands that all the results should have IDs settled after SW.  If not given, then the 10 youngest transactions are returned.",
                                &start_row),
    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-bank-transfer",
                                   "WARNING",
                                   NULL));
  global_ret = 1;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-bank-transfer",
                          "Execute bank transfer to the exchange",
                          options,
                          &run, NULL))
    return 1;
  return global_ret;
}


/* end taler-bank-transfer.c */
