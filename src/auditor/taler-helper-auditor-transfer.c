/*
  This file is part of TALER
  Copyright (C) 2017-2024 Taler Systems SA

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
 * @file auditor/taler-helper-auditor-transfer.c
 * @brief audits that deposits past due date are
 *    aggregated and have a matching wire transfer
 * database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_signatures.h"
#include "report-lib.h"
#include "taler_dbevents.h"


/**
 * Run in test mode. Exit when idle instead of
 * going to sleep and waiting for more work.
 */
static int test_mode;

/**
 * Return value from main().
 */
static int global_ret;

/**
 * State of the current database transaction with
 * the auditor DB.
 */
static enum GNUNET_DB_QueryStatus global_qs;

/**
 * Last reserve_out / wire_out serial IDs seen.
 */
static TALER_ARL_DEF_PP (wire_batch_deposit_id);
static TALER_ARL_DEF_PP (wire_aggregation_id);

/**
 * Should we run checks that only work for exchange-internal audits?
 */
static int internal_checks;

/**
 * Database event handler to wake us up again.
 */
static struct GNUNET_DB_EventHandler *eh;

/**
 * The auditors's configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;


/**
 * Task run on shutdown.
 *
 * @param cls NULL
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
  TALER_EXCHANGEDB_unload_accounts ();
  TALER_ARL_cfg = NULL;
}


/**
 * Start the database transactions and begin the audit.
 *
 * @return false on failure
 */
static bool
begin_transaction (void);


/**
 * Commit the transaction, checkpointing our progress in the auditor DB.
 *
 * @param qs transaction status so far
 */
static void
commit_transaction (enum GNUNET_DB_QueryStatus qs)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transaction logic ended with status %d\n",
              qs);
  if (qs < 0)
    goto handle_db_error;
  qs = TALER_ARL_adb->update_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (wire_batch_deposit_id),
    TALER_ARL_SET_PP (wire_aggregation_id),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  qs = TALER_ARL_adb->insert_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_SET_PP (wire_batch_deposit_id),
    TALER_ARL_SET_PP (wire_aggregation_id),
    NULL);
  if (0 > qs)
    goto handle_db_error;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Concluded audit step at %llu/%llu\n",
              (unsigned long long) TALER_ARL_USE_PP (wire_aggregation_id),
              (unsigned long long) TALER_ARL_USE_PP (wire_batch_deposit_id));
  qs = TALER_ARL_edb->commit (TALER_ARL_edb->cls);
  if (0 > qs)
    goto handle_db_error;
  qs = TALER_ARL_adb->commit (TALER_ARL_adb->cls);
  if (0 > qs)
    goto handle_db_error;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transaction concluded!\n");
  if (1 == test_mode)
    GNUNET_SCHEDULER_shutdown ();
  return;
handle_db_error:
  TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
  TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
  if (GNUNET_DB_STATUS_HARD_ERROR != qs)
  {
    for (unsigned int max_retries = 3; max_retries>0; max_retries--)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Trying again (%u attempts left)\n",
                  max_retries);
      if (begin_transaction ())
        return;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Hard database error, terminating\n");
  GNUNET_SCHEDULER_shutdown ();
}


/**
 * Closure for import_wire_missing_cb().
 */
struct ImportMissingWireContext
{
  /**
   * Set to maximum row ID encountered.
   */
  uint64_t max_batch_deposit_uuid;

  /**
   * Set to database errors in callback.
   */
  enum GNUNET_DB_QueryStatus err;
};


/**
 * Function called on deposits that need to be checked for their
 * wire transfer.
 *
 * @param cls closure, points to a `struct ImportMissingWireContext`
 * @param batch_deposit_serial_id serial of the entry in the batch deposits table
 * @param total_amount value of the missing deposits, including fee
 * @param wire_target_h_payto where should the funds be wired
 * @param deadline what was the earliest requested wire transfer deadline
 */
static void
import_wire_missing_cb (
  void *cls,
  uint64_t batch_deposit_serial_id,
  const struct TALER_Amount *total_amount,
  const struct TALER_PaytoHashP *wire_target_h_payto,
  struct GNUNET_TIME_Timestamp deadline)
{
  struct ImportMissingWireContext *wc = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (wc->err < 0)
    return; /* already failed */
  GNUNET_assert (batch_deposit_serial_id > wc->max_batch_deposit_uuid);
  wc->max_batch_deposit_uuid = batch_deposit_serial_id;
  qs = TALER_ARL_adb->insert_pending_deposit (
    TALER_ARL_adb->cls,
    batch_deposit_serial_id,
    wire_target_h_payto,
    total_amount,
    deadline);
  if (qs < 0)
    wc->err = qs;
}


/**
 * Closure for #clear_finished_transfer_cb().
 */
struct AggregationContext
{
  /**
   * Set to maximum row ID encountered.
   */
  uint64_t max_aggregation_serial;

  /**
   * Set to database errors in callback.
   */
  enum GNUNET_DB_QueryStatus err;
};


/**
 * Function called on aggregations that were done for
 * a (batch) deposit.
 *
 * @param cls closure
 * @param tracking_serial_id where in the table are we
 * @param batch_deposit_serial_id which batch deposit was aggregated
 */
static void
clear_finished_transfer_cb (
  void *cls,
  uint64_t tracking_serial_id,
  uint64_t batch_deposit_serial_id)
{
  struct AggregationContext *ac = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (0 > ac->err)
    return; /* already failed */
  GNUNET_assert (ac->max_aggregation_serial < tracking_serial_id);
  ac->max_aggregation_serial = tracking_serial_id + 1;
  qs = TALER_ARL_adb->delete_pending_deposit (
    TALER_ARL_adb->cls,
    batch_deposit_serial_id);
  if (0 == qs)
  {
    /* Aggregated something twice or other error, report! */
    GNUNET_break (0);
    // FIXME: report more nicely!
  }
  if (0 > qs)
    ac->err = qs;
}


