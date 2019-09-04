/*
  This file is part of TALER
  (C) 2015-2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file wire/test_wire_plugin_legacy_taler-bank.c
 * @brief Tests legacy history-range API against the Fakebank.
 *        Version for the real Python bank forthcoming.
 *
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"
#include "taler_wire_plugin.h"
#include "taler_fakebank_lib.h"
#include <gnunet/gnunet_json_lib.h>

/**
 * How many wire transfers this test should accomplish, before
 * delving into actual checks.
 */
#define NTRANSACTIONS 5

/**
 * Destination account to use.
 */
static const char *dest_account = "payto://x-taler-bank/localhost:8088/42";

/**
 * Origin account, section in the configuration file.
 */
static const char *my_account = "account-test";

/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Set to #GNUNET_SYSERR if the test failed.
 */
static int global_ret;

/**
 * The 'test' plugin that we are using for the test.
 */
static struct TALER_WIRE_Plugin *plugin;

/**
 * Active preparation handle, or NULL if not active.
 */
static struct TALER_WIRE_PrepareHandle *ph;

/**
 * Active execution handle, or NULL if not active.
 */
static struct TALER_WIRE_ExecuteHandle *eh;

/**
 * Handle to the bank.
 */
static struct TALER_FAKEBANK_Handle *fb;

/**
 * Handle to the history-range request (the "legacy" bank API).
 */
static struct TALER_WIRE_HistoryHandle *hhr;

/**
 * Wire transfer identifier we are using.
 */
static struct TALER_WireTransferIdentifierRawP wtid;

/**
 * Number of total transaction to make it happen in the test.
 */
static int Ntransactions = NTRANSACTIONS;
static int ntransactions = NTRANSACTIONS;
static int ztransactions = 0;

/**
 * Timestamp used as the oldest extreme in the query range.
 */
static struct GNUNET_TIME_Absolute first_timestamp;

/**
 * Function called on shutdown (regular, error or CTRL-C).
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  TALER_FAKEBANK_stop (fb);
  fb = NULL;
  if (NULL != eh)
  {
    plugin->execute_wire_transfer_cancel (plugin->cls,
                                          eh);
    eh = NULL;
  }
  if (NULL != ph)
  {
    plugin->prepare_wire_transfer_cancel (plugin->cls,
                                          ph);
    ph = NULL;
  }

  if (NULL != hhr)
  {
    plugin->get_history_cancel (plugin->cls,
                                hhr);
    hhr = NULL;
  }

  TALER_WIRE_plugin_unload (plugin);
}


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank for the transaction history.
 *
 * @param cls closure
 * @param ec taler status code
 * @param dir direction of the transfer
 * @param row_off identification of the position at
 *        which we are querying
 * @param row_off_size number of bytes in @a row_off
 * @param details details about the wire transfer
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to
 *         abort iteration
 */
static int
history_result_cb
  (void *cls,
   enum TALER_ErrorCode ec,
   enum TALER_BANK_Direction dir,
   const void *row_off,
   size_t row_off_size,
   const struct TALER_WIRE_TransferDetails *details)
{
  int *expected_number = cls;
  static int accumulator = 0;

  if ( (TALER_BANK_DIRECTION_NONE == dir) &&
       (GNUNET_OK == global_ret) )
  {
    /* End-of-list, check all the transactions got accounted
     * into the history.  */
    
    if (*expected_number != accumulator)
    {
      GNUNET_break (0); 
      TALER_LOG_ERROR
        ("Unexpected # of transactions: %d, %d were expected.\n",
         accumulator,
         *expected_number);
      global_ret = GNUNET_NO; 
    }

   if (ztransactions != *expected_number)
   {
     /* Call the second test, under the assumption that after
      * running the test with ztransactions expected entries,
      * we shut the test down.  */

     accumulator = 0;
     GNUNET_assert
       (NULL != (hhr = plugin->get_history_range
         (plugin->cls,
          my_account,
          TALER_BANK_DIRECTION_BOTH,
          GNUNET_TIME_UNIT_ZERO_ABS,
          GNUNET_TIME_absolute_subtract
            (first_timestamp,
             GNUNET_TIME_UNIT_HOURS),
          &history_result_cb,

          /**
           * Zero results are expected from 1970 up to 1 hour ago.
           */
          &ztransactions)));

     return GNUNET_OK;
   }

    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_OK;
  }

  accumulator++;
  return GNUNET_OK;
}


