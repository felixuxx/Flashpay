/*
  This file is part of TALER
  (C) 2015 GNUnet e.V.

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
           ",vsize"
           ",u16"
           ",u32"
           ",u64"
           ",json"
           ") VALUES "
           "($1, $2, $3, $4, $5, $6,"
            "$7, $8, $9, $10, $11, $12, $13, $14, $15, $16);",
           16, NULL);
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
	   ",vsize"
           ",u16"
           ",u32"
           ",u64"
           ",json"
           " FROM test_pq"
           " ORDER BY abs_time DESC "
           " LIMIT 1;",
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
  PGresult *result;
  int ret;
  struct GNUNET_CRYPTO_rsa_PrivateKey *priv;
  char msg[] = "Hello";
  void *msg2;
  size_t msg2_len;
  uint16_t u16;
  uint16_t u162;
  uint32_t u32;
  uint32_t u322;
  uint64_t u64;
  uint64_t u642;
  json_t *json;
  json_t *json2;

  priv = GNUNET_CRYPTO_rsa_private_key_create (1024);
  pub = GNUNET_CRYPTO_rsa_private_key_get_public (priv);
  sig = GNUNET_CRYPTO_rsa_sign (priv,
				msg,
				sizeof (msg));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:5.5",
                                         &hamount));
  TALER_amount_hton (&namount,
		     &hamount);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount ("EUR:4.4",
                                         &hamount));
  u16 = 16;
  u32 = 32;
  u64 = 64;
  json = json_object ();
  json_object_set (json, "foo", json_integer (42));
  GNUNET_assert (NULL != json);
  /* FIXME: test TALER_PQ_result_spec_variable_size */
  {
    struct TALER_PQ_QueryParam params_insert[] = {
      TALER_PQ_query_param_rsa_public_key (pub),
      TALER_PQ_query_param_rsa_signature (sig),
      TALER_PQ_query_param_absolute_time (&abs_time),
      TALER_PQ_query_param_absolute_time (&forever),
      TALER_PQ_query_param_auto_from_type (&hc),
      TALER_PQ_query_param_amount (&hamount),
      TALER_PQ_query_param_amount_nbo (&namount),
      TALER_PQ_query_param_fixed_size (msg, strlen (msg)),
      TALER_PQ_query_param_uint16 (&u16),
      TALER_PQ_query_param_uint32 (&u32),
      TALER_PQ_query_param_uint64 (&u64),
      TALER_PQ_query_param_json (json),
      TALER_PQ_query_param_end
    };
    struct TALER_PQ_QueryParam params_select[] = {
      TALER_PQ_query_param_end
    };
    struct TALER_PQ_ResultSpec results_select[] = {
      TALER_PQ_result_spec_rsa_public_key ("pub", &pub2),
      TALER_PQ_result_spec_rsa_signature ("sig", &sig2),
      TALER_PQ_result_spec_absolute_time ("abs_time", &abs_time2),
      TALER_PQ_result_spec_absolute_time ("forever", &forever2),
      TALER_PQ_result_spec_auto_from_type ("hash", &hc2),
      TALER_PQ_result_spec_amount ("hamount", &hamount2),
      TALER_PQ_result_spec_amount_nbo ("namount", &namount2),
      TALER_PQ_result_spec_variable_size ("vsize", &msg2, &msg2_len),
      TALER_PQ_result_spec_uint16 ("u16", &u162),
      TALER_PQ_result_spec_uint32 ("u32", &u322),
      TALER_PQ_result_spec_uint64 ("u64", &u642),
      TALER_PQ_result_spec_json ("json", &json2),
      TALER_PQ_result_spec_end
    };

    result = TALER_PQ_exec_prepared (conn,
				     "test_insert",
				     params_insert);
    if (PGRES_COMMAND_OK != PQresultStatus (result))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
		  "Database failure: %s\n",
		  PQresultErrorMessage (result));
      PQclear (result);
      GNUNET_CRYPTO_rsa_signature_free (sig);
      GNUNET_CRYPTO_rsa_private_key_free (priv);
      GNUNET_CRYPTO_rsa_public_key_free (pub);
      return 1;
    }

    PQclear (result);
    result = TALER_PQ_exec_prepared (conn,
				     "test_select",
				     params_select);
    if (1 !=
	PQntuples (result))
    {
      GNUNET_break (0);
      PQclear (result);
      GNUNET_CRYPTO_rsa_signature_free (sig);
      GNUNET_CRYPTO_rsa_private_key_free (priv);
      GNUNET_CRYPTO_rsa_public_key_free (pub);
      return 1;
    }
    ret = TALER_PQ_extract_result (result,
				   results_select,
				   0);
    GNUNET_break (GNUNET_YES == ret);
    GNUNET_break (abs_time.abs_value_us == abs_time2.abs_value_us);
    GNUNET_break (forever.abs_value_us == forever2.abs_value_us);
    GNUNET_break (0 ==
		  memcmp (&hc,
			  &hc2,
			  sizeof (struct GNUNET_HashCode)));
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
    GNUNET_break (0 ==
		  GNUNET_CRYPTO_rsa_signature_cmp (sig,
						   sig2));
    GNUNET_break (0 ==
		  GNUNET_CRYPTO_rsa_public_key_cmp (pub,
						    pub2));
    GNUNET_break (strlen (msg) == msg2_len);
    GNUNET_break (0 ==
		  strncmp (msg,
			   msg2,
			   msg2_len));
    GNUNET_break (16 == u162);
    GNUNET_break (32 == u322);
    GNUNET_break (64 == u642);
    GNUNET_break (42 == json_integer_value (json_object_get (json2, "foo")));
    json_decref (json2);
    TALER_PQ_cleanup_result (results_select);
    PQclear (result);
  }
  GNUNET_CRYPTO_rsa_signature_free (sig);
  GNUNET_CRYPTO_rsa_private_key_free (priv);
  GNUNET_CRYPTO_rsa_public_key_free (pub);
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

  GNUNET_log_setup ("test-pq",
		    "WARNING",
		    NULL);
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
		   ",vsize VARCHAR NOT NULL"
		   ",u16 INT2 NOT NULL"
		   ",u32 INT4 NOT NULL"
		   ",u64 INT8 NOT NULL"
		   ",json VARCHAR NOT NULL"
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
