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
   * Authentication data. Only parsed if
   * #TALER_EXCHANGEDB_ALO_AUTHDATA was set.
   */
  const struct TALER_BANK_AuthenticationData *auth;

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
   * true if this account is enabed to be debited
   * by the taler-exchange-aggregator.
   */
  bool debit_enabled;

  /**
   * true if this account is enabed to be credited by wallets
   * and needs to be watched by the taler-exchange-wirewatch.
   * Also, the account will only be included in /wire if credit
   * is enabled.
   */
  bool credit_enabled;
};


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
 * Return information about all accounts that
 * were loaded by #TALER_EXCHANGEDB_load_accounts().
 *
 * @param cb callback to invoke
 * @param cb_cls closure for @a cb
 */
void
TALER_EXCHANGEDB_find_accounts (TALER_EXCHANGEDB_AccountCallback cb,
                                void *cb_cls);


/**
 * Find the wire plugin for the given payto:// URL.
 * Only useful after the accounts have been loaded
 * using #TALER_EXCHANGEDB_load_accounts().
 *
 * @param method wire method we need an account for
 * @return NULL on error
 */
const struct TALER_EXCHANGEDB_AccountInfo *
TALER_EXCHANGEDB_find_account_by_method (const char *method);


/**
 * Find the wire plugin for the given payto:// URL
 * Only useful after the accounts have been loaded
 * using #TALER_EXCHANGEDB_load_accounts().
 *
 * @param url wire address we need an account for
 * @return NULL on error
 */
const struct TALER_EXCHANGEDB_AccountInfo *
TALER_EXCHANGEDB_find_account_by_payto_uri (const char *url);


/**
 * Options for #TALER_EXCHANGEDB_load_accounts()
 */
enum TALER_EXCHANGEDB_AccountLoaderOptions
{
  TALER_EXCHANGEDB_ALO_NONE = 0,

  /**
   * Load accounts enabled for DEBITs.
   */
  TALER_EXCHANGEDB_ALO_DEBIT = 1,

  /**
   * Load accounts enabled for CREDITs.
   */
  TALER_EXCHANGEDB_ALO_CREDIT = 2,

  /**
   * Load authentication data from the
   * "taler-accountcredentials-" section
   * to access the account at the bank.
   */
  TALER_EXCHANGEDB_ALO_AUTHDATA = 4
};


/**
 * Load account information opf the exchange from
 * @a cfg.
 *
 * @param cfg configuration to load from
 * @param options loader options
 * @return #GNUNET_OK on success, #GNUNET_NO if no accounts are configured
 */
enum GNUNET_GenericReturnValue
TALER_EXCHANGEDB_load_accounts (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  enum TALER_EXCHANGEDB_AccountLoaderOptions options);


/**
 * Free resources allocated by
 * #TALER_EXCHANGEDB_load_accounts().
 */
void
TALER_EXCHANGEDB_unload_accounts (void);

#endif
