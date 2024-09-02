/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_batch-withdraw.c
 * @brief Handle /reserves/$RESERVE_PUB/batch-withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler-exchange-httpd.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_batch-withdraw.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler_util.h"


/**
 * Information per planchet in the batch.
 */
struct PlanchetContext
{

  /**
   * Value of the coin being exchanged (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Blinded planchet.
   */
  struct TALER_BlindedPlanchet blinded_planchet;

  /**
   * Set to the resulting signed coin data to be returned to the client.
   */
  struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

};

/**
 * Context for #batch_withdraw_transaction.
 */
struct BatchWithdrawContext
{

  /**
   * Kept in a DLL.
   */
  struct BatchWithdrawContext *prev;

  /**
   * Kept in a DLL.
   */
  struct BatchWithdrawContext *next;

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
   * KYC status of the reserve used for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash of payto:// URI of the bank account that
   * established the reserve, set during the @e kyc
   * check (if any).
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Array of @e planchets_length planchets we are processing.
   */
  struct PlanchetContext *planchets;

  /**
   * Current time for the DB transaction.
   */
  struct GNUNET_TIME_Timestamp now;

  /**
   * Total amount from all coins with fees.
   */
  struct TALER_Amount batch_total;

  /**
   * Length of the @e planchets array.
   */
  unsigned int planchets_length;

  /**
   * HTTP status to return with @e response, or 0.
   */
  unsigned int http_status;

  /**
   * Processing phase we are in.
   */
  enum
  {
    BWC_PHASE_CHECK_KEYS,
    BWC_PHASE_RUN_LEGI_CHECK,
    BWC_PHASE_SUSPENDED,
    BWC_PHASE_CHECK_KYC_RESULT,
    BWC_PHASE_PREPARE_TRANSACTION,
    BWC_PHASE_RUN_TRANSACTION,
    BWC_PHASE_GENERATE_REPLY_SUCCESS,
    BWC_PHASE_GENERATE_REPLY_FAILURE,
    BWC_PHASE_RETURN_YES,
    BWC_PHASE_RETURN_NO
  } phase;

};


/**
 * Kept in a DLL.
 */
static struct BatchWithdrawContext *bwc_head;

/**
 * Kept in a DLL.
 */
static struct BatchWithdrawContext *bwc_tail;


void
TEH_batch_withdraw_cleanup ()
{
  struct BatchWithdrawContext *bwc;

  while (NULL != (bwc = bwc_head))
  {
    GNUNET_CONTAINER_DLL_remove (bwc_head,
                                 bwc_tail,
                                 bwc);
    MHD_resume_connection (bwc->rc->connection);
  }
}


/**
 * Terminate the main loop by returning the final
 * result.
 *
 * @param[in,out] bwc context to update phase for
 * @param mres MHD status to return
 */
static void
finish_loop (struct BatchWithdrawContext *bwc,
             MHD_RESULT mres)
{
  bwc->phase = (MHD_YES == mres)
    ? BWC_PHASE_RETURN_YES
    : BWC_PHASE_RETURN_NO;
}


/**
 * Generates our final (successful) response.
 *
 * @param bwc operation context
 */
static void
generate_reply_success (struct BatchWithdrawContext *bwc)
{
  const struct TEH_RequestContext *rc = bwc->rc;
  json_t *sigs;

  sigs = json_array ();
  GNUNET_assert (NULL != sigs);
  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];

    GNUNET_assert (
      0 ==
      json_array_append_new (
        sigs,
        GNUNET_JSON_PACK (
          TALER_JSON_pack_blinded_denom_sig (
            "ev_sig",
            &pc->collectable.sig))));
  }
  TEH_METRICS_batch_withdraw_num_coins += bwc->planchets_length;
  finish_loop (bwc,
               TALER_MHD_REPLY_JSON_PACK (
                 rc->connection,
                 MHD_HTTP_OK,
                 GNUNET_JSON_pack_array_steal ("ev_sigs",
                                               sigs)));
}


