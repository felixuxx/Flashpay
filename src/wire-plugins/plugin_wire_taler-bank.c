/*
  This file is part of TALER
  Copyright (C) 2017, 2018 Taler Systems SA

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
 * @file plugin_wire_taler_bank.c
 * @brief plugin for the "x-taler-bank" wire method
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_wire_plugin.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include <gnunet/gnunet_curl_lib.h>

/* only for HTTP status codes */
#include <microhttpd.h>

/**
 * Maximum legal 'value' for an account number, based on IEEE double (for JavaScript compatibility).
 */
#define MAX_ACCOUNT_NO (1LLU << 52)

/**
 * Type of the "cls" argument given to each of the functions in
 * our API.
 */
struct TalerBankClosure
{

  /**
   * Which currency do we support?
   */
  char *currency;

  /**
   * Handle to the context for sending funds to the bank.
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * Scheduler context for running the @e ctx.
   */
  struct GNUNET_CURL_RescheduleContext *rc;

  /**
   * Configuration we use to lookup account information.
   */
  struct GNUNET_CONFIGURATION_Handle *cfg;

};


/**
 * Handle returned by #taler_bank_prepare_wire_transfer.
 */
struct TALER_WIRE_PrepareHandle
{

  /**
   * Task we use for async execution.
   */
  struct GNUNET_SCHEDULER_Task *task;

  /**
   * TalerBank closure we run in.
   */
  struct TalerBankClosure *tc;

  /**
   * Authentication information.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Which account should be debited? Given as the respective
   * section in the configuration file.
   */
  char *origin_account_url;

  /**
   * Which account should be credited?
   */
  char *destination_account_url;

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
 * Handle returned by #taler_bank_execute_wire_transfer.
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
taler_bank_amount_round (void *cls,
                         struct TALER_Amount *amount)
{
  struct TalerBankClosure *tc = cls;
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
  /* 'taler_bank' method supports 1/100 of the unit currency, i.e. 0.01 CUR */
  delta = amount->fraction % (TALER_AMOUNT_FRAC_BASE / 100);
  if (0 == delta)
    return GNUNET_NO;
  amount->fraction -= delta;
  return GNUNET_OK;
}


/**
 * Information about an account extracted from a payto://-URL.
 */
struct Account
{
  /**
   * Hostname of the bank (possibly including port).
   */
  char *hostname;

  /**
   * Bank account number.
   */
  unsigned long long no;

  /**
   * Base URL of the bank hosting the account above.
   */
  char *bank_base_url;
};


/**
 * Parse payto:// account URL (only account information,
 * wire subject and amount are ignored).
 *
 * @param account_url URL to parse
 * @param account[out] set to information, can be NULL
 * @return #TALER_EC_NONE if @a account_url is well-formed
 */
static enum TALER_ErrorCode
parse_payto (const char *account_url,
             struct Account *r_account)
{
  const char *hostname;
  const char *account;
  const char *q;
  unsigned long long no;

#define PREFIX "payto://x-taler-bank/"
  if (0 != strncasecmp (account_url,
                        PREFIX,
                        strlen (PREFIX)))
    return TALER_EC_PAYTO_WRONG_METHOD;
  hostname = &account_url[strlen (PREFIX)];
  if (NULL == (account = strchr (hostname,
                                 (unsigned char) '/')))
    return TALER_EC_PAYTO_MALFORMED;
  account++;
  if (NULL != (q = strchr (account,
                           (unsigned char) '?')))
  {
    char *s;

    s = GNUNET_strndup (account,
                        q - account);
    if (1 != sscanf (s,
                     "%llu",
                     &no))
    {
      GNUNET_free (s);
      return TALER_EC_PAYTO_MALFORMED;
    }
    GNUNET_free (s);
  }
  else if (1 != sscanf (account,
                        "%llu",
                        &no))
  {
    return TALER_EC_PAYTO_MALFORMED;
  }
  if (no > MAX_ACCOUNT_NO)
    return TALER_EC_PAYTO_MALFORMED;

