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
 * @file exchangedb/pg_get_link_data.c
 * @brief Implementation of the get_link_data function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_link_data.h"
#include "pg_helper.h"


/**
 * Closure for #add_ldl().
 */
struct LinkDataContext
{
  /**
   * Function to call on each result.
   */
  TALER_EXCHANGEDB_LinkCallback ldc;

  /**
   * Closure for @e ldc.
   */
  void *ldc_cls;

  /**
   * Last transfer public key for which we have information in @e last.
   * Only valid if @e last is non-NULL.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Link data for @e transfer_pub
   */
  struct TALER_EXCHANGEDB_LinkList *last;

  /**
   * Status, set to #GNUNET_SYSERR on errors,
   */
  int status;
};


/**
 * Free memory of the link data list.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param ldl link data list to release
 */
static void
free_link_data_list (void *cls,
                     struct TALER_EXCHANGEDB_LinkList *ldl)
{
  struct TALER_EXCHANGEDB_LinkList *next;

  (void) cls;
  while (NULL != ldl)
  {
    next = ldl->next;
    TALER_denom_pub_free (&ldl->denom_pub);
    TALER_blinded_denom_sig_free (&ldl->ev_sig);
    GNUNET_free (ldl);
    ldl = next;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct LinkDataContext *`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_ldl (void *cls,
         PGresult *result,
         unsigned int num_results)
{
  struct LinkDataContext *ldctx = cls;

  for (int i = num_results - 1; i >= 0; i--)
  {
    struct TALER_EXCHANGEDB_LinkList *pos;
    struct TALER_TransferPublicKeyP transfer_pub;

    pos = GNUNET_new (struct TALER_EXCHANGEDB_LinkList);
    {
      struct TALER_BlindedPlanchet bp;
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                              &transfer_pub),
        GNUNET_PQ_result_spec_auto_from_type ("link_sig",
                                              &pos->orig_coin_link_sig),
        TALER_PQ_result_spec_blinded_denom_sig ("ev_sig",
                                                &pos->ev_sig),
        GNUNET_PQ_result_spec_uint32 ("freshcoin_index",
                                      &pos->coin_refresh_offset),
        TALER_PQ_result_spec_exchange_withdraw_values ("ewv",
                                                       &pos->alg_values),
        TALER_PQ_result_spec_denom_pub ("denom_pub",
                                        &pos->denom_pub),
        TALER_PQ_result_spec_blinded_planchet ("coin_ev",
                                               &bp),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (pos);
        ldctx->status = GNUNET_SYSERR;
        return;
      }
      if (TALER_DENOMINATION_CS == bp.cipher)
      {
        pos->nonce = bp.details.cs_blinded_planchet.nonce;
        pos->have_nonce = true;
      }
      TALER_blinded_planchet_free (&bp);
    }
    if ( (NULL != ldctx->last) &&
         (0 == GNUNET_memcmp (&transfer_pub,
                              &ldctx->transfer_pub)) )
    {
      pos->next = ldctx->last;
    }
    else
    {
      if (NULL != ldctx->last)
      {
        ldctx->ldc (ldctx->ldc_cls,
                    &ldctx->transfer_pub,
                    ldctx->last);
        free_link_data_list (cls,
                             ldctx->last);
      }
      ldctx->transfer_pub = transfer_pub;
    }
    ldctx->last = pos;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_link_data (void *cls,
                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                      TALER_EXCHANGEDB_LinkCallback ldc,
                      void *ldc_cls)
{
  struct PostgresClosure *pg = cls;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct LinkDataContext ldctx;

  PREPARE (pg,
           "get_link",
           "SELECT "
           " tp.transfer_pub"
           ",denoms.denom_pub"
           ",rrc.ev_sig"
           ",rrc.ewv"
           ",rrc.link_sig"
           ",rrc.freshcoin_index"
           ",rrc.coin_ev"
           " FROM refresh_commitments"
           "     JOIN refresh_revealed_coins rrc"
           "       USING (melt_serial_id)"
           "     JOIN refresh_transfer_keys tp"
           "       USING (melt_serial_id)"
           "     JOIN denominations denoms"
           "       ON (rrc.denominations_serial = denoms.denominations_serial)"
           " WHERE old_coin_pub=$1"
           " ORDER BY tp.transfer_pub, rrc.freshcoin_index ASC");
  ldctx.ldc = ldc;
  ldctx.ldc_cls = ldc_cls;
  ldctx.last = NULL;
  ldctx.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             "get_link",
                                             params,
                                             &add_ldl,
                                             &ldctx);
  if (NULL != ldctx.last)
  {
    if (GNUNET_OK == ldctx.status)
    {
      /* call callback one more time! */
      ldc (ldc_cls,
           &ldctx.transfer_pub,
           ldctx.last);
    }
    free_link_data_list (cls,
                         ldctx.last);
    ldctx.last = NULL;
  }
  if (GNUNET_OK != ldctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}