/**
 * Check if the @a bwc is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param bwc parsed request data
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
check_request_idempotent (
  struct BatchWithdrawContext *bwc)
{
  const struct TEH_RequestContext *rc = bwc->rc;

  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

    qs = TEH_plugin->get_withdraw_info (
      TEH_plugin->cls,
      &pc->collectable.h_coin_envelope,
      &collectable);
    if (0 > qs)
    {
      /* FIXME: soft error not handled correctly! */
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     rc->connection,
                     MHD_HTTP_INTERNAL_SERVER_ERROR,
                     TALER_EC_GENERIC_DB_FETCH_FAILED,
                     "get_withdraw_info"));
      return true;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      return false;
    pc->collectable = collectable;
  }
  /* generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_BATCH_WITHDRAW]++;
  bwc->phase = BWC_PHASE_GENERATE_REPLY_SUCCESS;
  return true;
}


/**
 * Function implementing withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * Note that "bwc->collectable.sig" is set before entering this function as we
 * signed before entering the transaction.
 *
 * @param cls a `struct BatchWithdrawContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
batch_withdraw_transaction (
  void *cls,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret)
{
  struct BatchWithdrawContext *bwc = cls;
  uint64_t ruuid;
  enum GNUNET_DB_QueryStatus qs;
  bool found = false;
  bool balance_ok = false;
  bool age_ok = false;
  uint16_t allowed_maximum_age = 0;
  struct TALER_Amount reserve_balance;

  qs = TEH_plugin->do_batch_withdraw (
    TEH_plugin->cls,
    bwc->now,
    &bwc->reserve_pub,
    &bwc->batch_total,
    TEH_age_restriction_enabled,
    &found,
    &balance_ok,
    &reserve_balance,
    &age_ok,
    &allowed_maximum_age,
    &ruuid);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     connection,
                     MHD_HTTP_INTERNAL_SERVER_ERROR,
                     TALER_EC_GENERIC_DB_FETCH_FAILED,
                     "update_reserve_batch_withdraw"));
      return qs;
    }
    return qs;
  }
  if (! found)
  {
    finish_loop (bwc,
                 TALER_MHD_reply_with_error (
                   connection,
                   MHD_HTTP_NOT_FOUND,
                   TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                   NULL));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (! age_ok)
  {
    /* We respond with the lowest age in the corresponding age group
     * of the required age */
    uint16_t lowest_age = TALER_get_lowest_age (
      &TEH_age_restriction_config.mask,
      allowed_maximum_age);

    finish_loop (bwc,
                 TEH_RESPONSE_reply_reserve_age_restriction_required (
                   connection,
                   lowest_age));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (! balance_ok)
  {
    if (check_request_idempotent (bwc))
      return GNUNET_DB_STATUS_HARD_ERROR;
    finish_loop (bwc,
                 TEH_RESPONSE_reply_reserve_insufficient_balance (
                   connection,
                   TALER_EC_EXCHANGE_WITHDRAW_INSUFFICIENT_FUNDS,
                   &reserve_balance,
                   &bwc->batch_total,
                   &bwc->reserve_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Add information about each planchet in the batch */
  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];
    const struct TALER_BlindedPlanchet *bp = &pc->blinded_planchet;
    const union GNUNET_CRYPTO_BlindSessionNonce *nonce = NULL;
    bool denom_unknown = true;
    bool conflict = true;
    bool nonce_reuse = true;

    switch (bp->blinded_message->cipher)
    {
    case GNUNET_CRYPTO_BSA_INVALID:
      break;
    case GNUNET_CRYPTO_BSA_RSA:
      break;
    case GNUNET_CRYPTO_BSA_CS:
      nonce = (const union GNUNET_CRYPTO_BlindSessionNonce *)
              &bp->blinded_message->details.cs_blinded_message.nonce;
      break;
    }
    qs = TEH_plugin->do_batch_withdraw_insert (
      TEH_plugin->cls,
      nonce,
      &pc->collectable,
      bwc->now,
      ruuid,
      &denom_unknown,
      &conflict,
      &nonce_reuse);
    if (0 > qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        finish_loop (bwc,
                     TALER_MHD_reply_with_error (
                       connection,
                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                       "do_batch_withdraw_insert"));
      return qs;
    }
    if (denom_unknown)
    {
      GNUNET_break (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     connection,
                     MHD_HTTP_INTERNAL_SERVER_ERROR,
                     TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                     NULL));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs) ||
         (conflict) )
    {
      if (check_request_idempotent (bwc))
        return GNUNET_DB_STATUS_HARD_ERROR;
      /* We do not support *some* of the coins of the request being
           idempotent while others being fresh. */
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Idempotent coin in batch, not allowed. Aborting.\n");
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     connection,
                     MHD_HTTP_CONFLICT,
                     TALER_EC_EXCHANGE_WITHDRAW_BATCH_IDEMPOTENT_PLANCHET,
                     NULL));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (nonce_reuse)
    {
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     connection,
                     MHD_HTTP_BAD_REQUEST,
                     TALER_EC_EXCHANGE_WITHDRAW_NONCE_REUSE,
                     NULL));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  TEH_METRICS_num_success[TEH_MT_SUCCESS_BATCH_WITHDRAW]++;
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * The request was prepared successfully. Run
 * the main DB transaction.
 *
 * @param bwc storage for request processing
 */
