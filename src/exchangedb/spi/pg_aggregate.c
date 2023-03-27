#include "postgres.h"
#include "fmgr.h"
#include "utils/numeric.h"
#include "utils/builtins.h"
#include "executor/spi.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(get_deposit_summary);

Datum get_deposit_summary(PG_FUNCTION_ARGS)
{

  static SPIPlanPtr deposit_plan;
  static SPIPlanPtr refund_plan;
  static SPIPlanPtr refund_by_coin_plan;
  static SPIPlanPtr norm_refund_by_coin_plan;
  static SPIPlanPtr fully_refunded_by_coins_plan;
  static SPIPlanPtr fees_plan;

  int shard = PG_GETARG_INT32(0);
  char * sql;
  char *merchant_pub = text_to_cstring(PG_GETARG_TEXT_P(1));
  char *wire_target_h_payto = text_to_cstring(PG_GETARG_TEXT_P(2));
  char *wtid_raw = text_to_cstring(PG_GETARG_TEXT_P(3));
  int refund_deadline = PG_GETARG_INT32(4);
  int conn = SPI_connect();
  if (conn != SPI_OK_CONNECT)
  {
    elog(ERROR, "DB connexion failed ! \n");
  }

  if ( deposit_plan == NULL
       || refund_plan == NULL
       || refund_by_coin_plan == NULL
       || norm_refund_by_coin_plan = NULL
       || fully_refunded_coins_plan = NULL
       || fees_plan == NULL )
  {
    if (deposit_plan == NULL)
    {
      int nargs = 3;
      Oid argtypes[3];
      argtypes[0] = INT8OID;
      argtypes[1] = BYTEAOID;
      argtypes[2] = BYTEAOID;
      const char *dep_sql =
        "    UPDATE deposits"
        "    SET done=TRUE"
        "    WHERE NOT (done OR policy_blocked)"
        "        AND refund_deadline < $1"
        "        AND merchant_pub = $2"
        "        AND wire_target_h_payto = $3"
        "    RETURNING"
        "        deposit_serial_id"
        "        ,coin_pub"
        "        ,amount_with_fee_val AS amount_val"
        "        ,amount_with_fee_frac AS amount_frac";
      SPIPlanPtr new_plan =
        SPI_prepare(dep_sql, 4, argtypes});
      if (new_plan == NULL)
      {
        elog(ERROR, "SPI_prepare for deposit failed ! \n");
      }
      deposit_plan = SPI_saveplan(new_plan);
      if (deposit_plan == NULL)
      {
        elog(ERROR, "SPI_saveplan for deposit failed ! \n");
      }
    }

    Datum values[4];
    values[0] = Int64GetDatum(refund_deadline);
    values[1] = CStringGetDatum(merchant_pub);
    values[2] = CStringGetDatum(wire_target_h_payto);
    int ret = SPI_execute_plan (deposit_plan,
                                values,
                                NULL,
                                true,
                                0);
    if (ret != SPI_OK_UPDATE)
    {
        elog(ERROR, "Failed to execute subquery 1\n");
    }
    uint64_t *dep_deposit_serial_ids = palloc(sizeof(uint64_t) * SPI_processed);
    BYTEA **dep_coin_pubs = palloc(sizeof(BYTEA *) * SPI_processed);
    uint64_t *dep_amount_vals = palloc(sizeof(uint64_t) * SPI_processed);
    uint32_t *dep_amount_fracs = palloc(sizeof(uint32_t) * SPI_processed);
    for (unsigned int i = 0; i < SPI_processed; i++) {
      HeapTuple tuple = SPI_tuptable->vals[i];
      dep_deposit_serial_ids[i] =
        DatumGetInt64(SPI_getbinval(tuple, SPI_tuptable->tupdesc, 1, &ret));
      dep_coin_pubs[i] =
        DatumGetByteaP(SPI_getbinval(tuple, SPI_tuptable->tupdesc, 2, &ret));
      dep_amount_vals[i] =
        DatumGetInt64(SPI_getbinval(tuple, SPI_tuptable->tupdesc, 3, &ret));
      dep_amount_fracs[i] =
        DatumGetInt32(SPI_getbinval(tuple, SPI_tuptable->tupdesc, 4, &ret));
    }


    if (refund_plan == NULL)
    {
      const char *ref_sql =
        "ref AS ("
        "  SELECT"
        "    amount_with_fee_val AS refund_val"
        "   ,amount_with_fee_frac AS refund_frac"
        "   ,coin_pub"
        "   ,deposit_serial_id"
        "    FROM refunds"
        "   WHERE coin_pub IN (SELECT coin_pub FROM dep)"
        "     AND deposit_serial_id IN (SELECT deposit_serial_id FROM dep)) ";
      SPIPlanPtr new_plan = SPI_prepare(ref_sql, 0, NULL);
      if (new_plan == NULL)
        elog (ERROR, "SPI_prepare for refund failed ! \n");
      refund_plan = SPI_saveplan(new_plan);
      if (refund_plan == NULL)
      {
        elog(ERROR, "SPI_saveplan for refund failed ! \n");
      }
    }

    int64t_t *ref_deposit_serial_ids = palloc(sizeof(int64_t) * SPI_processed);

    int res = SPI_execute_plan (refund_plan, NULL, NULL, false, 0);
    if (res != SPI_OK_SELECT)
    {
      elog(ERROR, "Failed to execute subquery 2\n");
    }
    SPITupleTable *tuptable = SPI_tuptable;
    TupleDesc tupdesc = tuptable->tupdesc;
    for (unsigned int i = 0; i < SPI_processed; i++)
    {
      HeapTuple tuple = tuptable->vals[i];
      Datum refund_val = SPI_getbinval(tuple, tupdesc, 1, &refund_val_isnull);
      Datum refund_frac = SPI_getbinval(tuple, tupdesc, 2, &refund_frac_isnull);
      Datum coin_pub = SPI_getbinval(tuple, tupdesc, 3, &coin_pub_isnull);
      Datum deposit_serial_id = SPI_getbinval(tuple, tupdesc, 4, &deposit_serial_id_isnull);
      if (refund_val_isnull
          || refund_frac_isnull
          || coin_pub_isnull
          || deposit_serial_id_isnull )
      {
        elog(ERROR, "Failed to retrieve data from subquery 2");
      }
      uint64_t refund_val_int = DatumGetUInt64(refund_val);
      uint32_t refund_frac_int = DatumGetUInt32(refund_frac);
      BYTEA coin_pub = DatumGetByteaP(coin_pub);
      ref_deposit_serial_ids = DatumGetInt64(deposit_serial_id);

      refund *new_refund = (refund*) palloc(sizeof(refund));
      new_refund->coin_pub = coin_pub_str;
      new_refund->deposit_serial_id = deposit_serial_id_int;
      new_refund->amount_with_fee_val = refund_val_int;
      new_refund->amount_with_fee_frac = refund_frac_int;
    }


    if (refund_by_coin_plan == NULL)
    {
      const char *ref_by_coin_sql =
        "ref_by_coin AS ("
        "  SELECT"
        "    SUM(refund_val) AS sum_refund_val"
        "   ,SUM(refund_frac) AS sum_refund_frac"
        "   ,coin_pub"
        "   ,deposit_serial_id"
        "    FROM ref"
        "   GROUP BY coin_pub, deposit_serial_id) ";
      SPIPlanPtr new_plan = SPI_prepare (ref_by_coin_sql, 0, NULL);
      if (new_plan == NULL)
        elog(ERROR, "SPI_prepare for refund by coin failed ! \n");
      refund_by_coin_plan = SPI_saveplan (new_plan);
      if (refund_by_coin_plan == NULL)
        elog(ERROR, "SPI_saveplan for refund failed");
    }


    int res = SPI_execute_plan (refund_by_coin_plan, NULL, NULL, false, 0);
    if (res != SPI_OK_SELECT)
    {
      elog(ERROR, "Failed to execute subquery 2\n");
    }

    SPITupleTable *tuptable = SPI_tuptable;
    TupleDesc tupdesc = tuptable->tupdesc;
    for (unsigned int i = 0; i < SPI_processed; i++)
    {
      HeapTuple tuple = tuptable->vals[i];
      Datum sum_refund_val = SPI_getbinval(tuple, tupdesc, 1, &refund_val_isnull);
      Datum sum_refund_frac = SPI_getbinval(tuple, tupdesc, 2, &refund_frac_isnull);
      Datum coin_pub = SPI_getbinval(tuple, tupdesc, 3, &coin_pub_isnull);
      Datum deposit_serial_id_int = SPI_getbinval(tuple, tupdesc, 4, &deposit_serial_id_isnull);
      if (refund_val_isnull
          || refund_frac_isnull
          || coin_pub_isnull
          || deposit_serial_id_isnull )
      {
        elog(ERROR, "Failed to retrieve data from subquery 2");
      }
      uint64_t s_refund_val_int = DatumGetUInt64(sum_refund_val);
      uint32_t s_refund_frac_int = DatumGetUInt32(sum_refund_frac);
      BYTEA coin_pub = DatumGetByteaP(coin_pub);
      uint64_t deposit_serial_id_int = DatumGetInt64(deposit_serial_id_int);
      refund *new_refund_by_coin = (refund*) palloc(sizeof(refund));
      new_refund_by_coin->coin_pub = coin_pub;
      new_refund_by_coin->deposit_serial_id = deposit_serial_id_int;
      new_refund_by_coin->refund_amount_with_fee_val = s_refund_val_int;
      new_refund_by_coin->refund_amount_with_fee_frac = s_refund_frac_int;
    }


    if (norm_refund_by_coin_plan == NULL)
    {
      const char *norm_ref_by_coin_sql =
        "norm_ref_by_coin AS ("
        "  SELECT"
        "   coin_pub"
        "   ,deposit_serial_id"
        "    FROM ref_by_coin) ";
      SPIPlanPtr new_plan = SPI_prepare (norm_ref_by_coin_sql, 0, NULL);
      if (new_plan == NULL)
        elog(ERROR, "SPI_prepare for norm refund by coin failed ! \n");
      norm_refund_by_coin_plan = SPI_saveplan(new_plan);
      if (norm_refund_by_coin_plan == NULL)
        elog(ERROR, "SPI_saveplan for norm refund by coin failed ! \n");
    }

    double norm_refund_val =
      ((double)new_refund_by_coin->refund_amount_with_fee_val
       + (double)new_refund_by_coin->refund_amount_with_fee_frac) / 100000000;
    double norm_refund_frac =
      (double)new_refund_by_coin->refund_amount_with_fee_frac % 100000000;

    if (fully_refunded_coins_plan == NULL)
    {
      const char *fully_refunded_coins_sql =
        "fully_refunded_coins AS ("
        "  SELECT"
        "    dep.coin_pub"
        "    FROM norm_ref_by_coin norm"
        "    JOIN dep"
        "      ON (norm.coin_pub = dep.coin_pub"
        "      AND norm.deposit_serial_id = dep.deposit_serial_id"
        "      AND norm.norm_refund_val = dep.amount_val"
        "      AND norm.norm_refund_frac = dep.amount_frac)) ";
      SPIPlanPtr new_plan =
        SPI_prepare(fully_refunded_coins_sql, 0, NULL);
      if (new_plan == NULL)
        elog (ERROR, "SPI_prepare for fully refunded coins failed ! \n");
      fully_refunded_coins_plan = SPI_saveplan(new_plan);
      if (fully_refunded_coins_plan == NULL)
        elog (ERROR, "SPI_saveplan for fully refunded coins failed ! \n");
    }

    int res = SPI_execute_plan(fully_refunded_coins_sql);
    if ( res != SPI_OK_SELECT)
      elog(ERROR, "Failed to execute subquery 4\n");
    SPITupleTable * tuptable = SPI_tuptable;
    TupleDesc tupdesc = tuptable->tupdesc;

    BYTEA coin_pub = SPI_getbinval(tuple, tupdesc, 1, &coin_pub_isnull);
    if (fees_plan == NULL)
    {
      const char *fees_sql =
        "SELECT "
        "  denom.fee_deposit_val AS fee_val, "
        "  denom.fee_deposit_frac AS fee_frac, "
        "  cs.deposit_serial_id "
        "FROM dep cs "
        "JOIN known_coins kc USING (coin_pub) "
        "JOIN denominations denom USING (denominations_serial) "
        "WHERE coin_pub NOT IN (SELECT coin_pub FROM fully_refunded_coins)";
      SPIPlanPtr new_plan =
        SPI_prepare(fees_sql, 0, NULL);
      if (new_plan == NULL)
      {
        elog(ERROR, "SPI_prepare for fees failed ! \n");
      }
      fees_plan = SPI_saveplan(new_plan);
      if (fees_plan == NULL)
      {
        elog(ERROR, "SPI_saveplan for fees failed ! \n");
      }
    }
  }
  int fees_ntuples;
  SPI_execute(fees_sql, true, 0);
  if (SPI_result_code() != SPI_OK_SELECT)
  {
    ereport(
            ERROR,
            (errcode(ERRCODE_INTERNAL_ERROR),
             errmsg("deposit fee query failed: error code %d \n", SPI_result_code())));
  }
  fees_ntuples = SPI_processed;

  if (fees_ntuples > 0)
  {
    for (i = 0; i < fees_ntuples; i++)
    {
      Datum fee_val_datum =
        SPI_getbinval(SPI_tuptable->vals[i], SPI_tuptable->tupdesc, 1, &fee_null);
      Datum fee_frac_datum =
        SPI_getbinval(SPI_tuptable->vals[i], SPI_tuptable->tupdesc, 2, &fee_null);
      Datum deposit_id_datum =
        SPI_getbinval(SPI_tuptable->vals[i], SPI_tuptable->tupdesc, 3, &deposit_null);
      if (!fee_null && !deposit_null)
      {
        int64 fee_val = DatumGetInt64(fee_val_datum);
        int32 fee_frac = DatumGetInt32(fee_frac_datum);
        int64 deposit_id = DatumGetInt64(deposit_id_datum);
        sum_fee_value += fee_val;
        sum_fee_fraction += fee_frac;
        char *insert_agg_sql =
          psprintf(
                   "INSERT INTO "
                   "aggregation_tracking(deposit_serial_id, wtid_raw)"
                   " VALUES (%lld, '%s')",
                   deposit_id, wtid_raw);
        SPI_execute(insert_agg_sql, false, 0);
      }
    }
  }

  TupleDesc tupdesc;
  SPITupleTable *tuptable = SPI_tuptable;
  HeapTuple tuple;
  Datum result;

  if (tuptable == NULL || SPI_processed != 1)
  {
    ereport(
            ERROR,
            (errcode(ERRCODE_INTERNAL_ERROR),
             errmsg("Unexpected result \n")));
  }
  tupdesc = SPI_tuptable->tupdesc;
  tuple = SPI_tuptable->vals[0];
  result = HeapTupleGetDatum(tuple);

  TupleDesc result_desc = CreateTemplateTupleDesc(6, false);
  TupleDescInitEntry(result_desc, (AttrNumber) 1, "sum_deposit_value", INT8OID, -1, 0);
  TupleDescInitEntry(result_desc, (AttrNumber) 2, "sum_deposit_fraction", INT4OID, -1, 0);
  TupleDescInitEntry(result_desc, (AttrNumber) 3, "sum_refund_value", INT8OID, -1, 0);
  TupleDescInitEntry(result_desc, (AttrNumber) 4, "sum_refund_fraction", INT4OID, -1, 0);
  TupleDescInitEntry(result_desc, (AttrNumber) 5, "sum_fee_value", INT8OID, -1, 0);
  TupleDescInitEntry(result_desc, (AttrNumber) 6, "sum_fee_fraction", INT4OID, -1, 0);

  int ret = SPI_prepare(sql, 4, argtypes);
  if (ret != SPI_OK_PREPARE)
  {
    elog(ERROR, "Failed to prepare statement: %s \n", sql);
  }

  ret = SPI_execute_plan(plan, args, nulls, true, 0);
  if (ret != SPI_OK_SELECT)
  {
    elog(ERROR, "Failed to execute statement: %s \n", sql);
  }

  if (SPI_processed > 0)
  {
    HeapTuple tuple;
    Datum values[6];
    bool nulls[6] = {false};
    values[0] =
      SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &nulls[0]);
    values[1] =
      SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 2, &nulls[1]);
    values[2] =
      SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 3, &nulls[2]);
    values[3] =
      SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 4, &nulls[3]);
    values[4] =
      SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 5, &nulls[4]);
    values[5] =
      SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 6, &nulls[5]);
    tuple = heap_form_tuple(result_desc, values, nulls);
    PG_RETURN_DATUM(HeapTupleGetDatum(tuple));
  }
  SPI_finish();

  PG_RETURN_NULL();
}



