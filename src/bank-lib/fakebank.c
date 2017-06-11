/*
  This file is part of TALER
  (C) 2016, 2017 Inria and GNUnet e.V.

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
 * @file bank-lib/fakebank.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */

#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"

/**
 * Maximum POST request size (for /admin/add/incoming)
 */
#define REQUEST_BUFFER_MAX (4*1024)



/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction
{

  /**
   * We store transactions in a DLL.
   */
  struct Transaction *next;

  /**
   * We store transactions in a DLL.
   */
  struct Transaction *prev;

  /**
   * Amount to be transferred.
   */
  struct TALER_Amount amount;

  /**
   * Account to debit.
   */
  uint64_t debit_account;

  /**
   * Account to credit.
   */
  uint64_t credit_account;

  /**
   * Subject of the transfer.
   */
  char *subject;

  /**
   * Base URL of the exchange.
   */
  char *exchange_base_url;

  /**
   * When did the transaction happen?
   */
  struct GNUNET_TIME_Absolute date;

  /**
   * Number of this transaction.
   */
  uint64_t serial_id;
};


/**
 * Handle for the fake bank.
 */
struct TALER_FAKEBANK_Handle
{
  /**
   * We store transactions in a DLL.
   */
  struct Transaction *transactions_head;

  /**
   * We store transactions in a DLL.
   */
  struct Transaction *transactions_tail;

  /**
   * HTTP server we run to pretend to be the "test" bank.
   */
  struct MHD_Daemon *mhd_bank;

  /**
   * Task running HTTP server for the "test" bank.
   */
  struct GNUNET_SCHEDULER_Task *mhd_task;

  /**
   * Number of transactions.
   */
  uint64_t serial_counter;
};


/**
 * Check that the @a want_amount was transferred from
 * the @a want_debit to the @a want_credit account.  If
 * so, set the @a subject to the transfer identifier.
 * If not, return #GNUNET_SYSERR.
 *
 * @param h bank instance
 * @param want_amount transfer amount desired
 * @param want_debit account that should have been debited
 * @param want_credit account that should have been credited
 * @param exchange_base_url expected base URL of the exchange
 *        i.e. "https://example.com/"; may include a port
 * @param[out] wtid set to the wire transfer identifier
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check (struct TALER_FAKEBANK_Handle *h,
                      const struct TALER_Amount *want_amount,
                      uint64_t want_debit,
                      uint64_t want_credit,
                      const char *exchange_base_url,
                      char **subject)
{
  for (struct Transaction *t = h->transactions_head; NULL != t; t = t->next)
  {
    if ( (want_debit == t->debit_account) &&
         (want_credit == t->credit_account) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (0 == strcasecmp (exchange_base_url,
                           t->exchange_base_url)) )
    {
      GNUNET_CONTAINER_DLL_remove (h->transactions_head,
                                   h->transactions_tail,
                                   t);
      *subject = t->subject;
      GNUNET_free (t->exchange_base_url);
      GNUNET_free (t);
      return GNUNET_OK;
    }
  }
  fprintf (stderr,
           "Did not find matching transaction!\nI have:\n");
  for (struct Transaction *t = h->transactions_head; NULL != t; t = t->next)
  {
    char *s;

    s = TALER_amount_to_string (&t->amount);
    fprintf (stderr,
             "%llu -> %llu (%s) from %s\n",
             (unsigned long long) t->debit_account,
             (unsigned long long) t->credit_account,
             s,
             t->exchange_base_url);
    GNUNET_free (s);
  }
  return GNUNET_SYSERR;
}


/**
 * Tell the fakebank to create another wire transfer.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param subject wire transfer subject to use
 * @param exchange_base_url exchange URL
 * @return serial_id of the transfer
 */
