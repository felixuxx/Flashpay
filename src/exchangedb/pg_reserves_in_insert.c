/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @file exchangedb/pg_reserves_in_insert.c
 * @brief Implementation of the reserves_in_insert function for Postgres
 * @author Christian Grothoff
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_reserves_in_insert.h"
#include "pg_helper.h"
#include "pg_start.h"
#include "pg_start_read_committed.h"
#include "pg_commit.h"
#include "pg_preflight.h"
#include "pg_rollback.h"
#include "pg_reserves_get.h"
#include "pg_reserves_update.h"
#include "pg_setup_wire_target.h"
#include "pg_event_notify.h"


/**
 * Generate event notification for the reserve change.
 *
 * @param reserve_pub reserve to notfiy on
 * @return string to pass to postgres for the notification
 */
static char *
compute_notify_on_reserve (const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct TALER_ReserveEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_RESERVE_INCOMING),
    .reserve_pub = *reserve_pub
  };

  return GNUNET_PG_get_event_notify_channel (&rep.header);
}


/**
 * Record we keep per reserve to process.
 */
struct ReserveRecord
{
  /**
   * Details about reserve to insert (input).
   */
  const struct TALER_EXCHANGEDB_ReserveInInfo *reserve;

  /**
   * Hash of the payto URI in @e reserve.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Notification to trigger on the reserve (input).
   */
  char *notify_s;

  /**
   * Set to UUID of the reserve (output);
   */
  uint64_t reserve_uuid;

  /**
   * Set to true if the transaction was an exact duplicate (output).
   */
  bool transaction_duplicate;

  /**
   * Set to true if the transaction conflicted with an existing reserve (output)
   * and needs to be re-done with an UPDATE.
   */
  bool conflicts;
};


/**
 * Generate the SQL parameters to insert the record @a rr at
 * index @a index
 */
#define RR_QUERY_PARAM(rr,index) \
  GNUNET_PQ_query_param_auto_from_type (rr[index].reserve->reserve_pub),    \
  GNUNET_PQ_query_param_uint64 (&rr[index].reserve->wire_reference),        \
  TALER_PQ_query_param_amount_tuple (pg->conn, rr[index].reserve->balance), \
  GNUNET_PQ_query_param_string (rr[index].reserve->exchange_account_name),  \
  GNUNET_PQ_query_param_timestamp (&rr[index].reserve->execution_time),     \
  GNUNET_PQ_query_param_auto_from_type (&rr[index].h_payto),                \
  GNUNET_PQ_query_param_string (rr[index].reserve->sender_account_details), \
  GNUNET_PQ_query_param_string (rr[index].notify_s)


/**
 * Generate the SQL parameters to obtain results for record @a rr at
 * index @a index
 */
#define RR_RESULT_PARAM(rr,index) \
  GNUNET_PQ_result_spec_bool ("transaction_duplicate" TALER_S (index), \
                              &rr[index].transaction_duplicate),       \
  GNUNET_PQ_result_spec_allow_null ( \
    GNUNET_PQ_result_spec_uint64 ("reserve_uuid" TALER_S (index),        \
                                  &rr[index].reserve_uuid),              \
    &rr[index].conflicts)


