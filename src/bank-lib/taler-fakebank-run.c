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
#include "taler_mhd_lib.h"

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
 * Handle for the service.
 */
static struct TALER_FAKEBANK_Handle *fb;

/**
 * Keepalive task in multi-threaded mode.
 */
static struct GNUNET_SCHEDULER_Task *keepalive;


/**
 * Stop the process.
 *
 * @param cls NULL
 */
static void
do_shutdown (void *cls)
{
  (void) cls;
  TALER_FAKEBANK_stop (fb);
  fb = NULL;
  if (NULL != keepalive)
  {
    GNUNET_SCHEDULER_cancel (keepalive);
    keepalive = NULL;
  }
}


/**
 * Task that should never be run.
 *
 * @param cls NULL
 */
static void
keepalive_task (void *cls)
{
  (void) cls;
  GNUNET_assert (0);
}


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
  unsigned long long ram = 1024 * 128; /* 128 k entries */
  char *currency_string;

  (void) cls;
  (void) args;
  (void) cfgfile;
  if (GNUNET_OK !=
      TALER_config_get_currency (cfg,
                                 &currency_string))
  {
    ret = EXIT_NOTCONFIGURED;
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
  {
    enum TALER_MHD_GlobalOptions go;

    go = TALER_MHD_GO_NONE;
    if (0 != connection_close)
      go |= TALER_MHD_GO_FORCE_CONNECTION_CLOSE;
    TALER_MHD_setup (go);
  }
  fb = TALER_FAKEBANK_start2 ((uint16_t) port,
                              currency_string,
                              ram,
                              num_threads);
  if (NULL == fb)
  {
    GNUNET_break (0);
    ret = EXIT_FAILURE;
    return;
  }
  GNUNET_free (currency_string);
  keepalive = GNUNET_SCHEDULER_add_delayed (GNUNET_TIME_UNIT_FOREVER_REL,
                                            &keepalive_task,
                                            NULL);
  GNUNET_SCHEDULER_add_shutdown (&do_shutdown,
                                 NULL);
  ret = EXIT_SUCCESS;
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
    return EXIT_INVALIDARGUMENT;
  return ret;
}
