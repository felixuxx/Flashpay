#include "postgres.h"

#include <stdio.h>
#include <stdlib.h>
#include <postgresql/libpq-fe.h>
#include <libpq-int.h>
#include <catalog/pg_type.h>
#include <executor/spi.h>
#include <funcapi.h>
#include <fmgr.h>
#include <utils/builtins.h>
#include <utils/array.h>
#include <sys/time.h>
#include <utils/numeric.h>
#include <utils/timestamp.h>
#include <utils/bytea.h>

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

typedef struct
{
  Datum col1;
  Datum col2;
} valuest;

void _PG_init (void);

void _PG_fini (void);

void
_PG_init (void)
{
}


PG_FUNCTION_INFO_V1 (pg_spi_insert_int);
PG_FUNCTION_INFO_V1 (pg_spi_select_from_x);
PG_FUNCTION_INFO_V1 (pg_spi_select_pair_from_y);
// PG_FUNCTION_INFO_V1(pg_spi_select_with_cond);
PG_FUNCTION_INFO_V1 (pg_spi_update_y);
PG_FUNCTION_INFO_V1 (pg_spi_prepare_example);
PG_FUNCTION_INFO_V1 (pg_spi_prepare_example_without_saveplan);
PG_FUNCTION_INFO_V1 (pg_spi_prepare_insert);
PG_FUNCTION_INFO_V1 (pg_spi_prepare_insert_without_saveplan);
// PG_FUNCTION_INFO_V1(pg_spi_prepare_select_with_cond);
PG_FUNCTION_INFO_V1 (pg_spi_prepare_select_with_cond_without_saveplan);
PG_FUNCTION_INFO_V1 (pg_spi_prepare_update);
PG_FUNCTION_INFO_V1 (pg_spi_get_dep_ref_fees);
// SIMPLE SELECT
Datum
pg_spi_prepare_example (PG_FUNCTION_ARGS)
{
  static SPIPlanPtr prepared_plan;
  int ret;
  int64 result;
  char *value;
  SPIPlanPtr new_plan;

  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "DB connection failed ! \n");
  }
  {
    if (prepared_plan == NULL)
    {
      new_plan = SPI_prepare ("SELECT 1 FROM X", 0, NULL);
      prepared_plan = SPI_saveplan (new_plan);

      if (prepared_plan == NULL)
      {
        elog (ERROR, "FAIL TO SAVE !\n");
      }
    }

    ret = SPI_execute_plan (prepared_plan, NULL, 0,false, 0);
    if (ret != SPI_OK_SELECT)
    {
      elog (ERROR, "SELECT FAILED %d !\n", ret);
    }

    if (SPI_tuptable != NULL && SPI_tuptable->vals != NULL &&
        SPI_tuptable->tupdesc != NULL)
    {
      value = SPI_getvalue (SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1);
      result = atoi (value);
    }
    else
    {
      elog (ERROR, "EMPTY TABLE !\n");
    }
  }
  SPI_finish ();
  PG_RETURN_INT64 (result);
}


Datum
pg_spi_prepare_example_without_saveplan (PG_FUNCTION_ARGS)
{
  int ret;
  int64 result;
  char *value;
  SPIPlanPtr new_plan;

  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "DB connection failed ! \n");
  }

  {
    new_plan = SPI_prepare ("SELECT 1 FROM X", 0, NULL);
    ret = SPI_execute_plan (new_plan, NULL, 0,false, 0);
    if (ret != SPI_OK_SELECT)
    {
      elog (ERROR, "SELECT FAILED %d !\n", ret);
    }

    if (SPI_tuptable != NULL
        && SPI_tuptable->vals != NULL
        && SPI_tuptable->tupdesc != NULL)
    {
      value = SPI_getvalue (SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1);
      result = atoi (value);
    }
    else
    {
      elog (ERROR, "EMPTY TABLE !\n");
    }
  }
  SPI_finish ();
  PG_RETURN_INT64 (result);//  PG_RETURN_INT64(result);
}