/**
 * Insert 1 reserve record @a rr into the database.
 *
 * @param pg database context
 * @param gc gc timestamp to use
 * @param reserve_expiration expiration time to use
 * @param[in,out] rr array of reserve details to use and update
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
insert1 (struct PostgresClosure *pg,
         struct GNUNET_TIME_Timestamp gc,
         struct GNUNET_TIME_Timestamp reserve_expiration,
         struct ReserveRecord *rr)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    RR_QUERY_PARAM (rr, 0),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    RR_RESULT_PARAM (rr, 0),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch1_reserve_create",
           "SELECT "
           " transaction_duplicate0 AS transaction_duplicate0"
           ",ruuid0 AS reserve_uuid0"
           " FROM exchange_do_batch_reserves_in_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch1_reserve_create",
                                                 params,
                                                 rs);
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to create reserves 1(%d)\n",
                qs);
    return qs;
  }
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  if ((! rr[0].conflicts) && rr[0].transaction_duplicate)
  {
    GNUNET_break (0);
    TEH_PG_rollback (pg);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * Insert 2 reserve records @a rr into the database.
 *
 * @param pg database context
 * @param gc gc timestamp to use
 * @param reserve_expiration expiration time to use
 * @param[in,out] rr array of reserve details to use and update
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
insert2 (struct PostgresClosure *pg,
         struct GNUNET_TIME_Timestamp gc,
         struct GNUNET_TIME_Timestamp reserve_expiration,
         struct ReserveRecord *rr)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    RR_QUERY_PARAM (rr, 0),
    RR_QUERY_PARAM (rr, 1),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    RR_RESULT_PARAM (rr, 0),
    RR_RESULT_PARAM (rr, 1),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch2_reserve_create",
           "SELECT"
           " transaction_duplicate0"
           ",transaction_duplicate1"
           ",ruuid0 AS reserve_uuid0"
           ",ruuid1 AS reserve_uuid1"
           " FROM exchange_do_batch2_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch2_reserve_create",
                                                 params,
                                                 rs);
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to create reserves 2(%d)\n",
                qs);
    return qs;
  }
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  for (unsigned int i = 0; i<2; i++)
  {
    if ((! rr[i].conflicts) && (rr[i].transaction_duplicate))
    {
      GNUNET_break (0);
      TEH_PG_rollback (pg);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return qs;
}


/**
 * Insert 4 reserve records @a rr into the database.
 *
 * @param pg database context
 * @param gc gc timestamp to use
 * @param reserve_expiration expiration time to use
 * @param[in,out] rr array of reserve details to use and update
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
insert4 (struct PostgresClosure *pg,
         struct GNUNET_TIME_Timestamp gc,
         struct GNUNET_TIME_Timestamp reserve_expiration,
         struct ReserveRecord *rr)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    RR_QUERY_PARAM (rr, 0),
    RR_QUERY_PARAM (rr, 1),
    RR_QUERY_PARAM (rr, 2),
    RR_QUERY_PARAM (rr, 3),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    RR_RESULT_PARAM (rr, 0),
    RR_RESULT_PARAM (rr, 1),
    RR_RESULT_PARAM (rr, 2),
    RR_RESULT_PARAM (rr, 3),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch4_reserve_create",
           "SELECT"
           " transaction_duplicate0"
           ",transaction_duplicate1"
           ",transaction_duplicate2"
           ",transaction_duplicate3"
           ",ruuid0 AS reserve_uuid0"
           ",ruuid1 AS reserve_uuid1"
           ",ruuid2 AS reserve_uuid2"
           ",ruuid3 AS reserve_uuid3"
           " FROM exchange_do_batch4_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch4_reserve_create",
                                                 params,
                                                 rs);
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to create reserves4 (%d)\n",
                qs);
    return qs;
  }

  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  for (unsigned int i = 0; i<4; i++)
  {
    if ((! rr[i].conflicts) && (rr[i].transaction_duplicate))
    {
      GNUNET_break (0);
      TEH_PG_rollback (pg);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return qs;
}


/**
 * Insert 8 reserve records @a rr into the database.
 *
 * @param pg database context
 * @param gc gc timestamp to use
 * @param reserve_expiration expiration time to use
 * @param[in,out] rr array of reserve details to use and update
 * @return database transaction status
 */
