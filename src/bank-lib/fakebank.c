/*
  This file is part of TALER
  (C) 2016-2021 Taler Systems SA

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
// TODO: support long polling
// TODO: support adding WAD transfers
// TODO: adapt taler-exchange-benchmark to profile bank API
// FIXME: support 'close_connections' option

#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>

/**
 * Maximum POST request size (for /admin/add-incoming)
 */
#define REQUEST_BUFFER_MAX (4 * 1024)

/**
 * How long are exchange base URLs allowed to be at most?
 * Set to a relatively low number as this does contribute
 * significantly to our RAM consumption.
 */
#define MAX_URL_LEN 64

/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction;

/**
 * Per account information.
 */
struct Account
{

  /**
   * Inbound transactions for this account in a MDLL.
   */
  struct Transaction *in_head;

  /**
   * Inbound transactions for this account in a MDLL.
   */
  struct Transaction *in_tail;

  /**
   * Outbound transactions for this account in a MDLL.
   */
  struct Transaction *out_head;

  /**
   * Outbound transactions for this account in a MDLL.
   */
  struct Transaction *out_tail;

  /**
   * Account name (string, not payto!)
   */
  char *account_name;

  /**
   * Current account balance.
   */
  struct TALER_Amount balance;

  /**
   * true if the balance is negative.
   */
  bool is_negative;

};


/**
 * Details about a transcation we (as the simulated bank) received.
 */
struct Transaction
{
  /**
   * We store inbound transactions in a MDLL.
   */
  struct Transaction *next_in;

  /**
   * We store inbound transactions in a MDLL.
   */
  struct Transaction *prev_in;

  /**
   * We store outbound transactions in a MDLL.
   */
  struct Transaction *next_out;

  /**
   * We store outbound transactions in a MDLL.
   */
  struct Transaction *prev_out;

  /**
   * Amount to be transferred.
   */
  struct TALER_Amount amount;

  /**
   * Account to debit.
   */
  struct Account *debit_account;

  /**
   * Account to credit.
   */
  struct Account *credit_account;

  /**
   * Random unique identifier for the request.
   * Used to detect idempotent requests.
   */
  struct GNUNET_HashCode request_uid;

  /**
   * When did the transaction happen?
   */
  struct GNUNET_TIME_Absolute date;

  /**
   * Number of this transaction.
   */
  uint64_t row_id;

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
    T_DEBIT,

    /**
     * Exchange-to-exchange WAD transfer.
     */
    T_WAD,
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
      char exchange_base_url[MAX_URL_LEN];

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

    /**
     * Used if @e type is T_WAD.
     */
    struct
    {

      /**
       * Subject of the transfer.
       */
      struct TALER_WadIdentifierP wad;

      /**
       * Base URL of the originating exchange.
       */
      char origin_base_url[MAX_URL_LEN];

    } wad;

  } subject;

  /**
   * Has this transaction not yet been subjected to
   * #TALER_FAKEBANK_check_credit() or #TALER_FAKEBANK_check_debit() and
   * should thus be counted in #TALER_FAKEBANK_check_empty()?
   */
  bool unchecked;
};


/**
 * Handle for the fake bank.
 */
struct TALER_FAKEBANK_Handle
{
  /**
   * We store transactions in a revolving array.
   */
  struct Transaction **transactions;

  /**
   * HTTP server we run to pretend to be the "test" bank.
   */
  struct MHD_Daemon *mhd_bank;

  /**
   * Task running HTTP server for the "test" bank,
   * unless we are using a thread pool (then NULL).
   */
  struct GNUNET_SCHEDULER_Task *mhd_task;

  /**
   * Hashmap of reserve public keys to
   * `struct Transaction` with that reserve public
   * key. Used to prevent public-key re-use.
   */
  struct GNUNET_CONTAINER_MultiPeerMap *rpubs;

  /**
   * Lock for accessing @a rpubs map.
   */
  pthread_mutex_t rpubs_lock;

  /**
   * Hashmap of hashes of account names to `struct Account`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *accounts;

  /**
   * Lock for accessing @a accounts hash map.
   */
  pthread_mutex_t accounts_lock;

  /**
   * Hashmap of hashes of transaction request_uids to `struct Transaction`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *uuid_map;

  /**
   * Lock for accessing @a uuid_map.
   */
  pthread_mutex_t uuid_map_lock;

  /**
   * Lock for accessing the internals of
   * accounts and transaction array entries.
   */
  pthread_mutex_t big_lock;

  /**
   * Current transaction counter.
   */
  uint64_t serial_counter;

