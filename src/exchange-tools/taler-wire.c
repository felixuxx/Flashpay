/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-wire.c
 * @brief Utility performing wire transfers.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */

#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include <taler/taler_util.h>

/**
 * Plugin name specified by the user.
 */
char *plugin;

/**
 * Global return code.
 */
unsigned int global_ret;


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used
 *        (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  if (NULL == plugin)
  {
    global_ret = 1;
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "The PLUGIN command line option is mandatory.\n");
    return;
  }
}

/**
 * Main function of taler-wire.  This tool is used to command the
 * execution of wire transfers from the command line.  Its main
 * purpose is to test whether the bank and exchange can speak the
 * same protocol of a certain wire plugin.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {

    GNUNET_GETOPT_option_string ('p',
                                 "plugin",
                                 "PLUGIN",
                                 "Wire plugin to use",
                                 &plugin),

    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert
    (GNUNET_OK == GNUNET_log_setup ("taler-wire",
                                    NULL,
                                    NULL)); /* filename */

  if (GNUNET_OK != GNUNET_PROGRAM_run
      (argc,
       argv,
       "taler-wire",
       "Perform wire transfers using plugin PLUGIN",
       options,
       &run,
       NULL))
    return 1;

  return global_ret;
}
