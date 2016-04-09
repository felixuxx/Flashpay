/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V. & Inria

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
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_wire_plugin.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"

/* only for HTTP status codes */
#include <microhttpd.h>

/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct TestClosure
{

  /**
   * Handle to the bank for sending funds to the bank.
   */
  struct TALER_BANK_Context *bank;

  /**
   * Which currency do we support?
   */
  char *currency;

  /**
   * Number of the account that the exchange has at the bank for outgoing
   * transfers.
   */
  unsigned long long exchange_account_outgoing_no;

  /**
   * Handle to the bank task, or NULL.
   */
  struct GNUNET_SCHEDULER_Task *bt;

};


/**
 * Handle returned by #test_prepare_wire_transfer.
 */
struct TALER_WIRE_PrepareHandle
{

  /**
   * Task we use for async execution.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * Test closure we run in.
   */
  struct TestClosure *tc;

  /**
   * Wire data for the transfer.
   */
  json_t *wire;

  /**
   * Function to call with the serialized data.
   */
  TALER_WIRE_PrepareTransactionCallback ptc;

  /**
   * Closure for @e ptc.
   */
  void *ptc_cls;

  /**
   * Amount to transfer.
   */
  struct TALER_Amount amount;

  /**
   * Subject of the wire transfer.
   */
  struct TALER_WireTransferIdentifierRawP wtid;


};


/**
 * Handle returned by #test_execute_wire_transfer.
 */
struct TALER_WIRE_ExecuteHandle
{

  /**
   * Handle to the HTTP request to the bank.
   */
  struct TALER_BANK_AdminAddIncomingHandle *aaih;

  /**
   * Function to call with the result.
   */
  TALER_WIRE_ConfirmationCallback cc;

  /**
   * Closure for @e cc.
   */
  void *cc_cls;
};


/**
 * Task that runs the bank's context's event loop with the GNUnet
 * scheduler.
 *
 * @param cls our `struct TestClosure`
 */
static void
context_task (void *cls)
{
  struct TestClosure *tc = cls;
  long timeout;
  int max_fd;
  fd_set read_fd_set;
  fd_set write_fd_set;
  fd_set except_fd_set;
  struct GNUNET_NETWORK_FDSet *rs;
  struct GNUNET_NETWORK_FDSet *ws;
  struct GNUNET_TIME_Relative delay;

  tc->bt = NULL;
  TALER_BANK_perform (tc->bank);
  max_fd = -1;
  timeout = -1;
  FD_ZERO (&read_fd_set);
  FD_ZERO (&write_fd_set);
  FD_ZERO (&except_fd_set);
  TALER_BANK_get_select_info (tc->bank,
                              &read_fd_set,
                              &write_fd_set,
                              &except_fd_set,
                              &max_fd,
                              &timeout);
  if (timeout >= 0)
    delay = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                           timeout);
  else
    delay = GNUNET_TIME_UNIT_FOREVER_REL;
  rs = GNUNET_NETWORK_fdset_create ();
  GNUNET_NETWORK_fdset_copy_native (rs,
                                    &read_fd_set,
                                    max_fd + 1);
  ws = GNUNET_NETWORK_fdset_create ();
  GNUNET_NETWORK_fdset_copy_native (ws,
                                    &write_fd_set,
                                    max_fd + 1);
  tc->bt = GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_DEFAULT,
                                        delay,
                                        rs,
                                        ws,
                                        &context_task,
                                        tc);
  GNUNET_NETWORK_fdset_destroy (rs);
  GNUNET_NETWORK_fdset_destroy (ws);
}


/**
 * Run the bank task now.
 *
 * @param tc context for which we should initiate running the task
 */
static void
run_bt (struct TestClosure *tc)
{
  if (NULL != tc->bt)
    GNUNET_SCHEDULER_cancel (tc->bt);
  tc->bt = GNUNET_SCHEDULER_add_now (&context_task,
                                     tc);
}


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

  if (NULL == tc->currency)
    return GNUNET_SYSERR; /* not configured with currency */
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
 * Obtain wire transfer details in the plugin-specific format
 * from the configuration.
 *
 * @param cls closure
 * @param cfg configuration with details about wire accounts
 * @param account_name which section in the configuration should we parse
 * @return NULL if @a cfg fails to have valid wire details for @a account_name
 */