// SELECT 1 FROM X
// V1
Datum
pg_spi_select_from_x (PG_FUNCTION_ARGS)
{
  int ret;
  char *query = "SELECT 1 FROM X";
  uint64 proc;
  ret = SPI_connect ();

  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "SPI_connect failed");
  }

  ret = SPI_exec (query, 10);
  proc = SPI_processed;
  if (ret != SPI_OK_SELECT)
  {
    elog (ERROR, "SPI_exec failed");
  }

  SPI_finish ();

  PG_RETURN_INT64 (proc);
}


// INSERT INTO X VALUES (1)
Datum
pg_spi_insert_int (PG_FUNCTION_ARGS)
{
  int ret;
  int nargs;
  Oid argtypes[1];
  Datum values[1];
  char *query = "INSERT INTO X (a) VALUES ($1)";

  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "SPI_connect failed");
  }

  nargs = 1;
  argtypes[0] = INT4OID;
  values[0] = Int32GetDatum (3);

  ret = SPI_execute_with_args (query, nargs, argtypes, values, NULL, false, 0);
  if (ret != SPI_OK_INSERT)
  {
    elog (ERROR, "SPI_execute_with_args failed");
  }

  SPI_finish ();

  PG_RETURN_VOID ();
}


Datum
pg_spi_prepare_insert (PG_FUNCTION_ARGS)
{
  static SPIPlanPtr prepared_plan = NULL;
  int ret;
  int nargs;
  Oid argtypes[1];
  Datum values[1];
  const char *query = "INSERT INTO X (a) VALUES ($1)";
  SPIPlanPtr new_plan;
  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "SPI_connect failed ! \n");
  }
  if (prepared_plan == NULL)
  {

    argtypes[0] = INT4OID;
    nargs = 1;
    values[0] = Int32GetDatum (3);
    new_plan = SPI_prepare (query, nargs, argtypes);
    if (new_plan== NULL)
    {
      elog (ERROR, "SPI_prepare failed ! \n");
    }
    prepared_plan = SPI_saveplan (new_plan);
    if (prepared_plan == NULL)
    {
      elog (ERROR, "SPI_saveplan failed ! \n");
    }
  }

  ret = SPI_execute_plan (prepared_plan, values, NULL, false, 0);
  if (ret != SPI_OK_INSERT)
  {
    elog (ERROR, "SPI_execute_plan failed ! \n");
  }

  SPI_finish ();

  PG_RETURN_VOID ();
}


/*
Datum
pg_spi_prepare_insert_bytea(PG_FUNCTION_ARGS)
{
  static SPIPlanPtr prepared_plan = NULL;
  int ret;
  int nargs;
  Oid argtypes[1];
  Datum values[1];
  Oid argtypes2[1];
  Datum val[1];
  char *query = "INSERT INTO X (a) VALUES ($1)";
  SPIPlanPtr new_plan;
  ret = SPI_connect();
  if (ret != SPI_OK_CONNECT)
  {
    elog(ERROR, "SPI_connect failed ! \n");
  }
  if (prepared_plan == NULL) {
    argtypes2[0] = BOOLOID;
    val[0] = BoolGetDatum();
    argtypes[0] = BYTEAOID;
    nargs = 1;
    values[0] = Int32GetDatum(3);
    new_plan = SPI_prepare(query, nargs, argtypes);
    if (new_plan== NULL)
    {
      elog(ERROR, "SPI_prepare failed ! \n");
    }
    prepared_plan = SPI_saveplan(new_plan);
    if (prepared_plan == NULL)
    {
      elog(ERROR, "SPI_saveplan failed ! \n");
    }
  }

  ret = SPI_execute_plan(prepared_plan, values, NULL, false, 0);
  if (ret != SPI_OK_INSERT)
  {
    elog(ERROR, "SPI_execute_plan failed ! \n");
  }

  SPI_finish();

  PG_RETURN_VOID();
}
*/

