/*
  This file is part of TALER
  Copyright (C) 2017 Taler Systems SA

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
 * @file auditor/taler-wire-auditor.c
 * @brief audits that wire transfers match those from an exchange database.
 * @author Christian Grothoff
 *
 * - First, this auditor verifies that 'reserves_in' actually matches
 *   the incoming wire transfers from the bank.
 * - Second, we check that the outgoing wire transfers match those
 *   given in the 'wire_out' table.
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_wire_lib.h"
#include "taler_signatures.h"


/**
 * Return value from main().
 */
static int global_ret;

/**
 * Command-line option "-r": restart audit from scratch
 */
static int restart;

/**
 * Name of the wire plugin to load to access the exchange's bank account.
 */
static char *wire_plugin;

/**
 * Handle to access the exchange's database.
 */
static struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Which currency are we doing the audit for?
 */
static char *currency;

/**
 * Our configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our session with the #edb.
 */
static struct TALER_EXCHANGEDB_Session *esession;

/**
 * Handle to access the auditor's database.
 */
static struct TALER_AUDITORDB_Plugin *adb;

/**
 * Our session with the #adb.
 */
static struct TALER_AUDITORDB_Session *asession;

/**
 * Master public key of the exchange to audit.
 */
static struct TALER_MasterPublicKeyP master_pub;

/**
 * Handle to the wire plugin for wire operations.
 */
static struct TALER_WIRE_Plugin *wp;

/**
 * Active wire request for the transaction history.
 */
static struct TALER_WIRE_HistoryHandle *hh;

/**
 * Query status for the incremental processing status in the auditordb.
 */
static enum GNUNET_DB_QueryStatus qsx;

/**
 * Last reserve_in / reserve_out serial IDs seen.
 */
static struct TALER_AUDITORDB_WireProgressPoint pp;

/**
 * Where we are in the inbound (CREDIT) transaction history.
 */
static void *in_wire_off;

/**
 * Where we are in the inbound (DEBIT) transaction history.
 */
static void *out_wire_off;

/**
 * Number of bytes in #in_wire_off and #out_wire_off.
 */
static size_t wire_off_size;


/* *****************************   Shutdown   **************************** */

/**
 * Task run on shutdown.
 */
static void
do_shutdown ()
{
  if (NULL != hh)
  {
    wp->get_history_cancel (wp->cls,
                            hh);
    hh = NULL;
  }
  if (NULL != wp)
  {
    TALER_WIRE_plugin_unload (wp);
    wp = NULL;
  }
  if (NULL != adb)
  {
    TALER_AUDITORDB_plugin_unload (adb);
    adb = NULL;
  }
  if (NULL != edb)
  {
    TALER_EXCHANGEDB_plugin_unload (edb);
    edb = NULL;
  }
}


/* ***************************** Report logic **************************** */

#if 0
/**
 * Report a (serious) inconsistency in the exchange's database.
 *
 * @param table affected table
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_inconsistency (const char *table,
                          uint64_t rowid,
                          const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Database inconsistency detected in table %s at row %llu: %s\n",
              table,
              (unsigned long long) rowid,
              diagnostic);
}


/**
 * Report a minor inconsistency in the exchange's database (i.e. something
 * relating to timestamps that should have no financial implications).
 *
 * @param table affected table
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_minor_inconsistency (const char *table,
                                uint64_t rowid,
                                const char *diagnostic)
{
  // TODO: implement proper reporting logic writing to file.
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Minor inconsistency detected in table %s at row %llu: %s\n",
              table,
              (unsigned long long) rowid,
              diagnostic);
}
#endif


/* *************************** General transaction logic ****************** */

