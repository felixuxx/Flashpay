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
 * @file exchangedb/pg_lookup_signing_key.c
 * @brief Implementation of the lookup_signing_key function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_lookup_signing_key.h"
#include "pg_helper.h"


enum GNUNET_DB_QueryStatus
TEH_PG_lookup_signing_key (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_EXCHANGEDB_SignkeyMetaData *meta)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (exchange_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_timestamp ("valid_from",
                                     &meta->start),
    GNUNET_PQ_result_spec_timestamp ("expire_sign",
                                     &meta->expire_sign),
    GNUNET_PQ_result_spec_timestamp ("expire_legal",
                                     &meta->expire_legal),
    GNUNET_PQ_result_spec_end
  };


  PREPARE (pg,
           "lookup_signing_key",
           "SELECT"
           " valid_from"
           ",expire_sign"
           ",expire_legal"
           " FROM exchange_sign_keys"
           " WHERE exchange_pub=$1");

  return GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                   "lookup_signing_key",
                                                   params,
                                                   rs);
}

