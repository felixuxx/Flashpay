/*
  This file is part of TALER
  Copyright (C) 2016, 2018 GNUnet e.V.

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
 * @file plugin_wire_template.c
 * @brief template for wire plugins; replace "template" with real plugin name!
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
struct TemplateClosure
{

  /**
   * Which currency do we support?
   */
  char *currency;

  /**
   * Which configuration do we use to lookup accounts?
   */
  struct GNUNET_CONFIGURATION_Handle *cfg;

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
template_amount_round (void *cls,
                       struct TALER_Amount *amount)
{
  struct TemplateClosure *tc = cls;

  if (0 != strcasecmp (amount->currency,
                       tc->currency))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_break (0); // not implemented
  return GNUNET_SYSERR;
}


/**
 * Check if the given payto:// URL is correctly formatted for this plugin
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_url the payto:// URL
 * @return #TALER_EC_NONE if correctly formatted
 */
static enum TALER_ErrorCode
template_wire_validate (void *cls,
                        const char *account_url)
{
  (void) cls;
  (void) account_url;
  GNUNET_break (0);
  return TALER_EC_NOT_IMPLEMENTED;
}


/**
 * Prepare for exeuction of a wire transfer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param origin_account_section configuration section specifying the origin
 *        account of the exchange to use
 * @param destination_account_url payto:// URL identifying where to send the money
 * @param amount amount to transfer, already rounded
 * @param exchange_base_url base URL of the exchange (for tracking)
 * @param wtid wire transfer identifier to use
 * @param ptc function to call with the prepared data to persist
 * @param ptc_cls closure for @a ptc
 * @return NULL on failure
 */
