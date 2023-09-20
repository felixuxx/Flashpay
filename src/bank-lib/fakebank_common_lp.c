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
 * @file bank-lib/fakebank_common_lp.c
 * @brief long-polling support for fakebank
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


void
TALER_FAKEBANK_lp_trigger_ (struct LongPoller *lp)
{
  struct TALER_FAKEBANK_Handle *h = lp->h;
  struct Account *acc = lp->account;

  GNUNET_CONTAINER_DLL_remove (acc->lp_head,
                               acc->lp_tail,
                               lp);
  MHD_resume_connection (lp->conn);
  GNUNET_free (lp);
  h->mhd_again = true;
#ifdef __linux__
  if (-1 == h->lp_event)
#else
  if ( (-1 == h->lp_event_in) &&
       (-1 == h->lp_event_out) )
#endif
  {
    if (NULL != h->mhd_task)
      GNUNET_SCHEDULER_cancel (h->mhd_task);
    h->mhd_task =
      GNUNET_SCHEDULER_add_now (&TALER_FAKEBANK_run_mhd_,
                                h);
  }
}


void *
TALER_FAKEBANK_lp_expiration_thread_ (void *cls)
{
  struct TALER_FAKEBANK_Handle *h = cls;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  while (! h->in_shutdown)
  {
    struct LongPoller *lp;
    int timeout_ms;

    lp = GNUNET_CONTAINER_heap_peek (h->lp_heap);
    while ( (NULL != lp) &&
            GNUNET_TIME_absolute_is_past (lp->timeout))
    {
      GNUNET_assert (lp ==
                     GNUNET_CONTAINER_heap_remove_root (h->lp_heap));
      TALER_FAKEBANK_lp_trigger_ (lp);
      lp = GNUNET_CONTAINER_heap_peek (h->lp_heap);
    }
    if (NULL != lp)
    {
      struct GNUNET_TIME_Relative rem;
      unsigned long long left_ms;

      rem = GNUNET_TIME_absolute_get_remaining (lp->timeout);
      left_ms = rem.rel_value_us / GNUNET_TIME_UNIT_MILLISECONDS.rel_value_us;
      if (left_ms > INT_MAX)
        timeout_ms = INT_MAX;
      else
        timeout_ms = (int) left_ms;
    }
    else
    {
      timeout_ms = -1; /* infinity */
    }
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    {
      struct pollfd p = {
#ifdef __linux__
        .fd = h->lp_event,
#else
        .fd = h->lp_event_out,
#endif
        .events = POLLIN
      };
      int ret;

      ret = poll (&p,
                  1,
                  timeout_ms);
      if (-1 == ret)
      {
        if (EINTR != errno)
          GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                               "poll");
      }
      else if (1 == ret)
      {
        /* clear event */
        uint64_t ev;
        ssize_t iret;

#ifdef __linux__
        iret = read (h->lp_event,
                     &ev,
                     sizeof (ev));
#else
        iret = read (h->lp_event_out,
                     &ev,
                     sizeof (ev));
#endif
        if (-1 == iret)
        {
          GNUNET_log_strerror (GNUNET_ERROR_TYPE_WARNING,
                               "read");
        }
        else
        {
          GNUNET_break (sizeof (uint64_t) == iret);
        }
      }
    }
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->big_lock));
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return NULL;
}


/**
 * Trigger long pollers that might have been waiting
 * for @a t.
 *
 * @param h fakebank handle
 * @param t transaction to notify on
 */
