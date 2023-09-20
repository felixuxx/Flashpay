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
 * @file bank-lib/fakebank_bank_get_accounts.c
 * @brief implements the Taler Bank API "GET /accounts/" handler
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank_get_accounts.h"
#include "fakebank_common_lookup.h"

/**
 * Handle GET /accounts/${account_name} request of the Taler bank API.
 *
 * @param h the handle
 * @param connection the connection
 * @param account_name name of the account
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_bank_get_accounts_ (struct TALER_FAKEBANK_Handle *h,
                                   struct MHD_Connection *connection,
                                   const char *account_name)
{
  struct Account *acc;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
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

  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_string ("payto_uri",
                             acc->payto_uri),
    GNUNET_JSON_pack_object_steal (
      "balance",
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_string ("credit_debit_indicator",
                                 acc->is_negative
                                 ? "debit"
                                 : "credit"),
        TALER_JSON_pack_amount ("amount",
                                &acc->balance))));
}