Datum
pg_spi_prepare_insert_without_saveplan (PG_FUNCTION_ARGS)
{
  int ret;
  int nargs;
  Oid argtypes[1];
  Datum values[1];
  const char *query = "INSERT INTO X (a) VALUES ($1)";
  SPIPlanPtr new_plan;
  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "SPI_connect failed");
  }
  {
    argtypes[0] = INT4OID;
    nargs = 1;
    values[0] = Int32GetDatum (3);
    new_plan = SPI_prepare (query, nargs, argtypes);
    if (new_plan== NULL)
    {
      elog (ERROR, "SPI_prepare failed");
    }
  }

  ret = SPI_execute_plan (new_plan, values, NULL, false, 0);
  if (ret != SPI_OK_INSERT)
  {
    elog (ERROR, "SPI_execute_plan failed");
  }

  SPI_finish ();

  PG_RETURN_VOID ();
}


/*
Datum
pg_spi_select_pair_from_y(PG_FUNCTION_ARGS)
{
  int ret;
  valuest result;
  bool isnull;
  char *query = "SELECT 1,1 FROM Y";
  result.col1 = 0;
  result.col2 = 0;

  if ((ret = SPI_connect()) < 0) {
    fprintf(stderr, "SPI_connect returned %d\n", ret);
    exit(1);
  }
  ret = SPI_exec(query, 0);
  if (ret == SPI_OK_SELECT && SPI_processed > 0) {
    int i;
    SPITupleTable *tuptable = SPI_tuptable;
    TupleDesc tupdesc = tuptable->tupdesc;
    for (i = 0; i < SPI_processed; i++) {
      HeapTuple tuple = tuptable->vals[i];
      result.col1 = SPI_getbinval(tuple, tupdesc, 1, &isnull);
      result.col2 = SPI_getbinval(tuple, tupdesc, 2, &isnull);
    }
  }
  SPI_finish();
  PG_RETURN_TEXT_P(result);
}
*/

// SELECT X FROM Y WHERE Z=$1
/*
Datum
pg_spi_select_with_cond(PG_FUNCTION_ARGS)
{
    int ret;
    char *query;
    int nargs;
    Oid argtypes[1];
    Datum values[1];
    uint64 proc;
    query = "SELECT col1 FROM Y WHERE col2 = $1";

    ret = SPI_connect();
    if (ret != SPI_OK_CONNECT) {
        elog(ERROR, "SPI_connect failed: %d", ret);
    }
    nargs = 1;
    argtypes[0] = INT4OID;
    values[0] = Int32GetDatum(2);

    ret = SPI_execute_with_args(query, nargs, argtypes, values, NULL, false, 0);
    proc = SPI_processed;
    if (ret != SPI_OK_SELECT)
    {
      elog(ERROR, "SPI_execute_with_args failed");
    }

    SPI_finish();


    PG_RETURN_INT64(proc);
    }*/

////////SELECT WITH COND
/*
Datum pg_spi_prepare_select_with_cond(PG_FUNCTION_ARGS) {
  static SPIPlanPtr prepared_plan = NULL;
  SPIPlanPtr new_plan;
  int ret;
  Datum values[1];
  uint64 proc;
  int nargs;
  Oid argtypes[1];
  char *query = "SELECT col1 FROM Y WHERE col1 = $1";
  int result = 0;

  ret = SPI_connect();
  if (ret != SPI_OK_CONNECT)
    elog(ERROR, "SPI_connect failed ! \n");

  if (prepared_plan == NULL) {

    argtypes[0] = INT4OID;
    nargs = 1;
    values[0] = DatumGetByteaP(SPI_getbinval(tuptable->vals[0], tupdesc, 1, &isnull)); //Value col2

    new_plan = SPI_prepare(query, nargs, argtypes);
    if (new_plan == NULL)
      elog(ERROR, "SPI_prepare failed ! \n");

    prepared_plan = SPI_saveplan(new_plan);
    if (prepared_plan == NULL)
      elog(ERROR, "SPI_saveplan failed ! \n");
  }


  ret = SPI_execute_plan(prepared_plan, values, NULL, false, 0);

  if (ret != SPI_OK_SELECT) {
    elog(ERROR, "SPI_execute_plan failed: %d \n", ret);
    }

  proc = SPI_processed;

  if (proc > 0) {
    SPITupleTable *tuptable = SPI_tuptable;
    TupleDesc tupdesc = tuptable->tupdesc;
    HeapTuple tuple;
    int i;

    for (i = 0; i < proc; i++) {
      tuple = tuptable->vals[i];
      for (int j = 1; j <= tupdesc->natts; j++) {
        char * value = SPI_getvalue(tuple, tupdesc, j);
        result += atoi(value);
      }
    }
    }
  SPI_finish();
  PG_RETURN_INT64(result);
}
*/