uint64_t
TALER_FAKEBANK_make_transfer (struct TALER_FAKEBANK_Handle *h,
                              uint64_t debit_account,
                              uint64_t credit_account,
                              const struct TALER_Amount *amount,
                              const char *subject,
                              const char *exchange_base_url)
{
  struct Transaction *t;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Making transfer from %llu to %llu over %s and subject %s\n",
              (unsigned long long) debit_account,
              (unsigned long long) credit_account,
              TALER_amount2s (amount),
              subject);
  t = GNUNET_new (struct Transaction);
  t->debit_account = debit_account;
  t->credit_account = credit_account;
  t->amount = *amount;
  t->exchange_base_url = GNUNET_strdup (exchange_base_url);
  t->serial_id = ++h->serial_counter;
  t->date = GNUNET_TIME_absolute_get ();
  t->subject = GNUNET_strdup (subject);
  GNUNET_TIME_round_abs (&t->date);
  GNUNET_CONTAINER_DLL_insert_tail (h->transactions_head,
                                    h->transactions_tail,
                                    t);
  return t->serial_id;
}


/**
 * Check that no wire transfers were ordered (or at least none
 * that have not been taken care of via #TALER_FAKEBANK_check()).
 * If any transactions are onrecord, return #GNUNET_SYSERR.
 *
 * @param h bank instance
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_empty (struct TALER_FAKEBANK_Handle *h)
{
  struct Transaction *t;

  if (NULL == h->transactions_head)
    return GNUNET_OK;

  fprintf (stderr,
           "Expected empty transaction set, but I have:\n");
  for (t = h->transactions_head; NULL != t; t = t->next)
  {
    char *s;

    s = TALER_amount_to_string (&t->amount);
    fprintf (stderr,
             "%llu -> %llu (%s) from %s\n",
             (unsigned long long) t->debit_account,
             (unsigned long long) t->credit_account,
             s,
             t->exchange_base_url);
    GNUNET_free (s);
  }
  return GNUNET_SYSERR;
}


/**
 * Stop running the fake bank.
 *
 * @param h bank to stop
 */
void
TALER_FAKEBANK_stop (struct TALER_FAKEBANK_Handle *h)
{
  struct Transaction *t;

  while (NULL != (t = h->transactions_head))
  {
    GNUNET_CONTAINER_DLL_remove (h->transactions_head,
                                 h->transactions_tail,
                                 t);
    GNUNET_free (t->subject);
    GNUNET_free (t->exchange_base_url);
    GNUNET_free (t);
  }
  if (NULL != h->mhd_task)
  {
    GNUNET_SCHEDULER_cancel (h->mhd_task);
    h->mhd_task = NULL;
  }
  if (NULL != h->mhd_bank)
  {
    MHD_stop_daemon (h->mhd_bank);
    h->mhd_bank = NULL;
  }
  GNUNET_free (h);
}


/**
 * Function called whenever MHD is done with a request.  If the
 * request was a POST, we may have stored a `struct Buffer *` in the
 * @a con_cls that might still need to be cleaned up.  Call the
 * respective function to free the memory.
 *
 * @param cls client-defined closure
 * @param connection connection handle
 * @param con_cls value as set by the last call to
 *        the #MHD_AccessHandlerCallback
 * @param toe reason for request termination
 * @see #MHD_OPTION_NOTIFY_COMPLETED
 * @ingroup request
 */
static void
handle_mhd_completion_callback (void *cls,
                                struct MHD_Connection *connection,
                                void **con_cls,
                                enum MHD_RequestTerminationCode toe)
{
  /*  struct TALER_FAKEBANK_Handle *h = cls; */