  if (NULL != r_account)
  {
    long long unsigned port;
    char *p;

    r_account->hostname = GNUNET_strndup (hostname,
                                          account - hostname);
    r_account->no = no;
    port = 443; /* if non given, equals 443.  */
    if (NULL != (p = strchr (r_account->hostname,
                           (unsigned char) ':')))
    {
      p++;
      if (1 != sscanf (p,
                       "%llu",
                       &port))
      {
        GNUNET_break (0);
        TALER_LOG_ERROR ("Malformed host from payto:// URI\n");
        GNUNET_free (r_account->hostname);
        return TALER_EC_PAYTO_MALFORMED;
      }
    }
    if (443 != port)
    {
      GNUNET_assert
        (GNUNET_SYSERR != GNUNET_asprintf
          (&r_account->bank_base_url,
           "http://%s",
           r_account->hostname));
    }
    else
    {
      GNUNET_assert
        (GNUNET_SYSERR != GNUNET_asprintf
          (&r_account->bank_base_url,
           "https://%s",
           r_account->hostname));
    }
  }
  return TALER_EC_NONE;
}


/**
 * Check if the given payto:// URL is correctly formatted.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_url an account URL
 * @return #TALER_EC_NONE if correctly formatted
 */
static enum TALER_ErrorCode
taler_bank_wire_validate (void *cls,
                          const char *account_url)
{
  (void) cls;

  return parse_payto (account_url,
                      NULL);
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

  /* followed by 0-terminated origin account URL */

  /* followed by 0-terminated destination account URL */

  /* followed by 0-terminated exchange base URL */

  /* optionally followed by 0-terminated origin username URL */

  /* optionally followed by 0-terminated origin password URL */

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
taler_bank_prepare_wire_transfer_cancel (void *cls,
                                         struct TALER_WIRE_PrepareHandle *pth)
{
  if (NULL != pth->task)
    GNUNET_SCHEDULER_cancel (pth->task);
  TALER_BANK_auth_free (&pth->auth);
  GNUNET_free (pth->origin_account_url);
  GNUNET_free (pth->destination_account_url);
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
  size_t len_i;
  size_t len_o;
  size_t len_au;
  size_t len_ap;
  size_t len_b;
  struct BufFormatP bf;

  pth->task = NULL;
  /* serialize the state into a 'buf' */
  len_o = strlen (pth->origin_account_url) + 1;
  len_i = strlen (pth->destination_account_url) + 1;
  len_b = strlen (pth->exchange_base_url) + 1;
  len_au = 0;
  len_ap = 0;
  switch (pth->auth.method)
  {
  case TALER_BANK_AUTH_NONE:
    break;
  case TALER_BANK_AUTH_BASIC:
    len_au = strlen (pth->auth.details.basic.username) + 1;
    len_ap = strlen (pth->auth.details.basic.password) + 1;
    break;
  }
  bf.wtid = pth->wtid;
  TALER_amount_hton (&bf.amount,
                     &pth->amount);
  {
    char buf[sizeof (struct BufFormatP) + len_o + len_i + len_b + len_au + len_ap];

    memcpy (buf,
            &bf,
            sizeof (struct BufFormatP));
    memcpy (&buf[sizeof (struct BufFormatP)],
            pth->origin_account_url,
            len_o);
    memcpy (&buf[sizeof (struct BufFormatP) + len_o],
            pth->destination_account_url,
            len_i);
    memcpy (&buf[sizeof (struct BufFormatP) + len_o + len_i],
            pth->exchange_base_url,
            len_b);
    switch (pth->auth.method)
    {
    case TALER_BANK_AUTH_NONE:
      break;
    case TALER_BANK_AUTH_BASIC:
      memcpy (&buf[sizeof (struct BufFormatP) + len_o + len_i + len_b],
              pth->auth.details.basic.username,
              len_au);
      memcpy (&buf[sizeof (struct BufFormatP) + len_o + len_i + len_b + len_au],
              pth->auth.details.basic.password,
              len_ap);
      break;
    }
    /* finally give the state back */
    pth->ptc (pth->ptc_cls,
              buf,
              sizeof (buf));
  }
  taler_bank_prepare_wire_transfer_cancel (NULL,
                                           pth);
}


/**
 * Parse account configuration from @a cfg in @a section into @a account.
 * Obtains the URL option and initializes @a account from it.
 *
 * @param cfg configuration to parse
 * @param section section with the account configuration
 * @param account[out] account information to initialize
 * @return #GNUNET_OK on success
 */
static int
parse_account_cfg (const struct GNUNET_CONFIGURATION_Handle *cfg,
                   const char *section,
                   struct Account *account)
{
  char *account_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "URL",
                                             &account_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "URL");
    return GNUNET_SYSERR;
  }

