/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2020, 2024 Taler Systems SA

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
 * @file exchangedb/plugin_exchangedb_common.c
 * @brief Functions shared across plugins, this file is meant to be
 *        included in each plugin.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "plugin_exchangedb_common.h"


void
TEH_COMMON_free_reserve_history (
  void *cls,
  struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  (void) cls;
  while (NULL != rh)
  {
    switch (rh->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      {
        struct TALER_EXCHANGEDB_BankTransfer *bt;

        bt = rh->details.bank;
        GNUNET_free (bt->sender_account_details.full_payto);
        GNUNET_free (bt);
        break;
      }
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      {
        struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;

        cbc = rh->details.withdraw;
        TALER_blinded_denom_sig_free (&cbc->sig);
        GNUNET_free (cbc);
        break;
      }
    case TALER_EXCHANGEDB_RO_RECOUP_COIN:
      {
        struct TALER_EXCHANGEDB_Recoup *recoup;

        recoup = rh->details.recoup;
        TALER_denom_sig_free (&recoup->coin.denom_sig);
        GNUNET_free (recoup);
        break;
      }
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      {
        struct TALER_EXCHANGEDB_ClosingTransfer *closing;

        closing = rh->details.closing;
        GNUNET_free (closing->receiver_account_details.full_payto);
        GNUNET_free (closing);
        break;
      }
    case TALER_EXCHANGEDB_RO_PURSE_MERGE:
      {
        struct TALER_EXCHANGEDB_PurseMerge *merge;

        merge = rh->details.merge;
        GNUNET_free (merge);
        break;
      }
    case TALER_EXCHANGEDB_RO_HISTORY_REQUEST:
      {
        struct TALER_EXCHANGEDB_HistoryRequest *history;

        history = rh->details.history;
        GNUNET_free (history);
        break;
      }
    case TALER_EXCHANGEDB_RO_OPEN_REQUEST:
      {
        struct TALER_EXCHANGEDB_OpenRequest *or;

        or = rh->details.open_request;
        GNUNET_free (or);
        break;
      }
    case TALER_EXCHANGEDB_RO_CLOSE_REQUEST:
      {
        struct TALER_EXCHANGEDB_CloseRequest *cr;

        cr = rh->details.close_request;
        GNUNET_free (cr);
        break;
      }
    }
    {
      struct TALER_EXCHANGEDB_ReserveHistory *next;

      next = rh->next;
      GNUNET_free (rh);
      rh = next;
    }
  }
}


void
TEH_COMMON_free_coin_transaction_list (
  void *cls,
  struct TALER_EXCHANGEDB_TransactionList *tl)
{
  (void) cls;
  while (NULL != tl)
  {
    switch (tl->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      {
        struct TALER_EXCHANGEDB_DepositListEntry *deposit;

        deposit = tl->details.deposit;
        GNUNET_free (deposit->receiver_wire_account.full_payto);
        GNUNET_free (deposit);
        break;
      }
    case TALER_EXCHANGEDB_TT_MELT:
      GNUNET_free (tl->details.melt);
      break;
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      {
        struct TALER_EXCHANGEDB_RecoupRefreshListEntry *rr;

        rr = tl->details.old_coin_recoup;
        TALER_denom_sig_free (&rr->coin.denom_sig);
        GNUNET_free (rr);
        break;
      }
    case TALER_EXCHANGEDB_TT_REFUND:
      GNUNET_free (tl->details.refund);
      break;
    case TALER_EXCHANGEDB_TT_RECOUP:
      GNUNET_free (tl->details.recoup);
      break;
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      {
        struct TALER_EXCHANGEDB_RecoupRefreshListEntry *rr;

        rr = tl->details.recoup_refresh;
        TALER_denom_sig_free (&rr->coin.denom_sig);
        GNUNET_free (rr);
        break;
      }
    case TALER_EXCHANGEDB_TT_PURSE_DEPOSIT:
      {
        struct TALER_EXCHANGEDB_PurseDepositListEntry *deposit;

        deposit = tl->details.purse_deposit;
        GNUNET_free (deposit->exchange_base_url);
        GNUNET_free (deposit);
        break;
      }
    case TALER_EXCHANGEDB_TT_PURSE_REFUND:
      {
        struct TALER_EXCHANGEDB_PurseRefundListEntry *prefund;

        prefund = tl->details.purse_refund;
        GNUNET_free (prefund);
        break;
      }
    case TALER_EXCHANGEDB_TT_RESERVE_OPEN:
      {
        struct TALER_EXCHANGEDB_ReserveOpenListEntry *role;

        role = tl->details.reserve_open;
        GNUNET_free (role);
        break;
      }
    }
    {
      struct TALER_EXCHANGEDB_TransactionList *next;

      next = tl->next;
      GNUNET_free (tl);
      tl = next;
    }
  }
}


/* end of plugin_exchangedb_common.c */
