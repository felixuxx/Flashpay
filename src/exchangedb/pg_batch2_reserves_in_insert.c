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


<<<<<<< HEAD
enum GNUNET_DB_QueryStatus
TEH_PG_batch2_reserves_in_insert (void *cls,
                                  const struct
                                  TALER_EXCHANGEDB_ReserveInInfo *reserves,
                                  unsigned int reserves_length,
                                  enum GNUNET_DB_QueryStatus *results)
=======
static enum GNUNET_DB_QueryStatus
insert1(struct PostgresClosure *pg,
        const struct TALER_EXCHANGEDB_ReserveInInfo *reserve,
        struct GNUNET_TIME_Timestamp expiry,
        struct GNUNET_TIME_Timestamp gc,
        struct TALER_PaytoHashP h_payto,
        const char *notify_s,
        struct GNUNET_TIME_Timestamp reserve_expiration,
        bool *transaction_duplicate,
        bool *conflict,
        uint64_t *reserve_uuid)
>>>>>>> b9baf781 (new batch test and standard deviation)
{
  enum GNUNET_DB_QueryStatus qs2;
  PREPARE (pg,
           "batch1_reserve_create",
           "SELECT "
           "out_reserve_found AS conflicted"
           ",transaction_duplicate"
           ",ruuid AS reserve_uuid"
           " FROM exchange_do_batch_reserves_in_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12);");

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
      GNUNET_PQ_query_param_string (notify_s),
      GNUNET_PQ_query_param_end
    };

    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_bool ("conflicted",
                                  conflict),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate",
                                  transaction_duplicate),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    reserve_uuid),
      GNUNET_PQ_result_spec_end
    };

    TALER_payto_hash (reserve->sender_account_details,
                      &h_payto);

    /* Note: query uses 'on conflict do nothing' */
    qs2 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "batch1_reserve_create",
                                                    params,
                                                    rs);

    if (qs2 < 0)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to create reserves (%d)\n",
                  qs2);
      return qs2;
    }
   GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs2);

   if ((*conflict) && (*transaction_duplicate))
   {
     GNUNET_break (0);
     TEH_PG_rollback (pg);
     return GNUNET_DB_STATUS_HARD_ERROR;
   }
   return qs2;
}



static enum GNUNET_DB_QueryStatus
insert2 (struct PostgresClosure *pg,
         const struct TALER_EXCHANGEDB_ReserveInInfo reserves[2],
         struct GNUNET_TIME_Timestamp expiry,
         struct GNUNET_TIME_Timestamp gc,
         struct TALER_PaytoHashP h_payto,
         char *const*notify_s,
         struct GNUNET_TIME_Timestamp reserve_expiration,
         bool *transaction_duplicate,
         bool *conflict,
         uint64_t *reserve_uuid)
{
  enum GNUNET_DB_QueryStatus qs1;
  PREPARE (pg,
           "batch2_reserve_create",
           "SELECT "
           "out_reserve_found AS conflicted"
           ",out_reserve_found2 AS conflicted2"
           ",transaction_duplicate"
           ",transaction_duplicate2"
           ",ruuid AS reserve_uuid"
           ",ruuid2 AS reserve_uuid2"
           " FROM exchange_do_batch2_reserves_insert"
<<<<<<< HEAD
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21);");
  expiry = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (reserves->execution_time.abs_time,
                              pg->idle_reserve_expiration_time));
  gc = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                              pg->legal_reserve_expiration_time));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating reserve %s with expiration in %s\n",
              TALER_B2S (reserves->reserve_pub),
              GNUNET_STRINGS_relative_time_to_string (
                pg->idle_reserve_expiration_time,
                GNUNET_NO));

  {
    if (GNUNET_OK !=
        TEH_PG_start_read_committed (pg,
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
  for (unsigned int i = 0; i<reserves_length; i++)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];
    notify_s[i] = compute_notify_on_reserve (reserve->reserve_pub);
  }

  for (unsigned int i = 0; i<(reserves_length & ~1); i += 2)
  {
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve0 = &reserves[i];
    const struct TALER_EXCHANGEDB_ReserveInInfo *reserve1 = &reserves[i + 1];
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (reserve0->reserve_pub),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_uint64 (&reserve0->wire_reference),
      TALER_PQ_query_param_amount (reserve0->balance),
      GNUNET_PQ_query_param_string (reserve0->exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserve0->execution_time),
=======
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22);");

    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserves[0].reserve_pub),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_uint64 (&reserves[0].wire_reference),
      TALER_PQ_query_param_amount (&reserves[0].balance),
      GNUNET_PQ_query_param_string (reserves[0].exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserves[0].execution_time),
