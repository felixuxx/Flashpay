/*
  This file is part of TALER
  Copyright (C) 2023, 2024 Taler Systems SA

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
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"
#include "taler_error_codes.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_age-withdraw.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler_util.h"


/**
 * Context for #age_withdraw_transaction.
 */
struct AgeWithdrawContext
{

  /**
   * Kept in a DLL.
   */
  struct AgeWithdrawContext *next;

  /**
   * Kept in a DLL.
   */
  struct AgeWithdrawContext *prev;

  /**
   * Handle for the legitimization check.
   */
  struct TEH_LegitimizationCheckHandle *lch;

  /**
   * request context
   */
  const struct TEH_RequestContext *rc;

  /**
   * Response to return, if set.
   */
  struct MHD_Response *response;

  /**
   * Public key of the reserve.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * KYC status for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Set to the hash of the normalized payto URI that established
   * the reserve.
   */
  struct TALER_NormalizedPaytoHashP h_normalized_payto;

  /**
   * value the client committed to
   */
  struct TALER_AgeWithdrawCommitmentHashP ach;

  /**
   * Timestamp
   */
  struct GNUNET_TIME_Timestamp now;

  /**
   * The data from the age-withdraw request, as we persist it
   */
  struct TALER_EXCHANGEDB_AgeWithdraw commitment;

  /**
   * HTTP status to return with @e response, or 0.
   */
  unsigned int http_status;

  /**
   * Number of coins/denonations in the reveal
   */
  unsigned int num_coins;

  /**
   * #num_coins * #kappa hashes of blinded coin planchets.
   */
  struct TALER_BlindedPlanchet (*coin_evs) [ TALER_CNC_KAPPA];

  /**
   * #num_coins hashes of the denominations from which the coins are withdrawn.
   * Those must support age restriction.
   */
  struct TALER_DenominationHashP *denom_hs;

  /**
   * Current processing phase we are in.
   */
  enum
  {
    AWC_PHASE_CHECK_KEYS = 1,
    AWC_PHASE_CHECK_RESERVE_SIGNATURE,
    AWC_PHASE_RUN_LEGI_CHECK,
    AWC_PHASE_SUSPENDED,
    AWC_PHASE_CHECK_KYC_RESULT,
    AWC_PHASE_PREPARE_TRANSACTION,
    AWC_PHASE_RUN_TRANSACTION,
    AWC_PHASE_GENERATE_REPLY_SUCCESS,
    AWC_PHASE_GENERATE_REPLY_FAILURE,
    AWC_PHASE_RETURN_YES,
    AWC_PHASE_RETURN_NO
  } phase;

};


/**
 * Kept in a DLL.
 */
static struct AgeWithdrawContext *awc_head;

/**
 * Kept in a DLL.
 */
static struct AgeWithdrawContext *awc_tail;


void
TEH_age_withdraw_cleanup ()
{
  struct AgeWithdrawContext *awc;

  while (NULL != (awc = awc_head))
  {
    GNUNET_CONTAINER_DLL_remove (awc_head,
                                 awc_tail,
                                 awc);
    MHD_resume_connection (awc->rc->connection);
  }
}


/**
 * Terminate the main loop by returning the final
 * result.
 *
 * @param[in,out] awc context to update phase for
 * @param mres MHD status to return
 */
static void
finish_loop (struct AgeWithdrawContext *awc,
             MHD_RESULT mres)
{
  awc->phase = (MHD_YES == mres)
    ? AWC_PHASE_RETURN_YES
    : AWC_PHASE_RETURN_NO;
}


/**
 * Send a response to a "age-withdraw" request.
 *
 * @param[in,out] awc context for the operation
 */
static void
reply_age_withdraw_success (
  struct AgeWithdrawContext *awc)
{
  struct MHD_Connection *connection
    = awc->rc->connection;
  const struct TALER_AgeWithdrawCommitmentHashP *ach
    = &awc->commitment.h_commitment;
  uint32_t noreveal_index
    = awc->commitment.noreveal_index;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  ec = TALER_exchange_online_age_withdraw_confirmation_sign (
    &TEH_keys_exchange_sign_,
    ach,
    noreveal_index,
    &pub,
    &sig);
  if (TALER_EC_NONE != ec)
  {
    finish_loop (awc,
                 TALER_MHD_reply_with_ec (connection,
                                          ec,
                                          NULL));
    return;
  }
  finish_loop (awc,
               TALER_MHD_REPLY_JSON_PACK (
                 connection,
                 MHD_HTTP_OK,
                 GNUNET_JSON_pack_uint64 ("noreveal_index",
                                          noreveal_index),
                 GNUNET_JSON_pack_data_auto ("exchange_sig",
                                             &sig),
                 GNUNET_JSON_pack_data_auto ("exchange_pub",
                                             &pub)));
}