void
TALER_FAKEBANK_notify_transaction_ (
  struct TALER_FAKEBANK_Handle *h,
  struct Transaction *t)
{
  struct Account *debit_acc = t->debit_account;
  struct Account *credit_acc = t->credit_account;
  struct LongPoller *nxt;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  for (struct LongPoller *lp = debit_acc->lp_head;
       NULL != lp;
       lp = nxt)
  {
    nxt = lp->next;
    if (LP_DEBIT == lp->type)
    {
      GNUNET_assert (lp ==
                     GNUNET_CONTAINER_heap_remove_node (lp->hn));
      TALER_FAKEBANK_lp_trigger_ (lp);
    }
  }
  for (struct LongPoller *lp = credit_acc->lp_head;
       NULL != lp;
       lp = nxt)
  {
    nxt = lp->next;
    if (LP_CREDIT == lp->type)
    {
      GNUNET_assert (lp ==
                     GNUNET_CONTAINER_heap_remove_node (lp->hn));
      TALER_FAKEBANK_lp_trigger_ (lp);
    }
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
}


/**
 * Notify long pollers that a @a wo was updated.
 * Must be called with the "big_lock" still held.
 *
 * @param h fakebank handle
 * @param wo withdraw operation that finished
 */
void
TALER_FAKEBANK_notify_withdrawal_ (
  struct TALER_FAKEBANK_Handle *h,
  const struct WithdrawalOperation *wo)
{
  struct Account *debit_acc = wo->debit_account;
  struct LongPoller *nxt;

  for (struct LongPoller *lp = debit_acc->lp_head;
       NULL != lp;
       lp = nxt)
  {
    nxt = lp->next;
    if ( (LP_WITHDRAW == lp->type) &&
         (wo == lp->wo) )
    {
      GNUNET_assert (lp ==
                     GNUNET_CONTAINER_heap_remove_node (lp->hn));
      TALER_FAKEBANK_lp_trigger_ (lp);
    }
  }
}


/**
 * Task run when a long poller is about to time out.
 * Only used in single-threaded mode.
 *
 * @param cls a `struct TALER_FAKEBANK_Handle *`
 */
static void
lp_timeout (void *cls)
{
  struct TALER_FAKEBANK_Handle *h = cls;
  struct LongPoller *lp;

  h->lp_task = NULL;
  while (NULL != (lp = GNUNET_CONTAINER_heap_peek (h->lp_heap)))
  {
    if (GNUNET_TIME_absolute_is_future (lp->timeout))
      break;
    GNUNET_assert (lp ==
                   GNUNET_CONTAINER_heap_remove_root (h->lp_heap));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Timeout reached for long poller %p\n",
                lp->conn);
    TALER_FAKEBANK_lp_trigger_ (lp);
  }
  if (NULL == lp)
    return;
  h->lp_task = GNUNET_SCHEDULER_add_at (lp->timeout,
                                        &lp_timeout,
                                        h);
}


/**
 * Reschedule the timeout task of @a h for time @a t.
 *
 * @param h fakebank handle
 * @param t when will the next connection timeout expire
 */
static void
reschedule_lp_timeout (struct TALER_FAKEBANK_Handle *h,
                       struct GNUNET_TIME_Absolute t)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Scheduling timeout task for %s\n",
              GNUNET_STRINGS_absolute_time_to_string (t));
#ifdef __linux__
  if (-1 != h->lp_event)
#else
  if (-1 != h->lp_event_in && -1 != h->lp_event_out)
#endif
  {
    uint64_t num = 1;

    GNUNET_break (sizeof (num) ==
#ifdef __linux__
                  write (h->lp_event,
                         &num,
                         sizeof (num)));
#else
                  write (h->lp_event_in,
                         &num,
                         sizeof (num)));
#endif
  }
  else
  {
    if (NULL != h->lp_task)
      GNUNET_SCHEDULER_cancel (h->lp_task);
    h->lp_task = GNUNET_SCHEDULER_add_at (t,
                                          &lp_timeout,
                                          h);
  }
}


void
TALER_FAKEBANK_start_lp_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  struct Account *acc,
  struct GNUNET_TIME_Relative lp_timeout,
  enum LongPollType dir,
  const struct WithdrawalOperation *wo)
{
  struct LongPoller *lp;
  bool toc;

  lp = GNUNET_new (struct LongPoller);
  lp->account = acc;
  lp->h = h;
  lp->wo = wo;
  lp->conn = connection;
  lp->timeout = GNUNET_TIME_relative_to_absolute (lp_timeout);
  lp->type = dir;
  lp->hn = GNUNET_CONTAINER_heap_insert (h->lp_heap,
                                         lp,
                                         lp->timeout.abs_value_us);
  toc = (lp ==
         GNUNET_CONTAINER_heap_peek (h->lp_heap));
  GNUNET_CONTAINER_DLL_insert (acc->lp_head,
                               acc->lp_tail,
                               lp);
  MHD_suspend_connection (connection);
  if (toc)
    reschedule_lp_timeout (h,
                           lp->timeout);

}