>>>>>>> b9baf781 (new batch test and standard deviation)
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserves[0].sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),
<<<<<<< HEAD
      GNUNET_PQ_query_param_string (notify_s[i]),
      GNUNET_PQ_query_param_auto_from_type (reserve1->reserve_pub),
      GNUNET_PQ_query_param_uint64 (&reserve1->wire_reference),
      TALER_PQ_query_param_amount (reserve1->balance),
      GNUNET_PQ_query_param_string (reserve1->exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserve1->execution_time),
=======
      GNUNET_PQ_query_param_string (notify_s[0]), // FIXME: 2 different notifies!
      GNUNET_PQ_query_param_string (notify_s[1]),
      GNUNET_PQ_query_param_auto_from_type (&reserves[1].reserve_pub),
      GNUNET_PQ_query_param_uint64 (&reserves[1].wire_reference),
      TALER_PQ_query_param_amount (&reserves[1].balance),
      GNUNET_PQ_query_param_string (reserves[1].exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserves[1].execution_time),
>>>>>>> b9baf781 (new batch test and standard deviation)
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserves[1].sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),

      GNUNET_PQ_query_param_end
    };

    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_bool ("conflicted",
                                  &conflict[0]),
      GNUNET_PQ_result_spec_bool ("conflicted2",
                                  &conflict[1]),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate",
                                  &transaction_duplicate[0]),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate2",
                                  &transaction_duplicate[1]),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &reserve_uuid[0]),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid2",
                                    &reserve_uuid[1]),
      GNUNET_PQ_result_spec_end
    };

    TALER_payto_hash (reserves[0].sender_account_details,
                      &h_payto);
    TALER_payto_hash (reserves[1].sender_account_details,
                      &h_payto);


    qs1 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "batch2_reserve_create",
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
         /*   results[i] = (transaction_duplicate)
      ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
      : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;*/

    if (((conflict[0]) && (transaction_duplicate[0])) ||((conflict[1]) && (transaction_duplicate[1])))
   {
     GNUNET_break (0);
     TEH_PG_rollback (pg);
     return GNUNET_DB_STATUS_HARD_ERROR;
   }
    return qs1;
}


