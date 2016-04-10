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
 * Handle to the exchange's configuration
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;


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
  char *cfgfile = NULL;
  char *reserve_pub_str = NULL;
  char *add_str = NULL;
  struct TALER_Amount add_value;
  char *details = NULL;
  json_t *jdetails;
  json_error_t error;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_EXCHANGEDB_Session *session;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'a', "add", "DENOM",
     "value to add", 1,
     &GNUNET_GETOPT_set_string, &add_str},
    GNUNET_GETOPT_OPTION_CFG_FILE (&cfgfile),
    {'d', "details", "JSON",
     "details about the bank transaction which justify why we add this amount", 1,
     &GNUNET_GETOPT_set_string, &details},
    GNUNET_GETOPT_OPTION_HELP ("Deposit funds into a Taler reserve"),
    {'R', "reserve", "KEY",
     "reserve (public key) to modify", 1,
     &GNUNET_GETOPT_set_string, &reserve_pub_str},
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-reservemod",
                                   "WARNING",
                                   NULL));

  if (GNUNET_GETOPT_run ("taler-exchange-reservemod",
                         options,
                         argc, argv) < 0)
    return 1;
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR == GNUNET_CONFIGURATION_load (cfg,
                                                  cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _("Malformed configuration file `%s', exit ...\n"),
                cfgfile);
    GNUNET_free_non_null (cfgfile);
    GNUNET_free_non_null (add_str);
    GNUNET_free_non_null (details);
    GNUNET_free_non_null (reserve_pub_str);
    return 1;
  }
  GNUNET_free_non_null (cfgfile);
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (cfg,
                                               "exchange",
                                               "KEYDIR",
                                               &exchange_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    GNUNET_free_non_null (add_str);
    GNUNET_free_non_null (details);
    GNUNET_free_non_null (reserve_pub_str);
    return 1;
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
    GNUNET_free_non_null (add_str);
    GNUNET_free_non_null (details);
    GNUNET_free_non_null (reserve_pub_str);
    return 1;
  }
  if ( (NULL == add_str) ||
       (GNUNET_OK !=
        TALER_string_to_amount (add_str,
                                &add_value)) )
  {
    fprintf (stderr,
             "Failed to parse currency amount `%s'\n",
             add_str);
    GNUNET_free_non_null (add_str);
    GNUNET_free_non_null (details);
    GNUNET_free_non_null (reserve_pub_str);
    return 1;
  }

  if (NULL == details)
  {
    fprintf (stderr,
             "No wiring details given (justification required)\n");
   GNUNET_free_non_null (add_str);
   GNUNET_free_non_null (reserve_pub_str);
   return 1;
  }

  ret = 1;
  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize database plugin.\n");
    goto cleanup;
  }

  session = plugin->get_session (plugin->cls,
                                 GNUNET_NO);
  if (NULL == session)
  {
    fprintf (stderr,
             "Failed to initialize DB session\n");
    goto cleanup;
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
    goto cleanup;
  }
  /* FIXME: maybe allow passing timestamp via command-line? */
  ret = plugin->reserves_in_insert (plugin->cls,
				    session,
				    &reserve_pub,
				    &add_value,
                                    GNUNET_TIME_absolute_get (),
				    jdetails);
  json_decref (jdetails);
  if (GNUNET_SYSERR == ret)
  {
    fprintf (stderr,
             "Failed to update reserve.\n");
    goto cleanup;
  }
  if (GNUNET_NO == ret)
  {
    fprintf (stderr,
             "Record exists, reserve not updated.\n");
  }
  ret = 0;
 cleanup:
  if (NULL != plugin)
    TALER_EXCHANGEDB_plugin_unload (plugin);
  if (NULL != cfg)
    GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free_non_null (add_str);
  GNUNET_free_non_null (details);
  GNUNET_free_non_null (reserve_pub_str);
  return ret;
}

/* end taler-exchange-reservemod.c */
