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
 * @file exchangedb/pg_batch_ensure_coin_known.c
 * @brief Implementation of the batch_ensure_coin_known function for Postgres
 * @author Christian Grothoff
 *
 * FIXME: use the array support for postgres to simplify this code!
 *
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_exchangedb_plugin.h"
#include "taler_pq_lib.h"
#include "pg_batch_ensure_coin_known.h"
#include "pg_helper.h"


static enum GNUNET_DB_QueryStatus
insert1 (struct PostgresClosure *pg,
         const struct TALER_CoinPublicInfo coin[1],
         struct TALER_EXCHANGEDB_CoinInfo result[1])
{
  enum GNUNET_DB_QueryStatus qs;
  bool is_denom_pub_hash_null = false;
  bool is_age_hash_null = false;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin[0].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[0].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[0].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[0].denom_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("existed",
                                &result[0].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  &result[0].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &result[0].denom_hash),
      &is_denom_pub_hash_null),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &result[0].h_age_commitment),
      &is_age_hash_null),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch1_known_coin",
           "SELECT"
           " existed1 AS existed"
           ",known_coin_id1 AS known_coin_id"
           ",denom_pub_hash1 AS denom_hash"
           ",age_commitment_hash1 AS h_age_commitment"
           " FROM exchange_do_batch1_known_coin"
           "  ($1, $2, $3, $4);"
           );
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch1_known_coin",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0); /* should be impossible */
    return GNUNET_DB_STATUS_HARD_ERROR;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break; /* continued below */
  }

  if ( (! is_denom_pub_hash_null) &&
       (0 != GNUNET_memcmp (&result[0].denom_hash,
                            &coin->denom_pub_hash)) )
  {
    GNUNET_break_op (0);
    result[0].denom_conflict = true;
  }

  if ( (! is_denom_pub_hash_null) &&
       (0 != GNUNET_memcmp (&result[0].denom_hash,
                            &coin[0].denom_pub_hash)) )
  {
    GNUNET_break_op (0);
    result[0].denom_conflict = true;
  }

  result[0].age_conflict = TALER_AgeCommitmentHash_NoConflict;

  if (is_age_hash_null != coin[0].no_age_commitment)
  {
    if (is_age_hash_null)
    {
      GNUNET_break_op (0);
      result[0].age_conflict = TALER_AgeCommitmentHash_NullExpected;
    }
    else
    {
      GNUNET_break_op (0);
      result[0].age_conflict = TALER_AgeCommitmentHash_ValueExpected;
    }
  }
  else if ( (! is_age_hash_null) &&
            (0 != GNUNET_memcmp (&result[0].h_age_commitment,
                                 &coin[0].h_age_commitment)) )
  {
    GNUNET_break_op (0);
    result[0].age_conflict = TALER_AgeCommitmentHash_ValueDiffers;
  }

  return qs;
}