static void
run_transaction (struct BatchWithdrawContext *bwc)
{
  MHD_RESULT mhd_ret;

  GNUNET_assert (BWC_PHASE_RUN_TRANSACTION ==
                 bwc->phase);
  if (GNUNET_OK !=
      TEH_DB_run_transaction (bwc->rc->connection,
                              "run batch withdraw",
                              TEH_MT_REQUEST_WITHDRAW,
                              &mhd_ret,
                              &batch_withdraw_transaction,
                              bwc))
  {
    if (BWC_PHASE_RUN_TRANSACTION == bwc->phase)
      finish_loop (bwc,
                   mhd_ret);
    return;
  }
  bwc->phase++;
}


/**
 * The request was parsed successfully. Prepare
 * our side for the main DB transaction.
 *
 * @param bwc storage for request processing
 */
static void
prepare_transaction (struct BatchWithdrawContext *bwc)
{
  const struct TEH_RequestContext *rc = bwc->rc;
  struct TALER_BlindedDenominationSignature bss[bwc->planchets_length];
  struct TEH_CoinSignData csds[bwc->planchets_length];

  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];
    struct TEH_CoinSignData *csdsi = &csds[i];

    csdsi->h_denom_pub = &pc->collectable.denom_pub_hash;
    csdsi->bp = &pc->blinded_planchet;
  }
  {
    enum TALER_ErrorCode ec;

    ec = TEH_keys_denomination_batch_sign (
      bwc->planchets_length,
      csds,
      false,
      bss);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_ec (
                     rc->connection,
                     ec,
                     NULL));
      return;
    }
  }
  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];

    pc->collectable.sig = bss[i];
  }
  bwc->phase++;
}


/**
 * Check the KYC result.
 *
 * @param bwc storage for request processing
 */