  if (TALER_EC_NONE !=
      parse_payto (account_url,
                   account))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "URL",
                               "Malformed payto:// URL for x-taler-bank method");
    GNUNET_free (account_url);
    return GNUNET_SYSERR;
  }
  GNUNET_free (account_url);
  return GNUNET_OK;
}


/**
 * Prepare for exeuction of a wire transfer.  Note that we should call
 * @a ptc asynchronously (as that is what the API requires, because
 * some transfer methods need it).  So while we could immediately call
 * @a ptc, we first bundle up all the data and schedule a task to do
 * the work.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param origin_account_section configuration section specifying the origin
 *        account of the exchange to use
 * @param destination_account_url payto:// URL identifying where to send the money
 * @param amount amount to transfer, already rounded
 * @param exchange_base_url base URL of this exchange
 * @param wtid wire transfer identifier to use
 * @param ptc function to call with the prepared data to persist
 * @param ptc_cls closure for @a ptc
 * @return NULL on failure
 */
static struct TALER_WIRE_PrepareHandle *
taler_bank_prepare_wire_transfer (void *cls,
                                  const char *origin_account_section,
                                  const char *destination_account_url,
                                  const struct TALER_Amount *amount,
                                  const char *exchange_base_url,
                                  const struct TALER_WireTransferIdentifierRawP *wtid,
                                  TALER_WIRE_PrepareTransactionCallback ptc,
                                  void *ptc_cls)
{
  struct TalerBankClosure *tc = cls;
  struct TALER_WIRE_PrepareHandle *pth;
  char *origin_account_url;
  struct Account a_in;
  struct Account a_out;

  /* Check that payto:// URLs are valid */
  if (TALER_EC_NONE !=
      parse_payto (destination_account_url,
                   &a_out))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "payto://-URL `%s' is invalid!\n",
                destination_account_url);
    return NULL;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (tc->cfg,
                                             origin_account_section,
                                             "URL",
                                             &origin_account_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               origin_account_section,
                               "URL");
    GNUNET_free (a_out.hostname);
    GNUNET_free (a_out.bank_base_url);
    return NULL;
  }
  if (TALER_EC_NONE !=
      parse_payto (origin_account_url,
                   &a_in))
    {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               origin_account_section,
                               "URL",
                               "Malformed payto:// URL for x-taler-bank method");
    GNUNET_free (origin_account_url);
    GNUNET_free (a_out.hostname);
    GNUNET_free (a_out.bank_base_url);
    return NULL;
  }

  /* Make sure the bank is the same! */
  if (0 != strcasecmp (a_in.hostname,
                       a_out.hostname))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "x-taler-bank hostname missmatch: `%s' != `%s'\n",
                a_in.hostname,
                a_out.hostname);
    GNUNET_free (a_in.hostname);
    GNUNET_free (a_in.bank_base_url);
    GNUNET_free (a_out.hostname);
    GNUNET_free (a_out.bank_base_url);
    GNUNET_free (origin_account_url);
    return NULL;
  }
  GNUNET_free (a_in.hostname);
  GNUNET_free (a_in.bank_base_url);
  GNUNET_free (a_out.hostname);
  GNUNET_free (a_out.bank_base_url);

  pth = GNUNET_new (struct TALER_WIRE_PrepareHandle);
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (tc->cfg,
                                 origin_account_section,
                                 &pth->auth))
  {
    GNUNET_free (pth);
    GNUNET_free (origin_account_url);
    return NULL;
  }

  pth->tc = tc;
  pth->origin_account_url = origin_account_url;
  pth->destination_account_url = GNUNET_strdup (destination_account_url);
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
 * @param ec error code from the bank
 * @param serial_id unique ID of the wire transfer in the bank's records; UINT64_MAX on error
 * @param timestamp time when the transfer was settled by the bank.
 * @param json detailed response from the HTTPD, or NULL if reply was not JSON
 */
