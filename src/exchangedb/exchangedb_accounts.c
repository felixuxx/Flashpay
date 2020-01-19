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
 * Closure of #check_for_account.
 */
struct FindAccountContext
{
  /**
   * Configuration we are usign.
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
};


/**
 * Check if @a section begins with "exchange-wire-", and if
 * so if the "ENABLE" option is set to "YES".  If both are
 * true, call the callback from the context with the
 * rest of the section name.
 *
 * @param cls our `struct FindEnabledWireContext`
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
  struct TALER_EXCHANGEDB_AccountInfo ai;

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
    return;
  }
  method = TALER_payto_get_method (payto_uri);
  if (NULL == method)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "payto URI in config ([%s]/PAYTO_URI) malformed\n",
                section);
    GNUNET_free (payto_uri);
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (ctx->cfg,
                                               section,
                                               "WIRE_RESPONSE",
                                               &wire_response_filename))
    wire_response_filename = NULL;
  ai.section_name = section;
  ai.method = method;
  ai.payto_uri = payto_uri;
  ai.wire_response_filename = wire_response_filename;

  ai.debit_enabled = (GNUNET_YES ==
                      GNUNET_CONFIGURATION_get_value_yesno (ctx->cfg,
                                                            section,
                                                            "ENABLE_DEBIT"));
  ai.credit_enabled = (GNUNET_YES ==
                       GNUNET_CONFIGURATION_get_value_yesno (ctx->cfg,
                                                             section,
                                                             "ENABLE_CREDIT"));
  ctx->cb (ctx->cb_cls,
           &ai);
  GNUNET_free (payto_uri);
  GNUNET_free (method);
  GNUNET_free_non_null (wire_response_filename);
}


/**
 * Parse the configuration to find account information.
 *
 * @param cfg configuration to use
 * @param cb callback to invoke
 * @param cb_cls closure for @a cb
 */
// FIXME(dold): why is this part of the exchange database?  Does this really belong here?
void
TALER_EXCHANGEDB_find_accounts (const struct GNUNET_CONFIGURATION_Handle *cfg,
                                TALER_EXCHANGEDB_AccountCallback cb,
                                void *cb_cls)
{
  struct FindAccountContext ctx;

  ctx.cfg = cfg;
  ctx.cb = cb;
  ctx.cb_cls = cb_cls;
  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &check_for_account,
                                         &ctx);
}


/* end of exchangedb_accounts.c */
