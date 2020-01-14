/*
  This file is part of TALER
  (C) 2016-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file bank-lib/fakebank.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"

/**
 * Maximum POST request size (for /admin/add-incoming)
 */
#define REQUEST_BUFFER_MAX (4 * 1024)


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
  char *debit_account;

  /**
   * Account to credit.
   */
  char *credit_account;

  /**
   * Random unique identifier for the request.
   */
  struct GNUNET_HashCode request_uid;

  /**
   * What does the @e subject contain?
   */
  enum
  {
    /**
     * Transfer TO the exchange.
     */
    T_CREDIT,

    /**
     * Transfer FROM the exchange.
     */
    T_DEBIT
  } type;

  /**
   * Wire transfer subject.
   */
  union
  {

    /**
     * Used if @e type is T_DEBIT.
     */
    struct
    {

      /**
       * Subject of the transfer.
       */
      struct TALER_WireTransferIdentifierRawP wtid;

      /**
       * Base URL of the exchange.
       */
      char *exchange_base_url;

    } debit;

    /**
     * Used if @e type is T_CREDIT.
     */
    struct
    {

      /**
       * Reserve public key of the credit operation.
       */
      struct TALER_ReservePublicKeyP reserve_pub;

    } credit;

  } subject;

  /**
   * When did the transaction happen?
   */
  struct GNUNET_TIME_Absolute date;

  /**
   * Number of this transaction.
   */
  uint64_t row_id;

  /**
   * Has this transaction been subjected to #TALER_FAKEBANK_check_credit()
   * or #TALER_FAKEBANK_check_debit()
   * and should thus no longer be counted in
   * #TALER_FAKEBANK_check_empty()?
   */
  int checked;
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

  /**
   * BaseURL of the fakebank.
   */
  char *my_baseurl;

  /**
   * Our port number.
   */
  uint16_t port;

#if EPOLL_SUPPORT
  /**
   * Boxed @e mhd_fd.
   */
  struct GNUNET_NETWORK_Handle *mhd_rfd;

  /**
   * File descriptor to use to wait for MHD.
   */
  int mhd_fd;
#endif
};


/**
 * Return account string from an x-taler-bank payto:// URL.
 *
 * @param  payto:// URL of method x-taler-bank
 * @return account_name the account name
 */
char *
get_xtalerbank_payto_account (const char *payto_url)
{
  const char *beg;

  GNUNET_assert (0 == strncasecmp (payto_url,
                                   "payto://x-taler-bank/",
                                   strlen ("payto://x-taler-bank/")));
  beg = strchr (&payto_url[strlen ("payto://x-taler-bank/")],
                '/');
  GNUNET_assert (NULL != beg);
  return GNUNET_strdup (&beg[1]);
}


/**
 * Generate log messages for failed check operation.
 *
 * @param h handle to output transaction log for
 */
static void
check_log (struct TALER_FAKEBANK_Handle *h)
{
  for (struct Transaction *t = h->transactions_head; NULL != t; t = t->next)
  {
    if (GNUNET_YES == t->checked)
      continue;
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "%s -> %s (%s)\n",
                t->debit_account,
                t->credit_account,
                TALER_amount2s (&t->amount));
  }
}