static void
check_kyc_result (struct BatchWithdrawContext *bwc)
{
  /* return final positive response */
  if (! bwc->kyc.ok)
  {
    if (check_request_idempotent (bwc))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Request is idempotent!\n");
      return;
    }
    /* KYC required */
    finish_loop (bwc,
                 TEH_RESPONSE_reply_kyc_required (
                   bwc->rc->connection,
                   &bwc->h_payto,
                   &bwc->kyc,
                   false));
    return;
  }
  bwc->phase++;
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
  struct BatchWithdrawContext *bwc = cls;

  bwc->lch = NULL;
  GNUNET_assert (BWC_PHASE_SUSPENDED ==
                 bwc->phase);
  MHD_resume_connection (bwc->rc->connection);
  GNUNET_CONTAINER_DLL_remove (bwc_head,
                               bwc_tail,
                               bwc);
  TALER_MHD_daemon_trigger ();
  if (NULL != lcr->response)
  {
    bwc->response = lcr->response;
    bwc->http_status = lcr->http_status;
    bwc->phase = BWC_PHASE_GENERATE_REPLY_FAILURE;
    return;
  }
  bwc->kyc = lcr->kyc;
  bwc->phase = BWC_PHASE_CHECK_KYC_RESULT;
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
  struct BatchWithdrawContext *bwc = cls;
  enum GNUNET_GenericReturnValue ret;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check during age-withdrawal\n",
              TALER_amount2s (&bwc->batch_total));
  ret = cb (cb_cls,
            &bwc->batch_total,
            bwc->now.abs_time);
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  qs = TEH_plugin->select_withdraw_amounts_for_kyc_check (
    TEH_plugin->cls,
    &bwc->h_payto,
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
 * @param bwc operation context
 */
static void
run_legi_check (struct BatchWithdrawContext *bwc)
{
  enum GNUNET_DB_QueryStatus qs;
  char *payto_uri;

  /* Check if the money came from a wire transfer */
  qs = TEH_plugin->reserves_get_origin (
    TEH_plugin->cls,
    &bwc->reserve_pub,
    &bwc->h_payto,
    &payto_uri);
  if (qs < 0)
  {
    finish_loop (bwc,
                 TALER_MHD_reply_with_error (
                   bwc->rc->connection,
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
    bwc->phase = BWC_PHASE_PREPARE_TRANSACTION;
    return;
  }

  bwc->lch = TEH_legitimization_check (
    &bwc->rc->async_scope_id,
    TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW,
    payto_uri,
    &bwc->h_payto,
    NULL, /* no account pub: this is about the origin account */
    &withdraw_amount_cb,
    bwc,
    &withdraw_legi_cb,
    bwc);
  GNUNET_assert (NULL != bwc->lch);
  GNUNET_free (payto_uri);
  GNUNET_CONTAINER_DLL_insert (bwc_head,
                               bwc_tail,
                               bwc);
  MHD_suspend_connection (bwc->rc->connection);
  bwc->phase = BWC_PHASE_SUSPENDED;
}


/**
 * Check if the keys in the request are valid for
 * withdrawing.
 *
 * @param[in,out] bwc storage for request processing
 */
static void
check_keys (struct BatchWithdrawContext *bwc)
{
  const struct TEH_RequestContext *rc = bwc->rc;
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    if (check_request_idempotent (bwc))
      return;
    GNUNET_break (0);
    finish_loop (bwc,
                 TALER_MHD_reply_with_error (
                   rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                   NULL));
    return;
  }
  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];
    struct TEH_DenominationKey *dk;


    dk = TEH_keys_denomination_by_hash_from_state (
      ksh,
      &pc->collectable.denom_pub_hash,
      NULL,
      NULL);
    if (NULL == dk)
    {
      if (check_request_idempotent (bwc))
        return;
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TEH_RESPONSE_reply_unknown_denom_pub_hash (
                     rc->connection,
                     &pc->collectable.denom_pub_hash));
      return;
    }
    if (GNUNET_TIME_absolute_is_past (
          dk->meta.expire_withdraw.abs_time))
    {
      /* This denomination is past the expiration time for withdraws */
      if (check_request_idempotent (bwc))
        return;
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TEH_RESPONSE_reply_expired_denom_pub_hash (
                     rc->connection,
                     &pc->collectable.denom_pub_hash,
                     TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
                     "WITHDRAW"));
      return;
    }
    if (GNUNET_TIME_absolute_is_future (
          dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid, no need to check
         for idempotency! */
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TEH_RESPONSE_reply_expired_denom_pub_hash (
                     rc->connection,
                     &pc->collectable.denom_pub_hash,
                     TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
                     "WITHDRAW"));
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      if (check_request_idempotent (bwc))
        return;
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TEH_RESPONSE_reply_expired_denom_pub_hash (
                     rc->connection,
                     &pc->collectable.denom_pub_hash,
                     TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                     "WITHDRAW"));
      return;
    }
    if (dk->denom_pub.bsign_pub_key->cipher !=
        pc->blinded_planchet.blinded_message->cipher)
    {
      /* denomination cipher and blinded planchet cipher not the same */
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     rc->connection,
                     MHD_HTTP_BAD_REQUEST,
                     TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                     NULL));
    }
    if (0 >
        TALER_amount_add (&pc->collectable.amount_with_fee,
                          &dk->meta.value,
                          &dk->meta.fees.withdraw))
    {
      GNUNET_break (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (rc->connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                                               NULL));
      return;
    }
    if (0 >
        TALER_amount_add (&bwc->batch_total,
                          &bwc->batch_total,
                          &pc->collectable.amount_with_fee))
    {
      GNUNET_break (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     rc->connection,
                     MHD_HTTP_INTERNAL_SERVER_ERROR,
                     TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                     NULL));
      return;
    }

    TALER_coin_ev_hash (&pc->blinded_planchet,
                        &pc->collectable.denom_pub_hash,
                        &pc->collectable.h_coin_envelope);

    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_withdraw_verify (
          &pc->collectable.denom_pub_hash,
          &pc->collectable.amount_with_fee,
          &pc->collectable.h_coin_envelope,
          &pc->collectable.reserve_pub,
          &pc->collectable.reserve_sig))
    {
      GNUNET_break_op (0);
      finish_loop (bwc,
                   TALER_MHD_reply_with_error (
                     rc->connection,
                     MHD_HTTP_FORBIDDEN,
                     TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                     NULL));
      return;
    }
  }
  bwc->phase++;
  /* everything parsed */
}


/**
 * Batch-withdraw-specific cleanup routine. Function called
 * upon completion of the request that should
 * clean up @a rh_ctx. Can be NULL.
 *
 * @param rc request context to clean up
 */
