/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file exchangedb/bench_db.c
 * @brief test cases for DB interaction functions
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include <gnunet/gnunet_pq_lib.h>
#include "taler_util.h"

/**
 * How many elements should we insert?
 */
#define TOTAL (1024 * 16)

/**
 * Global result from the testcase.
 */
static int result;

/**
 * Initializes @a ptr with random data.
 */
#define RND_BLK(ptr)                                                    \
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))


static bool
prepare (struct GNUNET_PQ_Context *conn)
{
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare (
      "bm_insert",
      "INSERT INTO benchmap "
      "(hc"
      ",expiration_date"
      ") VALUES "
      "($1, $2);",
      2),
    /* Used in #postgres_iterate_denomination_info() */
    GNUNET_PQ_make_prepare (
      "bm_select",
      "SELECT"
      " expiration_date"
      " FROM benchmap"
      " WHERE hc=$1;",
      1),
    GNUNET_PQ_make_prepare (
      "bhm_insert",
      "INSERT INTO benchhmap "
      "(hc"
      ",expiration_date"
      ") VALUES "
      "($1, $2);",
      2),
    /* Used in #postgres_iterate_denomination_info() */
    GNUNET_PQ_make_prepare (
      "bhm_select",
      "SELECT"
      " expiration_date"
      " FROM benchhmap"
      " WHERE hc=$1;",
      1),
    GNUNET_PQ_make_prepare (
      "bem_insert",
      "INSERT INTO benchemap "
      "(hc"
      ",ihc"
      ",expiration_date"
      ") VALUES "
      "($1, $2, $3);",
      3),
    /* Used in #postgres_iterate_denomination_info() */
    GNUNET_PQ_make_prepare (
      "bem_select",
      "SELECT"
      " expiration_date"
      " FROM benchemap"
      " WHERE ihc=$1 AND hc=$2;",
      2),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };
  enum GNUNET_GenericReturnValue ret;

  ret = GNUNET_PQ_prepare_statements (conn,
                                      ps);
  if (GNUNET_OK != ret)
    return false;
  return true;
}


static bool
bm_insert (struct GNUNET_PQ_Context *conn,
           unsigned int i)
{
  uint32_t b = htonl ((uint32_t) i);
  struct GNUNET_HashCode hc;
  struct GNUNET_TIME_Absolute now;

  now = GNUNET_TIME_absolute_get ();
  GNUNET_CRYPTO_hash (&b,
                      sizeof (b),
                      &hc);
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&hc),
      GNUNET_PQ_query_param_absolute_time (&now),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_non_select (conn,
                                             "bm_insert",
                                             params);
    return (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  }
}


static bool
bhm_insert (struct GNUNET_PQ_Context *conn,
            unsigned int i)
{
  uint32_t b = htonl ((uint32_t) i);
  struct GNUNET_HashCode hc;
  struct GNUNET_TIME_Absolute now;

  now = GNUNET_TIME_absolute_get ();
  GNUNET_CRYPTO_hash (&b,
                      sizeof (b),
                      &hc);
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&hc),
      GNUNET_PQ_query_param_absolute_time (&now),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_non_select (conn,
                                             "bhm_insert",
                                             params);
    return (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  }
}


static bool
bem_insert (struct GNUNET_PQ_Context *conn,
            unsigned int i)
{
  uint32_t b = htonl ((uint32_t) i);
  struct GNUNET_HashCode hc;
  struct GNUNET_TIME_Absolute now;
  uint32_t ihc;

  now = GNUNET_TIME_absolute_get ();
  GNUNET_CRYPTO_hash (&b,
                      sizeof (b),
                      &hc);
  memcpy (&ihc,
          &hc,
          sizeof (ihc));
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&hc),
      GNUNET_PQ_query_param_uint32 (&ihc),
      GNUNET_PQ_query_param_absolute_time (&now),
      GNUNET_PQ_query_param_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_non_select (conn,
                                             "bem_insert",
                                             params);
    return (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  }
}


static bool
bm_select (struct GNUNET_PQ_Context *conn,
           unsigned int i)
{
  uint32_t b = htonl ((uint32_t) i);
  struct GNUNET_HashCode hc;
  struct GNUNET_TIME_Absolute now;

  GNUNET_CRYPTO_hash (&b,
                      sizeof (b),
                      &hc);
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&hc),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_absolute_time ("expiration_date",
                                           &now),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_singleton_select (conn,
                                                   "bm_select",
                                                   params,
                                                   rs);
    return (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  }
}


static bool
bhm_select (struct GNUNET_PQ_Context *conn,
            unsigned int i)
{
  uint32_t b = htonl ((uint32_t) i);
  struct GNUNET_HashCode hc;
  struct GNUNET_TIME_Absolute now;

  GNUNET_CRYPTO_hash (&b,
                      sizeof (b),
                      &hc);
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&hc),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_absolute_time ("expiration_date",
                                           &now),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_singleton_select (conn,
                                                   "bhm_select",
                                                   params,
                                                   rs);
    return (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  }
}


