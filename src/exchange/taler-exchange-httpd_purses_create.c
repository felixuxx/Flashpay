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
 * @file taler-exchange-httpd_purses_create.c
 * @brief Handle /purses/$PID/create requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_common_deposit.h"
#include "taler-exchange-httpd_purses_create.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for #create_transaction.
 */
struct PurseCreateContext
{

  /**
   * Total actually deposited by all the coins.
   */
  struct TALER_Amount deposit_total;

  /**
   * Our current time.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Merge key for the purse.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Encrypted contract of for the purse.
   */
  struct TALER_EncryptedContract econtract;

  /**
   * Signature of the client affiming this request.
   */
  struct TALER_PurseContractSignatureP purse_sig;

  /**
   * Fundamental details about the purse.
   */
  struct TEH_PurseDetails pd;

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

  /**
   * Do we have an @e econtract?
   */
  bool no_econtract;

};


/**
 * Execute database transaction for /purses/$PID/create.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST NOT queue
 * a MHD response.  IF it returns an hard error, the transaction logic MUST
 * queue a MHD response and set @a mhd_ret.  IF it returns the soft error
 * code, the function MAY be called again to retry and MUST not queue a MHD
 * response.
 *
 * @param cls a `struct PurseCreateContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
create_transaction (void *cls,
                    struct MHD_Connection *connection,
                    MHD_RESULT *mhd_ret)
{
  struct PurseCreateContext *pcc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount purse_fee;
  bool in_conflict = true;

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &purse_fee));
  /* 1) create purse */
  qs = TEH_plugin->insert_purse_request (
    TEH_plugin->cls,
    &pcc->pd.purse_pub,
    &pcc->merge_pub,
    pcc->pd.purse_expiration,
    &pcc->pd.h_contract_terms,
    pcc->min_age,
    TALER_WAMF_MODE_MERGE_FULLY_PAID_PURSE,
    &purse_fee,
    &pcc->pd.target_amount,
    &pcc->purse_sig,
    &in_conflict);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    TALER_LOG_WARNING (
      "Failed to store create purse information in database\n");
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_INTERNAL_SERVER_ERROR,
                                  TALER_EC_GENERIC_DB_STORE_FAILED,
                                  "purse create");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (in_conflict)
  {
    struct TALER_PurseMergePublicKeyP merge_pub;
    struct GNUNET_TIME_Timestamp purse_expiration;
    struct TALER_PrivateContractHashP h_contract_terms;
    struct TALER_Amount target_amount;
    struct TALER_Amount balance;
    struct TALER_PurseContractSignatureP purse_sig;
    uint32_t min_age;

    TEH_plugin->rollback (TEH_plugin->cls);
    qs = TEH_plugin->get_purse_request (TEH_plugin->cls,
                                        &pcc->pd.purse_pub,
                                        &merge_pub,
                                        &purse_expiration,
                                        &h_contract_terms,
                                        &min_age,
                                        &target_amount,
                                        &balance,
                                        &purse_sig);
    if (qs < 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
      TALER_LOG_WARNING ("Failed to fetch purse information from database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "select purse request");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    *mhd_ret
      = TALER_MHD_REPLY_JSON_PACK (
          connection,
          MHD_HTTP_CONFLICT,
          TALER_JSON_pack_ec (
            TALER_EC_EXCHANGE_PURSE_CREATE_CONFLICTING_META_DATA),
          TALER_JSON_pack_amount ("amount",
                                  &target_amount),
          GNUNET_JSON_pack_uint64 ("min_age",
                                   min_age),
          GNUNET_JSON_pack_timestamp ("purse_expiration",
                                      purse_expiration),
          GNUNET_JSON_pack_data_auto ("purse_sig",
                                      &purse_sig),
          GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                      &h_contract_terms),
          GNUNET_JSON_pack_data_auto ("merge_pub",
                                      &merge_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  /* 2) deposit all coins */
  for (unsigned int i = 0; i<pcc->num_coins; i++)
  {
    struct TEH_PurseDepositedCoin *coin = &pcc->coins[i];
    bool balance_ok = false;
    bool conflict = true;
    bool too_late = true;

    qs = TEH_make_coin_known (&coin->cpi,
                              connection,
                              &coin->known_coin_id,
                              mhd_ret);
    if (qs < 0)
      return qs;
    qs = TEH_plugin->do_purse_deposit (TEH_plugin->cls,
                                       &pcc->pd.purse_pub,
                                       &coin->cpi.coin_pub,
                                       &coin->amount,
                                       &coin->coin_sig,
                                       &coin->amount_minus_fee,
                                       &balance_ok,
                                       &too_late,
                                       &conflict);
    if (qs <= 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0 != qs);
      TALER_LOG_WARNING (
        "Failed to store purse deposit information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "purse create deposit");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (! balance_ok)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Coin %s has insufficient balance for purse deposit of amount %s\n",
                  TALER_B2S (&coin->cpi.coin_pub),
                  TALER_amount2s (&coin->amount));
      *mhd_ret
        = TEH_RESPONSE_reply_coin_insufficient_funds (
            connection,
            TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
            &coin->cpi.denom_pub_hash,
            &coin->cpi.coin_pub);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (too_late)
    {
      *mhd_ret
        = TALER_MHD_reply_with_ec (
            connection,
            TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
            "too late to deposit on purse creation");
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
                                          &pcc->pd.purse_pub,
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
            GNUNET_JSON_pack_data_auto ("coin_sig",
                                        &coin_sig),
            GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                        &h_denom_pub),
            GNUNET_JSON_pack_data_auto ("h_age_restrictions",
                                        &phac),
            GNUNET_JSON_pack_allow_null (
              GNUNET_JSON_pack_string ("partner_url",
                                       partner_url)),
            TALER_JSON_pack_amount ("amount",
                                    &amount));
      GNUNET_free (partner_url);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  /* 3) if present, persist contract */
  if (! pcc->no_econtract)
  {
    in_conflict = true;
    qs = TEH_plugin->insert_contract (TEH_plugin->cls,
                                      &pcc->pd.purse_pub,
                                      &pcc->econtract,
                                      &in_conflict);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING ("Failed to store purse information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "purse create contract");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (in_conflict)
    {
      struct TALER_EncryptedContract econtract;
      struct GNUNET_HashCode h_econtract;

      qs = TEH_plugin->select_contract_by_purse (
        TEH_plugin->cls,
        &pcc->pd.purse_pub,
        &econtract);
      if (qs <= 0)
      {
        if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
          return qs;
        GNUNET_break (0 != qs);
        TALER_LOG_WARNING (
          "Failed to store fetch contract information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "select contract");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      GNUNET_CRYPTO_hash (econtract.econtract,
                          econtract.econtract_size,
                          &h_econtract);
      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_CONFLICT,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_PURSE_ECONTRACT_CONFLICTING_META_DATA),
            GNUNET_JSON_pack_data_auto ("h_econtract",
                                        &h_econtract),
            GNUNET_JSON_pack_data_auto ("econtract_sig",
                                        &econtract.econtract_sig),
            GNUNET_JSON_pack_data_auto ("contract_pub",
                                        &econtract.contract_pub));
      GNUNET_free (econtract.econtract);
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
            struct PurseCreateContext *pcc,
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
         &pcc->pd.purse_pub,
         pcc->min_age)))
    return iret;
  if (0 >
      TALER_amount_add (&pcc->deposit_total,
                        &pcc->deposit_total,
                        &coin->amount_minus_fee))
  {
    GNUNET_break (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_GENERIC_FAILED_COMPUTE_AMOUNT,
                                        "total deposit contribution"))
           ? GNUNET_NO
           : GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


MHD_RESULT
TEH_handler_purses_create (
  struct TEH_RequestContext *rc,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *root)
{
  struct MHD_Connection *connection = rc->connection;
  struct PurseCreateContext pcc = {
    .pd.purse_pub = *purse_pub,
    .exchange_timestamp = GNUNET_TIME_timestamp_get ()
  };
  const json_t *deposits;
  json_t *deposit;
  unsigned int idx;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("amount",
                            TEH_currency,
                            &pcc.pd.target_amount),
    GNUNET_JSON_spec_uint32 ("min_age",
                             &pcc.min_age),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_econtract ("econtract",
                                 &pcc.econtract),
      &pcc.no_econtract),
    GNUNET_JSON_spec_fixed_auto ("merge_pub",
                                 &pcc.merge_pub),
    GNUNET_JSON_spec_fixed_auto ("purse_sig",
                                 &pcc.purse_sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &pcc.pd.h_contract_terms),
    GNUNET_JSON_spec_array_const ("deposits",
                                  &deposits),
    GNUNET_JSON_spec_timestamp ("purse_expiration",
                                &pcc.pd.purse_expiration),
    GNUNET_JSON_spec_end ()
  };
  const struct TEH_GlobalFee *gf;

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
  if (GNUNET_TIME_timestamp_cmp (pcc.pd.purse_expiration,
                                 <,
                                 pcc.exchange_timestamp))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_PURSE_CREATE_EXPIRATION_BEFORE_NOW,
                                       NULL);
  }
  if (GNUNET_TIME_absolute_is_never (pcc.pd.purse_expiration.abs_time))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_PURSE_CREATE_EXPIRATION_IS_NEVER,
                                       NULL);
  }
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
    struct TEH_KeyStateHandle *keys;

    keys = TEH_keys_get_state ();
    if (NULL == keys)
    {
      GNUNET_break (0);
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         NULL);
    }
    gf = TEH_keys_global_fee_by_time (keys,
                                      pcc.exchange_timestamp);
  }
  if (NULL == gf)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Cannot create purse: global fees not configured!\n");
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_GLOBAL_FEES_MISSING,
                                       NULL);
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
      for (unsigned int i = 0; i<idx; i++)
        TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
      GNUNET_free (pcc.coins);
      GNUNET_JSON_parse_free (spec);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
  }

  if (0 < TALER_amount_cmp (&gf->fees.purse,
                            &pcc.deposit_total))
  {
    GNUNET_break_op (0);
    GNUNET_free (pcc.coins);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_CREATE_PURSE_NEGATIVE_VALUE_AFTER_FEE,
                                       NULL);
  }
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;

  if (GNUNET_OK !=
      TALER_wallet_purse_create_verify (
        pcc.pd.purse_expiration,
        &pcc.pd.h_contract_terms,
        &pcc.merge_pub,
        pcc.min_age,
        &pcc.pd.target_amount,
        &pcc.pd.purse_pub,
        &pcc.purse_sig))
  {
    TALER_LOG_WARNING ("Invalid signature on /purses/$PID/create request\n");
    for (unsigned int i = 0; i<pcc.num_coins; i++)
      TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
    GNUNET_free (pcc.coins);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_PURSE_CREATE_SIGNATURE_INVALID,
                                       NULL);
  }
  if ( (! pcc.no_econtract) &&
       (GNUNET_OK !=
        TALER_wallet_econtract_upload_verify (pcc.econtract.econtract,
                                              pcc.econtract.econtract_size,
                                              &pcc.econtract.contract_pub,
                                              purse_pub,
                                              &pcc.econtract.econtract_sig)) )
  {
    TALER_LOG_WARNING ("Invalid signature on /purses/$PID/create request\n");
    for (unsigned int i = 0; i<pcc.num_coins; i++)
      TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
    GNUNET_free (pcc.coins);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_PURSE_ECONTRACT_SIGNATURE_INVALID,
                                       NULL);
  }


  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    for (unsigned int i = 0; i<pcc.num_coins; i++)
      TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
    GNUNET_free (pcc.coins);
    GNUNET_JSON_parse_free (spec);
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
                                "execute purse create",
                                TEH_MT_REQUEST_PURSE_CREATE,
                                &mhd_ret,
                                &create_transaction,
                                &pcc))
    {
      for (unsigned int i = 0; i<pcc.num_coins; i++)
        TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
      GNUNET_free (pcc.coins);
      GNUNET_JSON_parse_free (spec);
      return mhd_ret;
    }
  }

  /* generate regular response */
  {
    MHD_RESULT res;

    res = TEH_RESPONSE_reply_purse_created (connection,
                                            pcc.exchange_timestamp,
                                            &pcc.deposit_total,
                                            &pcc.pd);
    for (unsigned int i = 0; i<pcc.num_coins; i++)
      TEH_common_purse_deposit_free_coin (&pcc.coins[i]);
    GNUNET_free (pcc.coins);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_purses_create.c */