static void
execute_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            long long unsigned int serial_id,
            struct GNUNET_TIME_Absolute timestamp,
            const json_t *json)
{
  struct TALER_WIRE_ExecuteHandle *eh = cls;
  json_t *reason;
  const char *emsg;
  char *s;
  uint64_t serial_id_nbo;

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
                     "%u/%u (%s)",
                     http_status,
                     (unsigned int) ec,
                     emsg);
  else
    GNUNET_asprintf (&s,
                     "%u/%u",
                     http_status,
                     (unsigned int) ec);

  serial_id_nbo = GNUNET_htonll (serial_id);

  eh->cc (eh->cc_cls,
          (MHD_HTTP_OK == http_status) ? GNUNET_OK : GNUNET_SYSERR,
          &serial_id_nbo,
          sizeof (uint64_t),
          (MHD_HTTP_OK == http_status) ? NULL : s);

  GNUNET_free (s);
  GNUNET_free (eh);
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
taler_bank_execute_wire_transfer (void *cls,
                                  const char *buf,
                                  size_t buf_size,
                                  TALER_WIRE_ConfirmationCallback cc,
                                  void *cc_cls)
{
  struct TalerBankClosure *tc = cls;
  struct TALER_WIRE_ExecuteHandle *eh;
  struct TALER_Amount amount;
  struct Account origin_account;
  struct Account destination_account;
  struct BufFormatP bf;
  const char *exchange_base_url;
  const char *origin_account_url;
  const char *destination_account_url;
  struct TALER_BANK_AuthenticationData auth;
  size_t left;
  size_t slen;
  char *wire_s;

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
  memcpy (&bf,
          buf,
          sizeof (bf));
  TALER_amount_ntoh (&amount,
                     &bf.amount);
  origin_account_url = &buf[sizeof (struct BufFormatP)];
  left = buf_size - sizeof (struct BufFormatP);
  slen = strlen (origin_account_url) + 1;
  /* make sure there's enough space to accomodate what's been taken now */
  GNUNET_assert (left >= slen);
  left -= slen;
  if (0 == left)
  {
    GNUNET_break (0);
    return NULL;
  }
  destination_account_url = &origin_account_url[slen];
  slen = strlen (destination_account_url) + 1;
  GNUNET_assert (left >= slen);
  left -= slen;
  if (0 == left)
  {
    GNUNET_break (0);
    return NULL;
  }
  exchange_base_url = &destination_account_url[slen];
  slen = strlen (exchange_base_url) + 1;
  GNUNET_assert (left >= slen);
  left -= slen;
  if (0 == left)
  {
    auth.method = TALER_BANK_AUTH_NONE;
  }
  else
  {
    auth.method = TALER_BANK_AUTH_BASIC;
    auth.details.basic.username = (char *) &exchange_base_url[slen];
    slen = strlen (auth.details.basic.username) + 1;
    GNUNET_assert (left >= slen);
    left -= slen;
    if (0 == left)
    {
      GNUNET_break (0);
      return NULL;
    }
    auth.details.basic.password = &auth.details.basic.username[slen];
    slen = strlen (auth.details.basic.password) + 1;
    GNUNET_assert (left >= slen);
    left -= slen;
    if (0 != left)
    {
      GNUNET_break (0);
      return NULL;
    }
  }

  if (TALER_EC_NONE !=
      parse_payto (origin_account_url,
                   &origin_account))
  {
    GNUNET_break (0);
    return NULL;
  }
  if (TALER_EC_NONE !=
      parse_payto (destination_account_url,
                   &destination_account))
  {
    GNUNET_free_non_null (origin_account.hostname);
    GNUNET_free_non_null (origin_account.bank_base_url);
    GNUNET_break (0);
    return NULL;
  }
  if (0 != strcasecmp (origin_account.hostname,
                       destination_account.hostname))
  {
    GNUNET_break (0);
    GNUNET_free_non_null (origin_account.hostname);
    GNUNET_free_non_null (destination_account.hostname);
    GNUNET_free_non_null (origin_account.bank_base_url);
    GNUNET_free_non_null (destination_account.bank_base_url);
    return NULL;
  }

  eh = GNUNET_new (struct TALER_WIRE_ExecuteHandle);
  eh->cc = cc;
  eh->cc_cls = cc_cls;
  wire_s = GNUNET_STRINGS_data_to_string_alloc (&bf.wtid,
                                                sizeof (bf.wtid));
  eh->aaih = TALER_BANK_admin_add_incoming (tc->ctx,
                                            origin_account.bank_base_url,
                                            &auth,
                                            exchange_base_url,
                                            wire_s,
                                            &amount,
                                            (uint64_t) origin_account.no,
					    (uint64_t) destination_account.no,
                                            &execute_cb,
                                            eh);
  GNUNET_free_non_null (origin_account.bank_base_url);
  GNUNET_free_non_null (destination_account.bank_base_url);
  GNUNET_free_non_null (origin_account.hostname);
  GNUNET_free_non_null (destination_account.hostname);
  GNUNET_free (wire_s);
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
taler_bank_execute_wire_transfer_cancel (void *cls,
                                         struct TALER_WIRE_ExecuteHandle *eh)
{
  TALER_BANK_admin_add_incoming_cancel (eh->aaih);
  GNUNET_free (eh);
}


/**
 * Handle for a #taler_bank_get_history() request.
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

  /**
   * Authentication to use for access.
   */
  struct TALER_BANK_AuthenticationData auth;

};


