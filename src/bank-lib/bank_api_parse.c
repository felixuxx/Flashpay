/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/bank_api_parse.c
 * @brief Convenience function to parse authentication configuration
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_bank_service.h"


/**
 * Convenience method for parsing configuration section with bank account data.
 *
 * @param cfg configuration to parse
 * @param section the section with the configuration data
 * @param acc[out] set to the account details
 * @return #GNUNET_OK on success
 */
int
TALER_BANK_account_parse_cfg (const struct GNUNET_CONFIGURATION_Handle *cfg,
                              const char *section,
                              struct TALER_Account *acc)
{
  char *account_url;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "URL",
                                             &account_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "URL");
    return GNUNET_SYSERR;
  }
  if (TALER_EC_NONE !=
      TALER_BANK_payto_to_account (account_url,
                                   acc))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "URL",
                               "Malformed payto:// URL for x-taler-bank method");
    GNUNET_free (account_url);
    return GNUNET_SYSERR;
  }
  if (TALER_PAC_X_TALER_BANK != acc->type)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "URL",
                               "Malformed payto:// URL for x-taler-bank method");
    GNUNET_free (account_url);
    TALER_BANK_account_free (acc);
    return GNUNET_SYSERR;
  }
  GNUNET_free (account_url);
  return GNUNET_OK;
}


/**
 * Parse configuration section with bank authentication data.
 *
 * @param cfg configuration to parse
 * @param section the section with the configuration data
 * @param auth[out] set to the configuration data found
 * @return #GNUNET_OK on success
 */
int
TALER_BANK_auth_parse_cfg (const struct GNUNET_CONFIGURATION_Handle *cfg,
                           const char *section,
                           struct TALER_BANK_AuthenticationData *auth)
{
  const struct
  {
    const char *m;
    enum TALER_BANK_AuthenticationMethod e;
  } methods[] = {
    { "NONE",  TALER_BANK_AUTH_NONE  },
    { "BASIC", TALER_BANK_AUTH_BASIC },
    { NULL, TALER_BANK_AUTH_NONE     }
  };
  char *method;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "WIRE_GATEWAY_URL",
                                             &auth->wire_gateway_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "WIRE_GATEWAY_URL");
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "WIRE_GATEWAY_AUTH_METHOD",
                                             &method))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "WIRE_GATEWAY_AUTH_METHOD");
    GNUNET_free (auth->wire_gateway_url);
    return GNUNET_SYSERR;
  }
  for (unsigned int i = 0; NULL != methods[i].m; i++)
  {
    if (0 == strcasecmp (method,
                         methods[i].m))
    {
      switch (methods[i].e)
      {
      case TALER_BANK_AUTH_NONE:
        auth->method = TALER_BANK_AUTH_NONE;
        GNUNET_free (method);
        return GNUNET_OK;
      case TALER_BANK_AUTH_BASIC:
        if (GNUNET_OK !=
            GNUNET_CONFIGURATION_get_value_string (cfg,
                                                   section,
                                                   "USERNAME",
                                                   &auth->details.basic.username))
        {
          GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                     section,
                                     "USERNAME");
          GNUNET_free (method);
          GNUNET_free (auth->wire_gateway_url);
          return GNUNET_SYSERR;
        }
        if (GNUNET_OK !=
            GNUNET_CONFIGURATION_get_value_string (cfg,
                                                   section,
                                                   "PASSWORD",
                                                   &auth->details.basic.password))
        {
          GNUNET_free (auth->details.basic.username);
          auth->details.basic.username = NULL;
          GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                     section,
                                     "PASSWORD");
          GNUNET_free (method);
          GNUNET_free (auth->wire_gateway_url);
          return GNUNET_SYSERR;
        }
        auth->method = TALER_BANK_AUTH_BASIC;
        GNUNET_free (method);
        return GNUNET_OK;
      }
    }
  }
  GNUNET_free (method);
  return GNUNET_SYSERR;
}


/**
 * Free memory inside of @a auth (but not auth itself).
 * Dual to #TALER_BANK_auth_parse_cfg().
 *
 * @param auth authentication data to free
 */
void
TALER_BANK_auth_free (struct TALER_BANK_AuthenticationData *auth)
{
  switch (auth->method)
  {
  case TALER_BANK_AUTH_NONE:
    break;
  case TALER_BANK_AUTH_BASIC:
    if (NULL != auth->details.basic.username)
    {
      GNUNET_free (auth->details.basic.username);
      auth->details.basic.username = NULL;
    }
    if (NULL != auth->details.basic.password)
    {
      GNUNET_free (auth->details.basic.password);
      auth->details.basic.password = NULL;
    }
    break;
  }
  GNUNET_free (auth->wire_gateway_url);
}


/* end of bank_api_parse.c */