/**
 * Check that the @a want_amount was transferred from the @a
 * want_debit to the @a want_credit account.  If so, set the @a subject
 * to the transfer identifier and remove the transaction from the
 * list.  If the transaction was not recorded, return #GNUNET_SYSERR.
 *
 * @param h bank instance
 * @param want_amount transfer amount desired
 * @param want_debit account that should have been debited
 * @param want_debit account that should have been credited
 * @param exchange_base_url expected base URL of the exchange,
 *        i.e. "https://example.com/"; may include a port
 * @param[out] wtid set to the wire transfer identifier
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_debit (struct TALER_FAKEBANK_Handle *h,
                            const struct TALER_Amount *want_amount,
                            const char *want_debit,
                            const char *want_credit,
                            const char *exchange_base_url,
                            struct TALER_WireTransferIdentifierRawP *wtid)
{
  for (struct Transaction *t = h->transactions_head; NULL != t; t = t->next)
  {
    if ( (0 == strcasecmp (want_debit,
                           t->debit_account)) &&
         (0 == strcasecmp (want_credit,
                           t->credit_account)) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (GNUNET_NO == t->checked) &&
         (T_DEBIT == t->type) &&
         (0 == strcasecmp (exchange_base_url,
                           t->subject.debit.exchange_base_url)) )
    {
      *wtid = t->subject.debit.wtid;
      t->checked = GNUNET_YES;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Did not find matching transaction!\nI have:\n");
  check_log (h);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "I wanted:\n%s -> %s (%s) from %s\n",
              want_debit,
              want_credit,
              TALER_amount2s (want_amount),
              exchange_base_url);
  return GNUNET_SYSERR;
}


/**
 * Check that the @a want_amount was transferred from the @a want_debit to the
 * @a want_credit account with the @a subject.  If so, remove the transaction
 * from the list.  If the transaction was not recorded, return #GNUNET_SYSERR.
 *
 * @param h bank instance
 * @param want_amount transfer amount desired
 * @param want_debit account that should have been debited
 * @param want_debit account that should have been credited
 * @param reserve_pub reserve public key expected in wire subject
 * @return #GNUNET_OK on success
 */
