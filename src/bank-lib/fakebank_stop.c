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
 * @file bank-lib/fakebank_stop.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include <poll.h>
#ifdef __linux__
#include <sys/eventfd.h>
#endif
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_common_lp.h"


/**
 * Helper function to free memory when finished.
 *
 * @param cls NULL
 * @param key key of the account to free (ignored)
 * @param val a `struct Account` to free.
 */
static enum GNUNET_GenericReturnValue
free_account (void *cls,
              const struct GNUNET_HashCode *key,
              void *val)
{
  struct Account *account = val;

  (void) cls;
  (void) key;
  GNUNET_assert (NULL == account->lp_head);
  GNUNET_free (account->account_name);
  GNUNET_free (account->receiver_name);
  GNUNET_free (account->payto_uri);
  GNUNET_free (account->password);
  GNUNET_free (account);
  return GNUNET_OK;
}


/**
 * Helper function to free memory when finished.
 *
 * @param cls NULL
 * @param key key of the operation to free (ignored)
 * @param val a `struct WithdrawalOperation *` to free.
 */
static enum GNUNET_GenericReturnValue
free_withdraw_op (void *cls,
                  const struct GNUNET_ShortHashCode *key,
                  void *val)
{
  struct WithdrawalOperation *wo = val;

  (void) cls;
  (void) key;
  GNUNET_free (wo->amount);
  GNUNET_free (wo);
  return GNUNET_OK;
}


void
TALER_FAKEBANK_stop (struct TALER_FAKEBANK_Handle *h)
{
  if (NULL != h->lp_task)
  {
    GNUNET_SCHEDULER_cancel (h->lp_task);
    h->lp_task = NULL;
  }
#if EPOLL_SUPPORT
  if (NULL != h->mhd_rfd)
  {
    GNUNET_NETWORK_socket_free_memory_only_ (h->mhd_rfd);
    h->mhd_rfd = NULL;
  }
#endif
#ifdef __linux__
  if (-1 != h->lp_event)
#else
  if (-1 != h->lp_event_in && -1 != h->lp_event_out)
#endif
  {
    uint64_t val = 1;
    void *ret;
    struct LongPoller *lp;

    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->big_lock));
    h->in_shutdown = true;
    while (NULL != (lp = GNUNET_CONTAINER_heap_remove_root (h->lp_heap)))
      TALER_FAKEBANK_lp_trigger_ (lp);
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
#ifdef __linux__
    GNUNET_break (sizeof (val) ==
                  write (h->lp_event,
                         &val,
                         sizeof (val)));
#else
    GNUNET_break (sizeof (val) ==
                  write (h->lp_event_in,
                         &val,
                         sizeof (val)));
#endif
    GNUNET_break (0 ==
                  pthread_join (h->lp_thread,
                                &ret));
    GNUNET_break (NULL == ret);
#ifdef __linux__
    GNUNET_break (0 == close (h->lp_event));
    h->lp_event = -1;
#else
    GNUNET_break (0 == close (h->lp_event_in));
    GNUNET_break (0 == close (h->lp_event_out));
    h->lp_event_in = -1;
    h->lp_event_out = -1;
#endif
  }
  else
  {
    struct LongPoller *lp;

    while (NULL != (lp = GNUNET_CONTAINER_heap_remove_root (h->lp_heap)))
      TALER_FAKEBANK_lp_trigger_ (lp);
  }
  if (NULL != h->mhd_bank)
  {
    MHD_stop_daemon (h->mhd_bank);
    h->mhd_bank = NULL;
  }
  if (NULL != h->mhd_task)
  {
    GNUNET_SCHEDULER_cancel (h->mhd_task);
    h->mhd_task = NULL;
  }
  if (NULL != h->accounts)
  {
    GNUNET_CONTAINER_multihashmap_iterate (h->accounts,
                                           &free_account,
                                           NULL);
    GNUNET_CONTAINER_multihashmap_destroy (h->accounts);
  }
  if (NULL != h->wops)
  {
    GNUNET_CONTAINER_multishortmap_iterate (h->wops,
                                            &free_withdraw_op,
                                            NULL);
    GNUNET_CONTAINER_multishortmap_destroy (h->wops);
  }
  GNUNET_CONTAINER_multihashmap_destroy (h->uuid_map);
  GNUNET_CONTAINER_multipeermap_destroy (h->rpubs);
  GNUNET_CONTAINER_heap_destroy (h->lp_heap);
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
  GNUNET_free (h->exchange_url);
  GNUNET_free (h->hostname);
  GNUNET_free (h);
}
