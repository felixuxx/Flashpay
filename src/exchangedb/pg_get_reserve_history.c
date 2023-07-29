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
 * @file pg_get_reserve_history.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_history.h"
#include "plugin_exchangedb_common.h"
#include "pg_helper.h"

/**
 * Closure for callbacks invoked via #TEH_PG_get_reserve_history().
 */
struct ReserveHistoryContext
{

  /**
   * Which reserve are we building the history for?
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Where we build the history.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

  /**
   * Tail of @e rh list.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh_tail;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Sum of all credit transactions.
   */
  struct TALER_Amount balance_in;

  /**
   * Sum of all debit transactions.
   */
  struct TALER_Amount balance_out;

  /**
   * Set to #GNUNET_SYSERR on serious internal errors during
   * the callbacks.
   */
  enum GNUNET_GenericReturnValue status;
};


/**
 * Append and return a fresh element to the reserve
 * history kept in @a rhc.
 *
 * @param rhc where the history is kept
 * @return the fresh element that was added
 */
static struct TALER_EXCHANGEDB_ReserveHistory *
append_rh (struct ReserveHistoryContext *rhc)
{
  struct TALER_EXCHANGEDB_ReserveHistory *tail;

  tail = GNUNET_new (struct TALER_EXCHANGEDB_ReserveHistory);
  if (NULL != rhc->rh_tail)
  {
    rhc->rh_tail->next = tail;
    rhc->rh_tail = tail;
  }
  else
  {
    rhc->rh_tail = tail;
    rhc->rh = tail;
  }
  return tail;
}


/**
 * Add bank transfers to result set for #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_bank_to_exchange (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_BankTransfer *bt;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    bt = GNUNET_new (struct TALER_EXCHANGEDB_BankTransfer);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_uint64 ("wire_reference",
                                      &bt->wire_reference),
        TALER_PQ_RESULT_SPEC_AMOUNT ("credit",
                                     &bt->amount),
        GNUNET_PQ_result_spec_timestamp ("execution_date",
                                         &bt->execution_date),
        GNUNET_PQ_result_spec_string ("sender_account_details",
                                      &bt->sender_account_details),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (bt);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_in,
                                     &rhc->balance_in,
                                     &bt->amount));
    bt->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE;
    tail->details.bank = bt;
  } /* end of 'while (0 < rows)' */
}


/**
 * Add coin withdrawals to result set for #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_withdraw_coin (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_CollectableBlindcoin *cbc;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    cbc = GNUNET_new (struct TALER_EXCHANGEDB_CollectableBlindcoin);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("h_blind_ev",
                                              &cbc->h_coin_envelope),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &cbc->denom_pub_hash),
        TALER_PQ_result_spec_blinded_denom_sig ("denom_sig",
                                                &cbc->sig),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &cbc->reserve_sig),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &cbc->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_withdraw",
                                     &cbc->withdraw_fee),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (cbc);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &cbc->amount_with_fee));
    cbc->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_WITHDRAW_COIN;
    tail->details.withdraw = cbc;
  }
}


/**
 * Add recoups to result set for #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_recoup (void *cls,
            PGresult *result,
            unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_Recoup *recoup;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_Recoup);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                              &recoup->coin.coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        TALER_PQ_result_spec_denom_sig (
          "denom_sig",
          &recoup->coin.denom_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_in,
                                     &rhc->balance_in,
                                     &recoup->value));
    recoup->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_RECOUP_COIN;
    tail->details.recoup = recoup;
  } /* end of 'while (0 < rows)' */
}


/**
 * Add exchange-to-bank transfers to result set for
 * #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_exchange_to_bank (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_ClosingTransfer *closing;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    closing = GNUNET_new (struct TALER_EXCHANGEDB_ClosingTransfer);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &closing->amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("closing_fee",
                                     &closing->closing_fee),
        GNUNET_PQ_result_spec_timestamp ("execution_date",
                                         &closing->execution_date),
        GNUNET_PQ_result_spec_string ("receiver_account",
                                      &closing->receiver_account_details),
        GNUNET_PQ_result_spec_auto_from_type ("wtid",
                                              &closing->wtid),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (closing);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &closing->amount));
    closing->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK;
    tail->details.closing = closing;
  } /* end of 'while (0 < rows)' */
}