int
TALER_FAKEBANK_check_credit (struct TALER_FAKEBANK_Handle *h,
                             const struct TALER_Amount *want_amount,
                             const char *want_debit,
                             const char *want_credit,
                             const struct TALER_ReservePublicKeyP *reserve_pub)
{
  for (struct Transaction *t = h->transactions_head; NULL != t; t = t->next)
  {
    if ( (0 == strcasecmp (want_debit,
                           t->debit_account)) &&
         (0 == strcasecmp (want_credit,
                           t->credit_account)) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (GNUNET_NO == t->checked) &&
         (T_CREDIT == t->type) &&
         (0 == GNUNET_memcmp (reserve_pub,
                              &t->subject.credit.reserve_pub)) )
    {
      t->checked = GNUNET_YES;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Did not find matching transaction!\nI have:\n");
  check_log (h);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "I wanted:\n%llu -> %llu (%s) with subject %s\n",
              (unsigned long long) want_debit,
              (unsigned long long) want_credit,
              TALER_amount2s (want_amount),
              TALER_B2S (reserve_pub));
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
 * @param request_uid unique number to make the request unique, or NULL to create one
 * @return row_id of the transfer
 */
uint64_t
TALER_FAKEBANK_make_transfer (struct TALER_FAKEBANK_Handle *h,
                              const char *debit_account,
                              const char *credit_account,
                              const struct TALER_Amount *amount,
                              const struct
                              TALER_WireTransferIdentifierRawP *subject,
                              const char *exchange_base_url,
                              const struct GNUNET_HashCode *request_uid)
{
  struct Transaction *t;

  if (NULL != request_uid)
  {
    for (struct Transaction *t = h->transactions_head; NULL != t; t = t->next)
      if ( (0 == GNUNET_memcmp (request_uid,
                                &t->request_uid)) &&
           (0 == strcasecmp (debit_account,
                             t->debit_account)) &&
           (0 == strcasecmp (credit_account,
                             t->credit_account)) &&
           (0 == TALER_amount_cmp (amount,
                                   &t->amount)) &&
           (T_DEBIT == t->type) &&
           (0 == GNUNET_memcmp (subject,
                                &t->subject.debit.wtid)) )
        return t->row_id;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Making transfer from %s to %s over %s and subject %s; for exchange: %s\n",
              debit_account,
              credit_account,
              TALER_amount2s (amount),
              TALER_B2S (subject),
              exchange_base_url);
  t = GNUNET_new (struct Transaction);
  t->debit_account = GNUNET_strdup (debit_account);
  t->credit_account = GNUNET_strdup (credit_account);
  t->amount = *amount;
  t->row_id = ++h->serial_counter;
  t->date = GNUNET_TIME_absolute_get ();
  t->type = T_DEBIT;
  t->subject.debit.exchange_base_url = GNUNET_strdup (exchange_base_url);
  t->subject.debit.wtid = *subject;
  if (NULL == request_uid)
    GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_NONCE,
                                      &t->request_uid);
  else
    t->request_uid = *request_uid;
  GNUNET_TIME_round_abs (&t->date);
  GNUNET_CONTAINER_DLL_insert_tail (h->transactions_head,
                                    h->transactions_tail,
                                    t);
  return t->row_id;
}


/**
 * Tell the fakebank to create another wire transfer *to* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param reserve_pub reserve public key to use in subject
 * @return serial_id of the transfer
 */
uint64_t
TALER_FAKEBANK_make_admin_transfer (struct TALER_FAKEBANK_Handle *h,
                                    const char *debit_account,
                                    const char *credit_account,
                                    const struct TALER_Amount *amount,
                                    const struct
                                    TALER_ReservePublicKeyP *reserve_pub)
{
  struct Transaction *t;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Making transfer from %s to %s over %s and subject %s\n",
              debit_account,
              credit_account,
              TALER_amount2s (amount),
              TALER_B2S (reserve_pub));
  t = GNUNET_new (struct Transaction);
  t->debit_account = GNUNET_strdup (debit_account);
  t->credit_account = GNUNET_strdup (credit_account);
  t->amount = *amount;
  t->row_id = ++h->serial_counter;
  t->date = GNUNET_TIME_absolute_get ();
  t->type = T_CREDIT;
  t->subject.credit.reserve_pub = *reserve_pub;
  GNUNET_TIME_round_abs (&t->date);
  GNUNET_CONTAINER_DLL_insert_tail (h->transactions_head,
                                    h->transactions_tail,
                                    t);
  return t->row_id;
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

  t = h->transactions_head;
  while (NULL != t)
  {
    if (GNUNET_YES != t->checked)
      break;
    t = t->next;
  }
  if (NULL == t)
    return GNUNET_OK;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Expected empty transaction set, but I have:\n");
  check_log (h);
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
    GNUNET_free (t->debit_account);
    GNUNET_free (t->credit_account);
    if (T_DEBIT == t->type)
      GNUNET_free (t->subject.debit.exchange_base_url);
    GNUNET_free (t);
  }
  if (NULL != h->mhd_task)
  {
    GNUNET_SCHEDULER_cancel (h->mhd_task);
    h->mhd_task = NULL;
  }
#if EPOLL_SUPPORT
  GNUNET_NETWORK_socket_free_memory_only_ (h->mhd_rfd);
#endif
  if (NULL != h->mhd_bank)
  {
    MHD_stop_daemon (h->mhd_bank);
    h->mhd_bank = NULL;
  }
  GNUNET_free (h->my_baseurl);
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
  (void) cls;
  (void) connection;
  (void) toe;
  GNUNET_JSON_post_parser_cleanup (*con_cls);
  *con_cls = NULL;
}