/**
 * Check if the request is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param[in,out] awc parsed request data
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
check_request_idempotent (
  struct AgeWithdrawContext *awc)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_AgeWithdraw commitment;

  qs = TEH_plugin->get_age_withdraw (
    TEH_plugin->cls,
    &awc->commitment.reserve_pub,
    &awc->commitment.h_commitment,
    &commitment);
  if (0 > qs)
  {
    /* FIXME: soft error not handled correctly! */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      finish_loop (awc,
                   TALER_MHD_reply_with_ec (
                     awc->rc->connection,
                     TALER_EC_GENERIC_DB_FETCH_FAILED,
                     "get_age_withdraw"));
    return true; /* Well, kind-of. */
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return false;

  /* Generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_AGE_WITHDRAW]++;
  awc->phase = AWC_PHASE_GENERATE_REPLY_SUCCESS;
  return true;
}


/**
 * Function implementing age withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct AgeWithdrawContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
age_withdraw_transaction (
  void *cls,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret)
{
  struct AgeWithdrawContext *awc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool found = false;
  bool balance_ok = false;
  bool age_ok = false;
  bool conflict = false;
  uint16_t allowed_maximum_age = 0;
  uint32_t reserve_birthday = 0;
  struct TALER_Amount reserve_balance;

  qs = TEH_plugin->do_age_withdraw (
    TEH_plugin->cls,
    &awc->commitment,
    awc->now,
    &found,
    &balance_ok,
    &reserve_balance,
    &age_ok,
    &allowed_maximum_age,
    &reserve_birthday,
    &conflict);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      finish_loop (awc,
                   TALER_MHD_reply_with_ec (
                     awc->rc->connection,
                     TALER_EC_GENERIC_DB_FETCH_FAILED,
                     "do_age_withdraw"));
    return qs;
  }
  if (! found)
  {
    finish_loop (awc,
                 TALER_MHD_reply_with_ec (
                   awc->rc->connection,
                   TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                   NULL));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! age_ok)
  {
    finish_loop (awc,
                 TALER_MHD_REPLY_JSON_PACK (
                   awc->rc->connection,
                   MHD_HTTP_CONFLICT,
                   TALER_MHD_PACK_EC (
                     TALER_EC_EXCHANGE_AGE_WITHDRAW_MAXIMUM_AGE_TOO_LARGE),
                   GNUNET_JSON_pack_uint64 (
                     "allowed_maximum_age",
                     allowed_maximum_age),
                   GNUNET_JSON_pack_uint64 (
                     "reserve_birthday",
                     reserve_birthday)));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    finish_loop (awc,
                 TEH_RESPONSE_reply_reserve_insufficient_balance (
                   awc->rc->connection,
                   TALER_EC_EXCHANGE_AGE_WITHDRAW_INSUFFICIENT_FUNDS,
                   &reserve_balance,
                   &awc->commitment.amount_with_fee,
                   &awc->commitment.reserve_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (conflict)
  {
    /* do_age_withdraw signaled a conflict, so there MUST be an entry
     * in the DB.  Put that into the response */
    if (check_request_idempotent (awc))
      return GNUNET_DB_STATUS_HARD_ERROR;
    GNUNET_break (0);
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    TEH_METRICS_num_success[TEH_MT_SUCCESS_AGE_WITHDRAW]++;
  return qs;
}


/**
 * @brief Persist the commitment.
 *
 * On conflict, the noreveal_index from the previous, existing
 * commitment is returned to the client, returning success.
 *
 * On error (like, insufficient funds), the client is notified.
 *
 * @param awc The context for the current age withdraw request
 */
static void
run_transaction (
  struct AgeWithdrawContext *awc)
{
  MHD_RESULT mhd_ret;

