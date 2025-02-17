/*
  This file is part of TALER
  Copyright (C) 2017-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file exchangedb/exchangedb_transactions.c
 * @brief Logic to compute transaction totals of a transaction list for a coin
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"


enum GNUNET_GenericReturnValue
TALER_EXCHANGEDB_calculate_transaction_list_totals (
  struct TALER_EXCHANGEDB_TransactionList *tl,
  const struct TALER_Amount *off,
  struct TALER_Amount *ret)
{
  struct TALER_Amount spent = *off;
  struct TALER_Amount refunded;
  struct TALER_Amount deposit_fee;
  bool have_refund;

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (spent.currency,
                                        &refunded));
  have_refund = false;
  for (struct TALER_EXCHANGEDB_TransactionList *pos = tl;
       NULL != pos;
       pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      /* spent += pos->amount_with_fee */
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.deposit->amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      deposit_fee = pos->details.deposit->deposit_fee;
      break;
    case TALER_EXCHANGEDB_TT_MELT:
      /* spent += pos->amount_with_fee */
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.melt->amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      /* refunded += pos->refund_amount - pos->refund_fee */
      if (0 >
          TALER_amount_add (&refunded,
                            &refunded,
                            &pos->details.refund->refund_amount))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.refund->refund_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      have_refund = true;
      break;
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      /* refunded += pos->value */
      if (0 >
          TALER_amount_add (&refunded,
                            &refunded,
                            &pos->details.old_coin_recoup->value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_RECOUP:
      /* spent += pos->value */
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.recoup->value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      /* spent += pos->value */
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.recoup_refresh->value))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_PURSE_DEPOSIT:
      /* spent += pos->amount_with_fee */
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.purse_deposit->amount))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      deposit_fee = pos->details.purse_deposit->deposit_fee;
      break;
    case TALER_EXCHANGEDB_TT_PURSE_REFUND:
      /* refunded += pos->refund_amount - pos->refund_fee */
      if (0 >
          TALER_amount_add (&refunded,
                            &refunded,
                            &pos->details.purse_refund->refund_amount))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.purse_refund->refund_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      have_refund = true;
      break;
    case TALER_EXCHANGEDB_TT_RESERVE_OPEN:
      /* spent += pos->amount_with_fee */
      if (0 >
          TALER_amount_add (&spent,
                            &spent,
                            &pos->details.reserve_open->coin_contribution))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    }
  }
  if (have_refund)
  {
    /* If we gave any refund, also discount ONE deposit fee */
    if (0 >
        TALER_amount_add (&refunded,
                          &refunded,
                          &deposit_fee))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
  }
  /* spent = spent - refunded */
  if (0 >
      TALER_amount_subtract (&spent,
                             &spent,
                             &refunded))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  *ret = spent;
  return GNUNET_OK;
}
