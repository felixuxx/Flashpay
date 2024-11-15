/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
#include <gnunet/gnunet_json_lib.h>

enum GNUNET_GenericReturnValue
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
    /* may be OK! */
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
                               "invalid amount");
    return GNUNET_SYSERR;
  }
  GNUNET_free (str);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_config_get_denom_fees (const struct GNUNET_CONFIGURATION_Handle *cfg,
                             const char *currency,
                             const char *section,
                             struct TALER_DenomFeeSet *fees)
{
  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               section,
                               "FEE_WITHDRAW",
                               &fees->withdraw))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_WITHDRAW",
                               section);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               section,
                               "FEE_DEPOSIT",
                               &fees->deposit))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_DEPOSIT",
                               section);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               section,
                               "FEE_REFRESH",
                               &fees->refresh))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_REFRESH",
                               section);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_config_get_amount (cfg,
                               section,
                               "FEE_REFUND",
                               &fees->refund))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               "Need amount for option `%s' in section `%s'\n",
                               "FEE_REFUND",
                               section);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_denom_fee_check_currency (currency,
                                      fees))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Need fee amounts in section `%s' to use currency `%s'\n",
                section,
                currency);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_config_get_currency (const struct GNUNET_CONFIGURATION_Handle *cfg,
                           const char *section,
                           char **currency)
{
  size_t slen;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             section,
                                             "CURRENCY",
                                             currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "CURRENCY");
    return GNUNET_SYSERR;
  }
  slen = strlen (*currency);
  if (slen >= TALER_CURRENCY_LEN)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Currency `%s' longer than the allowed limit of %u characters.",
                *currency,
                (unsigned int) TALER_CURRENCY_LEN);
    GNUNET_free (*currency);
    *currency = NULL;
    return GNUNET_SYSERR;
  }
  for (size_t i = 0; i<slen; i++)
    if (! isalpha ((unsigned char) (*currency)[i]))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Currency `%s' must only use characters from the A-Z range.",
                  *currency);
      GNUNET_free (*currency);
      *currency = NULL;
      return GNUNET_SYSERR;
    }
  return GNUNET_OK;
}


/**
 * Closure for #parse_currencies_cb().
 */
struct CurrencyParserContext
{
  /**
   * Current offset in @e cspecs.
   */
  unsigned int num_currencies;

  /**
   * Length of the @e cspecs array.
   */
  unsigned int len_cspecs;

  /**
   * Array of currency specifications (see DD 51).
   */
  struct TALER_CurrencySpecification *cspecs;

  /**
   * Configuration we are parsing.
   */
  const struct GNUNET_CONFIGURATION_Handle *cfg;

  /**
   * Set to true if the configuration was malformed.
   */
  bool failure;
};


/**
 * Function to iterate over section.
 *
 * @param cls closure with a `struct CurrencyParserContext *`
 * @param section name of the section
 */