static json_t *
test_get_wire_details (void *cls,
                       const struct GNUNET_CONFIGURATION_Handle *cfg,
                       const char *account_name)
{
  json_t *ret;
  char *bank_uri;
  unsigned long long account_number;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
					     account_name,
					     "BANK_URI",
					     &bank_uri))
  {
    /* oopsie, configuration error */
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               account_name,
                               "BANK_URI");
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
					     account_name,
					     "BANK_ACCOUNT_NUMBER",
					     &account_number))
  {
    /* oopsie, configuration error */
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               account_name,
                               "BANK_ACCOUNT_NUMBER");
    GNUNET_free (bank_uri);
    return NULL;
  }
  ret = json_pack ("{s:s, s:I, s:s}",
                   "type", "test",
                   "account_number", (json_int_t) account_number,
                   "bank_uri", bank_uri);
  GNUNET_free (bank_uri);
  return ret;
}


/**
 * Compute purpose for signing.
 *
 * @param account number of the account
 * @param bank_uri URI of the bank
 * @param[out] mp purpose to be signed
 */
static void
compute_purpose (uint64_t account,
                 const char *bank_uri,
                 struct TALER_MasterWireDetailsPS *wsd)
{
  struct GNUNET_HashContext *hc;
  uint64_t n = GNUNET_htonll (account);

  wsd->purpose.size = htonl (sizeof (struct TALER_MasterWireDetailsPS));
  wsd->purpose.purpose = htonl (TALER_SIGNATURE_MASTER_TEST_DETAILS);
  hc = GNUNET_CRYPTO_hash_context_start ();
  GNUNET_CRYPTO_hash_context_read (hc,
				   "test",
				   strlen ("test") + 1);
  GNUNET_CRYPTO_hash_context_read (hc,
				   &n,
                                   sizeof (n));
  GNUNET_CRYPTO_hash_context_read (hc,
				   bank_uri,
				   strlen (bank_uri) + 1);
  GNUNET_CRYPTO_hash_context_finish (hc,
				     &wsd->h_sepa_details);
}


/**
 * Check if the given wire format JSON object is correctly formatted.
 * Right now, the only thing we require is a field
 * "account_number" which must contain a positive 53-bit integer.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wire the JSON wire format object
 * @param master_pub public key of the exchange to verify against
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
static int
test_wire_validate (void *cls,
                    const json_t *wire,
                    const struct TALER_MasterPublicKeyP *master_pub)
{
  json_error_t error;
  json_int_t account_no;

  if (0 !=
      json_unpack_ex ((json_t *) wire,
		      &error,
		      0,
		      "{s:I}",
		      "account_number", &account_no))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if ( (account_no < 0) ||
       (account_no > (1LL << 53)) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* FIXME: should check signature here in the future!
     (note: right now the sig is not properly provided
     by the exchange due to the way account data is
     specified in the configuration) */
  return GNUNET_YES;
}


GNUNET_NETWORK_STRUCT_BEGIN
/**
 * Format we used for serialized transaction data.
 */
struct BufFormatP
{

  /**
   * The wire transfer identifier.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * The amount.
   */
  struct TALER_AmountNBO amount;

  /* followed by serialized 'wire' JSON data */

};
GNUNET_NETWORK_STRUCT_END


/**
 * Prepare for exeuction of a wire transfer.  Calls the
 * callback with the serialized state.
 *
 * @param cls the `struct TALER_WIRE_PrepareHandle`
 */
