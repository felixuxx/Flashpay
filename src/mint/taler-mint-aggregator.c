/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-mint-aggregator.c
 * @brief Process that aggregates outgoing transactions and executes them
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <pthread.h>
#include "taler_wire_plugin.h"

/**
 * Which currency is used by this mint?
 */
static char *mint_currency_string;

/**
 * Base directory of the mint (global)
 */
static char *mint_directory;

/**
 * The mint's configuration (global)
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_MINTDB_Plugin *db_plugin;


/**
 * Load configuration parameters for the mint
 * server into the corresponding global variables.
 *
 * @param mint_directory the mint's directory
 * @return #GNUNET_OK on success
 */
static int
mint_serve_process_config (const char *mint_directory)
{
  unsigned long long port;

  cfg = TALER_config_load (mint_directory);
  if (NULL == cfg)
  {
    fprintf (stderr,
             "Failed to load mint configuration\n");
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint",
                                             "currency",
                                             &mint_currency_string))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "mint",
                               "currency");
    return GNUNET_SYSERR;
  }
  if (strlen (mint_currency_string) >= TALER_CURRENCY_LEN)
  {
    fprintf (stderr,
             "Currency `%s' longer than the allowed limit of %u characters.",
             mint_currency_string,
             (unsigned int) TALER_CURRENCY_LEN);
    return GNUNET_SYSERR;
  }

  if (NULL ==
      (db_plugin = TALER_MINTDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize DB subsystem\n");
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * The main function of the taler-mint-httpd server ("the mint").
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'d', "mint-dir", "DIR",
     "mint directory with configuration and keys for operating the mint", 1,
     &GNUNET_GETOPT_set_filename, &mint_directory},
    TALER_GETOPT_OPTION_HELP ("background process that aggregates and executes wire transfers to merchants"),
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-aggregator",
                                   "INFO",
                                   NULL));
  if (0 >=
      GNUNET_GETOPT_run ("taler-mint-aggregator",
                         options,
                         argc, argv))
    return 1;
  if (NULL == mint_directory)
  {
    fprintf (stderr,
             "Mint directory not specified\n");
    return 1;
  }

  if (GNUNET_OK !=
      mint_serve_process_config (mint_directory))
    return 1;



  TALER_MINTDB_plugin_unload (db_plugin);
  return (GNUNET_SYSERR == ret) ? 1 : 0;
}

/* end of taler-mint-aggregator.c */
