/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file exchangedb/test_exchangedb_by_j.c
 * @brief test cases for DB interaction functions
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**o
 * Global result from the testcase.
 */
static int result;

/**
 * Report line of error if @a cond is true, and jump to label "drop".
 */
#define FAILIF(cond)                            \
  do {                                          \
      if (! (cond)) {break;}                    \
    GNUNET_break (0);                           \
    goto drop;                                  \
  } while (0)


/**
 * Initializes @a ptr with random data.
 */
#define RND_BLK(ptr)                                                    \
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
  memset (ptr, 0, sizeof (*ptr))


/**
 * Currency we use.  Must match test-exchange-db-*.conf.
 */
#define CURRENCY "EUR"

/**
 * Database plugin under test.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */
static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  const uint32_t num_partitions = 10;

  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    GNUNET_break (0);
    result = 77;
    return;
  }
  (void) plugin->drop_tables (plugin->cls);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             true,
                             num_partitions))
  {
    GNUNET_break (0);
    result = 77;
    goto cleanup;
  }

  for (unsigned int i = 0; i< 8; i++)
  {
    static unsigned int batches[] = {1, 1, 2, 3, 4, 16, 64, 256};
    const char *sndr = "payto://x-taler-bank/localhost:8080/1";
    struct TALER_Amount value;
    unsigned int batch_size = batches[i];
    struct GNUNET_TIME_Absolute now;
    struct GNUNET_TIME_Timestamp ts;
    struct GNUNET_TIME_Relative duration;
    struct TALER_ReservePublicKeyP reserve_pubs[batch_size];
    struct TALER_EXCHANGEDB_ReserveInInfo reserves[batch_size];
    enum GNUNET_DB_QueryStatus results[batch_size];
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":1.000010",
                                           &value));
    now = GNUNET_TIME_absolute_get ();
    ts = GNUNET_TIME_timestamp_get ();


    for (unsigned int k = 0; k<batch_size; k++)
      {
        RND_BLK (&reserve_pubs[k]);
        reserves[k].reserve_pub = &reserve_pubs[k];
        reserves[k].balance = &value;
        reserves[k].execution_time = ts;
        reserves[k].sender_account_details = sndr;
        reserves[k].exchange_account_name = "name";
        reserves[k].wire_reference = k;
      }
    FAILIF (batch_size !=
            plugin->batch_reserves_in_insert (plugin->cls,
                                              reserves,
                                              batch_size,
                                              results));


    duration = GNUNET_TIME_absolute_get_duration (now);
    fprintf (stdout,
             "for a batchsize equal to %d it took %s\n",
             batch_size,
             GNUNET_STRINGS_relative_time_to_string (duration,
                                                     GNUNET_NO) );

  }
  result = 0;
drop:
  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls));
cleanup:
  TALER_EXCHANGEDB_plugin_unload (plugin);
  plugin = NULL;
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *config_filename;
  char *testname;
  struct GNUNET_CONFIGURATION_Handle *cfg;
  (void) argc;
  result = -1;
   if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
    }

  GNUNET_log_setup (argv[0],
                    "WARNING",
                    NULL);
   plugin_name++;
    (void) GNUNET_asprintf (&testname,
                          "test-exchange-db-%s",
                          plugin_name);
    (void) GNUNET_asprintf (&config_filename,
                          "%s.conf",
                          testname);
  fprintf (stdout,
           "Using config: %s\n",
           config_filename);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_filename))
  {
    GNUNET_break (0);
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 2;
  }
  GNUNET_SCHEDULER_run (&run,
                        cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}

/* end of test_exchangedb_by_j.c */
