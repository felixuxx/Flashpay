/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU Affero General Public License as
  published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty
  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General
  Public License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_age-withdraw.c
 * @brief Handle /reserves/$RESERVE_PUB/age-withdraw requests
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_age-withdraw.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"

/**
 * Send a response to a "age-withdraw" request.
 *
 * @param connection the connection to send the response to
 * @param ach value the client committed to
 * @param noreveal_index which index will the client not have to reveal
 * @return a MHD status code
 */
static MHD_RESULT
reply_age_withdraw_success (
  struct MHD_Connection *connection,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  uint32_t noreveal_index)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec =
    TALER_exchange_online_age_withdraw_confirmation_sign (
      &TEH_keys_exchange_sign_,
      ach,
      noreveal_index,
      &pub,
      &sig);

  if (TALER_EC_NONE != ec)
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);

  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_OK,
                                    GNUNET_JSON_pack_uint64 ("noreveal_index",
                                                             noreveal_index),
                                    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                                                &sig),
                                    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                                                &pub));
}


/**
 * Context for #age_withdraw_transaction.
 */
struct AgeWithdrawContext
{
  /**
   * KYC status for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash of the wire source URL, needed when kyc is needed.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * The data from the age-withdraw request
   */
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment commitment;

  /**
   * Number of coins/denonations in the reveal
   */
  uint32_t num_coins;

  /**
   * kappa * #num_coins hashes of blinded coin planchets.
   */
  struct TALER_BlindedPlanchet *coin_evs;

  /**
   * #num_coins hashes of the denominations from which the coins are withdrawn.
   * Those must support age restriction.
   */
  struct TALER_DenominationHashP *denoms_h;
};


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls closure, identifies the event type and
 *        account to iterate over events for
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 */
static void
age_withdraw_amount_cb (void *cls,
                        struct GNUNET_TIME_Absolute limit,
                        TALER_EXCHANGEDB_KycAmountCallback cb,
                        void *cb_cls)
{
  struct AgeWithdrawContext *awc = cls;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check during age-withdrawal\n",
              TALER_amount2s (&awc->commitment.amount_with_fee));
  if (GNUNET_OK !=
      cb (cb_cls,
          &awc->commitment.amount_with_fee,
          awc->now.abs_time))
    return;
  qs = TEH_plugin->select_withdraw_amounts_for_kyc_check (TEH_plugin->cls,
                                                          &awc->h_payto,
                                                          limit,
                                                          cb,
                                                          cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this age-withdrawal and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
}


