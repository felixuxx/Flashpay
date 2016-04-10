/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchange-tools/taler-exchange-dbinit.c
 * @brief Create tables for the exchange database.
 * @author Florian Dold
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_exchangedb_plugin.h"


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  char *cfgfile = NULL;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_CFG_FILE (&cfgfile),
    GNUNET_GETOPT_OPTION_HELP ("Initialize Taler Exchange database"),
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct TALER_EXCHANGEDB_Plugin *plugin;

  if (GNUNET_GETOPT_run ("taler-exchange-dbinit",
                         options,
                         argc, argv) < 0)
    return 1;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-dbinit",
                                   "INFO",
                                   NULL));
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR == GNUNET_CONFIGURATION_load (cfg,
                                                  cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _("Malformed configuration file `%s', exit ...\n"),
                cfgfile);
    GNUNET_free_non_null (cfgfile);
    return 1;
  }
  GNUNET_free_non_null (cfgfile);
  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    GNUNET_CONFIGURATION_destroy (cfg);
    return 1;
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             GNUNET_NO))
  {
    fprintf (stderr,
             "Failed to initialize database.\n");
    TALER_EXCHANGEDB_plugin_unload (plugin);
    GNUNET_CONFIGURATION_destroy (cfg);
    return 1;
  }
  TALER_EXCHANGEDB_plugin_unload (plugin);
  GNUNET_CONFIGURATION_destroy (cfg);
  return 0;
}

/* end of taler-exchange-dbinit.c */
