/*
  This file is part of TALER
  Copyright (C) 2018-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_common.c
 * @brief common functions for commands
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_testing_lib.h"


int
TALER_TESTING_history_entry_cmp (
  const struct TALER_EXCHANGE_ReserveHistoryEntry *h1,
  const struct TALER_EXCHANGE_ReserveHistoryEntry *h2)
{
  if (h1->type != h2->type)
    return 1;
  switch (h1->type)
  {
  case TALER_EXCHANGE_RTT_CREDIT:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 == strcasecmp (h1->details.in_details.sender_url,
                           h2->details.in_details.sender_url)) &&
         (h1->details.in_details.wire_reference ==
          h2->details.in_details.wire_reference) &&
         (GNUNET_TIME_timestamp_cmp (h1->details.in_details.timestamp,
                                     ==,
                                     h2->details.in_details.timestamp)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_WITHDRAWAL:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.withdraw.fee,
                            &h2->details.withdraw.fee)) )
      /* testing_api_cmd_withdraw doesn't set the out_authorization_sig,
         so we cannot test for it here. but if the amount matches,
         that should be good enough. */
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_AGEWITHDRAWAL:
    /* testing_api_cmd_age_withdraw doesn't set the out_authorization_sig,
       so we cannot test for it here. but if the amount matches,
       that should be good enough. */
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.age_withdraw.fee,
                            &h2->details.age_withdraw.fee)) &&
         (h1->details.age_withdraw.max_age ==
          h2->details.age_withdraw.max_age))
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_RECOUP:
    /* exchange_sig, exchange_pub and timestamp are NOT available
       from the original recoup response, hence here NOT check(able/ed) */
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.recoup_details.coin_pub,
                         &h2->details.recoup_details.coin_pub)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_CLOSING:
    /* testing_api_cmd_exec_closer doesn't set the
       receiver_account_details, exchange_sig, exchange_pub or wtid or timestamp
       so we cannot test for it here. but if the amount matches,
       that should be good enough. */
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.close_details.fee,
                            &h2->details.close_details.fee)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_MERGE:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.merge_details.purse_fee,
                            &h2->details.merge_details.purse_fee)) &&
         (GNUNET_TIME_timestamp_cmp (h1->details.merge_details.merge_timestamp,
                                     ==,
                                     h2->details.merge_details.merge_timestamp))
         &&
         (GNUNET_TIME_timestamp_cmp (h1->details.merge_details.purse_expiration,
                                     ==,
                                     h2->details.merge_details.purse_expiration))
         &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.merge_pub,
                         &h2->details.merge_details.merge_pub)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.h_contract_terms,
                         &h2->details.merge_details.h_contract_terms)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.purse_pub,
                         &h2->details.merge_details.purse_pub)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.reserve_sig,
                         &h2->details.merge_details.reserve_sig)) &&
         (h1->details.merge_details.min_age ==
          h2->details.merge_details.min_age) &&
         (h1->details.merge_details.flags ==
          h2->details.merge_details.flags) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_OPEN:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (GNUNET_TIME_timestamp_cmp (
            h1->details.open_request.request_timestamp,
            ==,
            h2->details.open_request.request_timestamp)) &&
         (GNUNET_TIME_timestamp_cmp (
            h1->details.open_request.reserve_expiration,
            ==,
            h2->details.open_request.reserve_expiration)) &&
         (h1->details.open_request.purse_limit ==
          h2->details.open_request.purse_limit) &&
         (0 ==
          TALER_amount_cmp (&h1->details.open_request.reserve_payment,
                            &h2->details.open_request.reserve_payment)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.open_request.reserve_sig,
                         &h2->details.open_request.reserve_sig)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_CLOSE:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (GNUNET_TIME_timestamp_cmp (
            h1->details.close_request.request_timestamp,
            ==,
            h2->details.close_request.request_timestamp)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.close_request.target_account_h_payto,
                         &h2->details.close_request.target_account_h_payto)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.close_request.reserve_sig,
                         &h2->details.close_request.reserve_sig)) )
      return 0;
    return 1;
  }
  GNUNET_assert (0);
  return 1;
}


enum GNUNET_GenericReturnValue
TALER_TESTING_parse_coin_reference (
  const char *coin_reference,
  char **cref,
  unsigned int *idx)
{
  const char *index;
  char dummy;

  /* We allow command references of the form "$LABEL#$INDEX" or
     just "$LABEL", which implies the index is 0. Figure out
     which one it is. */
  index = strchr (coin_reference, '#');
  if (NULL == index)
  {
    *idx = 0;
    *cref = GNUNET_strdup (coin_reference);
    return GNUNET_OK;
  }
  *cref = GNUNET_strndup (coin_reference,
                          index - coin_reference);
  if (1 != sscanf (index + 1,
                   "%u%c",
                   idx,
                   &dummy))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Numeric index (not `%s') required after `#' in command reference of command in %s:%u\n",
                index,
                __FILE__,
                __LINE__);
    GNUNET_free (*cref);
    *cref = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}
