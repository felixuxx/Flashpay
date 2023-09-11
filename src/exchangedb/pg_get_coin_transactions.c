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
 * @file pg_get_coin_transactions.c
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_get_coin_transactions.h"
#include "pg_helper.h"
#include "plugin_exchangedb_common.h"


/**
 * Closure for callbacks called from #postgres_get_coin_transactions()
 */
struct CoinHistoryContext
{
  /**
   * Head of the coin's history list.
   */
  struct TALER_EXCHANGEDB_TransactionList *head;

  /**
   * Public key of the coin we are building the history for.
   */
  const struct TALER_CoinSpendPublicKeyP *coin_pub;

  /**
   * Closure for all callbacks of this database plugin.
   */
  void *db_cls;

  /**
   * Plugin context.
   */
  struct PostgresClosure *pg;

  /**
   * Set to 'true' if the transaction failed.
   */
  bool failed;

  /**
   * Set to 'true' if we found a deposit or melt (for invariant check).
   */
  bool have_deposit_or_melt;
};


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_deposit (void *cls,
                  PGresult *result,
                  unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_DepositListEntry *deposit;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    chc->have_deposit_or_melt = true;
    deposit = GNUNET_new (struct TALER_EXCHANGEDB_DepositListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &deposit->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                     &deposit->deposit_fee),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &deposit->h_denom_pub),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                                &deposit->h_age_commitment),
          &deposit->no_age_commitment),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_auto_from_type ("wallet_data_hash",
                                                &deposit->wallet_data_hash),
          &deposit->no_wallet_data_hash),
        GNUNET_PQ_result_spec_timestamp ("wallet_timestamp",
                                         &deposit->timestamp),
        GNUNET_PQ_result_spec_timestamp ("refund_deadline",
                                         &deposit->refund_deadline),
        GNUNET_PQ_result_spec_timestamp ("wire_deadline",
                                         &deposit->wire_deadline),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &deposit->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &deposit->h_contract_terms),
        GNUNET_PQ_result_spec_auto_from_type ("wire_salt",
                                              &deposit->wire_salt),
        GNUNET_PQ_result_spec_string ("payto_uri",
                                      &deposit->receiver_wire_account),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &deposit->csig),
        GNUNET_PQ_result_spec_uint64 ("coin_deposit_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_auto_from_type ("done",
                                              &deposit->done),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (deposit);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_DEPOSIT;
    tl->details.deposit = deposit;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_purse_deposit (void *cls,
                        PGresult *result,
                        unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i < num_results; i++)
  {
    struct TALER_EXCHANGEDB_PurseDepositListEntry *deposit;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    chc->have_deposit_or_melt = true;
    deposit = GNUNET_new (struct TALER_EXCHANGEDB_PurseDepositListEntry);
    {
      bool not_finished;
      struct GNUNET_PQ_ResultSpec rs[] = {
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &deposit->amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_deposit",
                                     &deposit->deposit_fee),
        GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                              &deposit->purse_pub),
        GNUNET_PQ_result_spec_uint64 ("purse_deposit_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_string ("partner_base_url",
                                        &deposit->exchange_base_url),
          NULL),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &deposit->coin_sig),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                                &deposit->h_age_commitment),
          &deposit->no_age_commitment),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_bool ("refunded",
                                      &deposit->refunded),
          &not_finished),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (deposit);
        chc->failed = true;
        return;
      }
      if (not_finished)
        deposit->refunded = false;
      deposit->no_age_commitment = GNUNET_is_zero (&deposit->h_age_commitment);
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_PURSE_DEPOSIT;
    tl->details.purse_deposit = deposit;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_melt (void *cls,
               PGresult *result,
               unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_MeltListEntry *melt;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    chc->have_deposit_or_melt = true;
    melt = GNUNET_new (struct TALER_EXCHANGEDB_MeltListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("rc",
                                              &melt->rc),
        /* oldcoin_index not needed */
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &melt->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("old_coin_sig",
                                              &melt->coin_sig),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &melt->amount_with_fee),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refresh",
                                     &melt->melt_fee),
        GNUNET_PQ_result_spec_allow_null (
          GNUNET_PQ_result_spec_auto_from_type ("age_commitment_hash",
                                                &melt->h_age_commitment),
          &melt->no_age_commitment),
        GNUNET_PQ_result_spec_uint64 ("melt_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (melt);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_MELT;
    tl->details.melt = melt;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_refund (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RefundListEntry *refund;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    refund = GNUNET_new (struct TALER_EXCHANGEDB_RefundListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("merchant_pub",
                                              &refund->merchant_pub),
        GNUNET_PQ_result_spec_auto_from_type ("merchant_sig",
                                              &refund->merchant_sig),
        GNUNET_PQ_result_spec_auto_from_type ("h_contract_terms",
                                              &refund->h_contract_terms),
        GNUNET_PQ_result_spec_uint64 ("rtransaction_id",
                                      &refund->rtransaction_id),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &refund->refund_amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                     &refund->refund_fee),
        GNUNET_PQ_result_spec_uint64 ("refund_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (refund);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_REFUND;
    tl->details.refund = refund;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_purse_decision (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_PurseRefundListEntry *prefund;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    prefund = GNUNET_new (struct TALER_EXCHANGEDB_PurseRefundListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("purse_pub",
                                              &prefund->purse_pub),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount_with_fee",
                                     &prefund->refund_amount),
        TALER_PQ_RESULT_SPEC_AMOUNT ("fee_refund",
                                     &prefund->refund_fee),
        GNUNET_PQ_result_spec_uint64 ("purse_decision_serial_id",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (prefund);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_PURSE_REFUND;
    tl->details.purse_refund = prefund;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_old_coin_recoup (void *cls,
                     PGresult *result,
                     unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RecoupRefreshListEntry *recoup;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_RecoupRefreshListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("coin_pub",
                                              &recoup->coin.coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        TALER_PQ_result_spec_denom_sig ("denom_sig",
                                        &recoup->coin.denom_sig),
        GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        chc->failed = true;
        return;
      }
      recoup->old_coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP;
    tl->details.old_coin_recoup = recoup;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_recoup (void *cls,
                 PGresult *result,
                 unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RecoupListEntry *recoup;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_RecoupListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("reserve_pub",
                                              &recoup->reserve_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->h_denom_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_uint64 ("recoup_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_RECOUP;
    tl->details.recoup = recoup;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_recoup_refresh (void *cls,
                         PGresult *result,
                         unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_RecoupRefreshListEntry *recoup;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    recoup = GNUNET_new (struct TALER_EXCHANGEDB_RecoupRefreshListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("old_coin_pub",
                                              &recoup->old_coin_pub),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &recoup->coin_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_blind",
                                              &recoup->coin_blind),
        TALER_PQ_RESULT_SPEC_AMOUNT ("amount",
                                     &recoup->value),
        GNUNET_PQ_result_spec_timestamp ("recoup_timestamp",
                                         &recoup->timestamp),
        GNUNET_PQ_result_spec_auto_from_type ("denom_pub_hash",
                                              &recoup->coin.denom_pub_hash),
        TALER_PQ_result_spec_denom_sig ("denom_sig",
                                        &recoup->coin.denom_sig),
        GNUNET_PQ_result_spec_uint64 ("recoup_refresh_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (recoup);
        chc->failed = true;
        return;
      }
      recoup->coin.coin_pub = *chc->coin_pub;
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_RECOUP_REFRESH;
    tl->details.recoup_refresh = recoup;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Function to be called with the results of a SELECT statement
 * that has returned @a num_results results.
 *
 * @param cls closure of type `struct CoinHistoryContext`
 * @param result the postgres result
 * @param num_results the number of results in @a result
 */
static void
add_coin_reserve_open (void *cls,
                       PGresult *result,
                       unsigned int num_results)
{
  struct CoinHistoryContext *chc = cls;
  struct PostgresClosure *pg = chc->pg;

  for (unsigned int i = 0; i<num_results; i++)
  {
    struct TALER_EXCHANGEDB_ReserveOpenListEntry *role;
    struct TALER_EXCHANGEDB_TransactionList *tl;
    uint64_t serial_id;

    role = GNUNET_new (struct TALER_EXCHANGEDB_ReserveOpenListEntry);
    {
      struct GNUNET_PQ_ResultSpec rs[] = {
        GNUNET_PQ_result_spec_auto_from_type ("reserve_sig",
                                              &role->reserve_sig),
        GNUNET_PQ_result_spec_auto_from_type ("coin_sig",
                                              &role->coin_sig),
        TALER_PQ_RESULT_SPEC_AMOUNT ("contribution",
                                     &role->coin_contribution),
        GNUNET_PQ_result_spec_uint64 ("reserve_open_deposit_uuid",
                                      &serial_id),
        GNUNET_PQ_result_spec_end
      };

      if (GNUNET_OK !=
          GNUNET_PQ_extract_result (result,
                                    rs,
                                    i))
      {
        GNUNET_break (0);
        GNUNET_free (role);
        chc->failed = true;
        return;
      }
    }
    tl = GNUNET_new (struct TALER_EXCHANGEDB_TransactionList);
    tl->next = chc->head;
    tl->type = TALER_EXCHANGEDB_TT_RESERVE_OPEN;
    tl->details.reserve_open = role;
    tl->serial_id = serial_id;
    chc->head = tl;
  }
}


/**
 * Work we need to do.
 */
struct Work
{
  /**
   * SQL prepared statement name.
   */
  const char *statement;

  /**
   * Function to call to handle the result(s).
   */
  GNUNET_PQ_PostgresResultHandler cb;
};


enum GNUNET_DB_QueryStatus
TEH_PG_get_coin_transactions (
  void *cls,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_EXCHANGEDB_TransactionList **tlp)
{
  struct PostgresClosure *pg = cls;
  static const struct Work work[] = {
    /** #TALER_EXCHANGEDB_TT_DEPOSIT */
    { "get_deposit_with_coin_pub",
      &add_coin_deposit },
    /** #TALER_EXCHANGEDB_TT_MELT */
    { "get_refresh_session_by_coin",
      &add_coin_melt },
    /** #TALER_EXCHANGEDB_TT_PURSE_DEPOSIT */
    { "get_purse_deposit_by_coin_pub",
      &add_coin_purse_deposit },
    /** #TALER_EXCHANGEDB_TT_PURSE_REFUND */
    { "get_purse_decision_by_coin_pub",
      &add_coin_purse_decision },
    /** #TALER_EXCHANGEDB_TT_REFUND */
    { "get_refunds_by_coin",
      &add_coin_refund },
    /** #TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP */
    { "recoup_by_old_coin",
      &add_old_coin_recoup },
    /** #TALER_EXCHANGEDB_TT_RECOUP */
    { "recoup_by_coin",
      &add_coin_recoup },
    /** #TALER_EXCHANGEDB_TT_RECOUP_REFRESH */
    { "recoup_by_refreshed_coin",
      &add_coin_recoup_refresh },
    /** #TALER_EXCHANGEDB_TT_RESERVE_OPEN */
    { "reserve_open_by_coin",
      &add_coin_reserve_open },
    { NULL, NULL }
  };
  struct GNUNET_PQ_QueryParam params[] = {
    GNUNET_PQ_query_param_auto_from_type (coin_pub),
    GNUNET_PQ_query_param_end
  };
  enum GNUNET_DB_QueryStatus qs;
  struct CoinHistoryContext chc = {
    .head = NULL,
    .coin_pub = coin_pub,
    .pg = pg,
    .db_cls = cls
  };

  PREPARE (pg,
           "get_deposit_with_coin_pub",
           "SELECT"
           " cdep.amount_with_fee"
           ",denoms.fee_deposit"
           ",denoms.denom_pub_hash"
           ",kc.age_commitment_hash"
           ",bdep.wallet_timestamp"
           ",bdep.refund_deadline"
           ",bdep.wire_deadline"
           ",bdep.merchant_pub"
           ",bdep.h_contract_terms"
           ",bdep.wallet_data_hash"
           ",bdep.wire_salt"
           ",wt.payto_uri"
           ",cdep.coin_sig"
           ",cdep.coin_deposit_serial_id"
           ",bdep.done"
           " FROM coin_deposits cdep"
           " JOIN batch_deposits bdep"
           "   USING (batch_deposit_serial_id)"
           " JOIN wire_targets wt"
           "   USING (wire_target_h_payto)"
           " JOIN known_coins kc"
           "   ON (kc.coin_pub = cdep.coin_pub)"
           " JOIN denominations denoms"
           "   USING (denominations_serial)"
           " WHERE cdep.coin_pub=$1;");
  PREPARE (pg,
           "get_refresh_session_by_coin",
           "SELECT"
           " rc"
           ",old_coin_sig"
           ",amount_with_fee"
           ",denoms.denom_pub_hash"
           ",denoms.fee_refresh"
           ",kc.age_commitment_hash"
           ",melt_serial_id"
           " FROM refresh_commitments"
           " JOIN known_coins kc"
           "   ON (refresh_commitments.old_coin_pub = kc.coin_pub)"
           " JOIN denominations denoms"
           "   USING (denominations_serial)"
           " WHERE old_coin_pub=$1;");
  PREPARE (pg,
           "get_purse_deposit_by_coin_pub",
           "SELECT"
           " partner_base_url"
           ",pd.amount_with_fee"
           ",denoms.fee_deposit"
           ",pd.purse_pub"
           ",kc.age_commitment_hash"
           ",pd.coin_sig"
           ",pd.purse_deposit_serial_id"
           ",pdes.refunded"
           " FROM purse_deposits pd"
           " LEFT JOIN partners"
           "   USING (partner_serial_id)"
           " JOIN purse_requests pr"
           "   USING (purse_pub)"
           " LEFT JOIN purse_decision pdes"
           "   USING (purse_pub)"
           " JOIN known_coins kc"
           "   ON (pd.coin_pub = kc.coin_pub)"
           " JOIN denominations denoms"
           "   USING (denominations_serial)"
           // FIXME: use to-be-created materialized index
           // on coin_pub (query crosses partitions!)
           " WHERE pd.coin_pub=$1;");
  PREPARE (pg,
           "get_refunds_by_coin",
           "SELECT"
           " bdep.merchant_pub"
           ",ref.merchant_sig"
           ",bdep.h_contract_terms"
           ",ref.rtransaction_id"
           ",ref.amount_with_fee"
           ",denom.fee_refund"
           ",ref.refund_serial_id"
           " FROM refunds ref"
           " JOIN coin_deposits cdep"
           "   ON (ref.coin_pub = cdep.coin_pub AND ref.batch_deposit_serial_id = cdep.batch_deposit_serial_id)"
           " JOIN batch_deposits bdep"
           "   ON (ref.batch_deposit_serial_id = bdep.batch_deposit_serial_id)"
           " JOIN known_coins kc"
           "   ON (ref.coin_pub = kc.coin_pub)"
           " JOIN denominations denom"
           "   USING (denominations_serial)"
           " WHERE ref.coin_pub=$1;");
  PREPARE (pg,
           "get_purse_decision_by_coin_pub",
           "SELECT"
           " pdes.purse_pub"
           ",pd.amount_with_fee"
           ",denom.fee_refund"
           ",pdes.purse_decision_serial_id"
           " FROM purse_deposits pd"
           " JOIN purse_decision pdes"
           "   USING (purse_pub)"
           " JOIN known_coins kc"
           "   ON (pd.coin_pub = kc.coin_pub)"
           " JOIN denominations denom"
           "   USING (denominations_serial)"
           " WHERE pd.coin_pub=$1"
           "   AND pdes.refunded;");
  PREPARE (pg,
           "recoup_by_old_coin",
           "SELECT"
           " coins.coin_pub"
           ",coin_sig"
           ",coin_blind"
           ",amount"
           ",recoup_timestamp"
           ",denoms.denom_pub_hash"
           ",coins.denom_sig"
           ",recoup_refresh_uuid"
           " FROM recoup_refresh"
           " JOIN known_coins coins"
           "   USING (coin_pub)"
           " JOIN denominations denoms"
           "   USING (denominations_serial)"
           " WHERE rrc_serial IN"
           "   (SELECT rrc.rrc_serial"
           "    FROM refresh_commitments"
           "       JOIN refresh_revealed_coins rrc"
           "           USING (melt_serial_id)"
           "    WHERE old_coin_pub=$1);");
  PREPARE (pg,
           "recoup_by_coin",
           "SELECT"
           " reserves.reserve_pub"
           ",denoms.denom_pub_hash"
           ",coin_sig"
           ",coin_blind"
           ",amount"
           ",recoup_timestamp"
           ",recoup_uuid"
           " FROM recoup rcp"
           /* NOTE: suboptimal JOIN follows: crosses shards!
              Could theoretically be improved via a materialized
              index. But likely not worth it (query is rare and
              number of reserve shards might be limited) */
           " JOIN reserves_out ro"
           "   USING (reserve_out_serial_id)"
           " JOIN reserves"
           "   USING (reserve_uuid)"
           " JOIN known_coins coins"
           "   USING (coin_pub)"
           " JOIN denominations denoms"
           "   ON (denoms.denominations_serial = coins.denominations_serial)"
           " WHERE coins.coin_pub=$1;");
  /* Used in #postgres_get_coin_transactions() to obtain recoup transactions
     for a refreshed coin */
  PREPARE (pg,
           "recoup_by_refreshed_coin",
           "SELECT"
           " old_coins.coin_pub AS old_coin_pub"
           ",coin_sig"
           ",coin_blind"
           ",amount"
           ",recoup_timestamp"
           ",denoms.denom_pub_hash"
           ",coins.denom_sig"
           ",recoup_refresh_uuid"
           " FROM recoup_refresh"
           "    JOIN refresh_revealed_coins rrc"
           "      USING (rrc_serial)"
           "    JOIN refresh_commitments rfc"
           "      ON (rrc.melt_serial_id = rfc.melt_serial_id)"
           "    JOIN known_coins old_coins"
           "      ON (rfc.old_coin_pub = old_coins.coin_pub)"
           "    JOIN known_coins coins"
           "      ON (recoup_refresh.coin_pub = coins.coin_pub)"
           "    JOIN denominations denoms"
           "      ON (denoms.denominations_serial = coins.denominations_serial)"
           " WHERE coins.coin_pub=$1;");
  PREPARE (pg,
           "reserve_open_by_coin",
           "SELECT"
           " reserve_open_deposit_uuid"
           ",coin_sig"
           ",reserve_sig"
           ",contribution"
           " FROM reserves_open_deposits"
           " WHERE coin_pub=$1;");
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Getting transactions for coin %s\n",
              TALER_B2S (coin_pub));
  for (unsigned int i = 0; NULL != work[i].statement; i++)
  {
    qs = GNUNET_PQ_eval_prepared_multi_select (pg->conn,
                                               work[i].statement,
                                               params,
                                               work[i].cb,
                                               &chc);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Coin %s yielded %d transactions of type %s\n",
                TALER_B2S (coin_pub),
                qs,
                work[i].statement);
    if ( (0 > qs) ||
         (chc.failed) )
    {
      if (NULL != chc.head)
        TEH_COMMON_free_coin_transaction_list (cls,
                                               chc.head);
      *tlp = NULL;
      if (chc.failed)
        qs = GNUNET_DB_STATUS_HARD_ERROR;
      return qs;
    }
  }
  *tlp = chc.head;
  if (NULL == chc.head)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}
