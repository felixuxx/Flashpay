/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

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
#include "taler_wire_lib.h"

/**
 * How long do we sleep before trying again if there
 * are no transactions returned by the wire plugin?
 */
#define DELAY GNUNET_TIME_UNIT_SECONDS


/**
 * Handle to the plugin.
 */
static struct TALER_WIRE_Plugin *wire_plugin;
  
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
 * Encoded offset in the wire transfer list that we 
 * processed last.
 */
static void *last_row_off;

/**
 * Number of bytes in #last_row_off.
 */
static size_t last_row_off_size;

/**
 * Encoded offset in the wire transfer list from where
 * to start the next query with the bank.
 */
static void *start_off;

/**
 * Number of bytes in #start_off.
 */
static size_t start_off_size;

/**
 * Which wire plugin are we watching?
 */
static char *type;

/**
 * Should we delay the next request to the wire plugin a bit?
 */
static int delay;

/**
 * Next task to run, if any.
 */
static struct GNUNET_SCHEDULER_Task *task;

/**
 * Active request for history.
 */
static struct TALER_WIRE_HistoryHandle *hh;


/**
 * We're being aborted with CTRL-C (or SIGTERM). Shut down.
 *
 * @param cls closure
 */
static void
shutdown_task (void *cls)
{
  if (NULL != task)
  {
    GNUNET_SCHEDULER_cancel (task);
    task = NULL;
  }
  if (NULL != hh)
  {
    wire_plugin->get_history_cancel (wire_plugin->cls,
				     hh);
    hh = NULL;
  }
  TALER_EXCHANGEDB_plugin_unload (db_plugin);
  db_plugin = NULL;
  TALER_WIRE_plugin_unload (wire_plugin);
  wire_plugin = NULL;
  GNUNET_free_non_null (start_off);
  start_off = NULL;
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
                                             "currency",
                                             &exchange_currency_string))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "currency");
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

  if (NULL ==
      (wire_plugin = TALER_WIRE_plugin_load (cfg,
					     type)))
  {
    fprintf (stderr,
             "Failed to load wire plugin for `%s'\n",
             type);
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
 * @param dir direction of the transfer
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_cb (void *cls,
	    enum TALER_BANK_Direction dir,
	    const void *row_off,
	    size_t row_off_size,
	    const struct TALER_BANK_TransferDetails *details)
{
  struct TALER_EXCHANGEDB_Session *session = cls;
  int ret;
  struct TALER_ReservePublicKeyP reserve_pub;

  if (TALER_BANK_DIRECTION_NONE == dir)
  {
    hh = NULL;

    /* FIXME: commit last_off to DB! */

    ret = db_plugin->commit (db_plugin->cls,
			     session);
    if (GNUNET_OK == ret)
    {
      GNUNET_free_non_null (start_off);
      start_off = last_row_off;
      start_off_size = last_row_off_size;
    }
    if (GNUNET_YES == delay)
      task = GNUNET_SCHEDULER_add_delayed (DELAY,
					   &find_transfers,
					   NULL);
    else
      task = GNUNET_SCHEDULER_add_now (&find_transfers,
				       NULL);
    return GNUNET_OK; /* will be ignored anyway */
  }
  /* TODO: We should expect a checksum! */
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (details->wire_transfer_subject,
				     strlen (details->wire_transfer_subject),
				     &reserve_pub,
				     sizeof (reserve_pub)))
  {
    /* FIXME: need way to wire money back immediately... */
    GNUNET_break (0); // not implemented
    
    return GNUNET_OK;
  }
  // FIXME: store row_off+row_off_size instead of json_t?
  ret = db_plugin->reserves_in_insert (db_plugin->cls,
				       session,
				       &reserve_pub,
				       &details->amount,
				       details->execution_date,
				       details->account_details,
				       NULL /* FIXME */);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    db_plugin->rollback (db_plugin->cls,
                         session);
    /* try again */
    task = GNUNET_SCHEDULER_add_now (&find_transfers,
				     NULL);
    return GNUNET_SYSERR;
  }
  
  if (last_row_off_size != row_off_size)
  {
    GNUNET_free_non_null (last_row_off);
    last_row_off = GNUNET_malloc (row_off_size);
  }
  memcpy (last_row_off,
	  row_off,
	  row_off_size);
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
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        session))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  /* FIXME: fetch start_off from DB! */

  delay = GNUNET_YES;
  hh = wire_plugin->get_history (wire_plugin->cls,
				 TALER_BANK_DIRECTION_CREDIT,
				 start_off,
				 start_off_size,
				 1024,
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
  cfg = c;
  if (GNUNET_OK !=
      exchange_serve_process_config ())
  {
    global_ret = 1;
    return;
  }
  
  task = GNUNET_SCHEDULER_add_now (&find_transfers,
                                   NULL);
  GNUNET_SCHEDULER_add_shutdown (&shutdown_task,
                                 cls);
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
    GNUNET_GETOPT_option_string ('t',
				 "type",
				 "PLUGINNAME",
				 "which wire plugin to use",
				 &type),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
				    &argc, &argv))
    return 2;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-wirewatch",
                          gettext_noop ("background process that watches for incomming wire transfers from customers"),
                          options,
                          &run, NULL))
  {
    GNUNET_free ((void*) argv);
    return 1;
  }
  GNUNET_free ((void*) argv);
  return global_ret;
}

/* end of taler-exchange-wirewatch.c */
