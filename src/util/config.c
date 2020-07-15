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
 * @file config.c
 * @brief configuration parsing functions for Taler-specific data types
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#include "platform.h"
#include "taler_util.h"


/**
 * Obtain denomination amount from configuration file.
 *
 * @param cfg configuration to use
 * @param section section of the configuration to access
 * @param option option of the configuration to access
 * @param[out] denom set to the amount found in configuration
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_config_get_amount (const struct GNUNET_CONFIGURATION_Handle *cfg,
                         const char *section,
                         const char *option,
                         struct TALER_Amount *denom)
{
  char *str;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             option,
                                             &str))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               option);
    return GNUNET_NO;
  }
  if (GNUNET_OK !=
      TALER_string_to_amount (str,
                              denom))
  {
    GNUNET_free (str);
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               option,
                               "valid amount");
    return GNUNET_SYSERR;
  }
  GNUNET_free (str);
  return GNUNET_OK;
}


/**
 * Load our currency from the @a cfg (in section [taler]
 * the option "CURRENCY").
 *
 * @param cfg configuration to use
 * @param[out] currency where to write the result
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
int
TALER_config_get_currency (const struct GNUNET_CONFIGURATION_Handle *cfg,
                           char **currency)
{
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    return GNUNET_SYSERR;
  }
  if (strlen (*currency) >= TALER_CURRENCY_LEN)
  {
    fprintf (stderr,
             "Currency `%s' longer than the allowed limit of %u characters.",
             *currency,
             (unsigned int) TALER_CURRENCY_LEN);
    GNUNET_free (*currency);
    *currency = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}
