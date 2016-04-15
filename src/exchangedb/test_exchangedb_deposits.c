/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * @file exchange/test_exchange_deposits.c
 * @brief testcase for exchange deposits
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include <libpq-fe.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_pq_lib.h"
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"

#define EXCHANGE_CURRENCY "EUR"

#define DB_URI "postgres:///taler"

#define break_db_err(result) do { \
    GNUNET_break(0); \
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Database failure: %s\n", PQresultErrorMessage (result)); \
  } while (0)

/**
 * Shorthand for exit jumps.
 */
#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


/**
 * Should we not interact with a temporary table?
 */
static int persistent;

/**
 * Testcase result
 */
static int result;

/**
 * The plugin.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;

/**
 * Main function that will be run by the scheduler.
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
  static const char wire[] = "{"
      "\"type\":\"SEPA\","
      "\"IBAN\":\"DE67830654080004822650\","
      "\"NAME\":\"GNUNET E.V\","
      "\"BIC\":\"GENODEF1SRL\""
      "}";
  struct TALER_EXCHANGEDB_Deposit *deposit;
  uint64_t transaction_id;
  struct TALER_EXCHANGEDB_Session *session;

  deposit = NULL;
  EXITIF (NULL == (plugin = TALER_EXCHANGEDB_plugin_load (cfg)));
  EXITIF (GNUNET_OK !=
          plugin->create_tables (plugin->cls,
                                 ! persistent));
  session = plugin->get_session (plugin->cls,
                                 ! persistent);
  EXITIF (NULL == session);
  deposit = GNUNET_malloc (sizeof (struct TALER_EXCHANGEDB_Deposit) + sizeof (wire));
  /* Makeup a random coin public key */
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              deposit,
                              sizeof (struct TALER_EXCHANGEDB_Deposit));
  /* Makeup a random 64bit transaction ID */
  transaction_id = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                             UINT64_MAX);
  deposit->transaction_id = GNUNET_htonll (transaction_id);
  /* Random amount */
  deposit->amount_with_fee.value =
      htonl (GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, UINT32_MAX));
  deposit->amount_with_fee.fraction =
      htonl (GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, UINT32_MAX));
  GNUNET_assert (strlen (EXCHANGE_CURRENCY) < sizeof (deposit->amount_with_fee.currency));
  strcpy (deposit->amount_with_fee.currency, EXCHANGE_CURRENCY);
  /* Copy wireformat */
  deposit->wire = json_loads (wire, 0, NULL);
  EXITIF (GNUNET_OK !=
          plugin->insert_deposit (plugin->cls,
                                  session,
                                  deposit));
  EXITIF (GNUNET_OK !=
          plugin->have_deposit (plugin->cls,
                                session,
                                deposit));
  result = GNUNET_OK;

 EXITIF_exit:
  GNUNET_free_non_null (deposit);
  if (NULL != plugin)
  {
    TALER_EXCHANGEDB_plugin_unload (plugin);
    plugin = NULL;
  }
}


int
main (int argc,
      char *const argv[])
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'T', "persist", NULL,
     gettext_noop ("Use a persistent database table instead of a temporary one"),
     GNUNET_NO, &GNUNET_GETOPT_set_one, &persistent},
    GNUNET_GETOPT_OPTION_END
  };


  persistent = GNUNET_NO;
  result = GNUNET_SYSERR;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "test-exchange-deposits",
                          "testcase for exchange deposits",
                          options, &run, NULL))
    return 3;
  return (GNUNET_OK == result) ? 0 : 1;
}
