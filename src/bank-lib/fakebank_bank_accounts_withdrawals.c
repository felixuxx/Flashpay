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
 * @file bank-lib/fakebank_bank_accounts_withdrawals.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank_accounts_withdrawals.h"
#include "fakebank_common_lookup.h"


MHD_RESULT
TALER_FAKEBANK_bank_account_withdrawals_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account_name,
  const char *withdrawal_id)
{
  struct WithdrawalOperation *wo;
  struct Account *acc;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  wo = TALER_FAKEBANK_lookup_withdrawal_operation_ (h,
                                                    withdrawal_id);
  if (NULL == wo)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_TRANSACTION_NOT_FOUND,
                                       withdrawal_id);
  }
  acc = TALER_FAKEBANK_lookup_account_ (h,
                                        account_name,
                                        NULL);
  if (NULL == acc)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                       account_name);
  }
  if (wo->debit_account != acc)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_TRANSACTION_NOT_FOUND,
                                       account_name);
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_bool ("aborted",
                           wo->aborted),
    GNUNET_JSON_pack_bool ("selection_done",
                           wo->selection_done),
    GNUNET_JSON_pack_bool ("transfer_done",
                           wo->confirmation_done),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_string ("selected_exchange_account",
                               wo->exchange_account->payto_uri)),
    GNUNET_JSON_pack_allow_null (
      wo->selection_done
      ? GNUNET_JSON_pack_data_auto ("selected_reserve_pub",
                                    &wo->reserve_pub)
      : GNUNET_JSON_pack_string ("selected_reserve_pub",
                                 NULL)),
    TALER_JSON_pack_amount ("amount",
                            &wo->amount));
}
