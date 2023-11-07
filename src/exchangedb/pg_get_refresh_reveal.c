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
 * @file exchangedb/pg_get_refresh_reveal.c
 * @brief Implementation of the get_refresh_reveal function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_refresh_reveal.h"
#include "pg_helper.h"


/**
 * Context where we aggregate data from the database.
 * Closure for #add_revealed_coins().
 */
struct GetRevealContext
{
  /**
   * Array of revealed coins we obtained from the DB.
   */
  struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs;

  /**
   * Length of the @a rrcs array.
   */
  unsigned int rrcs_len;

  /**
   * Set to an error code if we ran into trouble.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct GetRevealContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_revealed_coins (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct GetRevealContext *grctx = cls;

  if (0 == num_results)
    return;
  grctx->rrcs = GNUNET_new_array (num_results,
                                  struct TALER_EXCHANGEDB_RefreshRevealedCoin);
  grctx->rrcs_len = num_results;
  for (unsigned int i = 0; i < num_results; i++)
  {
    uint32_t off;
    struct GNUNET_PQ_ResultSpec rso[] = {
      GNUNET_PQ_result_spec_uint32 ("freshcoin_index",
                                    &off),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rso,
                                  i))
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    if (off >= num_results)
    {
      GNUNET_break (0);
      grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return;
    }
    {
      struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx->rrcs[off];
      struct GNUNET_PQ_ResultSpec rsi[] = {
        /* NOTE: freshcoin_index selected and discarded here... */
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &rrc->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                              &rrc->orig_coin_link_sig),
        GNUNET_PQ_result_spec_auto_from_type ("h_coin_ev",
                                              &rrc->coin_envelope_hash),
        TALER_PQ_result_spec_blinded_planchet ("coin_ev",
                                               &rrc->blinded_planchet),
        TALER_PQ_result_spec_exchange_withdraw_values ("ewv",
                                                       &rrc->exchange_vals),
        TALER_PQ_result_spec_blinded_denom_sig ("ev_sig",
                                                &rrc->coin_sig),
        GNUNET_PQ_result_spec_end
      };

      if (NULL !=
          rrc->blinded_planchet.blinded_message)
      {
        /* duplicate offset, not allowed */
        GNUNET_break (0);
        grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rsi,
                                    i))
      {
        GNUNET_break (0);
        grctx->qs = GNUNET_DB_STATUS_HARD_ERROR;
        return;
      }
    }
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_refresh_reveal (void *cls,
                           const struct TALER_RefreshCommitmentP *rc,
                           TALER_EXCHANGEDB_RefreshCallback cb,
                           void *cb_cls)
{
  struct PostgresClosure *pg = cls;
  struct GetRevealContext grctx;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rc),
    GNUNET_PQ_query_param_end
  };

  memset (&grctx,
          0,
          sizeof (grctx));

  /* Obtain information about the coins created in a refresh
     operation, used in #postgres_get_refresh_reveal() */
  PREPARE (pg,
           "get_refresh_revealed_coins",
           "SELECT "
           " rrc.freshcoin_index"
           ",denom.denom_pub_hash"
           ",rrc.h_coin_ev"
           ",rrc.link_sig"
           ",rrc.coin_ev"
           ",rrc.ewv"
           ",rrc.ev_sig"
           " FROM refresh_commitments"
           "    JOIN refresh_revealed_coins rrc"
           "      USING (melt_serial_id)"
           "    JOIN denominations denom "
           "      USING (denominations_serial)"
           " WHERE rc=$1;");
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "get_refresh_revealed_coins",
                                             params,
                                             &add_revealed_coins,
                                             &grctx);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
  default: /* can have more than one result */
    break;
  }
  switch (grctx.qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
  case GNUNET_DB_STATUS_SOFT_ERROR:
    goto cleanup;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT: /* should be impossible */
    break;
  }

  /* Pass result back to application */
  cb (cb_cls,
      grctx.rrcs_len,
      grctx.rrcs);
cleanup:
  for (unsigned int i = 0; i < grctx.rrcs_len; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &grctx.rrcs[i];

    TALER_blinded_denom_sig_free (&rrc->coin_sig);
    TALER_blinded_planchet_free (&rrc->blinded_planchet);
    TALER_denom_ewv_free (&rrc->exchange_vals);
  }
  GNUNET_free (grctx.rrcs);
  return qs;
}
