/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-mint-aggregator.c
 * @brief Process that aggregates outgoing transactions and executes them
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include "taler_mintdb_lib.h"
#include "taler_mintdb_plugin.h"
#include "taler_wire_lib.h"

/**
 * Which currency is used by this mint?
 */
static char *mint_currency_string;

/**
 * Which wireformat should be supported by this aggregator?
 */
static char *mint_wireformat;

/**
 * Base directory of the mint (global)
 */
static char *mint_directory;

/**
 * The mint's configuration (global)
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_MINTDB_Plugin *db_plugin;

/**
 * Our wire plugin.
 */
static struct TALER_WIRE_Plugin *wire_plugin;

/**
 * Task for the main #run() function.
 */
static struct GNUNET_SCHEDULER_Task *task;


/**
 * Load configuration parameters for the mint
 * server into the corresponding global variables.
 *
 * @param mint_directory the mint's directory
 * @return #GNUNET_OK on success
 */
static int
mint_serve_process_config (const char *mint_directory)
{
  char *type;

  cfg = TALER_config_load (mint_directory);
  if (NULL == cfg)
  {
    fprintf (stderr,
             "Failed to load mint configuration\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint",
                                             "currency",
                                             &mint_currency_string))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint",
                               "currency");
    return GNUNET_SYSERR;
  }
  if (strlen (mint_currency_string) >= TALER_CURRENCY_LEN)
  {
    fprintf (stderr,
             "Currency `%s' longer than the allowed limit of %u characters.",
             mint_currency_string,
             (unsigned int) TALER_CURRENCY_LEN);
    return GNUNET_SYSERR;
  }
  if (NULL != mint_wireformat)
    GNUNET_CONFIGURATION_set_value_string (cfg,
                                           "mint",
                                           "wireformat",
                                           mint_wireformat);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint",
                                             "wireformat",
                                             &type))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint",
                               "wireformat");
    return GNUNET_SYSERR;
  }

  if (NULL ==
      (db_plugin = TALER_MINTDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    GNUNET_free (type);
    return GNUNET_SYSERR;
  }

  if (NULL ==
      (wire_plugin = TALER_WIRE_plugin_load (cfg,
                                             type)))
  {
    fprintf (stderr,
             "Failed to load wire plugin for `%s'\n",
             type);
    GNUNET_free (type);
    return GNUNET_SYSERR;
  }
  GNUNET_free (type);

  return GNUNET_OK;
}


/**
 * Function called with details about deposits that have been made,
 * with the goal of executing the corresponding wire transaction.
 *
 * @param cls closure
 * @param id transaction ID (used as future `min_id` to avoid
 *           iterating over transactions more than once)
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the mint gets to keep as transaction fees
 * @param transaction_id unique transaction ID chosen by the merchant
 * @param h_contract hash of the contract between merchant and customer
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param wire wire details for the merchant
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
deposit_cb (void *cls,
            uint64_t id,
            const struct TALER_Amount *amount_with_fee,
            const struct TALER_Amount *deposit_fee,
            uint64_t transaction_id,
            const struct GNUNET_HashCode *h_contract,
            struct GNUNET_TIME_Absolute wire_deadline,
            const json_t *wire)
{
  /* FIXME: compute aggregates, etc. */
  return GNUNET_OK;
}


/**
 * Main work function that queries the DB and executes transactions.
 */
static void
run (void *cls,
     const struct GNUNET_SCHEDULER_TaskContext *tc)
{
  int *global_ret = cls;
  struct TALER_MINTDB_Session *session;
  int ret;

  if (0 != (tc->reason & GNUNET_SCHEDULER_REASON_SHUTDOWN))
    return;
  if (NULL == (session = db_plugin->get_session (db_plugin->cls,
                                                 GNUNET_NO)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to obtain database session!\n");
    *global_ret = GNUNET_SYSERR;
    return;
  }
  if (GNUNET_OK !=
      db_plugin->start (db_plugin->cls,
                        session))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to start database transaction!\n");
    *global_ret = GNUNET_SYSERR;
    return;
  }
  ret = db_plugin->iterate_deposits (db_plugin->cls,
                                     session,
                                     0 /* FIXME: remove? */,
                                     128 /* FIXME: make configurable? */,
                                     &deposit_cb,
                                     NULL);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to execute deposit iteration!\n");
    *global_ret = GNUNET_SYSERR;
    db_plugin->rollback (db_plugin->cls,
                         session);
    return;
  }
  /* FIXME: finish aggregate computation */
  /* wire_plugin->prepare_wire_transfer () -- ASYNC! */
  /* db_plugin->wire_prepare_data_insert () -- transactional! */
  /* db_plugin->XXX () -- mark transactions selected for aggregate as finished */

  /* then finally: commit! */
  if (GNUNET_OK !=
      db_plugin->commit (db_plugin->cls,
                         session))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to commit database transaction!\n");
  }

  /* While possible, run 2nd type of transaction:
     db_plugin->start()
     - select pre-commit data from DB:
     db_plugin->wire_prepare_data_iterate ()
     - execute wire transfer (successfully!)
     wire_plugin->execute_wire_transfer() # ASYNC!
     db_plugin->wire_prepare_data_mark_finished ()
     db_plugin->insert_aggregation_tracking ()
     db_plugin->commit()
  */


  task = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_SECONDS /* FIXME: adjust! */,
                                       &run,
                                       global_ret);
}


/**
 * The main function of the taler-mint-httpd server ("the mint").
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'d', "mint-dir", "DIR",
     "mint directory with configuration and keys for operating the mint", 1,
     &GNUNET_GETOPT_set_filename, &mint_directory},
    {'f', "format", "WIREFORMAT",
     "wireformat to use, overrides WIREFORMAT option in [mint] section", 1,
     &GNUNET_GETOPT_set_filename, &mint_wireformat},
    TALER_GETOPT_OPTION_HELP ("background process that aggregates and executes wire transfers to merchants"),
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret = GNUNET_OK;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-aggregator",
                                   "INFO",
                                   NULL));
  if (0 >=
      GNUNET_GETOPT_run ("taler-mint-aggregator",
                         options,
                         argc, argv))
    return 1;
  if (NULL == mint_directory)
  {
    fprintf (stderr,
             "Mint directory not specified\n");
    return 1;
  }
  if (GNUNET_OK !=
      mint_serve_process_config (mint_directory))
  {
    return 1;
  }

  GNUNET_SCHEDULER_run (&run, &ret);

  TALER_MINTDB_plugin_unload (db_plugin);
  TALER_WIRE_plugin_unload (wire_plugin);
  return (GNUNET_SYSERR == ret) ? 1 : 0;
}

/* end of taler-mint-aggregator.c */
