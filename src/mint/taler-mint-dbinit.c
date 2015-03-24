/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mint/taler-mint-dbinit.c
 * @brief Create tables for the mint database.
 * @author Florian Dold
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <libpq-fe.h>
#include "taler_util.h"
#include "taler_mintdb_plugin.h"
#include "plugin.h"

/**
 * Mint directory with the keys.
 */
static char *mint_base_dir;

/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Mint's database.
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
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-dbinit OPTIONS"),
    {'d', "mint-dir", "DIR",
     "mint directory", 1,
     &GNUNET_GETOPT_set_filename, &mint_base_dir},
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_GETOPT_run ("taler-mint-dbinit",
                         options,
                         argc, argv) < 0)
    return 1;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-dbinit",
                                   "INFO",
                                   NULL));
  if (NULL == mint_base_dir)
  {
    fprintf (stderr,
             "Mint base directory not given.\n");
    return 1;
  }
  cfg = TALER_config_load (mint_base_dir);
  if (NULL == cfg)
  {
    fprintf (stderr,
             "Failed to load mint configuration.\n");
    return 1;
  }
  if (GNUNET_OK !=
      TALER_MINT_plugin_load (cfg))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    return 1;
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             GNUNET_NO))
  {
    fprintf (stderr,
             "Failed to initialize database.\n");
    TALER_MINT_plugin_unload ();
    return 1;
  }
  TALER_MINT_plugin_unload ();
  return 0;
}

/* end of taler-mint-dbinit.c */
