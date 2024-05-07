/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_insert_kyc_attributes.c
 * @brief Implementation of the insert_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_insert_kyc_attributes.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_attributes (
  void *cls,
  uint64_t process_row,
  const struct TALER_PaytoHashP *h_payto,
  uint32_t birthday,
  struct GNUNET_TIME_Timestamp collection_time,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  struct GNUNET_TIME_Absolute expiration_time,
  size_t enc_attributes_size,
  const void *enc_attributes,
  bool require_aml)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_TIME_Timestamp expiration
    = GNUNET_TIME_absolute_to_timestamp (expiration_time);
  struct TALER_KycCompletedEventP rep = {
    .header.size = htons (sizeof (rep)),
    .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
    .h_payto = *h_payto
  };
  char *kyc_completed_notify_s
    = GNUNET_PQ_get_event_notify_channel (&rep.header);
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_uint64 (&process_row),
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_uint32 (&birthday),
    (NULL == provider_account_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (provider_account_id),
    (NULL == provider_legitimization_id)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (provider_legitimization_id),
    GNUNET_PQ_query_param_timestamp (&collection_time),
    GNUNET_PQ_query_param_absolute_time (&expiration_time),
    GNUNET_PQ_query_param_timestamp (&expiration),
    GNUNET_PQ_query_param_fixed_size (enc_attributes,
                                      enc_attributes_size),
    GNUNET_PQ_query_param_bool (require_aml),
    GNUNET_PQ_query_param_string (kyc_completed_notify_s),
    GNUNET_PQ_query_param_end
  };
  bool ok;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("out_ok",
                                &ok),
    GNUNET_PQ_result_spec_end
  };
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Inserting KYC attributes, wake up on %s\n",
              kyc_completed_notify_s);
  PREPARE (pg,
           "insert_kyc_attributes",
           "SELECT "
           " out_ok"
           " FROM exchange_do_insert_kyc_attributes "
           "($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11);");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "insert_kyc_attributes",
                                                 params,
                                                 rs);
  GNUNET_PQ_cleanup_query_params_closures (params);
  GNUNET_free (kyc_completed_notify_s);
  GNUNET_PQ_event_do_poll (pg->conn);
  if (qs < 0)
    return qs;
  if (! ok)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return qs;
}
