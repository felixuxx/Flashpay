/*
  This file is part of TALER
  (C) 2024 Taler Systems SA

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
 * @file bank-lib/fakebank_twg_get_transfers_id.c
 * @brief routines to return outgoing transfer details
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
#include "fakebank_common_parser.h"
#include "fakebank_twg_get_transfers.h"


MHD_RESULT
TALER_FAKEBANK_twg_get_transfers_id_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *id,
  void **con_cls)
{
  struct Account *acc;
  unsigned long long row_id;
  json_t *trans;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling /transfers/%s connection %p\n",
              id,
              connection);
  {
    char dummy;

    if (1 !=
        sscanf (id,
                "%llu%c",
                &row_id,
                &dummy))
    {
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        id);
    }
  }
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  acc = TALER_FAKEBANK_lookup_account_ (h,
                                        account,
                                        NULL);
  if (NULL == acc)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                       account);
  }
  {
    struct Transaction *t = h->transactions[row_id % h->ram_limit];
    char *credit_payto;

    if (t->debit_account != acc)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid ID specified, transaction %llu not with account %s!\n",
                  (unsigned long long) row_id,
                  account);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_NO;
    }
    GNUNET_asprintf (&credit_payto,
                     "payto://x-taler-bank/localhost/%s?receiver-name=%s",
                     t->credit_account->account_name,
                     t->credit_account->receiver_name);
    trans = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto (
        "wtid",
        &t->subject.debit.wtid),
      GNUNET_JSON_pack_string (
        "exchange_base_url",
        t->subject.debit.exchange_base_url),
      GNUNET_JSON_pack_timestamp (
        "timestamp",
        t->date),
      TALER_JSON_pack_amount (
        "amount",
        &t->amount),
      GNUNET_JSON_pack_string (
        "credit_account",
        credit_payto),
      GNUNET_JSON_pack_string (
        "status",
        "success"));
    GNUNET_assert (NULL != trans);
    GNUNET_free (credit_payto);
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return TALER_MHD_reply_json (
    connection,
    trans,
    MHD_HTTP_OK);
}