/**
 * Add purse merge transfers to result set for
 * #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_p2p_merge (void *cls,
               PGresult *result,
               unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_PurseMerge *merge;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    merge = GNUNET_new (struct TALER_EXCHANGEDB_PurseMerge);
    {
      uint32_t flags32;
      struct TALER_Amount balance;
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("purse_fee",
                                     &merge->purse_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("balance",
                                     &balance),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &merge->amount_with_fee),
        GNUNET_PQ_result_spec_timestamp ("merge_timestamp",
                                         &merge->merge_timestamp),
        GNUNET_PQ_result_spec_timestamp ("purse_expiration",
                                         &merge->purse_expiration),
        GNUNET_PQ_result_spec_uint32 ("age_limit",
                                      &merge->min_age),
        GNUNET_PQ_result_spec_uint32 ("flags",
                                      &flags32),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &merge->h_contract_terms),
        GNUNET_PQ_result_spec_auto_from_type ("merge_pub",
                                              &merge->merge_pub),
        GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                              &merge->purse_pub),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &merge->reserve_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (merge);
        rhc->status = GNUNET_SYSERR;
        return;
      }
      merge->flags = (enum TALER_WalletAccountMergeFlags) flags32;
      if ( (! GNUNET_TIME_absolute_is_future (
              merge->merge_timestamp.abs_time)) &&
           (-1 != TALER_amount_cmp (&balance,
                                    &merge->amount_with_fee)) )
        merge->merged = true;
    }
    if (merge->merged)
      GNUNET_assert (0 <=
                     TALER_amount_add (&rhc->balance_in,
                                       &rhc->balance_in,
                                       &merge->amount_with_fee));
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &merge->purse_fee));
    merge->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_PURSE_MERGE;
    tail->details.merge = merge;
  }
}


/**
 * Add paid for history requests to result set for
 * #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_history_requests (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_HistoryRequest *history;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    history = GNUNET_new (struct TALER_EXCHANGEDB_HistoryRequest);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("history_fee",
                                     &history->history_fee),
        GNUNET_PQ_result_spec_timestamp ("request_timestamp",
                                         &history->request_timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &history->reserve_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (history);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &history->history_fee));
    history->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_HISTORY_REQUEST;
    tail->details.history = history;
  }
}


/**
 * Add paid for history requests to result set for
 * #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_open_requests (void *cls,
                   PGresult *result,
                   unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;
  struct PostgresClosure *pg = rhc->pg;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_OpenRequest *orq;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    orq = GNUNET_new (struct TALER_EXCHANGEDB_OpenRequest);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("open_fee",
                                     &orq->open_fee),
        GNUNET_PQ_result_spec_timestamp ("request_timestamp",
                                         &orq->request_timestamp),
        GNUNET_PQ_result_spec_timestamp ("expiration_date",
                                         &orq->reserve_expiration),
        GNUNET_PQ_result_spec_uint32 ("requested_purse_limit",
                                      &orq->purse_limit),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &orq->reserve_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (orq);
        rhc->status = GNUNET_SYSERR;
        return;
      }
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&rhc->balance_out,
                                     &rhc->balance_out,
                                     &orq->open_fee));
    orq->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_OPEN_REQUEST;
    tail->details.open_request = orq;
  }
}


/**
 * Add paid for history requests to result set for
 * #TEH_PG_get_reserve_history.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
add_close_requests (void *cls,
                    PGresult *result,
                    unsigned int num_results)
{
  struct ReserveHistoryContext *rhc = cls;

  while (0 < num_results)
  {
    struct TALER_EXCHANGEDB_CloseRequest *crq;
    struct TALER_EXCHANGEDB_ReserveHistory *tail;

    crq = GNUNET_new (struct TALER_EXCHANGEDB_CloseRequest);
    {
      char *payto_uri;
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_timestamp ("close_timestamp",
                                         &crq->request_timestamp),
        GNUNET_PQ_result_spec_string ("payto_uri",
                                      &payto_uri),
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &crq->reserve_sig),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    --num_results))
      {
        GNUNET_break (0);
        GNUNET_free (crq);
        rhc->status = GNUNET_SYSERR;
        return;
      }
      TALER_payto_hash (payto_uri,
                        &crq->target_account_h_payto);
      GNUNET_free (payto_uri);
    }
    crq->reserve_pub = *rhc->reserve_pub;
    tail = append_rh (rhc);
    tail->type = TALER_EXCHANGEDB_RO_CLOSE_REQUEST;
    tail->details.close_request = crq;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_history (void *cls,
                            const struct TALER_ReservePublicKeyP *reserve_pub,
                            struct TALER_Amount *balance,
                            struct TALER_EXCHANGEDB_ReserveHistory **rhp)
{
  struct PostgresClosure *pg = cls;
  struct ReserveHistoryContext rhc;
  struct
  {
    /**
     * Name of the prepared statement to run.
     */
    const char *statement;
    /**
     * Function to use to process the results.
     */
    GNUNET_PQ_PostgresResultHandler cb;
  } work[] = {
    /** #TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE */
    { "reserves_in_get_transactions",
      add_bank_to_exchange },
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup_by_reserve",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve",
      &add_exchange_to_bank },
    /** #TALER_EXCHANGEDB_RO_PURSE_MERGE */
    { "merge_by_reserve",
      &add_p2p_merge },
    /** #TALER_EXCHANGEDB_RO_HISTORY_REQUEST */
    { "history_by_reserve",
      &add_history_requests },
    /** #TALER_EXCHANGEDB_RO_OPEN_REQUEST */
    { "open_request_by_reserve",
      &add_open_requests },
    /** #TALER_EXCHANGEDB_RO_CLOSE_REQUEST */
    { "close_request_by_reserve",
      &add_close_requests },
    /* List terminator */
    { NULL,
      NULL }
  };
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "reserves_in_get_transactions",
           /*
           "SELECT"
           " wire_reference"
           ",credit"
           ",execution_date"
           ",payto_uri AS sender_account_details"
           " FROM reserves_in"
           " JOIN wire_targets"
           "   ON (wire_source_h_payto = wire_target_h_payto)"
           " WHERE reserve_pub=$1;",
           */
           "WITH ri AS MATERIALIZED ( "
           "  SELECT * "
           "  FROM reserves_in "
           "  WHERE reserve_pub = $1 "
           ") "
           "SELECT"
           "  wire_reference"
           "  ,credit"
           "  ,execution_date"
           "  ,payto_uri AS sender_account_details"
           " FROM wire_targets"
           " JOIN ri"
           "  ON (wire_target_h_payto = wire_source_h_payto) "
           "WHERE wire_target_h_payto = ( "
           "  SELECT wire_source_h_payto FROM ri "
           "); ");
  PREPARE (pg,
           "get_reserves_out",
           /*
           "SELECT"
           " ro.h_blind_ev"
           ",denom.denom_pub_hash"
           ",ro.denom_sig"
           ",ro.reserve_sig"
           ",ro.execution_date"
           ",ro.amount_with_fee"
           ",denom.fee_withdraw"
           " FROM reserves res"
           " JOIN reserves_out_by_reserve ror"
           "   ON (res.reserve_uuid = ror.reserve_uuid)"
           " JOIN reserves_out ro"
           "   ON (ro.h_blind_ev = ror.h_blind_ev)"
           " JOIN denominations denom"
           "   ON (ro.denominations_serial = denom.denominations_serial)"
           " WHERE res.reserve_pub=$1;",
           */
           "WITH robr AS MATERIALIZED ( "
           "  SELECT h_blind_ev "
           "  FROM reserves_out_by_reserve "
           "  WHERE reserve_uuid= ( "
           "    SELECT reserve_uuid "
           "    FROM reserves "
           "    WHERE reserve_pub = $1 "
           "  ) "
           ") SELECT"
           "  ro.h_blind_ev"
           "  ,denom.denom_pub_hash"
           "  ,ro.denom_sig"
           "  ,ro.reserve_sig"
           "  ,ro.execution_date"
           "  ,ro.amount_with_fee"
           "  ,denom.fee_withdraw"
           " FROM robr"
           " JOIN reserves_out ro"
           "   ON (ro.h_blind_ev = robr.h_blind_ev)"
           " JOIN denominations denom"
           "   ON (ro.denominations_serial = denom.denominations_serial);");
  PREPARE (pg,
           "recoup_by_reserve",
           /*
           "SELECT"
           " recoup.coin_pub"
           ",recoup.coin_sig"
           ",recoup.coin_blind"
           ",recoup.amount"
           ",recoup.recoup_timestamp"
           ",denominations.denom_pub_hash"
           ",known_coins.denom_sig"
           " FROM denominations"
           " JOIN (known_coins"
           "   JOIN recoup "
           "   ON (recoup.coin_pub = known_coins.coin_pub))"
           "  ON (known_coins.denominations_serial = denominations.denominations_serial)"
           " WHERE recoup.coin_pub"
           " IN (SELECT coin_pub"
           "     FROM recoup_by_reserve"
           "     JOIN (reserves_out"
           "       JOIN (reserves_out_by_reserve"
           "         JOIN reserves"
           "           ON (reserves.reserve_uuid = reserves_out_by_reserve.reserve_uuid))"
           "       ON (reserves_out_by_reserve.h_blind_ev = reserves_out.h_blind_ev))"
           "     ON (recoup_by_reserve.reserve_out_serial_id = reserves_out.reserve_out_serial_id)"
           "     WHERE reserves.reserve_pub=$1);",
           */
           "SELECT robr.coin_pub "
           "  ,robr.coin_sig"
           "  ,robr.coin_blind"
           "  ,robr.amount"
           "  ,robr.recoup_timestamp "
           "  ,denominations.denom_pub_hash "
           "  ,robr.denom_sig "
           "FROM denominations "
           "  JOIN exchange_do_recoup_by_reserve($1) robr"
           " USING (denominations_serial);");
  PREPARE (pg,
           "close_by_reserve",
           "SELECT"
           " amount"
           ",closing_fee"
           ",execution_date"
           ",payto_uri AS receiver_account"
           ",wtid"
           " FROM reserves_close"
           "   JOIN wire_targets"
           "     USING (wire_target_h_payto)"
           " WHERE reserve_pub=$1;");
  PREPARE (pg,
           "merge_by_reserve",
           "SELECT"
           " pr.amount_with_fee"
           ",pr.balance"
           ",pr.purse_fee"
           ",pr.h_contract_terms"
           ",pr.merge_pub"
           ",am.reserve_sig"
           ",pm.purse_pub"
           ",pm.merge_timestamp"
           ",pr.purse_expiration"
           ",pr.age_limit"
           ",pr.flags"
           " FROM purse_merges pm"
           "   JOIN purse_requests pr"
           "     USING (purse_pub)"
           "   LEFT JOIN purse_decision pdes"
           "     USING (purse_pub)"
           "   JOIN account_merges am"
           "     ON (am.purse_pub = pm.purse_pub AND"
           "         am.reserve_pub = pm.reserve_pub)"
           " WHERE pm.reserve_pub=$1"
           "  AND COALESCE(pm.partner_serial_id,0)=0" /* must be local! */
           "  AND NOT COALESCE (pdes.refunded, FALSE);");
  PREPARE (pg,
           "history_by_reserve",
           "SELECT"
           " history_fee"
           ",request_timestamp"
           ",reserve_sig"
           " FROM history_requests"
           " WHERE reserve_pub=$1;");
  PREPARE (pg,
           "open_request_by_reserve",
           "SELECT"
           " reserve_payment"
           ",request_timestamp"
           ",expiration_date"
           ",requested_purse_limit"
           ",reserve_sig"
           " FROM reserves_open_requests"
           " WHERE reserve_pub=$1;");
  PREPARE (pg,
           "close_request_by_reserve",
           "SELECT"
           " close_timestamp"
           ",payto_uri"
           ",reserve_sig"
           " FROM close_requests"
           " WHERE reserve_pub=$1;");

  rhc.reserve_pub = reserve_pub;
  rhc.rh = NULL;
  rhc.rh_tail = NULL;
  rhc.pg = pg;
  rhc.status = GNUNET_OK;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_out));
  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* make static analysis happy */
  for (unsigned int i = 0; NULL != work[i].cb; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               work[i].statement,
                                               params,
                                               work[i].cb,
                                               &rhc);
    if ( (0 > qs) ||
         (GNUNET_OK != rhc.status) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Failed to compile reserve history at `%s'\n",
                  work[i].statement);
      break;
    }
  }
  if ( (qs < 0) ||
       (rhc.status != GNUNET_OK) )
  {
    TEH_COMMON_free_reserve_history (cls,
                                     rhc.rh);
    rhc.rh = NULL;
    if (qs >= 0)
    {
      /* status == SYSERR is a very hard error... */
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  *rhp = rhc.rh;
  GNUNET_assert (0 <=
                 TALER_amount_subtract (balance,
                                        &rhc.balance_in,
                                        &rhc.balance_out));
  return qs;
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_status (void *cls,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           struct TALER_Amount *balance_in,
                           struct TALER_Amount *balance_out,
                           struct TALER_EXCHANGEDB_ReserveHistory **rhp)
{
  struct PostgresClosure *pg = cls;
  struct ReserveHistoryContext rhc;
  struct
  {
    /**
     * Name of the prepared statement to run.
     */
    const char *statement;
    /**
     * Function to use to process the results.
     */
    GNUNET_PQ_PostgresResultHandler cb;
  } work[] = {
    /** #TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE */
    { "reserves_in_get_transactions_truncated",
      add_bank_to_exchange },
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "get_reserves_out_truncated",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup_by_reserve_truncated",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "close_by_reserve_truncated",
      &add_exchange_to_bank },
    /** #TALER_EXCHANGEDB_RO_PURSE_MERGE */
    { "merge_by_reserve_truncated",
      &add_p2p_merge },
    /** #TALER_EXCHANGEDB_RO_HISTORY_REQUEST */
    { "history_by_reserve_truncated",
      &add_history_requests },
    /** #TALER_EXCHANGEDB_RO_OPEN_REQUEST */
    { "open_request_by_reserve_truncated",
      &add_open_requests },
    /** #TALER_EXCHANGEDB_RO_CLOSE_REQUEST */
    { "close_request_by_reserve_truncated",
      &add_close_requests },
    /* List terminator */
    { NULL,
      NULL }
  };
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Absolute timelimit;
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_absolute_time (&timelimit),
    GNUNET_PQ_query_param_end
  };

  PREPARE (pg,
           "reserves_in_get_transactions_truncated",
           /*
           "SELECT"
           " wire_reference"
           ",credit"
           ",execution_date"
           ",payto_uri AS sender_account_details"
           " FROM reserves_in"
           " JOIN wire_targets"
           "   ON (wire_source_h_payto = wire_target_h_payto)"
           " WHERE reserve_pub=$1"
           "   AND execution_date>=$2;",
           */
           "WITH ri AS MATERIALIZED ( "
           "  SELECT * "
           "  FROM reserves_in "
           "  WHERE reserve_pub = $1 "
           ") "
           "SELECT  "
           "  wire_reference"
           "  ,credit"
           "  ,execution_date"
           "  ,payto_uri AS sender_account_details"
           " FROM wire_targets"
           " JOIN ri"
           "  ON (wire_target_h_payto = wire_source_h_payto)"
           " WHERE execution_date >= $2"
           "  AND wire_target_h_payto = ( "
           "  SELECT wire_source_h_payto FROM ri "
           "); ");
  PREPARE (pg,
           "get_reserves_out_truncated",
           /*
           "SELECT"
           " ro.h_blind_ev"
           ",denom.denom_pub_hash"
           ",ro.denom_sig"
           ",ro.reserve_sig"
           ",ro.execution_date"
           ",ro.amount_with_fee"
           ",denom.fee_withdraw"
           " FROM reserves res"
           " JOIN reserves_out_by_reserve ror"
           "   ON (res.reserve_uuid = ror.reserve_uuid)"
           " JOIN reserves_out ro"
           "   ON (ro.h_blind_ev = ror.h_blind_ev)"
           " JOIN denominations denom"
           "   ON (ro.denominations_serial = denom.denominations_serial)"
           " WHERE res.reserve_pub=$1"
           "   AND execution_date>=$2;",
           */
           "WITH robr AS MATERIALIZED ( "
           "  SELECT h_blind_ev "
           "  FROM reserves_out_by_reserve "
           "  WHERE reserve_uuid= ( "
           "    SELECT reserve_uuid "
           "    FROM reserves "
           "    WHERE reserve_pub = $1 "
           "  ) "
           ") SELECT "
           "  ro.h_blind_ev"
           "  ,denom.denom_pub_hash"
           "  ,ro.denom_sig"
           "  ,ro.reserve_sig"
           "  ,ro.execution_date"
           "  ,ro.amount_with_fee"
           "  ,denom.fee_withdraw"
           " FROM robr"
           " JOIN reserves_out ro"
           "   ON (ro.h_blind_ev = robr.h_blind_ev)"
           " JOIN denominations denom"
           "   ON (ro.denominations_serial = denom.denominations_serial)"
           " WHERE ro.execution_date>=$2;");
  PREPARE (pg,
           "recoup_by_reserve_truncated",
           /*
           "SELECT"
           " recoup.coin_pub"
           ",recoup.coin_sig"
           ",recoup.coin_blind"
           ",recoup.amount"
           ",recoup.recoup_timestamp"
           ",denominations.denom_pub_hash"
           ",known_coins.denom_sig"
           " FROM denominations"
           " JOIN (known_coins"
           "   JOIN recoup "
           "   ON (recoup.coin_pub = known_coins.coin_pub))"
           "  ON (known_coins.denominations_serial = denominations.denominations_serial)"
           " WHERE recoup_timestamp>=$2"
           " AND recoup.coin_pub"
           "  IN (SELECT coin_pub"
           "     FROM recoup_by_reserve"
           "     JOIN (reserves_out"
           "       JOIN (reserves_out_by_reserve"
           "         JOIN reserves"
           "           ON (reserves.reserve_uuid = reserves_out_by_reserve.reserve_uuid))"
           "       ON (reserves_out_by_reserve.h_blind_ev = reserves_out.h_blind_ev))"
           "     ON (recoup_by_reserve.reserve_out_serial_id = reserves_out.reserve_out_serial_id)"
           "     WHERE reserves.reserve_pub=$1);",
           */
           "SELECT robr.coin_pub "
           "  ,robr.coin_sig "
           "  ,robr.coin_blind "
           "  ,robr.amount"
           "  ,robr.recoup_timestamp "
           "  ,denominations.denom_pub_hash "
           "  ,robr.denom_sig "
           "FROM denominations "
           "  JOIN exchange_do_recoup_by_reserve($1) robr"
           "    USING (denominations_serial)"
           " WHERE recoup_timestamp>=$2;");
  PREPARE (pg,
           "close_by_reserve_truncated",
           "SELECT"
           " amount"
           ",closing_fee"
           ",execution_date"
           ",payto_uri AS receiver_account"
           ",wtid"
           " FROM reserves_close"
           "   JOIN wire_targets"
           "     USING (wire_target_h_payto)"
           " WHERE reserve_pub=$1"
           "   AND execution_date>=$2;");
  PREPARE (pg,
           "merge_by_reserve_truncated",
           "SELECT"
           " pr.amount_with_fee"
           ",pr.balance"
           ",pr.purse_fee"
           ",pr.h_contract_terms"
           ",pr.merge_pub"
           ",am.reserve_sig"
           ",pm.purse_pub"
           ",pm.merge_timestamp"
           ",pr.purse_expiration"
           ",pr.age_limit"
           ",pr.flags"
           " FROM purse_merges pm"
           "   JOIN purse_requests pr"
           "     USING (purse_pub)"
           "   JOIN purse_decision pdes"
           "     USING (purse_pub)"
           "   JOIN account_merges am"
           "     ON (am.purse_pub = pm.purse_pub AND"
           "         am.reserve_pub = pm.reserve_pub)"
           " WHERE pm.reserve_pub=$1"
           "  AND pm.merge_timestamp >= $2"
           "  AND COALESCE(pm.partner_serial_id,0)=0" /* must be local! */
           "  AND NOT pdes.refunded;");
  PREPARE (pg,
           "history_by_reserve_truncated",
           "SELECT"
           " history_fee"
           ",request_timestamp"
           ",reserve_sig"
           " FROM history_requests"
           " WHERE reserve_pub=$1"
           "  AND request_timestamp>=$2;");
  PREPARE (pg,
           "open_request_by_reserve_truncated",
           "SELECT"
           " reserve_payment"
           ",request_timestamp"
           ",expiration_date"
           ",requested_purse_limit"
           ",reserve_sig"
           " FROM reserves_open_requests"
           " WHERE reserve_pub=$1"
           "   AND request_timestamp>=$2;");

  PREPARE (pg,
           "close_request_by_reserve_truncated",
           "SELECT"
           " close_timestamp"
           ",payto_uri"
           ",reserve_sig"
           " FROM close_requests"
           " WHERE reserve_pub=$1"
           "   AND close_timestamp>=$2;");

  timelimit = GNUNET_TIME_absolute_subtract (
    GNUNET_TIME_absolute_get (),
    GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_WEEKS,
                                   5));
  rhc.reserve_pub = reserve_pub;
  rhc.rh = NULL;
  rhc.rh_tail = NULL;
  rhc.pg = pg;
  rhc.status = GNUNET_OK;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_out));
  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS; /* make static analysis happy */
  for (unsigned int i = 0; NULL != work[i].cb; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               work[i].statement,
                                               params,
                                               work[i].cb,
                                               &rhc);
    if ( (0 > qs) ||
         (GNUNET_OK != rhc.status) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Query %s failed\n",
                  work[i].statement);
      break;
    }
  }
  if ( (qs < 0) ||
       (rhc.status != GNUNET_OK) )
  {
    TEH_COMMON_free_reserve_history (cls,
                                     rhc.rh);
    rhc.rh = NULL;
    if (qs >= 0)
    {
      /* status == SYSERR is a very hard error... */
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  *rhp = rhc.rh;
  *balance_in = rhc.balance_in;
  *balance_out = rhc.balance_out;
  return qs;
}