/**
 * Commit the transaction, checkpointing our progress in the auditor
 * DB.
 *
 * @param qs transaction status so far
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
commit (enum GNUNET_DB_QueryStatus qs)
{
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		  "Serialization issue, not recording progress\n");
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		  "Hard error, not recording progress\n");
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx)
    qs = adb->update_wire_auditor_progress (adb->cls,
                                            asession,
                                            &master_pub,
                                            &pp,
                                            in_wire_off,
                                            out_wire_off,
                                            wire_off_size);
  else
    qs = adb->insert_wire_auditor_progress (adb->cls,
                                            asession,
                                            &master_pub,
                                            &pp,
                                            in_wire_off,
                                            out_wire_off,
                                            wire_off_size);

  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		"Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _("Concluded audit step at %llu/%llu\n"),
              (unsigned long long) pp.last_reserve_in_serial_id,
              (unsigned long long) pp.last_reserve_out_serial_id);

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    qs = edb->commit (edb->cls,
                       esession);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      adb->rollback (adb->cls,
                     asession);
    }
    else
    {
      qs = adb->commit (adb->cls,
			asession);
      if (0 > qs)
      {
	GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Auditor DB commit failed!\n");
      }
    }
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Processing failed, rolling back transaction\n");
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
  }
  return qs;
}


/* ***************************** Analyze reserves_in ************************ */


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure
 * @param dir direction of the transfer
 * @param row_off identification of the position at which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_credit_cb (void *cls,
                   enum TALER_BANK_Direction dir,
                   const void *row_off,
                   size_t row_off_size,
                   const struct TALER_WIRE_TransferDetails *details)
{
  if (NULL == details)
  {
    /* end of operation */
    hh = NULL;
    /* TODO: also check DEBITs! */
    commit (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT);
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  /* TODO: implement actual checks! */
  return GNUNET_OK;
}



/* ***************************** Setup logic    ************************ */


/**
 * Main function that will be run.
 *
 * @param cls closure
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
  int ret;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching auditor\n");
  cfg = c;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (edb = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize exchange database plugin.\n");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (adb = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize auditor database plugin.\n");
    global_ret = 1;
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }
  if (restart)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Full audit restart requested, dropping old audit data.\n");
    GNUNET_break (GNUNET_OK ==
                  adb->drop_tables (adb->cls));
    TALER_AUDITORDB_plugin_unload (adb);
    if (NULL ==
        (adb = TALER_AUDITORDB_plugin_load (cfg)))
    {
      fprintf (stderr,
               "Failed to initialize auditor database plugin after drop.\n");
      global_ret = 1;
      TALER_EXCHANGEDB_plugin_unload (edb);
      return;
    }
    GNUNET_break (GNUNET_OK ==
                  adb->create_tables (adb->cls));
  }
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  wp = TALER_WIRE_plugin_load (cfg,
                               wire_plugin);
  if (NULL == wp)
  {
    fprintf (stderr,
             "Failed to load wire plugin `%s'\n",
             wire_plugin);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  ret = edb->start (edb->cls,
                    esession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  qsx = adb->get_wire_auditor_progress (adb->cls,
                                        asession,
                                        &master_pub,
                                        &pp,
                                        &in_wire_off,
                                        &out_wire_off,
                                        &wire_off_size);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _("First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _("Resuming audit at %llu/%llu\n"),
                (unsigned long long) pp.last_reserve_in_serial_id,
                (unsigned long long) pp.last_reserve_out_serial_id);
  }

  hh = wp->get_history (wp->cls,
                        TALER_BANK_DIRECTION_CREDIT,
                        in_wire_off,
                        wire_off_size,
                        INT64_MAX,
                        &history_credit_cb,
                        NULL);
  if (NULL == hh)
  {
    fprintf (stderr,
             "Failed to obtain bank transaction history\n");
    commit (GNUNET_DB_STATUS_HARD_ERROR);
    global_ret = 1;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
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
    GNUNET_GETOPT_option_mandatory
    (GNUNET_GETOPT_option_base32_auto ('m',
                                       "exchange-key",
                                       "KEY",
                                       "public key of the exchange (Crockford base32 encoded)",
                                       &master_pub)),
    GNUNET_GETOPT_option_flag ('r',
                               "restart",
                               "restart audit from the beginning (required on first run)",
                               &restart),
    GNUNET_GETOPT_option_string ('w',
                                 "wire",
                                 "PLUGINNAME",
                                 "name of the wire plugin to use",
                                 &wire_plugin),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-wire-auditor",
                                   "MESSAGE",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
			  argv,
                          "taler-wire-auditor",
			  "Audit exchange database for consistency with the bank's wire transfers",
			  options,
			  &run,
			  NULL))
    return 1;
  return global_ret;
}


/* end of taler-wire-auditor.c */