/**
 * Handle incoming HTTP request for /admin/add/incoming.
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account account into which to deposit the funds (credit)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_admin_add_incoming (struct TALER_FAKEBANK_Handle *h,
                           struct MHD_Connection *connection,
                           const char *account,
                           const char *upload_data,
                           size_t *upload_data_size,
                           void **con_cls)
{
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  uint64_t row_id;

  pr = GNUNET_JSON_post_parser (REQUEST_BUFFER_MAX,
                                connection,
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
    const char *debit_account;
    struct TALER_Amount amount;
    struct TALER_ReservePublicKeyP reserve_pub;
    char *debit;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("reserve_pub", &reserve_pub),
      GNUNET_JSON_spec_string ("debit_account", &debit_account),
      TALER_JSON_spec_amount ("amount", &amount),
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
    debit = get_xtalerbank_payto_account (debit_account);
    row_id = TALER_FAKEBANK_make_admin_transfer (h,
                                                 debit,
                                                 account,
                                                 &amount,
                                                 &reserve_pub);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Receiving incoming wire transfer: %s->%s, subject: %s, amount: %s\n",
                debit,
                account,
                TALER_B2S (&reserve_pub),
                TALER_amount2s (&amount));
    GNUNET_free (debit);
  }
  json_decref (json);

  /* Finally build response object */
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:I, s:o}",
                                    "row_id",
                                    (json_int_t) row_id,
                                    "timestamp", GNUNET_JSON_from_time_abs (
                                      GNUNET_TIME_UNIT_ZERO_ABS));                                       /*dummy tmp */
}


/**
 * Handle incoming HTTP request for /transfer.
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account account making the transfer
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
handle_transfer (struct TALER_FAKEBANK_Handle *h,
                 struct MHD_Connection *connection,
                 const char *account,
                 const char *upload_data,
                 size_t *upload_data_size,
                 void **con_cls)
{
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  uint64_t row_id;

  pr = GNUNET_JSON_post_parser (REQUEST_BUFFER_MAX,
                                connection,
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
    struct GNUNET_HashCode uuid;
    struct TALER_WireTransferIdentifierRawP wtid;
    const char *credit_account;
    const char *base_url;
    struct TALER_Amount amount;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("request_uid",
                                   &uuid),
      TALER_JSON_spec_amount ("amount",
                              &amount),
      GNUNET_JSON_spec_string ("exchange_base_url",
                               &base_url),
      GNUNET_JSON_spec_fixed_auto ("wtid",
                                   &wtid),
      GNUNET_JSON_spec_string ("credit_account",
                               &credit_account),
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
    {
      row_id = TALER_FAKEBANK_make_transfer (h,
                                             account,
                                             credit_account,
                                             &amount,
                                             &wtid,
                                             base_url,
                                             &uuid);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Receiving incoming wire transfer: %s->%s, subject: %s, amount: %s, from %s\n",
                  account,
                  credit_account,
                  TALER_B2S (&wtid),
                  TALER_amount2s (&amount),
                  base_url);
    }
  }
  json_decref (json);

  /* Finally build response object */
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:I, s:o}",
                                    "row_id",
                                    (json_int_t) row_id,
                                    "timestamp", GNUNET_JSON_from_time_abs (
                                      GNUNET_TIME_UNIT_ZERO_ABS));                                       /*dummy tmp */
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
handle_home_page (struct TALER_FAKEBANK_Handle *h,
                  struct MHD_Connection *connection,
                  void **con_cls)
{
  int ret;
  struct MHD_Response *resp;
#define HELLOMSG "Hello, Fakebank!"

  (void) h;
  (void) con_cls;
  resp = MHD_create_response_from_buffer
           (strlen (HELLOMSG),
           HELLOMSG,
           MHD_RESPMEM_MUST_COPY);

  ret = MHD_queue_response (connection,
                            MHD_HTTP_OK,
                            resp);

  MHD_destroy_response (resp);
  return ret;
}


/**
 * This is the "base" structure for both the /history and the
 * /history-range API calls.
 */
struct HistoryArgs
{

  /**
   * Bank account number of the requesting client.
   */
  uint64_t account_number;

  /**
   * Index of the starting transaction.
   */
  uint64_t start_idx;

  /**
   * Requested number of results and order
   * (positive: ascending, negative: descending)
   */
  int64_t delta;

  /**
   * Timeout for long polling.
   */
  struct GNUNET_TIME_Relative lp_timeout;

  /**
   * #GNUNET_YES if starting point was given.
   */
  int have_start;

};


