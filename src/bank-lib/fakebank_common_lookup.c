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
 * @file bank-lib/fakebank_common_lookup.c
 * @brief common helper functions related to lookups
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

struct WithdrawalOperation *
TALER_FAKEBANK_lookup_withdrawal_operation_ (struct TALER_FAKEBANK_Handle *h,
                                             const char *wopid)
{
  struct GNUNET_ShortHashCode sh;

  if (NULL == h->wops)
    return NULL;
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (wopid,
                                     strlen (wopid),
                                     &sh,
                                     sizeof (sh)))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  return GNUNET_CONTAINER_multishortmap_get (h->wops,
                                             &sh);
}


struct Account *
TALER_FAKEBANK_lookup_account_ (struct TALER_FAKEBANK_Handle *h,
                                const char *name,
                                const char *receiver_name)
{
  struct GNUNET_HashCode hc;
  size_t slen;
  struct Account *account;

  memset (&hc,
          0,
          sizeof (hc));
  slen = strlen (name);
  GNUNET_CRYPTO_hash (name,
                      slen,
                      &hc);
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->accounts_lock));
  account = GNUNET_CONTAINER_multihashmap_get (h->accounts,
                                               &hc);
  if (NULL == account)
  {
    if (NULL == receiver_name)
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->accounts_lock));
      return NULL;
    }
    account = GNUNET_new (struct Account);
    account->account_name = GNUNET_strdup (name);
    account->receiver_name = GNUNET_strdup (receiver_name);
    GNUNET_asprintf (&account->payto_uri,
                     "payto://x-taler-bank/%s/%s?receiver-name=%s",
                     h->hostname,
                     account->account_name,
                     account->receiver_name);
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (h->currency,
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
