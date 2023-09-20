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
 * @file bank-lib/fakebank_common_lp.h
 * @brief long-polling support for fakebank
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_COMMON_LP_H
#define FAKEBANK_COMMON_LP_H
#include "taler_fakebank_lib.h"


/**
 * Trigger the @a lp. Frees associated resources, except the entry of @a lp in
 * the timeout heap.  Must be called while the ``big lock`` is held.
 *
 * @param[in] lp long poller to trigger
 */
void
TALER_FAKEBANK_lp_trigger_ (struct LongPoller *lp);


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
  struct Transaction *t);


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
  const struct WithdrawalOperation *wo);


/**
 * Start long-polling for @a connection and @a acc
 * for transfers in @a dir. Must be called with the
 * "big lock" held.
 *
 * @param[in,out] h fakebank handle
 * @param[in,out] connection to suspend
 * @param[in,out] acc account affected
 * @param lp_timeout how long to suspend
 * @param dir direction of transfers to watch for
 * @param wo withdraw operation to watch, only
 *        if @a dir is #LP_WITHDRAW
 */
void
TALER_FAKEBANK_start_lp_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  struct Account *acc,
  struct GNUNET_TIME_Relative lp_timeout,
  enum LongPollType dir,
  const struct WithdrawalOperation *wo);


/**
 * Main routine of a thread that is run to wake up connections that have hit
 * their timeout. Runs until in_shutdown is set to true. Must be send signals
 * via lp_event on shutdown and/or whenever the heap changes to an earlier
 * timeout.
 *
 * @param cls a `struct TALER_FAKEBANK_Handle *`
 * @return NULL
 */
void *
TALER_FAKEBANK_lp_expiration_thread_ (void *cls);

#endif
