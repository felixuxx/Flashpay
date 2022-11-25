/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file exchangedb/pg_batch_reserves_in_insert.c
 * @brief Implementation of the reserves_in_insert function for Postgres
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_batch_reserves_in_insert.h"
#include "pg_helper.h"
#include "pg_start.h"
#include "pg_rollback.h"
#include "pg_start_read_committed.h"
#include "pg_commit.h"
#include "pg_reserves_get.h"
#include "pg_reserves_update.h"
#include "pg_setup_wire_target.h"
#include "pg_event_notify.h"
#include "pg_preflight.h"

/**
 * Generate event notification for the reserve change.
 *
 * @param reserve_pub reserve to notfiy on
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


enum GNUNET_DB_QueryStatus
TEH_PG_batch2_reserves_in_insert (void *cls,
                                 const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
                                 unsigned int reserves_length,
                                 enum GNUNET_DB_QueryStatus *results)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs1;
  struct GNUNET_TIME_Timestamp expiry;
  struct GNUNET_TIME_Timestamp gc;
  struct TALER_PaytoHashP h_payto;
  uint64_t reserve_uuid;
  bool conflicted;
  bool transaction_duplicate;
  bool need_update = false;
  struct GNUNET_TIME_Timestamp reserve_expiration
    = GNUNET_TIME_relative_to_timestamp (pg->idle_reserve_expiration_time);
  bool conflicts[reserves_length];
  char *notify_s[reserves_length];

  if (GNUNET_OK !=
      TEH_PG_preflight (pg))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  PREPARE (pg,
           "reserve_create",
           "SELECT "
           "out_reserve_found AS conflicted"
           ",transaction_duplicate"
           ",ruuid AS reserve_uuid"
           " FROM batch2_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17);");
  expiry = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (reserves->execution_time.abs_time,
                              pg->idle_reserve_expiration_time));
  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                              pg->legal_reserve_expiration_time));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating reserve %s with expiration in %s\n",
              TALER_B2S (&(reserves->reserve_pub)),
              GNUNET_STRINGS_relative_time_to_string (
                pg->idle_reserve_expiration_time,
                GNUNET_NO));

  {
    if (GNUNET_OK !=
        TEH_PG_start_read_committed(pg,
                                   "READ_COMMITED"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  /* Optimistically assume this is a new reserve, create balance for the first
     time; we do this before adding the actual transaction to "reserves_in",
     as for a new reserve it can't be a duplicate 'add' operation, and as
     the 'add' operation needs the reserve entry as a foreign key. */
  for (unsigned int i=0;i<reserves_length;i++)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];
    notify_s[i] = compute_notify_on_reserve (&reserve->reserve_pub);
  }

  for (unsigned int i=0;i<reserves_length;i++)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserve->reserve_pub),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_uint64 (&reserve->wire_reference),
      TALER_PQ_query_param_amount (&reserve->balance),
      GNUNET_PQ_query_param_string (reserve->exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserve->execution_time),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserve->sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),
      GNUNET_PQ_query_param_string (notify_s[i]),
      GNUNET_PQ_query_param_auto_from_type (&reserve->reserve_pub),
      TALER_PQ_query_param_amount (&reserve->balance),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_end
    };

    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_bool ("conflicted",
                                  &conflicted),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate",
                                  &transaction_duplicate),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &reserve_uuid),
      GNUNET_PQ_result_spec_end
    };

    TALER_payto_hash (reserve->sender_account_details,
                      &h_payto);

    /* Note: query uses 'on conflict do nothing' */
    qs1 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "reserve_create",
                                                    params,
                                                    rs);

    if (qs1 < 0)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to create reserves (%d)\n",
                  qs1);
      return qs1;
    }
   GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs1);
   results[i] = (transaction_duplicate)
      ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
      : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
   conflicts[i] = conflicted;
   //   fprintf(stdout, "%d", conflicts[i]);
   if (!conflicts[i] && transaction_duplicate)
   {
     GNUNET_break (0);
     TEH_PG_rollback (pg);
     return GNUNET_DB_STATUS_HARD_ERROR;
   }
   need_update |= conflicted;
  }
  // commit
  {
    enum GNUNET_DB_QueryStatus cs;

    cs = TEH_PG_commit (pg);
    if (cs < 0)
      return cs;
  }

  if (!need_update)
    goto exit;
  // begin serializable
  {
    if (GNUNET_OK !=
        TEH_PG_start(pg,
                     "reserve-insert-continued"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  enum GNUNET_DB_QueryStatus qs2;
  PREPARE (pg,
           "reserves_in_add_transaction",
           "SELECT batch_reserves_update"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9);");
  for (unsigned int i=0;i<reserves_length;i++)
  {
    if (! conflicts[i])
      continue;
    {
      const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (&reserve->reserve_pub),
        GNUNET_PQ_query_param_timestamp (&expiry),
        GNUNET_PQ_query_param_uint64 (&reserve->wire_reference),
        TALER_PQ_query_param_amount (&reserve->balance),
        GNUNET_PQ_query_param_string (reserve->exchange_account_name),
        GNUNET_PQ_query_param_bool (conflicted),
        GNUNET_PQ_query_param_auto_from_type (&h_payto),
        GNUNET_PQ_query_param_string (notify_s[i]),
        GNUNET_PQ_query_param_end
      };

      qs2 = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                "reserves_in_add_transaction",
                                                params);
      if (qs2<0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves (%d)\n",
                    qs2);
        return qs2;
      }
    }
  }
  {
    enum GNUNET_DB_QueryStatus cs;

    cs = TEH_PG_commit (pg);
    if (cs < 0)
      return cs;
  }

 exit:
  for (unsigned int i=0;i<reserves_length;i++)
    GNUNET_free (notify_s[i]);

  return reserves_length;
}