static struct TALER_WIRE_PrepareHandle *
template_prepare_wire_transfer (void *cls,
                                const char *origin_account_section,
                                const char *destination_account_url,
                                const struct TALER_Amount *amount,
                                const char *exchange_base_url,
                                const struct
                                TALER_WireTransferIdentifierRawP *wtid,
                                TALER_WIRE_PrepareTransactionCallback ptc,
                                void *ptc_cls)
{
  (void) cls;
  (void) origin_account_section;
  (void) destination_account_url;
  (void) amount;
  (void) exchange_base_url;
  (void) wtid;
  (void) ptc;
  (void) ptc_cls;
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
template_prepare_wire_transfer_cancel (void *cls,
                                       struct TALER_WIRE_PrepareHandle *pth)
{
  (void) cls;
  (void) pth;
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
template_execute_wire_transfer (void *cls,
                                const char *buf,
                                size_t buf_size,
                                TALER_WIRE_ConfirmationCallback cc,
                                void *cc_cls)
{
  (void) cls;
  (void) buf;
  (void) buf_size;
  (void) cc;
  (void) cc_cls;
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
template_execute_wire_transfer_cancel (void *cls,
                                       struct TALER_WIRE_ExecuteHandle *eh)
{
  (void) cls;
  (void) eh;
  GNUNET_break (0);
}


/**
 * Query transfer history of an account.  We use the variable-size
 * @a start_off to indicate which transfers we are interested in as
 * different banking systems may have different ways to identify
 * transfers.  The @a start_off value must thus match the value of
 * a `row_off` argument previously given to the @a hres_cb.  Use
 * NULL to query transfers from the beginning of time (with
 * positive @a num_results) or from the latest committed transfers
 * (with negative @a num_results).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_section specifies the configuration section which
 *        identifies the account for which we should get the history
 * @param direction what kinds of wire transfers should be returned
 * @param start_off from which row on do we want to get results, use NULL for the latest; exclusive
 * @param start_off_len number of bytes in @a start_off; must be `sizeof(uint64_t)`.
 * @param num_results how many results do we want; negative numbers to go into the past,
 *                    positive numbers to go into the future starting at @a start_row;
 *                    must not be zero.
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 */
static struct TALER_WIRE_HistoryHandle *
template_get_history (void *cls,
                      const char *account_section,
                      enum TALER_BANK_Direction direction,
                      const void *start_off,
                      size_t start_off_len,
                      int64_t num_results,
                      TALER_WIRE_HistoryResultCallback hres_cb,
                      void *hres_cb_cls)
{
  (void) cls;
  (void) account_section;
  (void) direction;
  (void) start_off;
  (void) start_off_len;
  (void) num_results;
  (void) hres_cb;
  (void) hres_cb_cls;
  GNUNET_break (0);
  return NULL;
}


/**
 * Cancel going over the account's history.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param whh operation to cancel
 */
static void
template_get_history_cancel (void *cls,
                             struct TALER_WIRE_HistoryHandle *whh)
{
  (void) cls;
  (void) whh;
  GNUNET_break (0);
}


/**
 * Reject an incoming wire transfer that was obtained from the
 * history. This function can be used to transfer funds back to
 * the sender if the WTID was malformed (i.e. due to a typo).
 *
 * Calling `reject_transfer` twice on the same wire transfer should
 * be idempotent, i.e. not cause the funds to be wired back twice.
 * Furthermore, the transfer should henceforth be removed from the
 * results returned by @e get_history.
 *
 * @param cls plugin's closure
 * @param account_section specifies the configuration section which
 *        identifies the account to use to reject the transfer
 * @param start_off offset of the wire transfer in plugin-specific format
 * @param start_off_len number of bytes in @a start_off
 * @param rej_cb function to call with the result of the operation
 * @param rej_cb_cls closure for @a rej_cb
 * @return handle to cancel the operation
 */
static struct TALER_WIRE_RejectHandle *
template_reject_transfer (void *cls,
                          const char *account_section,
                          const void *start_off,
                          size_t start_off_len,
                          TALER_WIRE_RejectTransferCallback rej_cb,
                          void *rej_cb_cls)
{
  (void) cls;
  (void) account_section;
  (void) start_off;
  (void) start_off_len;
  (void) rej_cb;
  (void) rej_cb_cls;
  GNUNET_break (0);
  return NULL;
}


/**
 * Cancel ongoing reject operation.  Note that the rejection may still
 * proceed. Basically, if this function is called, the rejection may
 * have happened or not.  This function is usually used during shutdown
 * or system upgrades.  At a later point, the application must call
 * @e reject_transfer again for this wire transfer, unless the
 * @e get_history shows that the wire transfer no longer exists.
 *
 * @param cls plugins' closure
 * @param rh operation to cancel
 * @return closure of the callback of the operation
 */
static void *
template_reject_transfer_cancel (void *cls,
                                 struct TALER_WIRE_RejectHandle *rh)
{
  (void) cls;
  (void) rh;
  GNUNET_break (0);
  return NULL;
}


/**
 * Initialize template-wire subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_WIRE_Plugin`
 */
void *
libtaler_plugin_wire_template_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TemplateClosure *tc;
  struct TALER_WIRE_Plugin *plugin;

  tc = GNUNET_new (struct TemplateClosure);
  tc->cfg = cfg;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &tc->currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    GNUNET_free (tc);
    return NULL;
  }

  plugin = GNUNET_new (struct TALER_WIRE_Plugin);
  plugin->cls = tc;
  plugin->method = "FIXME-REPLACE-BY-METHOD";
  plugin->amount_round = &template_amount_round;
  plugin->wire_validate = &template_wire_validate;
  plugin->prepare_wire_transfer = &template_prepare_wire_transfer;
  plugin->prepare_wire_transfer_cancel = &template_prepare_wire_transfer_cancel;
  plugin->execute_wire_transfer = &template_execute_wire_transfer;
  plugin->execute_wire_transfer_cancel = &template_execute_wire_transfer_cancel;
  plugin->get_history = &template_get_history;
  plugin->get_history_cancel = &template_get_history_cancel;
  plugin->reject_transfer = &template_reject_transfer;
  plugin->reject_transfer_cancel = &template_reject_transfer_cancel;
  return plugin;
}


/**
 * Shutdown Template wire subsystem.
 *
 * @param cls a `struct TALER_WIRE_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_wire_template_done (void *cls)
{
  struct TALER_WIRE_Plugin *plugin = cls;
  struct TemplateClosure *tc = plugin->cls;

  GNUNET_free (tc->currency);
  GNUNET_free (tc);
  GNUNET_free (plugin);
  return NULL;
}


/* end of plugin_wire_template.c */
