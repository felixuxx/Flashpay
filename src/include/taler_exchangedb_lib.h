/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file include/taler_exchangedb_lib.h
 * @brief IO operations for the exchange's private keys
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGEDB_LIB_H
#define TALER_EXCHANGEDB_LIB_H

#include "taler_signatures.h"
#include "taler_exchangedb_plugin.h"
#include "taler_bank_service.h"


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return NULL on failure
 */
struct TALER_EXCHANGEDB_Plugin *
TALER_EXCHANGEDB_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shutdown the plugin.
 *
 * @param plugin plugin to unload
 */
void
TALER_EXCHANGEDB_plugin_unload (struct TALER_EXCHANGEDB_Plugin *plugin);


/**
 * Information about an account from the configuration.
 */
struct TALER_EXCHANGEDB_AccountInfo
{
  /**
   * Section in the configuration file that specifies the
   * account. Must start with "exchange-account-".
   */
  const char *section_name;

  /**
   * Name of the wire method used by this account.
   */
  const char *method;

  /**
   * payto://-URL of the account.
   */
  const char *payto_uri;

  /**
   * Filename containing the signed /wire response, or NULL
   * if not given.
   */
  const char *wire_response_filename;

  /**
   * #GNUNET_YES if this account is enabed to be debited
   * by the taler-exchange-aggregator.
   */
  int debit_enabled;

  /**
   * #GNUNET_YES if this account is enabed to be credited by wallets
   * and needs to be watched by the taler-exchange-wirewatch.
   * Also, the account will only be included in /wire if credit
   * is enabled.
   */
  int credit_enabled;
};


/**
 * Function called with information about a wire account.
 *
 * @param cls closure
 * @param ai account information
 */
typedef void
(*TALER_EXCHANGEDB_AccountCallback)(
  void *cls,
  const struct TALER_EXCHANGEDB_AccountInfo *ai);

/**
 * Parse the configuration to find account information.
 *
 * @param cfg configuration to use
 * @param cb callback to invoke
 * @param cb_cls closure for @a cb
 * @return #GNUNET_OK if the configuration seems valid, #GNUNET_SYSERR if not
 */
int
TALER_EXCHANGEDB_find_accounts (const struct GNUNET_CONFIGURATION_Handle *cfg,
                                TALER_EXCHANGEDB_AccountCallback cb,
                                void *cb_cls);


/**
 * Calculate the total value of all transactions performed.
 * Stores @a off plus the cost of all transactions in @a tl
 * in @a ret.
 *
 * @param tl transaction list to process
 * @param off offset to use as the starting value
 * @param[out] ret where the resulting total is to be stored
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
int
TALER_EXCHANGEDB_calculate_transaction_list_totals (
  struct TALER_EXCHANGEDB_TransactionList *tl,
  const struct TALER_Amount *off,
  struct TALER_Amount *ret);


/* ***************** convenience functions ******** */

/**
 * Information we keep for each supported account of the exchange.
 */
struct TALER_EXCHANGEDB_WireAccount
{
  /**
   * Accounts are kept in a DLL.
   */
  struct TALER_EXCHANGEDB_WireAccount *next;

  /**
   * Plugins are kept in a DLL.
   */
  struct TALER_EXCHANGEDB_WireAccount *prev;

  /**
   * Authentication data.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Name of the section that configures this account.
   */
  char *section_name;

  /**
   * Name of the wire method underlying the account.
   */
  char *method;

};


/**
 * Find the wire plugin for the given payto:// URL.
 * Only useful after the accounts have been loaded
 * using #TALER_EXCHANGEDB_load_accounts().
 *
 * @param method wire method we need an account for
 * @return NULL on error
 */
struct TALER_EXCHANGEDB_WireAccount *
TALER_EXCHANGEDB_find_account_by_method (const char *method);


/**
 * Find the wire plugin for the given payto:// URL
 * Only useful after the accounts have been loaded
 * using #TALER_EXCHANGEDB_load_accounts().
 *
 * @param url wire address we need an account for
 * @return NULL on error
 */
struct TALER_EXCHANGEDB_WireAccount *
TALER_EXCHANGEDB_find_account_by_payto_uri (const char *url);


/**
 * Load account information opf the exchange from
 * @a cfg.
 *
 * @param cfg configuration to load from
 * @return #GNUNET_OK on success, #GNUNET_NO if no accounts are configured
 */
int
TALER_EXCHANGEDB_load_accounts (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Free resources allocated by
 * #TALER_EXCHANGEDB_load_accounts().
 */
void
TALER_EXCHANGEDB_unload_accounts (void);

#endif