  GNUNET_assert (AWC_PHASE_RUN_TRANSACTION ==
                 awc->phase);
  if (GNUNET_OK !=
      TEH_DB_run_transaction (awc->rc->connection,
                              "run age withdraw",
                              TEH_MT_REQUEST_AGE_WITHDRAW,
                              &mhd_ret,
                              &age_withdraw_transaction,
                              awc))
  {
    if (AWC_PHASE_RUN_TRANSACTION == awc->phase)
      finish_loop (awc,
                   mhd_ret);
    return;
  }
  awc->phase++;
}


/**
 * @brief Sign the chosen blinded coins.
 *
 * @param awc The context for the current age withdraw request
 */
static void
prepare_transaction (
  struct AgeWithdrawContext *awc)
{
  uint8_t noreveal_index;

  awc->commitment.denom_sigs
    = GNUNET_new_array (
        awc->num_coins,
        struct TALER_BlindedDenominationSignature);
  awc->commitment.h_coin_evs
    = GNUNET_new_array (
        awc->num_coins,
        struct TALER_BlindedCoinHashP);
  /* Pick the challenge */
  noreveal_index =
    GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
                              TALER_CNC_KAPPA);
  awc->commitment.noreveal_index = noreveal_index;

  /* Choose and sign the coins */
  {
    struct TEH_CoinSignData csds[awc->num_coins];
    enum TALER_ErrorCode ec;

    /* Pick the chosen blinded coins */
    for (uint32_t i = 0; i<awc->num_coins; i++)
    {
      struct TEH_CoinSignData *csdsi = &csds[i];

      csdsi->bp = &awc->coin_evs[i][noreveal_index];
      csdsi->h_denom_pub = &awc->denom_hs[i];
    }

    ec = TEH_keys_denomination_batch_sign (
      awc->num_coins,
      csds,
      false,
      awc->commitment.denom_sigs);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      finish_loop (awc,
                   TALER_MHD_reply_with_ec (
                     awc->rc->connection,
                     ec,
                     NULL));
      return;
    }
  }

  /* Prepare the hashes of the coins for insertion */
  for (uint32_t i = 0; i<awc->num_coins; i++)
  {
    TALER_coin_ev_hash (&awc->coin_evs[i][noreveal_index],
                        &awc->denom_hs[i],
                        &awc->commitment.h_coin_evs[i]);
  }
  awc->phase++;
}


/**
 * Check the KYC result.
 *
 * @param awc storage for request processing
 */
static void
check_kyc_result (struct AgeWithdrawContext *awc)
{
  /* return final positive response */
  if (! awc->kyc.ok)
  {
    if (check_request_idempotent (awc))
      return;
    /* KYC required */
    finish_loop (awc,
                 TEH_RESPONSE_reply_kyc_required (
                   awc->rc->connection,
                   &awc->h_normalized_payto,
                   &awc->kyc,
                   false));
    return;
  }
  awc->phase++;
}


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls closure
 * @param lcr legitimization check result
 */
static void
withdraw_legi_cb (
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr)
{
  struct AgeWithdrawContext *awc = cls;

  awc->lch = NULL;
  GNUNET_assert (AWC_PHASE_SUSPENDED ==
                 awc->phase);
  MHD_resume_connection (awc->rc->connection);
  GNUNET_CONTAINER_DLL_remove (awc_head,
                               awc_tail,
                               awc);
  TALER_MHD_daemon_trigger ();
  if (NULL != lcr->response)
  {
    awc->response = lcr->response;
    awc->http_status = lcr->http_status;
    awc->phase = AWC_PHASE_GENERATE_REPLY_FAILURE;
    return;
  }
  awc->kyc = lcr->kyc;
  awc->phase = AWC_PHASE_CHECK_KYC_RESULT;
}


/**
 * Function called to iterate over KYC-relevant transaction amounts for a
 * particular time range. Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls closure, identifies the event type and account to iterate
 *        over events for
 * @param limit maximum time-range for which events should be fetched
 *        (timestamp in the past)
 * @param cb function to call on each event found, events must be returned
 *        in reverse chronological order
 * @param cb_cls closure for @a cb, of type struct AgeWithdrawContext
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
withdraw_amount_cb (
  void *cls,
  struct GNUNET_TIME_Absolute limit,
  TALER_EXCHANGEDB_KycAmountCallback cb,
  void *cb_cls)
{
  struct AgeWithdrawContext *awc = cls;
  enum GNUNET_GenericReturnValue ret;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check during age-withdrawal\n",
              TALER_amount2s (&awc->commitment.amount_with_fee));
  ret = cb (cb_cls,
            &awc->commitment.amount_with_fee,
            awc->now.abs_time);
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  qs = TEH_plugin->select_withdraw_amounts_for_kyc_check (
    TEH_plugin->cls,
    &awc->h_normalized_payto,
    limit,
    cb,
    cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this age-withdrawal and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
  return qs;
}


/**
 * Do legitimization check.
 *
 * @param awc operation context
 */
