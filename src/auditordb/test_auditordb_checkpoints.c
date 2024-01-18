/*
  This file is part of TALER
  Copyright (C) 2016--2024 Taler Systems SA

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
 * @file auditordb/test_auditordb_checkpoints.c
 * @brief test cases for DB interaction functions
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_db_lib.h>
#include "taler_auditordb_lib.h"
#include "taler_auditordb_plugin.h"

/**
 * Currency we use, must match CURRENCY in "test-auditor-db-postgres.conf".
 */
#define CURRENCY "EUR"

/**
 * Report line of error if @a cond is true, and jump to label "drop".
 */
#define FAILIF(cond)                              \
  do {                                          \
    if (! (cond)) { break;}                     \
    GNUNET_break (0);                         \
    goto drop;                                \
  } while (0)

/**
 * Initializes @a ptr with random data.
 */
#define RND_BLK(ptr)                                                    \
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, \
                              sizeof (*ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
  memset (ptr, 0, sizeof (*ptr))


/**
 * Global result from the testcase.
 */
static int result = -1;

/**
 * Database plugin under test.
 */
static struct TALER_AUDITORDB_Plugin *plugin;


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */
static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_Amount a1;
  struct TALER_Amount a2;
  struct TALER_Amount a3;

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":11.245678",
                                         &a1));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":2",
                                         &a2));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":3",
                                         &a3));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "loading database plugin\n");
  if (NULL ==
      (plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to connect to database\n");
    result = 77;
    return;
  }

  (void) plugin->drop_tables (plugin->cls,
                              GNUNET_YES);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             false,
                             0))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to 'create_tables'\n");
    result = 77;
    goto unload;
  }
  if (GNUNET_SYSERR ==
      plugin->preflight (plugin->cls))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed preflight check\n");
    result = 77;
    goto drop;
  }

  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls));

  /* Test inserting a blank value, should tell us one result */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->insert_auditor_progress (plugin->cls,
                                     "Test",
                                     69,
                                     NULL)
    );
  /* Test re-inserting the same value; should yield no results */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
    plugin->insert_auditor_progress (plugin->cls,
                                     "Test",
                                     69,
                                     NULL)
    );
  /* Test inserting multiple values, with one already existing */
  GNUNET_assert (
    2 == plugin->insert_auditor_progress (plugin->cls,
                                          "Test",
                                          69,
                                          "Test2",
                                          123,
                                          "Test3",
                                          245,
                                          NULL)
    );
  /* Test re-re-inserting the same key with a different value; should also yield no results */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
    plugin->insert_auditor_progress (plugin->cls,
                                     "Test",
                                     42,
                                     NULL)
    );
  /* Test updating the same key (again) with a different value; should yield a result */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->update_auditor_progress (plugin->cls,
                                     "Test",
                                     42,
                                     NULL)
    );
  /* Test updating a key that doesn't exist; should yield 0 */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
    plugin->update_auditor_progress (plugin->cls,
                                     "NonexistentTest",
                                     1,
                                     NULL)
    );

  /* Right now, the state should look like this:
   * Test  = 42
   * Test2 = 123
   * Test3 = 245
   * Let's make sure that's the case! */
  uint64_t value;
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_auditor_progress (
      plugin->cls,
      "Test",
      &value,
      NULL)
    );
  GNUNET_assert (value == 42);

  /* Ensure the rest are also at their expected values */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_auditor_progress (
      plugin->cls,
      "Test2",
      &value,
      NULL)
    );
  GNUNET_assert (value == 123);
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_auditor_progress (
      plugin->cls,
      "Test3",
      &value,
      NULL)
    );
  GNUNET_assert (value == 245);

  /* Try fetching value that does not exist */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_auditor_progress (
      plugin->cls,
      "TestNX",
      &value,
      NULL)
    );
  GNUNET_assert (0 == value);


  /* Test inserting a blank value, should tell us one result */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->insert_balance (plugin->cls,
                            "Test",
                            &a1,
                            NULL)
    );
  /* Test re-inserting the same value; should yield no results */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
    plugin->insert_balance (plugin->cls,
                            "Test",
                            &a1,
                            NULL)
    );
  /* Test inserting multiple values, with one already existing */
  GNUNET_assert (
    2 == plugin->insert_balance (plugin->cls,
                                 "Test",
                                 &a1,
                                 "Test2",
                                 &a2,
                                 "Test3",
                                 &a3,
                                 NULL)
    );
  /* Test re-re-inserting the same key with a different value; should also yield no results */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
    plugin->insert_balance (plugin->cls,
                            "Test",
                            &a2,
                            NULL)
    );
  /* Test updating the same key (again) with a different value; should yield a result */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->update_balance (plugin->cls,
                            "Test",
                            &a2,
                            NULL)
    );
  /* Test updating a key that doesn't exist; should yield 0 */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_NO_RESULTS ==
    plugin->update_balance (plugin->cls,
                            "NonexistentTest",
                            &a2,
                            NULL)
    );

  /* Right now, the state should look like this:
   * Test  = a2
   * Test2 = a2
   * Test3 = a3
   * Let's make sure that's the case! */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_balance (
      plugin->cls,
      "Test",
      &a1,
      NULL)
    );
  GNUNET_assert (0 ==
                 TALER_amount_cmp (&a1,
                                   &a2));

  /* Ensure the rest are also at their expected values */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_balance (
      plugin->cls,
      "Test2",
      &a1,
      NULL)
    );
  GNUNET_assert (0 ==
                 TALER_amount_cmp (&a1,
                                   &a2));
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_balance (
      plugin->cls,
      "Test3",
      &a1,
      NULL)
    );
  GNUNET_assert (0 ==
                 TALER_amount_cmp (&a1,
                                   &a3));

  /* Try fetching value that does not exist */
  GNUNET_assert (
    GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
    plugin->get_balance (
      plugin->cls,
      "TestNX",
      &a1,
      NULL)
    );
  GNUNET_assert (GNUNET_OK !=
                 TALER_amount_is_valid (&a1));

  result = 0;
  GNUNET_break (0 <=
                plugin->commit (plugin->cls));
drop:
  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls,
                                     GNUNET_YES));
unload:
  TALER_AUDITORDB_plugin_unload (plugin);
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
  TALER_OS_init ();
  GNUNET_log_setup (argv[0],
                    "INFO",
                    NULL);
  if (NULL == (plugin_name = strrchr (argv[0],
                                      (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-auditor-db-%s",
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
  GNUNET_SCHEDULER_run (&run, cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}
