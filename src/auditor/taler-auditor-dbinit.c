/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2020 Taler Systems SA

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
 * @file auditor/taler-auditor-dbinit.c
 * @brief Create tables for the auditor database.
 * @author Florian Dold
 * @author Marcello Stanisci
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"


/**
 * Return value from main().
 */
static int global_ret;

/**
 * -r option: do restart audits
 */
static int restart_db;

/**
 * -R option: do full DB reset
 */
static int reset_db;

/**
 * -g option: garbage collect DB reset
 */
static int gc_db;


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct TALER_AUDITORDB_Plugin *plugin;

  (void) cls;
  (void) args;
  (void) cfgfile;
  if (NULL ==
      (plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    global_ret = 1;
    return;
  }
  if (reset_db)
  {
    if (GNUNET_OK !=
        plugin->drop_tables (plugin->cls,
                             GNUNET_YES))
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to reset database\n");
  }
  else if (restart_db)
  {
    if (GNUNET_OK !=
        plugin->drop_tables (plugin->cls,
                             GNUNET_NO))
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to restart audits\n");
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls))
  {
    fprintf (stderr,
             "Failed to initialize database.\n");
    TALER_AUDITORDB_plugin_unload (plugin);
    global_ret = 1;
    return;
  }
  if (gc_db)
  {
    if (GNUNET_SYSERR == plugin->gc (plugin->cls))
      fprintf (stderr,
               "Garbage collection failed!\n");
  }
  TALER_AUDITORDB_plugin_unload (plugin);
}


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler auditor's database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_flag ('r',
                               "restart",
                               "restart audits (DANGEROUS: all audits resume from scratch)",
                               &restart_db),
    GNUNET_GETOPT_option_flag ('R',
                               "reset",
                               "reset database (DANGEROUS: all existing data is lost!)",
                               &reset_db),
    GNUNET_GETOPT_option_flag ('g',
                               "gc",
                               "garbage collect database",
                               &gc_db),
    GNUNET_GETOPT_OPTION_END
  };
  enum GNUNET_GenericReturnValue ret;

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  if (GNUNET_OK !=
      GNUNET_STRINGS_get_utf8_args (argc, argv,
                                    &argc, &argv))
    return 4;
  ret = GNUNET_PROGRAM_run (
    argc, argv,
    "taler-auditor-dbinit",
    gettext_noop ("Initialize Taler auditor database"),
    options,
    &run, NULL);
  GNUNET_free_nz ((void *) argv);
  if (GNUNET_SYSERR == ret)
    return 3;
  if (GNUNET_NO == ret)
    return 0;
  return global_ret;
}


/* end of taler-auditor-dbinit.c */
