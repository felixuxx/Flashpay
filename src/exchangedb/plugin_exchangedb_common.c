/*
  This file is part of TALER
  Copyright (C) 2015, 2016 Inria & GNUnet e.V.

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
  struct TALER_EXCHANGEDB_BankTransfer *bt;
  struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;
  struct TALER_EXCHANGEDB_Payback *payback;
  struct TALER_EXCHANGEDB_ReserveHistory *backref;
  struct TALER_EXCHANGEDB_ClosingTransfer *closing;

  while (NULL != rh)
  {
    switch(rh->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      bt = rh->details.bank;
      GNUNET_free_non_null (bt->sender_account_details);
      GNUNET_free_non_null (bt->wire_reference);
      GNUNET_free (bt);
      break;
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      cbc = rh->details.withdraw;
      GNUNET_CRYPTO_rsa_signature_free (cbc->sig.rsa_signature);
      GNUNET_free (cbc);
      break;
    case TALER_EXCHANGEDB_RO_PAYBACK_COIN:
      payback = rh->details.payback;
      GNUNET_CRYPTO_rsa_signature_free (payback->coin.denom_sig.rsa_signature);
      GNUNET_free (payback);
      break;
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      closing = rh->details.closing;
      GNUNET_free_non_null (closing->receiver_account_details);
      GNUNET_free (closing);
      break;
    }
    backref = rh;
    rh = rh->next;
    GNUNET_free (backref);
  }
}


/**
 * Free linked list of transactions.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param list list to free
 */
static void
common_free_coin_transaction_list (void *cls,
                                   struct TALER_EXCHANGEDB_TransactionList *list)
{
  struct TALER_EXCHANGEDB_TransactionList *next;

  while (NULL != list)
  {
    next = list->next;

    switch (list->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      if (NULL != list->details.deposit->receiver_wire_account)
        json_decref (list->details.deposit->receiver_wire_account);
      if (NULL != list->details.deposit->coin.denom_sig.rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (list->details.deposit->coin.denom_sig.rsa_signature);
      GNUNET_free (list->details.deposit);
      break;
    case TALER_EXCHANGEDB_TT_REFRESH_MELT:
      if (NULL != list->details.melt->session.coin.denom_sig.rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (list->details.melt->session.coin.denom_sig.rsa_signature);
      GNUNET_free (list->details.melt);
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      if (NULL != list->details.refund->coin.denom_sig.rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (list->details.refund->coin.denom_sig.rsa_signature);
      GNUNET_free (list->details.refund);
      break;
    case TALER_EXCHANGEDB_TT_PAYBACK:
      if (NULL != list->details.payback->coin.denom_sig.rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (list->details.payback->coin.denom_sig.rsa_signature);
      GNUNET_free (list->details.payback);
      break;
    }
    GNUNET_free (list);
    list = next;
  }
}


/* end of plugin_exchangedb_common.c */