  GNUNET_JSON_post_parser_cleanup (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle incoming HTTP request for /admin/add/incoming.
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_admin_add_incoming (struct TALER_FAKEBANK_Handle *h,
                           struct MHD_Connection *connection,
                           const char *upload_data,
                           size_t *upload_data_size,
                           void **con_cls)
{
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  struct MHD_Response *resp;
  int ret;
  uint64_t serial_id;

  pr = GNUNET_JSON_post_parser (REQUEST_BUFFER_MAX,
                                con_cls,
                                upload_data,
                                upload_data_size,
                                &json);
  switch (pr)
  {
  case GNUNET_JSON_PR_OUT_OF_MEMORY:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_CONTINUE:
    return MHD_YES;
  case GNUNET_JSON_PR_REQUEST_TOO_LARGE:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_JSON_INVALID:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_SUCCESS:
    break;
  }
  {
    const char *wtid;
    uint64_t debit_account;
    uint64_t credit_account;
    const char *base_url;
    struct TALER_Amount amount;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("wtid", &wtid),
      GNUNET_JSON_spec_uint64 ("debit_account", &debit_account),
      GNUNET_JSON_spec_uint64 ("credit_account", &credit_account),
      TALER_JSON_spec_amount ("amount", &amount),
      GNUNET_JSON_spec_string ("exchange_url", &base_url),
      GNUNET_JSON_spec_end ()
    };
    if (GNUNET_OK !=
        GNUNET_JSON_parse (json,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      json_decref (json);
      return MHD_NO;
    }
    serial_id = TALER_FAKEBANK_make_transfer (h,
                                              debit_account,
                                              credit_account,
                                              &amount,
                                              wtid,
                                              base_url);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Receiving incoming wire transfer: %llu->%llu from %s\n",
                (unsigned long long) debit_account,
                (unsigned long long) credit_account,
                base_url);
  }
  json_decref (json);

  /* Finally build response object */
  {
    void *json_str;
    size_t json_len;

    json = json_pack ("{s:I}",
                      "serial_id",
                      (json_int_t) serial_id);
    json_str = json_dumps (json,
                           JSON_INDENT(2));
    json_decref (json);
    if (NULL == json_str)
    {
      GNUNET_break (0);
      return MHD_NO;
    }
    json_len = strlen (json_str);
    resp = MHD_create_response_from_buffer (json_len,
                                            json_str,
                                            MHD_RESPMEM_MUST_FREE);
    if (NULL == resp)
    {
      GNUNET_break (0);
      free (json_str);
      return MHD_NO;
    }
    (void) MHD_add_response_header (resp,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    "application/json");
  }
  ret = MHD_queue_response (connection,
                            MHD_HTTP_OK,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Handle incoming HTTP request for /history
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param con_cls place to store state, not used
 * @return MHD result code
 */
static int
handle_history (struct TALER_FAKEBANK_Handle *h,
                struct MHD_Connection *connection,
                void **con_cls)
{
  const char *auth;
  const char *delta;
  const char *start;
  const char *dir;
  const char *acc;
  unsigned long long account_number;
  unsigned long long start_number;
  long long count;
  enum TALER_BANK_Direction direction;
  struct Transaction *pos;
  json_t *history;
  json_t *jresponse;
  int ret;

  auth = MHD_lookup_connection_value (connection,
                                      MHD_GET_ARGUMENT_KIND,
                                      "auth");
  delta = MHD_lookup_connection_value (connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "delta");
  dir = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "direction");
  start = MHD_lookup_connection_value (connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "start");
  acc = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "account_number");
  if ( (NULL == auth) ||
       (0 != strcasecmp (auth,
                         "basic")) ||
       (NULL == acc) ||
       (NULL == delta) )
  {
    /* Invalid request, given that this is fakebank we impolitely just
       kill the connection instead of returning a nice error. */
    GNUNET_break (0);
    return MHD_NO;
  }
  if ( (1 != sscanf (delta,
                     "%lld",
                     &count)) ||
       (1 != sscanf (acc,
                     "%llu",
                     &account_number)) ||
       ( (NULL != start) &&
         (1 != sscanf (start,
                       "%llu",
                       &start_number)) ) ||
       ( (NULL != dir) &&
         (0 != strcasecmp (dir,
                           "CREDIT")) &&
         (0 != strcasecmp (dir,
                           "DEBIT")) ) )
  {
    /* Invalid request, given that this is fakebank we impolitely just
       kill the connection instead of returning a nice error. */
    GNUNET_break (0);
    return MHD_NO;
  }
  if (NULL == dir)
    direction = TALER_BANK_DIRECTION_BOTH;
  else if (0 == strcasecmp (dir,
                            "CREDIT"))
    direction = TALER_BANK_DIRECTION_CREDIT;
  else
    direction = TALER_BANK_DIRECTION_DEBIT;
  if (NULL == start)
  {
    if (count > 0)
      pos = h->transactions_head;
    else
      pos = h->transactions_tail;
  }
  else
  {
    for (pos = h->transactions_head;
         NULL != pos;
         pos = pos->next)
      if (pos->serial_id == start_number)
        break;
    if (NULL == pos)
    {
      GNUNET_break (0);
      return MHD_NO;
    }
    /* range is exclusive, skip the matching entry */
    if (count > 0)
      pos = pos->next;
    if (count < 0)
      pos = pos->prev;
  }
  history = json_array ();
  while ( (NULL != pos) &&
          (0 != count) )
  {
    json_t *trans;
    char *subject;

    if (! ( ( (account_number == pos->debit_account) &&
              (0 != (direction & TALER_BANK_DIRECTION_DEBIT)) ) ||
            ( (account_number == pos->credit_account) &&
              (0 != (direction & TALER_BANK_DIRECTION_CREDIT) ) ) ) )
    {
      if (count > 0)
        pos = pos->next;
      if (count < 0)
        pos = pos->prev;
      continue;
    }

    GNUNET_asprintf (&subject,
                     "%s %s",
                     pos->subject,
                     pos->exchange_base_url);
    trans = json_pack ("{s:I, s:o, s:o, s:s, s:I, s:s}",
                       "row_id", (json_int_t) pos->serial_id,
                       "date", GNUNET_JSON_from_time_abs (pos->date),
                       "amount", TALER_JSON_from_amount (&pos->amount),
                       "sign", (account_number == pos->debit_account) ? "-" : "+",
                       "counterpart", (json_int_t) ( (account_number == pos->debit_account)
                                                     ? pos->credit_account
                                                     : pos->debit_account),
                       "wt_subject", subject);
    GNUNET_free (subject);
    json_array_append (history,
                       trans);
    if (count > 0)
    {
      pos = pos->next;
      count--;
    }
    if (count < 0)
    {
      pos = pos->prev;
      count++;
    }
  }
  if (0 == json_array_size (history))
  {
    struct MHD_Response *resp;

    json_decref (history);
    resp = MHD_create_response_from_buffer (0,
                                            "",
                                            MHD_RESPMEM_PERSISTENT);
    ret = MHD_queue_response (connection,
                              MHD_HTTP_NO_CONTENT,
                              resp);
    MHD_destroy_response (resp);
    return ret;
  }

  jresponse = json_pack ("{s:o}",
                         "data", history);
  if (NULL == jresponse)
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  /* Finally build response object */
  {
    struct MHD_Response *resp;
    void *json_str;
    size_t json_len;

    json_str = json_dumps (jresponse,
                           JSON_INDENT(2));
    json_decref (jresponse);
    if (NULL == json_str)
    {
      GNUNET_break (0);
      return MHD_NO;
    }
    json_len = strlen (json_str);
    resp = MHD_create_response_from_buffer (json_len,
                                            json_str,
                                            MHD_RESPMEM_MUST_FREE);
    if (NULL == resp)
    {
      GNUNET_break (0);
      free (json_str);
      return MHD_NO;
    }
    (void) MHD_add_response_header (resp,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    "application/json");
    ret = MHD_queue_response (connection,
                              MHD_HTTP_OK,
                              resp);
    MHD_destroy_response (resp);
  }
  return ret;
}


/**
 * Handle incoming HTTP request.
 *
 * @param cls a `struct TALER_FAKEBANK_Handle`
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param version HTTP version (ignored)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_mhd_request (void *cls,
                    struct MHD_Connection *connection,
                    const char *url,
                    const char *method,
                    const char *version,
                    const char *upload_data,
                    size_t *upload_data_size,
                    void **con_cls)
{
  struct TALER_FAKEBANK_Handle *h = cls;

  if ( (0 == strcasecmp (url,
                         "/admin/add/incoming")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
    return handle_admin_add_incoming (h,
                                      connection,
                                      upload_data,
                                      upload_data_size,
                                      con_cls);
  if ( (0 == strcasecmp (url,
                         "/history")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
    return handle_history (h,
                           connection,
                           con_cls);

  /* Unexpected URI path, just close the connection. */
  /* we're rather impolite here, but it's a testcase. */
  GNUNET_break_op (0);
  return MHD_NO;
}


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls the `struct TALER_FAKEBANK_Handle`
 */
