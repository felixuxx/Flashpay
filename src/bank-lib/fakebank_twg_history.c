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
 * @file bank-lib/fakebank_twg_history.c
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

/**
 * Function called to clean up a history context.
 *
 * @param cls a `struct HistoryContext *`
 */
static void
history_cleanup (void *cls)
{
  struct HistoryContext *hc = cls;

  json_decref (hc->history);
  GNUNET_free (hc);
}


MHD_RESULT
TALER_FAKEBANK_twg_get_debit_history_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  void **con_cls)
{
  struct ConnectionContext *cc = *con_cls;
  struct HistoryContext *hc;
  struct Transaction *pos;
  enum GNUNET_GenericReturnValue ret;
  bool in_shutdown;
  const char *acc_payto_uri;

  if (NULL == cc)
  {
    cc = GNUNET_new (struct ConnectionContext);
    cc->ctx_cleaner = &history_cleanup;
    *con_cls = cc;
    hc = GNUNET_new (struct HistoryContext);
    cc->ctx = hc;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling /history/outgoing connection %p\n",
                connection);
    if (GNUNET_OK !=
        (ret = TALER_FAKEBANK_common_parse_history_args (h,
                                                         connection,
                                                         &hc->ha)))
    {
      GNUNET_break_op (0);
      return (GNUNET_SYSERR == ret) ? MHD_NO : MHD_YES;
    }
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->big_lock));
    hc->acc = TALER_FAKEBANK_lookup_account_ (h,
                                              account,
                                              NULL);
    if (NULL == hc->acc)
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                         account);
    }
    hc->history = json_array ();
    if (NULL == hc->history)
    {
      GNUNET_break (0);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_NO;
    }
    hc->timeout = GNUNET_TIME_relative_to_absolute (hc->ha.lp_timeout);
  }
  else
  {
    hc = cc->ctx;
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->big_lock));
  }

  if (! hc->ha.have_start)
  {
    pos = (0 > hc->ha.delta)
      ? hc->acc->out_tail
      : hc->acc->out_head;
  }
  else
  {
    struct Transaction *t = h->transactions[hc->ha.start_idx % h->ram_limit];
    bool overflow;
    uint64_t dir;
    bool skip = true;

    dir = (0 > hc->ha.delta) ? (h->ram_limit - 1) : 1;
    overflow = (t->row_id != hc->ha.start_idx);
    /* If account does not match, linear scan for
       first matching account. */
    while ( (! overflow) &&
            (NULL != t) &&
            (t->debit_account != hc->acc) )
    {
      skip = false;
      t = h->transactions[(t->row_id + dir) % h->ram_limit];
      if ( (NULL != t) &&
           (t->row_id == hc->ha.start_idx) )
        overflow = true; /* full circle, give up! */
    }
    if ( (NULL == t) ||
         overflow)
    {
      /* FIXME: these conditions are unclear to me. */
      if ( (GNUNET_TIME_relative_is_zero (hc->ha.lp_timeout)) &&
           (0 < hc->ha.delta))
      {
        GNUNET_assert (0 ==
                       pthread_mutex_unlock (&h->big_lock));
        if (overflow)
        {
          return TALER_MHD_reply_with_ec (
            connection,
            TALER_EC_BANK_ANCIENT_TRANSACTION_GONE,
            NULL);
        }
        goto finish;
      }
      if (h->in_shutdown)
      {
        GNUNET_assert (0 ==
                       pthread_mutex_unlock (&h->big_lock));
        goto finish;
      }
      TALER_FAKEBANK_start_lp_ (h,
                                connection,
                                hc->acc,
                                GNUNET_TIME_absolute_get_remaining (
                                  hc->timeout),
                                LP_DEBIT,
                                NULL);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_YES;
    }
    if (t->debit_account != hc->acc)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid start specified, transaction %llu not with account %s!\n",
                  (unsigned long long) hc->ha.start_idx,
                  account);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_NO;
    }
    if (skip)
    {
      /* range is exclusive, skip the matching entry */
      if (0 > hc->ha.delta)
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
                (long long) hc->ha.delta,
                (unsigned long long) pos->row_id);
  while ( (0 != hc->ha.delta) &&
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
      if (0 > hc->ha.delta)
        pos = pos->prev_in;
      if (0 < hc->ha.delta)
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
      GNUNET_JSON_pack_timestamp ("date",
                                  pos->date),
      TALER_JSON_pack_amount ("amount",
                              &pos->amount),
      GNUNET_JSON_pack_string ("credit_account",
                               credit_payto),
      GNUNET_JSON_pack_string ("exchange_base_url",
                               pos->subject.debit.exchange_base_url),
      GNUNET_JSON_pack_data_auto ("wtid",
                                  &pos->subject.debit.wtid));
    GNUNET_assert (NULL != trans);
    GNUNET_free (credit_payto);
    GNUNET_assert (0 ==
                   json_array_append_new (hc->history,
                                          trans));
    if (hc->ha.delta > 0)
      hc->ha.delta--;
    else
      hc->ha.delta++;
    if (0 > hc->ha.delta)
      pos = pos->prev_out;
    if (0 < hc->ha.delta)
      pos = pos->next_out;
  }
  if ( (0 == json_array_size (hc->history)) &&
       (! h->in_shutdown) &&
       (GNUNET_TIME_absolute_is_future (hc->timeout)) &&
       (0 < hc->ha.delta))
  {
    TALER_FAKEBANK_start_lp_ (h,
                              connection,
                              hc->acc,
                              GNUNET_TIME_absolute_get_remaining (hc->timeout),
                              LP_DEBIT,
                              NULL);
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return MHD_YES;
  }
  in_shutdown = h->in_shutdown;
  acc_payto_uri = hc->acc->payto_uri;
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
finish:
  if (0 == json_array_size (hc->history))
  {
    GNUNET_break (in_shutdown ||
                  (! GNUNET_TIME_absolute_is_future (hc->timeout)));
    return TALER_MHD_reply_static (connection,
                                   MHD_HTTP_NO_CONTENT,
                                   NULL,
                                   NULL,
                                   0);
  }
  {
    json_t *h = hc->history;

    hc->history = NULL;
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string (
        "debit_account",
        acc_payto_uri),
      GNUNET_JSON_pack_array_steal (
        "outgoing_transactions",
        h));
  }
}


