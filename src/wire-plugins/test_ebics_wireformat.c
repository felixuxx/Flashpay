/*
  This file is part of TALER
  (C) 2015, 2016, 2018 Taler Systems SA

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
 * @file wire/test_ebics_wireformat.c
 * @brief Tests for SEPA format validation by the EBICS plugin
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"


/**
 * Valid SEPA data
 */
static const char *valid_wire_str = "payto://sepa/DE67830654080004822650";

/**
 * IBAN has wrong country code
 */
static const char *invalid_wire_str = "payto://sepa/XX67830654080004822650";

/**
 * IBAN has wrong checksum
 */
static const char *invalid_wire_str2 = "payto://sepa/DE67830654080004822651";

/**
 * Unsupported wireformat type
 */
static const char *unsupported_wire_str = "payto://sega/DE67830654080004822650";


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct TALER_WIRE_Plugin *plugin;

  GNUNET_log_setup ("test-sepa-wireformats",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_CONFIGURATION_set_value_string (cfg,
                                         "taler",
                                         "currency",
                                         "EUR");
  plugin = TALER_WIRE_plugin_load (cfg,
                                   "ebics");
  GNUNET_assert (NULL != plugin);
  GNUNET_assert (TALER_EC_NONE !=
                 plugin->wire_validate (plugin->cls,
                                        unsupported_wire_str));
  GNUNET_assert (TALER_EC_NONE !=
                 plugin->wire_validate (plugin->cls,
                                        invalid_wire_str));
  GNUNET_assert (TALER_EC_NONE !=
                 plugin->wire_validate (plugin->cls,
                                        invalid_wire_str2));
  GNUNET_assert (TALER_EC_NONE ==
                 plugin->wire_validate (plugin->cls,
                                        valid_wire_str));
  TALER_WIRE_plugin_unload (plugin);
  GNUNET_CONFIGURATION_destroy (cfg);
  return 0;
}
