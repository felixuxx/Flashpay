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
 * @file bank-lib/fakebank_bank_post_withdrawals_id_op.c
 * @brief implement bank API POST /accounts/$ACCOUNT/withdrawals/$WID/$OP endpoint(s)
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank_post_withdrawals_id_op.h"
#include "fakebank_common_lookup.h"
#include "fakebank_common_lp.h"
#include "fakebank_common_make_admin_transfer.h"


/**
 * Handle POST /accounts/$ACC/withdrawals/{withdrawal_id}/confirm request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account name of the account
 * @param withdrawal_id the withdrawal operation identifier
 * @return MHD result code
 */
static MHD_RESULT
bank_withdrawals_confirm (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *withdrawal_id)
{
  const struct Account *acc;
  struct WithdrawalOperation *wo;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  acc = TALER_FAKEBANK_lookup_account_ (h,
                                        account,
                                        NULL);
  if (NULL == acc)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Account %s is unknown\n",
                account);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                       account);
  }
  wo = TALER_FAKEBANK_lookup_withdrawal_operation_ (h,
                                                    withdrawal_id);
  if ( (NULL == wo) ||
       (acc != wo->debit_account) )
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_TRANSACTION_NOT_FOUND,
                                       withdrawal_id);
  }
  if (NULL == wo->exchange_account)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_BANK_POST_WITHDRAWAL_OPERATION_REQUIRED,
                                       NULL);
  }
  if (NULL == wo->amount)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_BANK_POST_WITHDRAWAL_OPERATION_REQUIRED,
                                       NULL);
  }
  if (wo->aborted)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_CONFLICT,
                                       TALER_EC_BANK_CONFIRM_ABORT_CONFLICT,
                                       withdrawal_id);
  }
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  if (GNUNET_OK !=
      TALER_FAKEBANK_make_admin_transfer_ (
        h,
        wo->debit_account->account_name,
        wo->exchange_account->account_name,
        wo->amount,
        &wo->reserve_pub,
        &wo->row_id,
        &wo->timestamp))
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_CONFLICT,
                                       TALER_EC_BANK_DUPLICATE_RESERVE_PUB_SUBJECT,
                                       NULL);
  }
  /* Re-acquiring the lock and continuing to operate on 'wo'
     is currently (!) acceptable because we NEVER free 'wo'
     until shutdown. We may want to revise this if keeping
     all withdraw operations in RAM becomes an issue... */
  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  wo->confirmation_done = true;
  TALER_FAKEBANK_notify_withdrawal_ (h,
                                     wo);
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return TALER_MHD_reply_static (connection,
                                 MHD_HTTP_NO_CONTENT,
                                 NULL,
                                 NULL,
                                 0);
}


/**
 * Handle POST /accounts/$ACC/withdrawals/{withdrawal_id}/abort request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account name of the account
 * @param withdrawal_id the withdrawal operation identifier
 * @return MHD result code
 */
static MHD_RESULT
bank_withdrawals_abort (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *withdrawal_id)
{
  struct WithdrawalOperation *wo;
  const struct Account *acc;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  acc = TALER_FAKEBANK_lookup_account_ (h,
                                        account,
                                        NULL);
  if (NULL == acc)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Account %s is unknown\n",
                account);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                       account);
  }
  wo = TALER_FAKEBANK_lookup_withdrawal_operation_ (h,
                                                    withdrawal_id);
  if ( (NULL == wo) ||
       (acc != wo->debit_account) )
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_TRANSACTION_NOT_FOUND,
                                       withdrawal_id);
  }
  if (wo->confirmation_done)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_CONFLICT,
                                       TALER_EC_BANK_ABORT_CONFIRM_CONFLICT,
                                       withdrawal_id);
  }
  wo->aborted = true;
  TALER_FAKEBANK_notify_withdrawal_ (h,
                                     wo);
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  return TALER_MHD_reply_static (connection,
                                 MHD_HTTP_NO_CONTENT,
                                 NULL,
                                 NULL,
                                 0);
}


MHD_RESULT
TALER_FAKEBANK_bank_withdrawals_id_op_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *withdrawal_id,
  const char *op,
  const char *upload_data,
  size_t *upload_data_size,
  void **con_cls)
{
  if (0 == strcmp (op,
                   "/confirm"))
  {
    return bank_withdrawals_confirm (h,
                                     connection,
                                     account,
                                     withdrawal_id);
  }
  if (0 == strcmp (op,
                   "/abort"))
  {
    return bank_withdrawals_abort (h,
                                   connection,
                                   account,
                                   withdrawal_id);
  }
  GNUNET_break_op (0);
  return TALER_MHD_reply_with_error (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                     op);
}