static void
run_legi_check (struct AgeWithdrawContext *awc)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_FullPayto payto_uri;
  struct TALER_FullPaytoHashP h_full_payto;

  /* Check if the money came from a wire transfer */
  qs = TEH_plugin->reserves_get_origin (
    TEH_plugin->cls,
    &awc->commitment.reserve_pub,
    &h_full_payto,
    &payto_uri);
  if (qs < 0)
  {
    finish_loop (awc,
                 TALER_MHD_reply_with_error (
                   awc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_GENERIC_DB_FETCH_FAILED,
                   "reserves_get_origin"));
    return;
  }
  /* If _no_ results, reserve was created by merge,
     in which case no KYC check is required as the
     merge already did that. */
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    awc->phase = AWC_PHASE_PREPARE_TRANSACTION;
    return;
  }
  TALER_full_payto_normalize_and_hash (payto_uri,
                                       &awc->h_normalized_payto);
  awc->lch = TEH_legitimization_check (
    &awc->rc->async_scope_id,
    TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW,
    payto_uri,
    &awc->h_normalized_payto,
    NULL, /* no account pub: this is about the origin account */
    &withdraw_amount_cb,
    awc,
    &withdraw_legi_cb,
    awc);
  GNUNET_assert (NULL != awc->lch);
  GNUNET_free (payto_uri.full_payto);
  GNUNET_CONTAINER_DLL_insert (awc_head,
                               awc_tail,
                               awc);
  MHD_suspend_connection (awc->rc->connection);
  awc->phase = AWC_PHASE_SUSPENDED;
}


/**
 * Check that the client signature authorizing the
 * withdrawal is valid.
 *
 * @param[in,out] awc request context to check
 */
static void
check_reserve_signature (
  struct AgeWithdrawContext *awc)
{
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_age_withdraw_verify (
        &awc->commitment.h_commitment,
        &awc->commitment.amount_with_fee,
        &TEH_age_restriction_config.mask,
        awc->commitment.max_age,
        &awc->commitment.reserve_pub,
        &awc->commitment.reserve_sig))
  {
    GNUNET_break_op (0);
    finish_loop (awc,
                 TALER_MHD_reply_with_ec (
                   awc->rc->connection,
                   TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                   NULL));
    return;
  }
  awc->phase++;
}


/**
 * Check if the given denomination is still or already valid, has not been
 * revoked and supports age restriction.
 *
 * @param[in,out] awc context for the operation
 * @param ksh The handle to the current state of (denomination) keys in the exchange
 * @param denom_h Hash of the denomination key to check
 * @return NULL on failure (denomination invalid)
 */
static struct TEH_DenominationKey *
denomination_is_valid (
  struct AgeWithdrawContext *awc,
  struct TEH_KeyStateHandle *ksh,
  const struct TALER_DenominationHashP *denom_h)
{
  struct MHD_Connection *connection = awc->rc->connection;
  struct TEH_DenominationKey *dk;
  MHD_RESULT result;

  dk = TEH_keys_denomination_by_hash_from_state (
    ksh,
    denom_h,
    connection,
    &result);
  if (NULL == dk)
  {
    /* The denomination doesn't exist */
    /* Note: a HTTP-response has been queued and result has been set by
     * TEH_keys_denominations_by_hash_from_state */
    /* FIXME-Oec: lacks idempotency check... */
    finish_loop (awc,
                 result);
    return NULL;
  }

  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw.abs_time))
  {
    /* This denomination is past the expiration time for withdrawc */
    /* FIXME[oec]: add idempotency check */
    finish_loop (awc,
                 TEH_RESPONSE_reply_expired_denom_pub_hash (
                   connection,
                   denom_h,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
                   "age-withdraw_reveal"));
    return NULL;
  }

  if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
  {
    /* This denomination is not yet valid */
    finish_loop (awc,
                 TEH_RESPONSE_reply_expired_denom_pub_hash (
                   connection,
                   denom_h,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
                   "age-withdraw_reveal"));
    return NULL;
  }

  if (dk->recoup_possible)
  {
    /* This denomination has been revoked */
    finish_loop (awc,
                 TALER_MHD_reply_with_ec (
                   connection,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                   NULL));
    return NULL;
  }

  if (0 == dk->denom_pub.age_mask.bits)
  {
    /* This denomation does not support age restriction */
    char msg[256];

    GNUNET_snprintf (msg,
                     sizeof(msg),
                     "denomination %s does not support age restriction",
                     GNUNET_h2s (&denom_h->hash));

    finish_loop (awc,
                 TALER_MHD_reply_with_ec (
                   connection,
                   TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
                   msg));
    return NULL;
  }

  return dk;
}