/**
 * Parse URL history arguments, of _both_ APIs:
 * /history/incoming and /history/outgoing.
 *
 * @param connection MHD connection.
 * @param function_name name of the caller.
 * @param ha[out] will contain the parsed values.
 * @return GNUNET_OK only if the parsing succeedes.
 */
static int
parse_history_common_args (struct MHD_Connection *connection,
                           struct HistoryArgs *ha)
{
  const char *start;
  const char *delta;
  const char *long_poll_ms;
  unsigned long long lp_timeout;
  unsigned long long sval;
  long long d;

  start = MHD_lookup_connection_value (connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "start");
  ha->have_start = (NULL != start);
  delta = MHD_lookup_connection_value (connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "delta");
  long_poll_ms = MHD_lookup_connection_value (connection,
                                              MHD_GET_ARGUMENT_KIND,
                                              "long_poll_ms");
  lp_timeout = 0;
  if ( (NULL == delta) ||
       (1 != sscanf (delta,
                     "%lld",
                     &d)) ||
       ( (NULL != long_poll_ms) &&
         (1 != sscanf (long_poll_ms,
                       "%llu",
                       &lp_timeout)) ) ||
       ( (NULL != start) &&
         (1 != sscanf (start,
                       "%llu",
                       &sval)) ) )
  {
    /* Fail if one of the above failed.  */
    /* Invalid request, given that this is fakebank we impolitely
     * just kill the connection instead of returning a nice error.
     */
    GNUNET_break (0);
    return GNUNET_NO;
  }
  if (NULL == start)
    ha->start_idx = (d > 0) ? 0 : UINT64_MAX;
  else
    ha->start_idx = (uint64_t) sval;
  ha->delta = (int64_t) d;
  ha->lp_timeout
    = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                     lp_timeout);
  return GNUNET_OK;
}


/**
 * Handle incoming HTTP request for /history/outgoing
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account which account the request is about
 * @return MHD result code
 */
static int
handle_credit_history (struct TALER_FAKEBANK_Handle *h,
                       struct MHD_Connection *connection,
                       const char *account)
{
  struct HistoryArgs ha;
  struct Transaction *pos;
  json_t *history;

  if (GNUNET_OK !=
      parse_history_common_args (connection,
                                 &ha))
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  if (! ha.have_start)
  {
    pos = (0 > ha.delta)
          ? h->transactions_tail
          : h->transactions_head;
  }
  else if (NULL != h->transactions_head)
  {
    for (pos = h->transactions_head;
         NULL != pos;
         pos = pos->next)
      if (pos->row_id  == ha.start_idx)
        break;
    if (NULL == pos)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid start specified, transaction %llu not known!\n",
                  (unsigned long long) ha.start_idx);
      return MHD_NO;
    }
    /* range is exclusive, skip the matching entry */
    if (ha.delta > 0)
      pos = pos->next;
    if (ha.delta < 0)
      pos = pos->prev;
  }
  else
  {
    /* list is empty */
    pos = NULL;
  }
  history = json_array ();
  while ( (0 != ha.delta) &&
          (NULL != pos) )
  {
    if ( (0 == strcasecmp (pos->credit_account,
                           account)) &&
         (T_DEBIT == pos->type) )
    {
      json_t *trans;
      char *credit_payto;
      char *debit_payto;

      credit_payto = TALER_payto_xtalerbank_make (h->my_baseurl,
                                                  account);
      debit_payto = TALER_payto_xtalerbank_make (h->my_baseurl,
                                                 pos->debit_account);
      trans = json_pack
                ("{s:I, s:o, s:o, s:s, s:s, s:s, s:o}",
                "row_id", (json_int_t) pos->row_id,
                "date", GNUNET_JSON_from_time_abs (pos->date),
                "amount", TALER_JSON_from_amount (&pos->amount),
                "credit_account", credit_payto,
                "debit_account", debit_payto,
                "exchange_base_url",
                pos->subject.debit.exchange_base_url,
                "wtid", GNUNET_JSON_from_data_auto (
                  &pos->subject.debit.wtid));
      GNUNET_free (credit_payto);
      GNUNET_free (debit_payto);
      GNUNET_assert (0 ==
                     json_array_append_new (history,
                                            trans));
      if (ha.delta > 0)
        ha.delta--;
      else
        ha.delta++;
    }
    if (ha.delta > 0)
      pos = pos->prev;
    else
      pos = pos->next;
  }
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o}",
                                    "outgoing_transactions",
                                    history);
}


