/*
  This file is part of TALER
  Copyright (C) 2014-2017, 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_db.c
 * @brief Generic database operations for the exchange.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <pthread.h>
#include <jansson.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_db.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Send a response for a failed request.  The transaction history of the given
 * coin demonstrates that the @a residual value of the coin is below the @a
 * requested contribution of the coin for the operation.  Thus, the exchange
 * refuses the operation.
 *
 * @param connection the connection to send the response to
 * @param coin_pub public key of the coin
 * @param coin_value original value of the coin
 * @param tl transaction history for the coin
 * @param requested how much this coin was supposed to contribute, including fee
 * @param residual remaining value of the coin (after subtracting @a tl)
 * @return a MHD result code
 */
static MHD_RESULT
reply_insufficient_funds (
  struct MHD_Connection *connection,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *coin_value,
  struct TALER_EXCHANGEDB_TransactionList *tl,
  const struct TALER_Amount *requested,
  const struct TALER_Amount *residual)
{
  json_t *history;

  history = TEH_RESPONSE_compile_transaction_history (coin_pub,
                                                      tl);
  if (NULL == history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_CONFLICT,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    TALER_JSON_pack_amount ("original_value",
                            coin_value),
    TALER_JSON_pack_amount ("residual_value",
                            residual),
    TALER_JSON_pack_amount ("requested_value",
                            requested),
    GNUNET_JSON_pack_array_steal ("history",
                                  history));
}


/**
 * How often should we retry a transaction before giving up
 * (for transactions resulting in serialization/dead locks only).
 *
 * The current value is likely too high for production. We might want to
 * benchmark good values once we have a good database setup.  The code is
 * expected to work correctly with any positive value, albeit inefficiently if
 * we too aggressively force clients to retry the HTTP request merely because
 * we have database serialization issues.
 */
#define MAX_TRANSACTION_COMMIT_RETRIES 100


/**
 * Ensure coin is known in the database, and handle conflicts and errors.
 *
 * @param coin the coin to make known
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status, negative on error (@a mhd_ret will be set in this case)
 */
enum GNUNET_DB_QueryStatus
TEH_make_coin_known (const struct TALER_CoinPublicInfo *coin,
                     struct MHD_Connection *connection,
                     MHD_RESULT *mhd_ret)
{
  enum TALER_EXCHANGEDB_CoinKnownStatus cks;

  /* make sure coin is 'known' in database */
  cks = TEH_plugin->ensure_coin_known (TEH_plugin->cls,
                                       coin);
  switch (cks)
  {
  case TALER_EXCHANGEDB_CKS_ADDED:
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  case TALER_EXCHANGEDB_CKS_PRESENT:
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  case TALER_EXCHANGEDB_CKS_SOFT_FAIL:
    return GNUNET_DB_STATUS_SOFT_ERROR;
  case TALER_EXCHANGEDB_CKS_HARD_FAIL:
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_STORE_FAILED,
                                    NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  case TALER_EXCHANGEDB_CKS_CONFLICT:
    break;
  }

  {
    struct TALER_EXCHANGEDB_TransactionList *tl;
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                            &coin->coin_pub,
                                            GNUNET_NO,
                                            &tl);
    if (0 > qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          NULL);
      return qs;
    }
    // FIXME: why do we even return the transaction
    // history here!? This is a coin with multiple
    // associated denominations, after all...
    // => this is probably the wrong call, as this
    // is NOT about insufficient funds!
    *mhd_ret
      = TEH_RESPONSE_reply_coin_insufficient_funds (
          connection,
          TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY,
          &coin->coin_pub,
          tl);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
}


