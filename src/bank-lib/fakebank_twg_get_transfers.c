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
 * @file bank-lib/fakebank_twg_get_transfers.c
 * @brief routines to return account histories for the Taler Wire Gateway API
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
TALER_FAKEBANK_twg_get_transfers_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  void **con_cls)
{
  struct Transaction *pos;
  const char *acc_payto_uri;
  json_t *history;
  struct Account *acc;
  int64_t limit = -20;
  uint64_t offset;
  bool have_start;
  const char *status;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Handling /transfers connection %p\n",
              connection);

  TALER_MHD_parse_request_snumber (connection,
                                   "limit",
                                   &limit);
  if (limit > 0)
    offset = 0;
  else
    offset = UINT64_MAX;
  TALER_MHD_parse_request_number (connection,
                                  "offset",
                                  &offset);
  have_start = ((0 != offset) && (UINT64_MAX != offset));
  status = MHD_lookup_connection_value (connection,
                                        MHD_GET_ARGUMENT_KIND,
                                        "status");
  if ( (NULL != status) &&
       (0 != strcasecmp (status,
                         "success")) )
  {
    /* we only have successful transactions */
    return TALER_MHD_reply_static (connection,
                                   MHD_HTTP_NO_CONTENT,
                                   NULL,
                                   NULL,
                                   0);
  }

  GNUNET_assert (0 ==
                 pthread_mutex_lock (&h->big_lock));
  if (UINT64_MAX == offset)
    offset = h->serial_counter;
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
  history = json_array ();
  if (NULL == history)
  {
    GNUNET_break (0);
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return MHD_NO;
  }

  if (! have_start)
  {
    pos = (0 > limit)
      ? acc->out_tail
      : acc->out_head;
  }
  else
  {
    struct Transaction *t = h->transactions[offset % h->ram_limit];
    bool overflow;
    uint64_t dir;
    bool skip = true;

    dir = (0 > limit) ? (h->ram_limit - 1) : 1;
    overflow = (t->row_id != offset);
    /* If account does not match, linear scan for
       first matching account. */
    while ( (! overflow) &&
            (NULL != t) &&
            (t->debit_account != acc) )
    {
      skip = false;
      t = h->transactions[(t->row_id + dir) % h->ram_limit];
      if ( (NULL != t) &&
           (t->row_id == offset) )
        overflow = true; /* full circle, give up! */
    }
    if ( (NULL == t) ||
         (t->debit_account != acc) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid start specified, transaction %llu not with account %s!\n",
                  (unsigned long long) offset,
                  account);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_NO;
    }
    if (skip)
    {
      /* range is exclusive, skip the matching entry */
      if (0 > limit)
        pos = t->prev_out;
      else
        pos = t->next_out;
    }
    else
    {
      pos = t;
    }
  }
  if (NULL != pos)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning %lld debit transactions starting (inclusive) from %llu\n",
                (long long) limit,
                (unsigned long long) pos->row_id);
  while ( (0 != limit) &&
          (NULL != pos) )
  {
    json_t *trans;
    char *credit_payto;

    if (T_DEBIT != pos->type)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Unexpected CREDIT transaction #%llu for account `%s'\n",
                  (unsigned long long) pos->row_id,
                  account);
      if (0 > limit)
        pos = pos->prev_in;
      if (0 < limit)
        pos = pos->next_in;
      continue;
    }
    GNUNET_asprintf (&credit_payto,
                     "payto://x-taler-bank/localhost/%s?receiver-name=%s",
                     pos->credit_account->account_name,
                     pos->credit_account->receiver_name);

    trans = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("row_id",
                               pos->row_id),
      GNUNET_JSON_pack_timestamp ("timestamp",
                                  pos->date),
      TALER_JSON_pack_amount ("amount",
                              &pos->amount),
      GNUNET_JSON_pack_string ("credit_account",
                               credit_payto),
      GNUNET_JSON_pack_string ("status",
                               "success"));
    GNUNET_assert (NULL != trans);
    GNUNET_free (credit_payto);
    GNUNET_assert (0 ==
                   json_array_append_new (history,
                                          trans));
    if (limit > 0)
      limit--;
    else
      limit++;
    if (0 > limit)
      pos = pos->prev_out;
    if (0 < limit)
      pos = pos->next_out;
  }
  acc_payto_uri = acc->payto_uri;
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
  if (0 == json_array_size (history))
  {
    json_decref (history);
    return TALER_MHD_reply_static (connection,
                                   MHD_HTTP_NO_CONTENT,
                                   NULL,
                                   NULL,
                                   0);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_string (
      "debit_account",
      acc_payto_uri),
    GNUNET_JSON_pack_array_steal (
      "transfers",
      history));
}