static void
run_mhd (void *cls);


/**
 * Schedule MHD.  This function should be called initially when an
 * MHD is first getting its client socket, and will then automatically
 * always be called later whenever there is work to be done.
 */
static void
schedule_httpd (struct TALER_FAKEBANK_Handle *h)
{
  fd_set rs;
  fd_set ws;
  fd_set es;
  struct GNUNET_NETWORK_FDSet *wrs;
  struct GNUNET_NETWORK_FDSet *wws;
  int max;
  int haveto;
  MHD_UNSIGNED_LONG_LONG timeout;
  struct GNUNET_TIME_Relative tv;

  FD_ZERO (&rs);
  FD_ZERO (&ws);
  FD_ZERO (&es);
  max = -1;
  if (MHD_YES != MHD_get_fdset (h->mhd_bank, &rs, &ws, &es, &max))
  {
    GNUNET_assert (0);
    return;
  }
  haveto = MHD_get_timeout (h->mhd_bank, &timeout);
  if (MHD_YES == haveto)
    tv.rel_value_us = (uint64_t) timeout * 1000LL;
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  if (-1 != max)
  {
    wrs = GNUNET_NETWORK_fdset_create ();
    wws = GNUNET_NETWORK_fdset_create ();
    GNUNET_NETWORK_fdset_copy_native (wrs, &rs, max + 1);
    GNUNET_NETWORK_fdset_copy_native (wws, &ws, max + 1);
  }
  else
  {
    wrs = NULL;
    wws = NULL;
  }
  if (NULL != h->mhd_task)
    GNUNET_SCHEDULER_cancel (h->mhd_task);
  h->mhd_task =
    GNUNET_SCHEDULER_add_select (GNUNET_SCHEDULER_PRIORITY_DEFAULT,
                                 tv,
                                 wrs,
                                 wws,
                                 &run_mhd, h);
  if (NULL != wrs)
    GNUNET_NETWORK_fdset_destroy (wrs);
  if (NULL != wws)
    GNUNET_NETWORK_fdset_destroy (wws);
}


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls the `struct TALER_FAKEBANK_Handle`
 */
static void
run_mhd (void *cls)
{
  struct TALER_FAKEBANK_Handle *h = cls;

  h->mhd_task = NULL;
  MHD_run (h->mhd_bank);
  schedule_httpd (h);
}


/**
 * Start the fake bank.
 *
 * @param port port to listen to
 * @return NULL on error
 */
struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start (uint16_t port)
{
  struct TALER_FAKEBANK_Handle *h;

  h = GNUNET_new (struct TALER_FAKEBANK_Handle);
  h->mhd_bank = MHD_start_daemon (MHD_USE_DEBUG,
                                  port,
                                  NULL, NULL,
                                  &handle_mhd_request, h,
                                  MHD_OPTION_NOTIFY_COMPLETED,
                                  &handle_mhd_completion_callback, h,
                                  MHD_OPTION_END);
  if (NULL == h->mhd_bank)
  {
    GNUNET_free (h);
    return NULL;
  }
  schedule_httpd (h);
  return h;
}


/* end of fakebank.c */