static void
do_prepare (void *cls)
{
  struct TALER_WIRE_PrepareHandle *pth = cls;
  char *wire_enc;
  size_t len;
  struct BufFormatP bf;

  pth->task = NULL;
  /* serialize the state into a 'buf' */
  wire_enc = json_dumps (pth->wire,
                         JSON_COMPACT | JSON_SORT_KEYS);
  if (NULL == wire_enc)
  {
    GNUNET_break (0);
    pth->ptc (pth->ptc_cls,
              NULL,
              0);
    GNUNET_free (pth);
    return;
  }
  len = strlen (wire_enc) + 1;
  bf.wtid = pth->wtid;
  TALER_amount_hton (&bf.amount,
                     &pth->amount);
  {
    char buf[sizeof (struct BufFormatP) + len];

    memcpy (buf,
            &bf,
            sizeof (struct BufFormatP));
    memcpy (&buf[sizeof (struct BufFormatP)],
            wire_enc,
            len);

    /* finally give the state back */
    pth->ptc (pth->ptc_cls,
              buf,
              sizeof (buf));
  }
  free (wire_enc); /* not using GNUNET_free(),
                      as this one is allocated by libjansson */
  GNUNET_free (pth);
}


/**
 * Prepare for exeuction of a wire transfer.  Note that we should call
 * @a ptc asynchronously (as that is what the API requires, because
 * some transfer methods need it).  So while we could immediately call
 * @a ptc, we first bundle up all the data and schedule a task to do
 * the work.
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
  struct TestClosure *tc = cls;
  struct TALER_WIRE_PrepareHandle *pth;

  if (GNUNET_YES !=
      test_wire_validate (cls,
                          wire,
                          NULL))
  {
    GNUNET_break (0);
    return NULL;
  }
  pth = GNUNET_new (struct TALER_WIRE_PrepareHandle);
  pth->tc = tc;
  pth->wire = (json_t *) wire;
  json_incref (pth->wire);
  pth->wtid = *wtid;
  pth->ptc = ptc;
  pth->ptc_cls = ptc_cls;
  pth->amount = *amount;
  pth->task = GNUNET_SCHEDULER_add_now (&do_prepare,
                                        pth);
  return pth;
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
  GNUNET_SCHEDULER_cancel (pth->task);
  json_decref (pth->wire);
  GNUNET_free (pth);
}


/**
 * Called with the result of submitting information about an incoming
 * transaction to a bank.
 *
 * @param cls closure with the `struct TALER_WIRE_ExecuteHandle`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol)
 * @param json detailed response from the HTTPD, or NULL if reply was not JSON
 */
static void
execute_cb (void *cls,
            unsigned int http_status,
            json_t *json)
{
  struct TALER_WIRE_ExecuteHandle *eh = cls;
  json_t *reason;
  const char *emsg;
  char *s;

  eh->aaih = NULL;
  emsg = NULL;
  if (NULL != json)
  {
    reason = json_object_get (json,
                              "reason");
    if (NULL != reason)
      emsg = json_string_value (reason);
  }
  if (NULL != emsg)
    GNUNET_asprintf (&s,
                     "%u (%s)",
                     http_status,
                     emsg);
  else
    GNUNET_asprintf (&s,
                     "%u",
                     http_status);
  eh->cc (eh->cc_cls,
          (MHD_HTTP_OK == http_status) ? GNUNET_OK : GNUNET_SYSERR,
          (MHD_HTTP_OK == http_status) ? NULL : s);
  GNUNET_free (s);
  GNUNET_free (eh);
}


/**
 * Sign wire transfer details in the plugin-specific format.
 *
 * @param cls closure
 * @param in wire transfer details in JSON format
 * @param key private signing key to use
 * @param salt salt to add
 * @param[out] sig where to write the signature
 * @return #GNUNET_OK on success
 */
static int
test_sign_wire_details (void *cls,
                        const json_t *in,
                        const struct TALER_MasterPrivateKeyP *key,
                        const struct GNUNET_HashCode *salt,
                        struct TALER_MasterSignatureP *sig)
{
  struct TALER_MasterWireDetailsPS wsd;
  const char *bank_uri;
  const char *type;
  json_int_t account;
  json_error_t err;

