/*
  This file is part of TALER
  (C) 2016-2023 Taler Systems SA

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
 * @file bank-lib/fakebank_common_transact.c
 * @brief actual transaction logic for FAKEBANK
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_common_lookup.h"
#include "fakebank_common_lp.h"
#include "fakebank_common_transact.h"


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
void
TALER_FAKEBANK_transact_ (struct TALER_FAKEBANK_Handle *h,
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


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_make_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_WireTransferIdentifierRawP *subject,
  const char *exchange_base_url,
  const struct GNUNET_HashCode *request_uid,
  uint64_t *ret_row_id,
  struct GNUNET_TIME_Timestamp *timestamp)
{
  struct Transaction *t;
  struct Account *debit_acc;
  struct Account *credit_acc;
  size_t url_len;

  GNUNET_assert (0 == strcasecmp (amount->currency,
                                  h->currency));
  GNUNET_assert (NULL != debit_account);
  GNUNET_assert (NULL != credit_account);
  GNUNET_break (0 != strncasecmp ("payto://",
                                  debit_account,
                                  strlen ("payto://")));
  GNUNET_break (0 != strncasecmp ("payto://",
                                  credit_account,
                                  strlen ("payto://")));
  url_len = strlen (exchange_base_url);
  GNUNET_assert (url_len < MAX_URL_LEN);
  debit_acc = TALER_FAKEBANK_lookup_account_ (h,
                                              debit_account,
                                              debit_account);
  credit_acc = TALER_FAKEBANK_lookup_account_ (h,
                                               credit_account,
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
      *timestamp = t->date;
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
  t->date = GNUNET_TIME_timestamp_get ();
  if (NULL != timestamp)
    *timestamp = t->date;
  t->type = T_DEBIT;
  GNUNET_memcpy (t->subject.debit.exchange_base_url,
                 exchange_base_url,
                 url_len);
  t->subject.debit.wtid = *subject;
  if (NULL == request_uid)
    GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_NONCE,
                                      &t->request_uid);
  else
    t->request_uid = *request_uid;
  TALER_FAKEBANK_transact_ (h,
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Making transfer %llu from %s to %s over %s and subject %s; for exchange: %s\n",
              (unsigned long long) t->row_id,
              debit_account,
              credit_account,
              TALER_amount2s (amount),
              TALER_B2S (subject),
              exchange_base_url);
  *ret_row_id = t->row_id;
  TALER_FAKEBANK_notify_transaction_ (h,
                                      t);
  return GNUNET_OK;
}
