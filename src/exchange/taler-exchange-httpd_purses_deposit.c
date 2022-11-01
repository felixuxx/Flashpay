/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_purses_deposit.c
 * @brief Handle /purses/$PID/deposit requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_dbevents.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_common_deposit.h"
#include "taler-exchange-httpd_purses_deposit.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for #deposit_transaction.
 */
struct PurseDepositContext
{
  /**
   * Public key of the purse we are creating.
   */
  const struct TALER_PurseContractPublicKeyP *purse_pub;

  /**
   * Total amount to be put into the purse.
   */
  struct TALER_Amount amount;

  /**
   * Total actually deposited by all the coins.
   */
  struct TALER_Amount deposit_total;

  /**
   * When should the purse expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Hash of the contract (needed for signing).
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Our current time.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Array of coins being deposited.
   */
  struct TEH_PurseDepositedCoin *coins;

  /**
   * Length of the @e coins array.
   */
  unsigned int num_coins;

  /**
   * Minimum age for deposits into this purse.
   */
  uint32_t min_age;
};


/**
 * Send confirmation of purse creation success to client.
 *
 * @param connection connection to the client
 * @param pcc details about the request that succeeded
 * @return MHD result code
 */
static MHD_RESULT
reply_deposit_success (struct MHD_Connection *connection,
                       const struct PurseDepositContext *pcc)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_purse_created_sign (
         &TEH_keys_exchange_sign_,
         pcc->exchange_timestamp,
         pcc->purse_expiration,
         &pcc->amount,
         &pcc->deposit_total,
         pcc->purse_pub,
         &pcc->h_contract_terms,
         &pub,
         &sig)))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("total_deposited",
                            &pcc->deposit_total),
    TALER_JSON_pack_amount ("purse_value_after_fees",
                            &pcc->amount),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                pcc->exchange_timestamp),
    GNUNET_JSON_pack_timestamp ("purse_expiration",
                                pcc->purse_expiration),
    GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                &pcc->h_contract_terms),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Execute database transaction for /purses/$PID/deposit.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST NOT queue
 * a MHD response.  IF it returns an hard error, the transaction logic MUST
 * queue a MHD response and set @a mhd_ret.  IF it returns the soft error
 * code, the function MAY be called again to retry and MUST not queue a MHD
 * response.
 *
 * @param cls a `struct PurseDepositContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
deposit_transaction (void *cls,
                     struct MHD_Connection *connection,
                     MHD_RESULT *mhd_ret)
{
  struct PurseDepositContext *pcc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  for (unsigned int i = 0; i<pcc->num_coins; i++)
  {
    struct TEH_PurseDepositedCoin *coin = &pcc->coins[i];
    bool balance_ok = false;
    bool conflict = true;

    qs = TEH_make_coin_known (&coin->cpi,
                              connection,
                              &coin->known_coin_id,
                              mhd_ret);
    if (qs < 0)
      return qs;
    qs = TEH_plugin->do_purse_deposit (TEH_plugin->cls,
                                       pcc->purse_pub,
                                       &coin->cpi.coin_pub,
                                       &coin->amount,
                                       &coin->coin_sig,
                                       &coin->amount_minus_fee,
                                       &balance_ok,
                                       &conflict);
    if (qs <= 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to store purse deposit information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "do purse deposit");
      return qs;
    }
    if (! balance_ok)
    {
      *mhd_ret
        = TEH_RESPONSE_reply_coin_insufficient_funds (
            connection,
            TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
            &coin->cpi.denom_pub_hash,
            &coin->cpi.coin_pub);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (conflict)
    {
      struct TALER_Amount amount;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinSpendSignatureP coin_sig;
      struct TALER_DenominationHashP h_denom_pub;
      struct TALER_AgeCommitmentHash phac;
      char *partner_url = NULL;

      TEH_plugin->rollback (TEH_plugin->cls);
      qs = TEH_plugin->get_purse_deposit (TEH_plugin->cls,
                                          pcc->purse_pub,
                                          &coin->cpi.coin_pub,
                                          &amount,
                                          &h_denom_pub,
                                          &phac,
                                          &coin_sig,
                                          &partner_url);
      if (qs < 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
        TALER_LOG_WARNING (
          "Failed to fetch purse deposit information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "get purse deposit");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }

      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_CONFLICT,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_PURSE_DEPOSIT_CONFLICTING_META_DATA),
            GNUNET_JSON_pack_data_auto ("coin_pub",
                                        &coin_pub),
            GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                        &h_denom_pub),
            GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                        &phac),
            GNUNET_JSON_pack_data_auto ("coin_sig",
                                        &coin_sig),
            GNUNET_JSON_pack_allow_null (
              GNUNET_JSON_pack_string ("partner_url",
                                       partner_url)),
            TALER_JSON_pack_amount ("amount",
                                    &amount));
      GNUNET_free (partner_url);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return qs;
}


/**
 * Parse a coin and check signature of the coin and the denomination
 * signature over the coin.
 *
 * @param[in,out] connection our HTTP connection
 * @param[in,out] pcc request context
 * @param[out] coin coin to initialize
 * @param jcoin coin to parse
 * @return #GNUNET_OK on success, #GNUNET_NO if an error was returned,
 *         #GNUNET_SYSERR on failure and no error could be returned
 */
static enum GNUNET_GenericReturnValue
parse_coin (struct MHD_Connection *connection,
            struct PurseDepositContext *pcc,
            struct TEH_PurseDepositedCoin *coin,
            const json_t *jcoin)
{
  enum GNUNET_GenericReturnValue iret;

  if (GNUNET_OK !=
      (iret = TEH_common_purse_deposit_parse_coin (connection,
                                                   coin,
                                                   jcoin)))
    return iret;
  if (GNUNET_OK !=
      (iret = TEH_common_deposit_check_purse_deposit (
         connection,
         coin,
         pcc->purse_pub,
         pcc->min_age)))
    return iret;
  if (0 >
      TALER_amount_add (&pcc->deposit_total,
                        &pcc->deposit_total,
                        &coin->amount_minus_fee))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_FAILED_COMPUTE_AMOUNT,
                                       "total deposit contribution");
  }
  return GNUNET_OK;
}


MHD_RESULT
TEH_handler_purses_deposit (
  struct MHD_Connection *connection,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *root)
{
  struct PurseDepositContext pcc = {
    .purse_pub = purse_pub,
    .exchange_timestamp = GNUNET_TIME_timestamp_get ()
  };
  json_t *deposits;
  json_t *deposit;
  unsigned int idx;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("deposits",
                           &deposits),
    GNUNET_JSON_spec_end ()
  };

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
      return MHD_NO; /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      GNUNET_break_op (0);
      return MHD_YES; /* failure */
    }
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &pcc.deposit_total));
  pcc.num_coins = json_array_size (deposits);
  if ( (0 == pcc.num_coins) ||
       (pcc.num_coins > TALER_MAX_FRESH_COINS) )
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "deposits");
  }

  {
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_TIME_Timestamp create_timestamp;
    struct GNUNET_TIME_Timestamp merge_timestamp;

    qs = TEH_plugin->select_purse (
      TEH_plugin->cls,
      pcc.purse_pub,
      &create_timestamp,
      &pcc.purse_expiration,
      &pcc.amount,
      &pcc.deposit_total,
      &pcc.h_contract_terms,
      &merge_timestamp);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "select purse");
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "select purse");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_PURSE_UNKNOWN,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break; /* handled below */
    }
    if (GNUNET_TIME_absolute_is_past (pcc.purse_expiration.abs_time))
    {
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_GONE,
                                         TALER_EC_EXCHANGE_GENERIC_PURSE_EXPIRED,
                                         NULL);
    }
  }

  /* parse deposits */
  pcc.coins = GNUNET_new_array (pcc.num_coins,
                                struct TEH_PurseDepositedCoin);
  json_array_foreach (deposits, idx, deposit)
  {
    enum GNUNET_GenericReturnValue res;
    struct TEH_PurseDepositedCoin *coin = &pcc.coins[idx];

    res = parse_coin (connection,
                      &pcc,
                      coin,
                      deposit);
    if (GNUNET_OK != res)
    {
      GNUNET_JSON_parse_free (spec);
      for (unsigned int i = 0; i<idx; i++)
        TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
      GNUNET_free (pcc.coins);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
  }

  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    for (unsigned int i = 0; i<pcc.num_coins; i++)
      TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
    GNUNET_free (pcc.coins);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_START_FAILED,
                                       "preflight failure");
  }

  /* execute transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "execute purse deposit",
                                TEH_MT_REQUEST_PURSE_DEPOSIT,
                                &mhd_ret,
                                &deposit_transaction,
                                &pcc))
    {
      GNUNET_JSON_parse_free (spec);
      for (unsigned int i = 0; i<pcc.num_coins; i++)
        TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
      GNUNET_free (pcc.coins);
      return mhd_ret;
    }
  }
  {
    struct TALER_PurseEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_PURSE_DEPOSITED),
      .purse_pub = *pcc.purse_pub
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Notifying about purse deposit %s\n",
                TALER_B2S (pcc.purse_pub));
    TEH_plugin->event_notify (TEH_plugin->cls,
                              &rep.header,
                              NULL,
                              0);
  }

  /* generate regular response */
  {
    MHD_RESULT res;

    res = reply_deposit_success (connection,
                                 &pcc);
    for (unsigned int i = 0; i<pcc.num_coins; i++)
      TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
    GNUNET_free (pcc.coins);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_purses_deposit.c */