static void
parse_currencies_cb (void *cls,
                     const char *section)
{
  struct CurrencyParserContext *cpc = cls;
  struct TALER_CurrencySpecification *cspec;
  unsigned long long num;
  char *str;

  if (cpc->failure)
    return;
  if (0 != strncasecmp (section,
                        "currency-",
                        strlen ("currency-")))
    return; /* not interesting */
  if (GNUNET_YES !=
      GNUNET_CONFIGURATION_get_value_yesno (cpc->cfg,
                                            section,
                                            "ENABLED"))
    return; /* disabled */
  if (cpc->len_cspecs == cpc->num_currencies)
  {
    GNUNET_array_grow (cpc->cspecs,
                       cpc->len_cspecs,
                       cpc->len_cspecs * 2 + 4);
  }
  cspec = &cpc->cspecs[cpc->num_currencies++];
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cpc->cfg,
                                             section,
                                             "CODE",
                                             &str))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "CODE");
    cpc->failure = true;
    return;
  }
  if (GNUNET_OK !=
      TALER_check_currency (str))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "CODE",
                               "Currency code name given is invalid");
    cpc->failure = true;
    GNUNET_free (str);
    return;
  }
  memset (cspec->currency,
          0,
          sizeof (cspec->currency));
  /* Already checked in TALER_check_currency(), repeated here
     just to make static analysis happy */
  GNUNET_assert (strlen (str) < TALER_CURRENCY_LEN);
  strcpy (cspec->currency,
          str);
  GNUNET_free (str);

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cpc->cfg,
                                             section,
                                             "NAME",
                                             &str))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "NAME");
    cpc->failure = true;
    return;
  }
  cspec->name = str;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cpc->cfg,
                                             section,
                                             "FRACTIONAL_INPUT_DIGITS",
                                             &num))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FRACTIONAL_INPUT_DIGITS");
    cpc->failure = true;
    return;
  }
  if (num > TALER_AMOUNT_FRAC_LEN)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FRACTIONAL_INPUT_DIGITS",
                               "Number given is too big");
    cpc->failure = true;
    return;
  }
  cspec->num_fractional_input_digits = num;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cpc->cfg,
                                             section,
                                             "FRACTIONAL_NORMAL_DIGITS",
                                             &num))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FRACTIONAL_NORMAL_DIGITS");
    cpc->failure = true;
    return;
  }
  if (num > TALER_AMOUNT_FRAC_LEN)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FRACTIONAL_NORMAL_DIGITS",
                               "Number given is too big");
    cpc->failure = true;
    return;
  }
  cspec->num_fractional_normal_digits = num;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cpc->cfg,
                                             section,
                                             "FRACTIONAL_TRAILING_ZERO_DIGITS",
                                             &num))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FRACTIONAL_TRAILING_ZERO_DIGITS");
    cpc->failure = true;
    return;
  }
  if (num > TALER_AMOUNT_FRAC_LEN)
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "FRACTIONAL_TRAILING_ZERO_DIGITS",
                               "Number given is too big");
    cpc->failure = true;
    return;
  }
  cspec->num_fractional_trailing_zero_digits = num;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cpc->cfg,
                                             section,
                                             "ALT_UNIT_NAMES",
                                             &str))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "ALT_UNIT_NAMES");
    cpc->failure = true;
    return;
  }
  {
    json_error_t err;

    cspec->map_alt_unit_names = json_loads (str,
                                            JSON_REJECT_DUPLICATES,
                                            &err);
    GNUNET_free (str);
    if (NULL == cspec->map_alt_unit_names)
    {
      GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                                 section,
                                 "ALT_UNIT_NAMES",
                                 err.text);
      cpc->failure = true;
      return;
    }
  }
  if (GNUNET_OK !=
      TALER_check_currency_scale_map (cspec->map_alt_unit_names))
  {
    GNUNET_log_config_invalid (GNUNET_ERROR_TYPE_ERROR,
                               section,
                               "ALT_UNIT_NAMES",
                               "invalid map entry detected");
    cpc->failure = true;
    json_decref (cspec->map_alt_unit_names);
    cspec->map_alt_unit_names = NULL;
    return;
  }
}


