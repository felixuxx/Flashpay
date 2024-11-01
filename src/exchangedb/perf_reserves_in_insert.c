/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file exchangedb/perf_reserves_in_insert.c
 * @brief benchmark for 'reserves_in_insert'
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
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
        GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (* \
                                                                             ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
        memset (ptr, 0, sizeof (*ptr))

/**
 * How many rounds do we average over?
 */
#define ROUNDS 5

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
  static unsigned int batches[] = {1, 1, 2, 3, 4, 16, 32, 64, 128, 256, 512,
                                   1024, 1024, 512, 256, 128, 64, 32,
                                   16, 4, 3, 2, 1 };
  struct GNUNET_TIME_Relative times[sizeof (batches) / sizeof(*batches)];
  unsigned long long sqrs[sizeof (batches) / sizeof(*batches)];

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

  memset (times, 0, sizeof (times));
  memset (sqrs, 0, sizeof (sqrs));
  for (unsigned int r = 0; r < ROUNDS; r++)
  {
    for (unsigned int i = 0;
         i< sizeof(batches) / sizeof(*batches);
         i++)
    {
      unsigned int lcm = batches[i];
      struct TALER_Amount value;
      struct GNUNET_TIME_Absolute now;
      struct GNUNET_TIME_Timestamp ts;
      unsigned long long duration_sq;
      struct GNUNET_TIME_Relative duration;

      GNUNET_assert (GNUNET_OK ==
                     TALER_string_to_amount (CURRENCY ":1.000010",
                                             &value));
      now = GNUNET_TIME_absolute_get ();
      ts = GNUNET_TIME_timestamp_get ();
      {
        struct TALER_FullPayto sndr = {
          .full_payto = (char *) "payto://x-taler-bank/localhost:8080/1"
        };
        struct TALER_ReservePublicKeyP reserve_pubs[lcm];
        struct TALER_EXCHANGEDB_ReserveInInfo reserves[lcm];
        enum GNUNET_DB_QueryStatus results[lcm];

        for (unsigned int k = 0; k<lcm; k++)
        {
          RND_BLK (&reserve_pubs[k]);
          reserves[k].reserve_pub = &reserve_pubs[k];
          reserves[k].balance = &value;
          reserves[k].execution_time = ts;
          reserves[k].sender_account_details = sndr;
          reserves[k].exchange_account_name = "name";
          reserves[k].wire_reference = k;
        }
        FAILIF (lcm !=
                plugin->reserves_in_insert (plugin->cls,
                                            reserves,
                                            lcm,
                                            results));
      }
      duration = GNUNET_TIME_absolute_get_duration (now);
      times[i] = GNUNET_TIME_relative_add (times[i],
                                           duration);
      duration_sq = duration.rel_value_us * duration.rel_value_us;
      GNUNET_assert (duration_sq / duration.rel_value_us ==
                     duration.rel_value_us);
      GNUNET_assert (sqrs[i] + duration_sq >= sqrs[i]);
      sqrs[i] += duration_sq;
    } /* for 'i' batch size */
  } /* for 'r' ROUNDS */

  for (unsigned int i = 0;
       i< sizeof(batches) / sizeof(*batches);
       i++)
  {
    unsigned int lcm = batches[i];
    struct GNUNET_TIME_Relative avg;
    double avg_dbl;
    double variance;

    avg = GNUNET_TIME_relative_divide (times[i],
                                       ROUNDS);
    avg_dbl = avg.rel_value_us;
    variance = sqrs[i] - (avg_dbl * avg_dbl * ROUNDS);
    fprintf (stdout,
             "Batch[%4u]: %8llu us/entry ± %6.0f\n",
             batches[i],
             (unsigned long long) avg.rel_value_us / lcm,
             sqrt (variance / lcm / (ROUNDS - 1)));
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


/* end of perf_reserves_in_insert.c */
