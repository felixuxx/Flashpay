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
 * @file bank-lib/fakebank_bank_post_accounts_withdrawals.c
 * @brief implementation of the bank API's POST /accounts/AID/withdrawals endpoint
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include <pthread.h>
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_bank_post_accounts_withdrawals.h"
#include "fakebank_common_lookup.h"


/**
 * Execute POST /accounts/$account_name/withdrawals request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account_name name of the account
 * @param amount amont to withdraw
 * @return MHD result code
 */
static MHD_RESULT
do_post_account_withdrawals (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account_name,
  const struct TALER_Amount *amount)
{
  struct Account *acc;
  struct WithdrawalOperation *wo;

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
  wo = GNUNET_new (struct WithdrawalOperation);
  wo->debit_account = acc;
  wo->amount = *amount;
  if (NULL == h->wops)
  {
    h->wops = GNUNET_CONTAINER_multishortmap_create (32,
                                                     GNUNET_YES);
  }
  while (1)
  {
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                                &wo->wopid,
                                sizeof (wo->wopid));
    if (GNUNET_OK ==
        GNUNET_CONTAINER_multishortmap_put (h->wops,
                                            &wo->wopid,
                                            wo,
                                            GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY))
      break;
  }
  {
    char *wopids;
    char *uri;
    MHD_RESULT res;

    wopids = GNUNET_STRINGS_data_to_string_alloc (&wo->wopid,
                                                  sizeof (wo->wopid));
    GNUNET_asprintf (&uri,
                     "taler+http://withdraw/%s:%u/taler-integration/%s",
                     h->hostname,
                     (unsigned int) h->port,
                     wopids);
    GNUNET_free (wopids);
    res = TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string ("taler_withdraw_uri",
                               uri),
      GNUNET_JSON_pack_data_auto ("withdrawal_id",
                                  &wo->wopid));
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    GNUNET_free (uri);
    return res;
  }
}


/**
 * Handle POST /accounts/$account_name/withdrawals request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account_name name of the account
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_bank_post_account_withdrawals_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account_name,
  const void *upload_data,
  size_t *upload_data_size,
  void **con_cls)
{
  struct ConnectionContext *cc = *con_cls;
  enum GNUNET_JSON_PostResult pr;
  json_t *json;
  MHD_RESULT res;

  if (NULL == cc)
  {
    cc = GNUNET_new (struct ConnectionContext);
    cc->ctx_cleaner = &GNUNET_JSON_post_parser_cleanup;
    *con_cls = cc;
  }
  pr = GNUNET_JSON_post_parser (REQUEST_BUFFER_MAX,
                                connection,
                                &cc->ctx,
                                upload_data,
                                upload_data_size,
                                &json);
  switch (pr)
  {
  case GNUNET_JSON_PR_OUT_OF_MEMORY:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_CONTINUE:
    return MHD_YES;
  case GNUNET_JSON_PR_REQUEST_TOO_LARGE:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_JSON_INVALID:
    GNUNET_break (0);
    return MHD_NO;
  case GNUNET_JSON_PR_SUCCESS:
    break;
  }

  {
    struct TALER_Amount amount;
    enum GNUNET_GenericReturnValue ret;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_amount ("amount",
                              h->currency,
                              &amount),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        (ret = TALER_MHD_parse_json_data (connection,
                                          json,
                                          spec)))
    {
      GNUNET_break_op (0);
      json_decref (json);
      return (GNUNET_NO == ret) ? MHD_YES : MHD_NO;
    }
    res = do_post_account_withdrawals (h,
                                       connection,
                                       account_name,
                                       &amount);
  }
  json_decref (json);
  return res;
}
