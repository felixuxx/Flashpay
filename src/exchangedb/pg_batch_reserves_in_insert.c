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
 * @author JOSEPHxu
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
TEH_PG_batch_reserves_in_insert (void *cls,
                              const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
                              unsigned int reserves_length,
                              enum GNUNET_DB_QueryStatus *results)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs1;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct GNUNET_TIME_Timestamp expiry;
  struct GNUNET_TIME_Timestamp gc;
  struct TALER_PaytoHashP h_payto;
  uint64_t reserve_uuid;
  bool conflicted;
  bool transaction_duplicate;
  struct GNUNET_TIME_Timestamp reserve_expiration
    = GNUNET_TIME_relative_to_timestamp (pg->idle_reserve_expiration_time);

  reserve.pub = reserves->reserve_pub;
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
  /* Optimistically assume this is a new reserve, create balance for the first
     time; we do this before adding the actual transaction to "reserves_in",
     as for a new reserve it can't be a duplicate 'add' operation, and as
     the 'add' operation needs the reserve entry as a foreign key. */
  {
    struct GNUNET_PQ_QueryParam params[] = {
      GNUNET_PQ_query_param_auto_from_type (&reserves->reserve_pub), /*$1*/
      GNUNET_PQ_query_param_timestamp (&expiry),  /*$4*/
      GNUNET_PQ_query_param_timestamp (&gc),  /*$5*/
      GNUNET_PQ_query_param_uint64 (&reserves->wire_reference), /*6*/
      TALER_PQ_query_param_amount (&reserves->balance), /*7+8*/
      GNUNET_PQ_query_param_string (reserves->exchange_account_name), /*9*/
      GNUNET_PQ_query_param_timestamp (&reserves->execution_time), /*10*/
      GNUNET_PQ_query_param_auto_from_type (&h_payto), /*11*/
      GNUNET_PQ_query_param_string (reserves->sender_account_details),/*12*/
      GNUNET_PQ_query_param_timestamp (&reserve_expiration),/*13*/
      GNUNET_PQ_query_param_end
    };

    /* We should get all our results into results[]*/
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("reserve_uuid",
                                    &reserve_uuid),
      GNUNET_PQ_result_spec_bool ("conflicted",
                                  &conflicted),
      GNUNET_PQ_result_spec_bool ("transaction_duplicate",
                                  &transaction_duplicate),
      GNUNET_PQ_result_spec_end
    };


    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Reserve does not exist; creating a new one\n");
    /* Note: query uses 'on conflict do nothing' */
    PREPARE (pg,
             "reserve_create",
             "SELECT "
             "out_reserve_found AS conflicted"
             ",transaction_duplicate"
             ",ruuid AS reserve_uuid"
             " FROM batch_reserves_in"
             " ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);");

    qs1 = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                    "reserve_create",
                                                    params,
                                                    rs);


    if (qs1 < 0)
      return qs1;
  }
  if ((int)conflicted == 0 && (int)transaction_duplicate == 1)
    TEH_PG_rollback(pg);
  notify_on_reserve (pg,
                     &reserves->reserve_pub);

  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}