static enum GNUNET_DB_QueryStatus
insert8 (struct PostgresClosure *pg,
         struct GNUNET_TIME_Timestamp gc,
         struct GNUNET_TIME_Timestamp reserve_expiration,
         struct ReserveRecord *rr)
{
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_timestamp (&gc),
    GNUNET_PQ_query_param_timestamp (&reserve_expiration),
    RR_QUERY_PARAM (rr, 0),
    RR_QUERY_PARAM (rr, 1),
    RR_QUERY_PARAM (rr, 2),
    RR_QUERY_PARAM (rr, 3),
    RR_QUERY_PARAM (rr, 4),
    RR_QUERY_PARAM (rr, 5),
    RR_QUERY_PARAM (rr, 6),
    RR_QUERY_PARAM (rr, 7),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    RR_RESULT_PARAM (rr, 0),
    RR_RESULT_PARAM (rr, 1),
    RR_RESULT_PARAM (rr, 2),
    RR_RESULT_PARAM (rr, 3),
    RR_RESULT_PARAM (rr, 4),
    RR_RESULT_PARAM (rr, 5),
    RR_RESULT_PARAM (rr, 6),
    RR_RESULT_PARAM (rr, 7),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch8_reserve_create",
           "SELECT"
           " transaction_duplicate0"
           ",transaction_duplicate1"
           ",transaction_duplicate2"
           ",transaction_duplicate3"
           ",transaction_duplicate4"
           ",transaction_duplicate5"
           ",transaction_duplicate6"
           ",transaction_duplicate7"
           ",ruuid0 AS reserve_uuid0"
           ",ruuid1 AS reserve_uuid1"
           ",ruuid2 AS reserve_uuid2"
           ",ruuid3 AS reserve_uuid3"
           ",ruuid4 AS reserve_uuid4"
           ",ruuid5 AS reserve_uuid5"
           ",ruuid6 AS reserve_uuid6"
           ",ruuid7 AS reserve_uuid7"
           " FROM exchange_do_batch8_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39, $40, $41,$42,$43,$44,$45,$46,$47,$48,$49,$50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$60,$61,$62,$63,$64,$65,$66);");

  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch8_reserve_create",
                                                 params,
                                                 rs);
  if (qs < 0)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to create reserves8 (%d)\n",
                qs);
    return qs;
  }

  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs);
  for (unsigned int i = 0; i<8; i++)
  {
    if ((! rr[i].conflicts) && (rr[i].transaction_duplicate))
    {
      GNUNET_break (0);
      TEH_PG_rollback (pg);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return qs;
}


static enum GNUNET_DB_QueryStatus
transact (
  struct PostgresClosure *pg,
  struct ReserveRecord *rr,
  unsigned int reserves_length,
  unsigned int batch_size,
  enum GNUNET_DB_QueryStatus *results)
{
  struct GNUNET_TIME_Timestamp reserve_expiration
    = GNUNET_TIME_relative_to_timestamp (pg->idle_reserve_expiration_time);
  struct GNUNET_TIME_Timestamp gc
    = GNUNET_TIME_relative_to_timestamp (pg->legal_reserve_expiration_time);
  bool need_update = false;

  if (GNUNET_OK !=
      TEH_PG_preflight (pg))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (GNUNET_OK !=
      TEH_PG_start_read_committed (pg,
                                   "READ_COMMITED"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  {
    unsigned int i = 0;

    while (i < reserves_length)
    {
      enum GNUNET_DB_QueryStatus qs;
      enum GNUNET_DB_QueryStatus
      (*fun)(struct PostgresClosure *pg,
             struct GNUNET_TIME_Timestamp gc,
             struct GNUNET_TIME_Timestamp reserve_expiration,
             struct ReserveRecord *rr);
      unsigned int lim;
      unsigned int bs;

      bs = GNUNET_MIN (batch_size,
                       reserves_length - i);
      switch (bs)
      {
      case 7:
      case 6:
      case 5:
      case 4:
        fun = &insert4;
        lim = 4;
        break;
      case 3:
      case 2:
        fun = &insert2;
        lim = 2;
        break;
      case 1:
        fun = &insert1;
        lim = 1;
        break;
      case 0:
        GNUNET_assert (0);
        break;
      default:
        fun = insert8;
        lim = 8;
        break;
      }

      qs = fun (pg,
                gc,
                reserve_expiration,
                &rr[i]);
      if (qs < 0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to create reserve batch_%u (%d)\n",
                    lim,
                    qs);
        results[i] = qs;
        return qs;
      }
      for (unsigned int j = 0; j<lim; j++)
      {
        need_update |= rr[i + j].conflicts;
        results[i + j] = rr[i + j].transaction_duplicate
          ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
          : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
      }
      i += lim;
      continue;
    } /* end while */
  } /* end scope i */

  {
    enum GNUNET_DB_QueryStatus cs;

    cs = TEH_PG_commit (pg);
    if (cs < 0)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to commit\n");
      return cs;
    }
  }

  if (! need_update)
    return reserves_length;

  if (GNUNET_OK !=
      TEH_PG_start (pg,
                    "reserve-insert-continued"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  PREPARE (pg,
           "reserves_update",
           "SELECT"
           " out_duplicate AS duplicate "
           "FROM exchange_do_batch_reserves_update"
           " ($1,$2,$3,$4,$5,$6,$7,$8);");
  for (unsigned int i = 0; i<reserves_length; i++)
  {
    if (! rr[i].conflicts)
      continue;
    {
      bool duplicate;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (rr[i].reserve->reserve_pub),
        GNUNET_PQ_query_param_timestamp (&reserve_expiration),
        GNUNET_PQ_query_param_uint64 (&rr[i].reserve->wire_reference),
        TALER_PQ_query_param_amount_tuple (pg->conn,
                                           rr[i].reserve->balance),
        GNUNET_PQ_query_param_string (rr[i].reserve->exchange_account_name),
        GNUNET_PQ_query_param_auto_from_type (&rr[i].h_payto),
        GNUNET_PQ_query_param_string (rr[i].notify_s),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_bool ("duplicate",
                                    &duplicate),
        GNUNET_PQ_result_spec_end
      };
      enum GNUNET_DB_QueryStatus qs;

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "reserves_update",
                                                     params,
                                                     rs);
      if (qs < 0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves (%d)\n",
                    qs);
        results[i] = qs;
        return qs;
      }
      results[i] = duplicate
          ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
          : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    }
  }

  {
    enum GNUNET_DB_QueryStatus cs = TEH_PG_commit (pg);

    if (0 > cs)
      return cs;
  }
  return reserves_length;
}


