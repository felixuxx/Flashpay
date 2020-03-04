/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2020 Taler Systems SA

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

/**
 * Free memory associated with the given reserve history.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param rh history to free.
 */
static void
common_free_reserve_history (void *cls,
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
        GNUNET_free_non_null (bt->sender_account_details);
        GNUNET_free_non_null (bt->wire_reference);
        GNUNET_free (bt);
        break;
      }
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      {
        struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;

        cbc = rh->details.withdraw;
        GNUNET_CRYPTO_rsa_signature_free (cbc->sig.rsa_signature);
        GNUNET_free (cbc);
        break;
      }
    case TALER_EXCHANGEDB_RO_RECOUP_COIN:
      {
        struct TALER_EXCHANGEDB_Recoup *recoup;

        recoup = rh->details.recoup;
        GNUNET_CRYPTO_rsa_signature_free (recoup->coin.denom_sig.rsa_signature);
        GNUNET_free (recoup);
        break;
      }
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      {
        struct TALER_EXCHANGEDB_ClosingTransfer *closing;

        closing = rh->details.closing;
        GNUNET_free_non_null (closing->receiver_account_details);
        GNUNET_free (closing);
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


/**
 * Free linked list of transactions.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param tl list to free
 */
static void
common_free_coin_transaction_list (void *cls,
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
        if (NULL != deposit->receiver_wire_account)
          json_decref (deposit->receiver_wire_account);
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
        if (NULL != rr->coin.denom_sig.rsa_signature)
          GNUNET_CRYPTO_rsa_signature_free (rr->coin.denom_sig.rsa_signature);
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
        if (NULL != rr->coin.denom_sig.rsa_signature)
          GNUNET_CRYPTO_rsa_signature_free (rr->coin.denom_sig.rsa_signature);
        GNUNET_free (rr);
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
