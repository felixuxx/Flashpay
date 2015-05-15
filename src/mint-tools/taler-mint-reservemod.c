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
 * @file taler-mint-reservemod.c
 * @brief Modify reserves.  Allows manipulation of reserve balances.
 * @author Florian Dold
 * @author Benedikt Mueller
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <libpq-fe.h>
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_pq_lib.h"
#include "taler_mintdb_plugin.h"
#include "taler_mintdb_lib.h"

/**
 * After what time to inactive reserves expire?
 */
#define RESERVE_EXPIRATION GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_YEARS, 5)

/**
 * Director of the mint, containing the keys.
 */
static char *mint_directory;

/**
 * Handle to the mint's configuration
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our DB plugin.
 */
static struct TALER_MINTDB_Plugin *plugin;


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
  char *reserve_pub_str = NULL;
  char *add_str = NULL;
  struct TALER_Amount add_value;
  char *details = NULL;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_TIME_Absolute expiration;
  struct TALER_MINTDB_Session *session;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'a', "add", "DENOM",
     "value to add", 1,
     &GNUNET_GETOPT_set_string, &add_str},
    {'d', "mint-dir", "DIR",
     "mint directory with keys to update", 1,
     &GNUNET_GETOPT_set_filename, &mint_directory},
    {'D', "details", "JSON",
     "details about the bank transaction which justify why we add this amount", 1,
     &GNUNET_GETOPT_set_string, &details},
    TALER_GETOPT_OPTION_HELP ("Deposit funds into a Taler reserve"),
    {'R', "reserve", "KEY",
     "reserve (public key) to modify", 1,
     &GNUNET_GETOPT_set_string, &reserve_pub_str},
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-reservemod",
                                   "WARNING",
                                   NULL));

  if (GNUNET_GETOPT_run ("taler-mint-reservemod",
                         options,
                         argc, argv) < 0)
    return 1;
  if (NULL == mint_directory)
  {
    fprintf (stderr,
             "Mint directory not given\n");
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

  cfg = TALER_config_load (mint_directory);
  if (NULL == cfg)
  {
    fprintf (stderr,
             "Failed to load mint configuration\n");
    GNUNET_free_non_null (add_str);
    GNUNET_free_non_null (details);
    GNUNET_free_non_null (reserve_pub_str);
   return 1;
  }
  ret = 1;
  if (NULL ==
      (plugin = TALER_MINTDB_plugin_load (cfg)))
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
  expiration = GNUNET_TIME_relative_to_absolute (RESERVE_EXPIRATION);
  ret = plugin->reserves_in_insert (plugin->cls,
				    session,
				    &reserve_pub,
				    &add_value,
				    details,
				    expiration);
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
    TALER_MINTDB_plugin_unload (plugin);
  if (NULL != cfg)
    GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free_non_null (add_str);
  GNUNET_free_non_null (details);
  GNUNET_free_non_null (reserve_pub_str);
  return ret;
}

/* end taler-mint-reservemod.c */
