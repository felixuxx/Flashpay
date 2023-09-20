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
 * @file bank-lib/fakebank_tbi_get_withdrawal_operation.c
 * @brief Implementation of the GET /withdrawal-operation/ request of the Taler Bank Integration API
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
#include "fakebank_tbi_get_withdrawal_operation.h"

/**
 * Function called to clean up a withdraw context.
 *
 * @param cls a `struct WithdrawContext *`
 */
static void
withdraw_cleanup (void *cls)
{
  struct WithdrawContext *wc = cls;

  GNUNET_free (wc);
}


MHD_RESULT
TALER_FAKEBANK_tbi_get_withdrawal_operation_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *wopid,
  struct GNUNET_TIME_Relative lp,
  void **con_cls)
{
  struct ConnectionContext *cc = *con_cls;
  struct WithdrawContext *wc;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  if (NULL == cc)
  {
    cc = GNUNET_new (struct ConnectionContext);
    cc->ctx_cleaner = &withdraw_cleanup;
    *con_cls = cc;
    wc = GNUNET_new (struct WithdrawContext);
    cc->ctx = wc;
    wc->wo = TALER_FAKEBANK_lookup_withdrawal_operation_ (h,
                                                          wopid);
    if (NULL == wc->wo)
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_BANK_TRANSACTION_NOT_FOUND,
                                         wopid);
    }
    wc->timeout = GNUNET_TIME_relative_to_absolute (lp);
  }
  else
  {
    wc = cc->ctx;
  }
  if (GNUNET_TIME_absolute_is_past (wc->timeout) ||
      h->in_shutdown ||
      wc->wo->confirmation_done ||
      wc->wo->aborted)
  {
    json_t *wt;

    wt = json_array ();
    GNUNET_assert (NULL != wt);
    GNUNET_assert (0 ==
                   json_array_append_new (wt,
                                          json_string ("x-taler-bank")));
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_bool ("aborted",
                             wc->wo->aborted),
      GNUNET_JSON_pack_bool ("selection_done",
                             wc->wo->selection_done),
      GNUNET_JSON_pack_bool ("transfer_done",
                             wc->wo->confirmation_done),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("suggested_exchange",
                                 h->exchange_url)),
      TALER_JSON_pack_amount ("amount",
                              &wc->wo->amount),
      GNUNET_JSON_pack_array_steal ("wire_types",
                                    wt));
  }

  TALER_FAKEBANK_start_lp_ (h,
                            connection,
                            wc->wo->debit_account,
                            GNUNET_TIME_absolute_get_remaining (wc->timeout),
                            LP_WITHDRAW,
                            wc->wo);
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return MHD_YES;
}