MHD_RESULT
TALER_FAKEBANK_twg_get_credit_history_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  void **con_cls)
{
  struct ConnectionContext *cc = *con_cls;
  struct HistoryContext *hc;
  const struct Transaction *pos;
  enum GNUNET_GenericReturnValue ret;
  bool in_shutdown;
  const char *acc_payto_uri;

  if (NULL == cc)
  {
    cc = GNUNET_new (struct ConnectionContext);
    cc->ctx_cleaner = &history_cleanup;
    *con_cls = cc;
    hc = GNUNET_new (struct HistoryContext);
    cc->ctx = hc;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Handling /history/incoming connection %p\n",
                connection);
    if (GNUNET_OK !=
        (ret = TALER_FAKEBANK_common_parse_history_args (h,
                                                         connection,
                                                         &hc->ha)))
    {
      GNUNET_break_op (0);
      return (GNUNET_SYSERR == ret) ? MHD_NO : MHD_YES;
    }
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->big_lock));
    hc->acc = TALER_FAKEBANK_lookup_account_ (h,
                                              account,
                                              NULL);
    if (NULL == hc->acc)
    {
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_BANK_UNKNOWN_ACCOUNT,
                                         account);
    }
    hc->history = json_array ();
    if (NULL == hc->history)
    {
      GNUNET_break (0);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_NO;
    }
    hc->timeout = GNUNET_TIME_relative_to_absolute (hc->ha.lp_timeout);
  }
  else
  {
    hc = cc->ctx;
    GNUNET_assert (0 ==
                   pthread_mutex_lock (&h->big_lock));
  }

  if (! hc->ha.have_start)
  {
    pos = (0 > hc->ha.delta)
          ? hc->acc->in_tail
          : hc->acc->in_head;
  }
  else
  {
    struct Transaction *t = h->transactions[hc->ha.start_idx % h->ram_limit];
    bool overflow;
    uint64_t dir;
    bool skip = true;

    overflow = ( (NULL != t) && (t->row_id != hc->ha.start_idx) );
    dir = (0 > hc->ha.delta) ? (h->ram_limit - 1) : 1;
    /* If account does not match, linear scan for
       first matching account. */
    while ( (! overflow) &&
            (NULL != t) &&
            (t->credit_account != hc->acc) )
    {
      skip = false;
      t = h->transactions[(t->row_id + dir) % h->ram_limit];
      if ( (NULL != t) &&
           (t->row_id == hc->ha.start_idx) )
        overflow = true; /* full circle, give up! */
    }
    if ( (NULL == t) ||
         overflow)
    {
      /* FIXME: these conditions are unclear to me. */
      if (GNUNET_TIME_relative_is_zero (hc->ha.lp_timeout) &&
          (0 < hc->ha.delta))
      {
        GNUNET_assert (0 ==
                       pthread_mutex_unlock (&h->big_lock));
        if (overflow)
          return TALER_MHD_reply_with_ec (
            connection,
            TALER_EC_BANK_ANCIENT_TRANSACTION_GONE,
            NULL);
        goto finish;
      }
      if (h->in_shutdown)
      {
        GNUNET_assert (0 ==
                       pthread_mutex_unlock (&h->big_lock));
        goto finish;
      }
      TALER_FAKEBANK_start_lp_ (h,
                                connection,
                                hc->acc,
                                GNUNET_TIME_absolute_get_remaining (
                                  hc->timeout),
                                LP_CREDIT,
                                NULL);
      GNUNET_assert (0 ==
                     pthread_mutex_unlock (&h->big_lock));
      return MHD_YES;
    }
    if (skip)
    {
      /* range from application is exclusive, skip the
  matching entry */
      if (0 > hc->ha.delta)
        pos = t->prev_in;
      else
        pos = t->next_in;
    }
    else
    {
      pos = t;
    }
  }
  if (NULL != pos)
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning %lld credit transactions starting (inclusive) from %llu\n",
                (long long) hc->ha.delta,
                (unsigned long long) pos->row_id);
  while ( (0 != hc->ha.delta) &&
          (NULL != pos) )
  {
    json_t *trans;

    if (T_CREDIT != pos->type)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Unexpected DEBIT transaction #%llu for account `%s'\n",
                  (unsigned long long) pos->row_id,
                  account);
      if (0 > hc->ha.delta)
        pos = pos->prev_in;
      if (0 < hc->ha.delta)
        pos = pos->next_in;
      continue;
    }
    trans = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("row_id",
                               pos->row_id),
      GNUNET_JSON_pack_timestamp ("date",
                                  pos->date),
      TALER_JSON_pack_amount ("amount",
                              &pos->amount),
      GNUNET_JSON_pack_string ("debit_account",
                               pos->debit_account->payto_uri),
      GNUNET_JSON_pack_data_auto ("reserve_pub",
                                  &pos->subject.credit.reserve_pub));
    GNUNET_assert (NULL != trans);
    GNUNET_assert (0 ==
                   json_array_append_new (hc->history,
                                          trans));
    if (hc->ha.delta > 0)
      hc->ha.delta--;
    else
      hc->ha.delta++;
    if (0 > hc->ha.delta)
      pos = pos->prev_in;
    if (0 < hc->ha.delta)
      pos = pos->next_in;
  }
  if ( (0 == json_array_size (hc->history)) &&
       (! h->in_shutdown) &&
       (GNUNET_TIME_absolute_is_future (hc->timeout)) &&
       (0 < hc->ha.delta))
  {
    TALER_FAKEBANK_start_lp_ (h,
                              connection,
                              hc->acc,
                              GNUNET_TIME_absolute_get_remaining (hc->timeout),
                              LP_CREDIT,
                              NULL);
    GNUNET_assert (0 ==
                   pthread_mutex_unlock (&h->big_lock));
    return MHD_YES;
  }
  in_shutdown = h->in_shutdown;
  acc_payto_uri = hc->acc->payto_uri;
  GNUNET_assert (0 ==
                 pthread_mutex_unlock (&h->big_lock));
finish:
  if (0 == json_array_size (hc->history))
  {
    GNUNET_break (in_shutdown ||
                  (! GNUNET_TIME_absolute_is_future (hc->timeout)));
    return TALER_MHD_reply_static (connection,
                                   MHD_HTTP_NO_CONTENT,
                                   NULL,
                                   NULL,
                                   0);
  }
  {
    json_t *h = hc->history;

    hc->history = NULL;
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string (
        "credit_account",
        acc_payto_uri),
      GNUNET_JSON_pack_array_steal (
        "incoming_transactions",
        h));
  }
}
