/*
   This file is part of TALER
   Copyright (C) 2022-2024 Taler Systems SA

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

  return GNUNET_PQ_get_event_notify_channel (&rep.header);
}


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
  enum GNUNET_GenericReturnValue status;

  /**
   * Single value (no array) set to true if we need
   * to follow-up with an update.
   */
  bool needs_update;
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
    if (! ctx->transaction_duplicates[i])
      ctx->needs_update |= ctx->conflicts[i];
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_reserves_in_insert (
  void *cls,
  const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
  unsigned int reserves_length,
  enum GNUNET_DB_QueryStatus *results)
{
  struct PostgresClosure *pg = cls;
  unsigned int dups = 0;

  struct TALER_FullPaytoHashP h_full_paytos[
    GNUNET_NZL (reserves_length)];
  struct TALER_NormalizedPaytoHashP h_normalized_paytos[
    GNUNET_NZL (reserves_length)];
  char *notify_s[GNUNET_NZL (reserves_length)];
  struct TALER_ReservePublicKeyP reserve_pubs[GNUNET_NZL (reserves_length)];
  struct TALER_Amount balances[GNUNET_NZL (reserves_length)];
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
  enum GNUNET_DB_QueryStatus qs;
  bool need_update;

  for (unsigned int i = 0; i<reserves_length; i++)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];

    TALER_full_payto_hash (reserve->sender_account_details,
                           &h_full_paytos[i]);
    TALER_full_payto_normalize_and_hash (reserve->sender_account_details,
                                         &h_normalized_paytos[i]);
    notify_s[i] = compute_notify_on_reserve (reserve->reserve_pub);
    reserve_pubs[i] = *reserve->reserve_pub;
    balances[i] = *reserve->balance;
    execution_times[i] = reserve->execution_time;
    sender_account_details[i] = reserve->sender_account_details.full_payto;
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
           " FROM exchange_do_array_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);");
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
      TALER_PQ_query_param_array_amount (
        reserves_length,
        balances,
        pg->conn),
      GNUNET_PQ_query_param_array_ptrs_string (
        reserves_length,
        (const char **) exchange_account_names,
        pg->conn),
      GNUNET_PQ_query_param_array_timestamp (
        reserves_length,
        execution_times,
        pg->conn),
      GNUNET_PQ_query_param_array_auto_from_type (
        reserves_length,
        h_full_paytos,
        pg->conn),
      GNUNET_PQ_query_param_array_auto_from_type (
        reserves_length,
        h_normalized_paytos,
        pg->conn),
      GNUNET_PQ_query_param_array_ptrs_string (
        reserves_length,
        (const char **) sender_account_details,
        pg->conn),
      GNUNET_PQ_query_param_array_ptrs_string (
        reserves_length,
        (const char **) notify_s,
        pg->conn),
      GNUNET_PQ_query_param_end
    };
    struct Context ctx = {
      .reserve_uuids = reserve_uuids,
      .transaction_duplicates = transaction_duplicates,
      .conflicts = conflicts,
      .needs_update = false,
      .status = GNUNET_OK
    };

    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               "reserves_insert_with_array",
                                               params,
                                               &helper_cb,
                                               &ctx);
    GNUNET_PQ_cleanup_query_params_closures (params);
    if ( (qs < 0) ||
         (GNUNET_OK != ctx.status) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to insert into reserves (%d)\n",
                  qs);
      goto finished;
    }
    need_update = ctx.needs_update;
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
    if (transaction_duplicates[i])
      dups++;
    results[i] = transaction_duplicates[i]
      ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
      : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }

  if (! need_update)
  {
    qs = reserves_length;
    goto finished;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Reserve update needed for some reserves in the batch\n");
  PREPARE (pg,
           "reserves_update",
           "SELECT"
           " out_duplicate AS duplicate "
           "FROM exchange_do_batch_reserves_update"
           " ($1,$2,$3,$4,$5,$6,$7);");

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
    if (transaction_duplicates[i])
      continue;
    if (! conflicts[i])
      continue;
    {
      bool duplicate;
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (&reserve_pubs[i]),
        GNUNET_PQ_query_param_timestamp (&reserve_expiration),
        GNUNET_PQ_query_param_uint64 (&wire_references[i]),
        TALER_PQ_query_param_amount (pg->conn,
                                     &balances[i]),
        GNUNET_PQ_query_param_string (exchange_account_names[i]),
        GNUNET_PQ_query_param_auto_from_type (&h_paytos[i]),
        GNUNET_PQ_query_param_string (notify_s[i]),
        GNUNET_PQ_query_param_end
      };
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_bool ("duplicate",
                                    &duplicate),
        GNUNET_PQ_result_spec_end
      };
      enum GNUNET_DB_QueryStatus qsi;

      qsi = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                      "reserves_update",
                                                      params,
                                                      rs);
      if (qsi < 0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves (%d)\n",
                    qsi);
        results[i] = qsi;
        goto finished;
      }
      results[i] = duplicate
          ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
          : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
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
finished:
  for (unsigned int i = 0; i<reserves_length; i++)
    GNUNET_free (notify_s[i]);
  if (qs < 0)
    return qs;
  GNUNET_PQ_event_do_poll (pg->conn);
  if (0 != dups)
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "%u/%u duplicates among incoming transactions. Try increasing WIREWATCH_IDLE_SLEEP_INTERVAL in the [exchange] configuration section (if this happens a lot).\n",
                dups,
                reserves_length);
  return qs;
}
