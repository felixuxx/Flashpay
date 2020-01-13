/*
  This file is part of TALER
  Copyright (C) 2016, 2017, 2018 Taler Systems SA

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
 * @file taler-exchange-wirewatch.c
 * @brief Process that watches for wire transfers to the exchange's bank account
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include <microhttpd.h>
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"

/**
 * How long do we sleep before trying again if there
 * are no transactions returned by the wire plugin?
 */
#define DELAY GNUNET_TIME_UNIT_SECONDS


/**
 * Information we keep for each supported account.
 */
struct WireAccount
{
  /**
   * Accounts are kept in a DLL.
   */
  struct WireAccount *next;

  /**
   * Plugins are kept in a DLL.
   */
  struct WireAccount *prev;

  /**
   * Name of the section that configures this account.
   */
  char *section_name;

  /**
   * Account information.
   */
  struct TALER_Account account;

  /**
   * Authentication data.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Are we running from scratch and should re-process all transactions
   * for this account?
   */
  int reset_mode;

  /**
   * Until when is processing this wire plugin delayed?
   */
  struct GNUNET_TIME_Absolute delayed_until;

};


/**
 * Head of list of loaded wire plugins.
 */
static struct WireAccount *wa_head;

/**
 * Tail of list of loaded wire plugins.
 */
static struct WireAccount *wa_tail;

/**
 * Wire plugin we are currently using.
 */
static struct WireAccount *wa_pos;

/**
 * Handle to the context for interacting with the bank.
 */
static struct GNUNET_CURL_Context *ctx;

/**
 * Scheduler context for running the @e ctx.
 */
static struct GNUNET_CURL_RescheduleContext *rc;

/**
 * Which currency is used by this exchange?
 */
static char *exchange_currency_string;

/**
 * The exchange's configuration (global)
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *db_plugin;

/**
 * Value to return from main(). #GNUNET_OK on success, #GNUNET_SYSERR
 * on serious errors.
 */
static int global_ret;

/**
 * Encoded offset in the wire transfer list from where
 * to start the next query with the bank.
 */
static uint64_t last_row_off;

/**
 * Latest row offset seen in this transaction, becomes
 * the new #last_row_off upon commit.
 */
static uint64_t latest_row_off;

/**
 * Should we delay the next request to the wire plugin a bit?
 */
static int delay;

/**
 * Are we run in testing mode and should only do one pass?
 */
static int test_mode;

/**
 * Are we running from scratch and should re-process all transactions?
 */
static int reset_mode;

/**
 * How many transactions do we retrieve per batch?
 */
static unsigned int batch_size = 1024;

/**
 * How many transactions did we see in the current batch?
 */
static unsigned int current_batch_size;

/**
 * Next task to run, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * Active request for history.
 */
static struct TALER_BANK_CreditHistoryHandle *hh;


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  struct WireAccount *wa;

  (void) cls;
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
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  if (NULL != hh)
  {
    TALER_BANK_credit_history_cancel (hh);
    hh = NULL;
  }
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  while (NULL != (wa = wa_head))
  {
    GNUNET_CONTAINER_DLL_remove (wa_head,
                                 wa_tail,
                                 wa);
    TALER_BANK_account_free (&wa->account);
    TALER_BANK_auth_free (&wa->auth);
    GNUNET_free (wa->section_name);
    GNUNET_free (wa);
  }
  wa_pos = NULL;
  last_row_off = 0;
}


/**
 * Function called with information about a wire account.  Adds the
 * account to our list (if it is enabled and we can load the plugin).
 *
 * @param cls closure, NULL
 * @param ai account information
 */
static void
add_account_cb (void *cls,
                const struct TALER_EXCHANGEDB_AccountInfo *ai)
{
  struct WireAccount *wa;

  (void) cls;
  if (GNUNET_YES != ai->credit_enabled)
    return; /* not enabled for us, skip */
  wa = GNUNET_new (struct WireAccount);
  wa->reset_mode = reset_mode;
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (cfg,
                                 ai->section_name,
                                 &wa->auth))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Failed to load account `%s'\n",
                ai->section_name);
    GNUNET_free (wa);
    return;
  }
  if (GNUNET_OK !=
      TALER_BANK_account_parse_cfg (cfg,
                                    ai->section_name,
                                    &wa->account))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Failed to load account `%s'\n",
                ai->section_name);
    TALER_BANK_auth_free (&wa->auth);
    GNUNET_free (wa);
    return;
  }
  wa->section_name = GNUNET_strdup (ai->section_name);
  GNUNET_CONTAINER_DLL_insert (wa_head,
                               wa_tail,
                               wa);
}


/**
 * Parse configuration parameters for the exchange server into the
 * corresponding global variables.
 *
 * @return #GNUNET_OK on success
 */
