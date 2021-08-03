/*
  This file is part of TALER
  Copyright (C) 2018-2021 Taler Systems SA

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
 * @file exchangedb/exchangedb_accounts.c
 * @brief Logic to parse account information from the configuration
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"


/**
 * Information we keep for each supported account of the exchange.
 */
struct WireAccount
{
  /**
   * Accounts are kept in a DLL.
   */
  struct WireAccount *next;

  /**
   * Plugins are kept in a DLL.
   */
  struct WireAccount *prev;

  /**
   * Externally visible account information.
   */
  struct TALER_EXCHANGEDB_AccountInfo ai;

  /**
   * Authentication data. Only parsed if
   * #TALER_EXCHANGEDB_ALO_AUTHDATA was set.
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
 * Head of list of wire accounts of the exchange.
 */
static struct WireAccount *wa_head;

/**
 * Tail of list of wire accounts of the exchange.
 */
static struct WireAccount *wa_tail;


void
TALER_EXCHANGEDB_find_accounts (TALER_EXCHANGEDB_AccountCallback cb,
                                void *cb_cls)
{
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
    cb (cb_cls,
        &wa->ai);
}


const struct TALER_EXCHANGEDB_AccountInfo *
TALER_EXCHANGEDB_find_account_by_method (const char *method)
{
  for (struct WireAccount *wa = wa_head;
       NULL != wa;
       wa = wa->next)
    if (0 == strcmp (method,
                     wa->method))
      return &wa->ai;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "No wire account known for method `%s'\n",
              method);
  return NULL;
}


const struct TALER_EXCHANGEDB_AccountInfo *
TALER_EXCHANGEDB_find_account_by_payto_uri (const char *url)
{
  char *method;
  const struct TALER_EXCHANGEDB_AccountInfo *ai;

  method = TALER_payto_get_method (url);
  if (NULL == method)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid payto:// URL `%s'\n",
                url);
    return NULL;
  }
  ai = TALER_EXCHANGEDB_find_account_by_method (method);
  GNUNET_free (method);
  return ai;
}


/**
 * Closure for #add_account_cb().
 */
struct LoaderContext
{
  /**
   * Configuration to use.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * true if we are to load the authentication data
   * for the access to the bank account.
   */
  bool load_auth_data;

  /**
   * Load accounts enabled for CREDIT.
   */
  bool credit;

  /**
   * Load accounts enabled for DEBIT.
   */
  bool debit;

  /**
   * Loader status (set by callback).
   */
  enum GNUNET_GenericReturnValue res;
};


/**
 * Function called with information about a wire account.  Adds
 * the account to our list.
 *
 * @param cls closure, a `struct LoaderContext`
 * @param ai account information
 */
static void
add_account_cb (void *cls,
                const char *section)
{
  struct LoaderContext *lc = cls;
  const struct GNUNET_CONFIGURATION_Handle *cfg = lc->cfg;
  struct WireAccount *wa;
  char *payto_uri;
  char *method;
  bool debit;
  bool credit;

  if (0 != strncasecmp (section,
                        "exchange-account-",
                        strlen ("exchange-account-")))
    return;

  debit = (GNUNET_YES ==
           GNUNET_CONFIGURATION_get_value_yesno (lc->cfg,
                                                 section,
                                                 "ENABLE_DEBIT"));
  credit = (GNUNET_YES ==
            GNUNET_CONFIGURATION_get_value_yesno (lc->cfg,
                                                  section,
                                                  "ENABLE_CREDIT"));
  if (! ( ( (debit) &&
            (lc->debit) ) ||
          ( (credit) &&
            (lc->credit) ) ) )
    return; /* not enabled for us, skip */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "PAYTO_URI",
                                             &payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               section,
                               "PAYTO_URI");
    lc->res = GNUNET_SYSERR;
    return;
  }
  method = TALER_payto_get_method (payto_uri);
  GNUNET_free (payto_uri);
  if (NULL == method)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "payto URI in config ([%s]/PAYTO_URI) malformed\n",
                section);
    lc->res = GNUNET_SYSERR;
    return;
  }
  wa = GNUNET_new (struct WireAccount);
  wa->section_name = GNUNET_strdup (section);
  wa->method = method;
  wa->ai.debit_enabled = debit;
  wa->ai.credit_enabled = credit;
  wa->ai.auth = NULL;
  wa->ai.section_name = wa->section_name;
  wa->ai.method = wa->method;
  if (lc->load_auth_data)
  {
    char *csn;

    GNUNET_asprintf (&csn,
                     "exchange-accountcredentials-%s",
                     &section[strlen ("exchange-account-")]);
    if (GNUNET_OK !=
        TALER_BANK_auth_parse_cfg (cfg,
                                   csn,
                                   &wa->auth))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                  "Failed to load exchange account credentials from section `%s'\n",
                  csn);
      GNUNET_free (csn);
      GNUNET_free (wa->section_name);
      GNUNET_free (wa->method);
      GNUNET_free (wa);
      return;
    }
    wa->ai.auth = &wa->auth;
    GNUNET_free (csn);
  }
  GNUNET_CONTAINER_DLL_insert (wa_head,
                               wa_tail,
                               wa);
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGEDB_load_accounts (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  enum TALER_EXCHANGEDB_AccountLoaderOptions options)
{
  struct LoaderContext lc = {
    .cfg = cfg,
    .debit = 0 != (options & TALER_EXCHANGEDB_ALO_DEBIT),
    .credit = 0 != (options & TALER_EXCHANGEDB_ALO_CREDIT),
    .load_auth_data = 0 != (options & TALER_EXCHANGEDB_ALO_AUTHDATA),
  };

  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &add_account_cb,
                                         &lc);
  if (GNUNET_SYSERR == lc.res)
    return GNUNET_SYSERR;
  if (NULL == wa_head)
    return GNUNET_NO;
  return GNUNET_OK;
}


void
TALER_EXCHANGEDB_unload_accounts (void)
{
  struct WireAccount *wa;

  while (NULL != (wa = wa_head))
  {
    GNUNET_CONTAINER_DLL_remove (wa_head,
                                 wa_tail,
                                 wa);
    if (NULL != wa->ai.auth)
      TALER_BANK_auth_free (&wa->auth);
    GNUNET_free (wa->section_name);
    GNUNET_free (wa->method);
    GNUNET_free (wa);
  }
}


/* end of exchangedb_accounts.c */
