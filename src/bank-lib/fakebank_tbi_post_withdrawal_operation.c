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
 * @file bank-lib/fakebank_tbi_post_withdrawal_operation.c
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
#include "fakebank_common_lookup.h"
#include "fakebank_tbi_post_withdrawal_operation.h"


/**
 * Execute POST /withdrawal-operation/ request.
 *
 * @param h our handle
 * @param connection the connection
 * @param wopid the withdrawal operation identifier
 * @param reserve_pub public key of the reserve
 * @param exchange_payto_uri payto://-URI of the exchange
 * @param amount chosen by the client, or NULL to use the
 *        pre-determined amount
 * @return MHD result code
 */
static MHD_RESULT
do_post_withdrawal (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *wopid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_FullPayto exchange_payto_uri,
  const struct TALER_Amount *amount)
{
  struct WithdrawalOperation *wo;
  char *credit_name;
  struct Account *credit_account;
  const char *status_string;

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  wo = TALER_FAKEBANK_lookup_withdrawal_operation_ (h,
                                                    wopid);
  if (NULL == wo)
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_BANK_TRANSACTION_NOT_FOUND,
                                       wopid);
  }
  if ( (wo->selection_done) &&
       (0 != GNUNET_memcmp (&wo->reserve_pub,
                            reserve_pub)) )
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_CONFLICT,
                                       TALER_EC_BANK_WITHDRAWAL_OPERATION_RESERVE_SELECTION_CONFLICT,
                                       "reserve public key changed");
  }
  {
    /* check if reserve_pub is already in use */
    const struct GNUNET_PeerIdentity *pid;

    pid = (const struct GNUNET_PeerIdentity *) &wo->reserve_pub;
    if (GNUNET_CONTAINER_multipeermap_contains (h->rpubs,
                                                pid))
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_CONFLICT,
                                         TALER_EC_BANK_DUPLICATE_RESERVE_PUB_SUBJECT,
                                         NULL);
    }
  }
  credit_name = TALER_xtalerbank_account_from_payto (exchange_payto_uri);
  if (NULL == credit_name)
  {
    GNUNET_break_op (0);
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PAYTO_URI_MALFORMED,
                                       NULL);
  }
  credit_account = TALER_FAKEBANK_lookup_account_ (h,
                                                   credit_name,
                                                   NULL);
  if (NULL == credit_account)
  {
    MHD_RESULT res;

    GNUNET_break_op (0);
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    res = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_NOT_FOUND,
                                      TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                      credit_name);
    GNUNET_free (credit_name);
    return res;
  }
  GNUNET_free (credit_name);
  if ( (NULL != wo->exchange_account) &&
       (credit_account != wo->exchange_account) )
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_CONFLICT,
                                       TALER_EC_BANK_WITHDRAWAL_OPERATION_RESERVE_SELECTION_CONFLICT,
                                       "exchange account changed");
  }
  if ( (NULL != wo->amount) && (NULL != amount) && (0 != TALER_amount_cmp (wo->
                                                                           amount,
                                                                           amount)) )
  {
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_CONFLICT,
                                       TALER_EC_BANK_WITHDRAWAL_OPERATION_RESERVE_SELECTION_CONFLICT,
                                       "amount changed");
  }
  if (NULL == wo->amount)
  {
    if (NULL == amount)
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_BANK_POST_WITHDRAWAL_OPERATION_REQUIRED,
                                         "amount missing");
    }
    else
    {
      wo->amount = GNUNET_new (struct TALER_Amount);
      *wo->amount = *amount;
    }
  }
  GNUNET_assert (NULL != wo->amount);
  wo->exchange_account = credit_account;
  wo->reserve_pub = *reserve_pub;
  wo->selection_done = true;
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  if (wo->aborted)
    status_string = "aborted";
  else if (wo->confirmation_done)
    status_string = "confirmed";
  else
    status_string = "selected";
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    // FIXME: Deprecated field, should be deleted in the future.
    GNUNET_JSON_pack_bool ("transfer_done",
                           wo->confirmation_done),
    GNUNET_JSON_pack_string ("status",
                             status_string));
}


MHD_RESULT
TALER_FAKEBANK_tbi_post_withdrawal (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *wopid,
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
    struct TALER_ReservePublicKeyP reserve_pub;
    struct TALER_FullPayto exchange_payto_url;
    enum GNUNET_GenericReturnValue ret;
    struct TALER_Amount amount;
    bool amount_missing;
    struct TALER_Amount *amount_ptr;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                   &reserve_pub),
      TALER_JSON_spec_full_payto_uri ("selected_exchange",
                                      &exchange_payto_url),
      GNUNET_JSON_spec_mark_optional (
        TALER_JSON_spec_amount ("amount",
                                h->currency,
                                &amount),
        &amount_missing),
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

    amount_ptr = amount_missing ? NULL : &amount;

    res = do_post_withdrawal (h,
                              connection,
                              wopid,
                              &reserve_pub,
                              exchange_payto_url,
                              amount_ptr);
  }
  json_decref (json);
  return res;
}
