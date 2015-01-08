/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
#include "mint.h"


#define break_db_err(result) do { \
    GNUNET_break(0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s\n", PQresultErrorMessage (result)); \
    PQclear (result); \
  } while (0)


static char *mint_base_dir;
static struct GNUNET_CONFIGURATION_Handle *cfg;
static PGconn *db_conn;
static char *TALER_MINT_db_connection_cfg_str;


int
TALER_MINT_init_withdraw_tables (PGconn *conn)
{
  PGresult *result;
  result = PQexec (conn,
                   "CREATE TABLE IF NOT EXISTS reserves"
                   "("
                   " reserve_pub BYTEA PRIMARY KEY"
                   ",balance_value INT4 NOT NULL"
                   ",balance_fraction INT4 NOT NULL"
                   ",balance_currency VARCHAR(4) NOT NULL"
                   ",status_sig BYTEA"
                   ",status_sign_pub BYTEA"
                   ",expiration_date INT8 NOT NULL"
                   ")");
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn,
                   "CREATE TABLE IF NOT EXISTS collectable_blindcoins"
                   "("
                   "blind_ev BYTEA PRIMARY KEY"
                   ",blind_ev_sig BYTEA NOT NULL"
                   ",denom_pub BYTEA NOT NULL"
                   ",reserve_sig BYTEA NOT NULL"
                   ",reserve_pub BYTEA NOT NULL REFERENCES reserves (reserve_pub)"
                   ")");
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn,
                   "CREATE TABLE IF NOT EXISTS known_coins "
                   "("
                   " coin_pub BYTEA NOT NULL PRIMARY KEY"
                   ",denom_pub BYTEA NOT NULL"
                   ",denom_sig BYTEA NOT NULL"
                   ",expended_value INT4 NOT NULL"
                   ",expended_fraction INT4 NOT NULL"
                   ",expended_currency VARCHAR(4) NOT NULL"
                   ",refresh_session_pub BYTEA"
                   ")");
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn, 
                   "CREATE TABLE IF NOT EXISTS refresh_sessions "
                   "("
                   " session_pub BYTEA PRIMARY KEY CHECK (length(session_pub) = 32)"
                   ",session_melt_sig BYTEA"
                   ",session_commit_sig BYTEA"
                   ",noreveal_index INT2 NOT NULL"
                   // non-zero if all reveals were ok
                   // and the new coin signatures are ready
                   ",reveal_ok BOOLEAN NOT NULL DEFAULT false"
                   ") ");
  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn, 
                   "CREATE TABLE IF NOT EXISTS refresh_order "
                   "( "
                   " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub)"
                   ",newcoin_index INT2 NOT NULL "
                   ",denom_pub BYTEA NOT NULL "
                   ",PRIMARY KEY (session_pub, newcoin_index)"
                   ") ");

  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);


  result = PQexec (conn, 
                   "CREATE TABLE IF NOT EXISTS refresh_commit_link"
                   "("
                   " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub)"
                   ",transfer_pub BYTEA NOT NULL"
                   ",link_secret_enc BYTEA NOT NULL"
                   // index of the old coin in the customer's request
                   ",oldcoin_index INT2 NOT NULL"
                   // index for cut and choose,
                   // ranges from 0 to kappa-1
                   ",cnc_index INT2 NOT NULL"
                   ")");

  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn, 
                   "CREATE TABLE IF NOT EXISTS refresh_commit_coin"
                   "("
                   " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub) "
                   ",link_vector_enc BYTEA NOT NULL"
                   // index of the new coin in the customer's request
                   ",newcoin_index INT2 NOT NULL"
                   // index for cut and choose,
                   ",cnc_index INT2 NOT NULL"
                   ",coin_ev BYTEA NOT NULL"
                   ")");

  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn, 
                   "CREATE TABLE IF NOT EXISTS refresh_melt"
                   "("
                   " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub) "
                   ",coin_pub BYTEA NOT NULL REFERENCES known_coins (coin_pub) "
                   ",denom_pub BYTEA NOT NULL "
                   ",oldcoin_index INT2 NOT NULL"
                   ")");

  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn, 
                   "CREATE TABLE IF NOT EXISTS refresh_collectable"
                   "("
                   " session_pub BYTEA NOT NULL REFERENCES refresh_sessions (session_pub) "
                   ",ev_sig BYTEA NOT NULL"
                   ",newcoin_index INT2 NOT NULL"
                   ")");

  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  result = PQexec (conn,
                   "CREATE TABLE IF NOT EXISTS deposits "
                   "( "
                   " coin_pub BYTEA NOT NULL PRIMARY KEY CHECK (length(coin_pub)=32)"
                   ",denom_pub BYTEA NOT NULL CHECK (length(denom_pub)=32)"
                   ",transaction_id INT8 NOT NULL"
                   ",amount_currency VARCHAR(4) NOT NULL"
                   ",amount_value INT4 NOT NULL"
                   ",amount_fraction INT4 NOT NULL"
                   ",merchant_pub BYTEA NOT NULL"
                   ",h_contract BYTEA NOT NULL CHECK (length(h_contract)=64)"
                   ",h_wire BYTEA NOT NULL CHECK (length(h_wire)=64)"
                   ",coin_sig BYTEA NOT NULL CHECK (length(coin_sig)=64)"
                   ",wire TEXT NOT NULL"
                   ")");

  if (PGRES_COMMAND_OK != PQresultStatus(result))
  {
    break_db_err (result);
    return GNUNET_SYSERR;
  }
  PQclear (result);

  return GNUNET_OK;
}


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

  cfg = TALER_MINT_config_load (mint_base_dir);
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

  if (GNUNET_OK != TALER_MINT_init_withdraw_tables (db_conn))
  {
    fprintf (stderr, "Failed to initialize database.\n");
    return 1;
  }

  return 0;
}