/**
 * Handle incoming HTTP request for /history/incoming
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account which account the request is about
 * @return MHD result code
 */
static int
handle_debit_history (struct TALER_FAKEBANK_Handle *h,
                      struct MHD_Connection *connection,
                      const char *account)
{
  struct HistoryArgs ha;
  struct Transaction *pos;
  json_t *history;

  if (GNUNET_OK !=
      parse_history_common_args (connection,
                                 &ha))
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  if (! ha.have_start)
  {
    pos = (0 > ha.delta)
          ? h->transactions_tail
          : h->transactions_head;
  }
  else if (NULL != h->transactions_head)
  {
    for (pos = h->transactions_head;
         NULL != pos;
         pos = pos->next)
      if (pos->row_id  == ha.start_idx)
        break;
    if (NULL == pos)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid start specified, transaction %llu not known!\n",
                  (unsigned long long) ha.start_idx);
      return MHD_NO;
    }
    /* range is exclusive, skip the matching entry */
    if (ha.delta > 0)
      pos = pos->next;
    if (ha.delta < 0)
      pos = pos->prev;
  }
  else
  {
    /* list is empty */
    pos = NULL;
  }
  history = json_array ();
  while ( (0 != ha.delta) &&
          (NULL != pos) )
  {
    if ( (0 == strcasecmp (pos->debit_account,
                           account)) &&
         (T_CREDIT == pos->type) )
    {
      json_t *trans;
      char *credit_payto;
      char *debit_payto;

      credit_payto = TALER_payto_xtalerbank_make (h->my_baseurl,
                                                  pos->credit_account);
      debit_payto = TALER_payto_xtalerbank_make (h->my_baseurl,
                                                 account);
      trans = json_pack
                ("{s:I, s:o, s:o, s:s, s:s, s:s}",
                "row_id", (json_int_t) pos->row_id,
                "date", GNUNET_JSON_from_time_abs (pos->date),
                "amount", TALER_JSON_from_amount (&pos->amount),
                "credit_account", credit_payto,
                "debit_account", debit_payto,
                "reserve_pub", pos->subject /* we "know" it is OK */);
      GNUNET_free (credit_payto);
      GNUNET_free (debit_payto);
      GNUNET_assert (0 ==
                     json_array_append_new (history,
                                            trans));
      if (ha.delta > 0)
        ha.delta--;
      else
        ha.delta++;
    }
    if (ha.delta > 0)
      pos = pos->prev;
    else
      pos = pos->next;
  }
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o}",
                                    "incoming_transactions",
                                    history);
}


/**
 * Handle incoming HTTP request.
 *
 * @param h our handle
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param account which account should process the request
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request (a `struct Buffer *`)
 * @return MHD result code
 */
