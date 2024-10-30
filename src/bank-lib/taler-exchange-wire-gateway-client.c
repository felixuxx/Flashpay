/*
  This file is part of TALER
  Copyright (C) 2017-2023 Taler Systems SA

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
 * @file taler-exchange-wire-gateway-client.c
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
static unsigned long long start_row = UINT64_MAX;

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
  if (NULL != eh)
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
 * Callback used to process the transaction
 * history returned by the bank.
 *
 * @param cls closure
 * @param reply response we got from the bank
 */
static void
credit_history_cb (void *cls,
                   const struct TALER_BANK_CreditHistoryResponse *reply)
{
  (void) cls;

  chh = NULL;
  switch (reply->http_status)
  {
  case 0:
    fprintf (stderr,
             "Failed to obtain HTTP reply from `%s'\n",
             auth.wire_gateway_url);
    global_ret = 2;
    break;
  case MHD_HTTP_NO_CONTENT:
    fprintf (stdout,
             "No transactions.\n");
    global_ret = 0;
    break;
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<reply->details.ok.details_length; i++)
    {
      const struct TALER_BANK_CreditDetails *cd =
        &reply->details.ok.details[i];

      /* If credit/debit accounts were specified, use as a filter */
      if ( (NULL != credit_account) &&
           (0 != strcasecmp (credit_account,
                             reply->details.ok.credit_account_uri) ) )
        continue;
      if ( (NULL != debit_account) &&
           (0 != strcasecmp (debit_account,
                             cd->debit_account_uri) ) )
        continue;
      switch (cd->type)
      {
      case TALER_BANK_CT_RESERVE:
        fprintf (stdout,
                 "%llu: %s->%s (%s) over %s at %s\n",
                 (unsigned long long) cd->serial_id,
                 cd->debit_account_uri,
                 reply->details.ok.credit_account_uri,
                 TALER_B2S (&cd->details.reserve.reserve_pub),
                 TALER_amount2s (&cd->amount),
                 GNUNET_TIME_timestamp2s (cd->execution_date));
        break;
      case TALER_BANK_CT_KYCAUTH:
        fprintf (stdout,
                 "%llu: %s->%s (KYC:%s) over %s at %s\n",
                 (unsigned long long) cd->serial_id,
                 cd->debit_account_uri,
                 reply->details.ok.credit_account_uri,
                 TALER_B2S (&cd->details.kycauth.account_pub),
                 TALER_amount2s (&cd->amount),
                 GNUNET_TIME_timestamp2s (cd->execution_date));
        break;
      case TALER_BANK_CT_WAD:
        GNUNET_break (0); // FIXME
        break;
      }
    }
    global_ret = 0;
    break;
  default:
    fprintf (stderr,
             "Failed to obtain credit history from `%s': HTTP status %u (%s)\n",
             auth.wire_gateway_url,
             reply->http_status,
             TALER_ErrorCode_get_hint (reply->ec));
    if (NULL != reply->response)
      json_dumpf (reply->response,
                  stderr,
                  JSON_INDENT (2));
    global_ret = 2;
    break;
  }
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Ask the bank the list of transactions for the bank account
 * mentioned in the config section given by the user.
 */
static void
execute_credit_history (void)
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
                                   GNUNET_TIME_UNIT_ZERO,
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
 * Function with the debit transaction history.
 *
 * @param cls closure
 * @param reply response details
 */
static void
debit_history_cb (void *cls,
                  const struct TALER_BANK_DebitHistoryResponse *reply)
{
  (void) cls;

  dhh = NULL;
  switch (reply->http_status)
  {
  case 0:
    fprintf (stderr,
             "Failed to obtain HTTP reply from `%s'\n",
             auth.wire_gateway_url);
    global_ret = 2;
    break;
  case MHD_HTTP_NO_CONTENT:
    fprintf (stdout,
             "No transactions.\n");
    global_ret = 0;
    break;
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<reply->details.ok.details_length; i++)
    {
      const struct TALER_BANK_DebitDetails *dd =
        &reply->details.ok.details[i];

      /* If credit/debit accounts were specified, use as a filter */
      if ( (NULL != credit_account) &&
           (0 != strcasecmp (credit_account,
                             dd->credit_account_uri) ) )
        continue;
      if ( (NULL != debit_account) &&
           (0 != strcasecmp (debit_account,
                             reply->details.ok.debit_account_uri) ) )
        continue;
      fprintf (stdout,
               "%llu: %s->%s (%s) over %s at %s\n",
               (unsigned long long) dd->serial_id,
               reply->details.ok.debit_account_uri,
               dd->credit_account_uri,
               TALER_B2S (&dd->wtid),
               TALER_amount2s (&dd->amount),
               GNUNET_TIME_timestamp2s (dd->execution_date));
    }
    global_ret = 0;
    break;
  default:
    fprintf (stderr,
             "Failed to obtain debit history from `%s': HTTP status %u (%s)\n",
             auth.wire_gateway_url,
             reply->http_status,
             TALER_ErrorCode_get_hint (reply->ec));
    if (NULL != reply->response)
      json_dumpf (reply->response,
                  stderr,
                  JSON_INDENT (2));
    global_ret = 2;
    break;
  }
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Ask the bank the list of transactions for the bank account
 * mentioned in the config section given by the user.
 */