  /**
   * Number of transactions we keep in memory (at most).
   */
  uint64_t ram_limit;

  /**
   * Currency used by the fakebank.
   */
  char *currency;

  /**
   * BaseURL of the fakebank.
   */
  char *my_baseurl;

  /**
   * Our port number.
   */
  uint16_t port;

  /**
   * Force closing connections after each request.
   */
  bool force_close;

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
 * Lookup account with @a name, and if it does not exist, create it.
 *
 * @param[in,out] h bank to lookup account at
 * @param name account name to resolve
 * @return account handle (never NULL)
 */
static struct Account *
lookup_account (struct TALER_FAKEBANK_Handle *h,
                const char *name)
{
  struct GNUNET_HashCode hc;
  size_t slen;
  struct Account *account;

  memset (&hc,
          0,
          sizeof (hc));
  slen = strlen (name);
  if (slen < sizeof (hc))
    memcpy (&hc,
            name,
            slen); /* fake hashing for speed! */
  else
    GNUNET_CRYPTO_hash (name,
                        strlen (name),
                        &hc);
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->accounts_lock));
  account = GNUNET_CONTAINER_multihashmap_get (h->accounts,
                                               &hc);
  if (NULL == account)
  {
    account = GNUNET_new (struct Account);
    account->account_name = GNUNET_strdup (name);
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (h->currency,
                                          &account->balance));
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (h->accounts,
                                                      &hc,
                                                      account,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->accounts_lock));
  return account;
}


/**
 * Generate log messages for failed check operation.
 *
 * @param h handle to output transaction log for
 */
static void
check_log (struct TALER_FAKEBANK_Handle *h)
{
  for (uint64_t i = 0; i<h->ram_limit; i++)
  {
    struct Transaction *t = h->transactions[i];

    if (NULL == t)
      continue;
    if (t->unchecked)
      continue;
    switch (t->type)
    {
    case T_DEBIT:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  t->subject.debit.exchange_base_url,
                  "DEBIT");
      break;
    case T_CREDIT:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  TALER_B2S (&t->subject.credit.reserve_pub),
                  "CREDIT");
      break;
    case T_WAD:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s[%s] (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  t->subject.wad.origin_base_url,
                  TALER_B2S (&t->subject.wad),
                  "WAD");
      break;
    }
  }
}


int
TALER_FAKEBANK_check_debit (struct TALER_FAKEBANK_Handle *h,
                            const struct TALER_Amount *want_amount,
                            const char *want_debit,
                            const char *want_credit,
                            const char *exchange_base_url,
                            struct TALER_WireTransferIdentifierRawP *wtid)
{
  struct Account *debit_account;
  struct Account *credit_account;

  GNUNET_assert (0 ==
                 strcasecmp (want_amount->currency,
                             h->currency));
  debit_account = lookup_account (h,
                                  want_debit);
  credit_account = lookup_account (h,
                                   want_credit);
  for (struct Transaction *t = debit_account->out_tail;
       NULL != t;
       t = t->prev_out)
  {
    if ( (t->unchecked) &&
         (credit_account == t->credit_account) &&
         (T_DEBIT == t->type) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (0 == strcasecmp (exchange_base_url,
                           t->subject.debit.exchange_base_url)) )
    {
      *wtid = t->subject.debit.wtid;
      t->unchecked = false;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Did not find matching transaction! I have:\n");
  check_log (h);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "I wanted: %s->%s (%s) from exchange %s (DEBIT)\n",
              want_debit,
              want_credit,
              TALER_amount2s (want_amount),
              exchange_base_url);
  return GNUNET_SYSERR;
}


int
TALER_FAKEBANK_check_credit (struct TALER_FAKEBANK_Handle *h,
                             const struct TALER_Amount *want_amount,
                             const char *want_debit,
                             const char *want_credit,
                             const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct Account *debit_account;
  struct Account *credit_account;

  GNUNET_assert (0 == strcasecmp (want_amount->currency,
                                  h->currency));
  debit_account = lookup_account (h,
                                  want_debit);
  credit_account = lookup_account (h,
                                   want_credit);
  for (struct Transaction *t = credit_account->in_tail;
       NULL != t;
       t = t->prev_in)
  {
    if ( (t->unchecked) &&
         (debit_account == t->debit_account) &&
         (T_CREDIT == t->type) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (0 == GNUNET_memcmp (reserve_pub,
                              &t->subject.credit.reserve_pub)) )
    {
      t->unchecked = false;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Did not find matching transaction!\nI have:\n");
  check_log (h);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "I wanted:\n%s -> %s (%s) with subject %s (CREDIT)\n",
              want_debit,
              want_credit,
              TALER_amount2s (want_amount),
              TALER_B2S (reserve_pub));
  return GNUNET_SYSERR;
}


/**
 * Update @a account balance by @a amount.
 *
 * The @a big_lock must already be locked when calling
 * this function.
 *
 * @param[in,out] account account to update
 * @param amount balance change
 * @param debit true to subtract, false to add @a amount
 */
static void
update_balance (struct Account *account,
                const struct TALER_Amount *amount,
                bool debit)
{
  if (debit == account->is_negative)
  {
    GNUNET_assert (0 <=
                   TALER_amount_add (&account->balance,
                                     &account->balance,
                                     amount));
    return;
  }
  if (0 <= TALER_amount_cmp (&account->balance,
                             amount))
  {
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&account->balance,
                                          &account->balance,
                                          amount));
  }
  else
  {
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&account->balance,
                                          amount,
                                          &account->balance));
    account->is_negative = ! account->is_negative;
  }
}