static int
exchange_serve_process_config ()
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &exchange_currency_string))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    return GNUNET_SYSERR;
  }
  if (strlen (exchange_currency_string) >= TALER_CURRENCY_LEN)
  {
    fprintf (stderr,
             "Currency `%s' longer than the allowed limit of %u characters.",
             exchange_currency_string,
             (unsigned int) TALER_CURRENCY_LEN);
    return GNUNET_SYSERR;
  }

  if (NULL ==
      (db_plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }
  TALER_EXCHANGEDB_find_accounts (cfg,
                                  &add_account_cb,
                                  NULL);
  if (NULL == wa_head)
  {
    fprintf (stderr,
             "No wire accounts configured for credit!\n");
    TALER_EXCHANGEDB_plugin_unload (db_plugin);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Query for incoming wire transfers.
 *
 * @param cls NULL
 */
static void
find_transfers (void *cls);


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure with the `struct TALER_EXCHANGEDB_Session *`
 * @param ec taler error code
 * @param serial_id identification of the position at which we are querying
 * @param details details about the wire transfer
 * @param json raw JSON response
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            uint64_t serial_id,
            const struct TALER_BANK_CreditDetails *details,
            const json_t *json)
{
  struct TALER_EXCHANGEDB_Session *session = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == details)
  {
    hh = NULL;
    if (TALER_EC_NONE != ec)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Error fetching history: %u!\n",
                  (unsigned int) ec);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "End of list. Committing progress!\n");
    qs = db_plugin->commit (db_plugin->cls,
                            session);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Got DB soft error for commit\n");
      /* reduce transaction size to reduce rollback probability */
      if (2 > current_batch_size)
        current_batch_size /= 2;
      /* try again */
      GNUNET_assert (NULL == task);
      task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                       NULL);
      return GNUNET_OK; /* will be ignored anyway */
    }
    if (0 < qs)
    {
      /* transaction success, update #last_row_off */
      last_row_off = latest_row_off;
      latest_row_off = 0;

      /* if successful at limit, try increasing transaction batch size (AIMD) */
      if (current_batch_size == batch_size)
        batch_size++;
    }
    GNUNET_break (0 <= qs);
    if ( (GNUNET_YES == delay) &&
         (test_mode) &&
         (NULL == wa_pos->next) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Shutdown due to test mode!\n");
      GNUNET_SCHEDULER_shutdown ();
      return GNUNET_OK;
    }
    if (GNUNET_YES == delay)
    {
      wa_pos->delayed_until
        = GNUNET_TIME_relative_to_absolute (DELAY);
      wa_pos = wa_pos->next;
      if (NULL == wa_pos)
        wa_pos = wa_head;
      GNUNET_assert (NULL != wa_pos);
    }
    task = GNUNET_SCHEDULER_add_at (wa_pos->delayed_until,
                                    &find_transfers,
                                    NULL);
    return GNUNET_OK; /* will be ignored anyway */
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Adding wire transfer over %s with (hashed) subject `%s'\n",
              TALER_amount2s (&details->amount),
              TALER_B2S (&details->reserve_pub));

  /**
   * Debug block.
   */
  {
/* Should be 53, give 80 just to be redundant.  */
#define PUBSIZE 80
    char wtid_s[PUBSIZE];

    GNUNET_break
      (NULL != GNUNET_STRINGS_data_to_string (&details->reserve_pub,
                                              sizeof (details->reserve_pub),
                                              &wtid_s[0],
                                              PUBSIZE));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Plain text subject (= reserve_pub): %s\n",
                wtid_s);
  }

  current_batch_size++;
  qs = db_plugin->reserves_in_insert (db_plugin->cls,
                                      session,
                                      &details->reserve_pub,
                                      &details->amount,
                                      details->execution_date,
                                      details->account_url,
                                      wa_pos->section_name,
                                      serial_id);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls,
                         session);
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Got DB soft error for reserve_in_insert\n");
    db_plugin->rollback (db_plugin->cls,
                         session);
    /* try again */
    GNUNET_assert (NULL == task);
    task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                     NULL);
    return GNUNET_SYSERR;
  }

  latest_row_off = serial_id;
  return GNUNET_OK;
}


/**
 * Query for incoming wire transfers.
 *
 * @param cls NULL
 */
static void
find_transfers (void *cls)
{
  struct TALER_EXCHANGEDB_Session *session;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  task = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking for incoming wire transfers\n");

  if (NULL == (session = db_plugin->get_session (db_plugin->cls)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database session!\n");
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  db_plugin->preflight (db_plugin->cls,
                        session);
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        session,
                        "wirewatch check for incoming wire transfers"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (! wa_pos->reset_mode)
  {
    qs = db_plugin->get_latest_reserve_in_reference (db_plugin->cls,
                                                     session,
                                                     wa_pos->section_name,
                                                     &last_row_off);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to obtain starting point for montoring from database!\n");
      db_plugin->rollback (db_plugin->cls,
                           session);
      global_ret = GNUNET_SYSERR;
      GNUNET_SCHEDULER_shutdown ();
      return;
    }
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      /* try again */
      db_plugin->rollback (db_plugin->cls,
                           session);
      task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                       NULL);
      return;
    }
  }
  wa_pos->reset_mode = GNUNET_NO;
  delay = GNUNET_YES;
  current_batch_size = 0;

  hh = TALER_BANK_credit_history (ctx,
                                  wa_pos->account.details.x_taler_bank.
                                  account_base_url,
                                  &wa_pos->auth,
                                  last_row_off,
                                  batch_size,
                                  &history_cb,
                                  session);
  if (NULL == hh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start request for account history!\n");
    db_plugin->rollback (db_plugin->cls,
                         session);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
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
  (void) cls;
  (void) args;
  (void) cfgfile;
  cfg = c;
  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = 1;
    return;
  }
  wa_pos = wa_head;
  GNUNET_assert (NULL != wa_pos);
  task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
  ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                          &rc);
  rc = GNUNET_CURL_gnunet_rc_create (ctx);
  if (NULL == ctx)
  {
    GNUNET_break (0);
    return;
  }
}


/**
 * The main function of taler-exchange-wirewatch
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
    GNUNET_GETOPT_option_flag ('T',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_flag ('r',
                               "reset",
                               "start fresh with all transactions in the history",
                               &reset_mode),
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return 2;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-wirewatch",
                          gettext_noop (
                            "background process that watches for incomming wire transfers from customers"),
                          options,
                          &run, NULL))
  {
    GNUNET_free ((void *) argv);
    return 1;
  }
  GNUNET_free ((void *) argv);
  return global_ret;
}


/* end of taler-exchange-wirewatch.c */