/**
 * Check if the given array of hashes of denomination_keys a) belong
 * to valid denominations and b) those are marked as age restricted.
 * Also, calculate the total amount of the denominations including fees
 * for withdraw.
 *
 * @param awc context to check keys for
 */
static void
check_keys (
  struct AgeWithdrawContext *awc)
{
  struct MHD_Connection *connection
    = awc->rc->connection;
  unsigned int len
    = awc->num_coins;
  struct TALER_Amount total_amount;
  struct TALER_Amount total_fee;
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    finish_loop (awc,
                 TALER_MHD_reply_with_ec (
                   connection,
                   TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                   NULL));
    return;
  }

  awc->commitment.denom_serials
    = GNUNET_new_array (len,
                        uint64_t);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &total_amount));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &total_fee));
  for (unsigned int i = 0; i < len; i++)
  {
    struct TEH_DenominationKey *dk;

    dk = denomination_is_valid (awc,
                                ksh,
                                &awc->denom_hs[i]);
    if (NULL == dk)
      /* FIXME[oec]: add idempotency check */
      return;

    /* Ensure the ciphers from the planchets match the denominations' */
    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      if (dk->denom_pub.bsign_pub_key->cipher !=
          awc->coin_evs[i][k].blinded_message->cipher)
      {
        GNUNET_break_op (0);
        finish_loop (awc,
                     TALER_MHD_reply_with_ec (
                       connection,
                       TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                       NULL));
        return;
      }
    }

    /* Accumulate the values */
    if (0 > TALER_amount_add (&total_amount,
                              &total_amount,
                              &dk->meta.value))
    {
      GNUNET_break_op (0);
      finish_loop (awc,
                   TALER_MHD_reply_with_error (
                     connection,
                     MHD_HTTP_BAD_REQUEST,
                     TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                     "amount"));
      return;
    }

    /* Accumulate the withdraw fees */
    if (0 > TALER_amount_add (&total_fee,
                              &total_fee,
                              &dk->meta.fees.withdraw))
    {
      GNUNET_break_op (0);
      finish_loop (awc,
                   TALER_MHD_reply_with_error (
                     connection,
                     MHD_HTTP_BAD_REQUEST,
                     TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                     "fee"));
      return;
    }
    awc->commitment.denom_serials[i] = dk->meta.serial;
  }

  /* Save the total amount including fees */
  GNUNET_assert (0 <
                 TALER_amount_add (
                   &awc->commitment.amount_with_fee,
                   &total_amount,
                   &total_fee));
  awc->phase++;
}


/**
 * Age-withdraw-specific cleanup routine. Function called
 * upon completion of the request that should
 * clean up @a rh_ctx. Can be NULL.
 *
 * @param rc request context to clean up
 */
static void
clean_age_withdraw_rc (struct TEH_RequestContext *rc)
{
  struct AgeWithdrawContext *awc = rc->rh_ctx;

  for (unsigned int i = 0; i<awc->num_coins; i++)
  {
    for (unsigned int kappa = 0; kappa<TALER_CNC_KAPPA; kappa++)
    {
      TALER_blinded_planchet_free (&awc->coin_evs[i][kappa]);
    }
  }
  for (unsigned int i = 0; i<awc->num_coins; i++)
  {
    TALER_blinded_denom_sig_free (&awc->commitment.denom_sigs[i]);
  }
  GNUNET_free (awc->commitment.h_coin_evs);
  GNUNET_free (awc->commitment.denom_sigs);
  GNUNET_free (awc->denom_hs);
  GNUNET_free (awc->coin_evs);
  GNUNET_free (awc->commitment.denom_serials);
  GNUNET_free (awc);
}


