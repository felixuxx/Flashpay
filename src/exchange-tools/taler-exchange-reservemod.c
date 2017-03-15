/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V.

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
 * @file taler-exchange-reservemod.c
 * @brief Modify reserves.  Allows manipulation of reserve balances.
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
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
 * Public key of the reserve.
 */
static struct TALER_ReservePublicKeyP reserve_pub;

/**
 * Amount to add.  Invalid if not initialized.
 */
static struct TALER_Amount add_value;

/**
 * Details about the sender account in JSON format.
 */
static json_t *sender_details;

/**
 * Details about the wire transfer in JSON format.
 */
static json_t *transfer_details;

/**
 * Return value from main().
 */
static int global_ret;


/**
 * Run the database transaction.
 *
 * @param reserve_pub public key of the reserve to use
 * @param add_value value to add
 * @param jdetails JSON details about sender
 * @param tdetails JSON details about transfer
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on hard error,
 *         #GNUNET_NO if record exists
 */
static int
run_transaction (const struct TALER_ReservePublicKeyP *reserve_pub,
                 const struct TALER_Amount *add_value,
                 json_t *jdetails,
                 json_t *tdetails)
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
                                    jdetails,
                                    tdetails);
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
                       sender_details,
                       transfer_details))
    global_ret = 1;
  TALER_EXCHANGEDB_plugin_unload (plugin);
  json_decref (transfer_details);
  json_decref (sender_details);
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
    GNUNET_GETOPT_OPTION_MANDATORY
    (TALER_getopt_get_amount ('a',
                              "add",
                              "DENOM",
                              "value to add",
                              &add_value)),
    GNUNET_GETOPT_OPTION_MANDATORY
    (GNUNET_JSON_getopt ('s',
                         "sender",
                         "JSON",
                         "details about the sender's bank account",
                         &sender_details)),
    GNUNET_GETOPT_OPTION_MANDATORY
    (GNUNET_JSON_getopt ('t',
                         "transfer",
                         "JSON",
                         "details that uniquely identify the bank transfer",
                         &transfer_details)),
    GNUNET_GETOPT_OPTION_HELP ("Deposit funds into a Taler reserve"),
    GNUNET_GETOPT_OPTION_MANDATORY
    (GNUNET_GETOPT_OPTION_SET_BASE32_AUTO ('R',
                                          "reserve",
                                          "KEY",
                                          "reserve (public key) to modify",
                                           &reserve_pub)),
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
