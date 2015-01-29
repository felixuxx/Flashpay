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
 * @file taler-mint-reservemod.c
 * @brief Modify reserves.
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <libpq-fe.h>
#include "taler_util.h"
#include "taler_signatures.h"
#include "mint_db.h"
#include "db_pq.h"

char *mintdir;

static struct GNUNET_CRYPTO_EddsaPublicKey *reserve_pub;

struct GNUNET_CONFIGURATION_Handle *cfg;

static PGconn *db_conn;



/**
 * Create a new or add to existing reserve.
 * Fails if currencies do not match.
 *
 * @param denom denomination to add
 *
 * @return ...
 */
static int
reservemod_add (struct TALER_Amount denom)
{
  PGresult *result;
  {
    const void *param_values[] = { reserve_pub };
    int param_lengths[] = {sizeof(struct GNUNET_CRYPTO_EddsaPublicKey)};
    int param_formats[] = {1};
    result = PQexecParams (db_conn,
                           "select balance_value, balance_fraction, balance_currency from reserves where reserve_pub=$1 limit 1;",
                           1, NULL, (const char * const *) param_values, param_lengths, param_formats, 1);
  }

  if (PGRES_TUPLES_OK != PQresultStatus (result))
  {
    fprintf (stderr, "Select failed: %s\n", PQresultErrorMessage (result));
    return GNUNET_SYSERR;
  }
  if (0 == PQntuples (result))
  {
    struct GNUNET_TIME_AbsoluteNBO exnbo;
    exnbo = GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add ( GNUNET_TIME_absolute_get (), GNUNET_TIME_UNIT_YEARS));

    uint32_t value = htonl (denom.value);
    uint32_t fraction = htonl (denom.fraction);
    const void *param_values[] = {
      reserve_pub,
      &value,
      &fraction,
      denom.currency,
      &exnbo};
    int param_lengths[] = {32, 4, 4, strlen(denom.currency), 8};
    int param_formats[] = {1, 1, 1, 1, 1};
    result = PQexecParams (db_conn,
                           "insert into reserves (reserve_pub, balance_value, balance_fraction, balance_currency, "
                           " expiration_date )"
                           "values ($1,$2,$3,$4,$5);",
                           5, NULL, (const char **) param_values, param_lengths, param_formats, 1);

    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      fprintf (stderr, "Insert failed: %s\n", PQresultErrorMessage (result));
      return GNUNET_SYSERR;
    }
  }
  else
  {
    struct TALER_Amount old_denom;
    struct TALER_Amount new_denom;
    struct TALER_AmountNBO new_denom_nbo;
    int param_lengths[] = {4, 4, 32};
    int param_formats[] = {1, 1, 1};
    const void *param_values[] = {
      &new_denom_nbo.value,
      &new_denom_nbo.fraction,
      reserve_pub
    };

    GNUNET_assert (GNUNET_OK ==
                   TALER_DB_extract_amount (result, 0,
                                            "balance_value",
                                            "balance_fraction",
                                            "balance_currency",
                                            &old_denom));
    new_denom = TALER_amount_add (old_denom, denom);
    new_denom_nbo = TALER_amount_hton (new_denom);
    result = PQexecParams (db_conn,
                           "UPDATE reserves "
                           "SET balance_value = $1, balance_fraction = $2, "
                           " status_sig = NULL, status_sign_pub = NULL "
                           "WHERE reserve_pub = $3 ",
                           3, NULL, (const char **) param_values, param_lengths, param_formats, 1);

    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      fprintf (stderr, "Update failed: %s\n", PQresultErrorMessage (result));
      return GNUNET_SYSERR;
    }

    if (0 != strcmp ("1", PQcmdTuples (result)))
    {
      fprintf (stderr, "Update failed (updated '%s' tupes instead of '1')\n",
               PQcmdTuples (result));
      return GNUNET_SYSERR;
    }

  }
  return GNUNET_OK;
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
  static char *reserve_pub_str;
  static char *add_str;
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-keyup OPTIONS"),
    {'d', "mint-dir", "DIR",
     "mint directory with keys to update", 1,
     &GNUNET_GETOPT_set_filename, &mintdir},
    {'R', "reserve", "KEY",
     "reserve (public key) to modify", 1,
     &GNUNET_GETOPT_set_string, &reserve_pub_str},
    {'a', "add", "DENOM",
     "value to add", 1,
     &GNUNET_GETOPT_set_string, &add_str},
    GNUNET_GETOPT_OPTION_END
  };
  char *TALER_MINT_db_connection_cfg_str;

  GNUNET_assert (GNUNET_OK == GNUNET_log_setup ("taler-mint-keycheck", "WARNING", NULL));

  if (GNUNET_GETOPT_run ("taler-mint-keyup", options, argc, argv) < 0)
    return 1;
  if (NULL == mintdir)
  {
    fprintf (stderr, "mint directory not given\n");
    return 1;
  }

  reserve_pub = GNUNET_new (struct GNUNET_CRYPTO_EddsaPublicKey);
  if ((NULL == reserve_pub_str) ||
      (GNUNET_OK !=
       GNUNET_STRINGS_string_to_data (reserve_pub_str,
                                      strlen (reserve_pub_str),
                                      reserve_pub,
                                      sizeof (struct GNUNET_CRYPTO_EddsaPublicKey))))
  {
    fprintf (stderr, "reserve key invalid\n");
    return 1;
  }

  cfg = TALER_config_load (mintdir);
  if (NULL == cfg)
  {
    fprintf (stderr, "can't load mint configuration\n");
    return 1;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "mint",
                                             "db",
                                             &TALER_MINT_db_connection_cfg_str))
  {
    fprintf (stderr, "db configuration string not found\n");
    return 42;
  }
  db_conn = PQconnectdb (TALER_MINT_db_connection_cfg_str);
  if (CONNECTION_OK != PQstatus (db_conn))
  {
    fprintf (stderr, "db connection failed: %s\n", PQerrorMessage (db_conn));
    return 1;
  }

  if (NULL != add_str)
  {
    struct TALER_Amount add_value;
    if (GNUNET_OK != TALER_string_to_amount (add_str, &add_value))
    {
      fprintf (stderr, "could not read value\n");
      return 1;
    }
    if (GNUNET_OK != reservemod_add (add_value))
    {
      fprintf (stderr, "adding value failed\n");
      return 1;
    }
  }
  return 0;
}