enum GNUNET_DB_QueryStatus
TEH_PG_reserves_in_insert (
  void *cls,
  const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
  unsigned int reserves_length,
  unsigned int batch_size,
  enum GNUNET_DB_QueryStatus *results)
{
  struct PostgresClosure *pg = cls;
  struct ReserveRecord rrs[reserves_length];
  enum GNUNET_DB_QueryStatus qs;

  for (unsigned int i = 0; i<reserves_length; i++)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];
    struct ReserveRecord *rr = &rrs[i];

    rr->reserve = reserve;
    TALER_payto_hash (reserves->sender_account_details,
                      &rr->h_payto);
    rr->notify_s = compute_notify_on_reserve (reserve->reserve_pub);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Creating reserve %s with expiration in %s\n",
                TALER_B2S (&reserve->reserve_pub),
                GNUNET_STRINGS_relative_time_to_string (
                  pg->idle_reserve_expiration_time,
                  false));
  }
  qs = transact (pg,
                 rrs,
                 reserves_length,
                 batch_size,
                 results);
  GNUNET_PQ_event_do_poll (pg->conn);
  for (unsigned int i = 0; i<reserves_length; i++)
    GNUNET_free (rrs[i].notify_s);
  return qs;
}


#if 0

/**
 * Closure for our helper_cb()
 */
struct Context
{
  /**
   * Array of reserve UUIDs to initialize.
   */
  uint64_t *reserve_uuids;

  /**
   * Array with entries set to 'true' for duplicate transactions.
   */
  bool *transaction_duplicates;

  /**
   * Array with entries set to 'true' for rows with conflicts.
   */
  bool *conflicts;

  /**
   * Set to #GNUNET_SYSERR on failures.
   */
  struct GNUNET_GenericReturnValue status;

  /**
   * Single value (no array) set to true if we need
   * to follow-up with an update.
   */
  bool *needs_update;
};


