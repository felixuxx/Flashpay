/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file sq/test_sq.c
 * @brief Tests for SQLite3 convenience API
 * @author Jonathan Buchanan
 */
#include "platform.h"
#include "taler_sq_lib.h"


/**
 * Run actual test queries.
 *
 * @return 0 on success
 */
static int
run_queries (sqlite3 *db)
{
  struct TALER_Amount hamount;
  struct TALER_AmountNBO namount;
  json_t *json;
  struct GNUNET_TIME_Absolute htime = GNUNET_TIME_absolute_get ();
  struct GNUNET_TIME_AbsoluteNBO ntime;
  sqlite3_stmt *test_insert;
  sqlite3_stmt *test_select;
  struct GNUNET_SQ_PrepareStatement ps[] = {
    GNUNET_SQ_make_prepare ("INSERT INTO test_sq ("
                            " hamount_val"
                            ",hamount_frac"
                            ",namount_val"
                            ",namount_frac"
                            ",json"
                            ",htime"
                            ",ntime"
                            ") VALUES "
                            "($1, $2, $3, $4, $5, $6, $7)",
                            &test_insert),
    GNUNET_SQ_make_prepare ("SELECT"
                            " hamount_val"
                            ",hamount_frac"
                            ",namount_val"
                            ",namount_frac"
                            ",json"
                            ",htime"
                            ",ntime"
                            " FROM test_sq",
                            &test_select),
    GNUNET_SQ_PREPARE_END
  };
  int ret = 0;

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:1.23",
                                         &hamount));
  TALER_amount_hton (&namount,
                     &hamount);
  json = json_object ();
  json_object_set_new (json, "foo", json_integer (42));
  GNUNET_assert (NULL != json);
  GNUNET_TIME_round_abs (&htime);
  ntime = GNUNET_TIME_absolute_hton (htime);

  GNUNET_assert (GNUNET_OK == GNUNET_SQ_prepare (db,
                                                 ps));

  {
    struct GNUNET_SQ_QueryParam params_insert[] = {
      TALER_SQ_query_param_amount (&hamount),
      TALER_SQ_query_param_amount_nbo (&namount),
      TALER_SQ_query_param_json (json),
      TALER_SQ_query_param_absolute_time (&htime),
      TALER_SQ_query_param_absolute_time_nbo (&ntime),
      GNUNET_SQ_query_param_end
    };
    GNUNET_SQ_reset (db,
                     test_insert);
    GNUNET_assert (GNUNET_OK == GNUNET_SQ_bind (test_insert,
                                                params_insert));
    GNUNET_assert (SQLITE_DONE == sqlite3_step (test_insert));
    sqlite3_finalize (test_insert);
  }

  {
    struct TALER_Amount result_amount;
    struct TALER_AmountNBO nresult_amount;
    struct TALER_Amount nresult_amount_converted;
    json_t *result_json;
    struct GNUNET_TIME_Absolute hresult_time;
    struct GNUNET_TIME_AbsoluteNBO nresult_time;
    struct GNUNET_SQ_QueryParam params_select[] = {
      GNUNET_SQ_query_param_end
    };
    struct GNUNET_SQ_ResultSpec results_select[] = {
      TALER_SQ_result_spec_amount ("EUR",
                                   &result_amount),
      TALER_SQ_result_spec_amount_nbo ("EUR",
                                       &nresult_amount),
      TALER_SQ_result_spec_json (&result_json),
      TALER_SQ_result_spec_absolute_time (&hresult_time),
      TALER_SQ_result_spec_absolute_time_nbo (&nresult_time),
      GNUNET_SQ_result_spec_end
    };

    GNUNET_SQ_reset (db,
                     test_select);
    GNUNET_assert (GNUNET_OK == GNUNET_SQ_bind (test_select,
                                                params_select));
    GNUNET_assert (SQLITE_ROW == sqlite3_step (test_select));

    GNUNET_assert (GNUNET_OK == GNUNET_SQ_extract_result (test_select,
                                                          results_select));
    TALER_amount_ntoh (&nresult_amount_converted,
                       &nresult_amount);
    if ((GNUNET_OK != TALER_amount_cmp_currency (&hamount,
                                                 &result_amount)) ||
        (0 != TALER_amount_cmp (&hamount,
                                &result_amount)) ||
        (GNUNET_OK != TALER_amount_cmp_currency (&hamount,
                                                 &nresult_amount_converted)) ||
        (0 != TALER_amount_cmp (&hamount,
                                &nresult_amount_converted)) ||
        (1 != json_equal (json,
                          result_json)) ||
        (htime.abs_value_us != hresult_time.abs_value_us) ||
        (ntime.abs_value_us__ != nresult_time.abs_value_us__))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Result from database doesn't match input\n");
      ret = 1;
    }
    GNUNET_SQ_cleanup_result (results_select);
    sqlite3_finalize (test_select);
  }
  json_decref (json);

  return ret;
}


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_SQ_ExecuteStatement es[] = {
    GNUNET_SQ_make_execute ("CREATE TEMPORARY TABLE IF NOT EXISTS test_sq ("
                            " hamount_val INT8 NOT NULL"
                            ",hamount_frac INT8 NOT NULL"
                            ",namount_val INT8 NOT NULL"
                            ",namount_frac INT8 NOT NULL"
                            ",json VARCHAR NOT NULL"
                            ",htime INT8 NOT NULL"
                            ",ntime INT8 NOT NULL"
                            ")"),
    GNUNET_SQ_EXECUTE_STATEMENT_END
  };
  sqlite3 *db;
  int ret;

  GNUNET_log_setup ("test-pq",
                    "WARNING",
                    NULL);

  if (SQLITE_OK != sqlite3_open ("talercheck.db",
                                 &db))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to open SQLite3 database\n");
    return 77;
  }

  if (GNUNET_OK != GNUNET_SQ_exec_statements (db,
                                              es))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to create new table\n");
    if ((SQLITE_OK != sqlite3_close (db)) ||
        (0 != unlink ("talercheck.db")))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to close db or unlink\n");
    }
    return 1;
  }

  ret = run_queries (db);

  if (SQLITE_OK !=
      sqlite3_exec (db,
                    "DROP TABLE test_sq",
                    NULL, NULL, NULL))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to drop table\n");
    ret = 1;
  }

  if (SQLITE_OK != sqlite3_close (db))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to close database\n");
    ret = 1;
  }
  if (0 != unlink ("talercheck.db"))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to unlink test database file\n");
    ret = 1;
  }
  return ret;
}


/* end of sq/test_sq.c */