enum GNUNET_DB_QueryStatus
TEH_check_coin_balance (struct MHD_Connection *connection,
                        const struct TALER_CoinSpendPublicKeyP *coin_pub,
                        const struct TALER_Amount *coin_value,
                        const struct TALER_Amount *op_cost,
                        bool check_recoup,
                        bool zombie_required,
                        MHD_RESULT *mhd_ret)
{
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_Amount spent;
  enum GNUNET_DB_QueryStatus qs;

  /* Start with zero cost, as we already added this melt transaction
     to the DB, so we will see it again during the queries below. */
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &spent));

  /* get historic transaction costs of this coin, including recoups as
     we might be a zombie coin */
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          coin_pub,
                                          check_recoup,
                                          &tl);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "coin transaction history");
    return qs;
  }
  if (zombie_required)
  {
    /* The denomination key is only usable for a melt if this is a true
       zombie coin, i.e. it was refreshed and the resulting fresh coin was
       then recouped. Check that this is truly the case. */
    for (struct TALER_EXCHANGEDB_TransactionList *tp = tl;
         NULL != tp;
         tp = tp->next)
    {
      if (TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP == tp->type)
      {
        zombie_required = false; /* clear flag: was satisfied! */
        break;
      }
    }
    if (zombie_required)
    {
      /* zombie status not satisfied */
      GNUNET_break_op (0);
      TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                              tl);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_EXCHANGE_MELT_COIN_EXPIRED_NO_ZOMBIE,
                                             NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_calculate_transaction_list_totals (tl,
                                                          &spent,
                                                          &spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_EXCHANGE_GENERIC_COIN_HISTORY_COMPUTATION_FAILED,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Refuse to refresh when the coin's value is insufficient
     for the cost of all transactions. */
  if (0 > TALER_amount_cmp (coin_value,
                            &spent))
  {
    struct TALER_Amount coin_residual;
    struct TALER_Amount spent_already;

    /* First subtract the melt cost from 'spent' to
       compute the total amount already spent of the coin */
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&spent_already,
                                          &spent,
                                          op_cost));
    /* The residual coin value is the original coin value minus
       what we have spent (before the melt) */
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&coin_residual,
                                          coin_value,
                                          &spent_already));
    *mhd_ret = reply_insufficient_funds (
      connection,
      coin_pub,
      coin_value,
      tl,
      op_cost,
      &coin_residual);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* we're good, coin has sufficient funds to be melted */
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


enum GNUNET_GenericReturnValue
TEH_DB_run_transaction (struct MHD_Connection *connection,
                        const char *name,
                        enum TEH_MetricType mt,
                        MHD_RESULT *mhd_ret,
                        TEH_DB_TransactionCallback cb,
                        void *cb_cls)
{
  if (NULL != mhd_ret)
    *mhd_ret = -1; /* set to invalid value, to help detect bugs */
  if (GNUNET_OK !=
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    if (NULL != mhd_ret)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_SETUP_FAILED,
                                             NULL);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (mt < TEH_MT_COUNT);
  TEH_METRICS_num_requests[mt]++;
  for (unsigned int retries = 0;
       retries < MAX_TRANSACTION_COMMIT_RETRIES;
       retries++)
  {
    enum GNUNET_DB_QueryStatus qs;

    if (GNUNET_OK !=
        TEH_plugin->start (TEH_plugin->cls,
                           name))
    {
      GNUNET_break (0);
      if (NULL != mhd_ret)
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_START_FAILED,
                                               NULL);
      return GNUNET_SYSERR;
    }
    qs = cb (cb_cls,
             connection,
             mhd_ret);
    if (0 > qs)
      TEH_plugin->rollback (TEH_plugin->cls);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      return GNUNET_SYSERR;
    if (0 <= qs)
    {
      qs = TEH_plugin->commit (TEH_plugin->cls);
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        TEH_plugin->rollback (TEH_plugin->cls);
        if (NULL != mhd_ret)
          *mhd_ret = TALER_MHD_reply_with_error (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 TALER_EC_GENERIC_DB_COMMIT_FAILED,
                                                 NULL);
        return GNUNET_SYSERR;
      }
      if (0 > qs)
        TEH_plugin->rollback (TEH_plugin->cls);
    }
    /* make sure callback did not violate invariants! */
    GNUNET_assert ( (NULL == mhd_ret) ||
                    (-1 == (int) *mhd_ret) );
    if (0 <= qs)
      return GNUNET_OK;
    TEH_METRICS_num_conflict[mt]++;
  }
  TALER_LOG_ERROR ("Transaction `%s' commit failed %u times\n",
                   name,
                   MAX_TRANSACTION_COMMIT_RETRIES);
  if (NULL != mhd_ret)
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                           NULL);
  return GNUNET_SYSERR;
}


/* end of taler-exchange-httpd_db.c */