/**
 * Add transaction to the debit and credit accounts,
 * updating the balances as needed.
 *
 * The transaction @a t must already be locked
 * when calling this function!
 *
 * @param[in,out] h bank handle
 * @param[in,out] t transaction to add to account lists
 */
static void
post_transaction (struct TALER_FAKEBANK_Handle *h,
                  struct Transaction *t)
{
  struct Account *debit_acc = t->debit_account;
  struct Account *credit_acc = t->credit_account;
  uint64_t row_id;
  struct Transaction *old;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  row_id = ++h->serial_counter;
  old = h->transactions[row_id % h->ram_limit];
  h->transactions[row_id % h->ram_limit] = t;
  t->row_id = row_id;
  GNUNET_CONTAINER_MDLL_insert_tail (out,
                                     debit_acc->out_head,
                                     debit_acc->out_tail,
                                     t);
  update_balance (debit_acc,
                  &t->amount,
                  true);
  GNUNET_CONTAINER_MDLL_insert_tail (in,
                                     credit_acc->in_head,
                                     credit_acc->in_tail,
                                     t);
  update_balance (credit_acc,
                  &t->amount,
                  false);
  if (NULL != old)
  {
    struct Account *da;
    struct Account *ca;

    da = old->debit_account;
    ca = old->credit_account;
    /* slot was already in use, must clean out old
       entry first! */
    GNUNET_CONTAINER_MDLL_remove (out,
                                  da->out_head,
                                  da->out_tail,
                                  old);
    GNUNET_CONTAINER_MDLL_remove (in,
                                  ca->in_head,
                                  ca->in_tail,
                                  old);
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  if ( (NULL != old) &&
       (T_DEBIT == old->type) )
  {
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->uuid_map_lock));
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_remove (h->uuid_map,
                                                         &old->request_uid,
                                                         old));
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->uuid_map_lock));
  }
  GNUNET_free (old);
}


/**
 * Tell the fakebank to create another wire transfer *from* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param subject wire transfer subject to use
 * @param exchange_base_url exchange URL
 * @param request_uid unique number to make the request unique, or NULL to create one
 * @param[out] ret_row_id pointer to store the row ID of this transaction
 * @return #GNUNET_YES if the transfer was successful,
 *         #GNUNET_SYSERR if the request_uid was reused for a different transfer
 */
