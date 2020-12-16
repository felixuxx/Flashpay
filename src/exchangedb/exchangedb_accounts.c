/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * Head of list of wire accounts of the exchange.
 */
static struct TALER_EXCHANGEDB_WireAccount *wa_head;

/**
 * Tail of list of wire accounts of the exchange.
 */
static struct TALER_EXCHANGEDB_WireAccount *wa_tail;


/**
 * Closure of #check_for_account.
 */
struct FindAccountContext
{
  /**
   * Configuration we are using.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Callback to invoke.
   */
  TALER_EXCHANGEDB_AccountCallback cb;

  /**
   * Closure for @e cb.
   */
  void *cb_cls;

  /**
   * Set to #GNUNET_SYSERR if the configuration is invalid.
   */
  int res;
};


/**
 * Check if @a section begins with "exchange-account-", and if so if the
 * "PAYTO_URI" is given. If not, a warning is printed, otherwise we also check
 * if "ENABLE_CREDIT" or "ENABLE_DEBIT" options are set to "YES" and then call
 * the callback in @a cls with all of the information gathered.
 *
 * @param cls our `struct FindAccountContext`
 * @param section name of a section in the configuration
 */
static void
check_for_account (void *cls,
                   const char *section)
{
  struct FindAccountContext *ctx = cls;
  char *method;
  char *payto_uri;
  char *wire_response_filename;

  if (0 != strncasecmp (section,
                        "exchange-account-",
                        strlen ("exchange-account-")))
    return;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (ctx->cfg,
                                             section,
                                             "PAYTO_URI",
                                             &payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_WARNING,
                               section,
                               "PAYTO_URI");
    ctx->res = GNUNET_SYSERR;
    return;
  }
  method = TALER_payto_get_method (payto_uri);
  if (NULL == method)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "payto URI in config ([%s]/PAYTO_URI) malformed\n",
                section);
    ctx->res = GNUNET_SYSERR;
    GNUNET_free (payto_uri);
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (ctx->cfg,
                                               section,
                                               "WIRE_RESPONSE",
                                               &wire_response_filename))
    wire_response_filename = NULL;
  {
    struct TALER_EXCHANGEDB_AccountInfo ai = {
      .section_name = section,
      .method = method,
      .payto_uri = payto_uri,
      .wire_response_filename = wire_response_filename,
      .debit_enabled = (GNUNET_YES ==
                        GNUNET_CONFIGURATION_get_value_yesno (
                          ctx->cfg,
                          section,
                          "ENABLE_DEBIT")),
      .credit_enabled = (GNUNET_YES ==
                         GNUNET_CONFIGURATION_get_value_yesno (ctx->cfg,
                                                               section,
                                                               "ENABLE_CREDIT"))
    };

    ctx->cb (ctx->cb_cls,
             &ai);
  }
  GNUNET_free (payto_uri);
  GNUNET_free (method);
  GNUNET_free (wire_response_filename);
}


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
                                void *cb_cls)
{
  struct FindAccountContext ctx = {
    .cfg = cfg,
    .cb = cb,
    .cb_cls = cb_cls,
    .res = GNUNET_OK
  };

  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &check_for_account,
                                         &ctx);
  return ctx.res;
}


/**
 * Find the wire plugin for the given payto:// URL
 *
 * @param method wire method we need an account for
 * @return NULL on error
 */
struct TALER_EXCHANGEDB_WireAccount *
TALER_EXCHANGEDB_find_account_by_method (const char *method)
{
  for (struct TALER_EXCHANGEDB_WireAccount *wa = wa_head; NULL != wa; wa =
         wa->next)
    if (0 == strcmp (method,
                     wa->method))
      return wa;
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "No wire account known for method `%s'\n",
              method);
  return NULL;
}


/**
 * Find the wire plugin for the given payto:// URL
 *
 * @param url wire address we need an account for
 * @return NULL on error
 */
struct TALER_EXCHANGEDB_WireAccount *
TALER_EXCHANGEDB_find_account_by_payto_uri (const char *url)
{
  char *method;
  struct TALER_EXCHANGEDB_WireAccount *wa;

  method = TALER_payto_get_method (url);
  if (NULL == method)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid payto:// URL `%s'\n",
                url);
    return NULL;
  }
  wa = TALER_EXCHANGEDB_find_account_by_method (method);
  GNUNET_free (method);
  return wa;
}


/**
 * Function called with information about a wire account.  Adds
 * the account to our list.
 *
 * @param cls closure, a `struct GNUNET_CONFIGURATION_Handle`
 * @param ai account information
 */
static void
add_account_cb (void *cls,
                const struct TALER_EXCHANGEDB_AccountInfo *ai)
{
  const struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_EXCHANGEDB_WireAccount *wa;
  char *payto_uri;

  (void) cls;
  if (GNUNET_YES != ai->debit_enabled)
    return; /* not enabled for us, skip */
  wa = GNUNET_new (struct TALER_EXCHANGEDB_WireAccount);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             ai->section_name,
                                             "PAYTO_URI",
                                             &payto_uri))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               ai->section_name,
                               "PAYTO_URI");
    GNUNET_free (wa);
    return;
  }
  wa->method = TALER_payto_get_method (payto_uri);
  if (NULL == wa->method)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               ai->section_name,
                               "PAYTO_URI",
                               "could not obtain wire method from URI");
    GNUNET_free (wa);
    return;
  }
  GNUNET_free (payto_uri);
  if (GNUNET_OK !=
      TALER_BANK_auth_parse_cfg (cfg,
                                 ai->section_name,
                                 &wa->auth))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                "Failed to load exchange account `%s'\n",
                ai->section_name);
    GNUNET_free (wa->method);
    GNUNET_free (wa);
    return;
  }
  wa->section_name = GNUNET_strdup (ai->section_name);
  GNUNET_CONTAINER_DLL_insert (wa_head,
                               wa_tail,
                               wa);
}


/**
 * Load account information opf the exchange from
 * @a cfg.
 *
 * @param cfg configuration to load from
 * @return #GNUNET_OK on success, #GNUNET_NO if no accounts are configured
 */
int
TALER_EXCHANGEDB_load_accounts (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  TALER_EXCHANGEDB_find_accounts (cfg,
                                  &add_account_cb,
                                  (void *) cfg);
  if (NULL == wa_head)
    return GNUNET_NO;
  return GNUNET_OK;
}


/**
 * Free resources allocated by
 * #TALER_EXCHANGEDB_load_accounts().
 */
void
TALER_EXCHANGEDB_unload_accounts (void)
{
  struct TALER_EXCHANGEDB_WireAccount *wa;

  while (NULL != (wa = wa_head))
  {
    GNUNET_CONTAINER_DLL_remove (wa_head,
                                 wa_tail,
                                 wa);
    TALER_BANK_auth_free (&wa->auth);
    GNUNET_free (wa->section_name);
    GNUNET_free (wa->method);
    GNUNET_free (wa);
  }
}


/* end of exchangedb_accounts.c */
