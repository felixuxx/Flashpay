/*
  This file is part of TALER
  (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @param db_conn connection handle to initialize
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failure
 */
static int
postgres_prepare (PGconn *db_conn)
{
  PGresult *result;

#define PREPARE(name, sql, ...)                                 \
  do {                                                          \
    result = PQprepare (db_conn, name, sql, __VA_ARGS__);       \
    if (PGRES_COMMAND_OK != PQresultStatus (result))            \
    {                                                           \
      GNUNET_break (0);                                         \
      PQclear (result); result = NULL;                          \
      return GNUNET_SYSERR;                                     \
    }                                                           \
    PQclear (result); result = NULL;                            \
  } while (0);

  PREPARE ("test_insert",
           "INSERT INTO test_pq ("
           " pub"
           ",sig"
           ",abs_time"
           ",forever"
           ",hash"
           ",hamount_val" 
           ",hamount_frac"
           ",hamount_curr"
           ",namount_val" 
           ",namount_frac"
           ",namount_curr"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6,"
            "$7, $8, $9, $10, $11);",
           11, NULL);
  PREPARE ("test_select",
           "SELECT"
           " pub"
           ",sig"
           ",abs_time"
           ",forever"
           ",hash"
           ",hamount_val" 
           ",hamount_frac"
           ",hamount_curr"
           ",namount_val" 
           ",namount_frac"
           ",namount_curr"
           "FROM test_pq"
           "ORDER BY abs_time DESC "
           "LIMIT 1;",
           0, NULL);
  return GNUNET_OK;
#undef PREPARE
}


/**
 * Run actual test queries.
 *
 * @return 0 on success
 */
static int
run_queries (PGconn *conn)
{
  struct GNUNET_CRYPTO_rsa_PublicKey *pub;
  struct GNUNET_CRYPTO_rsa_PublicKey *pub2 = NULL;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct GNUNET_CRYPTO_rsa_Signature *sig2 = NULL;
  struct GNUNET_TIME_Absolute abs_time = GNUNET_TIME_absolute_get ();
  struct GNUNET_TIME_Absolute abs_time2;
  struct GNUNET_TIME_Absolute forever = GNUNET_TIME_UNIT_FOREVER_ABS;
  struct GNUNET_TIME_Absolute forever2;
  struct GNUNET_HashCode hc;
  struct GNUNET_HashCode hc2;
  struct TALER_Amount hamount;
  struct TALER_Amount hamount2;
  struct TALER_AmountNBO namount;
  struct TALER_AmountNBO namount2;
  struct TALER_PQ_QueryParam params_insert[] = {
    TALER_PQ_QUERY_PARAM_RSA_PUBLIC_KEY (pub),
    TALER_PQ_QUERY_PARAM_RSA_SIGNATURE (sig),
    TALER_PQ_QUERY_PARAM_ABSOLUTE_TIME (abs_time),
    TALER_PQ_QUERY_PARAM_ABSOLUTE_TIME (forever),
    TALER_PQ_QUERY_PARAM_PTR (&hc),
    TALER_PQ_QUERY_PARAM_AMOUNT (&hamount),
    TALER_PQ_QUERY_PARAM_AMOUNT_NBO (&namount),
    TALER_PQ_QUERY_PARAM_END
  };
  struct TALER_PQ_QueryParam params_select[] = {
    TALER_PQ_QUERY_PARAM_END
  };
  struct TALER_PQ_ResultSpec results_select[] = {
    TALER_PQ_RESULT_SPEC_RSA_PUBLIC_KEY ("pub", &pub2),
    TALER_PQ_RESULT_SPEC_RSA_SIGNATURE ("sig", &sig2),
    TALER_PQ_RESULT_SPEC_ABSOLUTE_TIME ("abs_time", &abs_time2),
    TALER_PQ_RESULT_SPEC_ABSOLUTE_TIME ("forever", &forever2),
    TALER_PQ_RESULT_SPEC ("hash", &hc2),
    TALER_PQ_RESULT_SPEC_AMOUNT ("hamount", &hamount2),
    TALER_PQ_RESULT_SPEC_AMOUNT_NBO ("namount", &namount2),
    TALER_PQ_RESULT_SPEC_END
  };
  PGresult *result;
  int ret;

  // FIXME: init pub, sig
  result = TALER_PQ_exec_prepared (conn,
				   "test_insert",
				   params_insert);
  PQclear (result);
  result = TALER_PQ_exec_prepared (conn,
				   "test_select",
				   params_select);
  ret = TALER_PQ_extract_result (result,
				 results_select,
				 0);
  // FIXME: cmp results!
  TALER_PQ_cleanup_result (results_select);
  PQclear (result);

  if (GNUNET_OK != ret)
    return 1;
  
  return 0;
}


int
main(int argc,
     const char *const argv[])
{
  PGconn *conn;
  PGresult *result;
  int ret;

  // FIXME: pass valid connect string for tests...
  conn = PQconnectdb ("postgres:///talercheck");
  if (CONNECTION_OK != PQstatus (conn))
  {
    fprintf (stderr,
	     "Cannot run test, database connection failed: %s\n",
	     PQerrorMessage (conn));
    GNUNET_break (0);
    PQfinish (conn);
    return 0; /* We ignore this type of error... */
  }

  result = PQexec (conn,
		   "CREATE TEMPORARY TABLE IF NOT EXISTS test_pq ("
		   " pub BYTEA NOT NULL"
		   ",sig BYTEA NOT NULL"
		   ",abs_time INT8 NOT NULL"
		   ",forever INT8 NOT NULL"
		   ",hash BYTEA NOT NULL CHECK(LENGTH(hash)=64)"
		   ",hamount_val INT8 NOT NULL"
		   ",hamount_frac INT4 NOT NULL"
		   ",hamount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
		   ",namount_val INT8 NOT NULL"
		   ",namount_frac INT4 NOT NULL"
		   ",namount_curr VARCHAR("TALER_CURRENCY_LEN_STR") NOT NULL"
		   ")");
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    fprintf (stderr,
	     "Failed to create table: %s\n",
	     PQerrorMessage (conn));
    PQclear (result);
    PQfinish (conn);
    return 1;
  }
  PQclear (result);
  if (GNUNET_OK !=
      postgres_prepare (conn))
  {
    GNUNET_break (0);
    PQclear (result);
    PQfinish (conn);
    return 1;
  }
  ret = run_queries (conn);
  result = PQexec (conn,
		   "DROP TABLE test_pq");
  if (PGRES_COMMAND_OK != PQresultStatus (result))
  {
    fprintf (stderr,
	     "Failed to create table: %s\n",
	     PQerrorMessage (conn));
    PQclear (result);
    PQfinish (conn);
    return 1;
  }
  PQclear (result);
  PQfinish (conn);
  return ret;
}


/* end of test_pq.c */
