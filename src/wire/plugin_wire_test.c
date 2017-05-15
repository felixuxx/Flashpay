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
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
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
#include <gnunet/gnunet_curl_lib.h>

/* only for HTTP status codes */
#include <microhttpd.h>

/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct TestClosure
{

  /**
   * Which currency do we support?
   */
  char *currency;

  /**
   * URI of our bank.
   */
  char *bank_uri;

  /**
   * Authentication information.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Handle to the context for sending funds to the bank.
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * Scheduler context for running the @e ctx.
   */
  struct GNUNET_CURL_RescheduleContext *rc;

  /**
   * Number of the account that the exchange has at the bank for
   * transfers.
   */
  unsigned long long exchange_account_no;

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
   * Base URL to use for the exchange.
   */
  char *exchange_base_url;

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
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    return GNUNET_SYSERR; /* not configured with currency */
  }
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
 * Compute purpose for signing.
 *
 * @param account number of the account
 * @param bank_uri URI of the bank
 * @param[out] wsd purpose to be signed
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
 * @param[out] emsg set to an error message, unless we return #TALER_EC_NONE;
 *             error message must be freed by the caller using GNUNET_free()
 * @return #TALER_EC_NONE if correctly formatted
 */
static enum TALER_ErrorCode
test_wire_validate (void *cls,
                    const json_t *wire,
                    const struct TALER_MasterPublicKeyP *master_pub,
                    char **emsg)
{
  struct TestClosure *tc = cls;
  json_error_t error;
  json_int_t account_no;
  const char *bank_uri;
  const char *sig_s;
  struct TALER_MasterWireDetailsPS wsd;
  struct TALER_MasterSignatureP sig;

  *emsg = NULL;
  if (0 !=
      json_unpack_ex ((json_t *) wire,
		      &error,
		      0,
		      "{s:I, s:s}",
		      "account_number", &account_no,
                      "bank_uri", &bank_uri))
  {
    char *dump;

    dump = json_dumps (wire, 0);
    GNUNET_asprintf (emsg,
                     "JSON parsing failed at %s:%u: %s (%s): %s\n",
                     __FILE__, __LINE__,
                     error.text,
                     error.source,
                     dump);
    free (dump);
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_JSON;
  }
  if ( (account_no < 0) ||
       (account_no > (1LL << 53)) )
  {
    GNUNET_asprintf (emsg,
                     "Account number %llu outside of permitted range\n",
                     account_no);
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_ACCOUNT_NUMBER;
  }
  if ( (NULL != tc->bank_uri) &&
       (0 != strcmp (bank_uri,
                     tc->bank_uri)) )
  {
    GNUNET_asprintf (emsg,
                     "Wire specifies bank URI `%s', but this exchange only supports `%s'\n",
                     bank_uri,
                     tc->bank_uri);
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_BANK;
  }
  if (NULL == master_pub)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Skipping signature check as master public key not given\n");
    return TALER_EC_NONE;
  }
  if (0 !=
      json_unpack_ex ((json_t *) wire,
		      &error,
		      0,
		      "{s:s}",
                      "sig", &sig_s))
  {
    GNUNET_asprintf (emsg,
                     "Signature check required, but signature is missing\n");
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_SIGNATURE;
  }
  compute_purpose (account_no,
                   bank_uri,
                   &wsd);
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (sig_s,
                                     strlen (sig_s),
                                     &sig,
                                     sizeof (sig)))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_TEST_DETAILS,
                                  &wsd.purpose,
                                  &sig.eddsa_signature,
                                  &master_pub->eddsa_pub))
  {
    GNUNET_asprintf (emsg,
                     "Signature using public key `%s' invalid\n",
                     TALER_B2S (master_pub));
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_SIGNATURE;
  }
  return TALER_EC_NONE;
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
  struct TestClosure *tc = cls;
  char *test_wire_file;
  json_error_t err;
  json_t *ret;
  char *emsg;

  /* Fetch reply */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               account_name,
                                               "TEST_RESPONSE_FILE",
                                               &test_wire_file))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               account_name,
                               "TEST_RESPONSE_FILE");
    return NULL;
  }
  ret = json_load_file (test_wire_file,
                        JSON_REJECT_DUPLICATES,
                        &err);
  if (NULL == ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse JSON in %s: %s (%s:%u)\n",
                test_wire_file,
                err.text,
                err.source,
                err.line);
    GNUNET_free (test_wire_file);
    return NULL;
  }
  if (TALER_EC_NONE !=
      test_wire_validate (tc,
                          ret,
                          NULL,
                          &emsg))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to validate TEST wire data in %s: %s\n",
                test_wire_file,
                emsg);
    GNUNET_free (emsg);
    GNUNET_free (test_wire_file);
    json_decref (ret);
    return NULL;
  }
  GNUNET_free (test_wire_file);
  return ret;
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

  /* followed by serialized 'wire' JSON data (0-terminated) */

  /* followed by 0-terminated base URL */

};
GNUNET_NETWORK_STRUCT_END


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
  if (NULL != pth->task)
    GNUNET_SCHEDULER_cancel (pth->task);
  json_decref (pth->wire);
  GNUNET_free (pth->exchange_base_url);
  GNUNET_free (pth);
}


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
  size_t len_w;
  size_t len_b;
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
    test_prepare_wire_transfer_cancel (NULL,
                                       pth);
    return;
  }
  len_w = strlen (wire_enc) + 1;
  len_b = strlen (pth->exchange_base_url) + 1;
  bf.wtid = pth->wtid;
  TALER_amount_hton (&bf.amount,
                     &pth->amount);
  {
    char buf[sizeof (struct BufFormatP) + len_w + len_b];

    memcpy (buf,
            &bf,
            sizeof (struct BufFormatP));
    memcpy (&buf[sizeof (struct BufFormatP)],
            wire_enc,
            len_w);
    memcpy (&buf[sizeof (struct BufFormatP) + len_w],
            pth->exchange_base_url,
            len_b);

    /* finally give the state back */
    pth->ptc (pth->ptc_cls,
              buf,
              sizeof (buf));
  }
  free (wire_enc); /* not using GNUNET_free(),
                      as this one is allocated by libjansson */
  test_prepare_wire_transfer_cancel (NULL,
                                     pth);
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
 * @param exchange_base_url base URL of this exchange
 * @param wtid wire transfer identifier to use
 * @param ptc function to call with the prepared data to persist
 * @param ptc_cls closure for @a ptc
 * @return NULL on failure
 */
