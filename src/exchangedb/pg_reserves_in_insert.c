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
 * @file exchangedb/pg_reserves_in_insert.c
 * @brief Implementation of the reserves_in_insert function for Postgres
 * @author Christian Grothoff
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
#include "pg_reserves_get.h"
#include "pg_reserves_update.h"
#include "pg_setup_wire_target.h"
#include "pg_event_notify.h"
/**
 * Generate event notification for the reserve
 * change.
 *
 * @param pg plugin state
 * @param reserve_pub reserve to notfiy on
 */

static void
notify_on_reserve (struct PostgresClosure *pg,
                   const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct TALER_ReserveEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_RESERVE_INCOMING),
    .reserve_pub = *reserve_pub
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Notifying on reserve!\n");
  TEH_PG_event_notify (pg,
                         &rep.header,
                         NULL,
                         0);
}

enum GNUNET_DB_QueryStatus
TEH_PG_reserves_in_insert (void *cls,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Timestamp execution_time,
                             const char *sender_account_details,
                             const char *exchange_account_section,
                             uint64_t wire_ref)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs1;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Timestamp expiry;
  struct GNUNET_TIME_Timestamp gc;
  uint64_t reserve_uuid;

  reserve.pub = *reserve_pub;
  expiry = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (execution_time.abs_time,
                              pg->idle_reserve_expiration_time));
  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                              pg->legal_reserve_expiration_time));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating reserve %s with expiration in %s\n",
              TALER_B2S (reserve_pub),
              GNUNET_STRINGS_relative_time_to_string (
                pg->idle_reserve_expiration_time,
                GNUNET_NO));
  /* Optimistically assume this is a new reserve, create balance for the first
     time; we do this before adding the actual transaction to "reserves_in",
     as for a new reserve it can't be a duplicate 'add' operation, and as
     the 'add' operation needs the reserve entry as a foreign key. */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve_pub),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_end
    };
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &reserve_uuid),
      GNUNET_PQ_result_spec_end
    };

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    /* Note: query uses 'on conflict do nothing' */



    PREPARE (pg,
             "reserve_create",
             "INSERT INTO reserves "
             "(reserve_pub"
             ",current_balance_val"
             ",current_balance_frac"
             ",expiration_date"
             ",gc_date"
             ") VALUES "
             "($1, $2, $3, $4, $5)"
             " ON CONFLICT DO NOTHING"
             " RETURNING reserve_uuid;");

    qs1 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "reserve_create",
                                                    params,
                                                    rs);
    if (qs1 < 0)
      return qs1;
  }

  /* Create new incoming transaction, "ON CONFLICT DO NOTHING"
     is again used to guard against duplicates. */
  {
    enum GNUNET_DB_QueryStatus qs2;
    enum GNUNET_DB_QueryStatus qs3;
    struct TALER_PaytoHashP h_payto;

    qs3 = TEH_PG_setup_wire_target (pg,
                             sender_account_details,
                             &h_payto);
    if (qs3 < 0)
      return qs3;
    /* We do not have the UUID, so insert by public key */
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserve.pub),
      GNUNET_PQ_query_param_uint64 (&wire_ref),
      TALER_PQ_query_param_amount (balance),
      GNUNET_PQ_query_param_string (exchange_account_section),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_timestamp (&execution_time),
      GNUNET_PQ_query_param_end
    };


    PREPARE (pg,
             "reserves_in_add_transaction",
             "INSERT INTO reserves_in "
             "(reserve_pub"
             ",wire_reference"
             ",credit_val"
             ",credit_frac"
             ",exchange_account_section"
             ",wire_source_h_payto"
             ",execution_date"
             ") VALUES ($1, $2, $3, $4, $5, $6, $7)"
             " ON CONFLICT DO NOTHING;");
    qs2 = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                              "reserves_in_add_transaction",
                                              params);
    /* qs2 could be 0 as statement used 'ON CONFLICT DO NOTHING' */
    if (0 >= qs2)
    {
      if ( (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs2) &&
           (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs1) )
      {
        /* Conflict for the transaction, but the reserve was
           just now created, that should be impossible. */
        GNUNET_break (0); /* should be impossible: reserve was fresh,
                             but transaction already known */
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      /* Transaction was already known or error. We are finished. */
      return qs2;
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs1)
  {
    /* New reserve, we are finished */
    notify_on_reserve (pg,
                       reserve_pub);
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }

  /* we were wrong with our optimistic assumption:
     reserve did already exist, need to do an update instead */
  {
    /* We need to move away from 'read committed' to serializable.
       Also, we know that it should be safe to commit at this point.
       (We are only run in a larger transaction for performance.) */
    enum GNUNET_DB_QueryStatus cs;

    cs = TEH_PG_commit(pg);
    if (cs < 0)
      return cs;
    if (GNUNET_OK !=
        TEH_PG_start (pg,
                        "reserve-update-serializable"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  {
    enum GNUNET_DB_QueryStatus reserve_exists;

    reserve_exists = TEH_PG_reserves_get (pg,
                                            &reserve);
    switch (reserve_exists)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return reserve_exists;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      return reserve_exists;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      /* First we got a conflict, but then we cannot select? Very strange. */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_SOFT_ERROR;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* continued below */
      break;
    }
  }

  {
    struct TALER_EXCHANGEDB_Reserve updated_reserve;
    enum GNUNET_DB_QueryStatus qs3;

    /* If the reserve already existed, we need to still update the
       balance; we do this after checking for duplication, as
       otherwise we might have to actually pay the cost to roll this
       back for duplicate transactions; like this, we should virtually
       never actually have to rollback anything. */
    updated_reserve.pub = reserve.pub;
    if (0 >
        TALER_amount_add (&updated_reserve.balance,
                          &reserve.balance,
                          balance))
    {
      /* currency overflow or incompatible currency */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Attempt to deposit incompatible amount into reserve\n");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    updated_reserve.expiry = GNUNET_TIME_timestamp_max (expiry,
                                                        reserve.expiry);
    updated_reserve.gc = GNUNET_TIME_timestamp_max (gc,
                                                    reserve.gc);
    qs3 = TEH_PG_reserves_update (pg,
                           &updated_reserve);
    switch (qs3)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return qs3;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      return qs3;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      /* How can the UPDATE not work here? Very strange. */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* continued below */
      break;
    }
  }
  notify_on_reserve (pg,
                     reserve_pub);
  /* Go back to original transaction mode */
  {
    enum GNUNET_DB_QueryStatus cs;

    cs = TEH_PG_commit (pg);
    if (cs < 0)
      return cs;
    if (GNUNET_OK !=
       TEH_PG_start_read_committed (pg, "reserve-insert-continued"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}