static enum GNUNET_DB_QueryStatus
insert4 (struct PostgresClosure *pg,
         const struct TALER_EXCHANGEDB_ReserveInInfo reserves[4],
         struct GNUNET_TIME_Timestamp expiry,
         struct GNUNET_TIME_Timestamp gc,
         struct TALER_PaytoHashP h_payto,
         char *const*notify_s,
         struct GNUNET_TIME_Timestamp reserve_expiration,
         bool *transaction_duplicate,
         bool *conflict,
         uint64_t *reserve_uuid)
{
  enum GNUNET_DB_QueryStatus qs3;
  PREPARE (pg,
           "batch4_reserve_create",
           "SELECT "
           "out_reserve_found AS conflicted"
           ",out_reserve_found2 AS conflicted2"
           ",out_reserve_found3 AS conflicted3"
           ",out_reserve_found4 AS conflicted4"
           ",transaction_duplicate"
           ",transaction_duplicate2"
           ",transaction_duplicate3"
           ",transaction_duplicate4"
           ",ruuid AS reserve_uuid"
           ",ruuid2 AS reserve_uuid2"
           ",ruuid3 AS reserve_uuid3"
           ",ruuid4 AS reserve_uuid4"
           " FROM exchange_do_batch4_reserves_insert"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39, $40, $41,$42);");

    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserves[0].reserve_pub),
      GNUNET_PQ_query_param_timestamp (&expiry),
      GNUNET_PQ_query_param_timestamp (&gc),
      GNUNET_PQ_query_param_uint64 (&reserves[0].wire_reference),
      TALER_PQ_query_param_amount (&reserves[0].balance),
      GNUNET_PQ_query_param_string (reserves[0].exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserves[0].execution_time),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserves[0].sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),
      GNUNET_PQ_query_param_string (notify_s[0]),
      GNUNET_PQ_query_param_string (notify_s[1]),
      GNUNET_PQ_query_param_string (notify_s[2]),
      GNUNET_PQ_query_param_string (notify_s[3]),

      GNUNET_PQ_query_param_auto_from_type (&reserves[1].reserve_pub),
      GNUNET_PQ_query_param_uint64 (&reserves[1].wire_reference),
      TALER_PQ_query_param_amount (&reserves[1].balance),
      GNUNET_PQ_query_param_string (reserves[1].exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserves[1].execution_time),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserves[1].sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),

      GNUNET_PQ_query_param_auto_from_type (&reserves[2].reserve_pub),
      GNUNET_PQ_query_param_uint64 (&reserves[2].wire_reference),
      TALER_PQ_query_param_amount (&reserves[2].balance),
      GNUNET_PQ_query_param_string (reserves[2].exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserves[2].execution_time),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserves[2].sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),

      GNUNET_PQ_query_param_auto_from_type (&reserves[3].reserve_pub),
      GNUNET_PQ_query_param_uint64 (&reserves[3].wire_reference),
      TALER_PQ_query_param_amount (&reserves[3].balance),
      GNUNET_PQ_query_param_string (reserves[3].exchange_account_name),
      GNUNET_PQ_query_param_timestamp (&reserves[3].execution_time),
      GNUNET_PQ_query_param_auto_from_type (&h_payto),
      GNUNET_PQ_query_param_string (reserves[3].sender_account_details),
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),

      GNUNET_PQ_query_param_end
    };

    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_bool ("conflicted",
                                  &conflict[0]),
      GNUNET_PQ_result_spec_bool ("conflicted2",
                                  &conflict[1]),
      GNUNET_PQ_result_spec_bool ("conflicted3",
                                  &conflict[2]),
      GNUNET_PQ_result_spec_bool ("conflicted4",
                                  &conflict[3]),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate",
                                  &transaction_duplicate[0]),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate2",
                                  &transaction_duplicate[1]),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate3",
                                  &transaction_duplicate[2]),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate4",
                                  &transaction_duplicate[3]),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &reserve_uuid[0]),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid2",
                                    &reserve_uuid[1]),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid3",
                                    &reserve_uuid[2]),
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid4",
                                    &reserve_uuid[3]),
      GNUNET_PQ_result_spec_end
    };

    TALER_payto_hash (reserves[0].sender_account_details,
                      &h_payto);
    TALER_payto_hash (reserves[1].sender_account_details,
                      &h_payto);
    TALER_payto_hash (reserves[2].sender_account_details,
                      &h_payto);
    TALER_payto_hash (reserves[3].sender_account_details,
                      &h_payto);

    qs3 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "batch4_reserve_create",
                                                    params,
                                                    rs);
    if (qs3 < 0)
    {
<<<<<<< HEAD
      const struct TALER_EXCHANGEDB_ReserveInInfo *reserve =
        &reserves[reserves_length - 1];
      // single insert logic here
    }
    GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs1);
    results[i] = (transaction_duplicate)
      ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
      : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
   conflicts[i] = conflicted;
   conflicts2[i] = conflicted2;
   // fprintf(stdout, "%d",conflicts[i]);
   // fprintf(stdout, "%d", conflicts2[i]);
   if ((!conflicts[i] && transaction_duplicate) ||(!conflicts2[i] && transaction_duplicate2))
=======
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to create reserves4 (%d)\n",
                  qs3);
      return qs3;
    }

   GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS != qs3);
   /*   results[i] = (transaction_duplicate)
      ? GNUNET_DB_STATUS_SUCCESS_NO_RESULTS
      : GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;*/

    if (((conflict[0]) && (transaction_duplicate[0])) ||((conflict[1]) && (transaction_duplicate[1])) ||((conflict[2]) && (transaction_duplicate[2])) ||((conflict[3]) && (transaction_duplicate[3])))
>>>>>>> b9baf781 (new batch test and standard deviation)
   {
     GNUNET_break (0);
     TEH_PG_rollback (pg);
     return GNUNET_DB_STATUS_HARD_ERROR;
   }
    return qs3;
}