/**
 * Checks for wire transfers that should have happened.
 *
 * @return false on failure
 */
static bool
check_for_required_transfers (void)
{
  enum GNUNET_DB_QueryStatus qs;
  struct ImportMissingWireContext wc = {
    .max_batch_deposit_uuid = TALER_ARL_USE_PP (wire_batch_deposit_id),
    .err = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
  };

  qs = TALER_ARL_edb->select_batch_deposits_missing_wire (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (wire_batch_deposit_id),
    &import_wire_missing_cb,
    &wc);
  if ((0 > qs) || (0 > wc.err))
  {
    GNUNET_break (0);
    GNUNET_break ((GNUNET_DB_STATUS_SOFT_ERROR == qs) ||
                  (GNUNET_DB_STATUS_SOFT_ERROR == wc.err));
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return false;
  }
  TALER_ARL_USE_PP (wire_batch_deposit_id) = wc.max_batch_deposit_uuid;
  return true;
}


/**
 * Checks that all wire transfers that should have happened
 * (based on deposits) have indeed happened.
 *
 * @return false on failure
 */
static bool
check_for_completed_transfers (void)
{
  struct AggregationContext ac = {
    .max_aggregation_serial = TALER_ARL_USE_PP (wire_aggregation_id),
    .err = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
  };
  enum GNUNET_DB_QueryStatus qs;

  qs = TALER_ARL_edb->select_aggregations_above_serial (
    TALER_ARL_edb->cls,
    TALER_ARL_USE_PP (wire_aggregation_id),
    &clear_finished_transfer_cb,
    &ac);
  if ( (0 > qs) || (0 > ac.err) )
  {
    GNUNET_break (0);
    GNUNET_break ((GNUNET_DB_STATUS_SOFT_ERROR == qs) ||
                  (GNUNET_DB_STATUS_SOFT_ERROR == ac.err));
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return false;
  }
  TALER_ARL_USE_PP (wire_aggregation_id) = ac.max_aggregation_serial;
  return true;
}


/**
 * Start the database transactions and begin the audit.
 *
 * @return true on success
 */
static bool
begin_transaction (void)
{
  enum GNUNET_DB_QueryStatus qs;

  if (GNUNET_SYSERR ==
      TALER_ARL_edb->preflight (TALER_ARL_edb->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize exchange database connection.\n");
    return false;
  }
  if (GNUNET_SYSERR ==
      TALER_ARL_adb->preflight (TALER_ARL_adb->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to initialize auditor database session.\n");
    return false;
  }
  global_qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  if (GNUNET_OK !=
      TALER_ARL_adb->start (TALER_ARL_adb->cls))
  {
    GNUNET_break (0);
    return false;
  }
  TALER_ARL_edb->preflight (TALER_ARL_edb->cls);
  if (GNUNET_OK !=
      TALER_ARL_edb->start (TALER_ARL_edb->cls,
                            "transfer auditor"))
  {
    GNUNET_break (0);
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    return false;
  }
  qs = TALER_ARL_adb->get_auditor_progress (
    TALER_ARL_adb->cls,
    TALER_ARL_GET_PP (wire_batch_deposit_id),
    TALER_ARL_GET_PP (wire_aggregation_id),
    NULL);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    TALER_ARL_adb->rollback (TALER_ARL_adb->cls);
    TALER_ARL_edb->rollback (TALER_ARL_edb->cls);
    return false;
  }

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "First analysis of with transfer auditor, starting audit from scratch\n");
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Resuming transfer audit at %llu / %llu\n",
                (unsigned long long) TALER_ARL_USE_PP (wire_batch_deposit_id),
                (unsigned long long) TALER_ARL_USE_PP (wire_aggregation_id));
  }

  {
    bool ok;

    ok = check_for_required_transfers ();
    if (ok)
      ok = check_for_completed_transfers ();
    commit_transaction (global_qs);
    if (test_mode)
    {
      GNUNET_SCHEDULER_shutdown ();
      return ok;
    }
    return ok;
  }
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
              "Received notification to wake transfer helper\n");
  if (! begin_transaction ())
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Audit failed\n");
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
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
      TALER_ARL_init (c))
  {
    global_ret = EXIT_FAILURE;
    return;
  }
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_load_accounts (TALER_ARL_cfg,
                                      TALER_EXCHANGEDB_ALO_DEBIT
                                      | TALER_EXCHANGEDB_ALO_CREDIT
                                      | TALER_EXCHANGEDB_ALO_AUTHDATA))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "No bank accounts configured\n");
    global_ret = EXIT_NOTCONFIGURED;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  if (0 == test_mode)
  {
    // FIXME: use different event type in the future!
    struct GNUNET_DB_EventHeaderP es = {
      .size = htons (sizeof (es)),
      .type = htons (TALER_DBEVENT_EXCHANGE_AUDITOR_WAKE_HELPER_WIRE)
    };

    eh = TALER_ARL_adb->event_listen (TALER_ARL_adb->cls,
                                      &es,
                                      GNUNET_TIME_UNIT_FOREVER_REL,
                                      &db_notify,
                                      NULL);
    GNUNET_assert (NULL != eh);
  }
  if (! begin_transaction ())
  {
    GNUNET_break (0);
    global_ret = EXIT_FAILURE;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
}


/**
 * The main function of the wire auditing tool. Checks that
 * the exchange's records of wire transfers match that of
 * the wire gateway.
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
    "taler-helper-auditor-transfer",
    gettext_noop (
      "Audit exchange database for consistency of transfers with respect to deposit deadlines"),
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


/* end of taler-helper-auditor-transfer.c */
