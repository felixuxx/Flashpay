/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @brief Obtain (parts of) the history of a reserve.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_reserve_history.h"
#include "pg_start_read_committed.h"
#include "pg_commit.h"
#include "pg_rollback.h"
#include "plugin_exchangedb_common.h"
#include "pg_helper.h"

/**
 * How often do we re-try when encountering DB serialization issues?
 * (We are read-only, so can only happen due to concurrent insert,
 * which should be very rare.)
 */
#define RETRIES 3


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
   * Set to true on serious internal errors during
   * the callbacks.
   */
  bool failed;
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
        rhc->failed = true;
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
        rhc->failed = true;
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
        rhc->failed = true;
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
        rhc->failed = true;
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
        rhc->failed = true;
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
        rhc->failed = true;
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
        rhc->failed = true;
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


/**
 * Add reserve history entries found.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param result SQL result
 * @param num_results number of rows in @a result
 */
static void
handle_history_entry (void *cls,
                      PGresult *result,
                      unsigned int num_results)
{
  static const struct
  {
    /**
     * Table with reserve history entry we are responsible for.
     */
    const char *table;
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
    { "reserves_in",
      "reserves_in_get_transactions",
      add_bank_to_exchange },
    /** #TALER_EXCHANGEDB_RO_WITHDRAW_COIN */
    { "reserves_out",
      "get_reserves_out",
      &add_withdraw_coin },
    /** #TALER_EXCHANGEDB_RO_RECOUP_COIN */
    { "recoup",
      "recoup_by_reserve",
      &add_recoup },
    /** #TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK */
    { "reserves_close",
      "close_by_reserve",
      &add_exchange_to_bank },
    /** #TALER_EXCHANGEDB_RO_PURSE_MERGE */
    { "purse_decision",
      "merge_by_reserve",
      &add_p2p_merge },
    /** #TALER_EXCHANGEDB_RO_OPEN_REQUEST */
    { "reserves_open_requests",
      "open_request_by_reserve",
      &add_open_requests },
    /** #TALER_EXCHANGEDB_RO_CLOSE_REQUEST */
    { "close_requests",
      "close_request_by_reserve",
      &add_close_requests },
    /* List terminator */
    { NULL, NULL, NULL }
  };
  struct ReserveHistoryContext *rhc = cls;
  char *table_name;
  uint64_t serial_id;
  struct GNUNET_PQ_ResultSpec rs[] = {
    GNUNET_PQ_result_spec_string ("table_name",
                                  &table_name),
    GNUNET_PQ_result_spec_uint64 ("serial_id",
                                  &serial_id),
    GNUNET_PQ_result_spec_end
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (rhc->reserve_pub),
    GNUNET_PQ_query_param_uint64 (&serial_id),
    GNUNET_PQ_query_param_end
  };

  while (0 < num_results--)
  {
    enum GNUNET_DB_QueryStatus qs;
    bool found = false;

    if (GNUNET_OK !=
        GNUNET_PQ_extract_result (result,
                                  rs,
                                  num_results))
    {
      GNUNET_break (0);
      rhc->failed = true;
      return;
    }

    for (unsigned int i = 0;
         NULL != work[i].cb;
         i++)
    {
      if (0 != strcmp (table_name,
                       work[i].table))
        continue;
      found = true;
      qs = GNUNET_PQ_eval_prepared_multi_select (rhc->pg->conn,
                                                 work[i].statement,
                                                 params,
                                                 work[i].cb,
                                                 rhc);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Reserve %s had %d transactions at %llu in table %s\n",
                  TALER_B2S (rhc->reserve_pub),
                  (int) qs,
                  (unsigned long long) serial_id,
                  table_name);
      if (0 >= qs)
        rhc->failed = true;
      break;
    }
    if (! found)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Coin history includes unsupported table `%s`\n",
                  table_name);
      rhc->failed = true;
    }
    GNUNET_PQ_cleanup_result (rs);
    if (rhc->failed)
      break;
  }
}