static void
clean_batch_withdraw_rc (struct TEH_RequestContext *rc)
{
  struct BatchWithdrawContext *bwc = rc->rh_ctx;

  if (NULL != bwc->lch)
  {
    TEH_legitimization_check_cancel (bwc->lch);
    bwc->lch = NULL;
  }
  for (unsigned int i = 0; i<bwc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &bwc->planchets[i];

    TALER_blinded_planchet_free (&pc->blinded_planchet);
    TALER_blinded_denom_sig_free (&pc->collectable.sig);
  }
  GNUNET_free (bwc->planchets);
  if (NULL != bwc->response)
  {
    MHD_destroy_response (bwc->response);
    bwc->response = NULL;
  }
  GNUNET_free (bwc);
}


MHD_RESULT
TEH_handler_batch_withdraw (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  struct BatchWithdrawContext *bwc = rc->rh_ctx;

  if (NULL == bwc)
  {
    const json_t *planchets;

    bwc = GNUNET_new (struct BatchWithdrawContext);
    rc->rh_ctx = bwc;
    rc->rh_cleaner = &clean_batch_withdraw_rc;
    bwc->rc = rc;
    bwc->reserve_pub = *reserve_pub;
    bwc->now = GNUNET_TIME_timestamp_get ();
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TEH_currency,
                                          &bwc->batch_total));

    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_array_const ("planchets",
                                      &planchets),
        GNUNET_JSON_spec_end ()
      };

      {
        enum GNUNET_GenericReturnValue res;

        res = TALER_MHD_parse_json_data (rc->connection,
                                         root,
                                         spec);
        if (GNUNET_OK != res)
          return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }
    }

    bwc->planchets_length = json_array_size (planchets);
    if (0 == bwc->planchets_length)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "planchets");
    }
    if (bwc->planchets_length > TALER_MAX_FRESH_COINS)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "too many planchets");
    }

    bwc->planchets
      = GNUNET_new_array (bwc->planchets_length,
                          struct PlanchetContext);

    for (unsigned int i = 0; i<bwc->planchets_length; i++)
    {
      struct PlanchetContext *pc = &bwc->planchets[i];
      struct GNUNET_JSON_Specification ispec[] = {
        GNUNET_JSON_spec_fixed_auto (
          "reserve_sig",
          &pc->collectable.reserve_sig),
        GNUNET_JSON_spec_fixed_auto (
          "denom_pub_hash",
          &pc->collectable.denom_pub_hash),
        TALER_JSON_spec_blinded_planchet (
          "coin_ev",
          &pc->blinded_planchet),
        GNUNET_JSON_spec_end ()
      };

      {
        enum GNUNET_GenericReturnValue res;

        res = TALER_MHD_parse_json_data (
          rc->connection,
          json_array_get (planchets,
                          i),
          ispec);
        if (GNUNET_OK != res)
          return (GNUNET_SYSERR == res)
            ? MHD_NO
            : MHD_YES;
      }
      pc->collectable.reserve_pub = bwc->reserve_pub;
      for (unsigned int k = 0; k<i; k++)
      {
        const struct PlanchetContext *kpc = &bwc->planchets[k];

        if (0 ==
            TALER_blinded_planchet_cmp (
              &kpc->blinded_planchet,
              &pc->blinded_planchet))
        {
          GNUNET_break_op (0);
          return TALER_MHD_reply_with_error (
            rc->connection,
            MHD_HTTP_BAD_REQUEST,
            TALER_EC_GENERIC_PARAMETER_MALFORMED,
            "duplicate planchet");
        }
      }
    }
    bwc->phase = BWC_PHASE_CHECK_KEYS;
  }

  while (true)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Batch withdraw processing in phase %d\n",
                bwc->phase);
    switch (bwc->phase)
    {
    case BWC_PHASE_CHECK_KEYS:
      check_keys (bwc);
      break;
    case BWC_PHASE_RUN_LEGI_CHECK:
      run_legi_check (bwc);
      break;
    case BWC_PHASE_SUSPENDED:
      return MHD_YES;
    case BWC_PHASE_CHECK_KYC_RESULT:
      check_kyc_result (bwc);
      break;
    case BWC_PHASE_PREPARE_TRANSACTION:
      prepare_transaction (bwc);
      break;
    case BWC_PHASE_RUN_TRANSACTION:
      run_transaction (bwc);
      break;
    case BWC_PHASE_GENERATE_REPLY_SUCCESS:
      generate_reply_success (bwc);
      break;
    case BWC_PHASE_GENERATE_REPLY_FAILURE:
      return MHD_queue_response (rc->connection,
                                 bwc->http_status,
                                 bwc->response);
    case BWC_PHASE_RETURN_YES:
      return MHD_YES;
    case BWC_PHASE_RETURN_NO:
      return MHD_NO;
    }
  }
}


/* end of taler-exchange-httpd_batch-withdraw.c */