static int
serve (struct TALER_FAKEBANK_Handle *h,
       struct MHD_Connection *connection,
       const char *account,
       const char *url,
       const char *method,
       const char *upload_data,
       size_t *upload_data_size,
       void **con_cls)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Fakebank, serving URL `%s' for account `%s'\n",
              url,
              account);
  if ( (0 == strcmp (url,
                     "/")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
    return handle_home_page (h,
                             connection,
                             con_cls);
  if ( (0 == strcmp (url,
                     "/admin/add-incoming")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
    return handle_admin_add_incoming (h,
                                      connection,
                                      account,
                                      upload_data,
                                      upload_data_size,
                                      con_cls);
  if ( (0 == strcmp (url,
                     "/transfer")) &&
       (NULL != account) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
    return handle_transfer (h,
                            connection,
                            account,
                            upload_data,
                            upload_data_size,
                            con_cls);
  if ( (0 == strcmp (url,
                     "/history/incoming")) &&
       (NULL != account) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
    return handle_debit_history (h,
                                 connection,
                                 account);
  if ( (0 == strcmp (url,
                     "/history/outgoing")) &&
       (NULL != account) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
    return handle_credit_history (h,
                                  connection,
                                  account);

  /* Unexpected URL path, just close the connection. */
  /* we're rather impolite here, but it's a testcase. */
  TALER_LOG_ERROR ("Breaking URL: %s\n",
                   url);
  GNUNET_break_op (0);
  return MHD_NO;
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
  char *account = NULL;
  char *end;
  int ret;

  (void) version;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling request for `%s'\n",
              url);
  if ( (strlen (url) > 1) &&
       (NULL != (end = strchr (url + 1, '/'))) )
  {
    account = GNUNET_strndup (url + 1,
                              end - url - 1);
    url = end;
  }
  ret = serve (h,
               connection,
               account,
               url,
               method,
               upload_data,
               upload_data_size,
               con_cls);
  GNUNET_free_non_null (account);
  return ret;
}


/**
 * Task run whenever HTTP server operations are pending.
 *
 * @param cls the `struct TALER_FAKEBANK_Handle`
 */
static void
run_mhd (void *cls);


#if EPOLL_SUPPORT
/**
 * Schedule MHD.  This function should be called initially when an
 * MHD is first getting its client socket, and will then automatically
 * always be called later whenever there is work to be done.
 *
 * @param h fakebank handle to schedule MHD for
 */
static void
schedule_httpd (struct TALER_FAKEBANK_Handle *h)
{
  int haveto;
  MHD_UNSIGNED_LONG_LONG timeout;
  struct GNUNET_TIME_Relative tv;

  haveto = MHD_get_timeout (h->mhd_bank,
                            &timeout);
  if (MHD_YES == haveto)
    tv.rel_value_us = (uint64_t) timeout * 1000LL;
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  if (NULL != h->mhd_task)
    GNUNET_SCHEDULER_cancel (h->mhd_task);
  h->mhd_task =
    GNUNET_SCHEDULER_add_read_net (tv,
                                   h->mhd_rfd,
                                   &run_mhd,
                                   h);
}


#else
/**
 * Schedule MHD.  This function should be called initially when an
 * MHD is first getting its client socket, and will then automatically
 * always be called later whenever there is work to be done.
 *
 * @param h fakebank handle to schedule MHD for
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


#endif


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
  h->port = port;
  GNUNET_asprintf (&h->my_baseurl,
                   "http://localhost:%u/",
                   (unsigned int) port);
  h->mhd_bank = MHD_start_daemon (MHD_USE_DEBUG
#if EPOLL_SUPPORT
                                  | MHD_USE_EPOLL_INTERNAL_THREAD
#else
                                  | MHD_USE_INTERNAL_POLLING_THREAD
#endif
                                  | MHD_USE_DUAL_STACK,
                                  port,
                                  NULL, NULL,
                                  &handle_mhd_request, h,
                                  MHD_OPTION_NOTIFY_COMPLETED,
                                  &handle_mhd_completion_callback, h,
                                  MHD_OPTION_LISTEN_BACKLOG_SIZE, (unsigned
                                                                   int) 1024,
                                  MHD_OPTION_END);
  if (NULL == h->mhd_bank)
  {
    GNUNET_free (h);
    return NULL;
  }
#if EPOLL_SUPPORT
  h->mhd_fd = MHD_get_daemon_info (h->mhd_bank,
                                   MHD_DAEMON_INFO_EPOLL_FD)->epoll_fd;
  h->mhd_rfd = GNUNET_NETWORK_socket_box_native (h->mhd_fd);
#endif
  schedule_httpd (h);
  return h;
}


/* end of fakebank.c */
