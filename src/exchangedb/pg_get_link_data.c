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
   * Status, set to #GNUNET_SYSERR on errors,
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Free memory of the link data list.
 *
 * @param ldl link data list to release
 */
static void
free_link_data_list (struct TALER_EXCHANGEDB_LinkList *ldl)
{
  struct TALER_EXCHANGEDB_LinkList *next;

  while (NULL != ldl)
  {
    next = ldl->next;
    TALER_denom_pub_free (&ldl->denom_pub);
    TALER_blinded_denom_sig_free (&ldl->ev_sig);
    GNUNET_free (ldl);
    ldl = next;
  }
}


struct Results
{
  struct TALER_EXCHANGEDB_LinkList *pos;
  struct TALER_TransferPublicKeyP transfer_pub;
};


static int
transfer_pub_cmp (const void *a,
                  const void *b)
{
  const struct Results *ra = a;
  const struct Results *rb = b;

  return GNUNET_memcmp (&ra->transfer_pub,
                        &rb->transfer_pub);
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
  struct Results *temp = GNUNET_new_array (num_results,
                                           struct Results);
  unsigned int temp_off = 0;

  for (int i = num_results - 1; i >= 0; i--)
  {
    struct TALER_EXCHANGEDB_LinkList *pos;

    pos = GNUNET_new (struct TALER_EXCHANGEDB_LinkList);
    {
      struct TALER_BlindedPlanchet bp;
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("transfer_pub",
                                              &temp[temp_off].transfer_pub),
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
    temp[temp_off].pos = pos;
    temp_off++;
  }
  qsort (temp,
         temp_off,
         sizeof (struct Results),
         &transfer_pub_cmp);
  if (temp_off > 0)
  {
    struct TALER_EXCHANGEDB_LinkList *head = NULL;

    head = temp[0].pos;
    for (unsigned int i = 1; i < temp_off; i++)
    {
      struct TALER_EXCHANGEDB_LinkList *pos = temp[i].pos;
      const struct TALER_TransferPublicKeyP *tp = &temp[i].transfer_pub;

      if (0 == GNUNET_memcmp (tp,
                              &temp[i - 1].transfer_pub))
      {
        pos->next = head;
        head = pos;
      }
      else
      {
        ldctx->ldc (ldctx->ldc_cls,
                    &temp[i - 1].transfer_pub,
                    head);
        free_link_data_list (head);
        head = pos;
      }
    }
    ldctx->ldc (ldctx->ldc_cls,
                &temp[temp_off - 1].transfer_pub,
                head);
    free_link_data_list (head);
  }
  GNUNET_free (temp);
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
  static int percent_refund = -2;
  const char *query;

  if (-2 == percent_refund)
  {
    const char *mode = getenv ("TALER_POSTGRES_GET_LINK_DATA_LOGIC");
    char dummy;

    if ( (NULL==mode) ||
         (1 != sscanf (mode,
                       "%d%c",
                       &percent_refund,
                       &dummy)) )
    {
      if (NULL != mode)
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Bad mode `%s' specified\n",
                    mode);
      percent_refund = 4; /* Fastest known */
    }
  }
  switch (percent_refund)
  {
  case 0:
    query = "get_link";
    PREPARE (pg,
             query,
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
    break;
  case 1:
    query = "get_link_v1";
    PREPARE (pg,
             query,
             "WITH rc AS MATERIALIZED ("
             "SELECT"
             " melt_serial_id"
             " FROM refresh_commitments"
             " WHERE old_coin_pub=$1"
             ")"
             "SELECT "
             " tp.transfer_pub"
             ",denoms.denom_pub"
             ",rrc.ev_sig"
             ",rrc.ewv"
             ",rrc.link_sig"
             ",rrc.freshcoin_index"
             ",rrc.coin_ev "
             "FROM "
             "refresh_revealed_coins rrc"
             "  JOIN refresh_transfer_keys tp"
             "   USING (melt_serial_id)"
             "  JOIN denominations denoms"
             "   USING (denominations_serial)"
             " WHERE rrc.melt_serial_id = (SELECT melt_serial_id FROM rc)"
             " ORDER BY tp.transfer_pub, rrc.freshcoin_index ASC");
    break;
  case 2:
    query = "get_link_v2";
    PREPARE (pg,
             query,
             "SELECT"
             " *"
             " FROM"
             " exchange_do_get_link_data"
             " ($1) "
             " AS "
             " (transfer_pub BYTEA"
             " ,denom_pub BYTEA"
             " ,ev_sig BYTEA"
             " ,ewv BYTEA"
             " ,link_sig BYTEA"
             " ,freshcoin_index INT4"
             " ,coin_ev BYTEA);");
    break;
  case 3:
    query = "get_link_v3";
    PREPARE (pg,
             query,
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
             " WHERE old_coin_pub=$1");
    break;
  case 4:
    query = "get_link_v4";
    PREPARE (pg,
             query,
             "WITH rc AS MATERIALIZED ("
             "SELECT"
             " melt_serial_id"
             " FROM refresh_commitments"
             " WHERE old_coin_pub=$1"
             ")"
             "SELECT "
             " tp.transfer_pub"
             ",denoms.denom_pub"
             ",rrc.ev_sig"
             ",rrc.ewv"
             ",rrc.link_sig"
             ",rrc.freshcoin_index"
             ",rrc.coin_ev "
             "FROM "
             "refresh_revealed_coins rrc"
             "  JOIN refresh_transfer_keys tp"
             "   USING (melt_serial_id)"
             "  JOIN denominations denoms"
             "   USING (denominations_serial)"
             " WHERE rrc.melt_serial_id = (SELECT melt_serial_id FROM rc)"
             );
    break;
  default:
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  ldctx.ldc = ldc;
  ldctx.ldc_cls = ldc_cls;
  ldctx.status = GNUNET_OK;
  qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                             query,
                                             params,
                                             &add_ldl,
                                             &ldctx);
  if (GNUNET_OK != ldctx.status)
    return GNUNET_DB_STATUS_HARD_ERROR;
  return qs;
}