static int
make_transfer (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_WireTransferIdentifierRawP *subject,
  const char *exchange_base_url,
  const struct GNUNET_HashCode *request_uid,
  uint64_t *ret_row_id)
{
  struct Transaction *t;
  struct Account *debit_acc;
  struct Account *credit_acc;
  size_t url_len;

  GNUNET_assert (0 == strcasecmp (amount->currency,
                                  h->currency));
  GNUNET_break (0 != strncasecmp ("payto://",
                                  debit_account,
                                  strlen ("payto://")));
  GNUNET_break (0 != strncasecmp ("payto://",
                                  credit_account,
                                  strlen ("payto://")));
  url_len = strlen (exchange_base_url);
  GNUNET_assert (url_len < MAX_URL_LEN);
  debit_acc = lookup_account (h,
                              debit_account);
  credit_acc = lookup_account (h,
                               credit_account);
  if (NULL != request_uid)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->uuid_map_lock));
    t = GNUNET_CONTAINER_multihashmap_get (h->uuid_map,
                                           request_uid);
    if (NULL != t)
    {
      if ( (debit_acc != t->debit_account) ||
           (credit_acc != t->credit_account) ||
           (0 != TALER_amount_cmp (amount,
                                   &t->amount)) ||
           (T_DEBIT != t->type) ||
           (0 != GNUNET_memcmp (subject,
                                &t->subject.debit.wtid)) )
      {
        /* Transaction exists, but with different details. */
        GNUNET_break (0);
        GNUNET_assert (0 ==
                       pthread_mutex_unlock (&h->uuid_map_lock));
        return GNUNET_SYSERR;
      }
      *ret_row_id = t->row_id;
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->uuid_map_lock));
      return GNUNET_OK;
    }
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->uuid_map_lock));
  }
  t = GNUNET_new (struct Transaction);
  t->unchecked = true;
  t->debit_account = debit_acc;
  t->credit_account = credit_acc;
  t->amount = *amount;
  t->date = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&t->date);
  t->type = T_DEBIT;
  memcpy (t->subject.debit.exchange_base_url,
          exchange_base_url,
          url_len);
  t->subject.debit.wtid = *subject;
  if (NULL == request_uid)
    GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_NONCE,
                                      &t->request_uid);
  else
    t->request_uid = *request_uid;
  post_transaction (h,
                    t);
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->uuid_map_lock));
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (
                   h->uuid_map,
                   &t->request_uid,
                   t,
                   GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->uuid_map_lock));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Making transfer %llu from %s to %s over %s and subject %s; for exchange: %s\n",
              (unsigned long long) t->row_id,
              debit_account,
              credit_account,
              TALER_amount2s (amount),
              TALER_B2S (subject),
              exchange_base_url);
  *ret_row_id = t->row_id;
  return GNUNET_OK;
}


/**
 * Tell the fakebank to create another wire transfer *to* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param reserve_pub reserve public key to use in subject
 * @param[out] row_id serial_id of the transfer
 * @param[out] timestamp when was the transfer made
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
make_admin_transfer (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *row_id,
  struct GNUNET_TIME_Absolute *timestamp)
{
  struct Transaction *t;
  const struct GNUNET_PeerIdentity *pid;
  struct Account *debit_acc;
  struct Account *credit_acc;

  GNUNET_static_assert (sizeof (*pid) ==
                        sizeof (*reserve_pub));
  pid = (const struct GNUNET_PeerIdentity *) reserve_pub;
  GNUNET_assert (NULL != debit_account);
  GNUNET_assert (NULL != credit_account);
  GNUNET_assert (0 == strcasecmp (amount->currency,
                                  h->currency));
  GNUNET_break (0 != strncasecmp ("payto://",
                                  debit_account,
                                  strlen ("payto://")));
  GNUNET_break (0 != strncasecmp ("payto://",
                                  credit_account,
                                  strlen ("payto://")));
  debit_acc = lookup_account (h,
                              debit_account);
  credit_acc = lookup_account (h,
                               credit_account);

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->rpubs_lock));
  t = GNUNET_CONTAINER_multipeermap_get (h->rpubs,
                                         pid);
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->rpubs_lock));
  if (NULL != t)
  {
    /* duplicate reserve public key not allowed */
    GNUNET_break (0);
    return GNUNET_NO;
  }

  t = GNUNET_new (struct Transaction);
  t->unchecked = true;
  t->debit_account = debit_acc;
  t->credit_account = credit_acc;
  t->amount = *amount;
  t->date = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&t->date);
  if (NULL != timestamp)
    *timestamp = t->date;
  t->type = T_CREDIT;
  t->subject.credit.reserve_pub = *reserve_pub;
  post_transaction (h,
                    t);
  if (NULL != row_id)
    *row_id = t->row_id;
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->rpubs_lock));
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multipeermap_put (
                   h->rpubs,
                   pid,
                   t,
                   GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->rpubs_lock));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Making transfer from %s to %s over %s and subject %s at row %llu\n",
              debit_account,
              credit_account,
              TALER_amount2s (amount),
              TALER_B2S (reserve_pub),
              (unsigned long long) t->row_id);
  return GNUNET_OK;
}