static struct TALER_WIRE_PrepareHandle *
test_prepare_wire_transfer (void *cls,
                            const json_t *wire,
                            const struct TALER_Amount *amount,
                            const char *exchange_base_url,
                            const struct TALER_WireTransferIdentifierRawP *wtid,
                            TALER_WIRE_PrepareTransactionCallback ptc,
                            void *ptc_cls)
{
  struct TestClosure *tc = cls;
  struct TALER_WIRE_PrepareHandle *pth;
  char *emsg;

  if (TALER_EC_NONE !=
      test_wire_validate (tc,
                          wire,
                          NULL,
                          &emsg))
  {
    GNUNET_break_op (0);
    GNUNET_free (emsg);
    return NULL;
  }
  pth = GNUNET_new (struct TALER_WIRE_PrepareHandle);
  pth->tc = tc;
  pth->wire = json_incref ((json_t *) wire);
  pth->exchange_base_url = GNUNET_strdup (exchange_base_url);
  pth->wtid = *wtid;
  pth->ptc = ptc;
  pth->ptc_cls = ptc_cls;
  pth->amount = *amount;
  pth->task = GNUNET_SCHEDULER_add_now (&do_prepare,
                                        pth);
  return pth;
}


/**
 * Called with the result of submitting information about an incoming
 * transaction to a bank.
 *
 * @param cls closure with the `struct TALER_WIRE_ExecuteHandle`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol)
 * @param serial_id unique ID of the wire transfer in the bank's records; UINT64_MAX on error
 * @param json detailed response from the HTTPD, or NULL if reply was not JSON
 */
