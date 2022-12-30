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
 * @file exchangedb/pg_update_kyc_attributes.c
 * @brief Implementation of the update_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_kyc_attributes.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_update_kyc_attributes (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct GNUNET_ShortHashCode *kyc_prox,
  const char *provider_section,
  const char *birthdate,
  struct GNUNET_TIME_Timestamp collection_time,
  struct GNUNET_TIME_Timestamp expiration_time,
  size_t enc_attributes_size,
  const void *enc_attributes)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (h_payto),
    GNUNET_PQ_query_param_auto_from_type (kyc_prox),
    GNUNET_PQ_query_param_string (provider_section),
    (NULL == birthdate)
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_string (birthdate),
    GNUNET_PQ_query_param_timestamp (&collection_time),
    GNUNET_PQ_query_param_timestamp (&expiration_time),
    GNUNET_PQ_query_param_fixed_size (enc_attributes,
                                      enc_attributes_size),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "update_kyc_attributes",
           "UPDATE kyc_attributes SET "
           " kyc_prox=$2"
           ",birthdate=$4"
           ",collection_time=$5"
           ",expiration_time=$6"
           ",encrypted_attributes=$7"
           " WHERE h_payto=$1 AND provider_section=$3;");
  return GNUNET_PQ_eval_prepared_non_select (pg->conn,
                                             "update_kyc_attributes",
                                             params);
}