/**
 * Cancel going over the account's history.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param whh operation to cancel
 */
static void
taler_bank_get_history_cancel (void *cls,
                               struct TALER_WIRE_HistoryHandle *whh)
{
  if (NULL != whh->hh)
  {
    TALER_BANK_history_cancel (whh->hh);
    whh->hh = NULL;
  }
  TALER_BANK_auth_free (&whh->auth);
  GNUNET_free (whh);
}


/**
 * Function called with results from the bank about the transaction history.
 *
 * @param cls the `struct TALER_WIRE_HistoryHandle`
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 *                    #MHD_HTTP_NO_CONTENT if there are no more results; on success the
 *                    last callback is always of this status (even if `abs(num_results)` were
 *                    already returned).
 * @param ec taler error code
 * @param dir direction of the transfer
 * @param serial_id monotonically increasing counter corresponding to the transaction
 * @param details details about the wire transfer
 * @param json detailed response from the HTTPD, or NULL if reply was not in JSON
 */
static void
bhist_cb (void *cls,
          unsigned int http_status,
          enum TALER_ErrorCode ec,
          enum TALER_BANK_Direction dir,
          uint64_t serial_id,
          const struct TALER_BANK_TransferDetails *details,
          const json_t *json)
{
  struct TALER_WIRE_HistoryHandle *whh = cls;
  uint64_t bserial_id = GNUNET_htonll (serial_id);
  struct TALER_WIRE_TransferDetails wd;

  switch (http_status) {
  case MHD_HTTP_OK:
    {
      char *subject;
      char *space;

      wd.amount = details->amount;
      wd.execution_date = details->execution_date;
      subject = GNUNET_strdup (details->wire_transfer_subject);
      space = strchr (subject,
                      (unsigned char) ' ');
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
                                         &wd.wtid,
                                         sizeof (wd.wtid)))
      {
        /* Ill-formed wire subject, set binary version to all zeros
           and pass as a string, this time including the part after
           the space. */
        memset (&wd.wtid,
                0,
                sizeof (wd.wtid));
        wd.wtid_s = details->wire_transfer_subject;
      }
      else
      {
        wd.wtid_s = NULL;
      }
      GNUNET_free (subject);
      wd.account_url = details->account_url;
      if ( (NULL != whh->hres_cb) &&
           (GNUNET_OK !=
            whh->hres_cb (whh->hres_cb_cls,
                          TALER_EC_NONE,
                          dir,
                          &bserial_id,
                          sizeof (bserial_id),
                          &wd)) )
        whh->hres_cb = NULL;
      GNUNET_break (NULL != whh->hh);
      /* Once we get the sentinel element, the handle becomes invalid. */
      if (TALER_BANK_DIRECTION_NONE == dir)
        whh->hh = NULL;
      return;
    }
  case MHD_HTTP_NO_CONTENT:
    if (NULL != whh->hres_cb)
      (void) whh->hres_cb (whh->hres_cb_cls,
                           ec,
                           TALER_BANK_DIRECTION_NONE,
                           NULL,
                           0,
                           NULL);
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Bank failed with HTTP status %u (EC: %u)\n",
                http_status,
                ec);
    if (NULL != whh->hres_cb)
      (void) whh->hres_cb (whh->hres_cb_cls,
                           ec,
                           TALER_BANK_DIRECTION_NONE,
                           NULL,
                           0,
                           NULL);
    break;
  }
  whh->hh = NULL;
  taler_bank_get_history_cancel (NULL,
                                 whh);
}


