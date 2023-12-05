/*
  This file is part of TALER
  (C) 2015, 2016, 2023 Taler Systems SA

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
 * @file pq/test_pq.c
 * @brief Tests for Postgres convenience API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_pq_lib.h"
#include <gnunet/gnunet_pq_lib.h>


/**
 * Setup prepared statements.
 *
 * @param db database handle to initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static enum GNUNET_GenericReturnValue
postgres_prepare (struct GNUNET_PQ_Context *db)
{
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("test_insert",
                            "INSERT INTO test_pq ("
                            " tamount"
                            ",json"
                            ",aamount"
                            ",tamountc"
                            ",hash"
                            ",hashes"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6);"),
    GNUNET_PQ_make_prepare ("test_select",
                            "SELECT"
                            " tamount"
                            ",json"
                            ",aamount"
                            ",tamountc"
                            ",hash"
                            ",hashes"
                            " FROM test_pq;"),
    GNUNET_PQ_PREPARED_STATEMENT_END
  };

  return GNUNET_PQ_prepare_statements (db,
                                       ps);
}


/**
 * Run actual test queries.
 *
 * @return 0 on success
 */
static int
run_queries (struct GNUNET_PQ_Context *conn)
{
  struct TALER_Amount tamount;
  struct TALER_Amount aamount[3];
  struct TALER_Amount tamountc;
  struct GNUNET_HashCode hc =
  {{0xdeadbeef,0xdeadbeef,0xdeadbeef,0xdeadbeef,
    0xdeadbeef,0xdeadbeef,0xdeadbeef,0xdeadbeef,
    0xdeadbeef,0xdeadbeef,0xdeadbeef,0xdeadbeef,
    0xdeadbeef,0xdeadbeef,0xdeadbeef,0xdeadbeef, }};
  struct GNUNET_HashCode hcs[2] =
  {{{0xc0feec0f,0xc0feec0f,0xc0feec0f,0xc0feec0f,
     0xc0feec0f,0xc0feec0f,0xc0feec0f,0xc0feec0f,
     0xc0feec0f,0xc0feec0f,0xc0feec0f,0xc0feec0f,
     0xc0feec0f,0xc0feec0f,0xc0feec0f,0xc0feec0f,}},
   {{0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,
     0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,
     0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,
     0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,0xdeadbeaf,}}};
  json_t *json;

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:5.3",
                                         &aamount[0]));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:6.4",
                                         &aamount[1]));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:7.5",
                                         &aamount[2]));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:7.7",
                                         &tamount));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("FOO:8.7",
                                         &tamountc));
  json = json_object ();
  GNUNET_assert (NULL != json);
  GNUNET_assert (0 ==
                 json_object_set_new (json,
                                      "foo",
                                      json_integer (42)));
  {
    struct GNUNET_PQ_QueryParam params_insert[] = {
      TALER_PQ_query_param_amount (conn,
                                   &tamount),
      TALER_PQ_query_param_json (json),
      TALER_PQ_query_param_array_amount (3,
                                         aamount,
                                         conn),
      TALER_PQ_query_param_amount_with_currency (conn,
                                                 &tamountc),
      GNUNET_PQ_query_param_fixed_size (&hc,
                                        sizeof (hc)),
      TALER_PQ_query_param_array_hash_code (2,
                                            hcs,
                                            conn),
      GNUNET_PQ_query_param_end
    };
    PGresult *result;

    result = GNUNET_PQ_exec_prepared (conn,
                                      "test_insert",
                                      params_insert);
    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Database failure: %s\n",
                  PQresultErrorMessage (result));
      PQclear (result);
      return 1;
    }
    PQclear (result);
    json_decref (json);
  }
  {
    struct TALER_Amount tamount2;
    struct TALER_Amount tamountc2;
    struct TALER_Amount *pamount;
    struct GNUNET_HashCode hc2;
    struct GNUNET_HashCode *hcs2;
    size_t npamount;
    size_t nhcs;
    json_t *json2;
    struct GNUNET_PQ_QueryParam params_select[] = {
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec results_select[] = {
      TALER_PQ_result_spec_amount ("tamount",
                                   "EUR",
                                   &tamount2),
      TALER_PQ_result_spec_json ("json",
                                 &json2),
      TALER_PQ_result_spec_array_amount (conn,
                                         "aamount",
                                         "EUR",
                                         &npamount,
                                         &pamount),
      TALER_PQ_result_spec_amount_with_currency ("tamountc",
                                                 &tamountc2),
      GNUNET_PQ_result_spec_auto_from_type ("hash",
                                            &hc2),
      TALER_PQ_result_spec_array_hash_code (conn,
                                            "hashes",
                                            &nhcs,
                                            &hcs2),
      GNUNET_PQ_result_spec_end
    };

    if (1 !=
        GNUNET_PQ_eval_prepared_singleton_select (conn,
                                                  "test_select",
                                                  params_select,
                                                  results_select))
    {
      GNUNET_break (0);
      return 1;
    }
    GNUNET_break (0 ==
                  TALER_amount_cmp (&tamount,
                                    &tamount2));
    GNUNET_break (42 ==
                  json_integer_value (json_object_get (json2,
                                                       "foo")));
    GNUNET_break (3 == npamount);
    for (size_t i = 0; i < 3; i++)
    {
      GNUNET_break (0 ==
                    TALER_amount_cmp (&aamount[i],
                                      &pamount[i]));
    }
    GNUNET_break (0 ==
                  TALER_amount_cmp (&tamountc,
                                    &tamountc2));
    GNUNET_break (0 == GNUNET_memcmp (&hc,&hc2));
    for (size_t i = 0; i < 2; i++)
    {
      GNUNET_break (0 ==
                    GNUNET_memcmp (&hcs[i],
                                   &hcs2[i]));
    }
    GNUNET_PQ_cleanup_result (results_select);
  }
  return 0;
}


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("DO $$ "
                            " BEGIN"
                            " CREATE DOMAIN gnunet_hashcode AS BYTEA"
                            "   CHECK(length(VALUE)=64);"
                            " EXCEPTION"
                            "   WHEN duplicate_object THEN null;"
                            " END "
                            "$$;"),
    GNUNET_PQ_make_execute ("DO $$ "
                            " BEGIN"
                            " CREATE TYPE taler_amount AS"
                            "   (val INT8, frac INT4);"
                            " EXCEPTION"
                            "   WHEN duplicate_object THEN null;"
                            " END "
                            "$$;"),
    GNUNET_PQ_make_execute ("DO $$ "
                            " BEGIN"
                            " CREATE TYPE taler_amount_currency AS"
                            "   (val INT8, frac INT4, curr VARCHAR(12));"
                            " EXCEPTION"
                            "   WHEN duplicate_object THEN null;"
                            " END "
                            "$$;"),
    GNUNET_PQ_make_execute ("CREATE TEMPORARY TABLE IF NOT EXISTS test_pq ("
                            " tamount taler_amount NOT NULL"
                            ",json VARCHAR NOT NULL"
                            ",aamount taler_amount[]"
                            ",tamountc taler_amount_currency"
                            ",hash gnunet_hashcode"
                            ",hashes gnunet_hashcode[]"
                            ")"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };
  struct GNUNET_PQ_Context *conn;
  int ret;

  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-pq",
                    "WARNING",
                    NULL);
  conn = GNUNET_PQ_connect ("postgres:///talercheck",
                            NULL,
                            es,
                            NULL);
  if (NULL == conn)
    return 77;
  if (GNUNET_OK !=
      postgres_prepare (conn))
  {
    GNUNET_break (0);
    GNUNET_PQ_disconnect (conn);
    return 1;
  }

  ret = run_queries (conn);
  {
    struct GNUNET_PQ_ExecuteStatement ds[] = {
      GNUNET_PQ_make_execute ("DROP TABLE test_pq"),
      GNUNET_PQ_EXECUTE_STATEMENT_END
    };

    if (GNUNET_OK !=
        GNUNET_PQ_exec_statements (conn,
                                   ds))
    {
      fprintf (stderr,
               "Failed to drop table\n");
      GNUNET_PQ_disconnect (conn);
      return 1;
    }
  }
  GNUNET_PQ_disconnect (conn);
  return ret;
}


/* end of test_pq.c */