static bool
bem_select (struct GNUNET_PQ_Context *conn,
            unsigned int i)
{
  uint32_t b = htonl ((uint32_t) i);
  struct GNUNET_HashCode hc;
  struct GNUNET_TIME_Absolute now;
  uint32_t ihc;

  GNUNET_CRYPTO_hash (&b,
                      sizeof (b),
                      &hc);
  memcpy (&ihc,
          &hc,
          sizeof (ihc));
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_uint32 (&ihc),
      GNUNET_PQ_query_param_auto_from_type (&hc),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_absolute_time ("expiration_date",
                                           &now),
      GNUNET_PQ_result_spec_end
    };
    enum GNUNET_DB_QueryStatus qs;

    qs = GNUNET_PQ_eval_prepared_singleton_select (conn,
                                                   "bem_select",
                                                   params,
                                                   rs);
    return (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  }
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */
static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct GNUNET_PQ_Context *conn;
  struct GNUNET_PQ_Context *conn2;
  struct GNUNET_TIME_Absolute now;
  pid_t f;
  int status;

  conn = GNUNET_PQ_connect_with_cfg (cfg,
                                     "bench-db-postgres",
                                     "benchmark-",
                                     NULL,
                                     NULL);
  if (NULL == conn)
  {
    result = EXIT_FAILURE;
    GNUNET_break (0);
    return;
  }
  conn2 = GNUNET_PQ_connect_with_cfg (cfg,
                                      "bench-db-postgres",
                                      NULL,
                                      NULL,
                                      NULL);
  if (! prepare (conn))
  {
    GNUNET_PQ_disconnect (conn);
    GNUNET_PQ_disconnect (conn2);
    result = EXIT_FAILURE;
    GNUNET_break (0);
    return;
  }
  if (! prepare (conn2))
  {
    GNUNET_PQ_disconnect (conn);
    GNUNET_PQ_disconnect (conn2);
    result = EXIT_FAILURE;
    GNUNET_break (0);
    return;
  }
  {
    struct GNUNET_PQ_ExecuteStatement es[] = {
      GNUNET_PQ_make_try_execute ("DELETE FROM benchmap;"),
      GNUNET_PQ_make_try_execute ("DELETE FROM benchemap;"),
      GNUNET_PQ_make_try_execute ("DELETE FROM benchhmap;"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };

    GNUNET_assert (GNUNET_OK ==
                   GNUNET_PQ_exec_statements (conn,
                                              es));
  }
  now = GNUNET_TIME_absolute_get ();
  for (unsigned int i = 0; i<TOTAL; i++)
    if (! bm_insert (conn,
                     i))
    {
      GNUNET_PQ_disconnect (conn);
      result = EXIT_FAILURE;
      GNUNET_break (0);
      return;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Insertion of %u elements took %s\n",
              (unsigned int) TOTAL,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));
  now = GNUNET_TIME_absolute_get ();
  f = fork ();
  for (unsigned int i = 0; i<TOTAL; i++)
  {
    uint32_t j;

    j = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_NONCE,
                                  TOTAL);
    if (! bm_select ((0 == f)? conn2 : conn,
                     j))
    {
      GNUNET_PQ_disconnect (conn);
      result = EXIT_FAILURE;
      GNUNET_break (0);
      return;
    }
  }
  if (0 == f)
    exit (0);
  waitpid (f, &status, 0);
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Selection of 2x%u elements took %s\n",
              (unsigned int) TOTAL,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));

  now = GNUNET_TIME_absolute_get ();
  for (unsigned int i = 0; i<TOTAL; i++)
    if (! bhm_insert (conn,
                      i))
    {
      GNUNET_PQ_disconnect (conn);
      result = EXIT_FAILURE;
      GNUNET_break (0);
      return;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Insertion of %u elements with hash index took %s\n",
              (unsigned int) TOTAL,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));
  now = GNUNET_TIME_absolute_get ();
  f = fork ();
  for (unsigned int i = 0; i<TOTAL; i++)
  {
    uint32_t j;

    j = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_NONCE,
                                  TOTAL);
    if (! bhm_select ((0 == f)? conn2 : conn,
                      j))
    {
      GNUNET_PQ_disconnect (conn);
      result = EXIT_FAILURE;
      GNUNET_break (0);
      return;
    }
  }
  if (0 == f)
    exit (0);
  waitpid (f, &status, 0);
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Selection of 2x%u elements with hash index took %s\n",
              (unsigned int) TOTAL,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));

  now = GNUNET_TIME_absolute_get ();
  for (unsigned int i = 0; i<TOTAL; i++)
    if (! bem_insert (conn,
                      i))
    {
      GNUNET_PQ_disconnect (conn);
      result = EXIT_FAILURE;
      GNUNET_break (0);
      return;
    }
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Insertion of %u elements with short element took %s\n",
              (unsigned int) TOTAL,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));
  now = GNUNET_TIME_absolute_get ();
  f = fork ();
  for (unsigned int i = 0; i<TOTAL; i++)
  {
    uint32_t j;

    j = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_NONCE,
                                  TOTAL);
    if (! bem_select ((0 == f)? conn2 : conn,
                      j))
    {
      GNUNET_PQ_disconnect (conn);
      result = EXIT_FAILURE;
      GNUNET_break (0);
      return;
    }
  }
  if (0 == f)
    exit (0);
  waitpid (f, &status, 0);
  GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
              "Selection of 2x%u elements with short element took %s\n",
              (unsigned int) TOTAL,
              GNUNET_STRINGS_relative_time_to_string (
                GNUNET_TIME_absolute_get_duration (now),
                GNUNET_YES));

  GNUNET_PQ_disconnect (conn);
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
                    "INFO",
                    NULL);
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "bench-db-%s",
                          plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf",
                          testname);
  TALER_OS_init ();
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


/* end of bench_db.c */