static enum GNUNET_DB_QueryStatus
insert2 (struct PostgresClosure *pg,
         const struct TALER_CoinPublicInfo coin[2],
         struct TALER_EXCHANGEDB_CoinInfo result[2])
{
  enum GNUNET_DB_QueryStatus qs;
  bool is_denom_pub_hash_null[2] = {false, false};
  bool is_age_hash_null[2] = {false, false};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin[0].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[0].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[0].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[0].denom_sig),

    GNUNET_PQ_query_param_auto_from_type (&coin[1].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[1].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[1].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[0].denom_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("existed",
                                &result[0].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  &result[0].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &result[0].denom_hash),
      &is_denom_pub_hash_null[0]),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &result[0].h_age_commitment),
      &is_age_hash_null[0]),
    GNUNET_PQ_result_spec_bool ("existed2",
                                &result[1].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id2",
                                  &result[1].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash2",
                                            &result[1].denom_hash),
      &is_denom_pub_hash_null[1]),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash2",
                                            &result[1].h_age_commitment),
      &is_age_hash_null[1]),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch2_known_coin",
           "SELECT"
           " existed1 AS existed"
           ",known_coin_id1 AS known_coin_id"
           ",denom_pub_hash1 AS denom_hash"
           ",age_commitment_hash1 AS h_age_commitment"
           ",existed2 AS existed2"
           ",known_coin_id2 AS known_coin_id2"
           ",denom_pub_hash2 AS denom_hash2"
           ",age_commitment_hash2 AS h_age_commitment2"
           " FROM exchange_do_batch2_known_coin"
           "  ($1, $2, $3, $4, $5, $6, $7, $8);"
           );
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch2_known_coin",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0); /* should be impossible */
    return GNUNET_DB_STATUS_HARD_ERROR;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break; /* continued below */
  }

  for (int i = 0; i < 2; i++)
  {
    if ( (! is_denom_pub_hash_null[i]) &&
         (0 != GNUNET_memcmp (&result[i].denom_hash,
                              &coin[i].denom_pub_hash)) )
    {
      GNUNET_break_op (0);
      result[i].denom_conflict = true;
    }

    result[i].age_conflict = TALER_AgeCommitmentHash_NoConflict;

    if (is_age_hash_null[i] != coin[i].no_age_commitment)
    {
      if (is_age_hash_null[i])
      {
        GNUNET_break_op (0);
        result[i].age_conflict = TALER_AgeCommitmentHash_NullExpected;
      }
      else
      {
        GNUNET_break_op (0);
        result[i].age_conflict = TALER_AgeCommitmentHash_ValueExpected;
      }
    }
    else if ( (! is_age_hash_null[i]) &&
              (0 != GNUNET_memcmp (&result[i].h_age_commitment,
                                   &coin[i].h_age_commitment)) )
    {
      GNUNET_break_op (0);
      result[i].age_conflict = TALER_AgeCommitmentHash_ValueDiffers;
    }
  }

  return qs;
}


static enum GNUNET_DB_QueryStatus
insert4 (struct PostgresClosure *pg,
         const struct TALER_CoinPublicInfo coin[4],
         struct TALER_EXCHANGEDB_CoinInfo result[4])
{
  enum GNUNET_DB_QueryStatus qs;
  bool is_denom_pub_hash_null[4] = {false, false, false, false};
  bool is_age_hash_null[4] = {false, false, false, false};
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (&coin[0].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[0].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[0].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[0].denom_sig),

    GNUNET_PQ_query_param_auto_from_type (&coin[1].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[1].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[1].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[0].denom_sig),

    GNUNET_PQ_query_param_auto_from_type (&coin[2].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[2].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[2].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[2].denom_sig),