MHD_RESULT
TEH_handler_age_withdraw (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  struct AgeWithdrawContext *awc = rc->rh_ctx;

  if (NULL == awc)
  {
    awc = GNUNET_new (struct AgeWithdrawContext);
    rc->rh_ctx = awc;
    rc->rh_cleaner = &clean_age_withdraw_rc;
    awc->rc = rc;
    awc->commitment.reserve_pub = *reserve_pub;
    awc->now = GNUNET_TIME_timestamp_get ();

    {
      const json_t *j_denom_hs;
      const json_t *j_blinded_coin_evs;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_array_const ("denom_hs",
                                      &j_denom_hs),
        GNUNET_JSON_spec_array_const ("blinded_coin_evs",
                                      &j_blinded_coin_evs),
        GNUNET_JSON_spec_uint16 ("max_age",
                                 &awc->commitment.max_age),
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &awc->commitment.reserve_sig),
        GNUNET_JSON_spec_end ()
      };
      enum GNUNET_GenericReturnValue res;

      res = TALER_MHD_parse_json_data (rc->connection,
                                       root,
                                       spec);
      if (GNUNET_OK != res)
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

      /* The age value MUST be on the beginning of an age group */
      if (awc->commitment.max_age !=
          TALER_get_lowest_age (&TEH_age_restriction_config.mask,
                                awc->commitment.max_age))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_ec (
          rc->connection,
          TALER_EC_GENERIC_PARAMETER_MALFORMED,
          "max_age must be the lower edge of an age group");
      }

      {
        size_t num_coins = json_array_size (j_denom_hs);
        const char *error = NULL;

        _Static_assert ((TALER_MAX_FRESH_COINS < INT_MAX / TALER_CNC_KAPPA),
                        "TALER_MAX_FRESH_COINS too large");
        if (0 == num_coins)
          error = "denoms_h must not be empty";
        else if (num_coins != json_array_size (j_blinded_coin_evs))
          error = "denoms_h and coins_evs must be arrays of the same size";
        else if (num_coins > TALER_MAX_FRESH_COINS)
          /**
           * The wallet had committed to more than the maximum coins allowed, the
           * reserve has been charged, but now the user can not withdraw any money
           * from it.  Note that the user can't get their money back in this case!
           */
          error =
            "maximum number of coins that can be withdrawn has been exceeded";

        if (NULL != error)
        {
          GNUNET_break_op (0);
          return TALER_MHD_reply_with_ec (
            rc->connection,
            TALER_EC_GENERIC_PARAMETER_MALFORMED,
            error);
        }
        awc->num_coins = (unsigned int) num_coins;
        awc->commitment.num_coins = (unsigned int) num_coins;
      }

      awc->denom_hs
        = GNUNET_new_array (awc->num_coins,
                            struct TALER_DenominationHashP);
      {
        size_t idx;
        json_t *value;

        json_array_foreach (j_denom_hs, idx, value) {
          struct GNUNET_JSON_Specification ispec[] = {
            GNUNET_JSON_spec_fixed_auto (NULL,
                                         &awc->denom_hs[idx]),
            GNUNET_JSON_spec_end ()
          };

          res = TALER_MHD_parse_json_data (rc->connection,
                                           value,
                                           ispec);
          if (GNUNET_OK != res)
            return (GNUNET_SYSERR == res)
            ? MHD_NO
            : MHD_YES;
        }
      }
      {
        typedef struct TALER_BlindedPlanchet
          _array_of_kappa_planchets[TALER_CNC_KAPPA];

        awc->coin_evs = GNUNET_new_array (awc->num_coins,
                                          _array_of_kappa_planchets);
      }
      {
        struct GNUNET_HashContext *hash_context;

        hash_context = GNUNET_CRYPTO_hash_context_start ();
        GNUNET_assert (NULL != hash_context);

        /* Parse blinded envelopes. */
        {
          json_t *j_kappa_coin_evs;
          size_t idx;

          json_array_foreach (j_blinded_coin_evs, idx, j_kappa_coin_evs) {
            if (! json_is_array (j_kappa_coin_evs))
            {
              char buf[256];

              GNUNET_snprintf (
                buf,
                sizeof(buf),
                "entry %u in array blinded_coin_evs must be an array",
                (unsigned int) (idx + 1));
              GNUNET_break_op (0);
              return TALER_MHD_reply_with_ec (
                rc->connection,
                TALER_EC_GENERIC_PARAMETER_MALFORMED,
                buf);
            }
            if (TALER_CNC_KAPPA != json_array_size (j_kappa_coin_evs))
            {
              char buf[256];

              GNUNET_snprintf (buf,
                               sizeof(buf),
                               "array no. %u in coin_evs must have length %u",
                               (unsigned int) (idx + 1),
                               (unsigned int) TALER_CNC_KAPPA);
              GNUNET_break_op (0);
              return TALER_MHD_reply_with_ec (
                rc->connection,
                TALER_EC_GENERIC_PARAMETER_MALFORMED,
                buf);
            }

            /* Now parse the individual kappa envelopes and calculate the hash of
             * the commitment along the way. */
            {
              size_t kappa;
              json_t *kvalue;

              json_array_foreach (j_kappa_coin_evs, kappa, kvalue) {
                struct GNUNET_JSON_Specification kspec[] = {
                  TALER_JSON_spec_blinded_planchet (NULL,
                                                    &awc->coin_evs[idx][kappa]),
                  GNUNET_JSON_spec_end ()
                };

                res = TALER_MHD_parse_json_data (rc->connection,
                                                 kvalue,
                                                 kspec);
                if (GNUNET_OK != res)
                  return (GNUNET_SYSERR == res)
                  ? MHD_NO
                  : MHD_YES;
                /* Continue to hash of the coin candidates */
                {
                  struct TALER_BlindedCoinHashP bch;

                  TALER_coin_ev_hash (&awc->coin_evs[idx][kappa],
                                      &awc->denom_hs[idx],
                                      &bch);
                  GNUNET_CRYPTO_hash_context_read (hash_context,
                                                   &bch,
                                                   sizeof(bch));
                }

                /* Check for duplicate planchets. Technically a bug on
                 * the client side that is harmless for us, but still
                 * not allowed per protocol */
                for (unsigned int i = 0; i < idx; i++)
                {
                  if (0 ==
                      TALER_blinded_planchet_cmp (
                        &awc->coin_evs[idx][kappa],
                        &awc->coin_evs[i][kappa]))
                  {
                    GNUNET_break_op (0);
                    return TALER_MHD_reply_with_ec (
                      rc->connection,
                      TALER_EC_GENERIC_PARAMETER_MALFORMED,
                      "duplicate planchet");
                  }
                } /* end duplicate check */
              } /* json_array_foreach over j_kappa_coin_evs */
            } /* scope of kappa/kvalue */
          } /* json_array_foreach over j_blinded_coin_evs */
        } /* scope of j_kappa_coin_evs, idx */

        /* Finally, calculate the h_commitment from all blinded envelopes */
        GNUNET_CRYPTO_hash_context_finish (hash_context,
                                           &awc->commitment.h_commitment.hash);

      } /* scope of hash_context */
    } /* scope of j_denom_hs, j_blinded_coin_evs */

    awc->phase = AWC_PHASE_CHECK_KEYS;
  } /* end of if NULL == awc */

  while (true)
  {
    switch (awc->phase)
    {
    case AWC_PHASE_CHECK_KEYS:
      check_keys (awc);
      break;
    case AWC_PHASE_CHECK_RESERVE_SIGNATURE:
      check_reserve_signature (awc);
      break;
    case AWC_PHASE_RUN_LEGI_CHECK:
      run_legi_check (awc);
      break;
    case AWC_PHASE_SUSPENDED:
      return MHD_YES;
    case AWC_PHASE_CHECK_KYC_RESULT:
      check_kyc_result (awc);
      break;
    case AWC_PHASE_PREPARE_TRANSACTION:
      prepare_transaction (awc);
      break;
    case AWC_PHASE_RUN_TRANSACTION:
      run_transaction (awc);
      break;
    case AWC_PHASE_GENERATE_REPLY_SUCCESS:
      reply_age_withdraw_success (awc);
      break;
    case AWC_PHASE_GENERATE_REPLY_FAILURE:
      return MHD_queue_response (rc->connection,
                                 awc->http_status,
                                 awc->response);
    case AWC_PHASE_RETURN_YES:
      return MHD_YES;
    case AWC_PHASE_RETURN_NO:
      return MHD_NO;
    }
  }
}


/* end of taler-exchange-httpd_age-withdraw.c */