/**
 * Helper function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct Context *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
helper_cb (void *cls,
           PGresult *result,
           unsigned int num_results)
{
  struct Context *ctx = cls;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_bool (
        "transaction_duplicate",
        &ctx->transaction_duplicates[i]),
      GNUNET_PQ_result_spec_allow_null (
        GNUNET_PQ_result_spec_uint64 ("ruuid",
                                      &ctx->reserve_uuids[i]),
        &ctx->conflicts[i]),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  i))
    {
      GNUNET_break (0);
      ctx->status = GNUNET_SYSERR;
      return;
    }
    *ctx->need_update |= ctx->conflicts[i];
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_reserves_in_insertN (
  void *cls,
  const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
  unsigned int reserves_length,
  enum GNUNET_DB_QueryStatus *results)
{
  struct PostgresClosure *pg = cls;
  struct TALER_PaytoHashP h_paytos[GNUNET_NZL (reserves_length)];
  char *notify_s[GNUNET_NZL (reserves_length)];
  struct TALER_ReservePublicKeyP *reserve_pubs[GNUNET_NZL (reserves_length)];
  struct TALER_Amount *balances[GNUNET_NZL (reserves_length)];
  struct GNUNET_TIME_Timestamp execution_times[GNUNET_NZL (reserves_length)];
  const char *sender_account_details[GNUNET_NZL (reserves_length)];
  const char *exchange_account_names[GNUNET_NZL (reserves_length)];
  uint64_t wire_references[GNUNET_NZL (reserves_length)];
  uint64_t reserve_uuids[GNUNET_NZL (reserves_length)];
  bool transaction_duplicates[GNUNET_NZL (reserves_length)];
  bool conflicts[GNUNET_NZL (reserves_length)];
  struct GNUNET_TIME_Timestamp reserve_expiration
    = GNUNET_TIME_relative_to_timestamp (pg->idle_reserve_expiration_time);
  struct GNUNET_TIME_Timestamp gc
    = GNUNET_TIME_relative_to_timestamp (pg->legal_reserve_expiration_time);
  bool needs_update = false;
  enum GNUNET_DB_QueryStatus qs;

  for (unsigned int i = 0; i<reserves_length; i++)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];

    TALER_payto_hash (reserve->sender_account_details,
                      &h_paytos[i]);
    notify_s[i] = compute_notify_on_reserve (reserve->reserve_pub);
    reserve_pubs[i] = &reserve->reserve_pub;
    balances[i] = &reserve->balance;
    execution_times[i] = reserve->execution_time;
    sender_account_details[i] = reserve->sender_account_details;
    exchange_account_names[i] = reserve->exchange_account_name;
    wire_references[i] = reserve->wire_reference;
  }

  /* NOTE: kind-of pointless to explicitly start a transaction here... */
  if (GNUNET_OK !=
      TEH_PG_preflight (pg))
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
    goto finished;
  }

  if (GNUNET_OK !=
      TEH_PG_start_read_committed (pg,
                                   "READ_COMMITED"))
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
    goto finished;
  }

  PREPARE (pg,
           "reserves_insert_with_array",
           "SELECT"
           " transaction_duplicate"
           ",ruuid"
           "FROM exchange_do_array_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);");
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),
      GNUNET_PQ_query_param_array_auto_from_type (reserves_length,
                                                  reserve_pubs,
                                                  pg->conn),
      GNUNET_PQ_query_param_array_uint64 (reserves_length,
                                          wire_references,
                                          pg->conn),
      TALER_PQ_query_param_array_amount (reserves_length,
                                         balances,
                                         pg->conn),
      GNUNET_PQ_query_param_array_string (reserves_length,
                                          exchange_account_names,
                                          pg->conn),
      GNUNET_PQ_query_param_array_timestamp (reserves_length,
                                             execution_times,
                                             pg->conn),
      GNUNET_PQ_query_param_array_bytes_same_size_cont_auto (
        reserves_length,
        h_paytos,
        sizeof (struct GNUNET_PaytoHashP),
        pg->conn),
      GNUNET_PQ_query_param_array_string (reserves_length,
                                          sender_account_details,
                                          pg->conn),
      GNUNET_PQ_query_param_array_string (reserves_length,
                                          notify_s,
                                          pg->conn),
      GNUNET_PQ_query_param_end
    };
    struct Context ctx = {
      .reserve_uuids = reserve_uuids,
      .transaction_duplicates = transaction_duplicates,
      .conflicts = conflicts,
      .needs_update = &needs_update,
      .status = GNUNET_OK
    };

    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "reserves_insert_with_array",
                                               params,
                                               &multi_res,
                                               &ctx);
    if ( (qs < 0) ||
         (GNUNET_OK != ctx.status) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to insert into reserves (%d)\n",
                  qs);
      goto finished;
    }
  }

  {
    enum GNUNET_DB_QueryStatus cs;

    cs = TEH_PG_commit (pg);
    if (cs < 0)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to commit\n");
      qs = cs;
      goto finished;
    }
  }
  for (unsigned int i = 0; i<reserves_length; i++)
  {
    results[i] = transaction_duplicates[i]
      ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
      : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }

  if (! need_update)
  {
    qs = reserves_length;
    goto finished;
  }
  if (GNUNET_OK !=
      TEH_PG_start (pg,
                    "reserve-insert-continued"))
  {
    GNUNET_break (0);
    qs = GNUNET_DB_STATUS_HARD_ERROR;
    goto finished;
  }

  for (unsigned int i = 0; i<reserves_length; i++)
  {
    if (! conflicts[i])
      continue;
    {
      bool duplicate;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (reserve_pubs[i]),
        GNUNET_PQ_query_param_timestamp (&reserve_expiration),
        GNUNET_PQ_query_param_uint64 (&wire_reference[i]),
        TALER_PQ_query_param_amount_tuple (pg->conn,
                                           balances[i]),
        GNUNET_PQ_query_param_string (exchange_account_names[i]),
        GNUNET_PQ_query_param_auto_from_type (h_paytos[i]),
        GNUNET_PQ_query_param_string (notify_s[i]),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_bool ("duplicate",
                                    &duplicate),
        GNUNET_PQ_result_spec_end
      };
      enum GNUNET_DB_QueryStatus qs;

      qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                     "reserves_update",
                                                     params,
                                                     rs);
      if (qs < 0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves (%d)\n",
                    qs);
        results[i] = qs;
        goto finished;
      }
      results[i] = duplicate
          ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
          : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    }
  }
finished:
  GNUNET_PQ_event_do_poll (pg->conn);
  for (unsigned int i = 0; i<reserves_length; i++)
    GNUNET_free (rrs[i].notify_s);
  return qs;
}


#endif
