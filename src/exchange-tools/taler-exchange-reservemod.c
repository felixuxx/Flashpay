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
 * @file taler-exchange-reservemod.c
 * @brief Modify reserves.  Allows manipulation of reserve balances.
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <libpq-fe.h>
#include <jansson.h>
#include "taler_exchangedb_plugin.h"

/**
 * Director of the exchange, containing the keys.
 */
static char *exchange_directory;

/**
 * Our DB plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;

/**
 * Public key of the reserve as a string.
 */
static char *reserve_pub_str;

/**
 * Amount to add as a string.
 */
static char *add_str;

/**
 * Details about the wire transfer in JSON format.
 */
static char *details;

/**
 * Return value from main().
 */
static int global_ret;


/**
 * Run the database transaction.
 *
 * @param reserve_pub public key of the reserve to use
 * @param add_value value to add
 * @param jdetails JSON details
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on hard error,
 *         #GNUNET_NO if record exists
 */
static int
run_transaction (const struct TALER_ReservePublicKeyP *reserve_pub,
                 const struct TALER_Amount *add_value,
                 json_t *jdetails)
{
  int ret;
  struct TALER_EXCHANGEDB_Session *session;

  session = plugin->get_session (plugin->cls);
  if (NULL == session)
  {
    fprintf (stderr,
             "Failed to initialize DB session\n");
    return GNUNET_SYSERR;
  }
  /* FIXME: maybe allow passing timestamp via command-line? */
  ret = plugin->reserves_in_insert (plugin->cls,
                                    session,
                                    reserve_pub,
                                    add_value,
                                    GNUNET_TIME_absolute_get (),
                                    jdetails);
  if (GNUNET_SYSERR == ret)
  {
    fprintf (stderr,
             "Failed to update reserve.\n");
  }
  if (GNUNET_NO == ret)
  {
    fprintf (stderr,
             "Record exists, reserve not updated.\n");
  }
  return ret;
}


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
  struct TALER_Amount add_value;
  json_t *jdetails;
  json_error_t error;
  struct TALER_ReservePublicKeyP reserve_pub;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchange",
                                               "KEYDIR",
                                               &exchange_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    global_ret = 1;
    return;
  }
  if ((NULL == reserve_pub_str) ||
      (GNUNET_OK !=
       GNUNET_STRINGS_string_to_data (reserve_pub_str,
                                      strlen (reserve_pub_str),
                                      &reserve_pub,
                                      sizeof (struct TALER_ReservePublicKeyP))))
  {
    fprintf (stderr,
             "Parsing reserve key invalid\n");
    global_ret = 1;
    return;
  }
  if ( (NULL == add_str) ||
       (GNUNET_OK !=
        TALER_string_to_amount (add_str,
                                &add_value)) )
  {
    fprintf (stderr,
             "Failed to parse currency amount `%s'\n",
             add_str);
    global_ret = 1;
    return;
  }
  if (NULL == details)
  {
    fprintf (stderr,
             "No wiring details given (justification required)\n");
    global_ret = 1;
    return;
  }
  jdetails = json_loads (details,
                         JSON_REJECT_DUPLICATES,
                         &error);
  if (NULL == jdetails)
  {
    fprintf (stderr,
             "Failed to parse JSON transaction details `%s': %s (%s)\n",
             details,
             error.text,
             error.source);
    global_ret = 1;
    return;
  }

  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    global_ret = 1;
    return;
  }
  if (GNUNET_SYSERR ==
      run_transaction (&reserve_pub,
                       &add_value,
                       jdetails))
    global_ret = 1;
  TALER_EXCHANGEDB_plugin_unload (plugin);
  json_decref (jdetails);
}


/**
 * The main function of the reservemod tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc, char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'a', "add", "DENOM",
     "value to add", 1,
     &GNUNET_GETOPT_set_string, &add_str},
    {'d', "details", "JSON",
     "details about the bank transaction which justify why we add this amount", 1,
     &GNUNET_GETOPT_set_string, &details},
    GNUNET_GETOPT_OPTION_HELP ("Deposit funds into a Taler reserve"),
    {'R', "reserve", "KEY",
     "reserve (public key) to modify", 1,
     &GNUNET_GETOPT_set_string, &reserve_pub_str},
    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-reservemod",
                                   "WARNING",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-reservemod",
			  "Deposit funds into a Taler reserve",
			  options,
			  &run, NULL))
    return 1;
  return global_ret;
}

/* end taler-exchange-reservemod.c */
