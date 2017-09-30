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
 * Last reserve_in / reserve_out serial IDs seen.
 */
static struct TALER_AUDITORDB_WireProgressPoint pp;


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


/* ***************************** Analyze reserves_in ************************ */
/* This logic checks the reserves_in table */

/**
 * Analyze reserves for being well-formed.
 *
 * @param cls NULL
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_reserves_in (void *cls)
{
  /* FIXME: #4958 */
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/* ***************************** Analyze reserves_out ************************ */
/* This logic checks the reserves_out table */

/**
 * Analyze reserves for being well-formed.
 *
 * @param cls NULL
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_reserves_out (void *cls)
{
#if 0
  // FIXME: start_off != rowid!
  hh = wp->get_history (wp->cls,
                        TALER_BANK_DIRECTION_CREDIT,
                        &start_off,
                        sizeof (start_off),
                        INT64_MAX,
                        &history_cb,
                        NULL);
#endif
  /* FIXME: #4958 */
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/* *************************** General transaction logic ****************** */

/**
 * Type of an analysis function.  Each analysis function runs in
 * its own transaction scope and must thus be internally consistent.
 *
 * @param cls closure
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*Analysis)(void *cls);


/**
 * Perform the given @a analysis incrementally, checkpointing our
 * progress in the auditor DB.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
incremental_processing (Analysis analysis,
                        void *analysis_cls)
{
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsx;
  void *in_wire_off;
  void *out_wire_off;
  size_t wire_off_size;

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
    return qsx;
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
  qs = analysis (analysis_cls);
  // FIXME: wire plugin does NOT support synchronous activity!
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
		  "Serialization issue, not recording progress\n");
    else
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		  "Hard database error, not recording progress\n");
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
  return qs;
}


/**
 * Perform the given @a analysis within a transaction scope.
 * Commit on success.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis succeessfully committed,
 *         #GNUNET_NO if we had an error on commit (retry may help)
 *         #GNUNET_SYSERR on hard errors
 */
static int
transact (Analysis analysis,
          void *analysis_cls)
{
  int ret;
  enum GNUNET_DB_QueryStatus qs;

  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  ret = edb->start (edb->cls,
                    esession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  qs = incremental_processing (analysis,
                                analysis_cls);
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


/**
 * Initialize DB sessions and run the analysis.
 */
static void
setup_sessions_and_run ()
{
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
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
    return;
  }
  // FIXME: wire plugin does NOT support synchronous activity!
  transact (&analyze_reserves_in,
            NULL);
  transact (&analyze_reserves_out,
            NULL);
}


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

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  setup_sessions_and_run ();
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Audit complete\n");
  if (NULL != wp)
    TALER_WIRE_plugin_unload (wp);
  if (NULL != adb)
    TALER_AUDITORDB_plugin_unload (adb);
  if (NULL != edb)
    TALER_EXCHANGEDB_plugin_unload (edb);
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
