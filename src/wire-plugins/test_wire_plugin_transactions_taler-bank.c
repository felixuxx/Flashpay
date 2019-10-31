/*
  This file is part of TALER
  (C) 2015-2018 Taler Systems SA

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
 * @file wire/test_wire_plugin_transactions_taler-bank.c
 * @brief Tests performing actual transactions with the taler-bank wire plugin against FAKEBANK
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"
#include "taler_wire_plugin.h"
#include "taler_fakebank_lib.h"
#include <gnunet/gnunet_json_lib.h>


/**
 * When does the test timeout? Right now, we expect this to be very
 * fast.
 */
#define TIMEOUT GNUNET_TIME_UNIT_SECONDS


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
 * Handle to the history request.
 */
static struct TALER_WIRE_HistoryHandle *hh;

/**
 * Handle to the history-range request (the "legacy" bank API).
 */
static struct TALER_WIRE_HistoryHandle *hhr;

/**
 * Handle for the timeout task.
 */
static struct GNUNET_SCHEDULER_Task *tt;

/**
 * Which serial ID do we expect to get from /history?
 */
static uint64_t serial_target;

/**
 * Wire transfer identifier we are using.
 */
static struct TALER_WireTransferIdentifierRawP wtid;


/**
 * Function called on shutdown (regular, error or CTRL-C).
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
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
  if (NULL != hh)
  {
    plugin->get_history_cancel (plugin->cls,
                                hh);
    hh = NULL;
  }

  if (NULL != hhr)
  {
    plugin->get_history_cancel (plugin->cls,
                                hhr);
    hhr = NULL;
  }

  if (NULL != tt)
  {
    GNUNET_SCHEDULER_cancel (tt);
    tt = NULL;
  }
  TALER_WIRE_plugin_unload (plugin);
}


/**
 * Function called on timeout.
 *
 * @param cls NULL
 */
static void
timeout_cb (void *cls)
{
  tt = NULL;
  GNUNET_break (0);
  global_ret = GNUNET_SYSERR;
  GNUNET_SCHEDULER_shutdown ();
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
  uint64_t *serialp;
  uint64_t serialh;
  struct TALER_Amount amount;

  if ( (TALER_BANK_DIRECTION_NONE == dir) &&
       (GNUNET_OK == global_ret) )
  {
    GNUNET_SCHEDULER_shutdown ();
    hh = NULL;
    return GNUNET_OK;
  }
  if (sizeof (uint64_t) != row_off_size)
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  serialp = (uint64_t *) row_off;
  serialh = GNUNET_ntohll (*serialp);
  if (serialh != serial_target)
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("KUDOS:5.01",
                                         &amount));
  if (0 != TALER_amount_cmp (&amount,
                             &details->amount))
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  if (0 != GNUNET_memcmp (&wtid,
                          &details->wtid))
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return GNUNET_SYSERR;
  }
  global_ret = GNUNET_OK;
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
                 const char *emsg)
{
  uint64_t tmp;

  eh = NULL;
  if (GNUNET_OK != success)
  {
    GNUNET_break (0);
    global_ret = GNUNET_SYSERR;
    GNUNET_SCHEDULER_shutdown ();
    return;
  }
  memcpy (&tmp,
          row_id,
          row_id_size);
  serial_target = GNUNET_ntohll (tmp);
  hh = plugin->get_history (plugin->cls,
                            my_account,
                            TALER_BANK_DIRECTION_BOTH,
                            NULL,
                            0,
                            5,
                            &history_result_cb,
                            NULL);
}


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
  tt = GNUNET_SCHEDULER_add_delayed (TIMEOUT,
                                     &timeout_cb,
                                     NULL);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &wtid,
                              sizeof (wtid));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("KUDOS:5.01",
                                         &amount));
  fb = TALER_FAKEBANK_start (8088);
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

  GNUNET_log_setup ("test-wire-plugin-transactions-test",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONFIGURATION_load (cfg,
                                            "test_wire_plugin_transactions_taler-bank.conf"));
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


/* end of test_wire_plugin_transactions_taler-bank.c */
