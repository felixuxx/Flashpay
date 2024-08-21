/*
  This file is part of TALER
  Copyright (C) 2016-2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero Public License for more details.

  You should have received a copy of the GNU Affero Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file auditor/taler-helper-auditor-deposits.c
 * @brief audits an exchange database for deposit confirmation consistency
 * @author Christian Grothoff
 * @author Nic Eigel
 *
 * We simply check that all of the deposit confirmations reported to us
 * by merchants were also reported to us by the exchange.
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "report-lib.h"
#include "taler_dbevents.h"
#include <jansson.h>
#include <inttypes.h>

/*
--
-- SELECT serial_id,h_contract_terms,h_wire,merchant_pub ...
--   FROM auditor.auditor_deposit_confirmations
--   WHERE NOT ancient
--    ORDER BY exchange_timestamp ASC;
--  SELECT 1
-      FROM exchange.deposits dep
       WHERE ($RESULT.contract_terms = dep.h_contract_terms) AND ($RESULT.h_wire = dep.h_wire) AND ...);
-- IF FOUND
-- DELETE FROM auditor.auditor_deposit_confirmations
--   WHERE serial_id = $RESULT.serial_id;
-- SELECT exchange_timestamp AS latest
--   FROM exchange.deposits ORDER BY exchange_timestamp DESC;
-- latest -= 1 hour; // time is not exactly monotonic...
-- UPDATE auditor.deposit_confirmations
--   SET ancient=TRUE
--  WHERE exchange_timestamp < latest
--    AND NOT ancient;
*/

/**
 * Return value from main().
 */
static int global_ret;

static TALER_ARL_DEF_PP (deposit_confirmation_serial_id);

/**
 * Run in test mode. Exit when idle instead of
 * going to sleep and waiting for more work.
 */
static int test_mode;

/**
 * Total amount involved in deposit confirmations that we did not get.
 */
static TALER_ARL_DEF_AB (total_missed_deposit_confirmations);

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

static struct GNUNET_DB_EventHandler *eh;

/**
 * The auditors's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Success or failure of (exchange) database operations within
 * #test_dc.
 */
static enum GNUNET_DB_QueryStatus eqs;


/**
 * Given a deposit confirmation from #TALER_ARL_adb, check that it is also
 * in #TALER_ARL_edb.  Update the deposit confirmation context accordingly.
 *
 * @param cls our `struct DepositConfirmationContext`
 * @param serial_id row of the @a dc in the database
 * @param dc the deposit confirmation we know
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
static enum GNUNET_GenericReturnValue
test_dc (void *cls,
         uint64_t serial_id,
         const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  bool missing = false;
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  TALER_ARL_USE_PP (deposit_confirmation_serial_id) = serial_id;
  for (unsigned int i = 0; i < dc->num_coins; i++)
  {
    struct GNUNET_TIME_Timestamp exchange_timestamp;
    struct TALER_Amount deposit_fee;

    qs = TALER_ARL_edb->have_deposit2 (TALER_ARL_edb->cls,
                                       &dc->h_contract_terms,
                                       &dc->h_wire,
                                       &dc->coin_pubs[i],
                                       &dc->merchant,
                                       dc->refund_deadline,
                                       &deposit_fee,
                                       &exchange_timestamp);
    missing |= (0 == qs);
    if (qs < 0)
    {
      GNUNET_break (0); /* DB error, complain */
      eqs = qs;
      return GNUNET_SYSERR;
    }
  }
  qs = TALER_ARL_adb->delete_deposit_confirmation (TALER_ARL_adb->cls,
                                                   serial_id);
  if (qs < 0)
  {
    GNUNET_break (0); /* DB error, complain */
    eqs = qs;
    return GNUNET_SYSERR;
  }
  if (! missing)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Found deposit %s in exchange database\n",
                GNUNET_h2s (&dc->h_contract_terms.hash));
    return GNUNET_OK; /* all coins found, all good */
  }
  // FIXME: where do we *decrease* this amount if we get a DC later?
  TALER_ARL_amount_add (&TALER_ARL_USE_AB (total_missed_deposit_confirmations),
                        &TALER_ARL_USE_AB (total_missed_deposit_confirmations),
                        &dc->total_without_fee);
  return GNUNET_OK;
}


