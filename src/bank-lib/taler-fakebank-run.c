/*
  This file is part of TALER
  Copyright (C) 2016, 2017 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file bank-lib/taler-fakebank-run.c
 * @brief Launch the fakebank, for testing the fakebank itself.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */

#include "platform.h"
#include "taler_fakebank_lib.h"

/**
 * Number of threads to use (-n)
 */
static unsigned int num_threads;

/**
 * Force connection close after each request (-C)
 */
static int connection_close;

/**
 * Global return value.
 */
static int ret;


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
  unsigned long long port = 8082;
  unsigned long long ram = 1024 * 1024 * 128; /* 128 M entries */
  char *currency_string;

  (void) cls;
  (void) args;
  (void) cfgfile;
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency_string))
  {
    ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "bank",
                                             "HTTP_PORT",
                                             &port))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Listening on default port %llu\n",
                port);
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_number (cfg,
                                             "bank",
                                             "RAM_LIMIT",
                                             &ram))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Maximum transaction history in RAM set to default of %llu\n",
                ram);
  }
  if (NULL ==
      TALER_FAKEBANK_start2 ((uint16_t) port,
                             currency_string,
                             ram,
                             num_threads,
                             (0 != connection_close) ))
    ret = 1;
  GNUNET_free (currency_string);
  ret = 0;
}


/**
 * The main function.
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
    GNUNET_GETOPT_option_flag ('C',
                               "connection-close",
                               "force HTTP connections to be closed after each request",
                               &connection_close),
    GNUNET_GETOPT_option_uint ('n',
                               "num-threads",
                               "NUM_THREADS",
                               "size of the thread pool",
                               &num_threads),
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-fakebank-run",
                          "Runs the fakebank",
                          options,
                          &run,
                          NULL))
    return 1;
  return ret;
}
