/*
  This file is part of TALER
  (C) 2016-2024 Taler Systems SA

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
 * @file bank-lib/fakebank_common_make_admin_transfer.c
 * @brief routine to create transfers to the exchange
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_common_make_admin_transfer.h"
#include "fakebank_common_lookup.h"
#include "fakebank_common_lp.h"
#include "fakebank_common_transact.h"


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_make_admin_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *row_id,
  struct GNUNET_TIME_Timestamp *timestamp)
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
  debit_acc = TALER_FAKEBANK_lookup_account_ (h,
                                              debit_account,
                                              debit_account);
  credit_acc = TALER_FAKEBANK_lookup_account_ (h,
                                               credit_account,
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
    GNUNET_break_op (0);
    return GNUNET_NO;
  }

  t = GNUNET_new (struct Transaction);
  t->unchecked = true;
  t->debit_account = debit_acc;
  t->credit_account = credit_acc;
  t->amount = *amount;
  t->date = GNUNET_TIME_timestamp_get ();
  if (NULL != timestamp)
    *timestamp = t->date;
  t->type = T_CREDIT;
  t->subject.credit.reserve_pub = *reserve_pub;
  TALER_FAKEBANK_transact_ (h,
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
  TALER_FAKEBANK_notify_transaction_ (h,
                                      t);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_make_kycauth_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const union TALER_AccountPublicKeyP *account_pub,
  uint64_t *row_id,
  struct GNUNET_TIME_Timestamp *timestamp)
{
  struct Transaction *t;
  const struct GNUNET_PeerIdentity *pid;
  struct Account *debit_acc;
  struct Account *credit_acc;

  GNUNET_static_assert (sizeof (*pid) ==
                        sizeof (*account_pub));
  pid = (const struct GNUNET_PeerIdentity *) account_pub;
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
  debit_acc = TALER_FAKEBANK_lookup_account_ (h,
                                              debit_account,
                                              debit_account);
  credit_acc = TALER_FAKEBANK_lookup_account_ (h,
                                               credit_account,
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
    GNUNET_break_op (0);
    return GNUNET_NO;
  }

  t = GNUNET_new (struct Transaction);
  t->unchecked = true;
  t->debit_account = debit_acc;
  t->credit_account = credit_acc;
  t->amount = *amount;
  t->date = GNUNET_TIME_timestamp_get ();
  if (NULL != timestamp)
    *timestamp = t->date;
  t->type = T_AUTH;
  t->subject.auth.account_pub = *account_pub;
  TALER_FAKEBANK_transact_ (h,
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
              TALER_B2S (account_pub),
              (unsigned long long) t->row_id);
  TALER_FAKEBANK_notify_transaction_ (h,
                                      t);
  return GNUNET_OK;
}