/**
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param success #GNUNET_OK on success,
 *        #GNUNET_SYSERR on failure
 * @param row_id ID of the fresh transaction,
 *        in _network_ byte order.
 * @param emsg NULL on success, otherwise an error message
 */
static void
confirmation_cb (void *cls,
                 int success,
                 const void *row_id,
                 size_t row_id_size,
                 const char *emsg);

/**
 * Callback with prepared transaction.
 *
 * @param cls closure
 * @param buf transaction data to persist, NULL on error
 * @param buf_size number of bytes in @a buf, 0 on error
 */
static void
prepare_cb (void *cls,
            const char *buf,
            size_t buf_size)
{
  ph = NULL;
  if (NULL == buf)
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  plugin->execute_wire_transfer (plugin->cls,
                                 buf,
                                 buf_size,
                                 &confirmation_cb,
                                 NULL);
}

/**
 * Function called with the result from the execute step.
 *
 * @param cls closure
 * @param success #GNUNET_OK on success,
 *        #GNUNET_SYSERR on failure
 * @param row_id ID of the fresh transaction,
 *        in _network_ byte order.
 * @param emsg NULL on success, otherwise an error message
 */
static void
confirmation_cb (void *cls,
                 int success,
                 const void *row_id,
                 size_t row_id_size,
                 const char *emsg)
{
  struct TALER_Amount amount;

  eh = NULL;
  if (GNUNET_OK != success)
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }

  if (0 >= --Ntransactions)
  {
    GNUNET_assert
      (NULL != (hhr = plugin->get_history_range
         (plugin->cls,
          my_account,
          TALER_BANK_DIRECTION_BOTH,
          GNUNET_TIME_UNIT_ZERO_ABS,
          GNUNET_TIME_UNIT_FOREVER_ABS,
          &history_result_cb,
          &ntransactions)));
    return;
  }

  /* Issue a new wire transfer!  */
  GNUNET_assert
    (GNUNET_OK == TALER_string_to_amount ("KUDOS:5.01",
                                          &amount));

  ph = plugin->prepare_wire_transfer (plugin->cls,
                                      my_account,
                                      dest_account,
                                      &amount,
                                      "https://exchange.net/",
                                      &wtid,
                                      &prepare_cb,
                                      NULL);
}


/**
 * Run the test.
 *
 * @param cls NULL
 */
static void
run (void *cls)
{
  struct TALER_Amount amount;
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &wtid,
                              sizeof (wtid));
  GNUNET_assert
    (GNUNET_OK == TALER_string_to_amount ("KUDOS:5.01",
                                          &amount));
  fb = TALER_FAKEBANK_start (8088);


  first_timestamp = GNUNET_TIME_absolute_get ();
  ph = plugin->prepare_wire_transfer (plugin->cls,
                                      my_account,
                                      dest_account,
                                      &amount,
                                      "https://exchange.net/",
                                      &wtid,
                                      &prepare_cb,
                                      NULL);
}


int
main (int argc,
      const char *const argv[])
{
  GNUNET_log_setup ("test-wire-plugin-legacy-test",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_assert
    (GNUNET_OK == GNUNET_CONFIGURATION_load
      (cfg,
       "test_wire_plugin_legacy_taler-bank.conf"));
  global_ret = GNUNET_OK;
  plugin = TALER_WIRE_plugin_load (cfg,
                                   "taler_bank");
  GNUNET_assert (NULL != plugin);
  GNUNET_SCHEDULER_run (&run,
                        NULL);
  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_OK != global_ret)
    return 1;
  return 0;
}

/* end of test_wire_plugin_legacy_taler-bank.c */