    GNUNET_PQ_query_param_auto_from_type (&coin[3].coin_pub),
    GNUNET_PQ_query_param_auto_from_type (&coin[3].denom_pub_hash),
    GNUNET_PQ_query_param_auto_from_type (&coin[3].h_age_commitment),
    TALER_PQ_query_param_denom_sig (&coin[3].denom_sig),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_bool ("existed",
                                &result[0].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id",
                                  &result[0].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                            &result[0].denom_hash),
      &is_denom_pub_hash_null[0]),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                            &result[0].h_age_commitment),
      &is_age_hash_null[0]),
    GNUNET_PQ_result_spec_bool ("existed2",
                                &result[1].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id2",
                                  &result[1].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash2",
                                            &result[1].denom_hash),
      &is_denom_pub_hash_null[1]),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash2",
                                            &result[1].h_age_commitment),
      &is_age_hash_null[1]),
    GNUNET_PQ_result_spec_bool ("existed3",
                                &result[2].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id3",
                                  &result[2].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash3",
                                            &result[2].denom_hash),
      &is_denom_pub_hash_null[2]),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash3",
                                            &result[2].h_age_commitment),
      &is_age_hash_null[2]),
    GNUNET_PQ_result_spec_bool ("existed4",
                                &result[3].existed),
    GNUNET_PQ_result_spec_uint64 ("known_coin_id4",
                                  &result[3].known_coin_id),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash4",
                                            &result[3].denom_hash),
      &is_denom_pub_hash_null[3]),
    GNUNET_PQ_result_spec_allow_null (
      GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash4",
                                            &result[3].h_age_commitment),
      &is_age_hash_null[3]),
    GNUNET_PQ_result_spec_end
  };

  PREPARE (pg,
           "batch4_known_coin",
           "SELECT"
           " existed1 AS existed"
           ",known_coin_id1 AS known_coin_id"
           ",denom_pub_hash1 AS denom_hash"
           ",age_commitment_hash1 AS h_age_commitment"
           ",existed2 AS existed2"
           ",known_coin_id2 AS known_coin_id2"
           ",denom_pub_hash2 AS denom_hash2"
           ",age_commitment_hash2 AS h_age_commitment2"
           ",existed3 AS existed3"
           ",known_coin_id3 AS known_coin_id3"
           ",denom_pub_hash3 AS denom_hash3"
           ",age_commitment_hash3 AS h_age_commitment3"
           ",existed4 AS existed4"
           ",known_coin_id4 AS known_coin_id4"
           ",denom_pub_hash4 AS denom_hash4"
           ",age_commitment_hash4 AS h_age_commitment4"
           " FROM exchange_do_batch2_known_coin"
           "  ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16);"
           );
  qs = GNUNET_PQ_eval_prepared_singleton_select (pg->conn,
                                                 "batch4_known_coin",
                                                 params,
                                                 rs);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    GNUNET_break (0); /* should be impossible */
    return GNUNET_DB_STATUS_HARD_ERROR;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break; /* continued below */
  }

  for (int i = 0; i < 4; i++)
  {
    if ( (! is_denom_pub_hash_null[i]) &&
         (0 != GNUNET_memcmp (&result[i].denom_hash,
                              &coin[i].denom_pub_hash)) )
    {
      GNUNET_break_op (0);
      result[i].denom_conflict = true;
    }

    result[i].age_conflict = TALER_AgeCommitmentHash_NoConflict;

    if (is_age_hash_null[i] != coin[i].no_age_commitment)
    {
      if (is_age_hash_null[i])
      {
        GNUNET_break_op (0);
        result[i].age_conflict = TALER_AgeCommitmentHash_NullExpected;
      }
      else
      {
        GNUNET_break_op (0);
        result[i].age_conflict = TALER_AgeCommitmentHash_ValueExpected;
      }
    }
    else if ( (! is_age_hash_null[i]) &&
              (0 != GNUNET_memcmp (&result[i].h_age_commitment,
                                   &coin[i].h_age_commitment)) )
    {
      GNUNET_break_op (0);
      result[i].age_conflict = TALER_AgeCommitmentHash_ValueDiffers;
    }
  }

  return qs;
}


enum GNUNET_DB_QueryStatus
TEH_PG_batch_ensure_coin_known (
  void *cls,
  const struct TALER_CoinPublicInfo *coin,
  struct TALER_EXCHANGEDB_CoinInfo *result,
  unsigned int coin_length,
  unsigned int batch_size)
{
  struct PostgresClosure *pg = cls;
  enum GNUNET_DB_QueryStatus qs = 0;
  unsigned int i = 0;

  while ( (qs >= 0) &&
          (i < coin_length) )
  {
    unsigned int bs = GNUNET_MIN (batch_size,
                                  coin_length - i);
    if (bs >= 4)
    {
      qs = insert4 (pg,
                    &coin[i],
                    &result[i]);
      i += 4;
      continue;
    }
    switch (bs)
    {
    case 3:
    case 2:
      qs = insert2 (pg,
                    &coin[i],
                    &result[i]);
      i += 2;
      break;
    case 1:
      qs = insert1 (pg,
                    &coin[i],
                    &result[i]);
      i += 1;
      break;
    case 0:
      GNUNET_assert (0);
      break;
    }
  } /* end while */
  if (qs < 0)
    return qs;
  return i;
}
