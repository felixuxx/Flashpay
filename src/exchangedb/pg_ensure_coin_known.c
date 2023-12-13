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
 * @file exchangedb/pg_ensure_coin_known.c
 * @brief Implementation of the ensure_coin_known function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_exchangedb_plugin.h"
#include "taler_pq_lib.h"
#include "pg_ensure_coin_known.h"
#include "pg_helper.h"


enum TALER_EXCHANGEDB_CoinKnownStatus
TEH_PG_ensure_coin_known (void *cls,
                          const struct TALER_CoinPublicInfo *coin,
                          uint64_t *known_coin_id,
                          struct TALER_DenominationHashP *denom_hash,
                          struct TALER_AgeCommitmentHash *h_age_commitment)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool existed;
  bool is_denom_pub_hash_null = false;
  bool is_age_hash_null = false;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin->coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin->denom_pub_hash),
    coin->no_age_commitment
    ? GNUNET_PQ_query_param_null ()
    : GNUNET_PQ_query_param_auto_from_type (&coin->h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin->denom_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("existed",
                                &existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            denom_hash),
      &is_denom_pub_hash_null),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            h_age_commitment),
      &is_age_hash_null),
    GNUNET_PQ_result_spec_end
  };

  /*
     See also:
     https://stackoverflow.com/questions/34708509/how-to-use-returning-with-on-conflict-in-postgresql/37543015#37543015
  */
  PREPARE (pg,
           "insert_known_coin",
           "WITH dd"
           "  (denominations_serial"
           "  ,coin"
           "  ) AS ("
           "    SELECT "
           "       denominations_serial"
           "      ,coin"
           "        FROM denominations"
           "        WHERE denom_pub_hash=$2"
           "  ), input_rows"
           "    (coin_pub) AS ("
           "      VALUES ($1::BYTEA)"
           "  ), ins AS ("
           "  INSERT INTO known_coins "
           "  (coin_pub"
           "  ,denominations_serial"
           "  ,age_commitment_hash"
           "  ,denom_sig"
           "  ,remaining"
           "  ) SELECT "
           "     $1"
           "    ,denominations_serial"
           "    ,$3"
           "    ,$4"
           "    ,coin"
           "  FROM dd"
           "  ON CONFLICT DO NOTHING" /* CONFLICT on (coin_pub) */
           "  RETURNING "
           "     known_coin_id"
           "  ) "
           "SELECT "
           "   FALSE AS existed"
           "  ,known_coin_id"
           "  ,NULL AS denom_pub_hash"
           "  ,NULL AS age_commitment_hash"
           "  FROM ins "
           "UNION ALL "
           "SELECT "
           "   TRUE AS existed"
           "  ,known_coin_id"
           "  ,denom_pub_hash"
           "  ,kc.age_commitment_hash"
           "  FROM input_rows"
           "  JOIN known_coins kc USING (coin_pub)"
           "  JOIN denominations USING (denominations_serial)"
           "  LIMIT 1");
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "insert_known_coin",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return TALER_EXCHANGEDB_CKS_SOFT_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0); /* should be impossible */
    return TALER_EXCHANGEDB_CKS_HARD_FAIL;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    if (! existed)
      return TALER_EXCHANGEDB_CKS_ADDED;
    break; /* continued below */
  }

  if ( (! is_denom_pub_hash_null) &&
       (0 != GNUNET_memcmp (&denom_hash->hash,
                            &coin->denom_pub_hash.hash)) )
  {
    GNUNET_break_op (0);
    return TALER_EXCHANGEDB_CKS_DENOM_CONFLICT;
  }

  if (is_age_hash_null != coin->no_age_commitment)
  {
    if (is_age_hash_null)
    {
      GNUNET_break_op (0);
      return TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NULL;
    }
    else
    {
      GNUNET_break_op (0);
      return TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NON_NULL;
    }
  }
  else if ( (! is_age_hash_null) &&
            (0 != GNUNET_memcmp (h_age_commitment,
                                 &coin->h_age_commitment)) )
  {
    GNUNET_break_op (0);
    return TALER_EXCHANGEDB_CKS_AGE_CONFLICT_VALUE_DIFFERS;
  }

  return TALER_EXCHANGEDB_CKS_PRESENT;
}