/**
 * Query transfer history of an account.  We use the variable-size
 * @a start_off to indicate which transfers we are interested in as
 * different banking systems may have different ways to identify
 * transfers.  The @a start_off value must thus match the value of
 * a `row_off` argument previously given to the @a hres_cb.  Use
 * NULL to query transfers from the beginning of time (with
 * positive @a num_results) or from the lataler_bank committed transfers
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
taler_bank_get_history (void *cls,
                        const char *account_section,
                        enum TALER_BANK_Direction direction,
                        const void *start_off,
                        size_t start_off_len,
                        int64_t num_results,
                        TALER_WIRE_HistoryResultCallback hres_cb,
                        void *hres_cb_cls)
{
  struct TalerBankClosure *tc = cls;
  struct TALER_WIRE_HistoryHandle *whh;
  const uint64_t *start_off_b64;
  uint64_t start_row;
  struct Account account;

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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Wire plugin 'taler_bank' got start offset of wrong size (%llu instead of %llu)\n",
                (unsigned long long) start_off_len,
                (unsigned long long) sizeof (uint64_t));
    GNUNET_break (0);
    /* Probably something is wrong with the DB, some other component
     * wrote a wrong value to it.  Instead of completely stopping to work,
     * we just scan from the beginning. */
    start_off = NULL;
  }
  if (NULL == start_off)
  {
    start_row = UINT64_MAX; /* no start row */
  }
  else
  {
    start_off_b64 = start_off;
    start_row = GNUNET_ntohll (*start_off_b64);
  }
  if (GNUNET_OK !=
      parse_account_cfg (tc->cfg,
                         account_section,
                         &account))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not parse the config section '%s'\n",
                account_section);
    return NULL;
  }

  whh = GNUNET_new (struct TALER_WIRE_HistoryHandle);
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (tc->cfg,
                                 account_section,
                                 &whh->auth))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not parse the auth values from '%s'\n",
                account_section);
    GNUNET_free (whh);
    return NULL;
  }

  whh->hres_cb = hres_cb;
  whh->hres_cb_cls = hres_cb_cls;

  whh->hh = TALER_BANK_history (tc->ctx,
                                account.bank_base_url,
                                &whh->auth,
                                (uint64_t) account.no,
                                direction,
                                /* Defaults to descending ordering always. */
                                GNUNET_NO,
                                start_row,
                                num_results,
                                &bhist_cb,
                                whh);
  if (NULL == whh->hh)
  {
    GNUNET_break (0);
    taler_bank_get_history_cancel (NULL,
                                   whh);
    GNUNET_free (account.hostname);
    GNUNET_free (account.bank_base_url);
    return NULL;
  }
  GNUNET_free (account.hostname);
  GNUNET_free (account.bank_base_url);
  GNUNET_assert (NULL != whh);
  return whh;
}