static void
execute_debit_history (void)
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
                                  GNUNET_TIME_UNIT_ZERO,
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
 * @param tr response details
 */
static void
confirmation_cb (void *cls,
                 const struct TALER_BANK_TransferResponse *tr)
{
  (void) cls;
  eh = NULL;
  if (MHD_HTTP_OK != tr->http_status)
  {
    fprintf (stderr,
             "The wire transfer didn't execute correctly (%u/%d).\n",
             tr->http_status,
             tr->ec);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  fprintf (stdout,
           "Wire transfer #%llu executed successfully at %s.\n",
           (unsigned long long) tr->details.ok.row_id,
           GNUNET_TIME_timestamp2s (tr->details.ok.timestamp));
  global_ret = 0;
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Ask the bank to execute a wire transfer.
 */
static void
execute_wire_transfer (void)
{
  struct TALER_WireTransferIdentifierRawP wtid;
  void *buf;
  size_t buf_size;
  char *params;

  if (NULL != debit_account)
  {
    fprintf (stderr,
             "Invalid option -C specified, conflicts with -D\n");
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  /* See if subject was given as a payto-parameter. */
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
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  else
  {
    /* pick one at random */
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &wtid,
                                sizeof (wtid));
  }
  params = strchr (credit_account,
                   (unsigned char) '&');
  if (NULL != params)
    *params = '\0';
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
  GNUNET_free (buf);
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
 * @param air response details
 */
static void
res_cb (void *cls,
        const struct TALER_BANK_AdminAddIncomingResponse *air)
{
  (void) cls;
  op = NULL;
  switch (air->http_status)
  {
  case MHD_HTTP_OK:
    global_ret = 0;
    fprintf (stdout,
             "%llu\n",
             (unsigned long long) air->details.ok.serial_id);
    break;
  default:
    fprintf (stderr,
             "Operation failed with status code %u/%u\n",
             (unsigned int) air->ec,
             air->http_status);
    if (NULL != air->response)
      json_dumpf (air->response,
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
execute_admin_transfer (void)
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
                                      debit_account,
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
    if (0 != strncasecmp ("exchange-accountcredentials-",
                          account_section,
                          strlen ("exchange-accountcredentials-")))
    {
      fprintf (stderr,
               "Error: invalid section specified, must begin with `%s`\n",
               "exchange-accountcredentials-");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    if ( (NULL != auth.wire_gateway_url) ||
         (NULL != auth.details.basic.username) ||
         (NULL != auth.details.basic.password) )
    {
      fprintf (stderr,
               "Error: Conflicting authentication options provided. Please only use one method.\n");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    if (GNUNET_OK !=
        TALER_BANK_auth_parse_cfg (cfg,
                                   account_section,
                                   &auth))
    {
      fprintf (stderr,
               "Error: Authentication information not found in configuration section `%s'\n",
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
    else if ( (NULL != auth.wire_gateway_url) &&
              (NULL != auth.details.bearer.token) )
    {
      auth.method = TALER_BANK_AUTH_BEARER;
    }

    else if (NULL == auth.wire_gateway_url)
    {
      fprintf (stderr,
               "Error: No account specified (use -b or -s options).\n");
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
  }
  if ( (NULL == auth.wire_gateway_url) ||
       (0 == strlen (auth.wire_gateway_url)) ||
       (0 != strncasecmp ("http",
                          auth.wire_gateway_url,
                          strlen ("http"))) )
  {
    fprintf (stderr,
             "Error: Invalid wire gateway URL `%s' configured.\n",
             auth.wire_gateway_url);
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if ( (GNUNET_YES == incoming_history) &&
       (GNUNET_YES == outgoing_history) )
  {
    fprintf (stderr,
             "Error: Please specify only -i or -o, but not both.\n");
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
 * The main function of the taler-exchange-wire-gateway-client
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
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  global_ret = 1;
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-wire-gateway-client",
    gettext_noop ("Client tool of the Taler Wire Gateway"),
    options,
    &run, NULL);
  if (GNUNET_SYSERR == ret)
    return 3;
  if (GNUNET_NO == ret)
    return 0;
  return global_ret;
}


/* end taler-wire-gateway-client.c */
