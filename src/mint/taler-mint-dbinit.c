/*
  This file is part of TALER
  Copyright (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @file taler-mint-dbinit.c
 * @brief Create tables for the mint database.
 * @author Florian Dold
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <libpq-fe.h>
#include "taler_util.h"
#include "mint_db.h"

#define break_db_err(result) do { \
    GNUNET_break(0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s\n", PQresultErrorMessage (result)); \
    PQclear (result); \
  } while (0)


static char *mint_base_dir;
static struct GNUNET_CONFIGURATION_Handle *cfg;
static PGconn *db_conn;
static char *TALER_MINT_db_connection_cfg_str;





/**
 * The main function of the serve tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc, char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-keyup OPTIONS"),
    {'d', "mint-dir", "DIR",
     "mint directory", 1,
     &GNUNET_GETOPT_set_filename, &mint_base_dir},
    GNUNET_GETOPT_OPTION_END
  };

  if (GNUNET_GETOPT_run ("taler-mint-serve", options, argc, argv) < 0)
    return 1;

  GNUNET_assert (GNUNET_OK == GNUNET_log_setup ("taler-mint-dbinit", "INFO", NULL));

  if (NULL == mint_base_dir)
  {
    fprintf (stderr, "Mint base directory not given.\n");
    return 1;
  }

  cfg = TALER_config_load (mint_base_dir);
  if (NULL == cfg)
  {
    fprintf (stderr, "Can't load mint configuration.\n");
    return 1;
  }
  if (GNUNET_OK != GNUNET_CONFIGURATION_get_value_string (cfg, "mint", "db", &TALER_MINT_db_connection_cfg_str))
  {
    fprintf (stderr, "Configuration 'mint.db' not found.\n");
    return 42;
  }
  db_conn = PQconnectdb (TALER_MINT_db_connection_cfg_str);
  if (CONNECTION_OK != PQstatus (db_conn))
  {
    fprintf (stderr, "Database connection failed: %s\n", PQerrorMessage (db_conn));
    return 1;
  }

  if (GNUNET_OK != TALER_MINT_DB_create_tables (GNUNET_NO))
  {
    fprintf (stderr, "Failed to initialize database.\n");
    return 1;
  }

  return 0;
}