/**
 * Query transfer history of an account.  The query is based on
 * the dates where the wire transfers got settled at the bank.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_section specifies the configuration section which
 *        identifies the account for which we should get the history
 * @param direction what kinds of wire transfers should be returned
 * @param start_date each history entry in the result will be time
 *        stamped after, or at this date.
 * @param end_date each history entry in the result will be time
 *        stamped before, or at this date.
 * @param hres_cb the callback to call with the transaction history
 * @param hres_cb_cls closure for the above callback
 * @param return the operation handle, or NULL on errors.
 */
static struct TALER_WIRE_HistoryHandle *
taler_bank_get_history_range (void *cls,
                              const char *account_section,
                              enum TALER_BANK_Direction direction,
                              struct GNUNET_TIME_Absolute start_date,
                              struct GNUNET_TIME_Absolute end_date,
                              TALER_WIRE_HistoryResultCallback hres_cb,
                              void *hres_cb_cls)
{
  GNUNET_break (0);
  return NULL;
}


/**
 * Context for a rejection operation.
 */
struct TALER_WIRE_RejectHandle
{
  /**
   * Function to call with the result.
   */
  TALER_WIRE_RejectTransferCallback rej_cb;

  /**
   * Closure for @e rej_cb.
   */
  void *rej_cb_cls;

  /**
   * Handle for the reject operation.
   */
  struct TALER_BANK_RejectHandle *brh;

  /**
   * Authentication information to use.
   */
  struct TALER_BANK_AuthenticationData auth;
};


/**
 * Callbacks of this type are used to serve the result of asking
 * the bank to reject an incoming wire transfer.
 *
 * @param cls closure
 * @param http_status HTTP response code, #MHD_HTTP_NO_CONTENT (204) for successful status request;
 *                    #MHD_HTTP_NOT_FOUND if the rowid is unknown;
 *                    0 if the bank's reply is bogus (fails to follow the protocol),
 * @param ec detailed error code
 */
static void
reject_cb (void *cls,
           unsigned int http_status,
           enum TALER_ErrorCode ec)
{
  struct TALER_WIRE_RejectHandle *rh = cls;

  rh->brh = NULL;
  rh->rej_cb (rh->rej_cb_cls,
              ec);
  GNUNET_free (rh);
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
taler_bank_reject_transfer_cancel (void *cls,
                                   struct TALER_WIRE_RejectHandle *rh)
{
  void *ret = rh->rej_cb_cls;

