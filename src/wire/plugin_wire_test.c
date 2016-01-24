/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file plugin_wire_test.c
 * @brief plugin for the "test" wire method
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 */
#include "platform.h"
#include "taler_wire_plugin.h"


/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct TestClosure
{

  /**
   * URI of the bank for sending funds to the bank.
   */
  char *bank_uri;

  /**
   * Which currency do we support?
   */
  char *currency;

};


/**
 * Round amount DOWN to the amount that can be transferred via the wire
 * method.  For example, Taler may support 0.000001 EUR as a unit of
 * payment, but SEPA only supports 0.01 EUR.  This function would
 * round 0.125 EUR to 0.12 EUR in this case.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param[in,out] amount amount to round down
 * @return #GNUNET_OK on success, #GNUNET_NO if rounding was unnecessary,
 *         #GNUNET_SYSERR if the amount or currency was invalid
 */
static int
test_amount_round (void *cls,
                   struct TALER_Amount *amount)
{
  struct TestClosure *tc = cls;
  uint32_t delta;

  if (0 != strcasecmp (amount->currency,
                       tc->currency))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* 'test' method supports 1/100 of the unit currency, i.e. 0.01 CUR */
  delta = amount->fraction % (TALER_AMOUNT_FRAC_BASE / 100);
  if (0 == delta)
    return GNUNET_NO;
  amount->fraction -= delta;
  return GNUNET_OK;
}


/**
 * Check if the given wire format JSON object is correctly formatted
 *
 * @param wire the JSON wire format object
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
static int
test_wire_validate (const json_t *wire)
{
  GNUNET_break (0); /* FIXME: we still need to define the
                       proper wire format for 'test' */
  return GNUNET_YES;
}


/**
 * Prepare for exeuction of a wire transfer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wire valid wire account information
 * @param amount amount to transfer, already rounded
 * @param wtid wire transfer identifier to use
 * @param ptc function to call with the prepared data to persist
 * @param ptc_cls closure for @a ptc
 * @return NULL on failure
 */
static struct TALER_WIRE_PrepareHandle *
test_prepare_wire_transfer (void *cls,
                            const json_t *wire,
                            const struct TALER_Amount *amount,
                            const struct TALER_WireTransferIdentifierRawP *wtid,
                            TALER_WIRE_PrepareTransactionCallback ptc,
                            void *ptc_cls)
{
  GNUNET_break (0);
  return NULL;
}


/**
 * Abort preparation of a wire transfer. For example,
 * because we are shutting down.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param pth preparation to cancel
 */
static void
test_prepare_wire_transfer_cancel (void *cls,
                                   struct TALER_WIRE_PrepareHandle *pth)
{
  GNUNET_break (0);
}


/**
 * Execute a wire transfer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param buf buffer with the prepared execution details
 * @param buf_size number of bytes in @a buf
 * @param cc function to call upon success
 * @param cc_cls closure for @a cc
 * @return NULL on error
 */
static struct TALER_WIRE_ExecuteHandle *
test_execute_wire_transfer (void *cls,
                            const char *buf,
                            size_t buf_size,
                            TALER_WIRE_ConfirmationCallback cc,
                            void *cc_cls)
{
  GNUNET_break (0);
  return NULL;
}


/**
 * Abort execution of a wire transfer. For example, because we are
 * shutting down.  Note that if an execution is aborted, it may or
 * may not still succeed. The caller MUST run @e
 * execute_wire_transfer again for the same request as soon as
 * possilbe, to ensure that the request either ultimately succeeds
 * or ultimately fails. Until this has been done, the transaction is
 * in limbo (i.e. may or may not have been committed).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param eh execution to cancel
 */
static void
test_execute_wire_transfer_cancel (void *cls,
                                   struct TALER_WIRE_ExecuteHandle *eh)
{
  GNUNET_break (0);
}


/**
 * Initialize test-wire subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_WIRE_Plugin`
 */
void *
libtaler_plugin_wire_test_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TestClosure *tc;
  struct TALER_WIRE_Plugin *plugin;

  tc = GNUNET_new (struct TestClosure);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "wire-test",
                                             "bank_uri",
                                             &tc->bank_uri))
    {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "wire-test",
                               "bank_uri");
    GNUNET_free (tc);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint",
                                             "CURRENCY",
                                             &tc->currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint",
                               "CURRENCY");
    GNUNET_free (tc->bank_uri);
    GNUNET_free (tc);
    return NULL;
  }

  plugin = GNUNET_new (struct TALER_WIRE_Plugin);
  plugin->cls = tc;
  plugin->amount_round = &test_amount_round;
  plugin->wire_validate = &test_wire_validate;
  plugin->prepare_wire_transfer = &test_prepare_wire_transfer;
  plugin->prepare_wire_transfer_cancel = &test_prepare_wire_transfer_cancel;
  plugin->execute_wire_transfer = &test_execute_wire_transfer;
  plugin->execute_wire_transfer_cancel = &test_execute_wire_transfer_cancel;
  return plugin;
}


/**
 * Shutdown Test wire subsystem.
 *
 * @param cls a `struct TALER_WIRE_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_wire_test_done (void *cls)
{
  struct TALER_WIRE_Plugin *plugin = cls;
  struct TestClosure *tc = plugin->cls;

  GNUNET_free (tc->bank_uri);
  GNUNET_free (tc->currency);
  GNUNET_free (tc);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_wire_test.c */