int
TALER_FAKEBANK_check_empty (struct TALER_FAKEBANK_Handle *h)
{
  for (uint64_t i = 0; i<h->ram_limit; i++)
  {
    struct Transaction *t = h->transactions[i];

    if ( (NULL != t) &&
         (t->unchecked) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Expected empty transaction set, but I have:\n");
      check_log (h);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


static int
free_account (void *cls,
              const struct GNUNET_HashCode *key,
              void *val)
{
  struct Account *account = val;

  GNUNET_free (account->account_name);
  GNUNET_free (account);
  return GNUNET_OK;
}


void
TALER_FAKEBANK_stop (struct TALER_FAKEBANK_Handle *h)
{
  if (NULL != h->mhd_task)
  {
    GNUNET_SCHEDULER_cancel (h->mhd_task);
    h->mhd_task = NULL;
  }
#if EPOLL_SUPPORT
  if (NULL != h->mhd_rfd)
  {
    GNUNET_NETWORK_socket_free_memory_only_ (h->mhd_rfd);
    h->mhd_rfd = NULL;
  }
#endif
  if (NULL != h->mhd_bank)
  {
    MHD_stop_daemon (h->mhd_bank);
    h->mhd_bank = NULL;
  }
  if (NULL != h->accounts)
  {
    GNUNET_CONTAINER_multihashmap_iterate (h->accounts,
                                           &free_account,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (h->accounts);
  }
  GNUNET_CONTAINER_multihashmap_destroy (h->uuid_map);
  GNUNET_CONTAINER_multipeermap_destroy (h->rpubs);
  GNUNET_assert (0 ==
                 pthread_mutex_destroy (&h->big_lock));
  GNUNET_assert (0 ==
                 pthread_mutex_destroy (&h->uuid_map_lock));
  GNUNET_assert (0 ==
                 pthread_mutex_destroy (&h->accounts_lock));
  GNUNET_assert (0 ==
                 pthread_mutex_destroy (&h->rpubs_lock));
  for (uint64_t i = 0; i<h->ram_limit; i++)
    GNUNET_free (h->transactions[i]);
  GNUNET_free (h->transactions);
  GNUNET_free (h->my_baseurl);
  GNUNET_free (h->currency);
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
static MHD_RESULT
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
  struct GNUNET_TIME_Absolute timestamp;
  enum GNUNET_GenericReturnValue ret;

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
      GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                   &reserve_pub),
      GNUNET_JSON_spec_string ("debit_account",
                               &debit_account),
      TALER_JSON_spec_amount ("amount",
                              &amount),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (json,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break (0);
      json_decref (json);
      /* We're fakebank, no need for nice error handling */
      return MHD_NO;
    }
    if (0 != strcasecmp (amount.currency,
                         h->currency))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Currency `%s' does not match our configuration\n",
                  amount.currency);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_GENERIC_CURRENCY_MISMATCH,
        NULL);
    }
    debit = TALER_xtalerbank_account_from_payto (debit_account);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Receiving incoming wire transfer: %s->%s, subject: %s, amount: %s\n",
                debit,
                account,
                TALER_B2S (&reserve_pub),
                TALER_amount2s (&amount));
    ret = make_admin_transfer (h,
                               debit,
                               account,
                               &amount,
                               &reserve_pub,
                               &row_id,
                               &timestamp);
    GNUNET_free (debit);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Reserve public key not unique\n");
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_BANK_DUPLICATE_RESERVE_PUB_SUBJECT,
        NULL);
    }
  }
  json_decref (json);

  /* Finally build response object */
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:I, s:o}",
                                    "row_id",
                                    (json_int_t) row_id,
                                    "timestamp",
                                    GNUNET_JSON_from_time_abs (timestamp));
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
static MHD_RESULT
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
    char *credit;
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
      /* We are fakebank, no need for nice error handling */
      return MHD_NO;
    }
    {
      int ret;

      credit = TALER_xtalerbank_account_from_payto (credit_account);
      ret = make_transfer (h,
                           account,
                           credit,
                           &amount,
                           &wtid,
                           base_url,
                           &uuid,
                           &row_id);
      if (GNUNET_OK != ret)
      {
        MHD_RESULT res;
        char *uids;

        GNUNET_break (0);
        uids = GNUNET_STRINGS_data_to_string_alloc (&uuid,
                                                    sizeof (uuid));
        json_decref (json);
        res = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_CONFLICT,
                                          TALER_EC_BANK_TRANSFER_REQUEST_UID_REUSED,
                                          uids);
        GNUNET_free (uids);
        return res;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Receiving incoming wire transfer: %s->%s, subject: %s, amount: %s, from %s\n",
                  account,
                  credit,
                  TALER_B2S (&wtid),
                  TALER_amount2s (&amount),
                  base_url);
      GNUNET_free (credit);
    }
  }
  json_decref (json);

  /* Finally build response object */
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:I, s:o}",
                                    "row_id",
                                    (json_int_t) row_id,
                                    /* dummy timestamp */
                                    "timestamp", GNUNET_JSON_from_time_abs (
                                      GNUNET_TIME_UNIT_ZERO_ABS));
}


/**
 * Handle incoming HTTP request for / (home page).
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param con_cls place to store state, not used
 * @return MHD result code
 */
static MHD_RESULT
handle_home_page (struct TALER_FAKEBANK_Handle *h,
                  struct MHD_Connection *connection,
                  void **con_cls)
{
  MHD_RESULT ret;
  struct MHD_Response *resp;
#define HELLOMSG "Hello, Fakebank!"

  (void) h;
  (void) con_cls;
  resp = MHD_create_response_from_buffer (
    strlen (HELLOMSG),
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
   * true if starting point was given.
   */
  bool have_start;

};


/**
 * Parse URL history arguments, of _both_ APIs:
 * /history/incoming and /history/outgoing.
 *
 * @param connection MHD connection.
 * @param[out] ha will contain the parsed values.
 * @return #GNUNET_OK only if the parsing succeeds.
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
  if (0 == ha->delta)
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
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
static MHD_RESULT
handle_debit_history (struct TALER_FAKEBANK_Handle *h,
                      struct MHD_Connection *connection,
                      const char *account)
{
  struct HistoryArgs ha;
  struct Account *acc;
  struct Transaction *pos;
  json_t *history;
  char *debit_payto;

  if (GNUNET_OK !=
      parse_history_common_args (connection,
                                 &ha))
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  acc = lookup_account (h,
                        account);
  GNUNET_asprintf (&debit_payto,
                   "payto://x-taler-bank/localhost/%s",
                   account);
  history = json_array ();
  if (NULL == history)
  {
    GNUNET_break (0);
    GNUNET_free (debit_payto);
    return MHD_NO;
  }
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  if (! ha.have_start)
  {
    pos = (0 > ha.delta)
          ? acc->out_tail
          : acc->out_head;
  }
  else
  {
    struct Transaction *t = h->transactions[ha.start_idx % h->ram_limit];

    if ( (NULL == t) ||
         (t->row_id != ha.start_idx) )
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      GNUNET_free (debit_payto);
      /* FIXME: suspend for long-polling instead */
      return TALER_MHD_reply_json_pack (connection,
                                        MHD_HTTP_OK,
                                        "{s:o}",
                                        "outgoing_transactions",
                                        history);
    }
    if (t->debit_account != acc)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid start specified, transaction %llu not with account %s!\n",
                  (unsigned long long) ha.start_idx,
                  account);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      GNUNET_free (debit_payto);
      json_decref (history);
      return MHD_NO;
    }
    /* range is exclusive, skip the matching entry */
    if (0 > ha.delta)
      pos = t->prev_out;
    else
      pos = t->next_out;
  }
  while ( (0 != ha.delta) &&
          (NULL != pos) )
  {
    json_t *trans;
    char *credit_payto;

    GNUNET_assert (T_DEBIT == pos->type);
    GNUNET_asprintf (&credit_payto,
                     "payto://x-taler-bank/localhost/%s",
                     pos->credit_account->account_name);
    trans = json_pack (
      "{s:I, s:o, s:o, s:s, s:s, s:s, s:o}",
      "row_id", (json_int_t) pos->row_id,
      "date", GNUNET_JSON_from_time_abs (pos->date),
      "amount", TALER_JSON_from_amount (&pos->amount),
      "credit_account", credit_payto,
      "debit_account", debit_payto,          // FIXME: inefficient to return this here always!
      "exchange_base_url",
      pos->subject.debit.exchange_base_url,
      "wtid", GNUNET_JSON_from_data_auto (
        &pos->subject.debit.wtid));
    GNUNET_assert (NULL != trans);
    GNUNET_free (credit_payto);
    GNUNET_assert (0 ==
                   json_array_append_new (history,
                                          trans));
    if (ha.delta > 0)
      ha.delta--;
    else
      ha.delta++;
    if (0 > ha.delta)
      pos = pos->prev_out;
    if (0 < ha.delta)
      pos = pos->next_out;
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  GNUNET_free (debit_payto);
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
static MHD_RESULT
handle_credit_history (struct TALER_FAKEBANK_Handle *h,
                       struct MHD_Connection *connection,
                       const char *account)
{
  struct HistoryArgs ha;
  struct Account *acc;
  const struct Transaction *pos;
  json_t *history;
  char *credit_payto;

  if (GNUNET_OK !=
      parse_history_common_args (connection,
                                 &ha))
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  acc = lookup_account (h,
                        account);
  history = json_array ();
  GNUNET_assert (NULL != history);
  GNUNET_asprintf (&credit_payto,
                   "payto://x-taler-bank/localhost/%s",
                   account);
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  if (! ha.have_start)
  {
    pos = (0 > ha.delta)
          ? acc->in_tail
          : acc->in_head;
  }
  else
  {
    struct Transaction *t = h->transactions[ha.start_idx % h->ram_limit];

    if ( (NULL == t) ||
         (t->row_id != ha.start_idx) )
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      GNUNET_free (credit_payto);
      /* FIXME: suspend for long-polling instead */
      return TALER_MHD_reply_json_pack (connection,
                                        MHD_HTTP_OK,
                                        "{s:o}",
                                        "incoming_transactions",
                                        history);
    }
    if (t->credit_account != acc)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid start specified, transaction %llu not with account %s!\n",
                  (unsigned long long) ha.start_idx,
                  account);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      json_decref (history);
      GNUNET_free (credit_payto);
      return MHD_NO;
    }
    /* range is exclusive, skip the matching entry */
    if (0 > ha.delta)
      pos = t->prev_in;
    else
      pos = t->next_in;
  }
  while ( (0 != ha.delta) &&
          (NULL != pos) )
  {
    json_t *trans;
    char *debit_payto;

    GNUNET_assert (T_CREDIT == pos->type);
    GNUNET_asprintf (&debit_payto,
                     "payto://x-taler-bank/localhost/%s",
                     pos->debit_account->account_name);
    trans = json_pack (
      "{s:I, s:o, s:o, s:s, s:s, s:o}",
      "row_id", (json_int_t) pos->row_id,
      "date", GNUNET_JSON_from_time_abs (pos->date),
      "amount", TALER_JSON_from_amount (&pos->amount),
      "credit_account", credit_payto,            // FIXME: inefficient to repeat this always here!
      "debit_account", debit_payto,
      "reserve_pub", GNUNET_JSON_from_data_auto (
        &pos->subject.credit.reserve_pub));
    GNUNET_assert (NULL != trans);
    GNUNET_free (debit_payto);
    GNUNET_assert (0 ==
                   json_array_append_new (history,
                                          trans));
    if (ha.delta > 0)
      ha.delta--;
    else
      ha.delta++;
    if (0 > ha.delta)
      pos = pos->prev_in;
    if (0 < ha.delta)
      pos = pos->next_in;
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  GNUNET_free (credit_payto);
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
static MHD_RESULT
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
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_GET))
  {
    if ( (0 == strcmp (url,
                       "/history/incoming")) &&
         (NULL != account) )
      return handle_credit_history (h,
                                    connection,
                                    account);
    if ( (0 == strcmp (url,
                       "/history/outgoing")) &&
         (NULL != account) )
      return handle_debit_history (h,
                                   connection,
                                   account);
    if (0 == strcmp (url,
                     "/"))
      return handle_home_page (h,
                               connection,
                               con_cls);
  }
  else if (0 == strcasecmp (method,
                            MHD_HTTP_METHOD_POST))
  {
    if (0 == strcmp (url,
                     "/admin/add-incoming"))
      return handle_admin_add_incoming (h,
                                        connection,
                                        account,
                                        upload_data,
                                        upload_data_size,
                                        con_cls);
    if ( (0 == strcmp (url,
                       "/transfer")) &&
         (NULL != account) )
      return handle_transfer (h,
                              connection,
                              account,
                              upload_data,
                              upload_data_size,
                              con_cls);
  }
  /* Unexpected URL path, just close the connection. */
  /* We're rather impolite here, but it's a testcase. */
  TALER_LOG_ERROR ("Breaking URL: %s %s\n",
                   method,
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
static MHD_RESULT
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
  MHD_RESULT ret;

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
  GNUNET_free (account);
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
  if (MHD_YES != MHD_get_fdset (h->mhd_bank,
                                &rs,
                                &ws,
                                &es,
                                &max))
  {
    GNUNET_assert (0);
    return;
  }
  haveto = MHD_get_timeout (h->mhd_bank,
                            &timeout);
  if (MHD_YES == haveto)
    tv.rel_value_us = (uint64_t) timeout * 1000LL;
  else
    tv = GNUNET_TIME_UNIT_FOREVER_REL;
  if (-1 != max)
  {
    wrs = GNUNET_NETWORK_fdset_create ();
    wws = GNUNET_NETWORK_fdset_create ();
    GNUNET_NETWORK_fdset_copy_native (wrs,
                                      &rs,
                                      max + 1);
    GNUNET_NETWORK_fdset_copy_native (wws,
                                      &ws,
                                      max + 1);
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
                                 &run_mhd,
                                 h);
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


struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start (uint16_t port,
                      const char *currency)
{
  return TALER_FAKEBANK_start2 (port,
                                currency,
                                65536, /* RAM limit */
                                1, /* number of threads */
                                false);
}


struct TALER_FAKEBANK_Handle *
TALER_FAKEBANK_start2 (uint16_t port,
                       const char *currency,
                       uint64_t ram_limit,
                       unsigned int num_threads,
                       bool close_connections)
{
  struct TALER_FAKEBANK_Handle *h;

  if (SIZE_MAX / sizeof (struct Transaction *) < ram_limit)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "This CPU architecture does not support keeping %llu transactions in RAM\n",
                (unsigned long long) ram_limit);
    return NULL;
  }
  GNUNET_assert (strlen (currency) < TALER_CURRENCY_LEN);
  h = GNUNET_new (struct TALER_FAKEBANK_Handle);
  h->port = port;
  h->force_close = close_connections;
  h->ram_limit = ram_limit;
  h->serial_counter = 0;
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->accounts_lock,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->rpubs_lock,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->uuid_map_lock,
                                     NULL));
  GNUNET_assert (0 ==
                 pthread_mutex_init (&h->big_lock,
                                     NULL));
  h->transactions
    = GNUNET_malloc_large (sizeof (struct Transaction *)
                           * ram_limit);
  if (NULL == h->transactions)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    TALER_FAKEBANK_stop (h);
    return NULL;
  }
  h->accounts = GNUNET_CONTAINER_multihashmap_create (128,
                                                      GNUNET_NO);
  h->uuid_map = GNUNET_CONTAINER_multihashmap_create (ram_limit * 4 / 3,
                                                      GNUNET_YES);
  if (NULL == h->uuid_map)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    TALER_FAKEBANK_stop (h);
    return NULL;
  }
  h->rpubs = GNUNET_CONTAINER_multipeermap_create (ram_limit * 4 / 3,
                                                   GNUNET_NO);
  if (NULL == h->rpubs)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "malloc");
    TALER_FAKEBANK_stop (h);
    return NULL;
  }
  h->currency = GNUNET_strdup (currency);
  GNUNET_asprintf (&h->my_baseurl,
                   "http://localhost:%u/",
                   (unsigned int) port);
  if (0 == num_threads)
  {
    h->mhd_bank = MHD_start_daemon (MHD_USE_DEBUG
#if EPOLL_SUPPORT
                                    | MHD_USE_EPOLL
#endif
                                    | MHD_USE_DUAL_STACK
                                    | MHD_ALLOW_SUSPEND_RESUME,
                                    port,
                                    NULL, NULL,
                                    &handle_mhd_request, h,
                                    MHD_OPTION_NOTIFY_COMPLETED,
                                    &handle_mhd_completion_callback, h,
                                    MHD_OPTION_LISTEN_BACKLOG_SIZE,
                                    (unsigned int) 1024,
                                    MHD_OPTION_END);
    if (NULL == h->mhd_bank)
    {
      TALER_FAKEBANK_stop (h);
      return NULL;
    }
#if EPOLL_SUPPORT
    h->mhd_fd = MHD_get_daemon_info (h->mhd_bank,
                                     MHD_DAEMON_INFO_EPOLL_FD)->epoll_fd;
    h->mhd_rfd = GNUNET_NETWORK_socket_box_native (h->mhd_fd);
#endif
    schedule_httpd (h);
  }
  else
  {
    h->mhd_bank = MHD_start_daemon (MHD_USE_DEBUG
                                    | MHD_USE_AUTO_INTERNAL_THREAD
                                    | MHD_ALLOW_SUSPEND_RESUME
                                    | MHD_USE_TURBO
                                    | MHD_USE_TCP_FASTOPEN
                                    | MHD_USE_DUAL_STACK,
                                    port,
                                    NULL, NULL,
                                    &handle_mhd_request, h,
                                    MHD_OPTION_NOTIFY_COMPLETED,
                                    &handle_mhd_completion_callback, h,
                                    MHD_OPTION_LISTEN_BACKLOG_SIZE,
                                    (unsigned int) 1024,
                                    MHD_OPTION_THREAD_POOL_SIZE,
                                    num_threads,
                                    MHD_OPTION_END);
    if (NULL == h->mhd_bank)
    {
      GNUNET_break (0);
      TALER_FAKEBANK_stop (h);
      return NULL;
    }
  }
  return h;
}


/* end of fakebank.c */