static void
execute_cb (void *cls,
            unsigned int http_status,
            uint64_t serial_id,
            const json_t *json)
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
          serial_id,
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
  char *emsg;
  const char *json_s;
  const char *exchange_base_url;

  if (NULL == tc->ctx)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Bank not initialized, cannot do transfers!\n");
    return NULL; /* not initialized with configuration, cannot do transfers */
  }
  if ( (buf_size <= sizeof (struct BufFormatP)) ||
       ('\0' != buf[buf_size - 1]) )
  {
    GNUNET_break (0);
    return NULL;
  }
  json_s = &buf[sizeof (struct BufFormatP)];
  exchange_base_url = &json_s[strlen (json_s) + 1];
  if (exchange_base_url > &buf[buf_size - 1])
  {
    GNUNET_break (0);
    return NULL;
  }
  memcpy (&bf,
          buf,
          sizeof (bf));
  TALER_amount_ntoh (&amount,
                     &bf.amount);
  wire = json_loads (json_s,
                     JSON_REJECT_DUPLICATES,
                     NULL);
  if (NULL == wire)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (TALER_EC_NONE ==
                 test_wire_validate (tc,
                                     wire,
                                     NULL,
                                     &emsg));
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
  eh->aaih = TALER_BANK_admin_add_incoming (tc->ctx,
                                            tc->bank_uri,
                                            &tc->auth,
                                            exchange_base_url,
                                            &bf.wtid,
                                            &amount,
                                            (uint64_t) tc->exchange_account_no,
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
 * Handle for a #test_get_history() request.
 */
struct TALER_WIRE_HistoryHandle
{

  /**
   * Function to call with results.
   */
  TALER_WIRE_HistoryResultCallback hres_cb;

  /**
   * Closure for @e hres_cb.
   */
  void *hres_cb_cls;

  /**
   * Request to the bank.
   */
  struct TALER_BANK_HistoryHandle *hh;

};


/**
 * Function called with results from the bank about the transaction history.
 *
 * @param cls the `struct TALER_WIRE_HistoryHandle`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param dir direction of the transfer
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
static void
bhist_cb (void *cls,
          unsigned int http_status,
          enum TALER_BANK_Direction dir,
          uint64_t serial_id,
          const struct TALER_BANK_TransferDetails *details,
          const json_t *json)
{
  struct TALER_WIRE_HistoryHandle *whh = cls;
  uint64_t bserial_id = GNUNET_htonll (serial_id);
  struct TALER_WIRE_TransferDetails wd;

  if (MHD_HTTP_OK == http_status)
  {
    char *subject;
    char *space;

    wd.amount = details->amount;
    wd.execution_date = details->execution_date;
    subject = GNUNET_strdup (details->wire_transfer_subject);
    space = strchr (subject, (int) ' ');
    if (NULL != space)
    {
      /* Space separates the actual wire transfer subject from the
         exchange base URL (if present, expected only for outgoing
         transactions).  So we cut the string off at the space. */
      *space = '\0';
    }
    /* NOTE: For a real bank, the subject should include a checksum! */
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (subject,
                                       strlen (subject),
                                       &wd.reserve_pub,
                                       sizeof (wd.reserve_pub)))
    {
      GNUNET_break (0);
      GNUNET_free (subject);
      /* NOTE: for a "real" bank, we would want to trigger logic to undo the
         wire transfer. However, for the "demo" bank, it should currently
         be "impossible" to do wire transfers with invalid subjects, and
         equally we thus don't need to undo them (and there is no API to do
         that nicely either right now). So we don't handle this case for now. */
      return;
    }
    GNUNET_free (subject);
    wd.account_details = details->account_details;

    if ( (NULL != whh->hres_cb) &&
	 (GNUNET_OK !=
	  whh->hres_cb (whh->hres_cb_cls,
			dir,
			&bserial_id,
			sizeof (bserial_id),
			&wd)) )
      whh->hres_cb = NULL;
  }
  else
  {
    (void) whh->hres_cb (whh->hres_cb_cls,
			 TALER_BANK_DIRECTION_NONE,
			 NULL,
			 0,
			 NULL);
    whh->hh = NULL;
    GNUNET_free (whh);
  }
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
test_get_history (void *cls,
                  enum TALER_BANK_Direction direction,
                  const void *start_off,
                  size_t start_off_len,
                  int64_t num_results,
                  TALER_WIRE_HistoryResultCallback hres_cb,
                  void *hres_cb_cls)
{
  struct TestClosure *tc = cls;
  struct TALER_WIRE_HistoryHandle *whh;
  const uint64_t *start_off_b64;
  uint64_t start_row;

  if (0 == num_results)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (TALER_BANK_DIRECTION_NONE == direction)
  {
    GNUNET_break (0);
    return NULL;
  }
  if ( (NULL != start_off) &&
       (sizeof (uint64_t) != start_off_len) )
  {
    GNUNET_break (0);
    return NULL;
  }
  if (NULL == start_off)
  {
    start_row = (num_results > 0) ? 0 : UINT64_MAX;
  }
  else
  {
    start_off_b64 = start_off;
    start_row = GNUNET_ntohll (*start_off_b64);
  }

  whh = GNUNET_new (struct TALER_WIRE_HistoryHandle);
  whh->hres_cb = hres_cb;
  whh->hres_cb_cls = hres_cb_cls;
  whh->hh = TALER_BANK_history (tc->ctx,
                                tc->bank_uri,
                                &tc->auth,
                                (uint64_t) tc->exchange_account_no,
                                direction,
                                start_row,
                                num_results,
                                &bhist_cb,
                                whh);
  if (NULL == whh->hh)
  {
    GNUNET_break (0);
    GNUNET_free (whh);
    return NULL;
  }
  return whh;
}


