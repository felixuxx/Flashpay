/*
  This file is part of TALER
  (C) 2016 GNUnet e.V.

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
 * @file exchange/test_taler_exchange_aggregator.c
 * @brief Tests for taler-exchange-aggregator logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_exchangedb_plugin.h"

/**
 * Return value from main().
 */
static int result;

/**
 * Name of the configuration file to use.
 */
static char *config_filename;


/**
 * Runs the aggregator process.
 */
static void
run_aggregator ()
{
  struct GNUNET_OS_Process *proc;

  proc = GNUNET_OS_start_process (GNUNET_NO,
                                  GNUNET_OS_INHERIT_STD_ALL,
                                  NULL, NULL, NULL,
                                  "taler-exchange-aggregator",
                                  "taler-exchange-aggregator",
                                  /* "-c", config_filename, */
                                  "-d", "test-exchange-home",
                                  "-t", /* enable temporary tables */
                                  NULL);
  GNUNET_OS_process_wait (proc);
  GNUNET_OS_process_destroy (proc);
}


/**
 * Main function that will be run by the scheduler.
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
  struct TALER_EXCHANGEDB_Plugin *plugin;
  struct TALER_EXCHANGEDB_Session *session;

  plugin = TALER_EXCHANGEDB_plugin_load (cfg);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             GNUNET_YES))
  {
    TALER_EXCHANGEDB_plugin_unload (plugin);
    result = 77;
    return;
  }
  session = plugin->get_session (plugin->cls,
                                 GNUNET_YES);
  /* FIXME: prime DB */
  /* FIXME: launch bank on 8082! */
  run_aggregator ();
  /* FIXME: check DB and bank */

  plugin->drop_temporary (plugin->cls,
                          session);
  TALER_EXCHANGEDB_plugin_unload (plugin);
  result = 77; /* skip: not finished */
}


int
main (int argc,
      char *const argv[])
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };
  char *argv2[] = {
    "test-taler-exchange-aggregator-<plugin_name>", /* will be replaced later */
    "-c", "test-taler-exchange-aggregator-<plugin_name>.conf", /* will be replaced later */
    NULL,
  };
  const char *plugin_name;
  char *testname;

  result = -1;
  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-taler-exchange-aggregator-%s", plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf", testname);
  argv2[0] = argv[0];
  argv2[2] = config_filename;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run ((sizeof (argv2)/sizeof (char *)) - 1, argv2,
                          testname,
                          "Test cases for exchange aggregator.",
                          options, &run, NULL))
  {
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 3;
  }
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}

/* end of test_taler_exchange_aggregator.c */
