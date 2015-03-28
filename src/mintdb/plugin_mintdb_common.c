/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mint/plugin_mintdb_common.c
 * @brief Functions shared across plugins, this file is meant to be
 *        #include-d in each plugin.
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
                             struct TALER_MINTDB_ReserveHistory *rh)
{
  struct TALER_MINTDB_BankTransfer *bt;
  struct TALER_MINTDB_CollectableBlindcoin *cbc;
  struct TALER_MINTDB_ReserveHistory *backref;

  while (NULL != rh)
  {
    switch(rh->type)
    {
    case TALER_MINTDB_RO_BANK_TO_MINT:
      bt = rh->details.bank;
      if (NULL != bt->wire)
        json_decref (bt->wire);
      GNUNET_free (bt);
      break;
    case TALER_MINTDB_RO_WITHDRAW_COIN:
      cbc = rh->details.withdraw;
      GNUNET_CRYPTO_rsa_signature_free (cbc->sig.rsa_signature);
      GNUNET_CRYPTO_rsa_public_key_free (cbc->denom_pub.rsa_public_key);
      GNUNET_free (cbc);
      break;
    }
    backref = rh;
    rh = rh->next;
    GNUNET_free (backref);
  }
}


/**
 * Free memory of the link data list.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param ldl link data list to release
 */
static void
common_free_link_data_list (void *cls,
                            struct TALER_MINTDB_LinkDataList *ldl)
{
  struct TALER_MINTDB_LinkDataList *next;

  while (NULL != ldl)
  {
    next = ldl->next;
    GNUNET_free (ldl->link_data_enc);
    GNUNET_free (ldl);
    ldl = next;
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
                                   struct TALER_MINTDB_TransactionList *list)
{
  struct TALER_MINTDB_TransactionList *next;

  while (NULL != list)
  {
    next = list->next;

    switch (list->type)
    {
    case TALER_MINTDB_TT_DEPOSIT:
      json_decref (list->details.deposit->wire);
      GNUNET_free (list->details.deposit);
      break;
    case TALER_MINTDB_TT_REFRESH_MELT:
      GNUNET_free (list->details.melt);
      break;
    case TALER_MINTDB_TT_LOCK:
      GNUNET_free (list->details.lock);
      /* FIXME: look at this again once locking is implemented (#3625) */
      break;
    }
    GNUNET_free (list);
    list = next;
  }
}

/* end of plugin_mintdb_common.c */