/**
 * Function implementing age withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * Note that "awc->commitment.sig" is set before entering this function as we
 * signed before entering the transaction.
 *
 * @param cls a `struct AgeWithdrawContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
age_withdraw_transaction (void *cls,
                          struct MHD_Connection *connection,
                          MHD_RESULT *mhd_ret)
{
  struct AgeWithdrawContext *awc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool found = false;
  bool balance_ok = false;
  uint64_t ruuid;

  awc->now = GNUNET_TIME_timestamp_get ();
  qs = TEH_plugin->reserves_get_origin (TEH_plugin->cls,
                                        &awc->commitment.reserve_pub,
                                        &awc->h_payto);
  if (qs < 0)
    return qs;

  /* If no results, reserve was created by merge,
     in which case no KYC check is required as the
     merge already did that. */
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    char *kyc_required;

    qs = TALER_KYCLOGIC_kyc_test_required (
      TALER_KYCLOGIC_KYC_TRIGGER_AGE_WITHDRAW,
      &awc->h_payto,
      TEH_plugin->select_satisfied_kyc_processes,
      TEH_plugin->cls,
      &age_withdraw_amount_cb,
      awc,
      &kyc_required);

    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_break (0);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "kyc_test_required");
      }
      return qs;
    }

    if (NULL != kyc_required)
    {
      /* insert KYC requirement into DB! */
      awc->kyc.ok = false;
      return TEH_plugin->insert_kyc_requirement_for_account (
        TEH_plugin->cls,
        kyc_required,
        &awc->h_payto,
        &awc->kyc.requirement_row);
    }
  }

  awc->kyc.ok = true;
  qs = TEH_plugin->do_age_withdraw (TEH_plugin->cls,
                                    &awc->commitment,
                                    &found,
                                    &balance_ok,
                                    &ruuid);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "do_age_withdraw");
    return qs;
  }
  else if (! found)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  else if (! balance_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret = TEH_RESPONSE_reply_reserve_insufficient_balance (
      connection,
      TALER_EC_EXCHANGE_AGE_WITHDRAW_INSUFFICIENT_FUNDS,
      &awc->commitment.amount_with_fee,
      &awc->commitment.reserve_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    TEH_METRICS_num_success[TEH_MT_SUCCESS_AGE_WITHDRAW]++;
  return qs;
}


/**
 * Check if the @a rc is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param rc request context
 * @param[in,out] awc parsed request data
 * @param[out] mret HTTP status, set if we return true
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
request_is_idempotent (struct TEH_RequestContext *rc,
                       struct AgeWithdrawContext *awc,
                       MHD_RESULT *mret)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment commitment;

  qs = TEH_plugin->get_age_withdraw_info (TEH_plugin->cls,
                                          &awc->commitment.reserve_pub,
                                          &awc->commitment.h_commitment,
                                          &commitment);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mret = TALER_MHD_reply_with_error (rc->connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_FETCH_FAILED,
                                          "get_age_withdraw_info");
    return true; /* well, kind-of */
  }

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return false;

  /* generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_AGE_WITHDRAW]++;
  *mret = reply_age_withdraw_success (rc->connection,
                                      &commitment.h_commitment,
                                      commitment.noreveal_index);
  return true;
}


MHD_RESULT
TEH_handler_age_withdraw (struct TEH_RequestContext *rc,
                          const struct TALER_ReservePublicKeyP *reserve_pub,
                          const json_t *root)
{
  MHD_RESULT mhd_ret;
  struct AgeWithdrawContext awc = {0};
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &awc.commitment.reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("h_commitment",
                                 &awc.commitment.h_commitment),
    TALER_JSON_spec_amount ("amount",
                            TEH_currency,
                            &awc.commitment.amount_with_fee),
    GNUNET_JSON_spec_uint16 ("max_age",
                             &awc.commitment.max_age),
    GNUNET_JSON_spec_end ()
  };

  awc.commitment.reserve_pub = *reserve_pub;


  /* Parse the JSON body */
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  do {
    /* If request was made before successfully, return the previous answer */
    if (request_is_idempotent (rc,
                               &awc,
                               &mhd_ret))
      break;

    /* Verify the signature of the request body with the reserve key */
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_age_withdraw_verify (&awc.commitment.h_commitment,
                                          &awc.commitment.amount_with_fee,
                                          awc.commitment.max_age,
                                          &awc.commitment.reserve_pub,
                                          &awc.commitment.reserve_sig))
    {
      GNUNET_break_op (0);
      mhd_ret = TALER_MHD_reply_with_error (rc->connection,
                                            MHD_HTTP_FORBIDDEN,
                                            TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                            NULL);
      break;
    }

    /* Run the transaction */
    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "run age withdraw",
                                TEH_MT_REQUEST_AGE_WITHDRAW,
                                &mhd_ret,
                                &age_withdraw_transaction,
                                &awc))
      break;

    /* Clean up and send back final response */
    GNUNET_JSON_parse_free (spec);

    if (! awc.kyc.ok)
      return TEH_RESPONSE_reply_kyc_required (rc->connection,
                                              &awc.h_payto,
                                              &awc.kyc);

    return reply_age_withdraw_success (rc->connection,
                                       &awc.commitment.h_commitment,
                                       awc.commitment.noreveal_index);
  } while(0);

  GNUNET_JSON_parse_free (spec);
  return mhd_ret;

}


/* end of taler-exchange-httpd_age-withdraw.c */