enum GNUNET_DB_QueryStatus
TEH_PG_batch2_reserves_in_insert (void *cls,
                                 const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
                                 unsigned int reserves_length,
                                  unsigned int batch_size,
                                 enum GNUNET_DB_QueryStatus *results)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs1;
  enum GNUNET_DB_QueryStatus qs2;
  enum GNUNET_DB_QueryStatus qs4;
  enum GNUNET_DB_QueryStatus qs5;
  struct GNUNET_TIME_Timestamp expiry;
  struct GNUNET_TIME_Timestamp gc;
  struct TALER_PaytoHashP h_payto;
  uint64_t reserve_uuid[reserves_length];
  bool transaction_duplicate[reserves_length];
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

  if (GNUNET_OK !=
      TEH_PG_start_read_committed(pg,
                                  "READ_COMMITED"))
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
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

  unsigned int i=0;

  while (i < reserves_length)
  {
    unsigned int bs = GNUNET_MIN (batch_size,
                                  reserves_length - i);
    if (bs >= 4)
    {
      //   fprintf(stdout, "batch4");
      qs4=insert4(pg,
                  &reserves[i],
                  expiry,
                  gc,
                  h_payto,
                  &notify_s[i],
                  reserve_expiration,
                  &transaction_duplicate[i],
                  &conflicts[i],
                  &reserve_uuid[i]);

     if (qs4<0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves4 (%d)\n",
                    qs4);
        return qs4;
      }
      need_update |= conflicts[i];
      need_update |= conflicts[i+1];
      need_update |= conflicts[i+2];
      need_update |= conflicts[i+3];
      //     fprintf(stdout, "%ld %ld %ld %ld\n", reserve_uuid[i], reserve_uuid[i+1], reserve_uuid[i+2], reserve_uuid[i+3]);
      //fprintf(stdout, "%d %d %d %d\n", transaction_duplicate[i], transaction_duplicate[i+1], transaction_duplicate[i+2], transaction_duplicate[i+3]);
      i += 4;
      continue;
    }
    switch (bs)
    {
    case 3:
    case 2:
      qs5=insert2(pg,
                  &reserves[i],
                  expiry,
                  gc,
                  h_payto,
                  &notify_s[i],
                  reserve_expiration,
                  &transaction_duplicate[i],
                  &conflicts[i],
                  &reserve_uuid[i]);
      if (qs5<0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves (%d)\n",
                    qs5);
        return qs5;
      }
      need_update |= conflicts[i];
      need_update |= conflicts[i+1];
      //      fprintf(stdout, "%ld %ld\n", reserve_uuid[i], reserve_uuid[i+1]);
      i += 2;
      break;
    case 1:
      qs2 = insert1(pg,
                    &reserves[i],
                    expiry,
                    gc,
                    h_payto,
                    notify_s[i],
                    reserve_expiration,
                    &transaction_duplicate[i],
                    &conflicts[i],
                    &reserve_uuid[i]);
      if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs2)
      {
        GNUNET_break (0);
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      need_update |= conflicts[i];
      i += 1;
      break;
    case 0:
      GNUNET_assert (0);
      break;
    }
  } /* end while */
  // commit
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
  {
    goto exit;
  }
  // begin serializable
  {
    if (GNUNET_OK !=
        TEH_PG_start (pg,
                      "reserve-insert-continued"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  enum GNUNET_DB_QueryStatus qs3;
  PREPARE (pg,
           "reserves_in_add_transaction",
           "CALL exchange_do_batch_reserves_update"
           " ($1,$2,$3,$4,$5,$6,$7,$8,$9);");
  for (unsigned int i = 0; i<reserves_length; i++)
  {
    if (! conflicts[i])
      continue;
    {
      const struct TALER_EXCHANGEDB_ReserveInInfo *reserve = &reserves[i];
      struct GNUNET_PQ_QueryParam params[] = {
        GNUNET_PQ_query_param_auto_from_type (reserve->reserve_pub),
        GNUNET_PQ_query_param_timestamp (&expiry),
        GNUNET_PQ_query_param_uint64 (&reserve->wire_reference),
        TALER_PQ_query_param_amount (reserve->balance),
        GNUNET_PQ_query_param_string (reserve->exchange_account_name),
        GNUNET_PQ_query_param_bool (conflicts[i]),
        GNUNET_PQ_query_param_auto_from_type (&h_payto),
        GNUNET_PQ_query_param_string (notify_s[i]),
        GNUNET_PQ_query_param_end
      };

      qs3 = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                                "reserves_in_add_transaction",
                                                params);
      if (qs3<0)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Failed to update reserves (%d)\n",
                    qs3);
        return qs3;
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
  for (unsigned int i = 0; i<reserves_length; i++)
    GNUNET_free (notify_s[i]);

  return reserves_length;
}
