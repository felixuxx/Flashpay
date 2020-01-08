/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file wire/wire_helper.c
 * @brief Helper functions for dealing with wire formats
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"

/**
 * Prefix of PAYTO URLs.
 */
#define PAYTO "payto://"


/**
 * Maps wire methods to plugin names.
 */
struct ConversionTable
{

  /**
   * Wire method (e.g. 'iban', 'x-taler-bank', ..)
   */
  const char *method;

  /**
   * Plugin name, e.g. 'taler_bank', ..
   */
  const char *plugin_name;
};

/**
 * Obtain the payment method from a @a payto_url
 *
 * @param payto_url the URL to parse
 * @return NULL on error (malformed @a payto_url)
 */
char *
TALER_WIRE_payto_get_method (const char *payto_url)
{
  const char *start;
  const char *end;

  if (0 != strncmp (payto_url,
                    PAYTO,
                    strlen (PAYTO)))
    return NULL;
  start = &payto_url[strlen (PAYTO)];
  end = strchr (start,
                (unsigned char) '/');
  if (NULL == end)
    return NULL;
  return GNUNET_strndup (start,
                         end - start);
}


/**
 * Get the plugin name from the payment method.
 *
 * FIXME: this is ugly, would be better to have
 * a way to iterate over all plugins and interrogate
 * them as to what wire method(s) they support!
 *
 * @param method the method implemented by the plugin (for
 *  simplicity, we assume 1 method is implemented by 1 plugin).
 * @return the plugin name, NULL if not found.
 */
const char *
TALER_WIRE_get_plugin_from_method (const char *method)
{
  static const struct ConversionTable ct[] = {
    {"x-taler-bank", "taler_bank"},
    {"iban", "taler_bank"},
    {NULL, NULL}
  };

  for (unsigned int i = 0;
       NULL != ct[i].method;
       i++)
  {
    if (0 == strcmp (method,
                     ct[i].method))
      return ct[i].plugin_name;
  }

  return NULL;
}


/* end of wire_helper.c */
