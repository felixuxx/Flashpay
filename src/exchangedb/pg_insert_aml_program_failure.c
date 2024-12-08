/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_insert_aml_program_failure.c
 * @brief Implementation of the insert_aml_program_failure function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_aml_program_failure.h"
#include "pg_helper.h"
#include "pg_event_notify.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_program_failure (
  void *cls,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const char *error_message,
  enum TALER_ErrorCode ec)
{
  struct PostgresClosure *pg = cls;
  uint32_t ec32 = (uint32_t) ec;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&process_row),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint32 (&ec32),
    GNUNET_PQ_query_param_string (error_message),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;

  PREPARE (pg,
           "insert_aml_program_failure",
           "UPDATE legitimization_processes"
           " SET"
           "  finished=TRUE"
           " ,error_code=$3"
           " ,error_message=$4"
           " WHERE h_payto=$2"
           "   AND legitimization_process_serial_id=$1;");
  qs = GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                           "insert_aml_program_failure",
                                           params);
  if (qs > 0)
  {
    /* FIXME: might want to do this eventually in the same transaction... */
    struct TALER_KycCompletedEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
      .h_payto = *h_payto
    };

    TEH_PG_event_notify (pg,
                         &rep.header,
                         NULL,
                         0);
  }
  return qs;
}