  if (0 !=
      json_unpack_ex ((json_t *) in,
                      &err,
                      0 /* flags */,
                      "{s:s, s:s, s:I}",
                      "type", &type,
                      "bank_uri", &bank_uri,
                      "account_number", &account))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to unpack JSON: %s (at %u)\n",
                err.text,
                err.position);
    return GNUNET_SYSERR;
  }
  if (0 != strcmp (type,
                   "test"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "`type' must be `test' for test wire details\n");
    return GNUNET_SYSERR;
  }
  compute_purpose (account,
                   bank_uri,
                   &wsd);
  GNUNET_CRYPTO_eddsa_sign (&key->eddsa_priv,
			    &wsd.purpose,
			    &sig->eddsa_signature);
  return GNUNET_OK;
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
  struct TestClosure *tc = cls;
  struct TALER_WIRE_ExecuteHandle *eh;
  json_t *wire;
  json_error_t error;
  struct TALER_Amount amount;
  json_int_t account_no;
  struct BufFormatP bf;

  if (NULL == tc->bank)
    return NULL; /* not initialized with configuration, cannot do transfers */
  if ( (buf_size <= sizeof (struct BufFormatP)) ||
       ('\0' != buf[buf_size -1]) )
  {
    GNUNET_break (0);
    return NULL;
  }
  memcpy (&bf,
          buf,
          sizeof (bf));
  TALER_amount_ntoh (&amount,
                     &bf.amount);
  wire = json_loads (&buf[sizeof (struct BufFormatP)],
                     JSON_REJECT_DUPLICATES,
                     NULL);
  if (NULL == wire)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (GNUNET_YES ==
                 test_wire_validate (NULL,
                                     wire,
                                     NULL));
  if (0 !=
      json_unpack_ex (wire,
		      &error,
		      0,
		      "{s:I}",
		      "account_number", &account_no))
  {
    GNUNET_break (0);
    return NULL;
  }

  eh = GNUNET_new (struct TALER_WIRE_ExecuteHandle);
  eh->cc = cc;
  eh->cc_cls = cc_cls;
  eh->aaih = TALER_BANK_admin_add_incoming (tc->bank,
                                            &bf.wtid,
                                            &amount,
                                            (uint64_t) tc->exchange_account_outgoing_no,
					    (uint64_t) account_no,
                                            &execute_cb,
                                            eh);
  json_decref (wire);
  if (NULL == eh->aaih)
  {
    GNUNET_break (0);
    GNUNET_free (eh);
    return NULL;
  }
  run_bt (tc);
  return eh;
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
  TALER_BANK_admin_add_incoming_cancel (eh->aaih);
  GNUNET_free (eh);
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
  char *uri;

  tc = GNUNET_new (struct TestClosure);
  if (NULL != cfg)
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "wire-outgoing-test",
                                               "BANK_URI",
                                               &uri))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "wire-outgoing-test",
                                 "BANK_URI");
      GNUNET_free (tc);
      return NULL;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_number (cfg,
                                               "wire-outgoing-test",
                                               "BANK_ACCOUNT_NUMBER",
                                               &tc->exchange_account_outgoing_no))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "wire-incoming-test",
                                 "BANK_ACCOUNT_NUMBER");
      GNUNET_free (uri);
      GNUNET_free (tc);
      return NULL;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "CURRENCY",
                                               &tc->currency))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "CURRENCY");
      GNUNET_free (uri);
      GNUNET_free (tc);
      return NULL;
    }
    tc->bank = TALER_BANK_init (uri);
    GNUNET_free (uri);
    if (NULL == tc->bank)
    {
      GNUNET_break (0);
      GNUNET_free (tc->currency);
      GNUNET_free (tc);
      return NULL;
    }
  }
  plugin = GNUNET_new (struct TALER_WIRE_Plugin);
  plugin->cls = tc;
  plugin->amount_round = &test_amount_round;
  plugin->get_wire_details = &test_get_wire_details;
  plugin->sign_wire_details = &test_sign_wire_details;
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

  if (NULL != tc->bt)
  {
    GNUNET_SCHEDULER_cancel (tc->bt);
    tc->bt = NULL;
  }
  if (NULL != tc->bank)
  {
    TALER_BANK_fini (tc->bank);
    tc->bank = NULL;
  }
  GNUNET_free_non_null (tc->currency);
  GNUNET_free (tc);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_wire_test.c */
