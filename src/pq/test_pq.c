/*
  This file is part of TALER
  (C) 2015, 2016 GNUnet e.V.

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


/**
 * Setup prepared statements.
 *
 * @param db database handle to initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
postgres_prepare (struct GNUNET_PQ_Context *db)
{
  struct GNUNET_PQ_PreparedStatement ps[] = {
    GNUNET_PQ_make_prepare ("test_insert",
                            "INSERT INTO test_pq ("
                            " hamount_val"
                            ",hamount_frac"
                            ",namount_val"
                            ",namount_frac"
                            ",json"
                            ") VALUES "
                            "($1, $2, $3, $4, $5);",
                            5),
    GNUNET_PQ_make_prepare ("test_select",
                            "SELECT"
                            " hamount_val"
                            ",hamount_frac"
                            ",namount_val"
                            ",namount_frac"
                            ",json"
                            " FROM test_pq;",
                            0),
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
  struct TALER_Amount hamount;
  struct TALER_Amount hamount2;
  struct TALER_AmountNBO namount;
  struct TALER_AmountNBO namount2;
  PGresult *result;
  int ret;
  json_t *json;
  json_t *json2;

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:5.5",
                                         &hamount));
  TALER_amount_hton (&namount,
                     &hamount);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4.4",
                                         &hamount));
  json = json_object ();
  json_object_set_new (json, "foo", json_integer (42));
  GNUNET_assert (NULL != json);
  {
    struct GNUNET_PQ_QueryParam params_insert[] = {
      TALER_PQ_query_param_amount (&hamount),
      TALER_PQ_query_param_amount_nbo (&namount),
      TALER_PQ_query_param_json (json),
      GNUNET_PQ_query_param_end
    };

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
  }
  {
    struct GNUNET_PQ_QueryParam params_select[] = {
      GNUNET_PQ_query_param_end
    };

    result = GNUNET_PQ_exec_prepared (conn,
                                      "test_select",
                                      params_select);
    if (1 !=
        PQntuples (result))
    {
      GNUNET_break (0);
      PQclear (result);
      return 1;
    }
  }

  {
    struct GNUNET_PQ_ResultSpec results_select[] = {
      TALER_PQ_result_spec_amount ("hamount", "EUR", &hamount2),
      TALER_PQ_result_spec_amount_nbo ("namount", "EUR", &namount2),
      TALER_PQ_result_spec_json ("json", &json2),
      GNUNET_PQ_result_spec_end
    };

    ret = GNUNET_PQ_extract_result (result,
                                    results_select,
                                    0);
    GNUNET_break (0 ==
                  TALER_amount_cmp (&hamount,
                                    &hamount2));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount ("EUR:5.5",
                                           &hamount));
    TALER_amount_ntoh (&hamount2,
                       &namount2);
    GNUNET_break (0 ==
                  TALER_amount_cmp (&hamount,
                                    &hamount2));
    GNUNET_break (42 ==
                  json_integer_value (json_object_get (json2, "foo")));
    GNUNET_PQ_cleanup_result (results_select);
    PQclear (result);
  }
  json_decref (json);
  if (GNUNET_OK != ret)
    return 1;

  return 0;
}


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_PQ_ExecuteStatement es[] = {
    GNUNET_PQ_make_execute ("CREATE TEMPORARY TABLE IF NOT EXISTS test_pq ("
                            " hamount_val INT8 NOT NULL"
                            ",hamount_frac INT4 NOT NULL"
                            ",namount_val INT8 NOT NULL"
                            ",namount_frac INT4 NOT NULL"
                            ",json VARCHAR NOT NULL"
                            ")"),
    GNUNET_PQ_EXECUTE_STATEMENT_END
  };

  struct GNUNET_PQ_Context *conn;
  int ret;

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