enum GNUNET_DB_QueryStatus
TEH_PG_get_reserve_history (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t start_off,
  uint64_t etag_in,
  uint64_t *etag_out,
  struct TALER_Amount *balance,
  struct TALER_EXCHANGEDB_ReserveHistory **rhp)
{
  struct PostgresClosure *pg = cls;
  struct ReserveHistoryContext rhc = {
    .pg = pg,
    .reserve_pub = reserve_pub
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_end
  };
  struct GNUNET_PQ_QueryParam lparams[] = {
    GNUNET_PQ_query_param_auto_from_type (reserve_pub),
    GNUNET_PQ_query_param_uint64 (&start_off),
    GNUNET_PQ_query_param_end
  };

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (pg->currency,
                                        &rhc.balance_out));

  *rhp = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting transactions for reserve %s\n",
              TALER_B2S (reserve_pub));
  PREPARE (pg,
           "get_reserve_history_etag",
           "SELECT"
           " hist.reserve_history_serial_id"
           ",r.current_balance"
           " FROM reserve_history hist"
           " JOIN reserves r USING (reserve_pub)"
           " WHERE hist.reserve_pub=$1"
           " ORDER BY reserve_history_serial_id DESC"
           " LIMIT 1;");
  PREPARE (pg,
           "get_reserve_history",
           "SELECT"
           " table_name"
           ",serial_id"
           " FROM reserve_history"
           " WHERE reserve_pub=$1"
           "   AND reserve_history_serial_id > $2"
           " ORDER BY reserve_history_serial_id DESC;");

  PREPARE (pg,
           "reserves_in_get_transactions",
           "SELECT"
           " ri.wire_reference"
           ",ri.credit"
           ",ri.execution_date"
           ",wt.payto_uri AS sender_account_details"
           " FROM reserves_in ri"
           " JOIN wire_targets wt"
           "   ON (wire_source_h_payto = wire_target_h_payto)"
           " WHERE ri.reserve_pub=$1"
           "   AND ri.reserve_in_serial_id=$2;");
  PREPARE (pg,
           "get_reserves_out",
           "SELECT"
           " ro.h_blind_ev"
           ",denom.denom_pub_hash"
           ",ro.denom_sig"
           ",ro.reserve_sig"
           ",ro.execution_date"
           ",ro.amount_with_fee"
           ",denom.fee_withdraw"
           " FROM reserves_out ro"
           " JOIN denominations denom"
           "   USING (denominations_serial)"
           " JOIN reserves res"
           "   USING (reserve_uuid)"
           " WHERE ro.reserve_out_serial_id=$2"
           "   AND res.reserve_pub=$1;");
  PREPARE (pg,
           "recoup_by_reserve",
           "SELECT"
           " rec.coin_pub"
           ",rec.coin_sig"
           ",rec.coin_blind"
           ",rec.amount"
           ",rec.recoup_timestamp"
           ",denom.denom_pub_hash"
           ",kc.denom_sig"
           " FROM recoup rec"
           " JOIN reserves_out ro"
           "   USING (reserve_out_serial_id)"
           " JOIN reserves res"
           "   USING (reserve_uuid)"
           " JOIN known_coins kc"
           "   USING (coin_pub)"
           " JOIN denominations denom"
           "   ON (denom.denominations_serial = kc.denominations_serial)"
           " WHERE rec.recoup_uuid=$2"
           "   AND res.reserve_pub=$1;");
  PREPARE (pg,
           "close_by_reserve",
           "SELECT"
           " rc.amount"
           ",rc.closing_fee"
           ",rc.execution_date"
           ",wt.payto_uri AS receiver_account"
           ",rc.wtid"
           " FROM reserves_close rc"
           " JOIN wire_targets wt"
           "   USING (wire_target_h_payto)"
           " WHERE reserve_pub=$1"
           "   AND close_uuid=$2;");
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
           " FROM purse_decision pdes"
           "   JOIN purse_requests pr"
           "     ON (pr.purse_pub = pdes.purse_pub)"
           "   JOIN purse_merges pm"
           "     ON (pm.purse_pub = pdes.purse_pub)"
           "   JOIN account_merges am"
           "     ON (am.purse_pub = pm.purse_pub AND"
           "         am.reserve_pub = pm.reserve_pub)"
           " WHERE pdes.purse_decision_serial_id=$2"
           "  AND pm.reserve_pub=$1"
           "  AND COALESCE(pm.partner_serial_id,0)=0" /* must be local! */
           "  AND NOT pdes.refunded;");
  PREPARE (pg,
           "open_request_by_reserve",
           "SELECT"
           " reserve_payment"
           ",request_timestamp"
           ",expiration_date"
           ",requested_purse_limit"
           ",reserve_sig"
           " FROM reserves_open_requests"
           " WHERE reserve_pub=$1"
           "   AND open_request_uuid=$2;");
  PREPARE (pg,
           "close_request_by_reserve",
           "SELECT"
           " close_timestamp"
           ",payto_uri"
           ",reserve_sig"
           " FROM close_requests"
           " WHERE reserve_pub=$1"
           "   AND close_request_serial_id=$2;");

  for (unsigned int i = 0; i<RETRIES; i++)
  {
    enum GNUNET_DB_QueryStatus qs;
    uint64_t end;
    struct GNUNET_PQ_ResultSpec rs[] = {
      GNUNET_PQ_result_spec_uint64 ("reserve_history_serial_id",
                                    &end),
      TALER_PQ_RESULT_SPEC_AMOUNT ("current_balance",
                                   balance),
      GNUNET_PQ_result_spec_end
    };

    if (GNUNET_OK !=
        TEH_PG_start_read_committed (pg,
                                     "get-reserve-transactions"))
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    /* First only check the last item, to see if
       we even need to iterate */
    qs = GNUNET_PQ_eval_prepared_singleton_select (
      pg->conn,
      "get_reserve_history_etag",
      params,
      rs);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      TEH_PG_rollback (pg);
      return qs;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      TEH_PG_rollback (pg);
      continue;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      TEH_PG_rollback (pg);
      return qs;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      *etag_out = end;
      if (end == etag_in)
        return qs;
    }
    /* We indeed need to iterate over the history */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Current ETag for reserve %s is %llu\n",
                TALER_B2S (reserve_pub),
                (unsigned long long) end);

    qs = GNUNET_PQ_eval_prepared_multi_select (
      pg->conn,
      "get_reserve_history",
      lparams,
      &handle_history_entry,
      &rhc);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      TEH_PG_rollback (pg);
      return qs;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      TEH_PG_rollback (pg);
      continue;
    default:
      break;
    }
    if (rhc.failed)
    {
      TEH_PG_rollback (pg);
      TEH_COMMON_free_reserve_history (pg,
                                       rhc.rh);
      return GNUNET_DB_STATUS_SOFT_ERROR;
    }
    qs = TEH_PG_commit (pg);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      TEH_COMMON_free_reserve_history (pg,
                                       rhc.rh);
      return qs;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      TEH_COMMON_free_reserve_history (pg,
                                       rhc.rh);
      rhc.rh = NULL;
      continue;
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      *rhp = rhc.rh;
      return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    }
  }
  return GNUNET_DB_STATUS_SOFT_ERROR;
}