  if (NULL != rh->brh)
    TALER_BANK_reject_cancel (rh->brh);
  TALER_BANK_auth_free (&rh->auth);
  GNUNET_free (rh);
  return ret;
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
taler_bank_reject_transfer (void *cls,
                            const char *account_section,
                            const void *start_off,
                            size_t start_off_len,
                            TALER_WIRE_RejectTransferCallback rej_cb,
                            void *rej_cb_cls)
{
  struct TalerBankClosure *tc = cls;
  const uint64_t *rowid_b64 = start_off;
  struct TALER_WIRE_RejectHandle *rh;
  struct Account account;

  if (sizeof (uint64_t) != start_off_len)
  {
    GNUNET_break (0);
    return NULL;
  }
  rh = GNUNET_new (struct TALER_WIRE_RejectHandle);
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (tc->cfg,
                                 account_section,
                                 &rh->auth))
  {
    GNUNET_free (rh);
    return NULL;
  }
  if (GNUNET_OK !=
      parse_account_cfg (tc->cfg,
                         account_section,
                         &account))
  {
    (void) taler_bank_reject_transfer_cancel (tc,
                                              rh);
    return NULL;
  }
  rh->rej_cb = rej_cb;
  rh->rej_cb_cls = rej_cb_cls;
  TALER_LOG_INFO ("Rejecting over %s bank URL\n",
                  account.hostname);
  rh->brh = TALER_BANK_reject (tc->ctx,
                               account.bank_base_url,
                               &rh->auth,
                               (uint64_t) account.no,
                               GNUNET_ntohll (*rowid_b64),
                               &reject_cb,
                               rh);
  if (NULL == rh->brh)
  {
    (void) taler_bank_reject_transfer_cancel (tc,
                                              rh);
    GNUNET_free (account.hostname);
    return NULL;
  }
  GNUNET_free (account.hostname);
  return rh;
}


/**
 * Initialize taler_bank-wire subsystem.
 *
 * @param cls a configuration instance
 * @return NULL on error, otherwise a `struct TALER_WIRE_Plugin`
 */
void *
libtaler_plugin_wire_taler_bank_init (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TalerBankClosure *tc;
  struct TALER_WIRE_Plugin *plugin;

  tc = GNUNET_new (struct TalerBankClosure);
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
  tc->ctx = GNUNET_CURL_init (&GNUNET_CURL_gnunet_scheduler_reschedule,
                              &tc->rc);
  tc->rc = GNUNET_CURL_gnunet_rc_create (tc->ctx);
  if (NULL == tc->ctx)
  {
    GNUNET_break (0);
    GNUNET_free (tc->currency);
    GNUNET_free (tc);
    return NULL;
  }
  plugin = GNUNET_new (struct TALER_WIRE_Plugin);
  plugin->cls = tc;
  plugin->method = "x-taler-bank";
  plugin->amount_round = &taler_bank_amount_round;
  plugin->wire_validate = &taler_bank_wire_validate;
  plugin->prepare_wire_transfer = &taler_bank_prepare_wire_transfer;
  plugin->prepare_wire_transfer_cancel = &taler_bank_prepare_wire_transfer_cancel;
  plugin->execute_wire_transfer = &taler_bank_execute_wire_transfer;
  plugin->execute_wire_transfer_cancel = &taler_bank_execute_wire_transfer_cancel;
  plugin->get_history = &taler_bank_get_history;
  plugin->get_history_range = &taler_bank_get_history_range;
  plugin->get_history_cancel = &taler_bank_get_history_cancel;
  plugin->reject_transfer = &taler_bank_reject_transfer;
  plugin->reject_transfer_cancel = &taler_bank_reject_transfer_cancel;
  return plugin;
}


/**
 * Shutdown taler-bank wire subsystem.
 *
 * @param cls a `struct TALER_WIRE_Plugin`
 * @return NULL (always)
 */
void *
libtaler_plugin_wire_taler_bank_done (void *cls)
{
  struct TALER_WIRE_Plugin *plugin = cls;
  struct TalerBankClosure *tc = plugin->cls;

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
  GNUNET_free_non_null (tc->currency);
  GNUNET_free (tc);
  GNUNET_free (plugin);
  return NULL;
}

/* end of plugin_wire_taler-bank.c */
