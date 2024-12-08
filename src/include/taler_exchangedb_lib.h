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
#include "taler_kyclogic_lib.h"


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @param skip_preflight true if we should skip the usual
 *   preflight check which assures us that the DB is actually
 *   operational; only taler-exchange-dbinit should use true here.
 * @return NULL on failure
 */
struct TALER_EXCHANGEDB_Plugin *
TALER_EXCHANGEDB_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                              bool skip_preflight);


/**
 * Shutdown the plugin.
 *
 * @param[in] plugin plugin to unload
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
   * true if this account is enabled to be debited
   * by the taler-exchange-aggregator.
   */
  bool debit_enabled;

  /**
   * true if this account is enabled to be credited by wallets
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
enum GNUNET_GenericReturnValue
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
TALER_EXCHANGEDB_find_account_by_payto_uri (
  const struct TALER_FullPayto url);


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


/**
 * Closure for various history building functions.
 */
struct TALER_EXCHANGEDB_HistoryBuilderContext
{
  /**
   * Account to build history for.
   */
  const struct TALER_NormalizedPaytoHashP *account;

  /**
   * Database plugin to build history with.
   */
  struct TALER_EXCHANGEDB_Plugin *db_plugin;

  /**
   * Key to use to decrypt KYC attributes.
   */
  struct TALER_AttributeEncryptionKeyP *attribute_key;
};


/**
 * Function called to obtain an AML
 * history in JSON on-demand if needed.
 *
 * @param cls must be a `struct TALER_EXCHANGEDB_HistoryBuilderContext *`
 * @return AML history in JSON format, NULL on error
 */
json_t *
TALER_EXCHANGEDB_aml_history_builder (void *cls);


/**
 * Function called to obtain a KYC
 * history in JSON on-demand if needed.
 *
 * @param cls must be a `struct TALER_EXCHANGEDB_HistoryBuilderContext *`
 * @return KYC history in JSON format, NULL on error
 */
json_t *
TALER_EXCHANGEDB_kyc_history_builder (void *cls);


/**
 * Function called to obtain the current ``LegitimizationRuleSet``
 * in JSON for an account on-demand if needed.
 *
 * @param cls must be a `struct TALER_EXCHANGEDB_HistoryBuilderContext *`
 * @return KYC history in JSON format, NULL on error
 */
json_t *
TALER_EXCHANGEDB_current_rule_builder (void *cls);


/**
 * Function called to obtain the latest KYC attributes
 * in JSON for an account on-demand if needed.
 *
 * @param cls must be a `struct TALER_EXCHANGEDB_HistoryBuilderContext *`
 * @return KYC attributes in JSON format, NULL on error
 */
json_t *
TALER_EXCHANGEDB_current_attributes_builder (void *cls);


/**
 * Handle for helper logic that advances rules to the currently
 * valid rule set.
 */
struct TALER_EXCHANGEDB_RuleUpdater;

/**
 * Main result returned in the
 * #TALER_EXCHANGEDB_CurrentRulesCallback
 */
struct TALER_EXCHANGEDB_RuleUpdaterResult
{
  /**
   * Row the rule set is based on.
   */
  uint64_t legitimization_outcome_last_row;

  /**
   * Current legitimization rule set, owned by callee.  Will be NULL on error
   * or for default rules. Will not contain skip rules and not be expired.
   */
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

  /**
   * Hint to return, if @e ec is not #TALER_EC_NONE. Can be NULL.
   */
  const char *hint;

  /**
   * Error code in case a problem was encountered
   * when fetching or updating the legitimization rules.
   */
  enum TALER_ErrorCode ec;
};


/**
 * Function called with the current rule set.
 *
 * @param cls closure
 * @param rur includes legitimziation rule set that applies to the account
 *   (owned by callee, callee must free the lrs!)
 */
typedef void
(*TALER_EXCHANGEDB_CurrentRulesCallback)(
  void *cls,
  struct TALER_EXCHANGEDB_RuleUpdaterResult *rur);


/**
 * Obtains the current rule set for an account and advances it
 * to the rule set that should apply right now. Considers
 * expiration of rules as well as "skip" measures. Runs
 * AML programs as needed to advance the rule book to the currently
 * valid state.
 *
 * On success, the result is returned in a (fresh) transaction
 * that must be committed for the result to be valid. This should
 * be used to ensure transactionality of the AML program result.
 *
 * This function should be called *outside* of any other transaction.
 * Calling it while a transaction is already running risks aborting
 * that transaction.
 *
 * @param plugin database plugin to use
 * @param attribute_key key to use to decrypt attributes
 * @param account account to get the rule set for
 * @param cb function to call with the result
 * @param cb_cls closure for @a cb
 * @return handle to cancel the operation
 */
struct TALER_EXCHANGEDB_RuleUpdater *
TALER_EXCHANGEDB_update_rules (
  struct TALER_EXCHANGEDB_Plugin *plugin,
  const struct TALER_AttributeEncryptionKeyP *attribute_key,
  const struct TALER_NormalizedPaytoHashP *account,
  TALER_EXCHANGEDB_CurrentRulesCallback cb,
  void *cb_cls);


/**
 * Cancel operation to get the current legitimization rule set.
 *
 * @param[in] ru operation to cancel
 */
void
TALER_EXCHANGEDB_update_rules_cancel (
  struct TALER_EXCHANGEDB_RuleUpdater *ru);


/**
 * Persist the given @a apr for the given process and account
 * into the database via @a plugin.
 *
 * @param plugin database API handle
 * @param process_row row identifying the AML process that was run
 * @param account_id hash of account the result is about
 * @param apr AML program result to persist
 */
enum GNUNET_DB_QueryStatus
TALER_EXCHANGEDB_persist_aml_program_result (
  struct TALER_EXCHANGEDB_Plugin *plugin,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *account_id,
  const struct TALER_KYCLOGIC_AmlProgramResult *apr);


#endif