enum GNUNET_GenericReturnValue
TALER_check_currency_scale_map (const json_t *map)
{
  /* validate map only maps from decimal numbers to strings! */
  const char *str;
  const json_t *val;
  bool zf = false;

  if (! json_is_object (map))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Object required for currency scale map\n");
    return GNUNET_SYSERR;
  }
  json_object_foreach ((json_t *) map, str, val)
  {
    int idx;
    char dummy;

    if ( (1 != sscanf (str,
                       "%d%c",
                       &idx,
                       &dummy)) ||
         (idx < -12) ||
         (idx > 24) ||
         (! json_is_string (val) ) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Invalid entry `%s' in currency scale map\n",
                  str);
      return GNUNET_SYSERR;
    }
    if (0 == idx)
      zf = true;
  }
  if (! zf)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Entry for 0 missing in currency scale map\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_CONFIG_parse_currencies (const struct GNUNET_CONFIGURATION_Handle *cfg,
                               const char *main_currency,
                               unsigned int *num_currencies,
                               struct TALER_CurrencySpecification **cspecs)
{
  struct CurrencyParserContext cpc = {
    .cfg = cfg
  };
  static struct TALER_CurrencySpecification defspec = {
    .num_fractional_input_digits = 2,
    .num_fractional_normal_digits = 2,
    .num_fractional_trailing_zero_digits = 2
  };

  GNUNET_CONFIGURATION_iterate_sections (cfg,
                                         &parse_currencies_cb,
                                         &cpc);
  if (cpc.failure)
  {
    GNUNET_array_grow (cpc.cspecs,
                       cpc.len_cspecs,
                       0);
    return GNUNET_SYSERR;
  }
  /* Make sure that there is some sane fallback for the main currency */
  if (NULL != main_currency)
  {
    struct TALER_CurrencySpecification *mspec = NULL;
    for (unsigned int i = 0; i<cpc.num_currencies; i++)
    {
      struct TALER_CurrencySpecification *cspec;

      cspec = &cpc.cspecs[i];
      if (0 == strcmp (main_currency,
                       cspec->currency))
      {
        mspec = cspec;
        break;
      }
    }
    if (NULL == mspec)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Lacking enabled currency specification for main currency %s, using fallback currency specification.\n",
                  main_currency);
      if (cpc.len_cspecs == cpc.num_currencies)
      {
        GNUNET_array_grow (cpc.cspecs,
                           cpc.len_cspecs,
                           cpc.len_cspecs + 1);
      }
      mspec = &cpc.cspecs[cpc.num_currencies++];
      *mspec = defspec;
      GNUNET_assert (strlen (main_currency) < TALER_CURRENCY_LEN);
      strcpy (mspec->currency,
              main_currency);
      mspec->map_alt_unit_names
        = GNUNET_JSON_PACK (
            GNUNET_JSON_pack_string ("0",
                                     main_currency)
            );
      mspec->name = GNUNET_strdup (main_currency);
    }
  }
  /* cspecs might've been overgrown, grow back to minimum size */
  GNUNET_array_grow (cpc.cspecs,
                     cpc.len_cspecs,
                     cpc.num_currencies);
  *num_currencies = cpc.num_currencies;
  *cspecs = cpc.cspecs;
  if (0 == *num_currencies)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "No currency formatting specification found! Please check your installation!\n");
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


json_t *
TALER_CONFIG_currency_specs_to_json (const struct
                                     TALER_CurrencySpecification *cspec)
{
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("name",
                             cspec->name),
    /* 'currency' is deprecated as of exchange v18 and merchant v6;
       remove this line once current-age > 6*/
    GNUNET_JSON_pack_string ("currency",
                             cspec->currency),
    GNUNET_JSON_pack_uint64 ("num_fractional_input_digits",
                             cspec->num_fractional_input_digits),
    GNUNET_JSON_pack_uint64 ("num_fractional_normal_digits",
                             cspec->num_fractional_normal_digits),
    GNUNET_JSON_pack_uint64 ("num_fractional_trailing_zero_digits",
                             cspec->num_fractional_trailing_zero_digits),
    GNUNET_JSON_pack_object_incref ("alt_unit_names",
                                    cspec->map_alt_unit_names));
}


void
TALER_CONFIG_free_currencies (
  unsigned int num_currencies,
  struct TALER_CurrencySpecification cspecs[static num_currencies])
{
  for (unsigned int i = 0; i<num_currencies; i++)
  {
    struct TALER_CurrencySpecification *cspec = &cspecs[i];

    GNUNET_free (cspec->name);
    json_decref (cspec->map_alt_unit_names);
  }
  GNUNET_array_grow (cspecs,
                     num_currencies,
                     0);
}