/**
 * Check that the deposit-confirmations that were reported to
 * us by merchants are also in the exchange's database.
 *
 * @param cls closure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_deposit_confirmations (void *cls)
{
  enum GNUNET_DB_QueryStatus qs;

  (void) cls;
  qs = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (deposit_confirmation_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis using deposit auditor, starting audit from scratch\n");
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming deposit confirmation audit at %llu\n",
                (unsigned long long) TALER_ARL_USE_PP (
                  deposit_confirmation_serial_id));
  }
  qs = TALER_ARL_adb->get_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_AB (total_missed_deposit_confirmations),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_adb->get_deposit_confirmations (
    TALER_ARL_adb->cls,
    INT64_MAX,
    0,
    true, /* return suppressed */
    &test_dc,
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 > eqs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == eqs);
    return eqs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Analyzed %d deposit confirmations\n",
              (int) qs);
  qs = TALER_ARL_adb->insert_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (deposit_confirmation_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_adb->update_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (deposit_confirmation_serial_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_adb->insert_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (total_missed_deposit_confirmations),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = TALER_ARL_adb->update_balance (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_AB (total_missed_deposit_confirmations),
    NULL);
  if (0 > qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Function called on events received from Postgres.
 *
 * @param cls closure, NULL
 * @param extra additional event data provided
 * @param extra_size number of bytes in @a extra
 */
static void
db_notify (void *cls,
           const void *extra,
           size_t extra_size)
{
  (void) cls;
  (void) extra;
  (void) extra_size;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received notification for new deposit_confirmation\n");
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_deposit_confirmations,
                                        NULL))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Audit failed\n");
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
}


/**
 * Function called on shutdown.
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  if (NULL != eh)
  {
    TALER_ARL_adb->event_listen_cancel (eh);
    eh = NULL;
  }
  TALER_ARL_done ();
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
  (void) cls;
  (void) args;
  (void) cfgfile;
  cfg = c;
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching deposit auditor\n");
  if (GNUNET_OK !=
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }

  if (test_mode != 1)
  {
    struct GNUNET_DB_EventHeaderP es = {
      .size = htons (sizeof (es)),
      .type = htons (TALER_DBEVENT_EXCHANGE_AUDITOR_WAKE_HELPER_DEPOSITS)
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Running helper indefinitely\n");
    eh = TALER_ARL_adb->event_listen (TALER_ARL_adb->cls,
                                      &es,
                                      GNUNET_TIME_UNIT_FOREVER_REL,
                                      &db_notify,
                                      NULL);
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  if (GNUNET_OK !=
      TALER_ARL_setup_sessions_and_run (&analyze_deposit_confirmations,
                                        NULL))
  {
    GNUNET_SCHEDULER_shutdown ();
    global_ret = EXIT_FAILURE;
    return;
  }
}


/**
 * The main function of the deposit auditing helper tool.
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
    GNUNET_GETOPT_option_flag ('i',
                               "internal",
                               "perform checks only applicable for exchange-internal audits",
                               &internal_checks),
    GNUNET_GETOPT_option_flag ('t',
                               "test",
                               "run in test mode and exit when idle",
                               &test_mode),
    GNUNET_GETOPT_option_timetravel ('T',
                                     "timetravel"),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return EXIT_INVALIDARGUMENT;
  ret = GNUNET_PROGRAM_run (
    argc,
    argv,
    "taler-helper-auditor-deposits",
    gettext_noop (
      "Audit Taler exchange database for deposit confirmation consistency"),
    options,
    &run,
    NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return EXIT_INVALIDARGUMENT;
  if (GNUNET_NO == ret)
    return EXIT_SUCCESS;
  return global_ret;
}


/* end of taler-helper-auditor-deposits.c */