Datum
pg_spi_prepare_select_with_cond_without_saveplan (PG_FUNCTION_ARGS)
{

  SPIPlanPtr new_plan;
  int ret;
  Datum values[1];
  uint64 proc;
  int nargs;
  Oid argtypes[1];
  char *query = "SELECT col1 FROM Y WHERE col2 = $1";
  int result = 0;

  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
    elog (ERROR, "SPI_connect failed ! \n");

  {

    argtypes[0] = INT4OID;
    nargs = 1;
    values[0] = Int32GetDatum (2); // Value col2

    new_plan = SPI_prepare (query, nargs, argtypes);
    if (new_plan == NULL)
      elog (ERROR, "SPI_prepare failed ! \n");

  }


  ret = SPI_execute_plan (new_plan, values, NULL, false, 0);

  if (ret != SPI_OK_SELECT)
  {
    elog (ERROR, "SPI_execute_plan failed: %d \n", ret);
  }

  proc = SPI_processed;

  if (proc > 0)
  {
    SPITupleTable *tuptable = SPI_tuptable;
    TupleDesc tupdesc = tuptable->tupdesc;
    HeapTuple tuple;
    int i;

    for (i = 0; i < proc; i++)
    {
      tuple = tuptable->vals[i];
      for (int j = 1; j <= tupdesc->natts; j++)
      {
        char *value = SPI_getvalue (tuple, tupdesc, j);
        result += atoi (value);
      }
    }
  }
  SPI_finish ();
  PG_RETURN_INT64 (result);
}


Datum
pg_spi_update_y (PG_FUNCTION_ARGS)
{
  int ret;
  int nargs;
  Oid argtypes[1];
  Datum values[1];
  const char *query = "UPDATE Y SET col1 = 4 WHERE (col2 = $1)";

  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "SPI_connect failed ! \n");
  }

  nargs = 1;
  argtypes[0] = INT4OID;
  values[0] = Int32GetDatum (0);

  ret = SPI_execute_with_args (query, nargs, argtypes, values, NULL, false, 0);
  if (ret != SPI_OK_UPDATE)
  {
    elog (ERROR, "SPI_execute_with_args failed ! \n");
  }

  SPI_finish ();

  PG_RETURN_VOID ();
}


Datum
pg_spi_prepare_update (PG_FUNCTION_ARGS)
{
  static SPIPlanPtr prepared_plan = NULL;
  SPIPlanPtr new_plan;
  int ret;
  int nargs;
  Oid argtypes[1];
  Datum values[1];
  const char *query = "UPDATE Y SET col1 = 4 WHERE (col2 = $1)";

  ret = SPI_connect ();
  if (ret != SPI_OK_CONNECT)
  {
    elog (ERROR, "SPI_connect failed ! \n");
  }

  if (prepared_plan == NULL)
  {
    argtypes[0] = INT4OID;
    nargs = 1;
    values[0] = Int32GetDatum (3);
    // PREPARE
    new_plan = SPI_prepare (query, nargs, argtypes);
    if (new_plan == NULL)
      elog (ERROR, "SPI_prepare failed ! \n");
    // SAVEPLAN
    prepared_plan = SPI_saveplan (new_plan);
    if (prepared_plan == NULL)
      elog (ERROR, "SPI_saveplan failed ! \n");
  }
  ret = SPI_execute_plan (prepared_plan, values, NULL, false, 0);
  if (ret != SPI_OK_UPDATE)
    elog (ERROR, "SPI_execute_plan failed ! \n");

  SPI_finish ();
  PG_RETURN_VOID ();
}


/*
Datum
pg_spi_prepare_update_without_saveplan(PG_FUNCTION_ARGS)
{}*/
void
_PG_fini (void)
{
}