/**
 * Cancel going over the account's history.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param whh operation to cancel
 */
static void
test_get_history_cancel (void *cls,
			 struct TALER_WIRE_HistoryHandle *whh)
{
  TALER_BANK_history_cancel (whh->hh);
  GNUNET_free (whh);
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
  char *user;
  char *pass;

  tc = GNUNET_new (struct TestClosure);
  if (NULL != cfg)
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange-wire-test",
                                               "BANK_URI",
                                               &tc->bank_uri))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange-wire-test",
                                 "BANK_URI");
      GNUNET_free (tc);
      return NULL;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_number (cfg,
                                               "exchange-wire-test",
                                               "EXCHANGE_ACCOUNT_NUMBER",
                                               &tc->exchange_account_no))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange-wire-test",
                                 "EXCHANGE_ACCOUNT_NUMBER");
      GNUNET_free (tc->bank_uri);
      GNUNET_free (tc);
      return NULL;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "taler",
                                               "CURRENCY",
                                               &tc->currency))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "taler",
                                 "CURRENCY");
      GNUNET_free (tc->bank_uri);
      GNUNET_free (tc);
      return NULL;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange-wire-test",
                                               "USERNAME",
                                               &user))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange-wire-test",
                                 "USERNAME");
      GNUNET_free (tc->bank_uri);
      GNUNET_free (tc);
      return NULL;
    }
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange-wire-test",
                                               "PASSWORD",
                                               &pass))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange-wire-test",
                                 "PASSWORD");
      GNUNET_free (tc->bank_uri);
      GNUNET_free (tc);
      GNUNET_free (user);
      return NULL;
    }
    tc->auth.method = TALER_BANK_AUTH_BASIC;
    tc->auth.details.basic.username = user;
    tc->auth.details.basic.password = pass;
    tc->ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                                &tc->rc);
    tc->rc = GNUNET_CURL_gnunet_rc_create (tc->ctx);
    if (NULL == tc->ctx)
    {
      GNUNET_break (0);
      GNUNET_free (tc->currency);
      GNUNET_free (tc->bank_uri);
      GNUNET_free (tc->auth.details.basic.username);
      GNUNET_free (tc->auth.details.basic.password);
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
  plugin->get_history = &test_get_history;
  plugin->get_history_cancel = &test_get_history_cancel;
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

  if (NULL != tc->ctx)
  {
    GNUNET_CURL_fini (tc->ctx);
    tc->ctx = NULL;
  }
  if (NULL != tc->rc)
  {
    GNUNET_CURL_gnunet_rc_destroy (tc->rc);
    tc->rc = NULL;
  }
  switch (tc->auth.method)
  {
  case TALER_BANK_AUTH_NONE:
    break;
  case TALER_BANK_AUTH_BASIC:
    if (NULL != tc->auth.details.basic.username)
    {
      GNUNET_free (tc->auth.details.basic.username);
      tc->auth.details.basic.username = NULL;
    }
    if (NULL != tc->auth.details.basic.password)
    {
      GNUNET_free (tc->auth.details.basic.password);
      tc->auth.details.basic.password = NULL;
    }
    break;
  }
  GNUNET_free_non_null (tc->currency);
  GNUNET_free_non_null (tc->bank_uri);
  GNUNET_free (tc);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_wire_test.c */
