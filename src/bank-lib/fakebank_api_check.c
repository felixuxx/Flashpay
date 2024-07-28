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
 * @file bank-lib/fakebank_api_check.c
 * @brief library that fakes being a Taler bank for testcases
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_common_lookup.h"


/**
 * Generate log messages for failed check operation.
 *
 * @param h handle to output transaction log for
 */
static void
check_log (struct TALER_FAKEBANK_Handle *h)
{
  for (uint64_t i = 0; i<h->ram_limit; i++)
  {
    struct Transaction *t = h->transactions[i];

    if (NULL == t)
      continue;
    if (! t->unchecked)
      continue;
    switch (t->type)
    {
    case T_DEBIT:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  t->subject.debit.exchange_base_url,
                  "DEBIT");
      break;
    case T_CREDIT:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  TALER_B2S (&t->subject.credit.reserve_pub),
                  "CREDIT");
      break;
    case T_AUTH:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  TALER_B2S (&t->subject.auth.account_pub),
                  "AUTH");
      break;
    case T_WAD:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "%s -> %s (%s) %s[%s] (%s)\n",
                  t->debit_account->account_name,
                  t->credit_account->account_name,
                  TALER_amount2s (&t->amount),
                  t->subject.wad.origin_base_url,
                  TALER_B2S (&t->subject.wad),
                  "WAD");
      break;
    }
  }
}


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_check_debit (struct TALER_FAKEBANK_Handle *h,
                            const struct TALER_Amount *want_amount,
                            const char *want_debit,
                            const char *want_credit,
                            const char *exchange_base_url,
                            struct TALER_WireTransferIdentifierRawP *wtid)
{
  struct Account *debit_account;
  struct Account *credit_account;

  GNUNET_assert (0 ==
                 strcasecmp (want_amount->currency,
                             h->currency));
  debit_account = TALER_FAKEBANK_lookup_account_ (h,
                                                  want_debit,
                                                  NULL);
  credit_account = TALER_FAKEBANK_lookup_account_ (h,
                                                   want_credit,
                                                   NULL);
  if (NULL == debit_account)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "I wanted: %s->%s (%s) from exchange %s (DEBIT), but debit account does not even exist!\n",
                want_debit,
                want_credit,
                TALER_amount2s (want_amount),
                exchange_base_url);
    return GNUNET_SYSERR;
  }
  if (NULL == credit_account)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "I wanted: %s->%s (%s) from exchange %s (DEBIT), but credit account does not even exist!\n",
                want_debit,
                want_credit,
                TALER_amount2s (want_amount),
                exchange_base_url);
    return GNUNET_SYSERR;
  }
  for (struct Transaction *t = debit_account->out_tail;
       NULL != t;
       t = t->prev_out)
  {
    if ( (t->unchecked) &&
         (credit_account == t->credit_account) &&
         (T_DEBIT == t->type) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (0 == strcasecmp (exchange_base_url,
                           t->subject.debit.exchange_base_url)) )
    {
      *wtid = t->subject.debit.wtid;
      t->unchecked = false;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Did not find matching transaction! I have:\n");
  check_log (h);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "I wanted: %s->%s (%s) from exchange %s (DEBIT)\n",
              want_debit,
              want_credit,
              TALER_amount2s (want_amount),
              exchange_base_url);
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_check_credit (struct TALER_FAKEBANK_Handle *h,
                             const struct TALER_Amount *want_amount,
                             const char *want_debit,
                             const char *want_credit,
                             const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct Account *debit_account;
  struct Account *credit_account;

  GNUNET_assert (0 == strcasecmp (want_amount->currency,
                                  h->currency));
  debit_account = TALER_FAKEBANK_lookup_account_ (h,
                                                  want_debit,
                                                  NULL);
  credit_account = TALER_FAKEBANK_lookup_account_ (h,
                                                   want_credit,
                                                   NULL);
  if (NULL == debit_account)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "I wanted:\n%s -> %s (%s) with subject %s (CREDIT) but debit account is unknown.\n",
                want_debit,
                want_credit,
                TALER_amount2s (want_amount),
                TALER_B2S (reserve_pub));
    return GNUNET_SYSERR;
  }
  if (NULL == credit_account)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "I wanted:\n%s -> %s (%s) with subject %s (CREDIT) but credit account is unknown.\n",
                want_debit,
                want_credit,
                TALER_amount2s (want_amount),
                TALER_B2S (reserve_pub));
    return GNUNET_SYSERR;
  }
  for (struct Transaction *t = credit_account->in_tail;
       NULL != t;
       t = t->prev_in)
  {
    if ( (t->unchecked) &&
         (debit_account == t->debit_account) &&
         (T_CREDIT == t->type) &&
         (0 == TALER_amount_cmp (want_amount,
                                 &t->amount)) &&
         (0 == GNUNET_memcmp (reserve_pub,
                              &t->subject.credit.reserve_pub)) )
    {
      t->unchecked = false;
      return GNUNET_OK;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Did not find matching transaction!\nI have:\n");
  check_log (h);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "I wanted:\n%s -> %s (%s) with subject %s (CREDIT)\n",
              want_debit,
              want_credit,
              TALER_amount2s (want_amount),
              TALER_B2S (reserve_pub));
  return GNUNET_SYSERR;
}


enum GNUNET_GenericReturnValue
TALER_FAKEBANK_check_empty (struct TALER_FAKEBANK_Handle *h)
{
  for (uint64_t i = 0; i<h->ram_limit; i++)
  {
    struct Transaction *t = h->transactions[i];

    if ( (NULL != t) &&
         (t->unchecked) )
    {
      if (T_AUTH == t->type)
        continue; /* ignore */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Expected empty transaction set, but I have:\n");
      check_log (h);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}