/*

*/


Datum
pg_spi_get_dep_ref_fees (PG_FUNCTION_ARGS)
{
  /* Define plan to save */
  static SPIPlanPtr deposit_plan;
  static SPIPlanPtr ref_plan;
  static SPIPlanPtr fees_plan;
  static SPIPlanPtr dummy_plan;
  /* Define variables to update */
  Timestamp refund_deadline = PG_GETARG_TIMESTAMP (0);
  bytea *merchant_pub = PG_GETARG_BYTEA_P (1);
  bytea *wire_target_h_payto = PG_GETARG_BYTEA_P (2);
  bytea *wtid_raw = PG_GETARG_BYTEA_P (3);
  bool is_null;
  /* Define variables to store the results of each SPI query */
  uint64_t sum_deposit_val  = 0;
  uint32_t sum_deposit_frac = 0;
  uint64_t s_refund_val     = 0;
  uint32_t s_refund_frac    = 0;
  uint64_t sum_dep_fee_val  = 0;
  uint32_t sum_dep_fee_frac = 0;
  uint64_t norm_refund_val  = 0;
  uint32_t norm_refund_frac = 0;
  uint64_t sum_refund_val   = 0;
  uint32_t sum_refund_frac  = 0;
  /* Define variables to store the Tuptable */
  SPITupleTable *dep_res;
  SPITupleTable *ref_res;
  SPITupleTable *ref_by_coin_res;
  SPITupleTable *norm_ref_by_coin_res;
  SPITupleTable *fully_refunded_coins_res;
  SPITupleTable *fees_res;
  SPITupleTable *dummys_res;
  /* Define variable to update */
  Datum values_refund[2];
  Datum values_deposit[3];
  Datum values_fees[2];
  Datum values_dummys[2];
  TupleDesc tupdesc;
  /* Define variables to replace some tables */
  bytea *ref_by_coin_coin_pub;
  int64 ref_by_coin_deposit_serial_id = 0;
  bytea *norm_ref_by_coin_coin_pub;
  int64_t norm_ref_by_coin_deposit_serial_id = 0;
  bytea *new_dep_coin_pub = NULL;
  int res = SPI_connect ();

  /* Connect to SPI */
  if (res < 0)
  {
    elog (ERROR, "Could not connect to SPI manager");
  }
  if (deposit_plan == NULL)
  {
    const char *dep_sql;
    SPIPlanPtr new_plan;

    // Execute first query and store results in variables
    dep_sql =
      "UPDATE deposits SET done=TRUE "
      "WHERE NOT (done OR policy_blocked) "
      "AND refund_deadline=$1 "
      "AND merchant_pub=$2 "
      "AND wire_target_h_payto=$3 "
      "RETURNING "
      "deposit_serial_id,"
      "coin_pub,"
      "amount_with_fee_val,"
      "amount_with_fee_frac;";
    fprintf (stderr, "dep sql %d\n", 1);
    new_plan =
      SPI_prepare (dep_sql, 4,(Oid[]){INT8OID, BYTEAOID, BYTEAOID});
    fprintf (stderr, "dep sql %d\n", 2);
    if (new_plan == NULL)
      elog (ERROR, "SPI_prepare failed for dep \n");
    deposit_plan = SPI_saveplan (new_plan);
    if (deposit_plan == NULL)
      elog (ERROR, "SPI_saveplan failed for dep \n");
  }
  fprintf (stdout, "dep sql %d\n", 3);

  values_deposit[0] = Int64GetDatum (refund_deadline);
  values_deposit[1] = PointerGetDatum (merchant_pub);
  values_deposit[2] = PointerGetDatum (wire_target_h_payto);

  res = SPI_execute_plan (deposit_plan,
                          values_deposit,
                          NULL,
                          true,
                          0);
  fprintf (stdout, "dep sql %d\n", 4);
  if (res != SPI_OK_UPDATE)
  {
    elog (ERROR, "Failed to execute subquery 1 \n");
  }
  // STORE TUPTABLE deposit
  dep_res = SPI_tuptable;

  for (unsigned int i = 0; i < SPI_processed; i++)
  {
    int64 dep_deposit_serial_ids = DatumGetInt64 (SPI_getbinval (
                                                    SPI_tuptable->vals[i],
                                                    SPI_tuptable->tupdesc, 1,
                                                    &is_null));
    bytea *dep_coin_pub = DatumGetByteaP (SPI_getbinval (SPI_tuptable->vals[i],
                                                         SPI_tuptable->tupdesc,
                                                         2, &is_null));
    int64 dep_amount_val = DatumGetInt64 (SPI_getbinval (SPI_tuptable->vals[i],
                                                         SPI_tuptable->tupdesc,
                                                         3, &is_null));
    int32 dep_amount_frac = DatumGetInt32 (SPI_getbinval (SPI_tuptable->vals[i],
                                                          SPI_tuptable->tupdesc,
                                                          4, &is_null));

    if (is_null)
      elog (ERROR, "Failed to retrieve data from deposit \n");
    if (ref_plan == NULL)
    {
      // Execute second query with parameters from first query and store results in variables
      const char *ref_sql =
        "SELECT amount_with_fee_val, amount_with_fee_frac, coin_pub, deposit_serial_id "
        "FROM refunds "
        "WHERE coin_pub=$1 "
        "AND deposit_serial_id=$2;";
      SPIPlanPtr new_plan = SPI_prepare (ref_sql, 3, (Oid[]){BYTEAOID,
                                                             INT8OID});
      if (new_plan == NULL)
        elog (ERROR, "SPI_prepare failed for refund\n");
      ref_plan = SPI_saveplan (new_plan);
      if (ref_plan == NULL)
        elog (ERROR, "SPI_saveplan failed for refund\n");
    }
    values_refund[0] = PointerGetDatum (dep_coin_pub);
    values_refund[1] = Int64GetDatum (dep_deposit_serial_ids);
    res = SPI_execute_plan (ref_plan,
                            values_refund,
                            NULL,
                            false,
                            0);
    if (res != SPI_OK_SELECT)
      elog (ERROR, "Failed to execute subquery 2\n");
    // STORE TUPTABLE refund
    ref_res = SPI_tuptable;
    for (unsigned int j = 0; j < SPI_processed; j++)
    {
      int64 ref_refund_val = DatumGetInt64 (SPI_getbinval (
                                              SPI_tuptable->vals[j],
                                              SPI_tuptable->tupdesc, 1,
                                              &is_null));
      int32 ref_refund_frac = DatumGetInt32 (SPI_getbinval (
                                               SPI_tuptable->vals[j],
                                               SPI_tuptable->tupdesc, 2,
                                               &is_null));
      bytea *ref_coin_pub = DatumGetByteaP (SPI_getbinval (
                                              SPI_tuptable->vals[j],
                                              SPI_tuptable->tupdesc, 3,
                                              &is_null));
      int64 ref_deposit_serial_id = DatumGetInt64 (SPI_getbinval (
                                                     SPI_tuptable->vals[j],
                                                     SPI_tuptable->tupdesc, 4,
                                                     &is_null));
      // Execute third query with parameters from second query and store results in variables
      ref_by_coin_coin_pub = ref_coin_pub;
      ref_by_coin_deposit_serial_id = ref_deposit_serial_id;
      // LOOP TO GET THE SUM FROM REFUND BY COIN
      for (unsigned int i = 0; i<SPI_processed; i++)
      {
        if ((ref_by_coin_coin_pub ==
             DatumGetByteaP (SPI_getbinval (SPI_tuptable->vals[i],
                                            SPI_tuptable->tupdesc, 1,
                                            &is_null)))
            &&
            (ref_by_coin_deposit_serial_id ==
             DatumGetUInt64 (SPI_getbinval (SPI_tuptable->vals[i],
                                            SPI_tuptable->tupdesc, 2,
                                            &is_null)))
            )
        {
          sum_refund_val += ref_refund_val;
          sum_refund_frac += ref_refund_frac;
          norm_ref_by_coin_coin_pub = ref_by_coin_coin_pub;
          norm_ref_by_coin_deposit_serial_id = ref_by_coin_deposit_serial_id;
        }
      }// END SUM CALCULATION
      // NORMALIZE REFUND VAL FRAC
      norm_refund_val =
        (sum_refund_val + sum_refund_frac) / 100000000;
      norm_refund_frac =
        sum_refund_frac % 100000000;
      // Get refund values
      s_refund_val += sum_refund_val;
      s_refund_frac = sum_refund_frac;
    }// END REFUND
    if (norm_ref_by_coin_coin_pub == dep_coin_pub
        && ref_by_coin_deposit_serial_id == dep_deposit_serial_ids
        && norm_refund_val == dep_amount_val
        && norm_refund_frac == dep_amount_frac)
    {
      new_dep_coin_pub = dep_coin_pub;
    }
    // Ensure we get the fee for each coin and not only once per denomination
    if (fees_plan == NULL)
    {
      const char *fees_sql =
        "SELECT "
        "  denom.fee_deposit_val AS fee_val, "
        "  denom.fee_deposit_frac AS fee_frac, "
        "FROM known_coins kc"
        "JOIN denominations denom USING (denominations_serial) "
        "WHERE kc.coin_pub = $1 AND kc.coin_pub != $2;";
      SPIPlanPtr new_plan = SPI_prepare (fees_sql, 3, (Oid[]){BYTEAOID,
                                                              BYTEAOID});
      if (new_plan == NULL)
      {
        elog (ERROR, "SPI_prepare for fees failed ! \n");
      }
      fees_plan = SPI_saveplan (new_plan);
      if (fees_plan == NULL)
      {
        elog (ERROR, "SPI_saveplan for fees failed ! \n");
      }
    }
    values_fees[0] = PointerGetDatum (dep_coin_pub);
    values_fees[1] = PointerGetDatum (new_dep_coin_pub);
    res = SPI_execute_plan (fees_plan, values_fees, NULL, false, 0);
    if (res != SPI_OK_SELECT)
      elog (ERROR, "SPI_execute_plan failed for fees \n");
    fees_res = SPI_tuptable;
    tupdesc = fees_res->tupdesc;
    for (unsigned int i = 0; i<SPI_processed; i++)
    {
      HeapTuple tuple = fees_res->vals[i];
      bool is_null;
      uint64_t fee_val = DatumGetUInt64 (SPI_getbinval (tuple, tupdesc, 1,
                                                        &is_null));
      uint32_t fee_frac = DatumGetUInt32 (SPI_getbinval (tuple, tupdesc, 2,
                                                         &is_null));
      uint64_t fees_deposit_serial_id = DatumGetUInt64 (SPI_getbinval (tuple,
                                                                       tupdesc,
                                                                       3,
                                                                       &is_null));
      if (dummy_plan == NULL)
      {
        const char *insert_dummy_sql =
          "INSERT INTO "
          "aggregation_tracking(deposit_serial_id, wtid_raw)"
          " VALUES ($1, $2)";

        SPIPlanPtr new_plan = SPI_prepare (insert_dummy_sql, 2, (Oid[]){INT8OID,
                                                                        BYTEAOID});
        if (new_plan == NULL)
          elog (ERROR, "FAILED to prepare aggregation tracking \n");
        dummy_plan = SPI_saveplan (new_plan);
        if (dummy_plan == NULL)
          elog (ERROR, "FAILED to saveplan aggregation tracking\n");
      }
      values_dummys[0] = Int64GetDatum (dep_deposit_serial_ids);
      values_dummys[1] = PointerGetDatum (wtid_raw);
      res = SPI_execute_plan (dummy_plan, values_dummys, NULL, false, 0);
      if (res != SPI_OK_INSERT)
        elog (ERROR, "Failed to insert dummy\n");
      dummys_res = SPI_tuptable;
      // Calculation of deposit fees for not fully refunded deposits
      sum_dep_fee_val  += fee_val;
      sum_dep_fee_frac += fee_frac;
    }
    // Get deposit values
    sum_deposit_val += dep_amount_val;
    sum_deposit_frac += dep_amount_frac;
  }// END DEPOSIT
  SPI_finish ();
  PG_RETURN_VOID ();
}
