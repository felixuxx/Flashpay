/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_batch-deposit.c
 * @brief Handle /batch-deposit requests; parses the POST and JSON and
 *        verifies the coin signatures before handing things off
 *        to the database.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_extensions_policy.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_batch-deposit.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for #batch_deposit_transaction.
 */
struct BatchDepositContext
{

  /**
   * Kept in a DLL.
   */
  struct BatchDepositContext *next;

  /**
   * Kept in a DLL.
   */
  struct BatchDepositContext *prev;

  /**
   * The request we are working on.
   */
  struct TEH_RequestContext *rc;

  /**
   * Handle for the legitimization check.
   */
  struct TEH_LegitimizationCheckHandle *lch;

  /**
   * Array with the individual coin deposit fees.
   */
  struct TALER_Amount *deposit_fees;

  /**
   * Information about deposited coins.
   */
  struct TALER_EXCHANGEDB_CoinDepositInformation *cdis;

  /**
   * Additional details for policy extension relevant for this
   * deposit operation, possibly NULL!
   */
  json_t *policy_json;


  /**
   * Response to return, if set.
   */
  struct MHD_Response *response;

  /**
   * KYC status of the reserve used for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash over @e policy_details, might be all zero
   */
  struct TALER_ExtensionPolicyHashP h_policy;

  /**
   * Hash over the merchant's payto://-URI with the wire salt.
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * When @e policy_details are persisted, this contains the id of the record
   * in the policy_details table.
   */
  uint64_t policy_details_serial_id;

  /**
   * Our timestamp (when we received the request).
   * Possibly updated by the transaction if the
   * request is idempotent (was repeated).
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Total amount that is accumulated with this deposit,
   * without fee.
   */
  struct TALER_Amount accumulated_total_without_fee;

  /**
   * Details about the batch deposit operation.
   */
  struct TALER_EXCHANGEDB_BatchDeposit bd;

  /**
   * If @e policy_json was present, the corresponding policy extension
   * calculates these details.  These will be persisted in the policy_details
   * table.
   */
  struct TALER_PolicyDetails policy_details;

  /**
   * HTTP status to return with @e response, or 0.
   */
  unsigned int http_status;

  /**
   * Our current state in the state machine.
   */
  enum
  {
    BDC_PHASE_INIT = 0,
    BDC_PHASE_PARSE = 1,
    BDC_PHASE_POLICY = 2,
    BDC_PHASE_KYC = 3,
    BDC_PHASE_TRANSACT = 4,
    BDC_PHASE_REPLY_SUCCESS = 5,
    BDC_PHASE_SUSPENDED,
    BDC_PHASE_CHECK_KYC_RESULT,
    BDC_PHASE_GENERATE_REPLY_FAILURE,
    BDC_PHASE_RETURN_YES,
    BDC_PHASE_RETURN_NO,
  } phase;

  /**
   * True, if no policy was present in the request. Then
   * @e policy_json is NULL and @e h_policy will be all zero.
   */
  bool has_no_policy;
};


/**
 * Head of list of suspended batch deposit operations.
 */
static struct BatchDepositContext *bdc_head;

/**
 * Tail of list of suspended batch deposit operations.
 */
static struct BatchDepositContext *bdc_tail;


void
TEH_batch_deposit_cleanup ()
{
  struct BatchDepositContext *bdc;

  while (NULL != (bdc = bdc_head))
  {
    GNUNET_assert (BDC_PHASE_SUSPENDED == bdc->phase);
    bdc->phase = BDC_PHASE_RETURN_NO;
    MHD_resume_connection (bdc->rc->connection);
    GNUNET_CONTAINER_DLL_remove (bdc_head,
                                 bdc_tail,
                                 bdc);
  }
}


/**
 * Terminate the main loop by returning the final
 * result.
 *
 * @param[in,out] bdc context to update phase for
 * @param mres MHD status to return
 */
static void
finish_loop (struct BatchDepositContext *bdc,
             MHD_RESULT mres)
{
  bdc->phase = (MHD_YES == mres)
    ? BDC_PHASE_RETURN_YES
    : BDC_PHASE_RETURN_NO;
}


/**
 * Send confirmation of batch deposit success to client.  This function will
 * create a signed message affirming the given information and return it to
 * the client.  By this, the exchange affirms that the coins had sufficient
 * (residual) value for the specified transaction and that it will execute the
 * requested batch deposit operation with the given wiring details.
 *
 * @param[in,out] bdc information about the batch deposit
 */
static void
bdc_phase_reply_success (
  struct BatchDepositContext *bdc)
{
  const struct TALER_EXCHANGEDB_BatchDeposit *bd = &bdc->bd;
  const struct TALER_CoinSpendSignatureP *csigs[GNUNET_NZL (bd->num_cdis)];
  enum TALER_ErrorCode ec;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  for (unsigned int i = 0; i<bdc->bd.num_cdis; i++)
    csigs[i] = &bd->cdis[i].csig;
  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_deposit_confirmation_sign (
         &TEH_keys_exchange_sign_,
         &bd->h_contract_terms,
         &bdc->h_wire,
         bdc->has_no_policy ? NULL : &bdc->h_policy,
         bdc->exchange_timestamp,
         bd->wire_deadline,
         bd->refund_deadline,
         &bdc->accumulated_total_without_fee,
         bd->num_cdis,
         csigs,
         &bdc->bd.merchant_pub,
         &pub,
         &sig)))
  {
    GNUNET_break (0);
    finish_loop (bdc,
                 TALER_MHD_reply_with_ec (bdc->rc->connection,
                                          ec,
                                          NULL));
    return;
  }
  finish_loop (bdc,
               TALER_MHD_REPLY_JSON_PACK (
                 bdc->rc->connection,
                 MHD_HTTP_OK,
                 GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                             bdc->exchange_timestamp),
                 GNUNET_JSON_pack_data_auto ("exchange_pub",
                                             &pub),
                 GNUNET_JSON_pack_data_auto ("exchange_sig",
                                             &sig)));
}


/**
 * Execute database transaction for /batch-deposit.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls a `struct BatchDepositContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
batch_deposit_transaction (void *cls,
                           struct MHD_Connection *connection,
                           MHD_RESULT *mhd_ret)
{
  struct BatchDepositContext *bdc = cls;
  const struct TALER_EXCHANGEDB_BatchDeposit *bd = &bdc->bd;
  enum GNUNET_DB_QueryStatus qs = GNUNET_DB_STATUS_HARD_ERROR;
  uint32_t bad_balance_coin_index = UINT32_MAX;
  bool balance_ok;
  bool in_conflict;

  /* If the deposit has a policy associated to it, persist it.  This will
   * insert or update the record. */
  if (! bdc->has_no_policy)
  {
    qs = TEH_plugin->persist_policy_details (
      TEH_plugin->cls,
      &bdc->policy_details,
      &bdc->bd.policy_details_serial_id,
      &bdc->accumulated_total_without_fee,
      &bdc->policy_details.fulfillment_state);
    if (qs < 0)
      return qs;

    bdc->bd.policy_blocked =
      bdc->policy_details.fulfillment_state != TALER_PolicyFulfillmentSuccess;
  }

  /* FIXME: replace by batch insert! */
  for (unsigned int i = 0; i<bdc->bd.num_cdis; i++)
  {
    const struct TALER_EXCHANGEDB_CoinDepositInformation *cdi
      = &bdc->cdis[i];
    uint64_t known_coin_id;

    qs = TEH_make_coin_known (&cdi->coin,
                              connection,
                              &known_coin_id,
                              mhd_ret);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "make coin known (%s) returned %d\n",
                TALER_B2S (&cdi->coin.coin_pub),
                qs);
    if (qs < 0)
      return qs;
  }

  qs = TEH_plugin->do_deposit (
    TEH_plugin->cls,
    bd,
    &bdc->exchange_timestamp,
    &balance_ok,
    &bad_balance_coin_index,
    &in_conflict);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    TALER_LOG_WARNING (
      "Failed to store /batch-deposit information in database\n");
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_STORE_FAILED,
      "batch-deposit");
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "do_deposit returned: %d / %s[%u] / %s\n",
              qs,
              balance_ok ? "balance ok" : "balance insufficient",
              (unsigned int) bad_balance_coin_index,
              in_conflict ? "in conflict" : "no conflict");
  if (in_conflict)
  {
    struct TALER_MerchantWireHashP h_wire;

    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        TEH_plugin->get_wire_hash_for_contract (
          TEH_plugin->cls,
          &bd->merchant_pub,
          &bd->h_contract_terms,
          &h_wire))
    {
      TALER_LOG_WARNING (
        "Failed to retrieve conflicting contract details from database\n");
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "batch-deposit");
      return qs;
    }

    *mhd_ret
      = TEH_RESPONSE_reply_coin_conflicting_contract (
          connection,
          TALER_EC_EXCHANGE_DEPOSIT_CONFLICTING_CONTRACT,
          &h_wire);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    GNUNET_assert (bad_balance_coin_index < bdc->bd.num_cdis);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "returning history of conflicting coin (%s)\n",
                TALER_B2S (&bdc->cdis[bad_balance_coin_index].coin.coin_pub));
    *mhd_ret
      = TEH_RESPONSE_reply_coin_insufficient_funds (
          connection,
          TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
          &bdc->cdis[bad_balance_coin_index].coin.denom_pub_hash,
          &bdc->cdis[bad_balance_coin_index].coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TEH_METRICS_num_success[TEH_MT_SUCCESS_DEPOSIT]++;
  return qs;
}


/**
 * Run database transaction.
 *
 * @param[in,out] bdc request context
 */
static void
bdc_phase_transact (struct BatchDepositContext *bdc)
{
  MHD_RESULT mhd_ret;

  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    finish_loop (bdc,
                 TALER_MHD_reply_with_error (
                   bdc->rc->connection,
                   MHD_HTTP_INTERNAL_SERVER_ERROR,
                   TALER_EC_GENERIC_DB_START_FAILED,
                   "preflight failure"));
    return;
  }

  if (GNUNET_OK !=
      TEH_DB_run_transaction (bdc->rc->connection,
                              "execute batch deposit",
                              TEH_MT_REQUEST_BATCH_DEPOSIT,
                              &mhd_ret,
                              &batch_deposit_transaction,
                              bdc))
  {
    finish_loop (bdc,
                 mhd_ret);
    return;
  }
  bdc->phase++;
}


/**
 * Check if the @a bdc is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param bdc parsed request data
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
check_request_idempotent (
  struct BatchDepositContext *bdc)
{
#if FIXME_PLACEHOLDER
  const struct TEH_RequestContext *rc = bdc->rc;

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
  bwc->phase = BDC_PHASE_GENERATE_REPLY_SUCCESS;
  return true;
#else
  GNUNET_break (0); // NOT IMPLEMENTED
  return false;
#endif
}


/**
 * Check the KYC result.
 *
 * @param bdc storage for request processing
 */
static void
bdc_phase_check_kyc_result (struct BatchDepositContext *bdc)
{
  /* return final positive response */
  if (! bdc->kyc.ok)
  {
    if (check_request_idempotent (bdc))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Request is idempotent!\n");
      return;
    }
    /* KYC required */
    finish_loop (bdc,
                 TEH_RESPONSE_reply_kyc_required (
                   bdc->rc->connection,
                   &bdc->bd.wire_target_h_payto,
                   &bdc->kyc));
    return;
  }
  bdc->phase = BDC_PHASE_TRANSACT;
}


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls closure
 * @param lcr legitimization check result
 */
static void
deposit_legi_cb (
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr)
{
  struct BatchDepositContext *bdc = cls;

  bdc->lch = NULL;
  GNUNET_assert (BDC_PHASE_SUSPENDED ==
                 bdc->phase);
  MHD_resume_connection (bdc->rc->connection);
  GNUNET_CONTAINER_DLL_remove (bdc_head,
                               bdc_tail,
                               bdc);
  TALER_MHD_daemon_trigger ();
  if (NULL != lcr->response)
  {
    bdc->response = lcr->response;
    bdc->http_status = lcr->http_status;
    bdc->phase = BDC_PHASE_GENERATE_REPLY_FAILURE;
    return;
  }
  bdc->kyc = lcr->kyc;
  bdc->phase = BDC_PHASE_CHECK_KYC_RESULT;
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
deposit_amount_cb (
  void *cls,
  struct GNUNET_TIME_Absolute limit,
  TALER_EXCHANGEDB_KycAmountCallback cb,
  void *cb_cls)
{
  struct BatchDepositContext *bdc = cls;
  enum GNUNET_GenericReturnValue ret;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check during deposit\n",
              TALER_amount2s (&bdc->accumulated_total_without_fee));
  ret = cb (cb_cls,
            &bdc->accumulated_total_without_fee,
            bdc->exchange_timestamp.abs_time);
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  qs = TEH_plugin->select_deposit_amounts_for_kyc_check (
    TEH_plugin->cls,
    &bdc->bd.wire_target_h_payto,
    limit,
    cb,
    cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this deposit and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
  return qs;
}


/**
 * Run KYC check.
 *
 * @param[in,out] bdc request context
 */
static void
bdc_phase_kyc (struct BatchDepositContext *bdc)
{
  if (GNUNET_YES != TEH_enable_kyc)
  {
    bdc->phase++;
    return;
  }
  /* FIXME: this fails to check that the
     merchant_pub used in this request
     matches the registered public key */
  bdc->lch = TEH_legitimization_check (
    &bdc->rc->async_scope_id,
    TALER_KYCLOGIC_KYC_TRIGGER_DEPOSIT,
    bdc->bd.receiver_wire_account,
    &bdc->bd.wire_target_h_payto,
    NULL,
    &deposit_amount_cb,
    bdc,
    &deposit_legi_cb,
    bdc);
  GNUNET_assert (NULL != bdc->lch);
  GNUNET_CONTAINER_DLL_insert (bdc_head,
                               bdc_tail,
                               bdc);
  MHD_suspend_connection (bdc->rc->connection);
  bdc->phase = BDC_PHASE_SUSPENDED;
}


/**
 * Handle policy.
 *
 * @param[in,out] bdc request context
 */
static void
bdc_phase_policy (struct BatchDepositContext *bdc)
{
  const char *error_hint = NULL;

  if (bdc->has_no_policy)
  {
    bdc->phase++;
    return;
  }
  if (GNUNET_OK !=
      TALER_extensions_create_policy_details (
        TEH_currency,
        bdc->policy_json,
        &bdc->policy_details,
        &error_hint))
  {
    GNUNET_break_op (0);
    finish_loop (bdc,
                 TALER_MHD_reply_with_error (
                   bdc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_EXCHANGE_DEPOSITS_POLICY_NOT_ACCEPTED,
                   error_hint));
    return;
  }

  TALER_deposit_policy_hash (bdc->policy_json,
                             &bdc->h_policy);
  bdc->phase++;
}


/**
 * Parse per-coin deposit information from @a jcoin
 * into @a deposit. Fill in generic information from
 * @a ctx.
 *
 * @param bdc information about the overall batch
 * @param jcoin coin data to parse
 * @param[out] cdi where to store the result
 * @param[out] deposit_fee where to write the deposit fee
 * @return #GNUNET_OK on success, #GNUNET_NO if an error was returned,
 *         #GNUNET_SYSERR on failure and no error could be returned
 */
static enum GNUNET_GenericReturnValue
parse_coin (const struct BatchDepositContext *bdc,
            json_t *jcoin,
            struct TALER_EXCHANGEDB_CoinDepositInformation *cdi,
            struct TALER_Amount *deposit_fee)
{
  const struct TALER_EXCHANGEDB_BatchDeposit *bd = &bdc->bd;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("contribution",
                            TEH_currency,
                            &cdi->amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &cdi->coin.denom_pub_hash),
    TALER_JSON_spec_denom_sig ("ub_sig",
                               &cdi->coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &cdi->coin.coin_pub),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &cdi->coin.h_age_commitment),
      &cdi->coin.no_age_commitment),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &cdi->csig),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_GenericReturnValue res;

  if (GNUNET_OK !=
      (res = TALER_MHD_parse_json_data (bdc->rc->connection,
                                        jcoin,
                                        spec)))
    return res;
  /* check denomination exists and is valid */
  {
    struct TEH_DenominationKey *dk;
    MHD_RESULT mret;

    dk = TEH_keys_denomination_by_hash (
      &cdi->coin.denom_pub_hash,
      bdc->rc->connection,
      &mret);
    if (NULL == dk)
    {
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES == mret)
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (0 > TALER_amount_cmp (&dk->meta.value,
                              &cdi->amount_with_fee))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (
                bdc->rc->connection,
                MHD_HTTP_BAD_REQUEST,
                TALER_EC_EXCHANGE_GENERIC_AMOUNT_EXCEEDS_DENOMINATION_VALUE,
                NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit.abs_time))
    {
      /* This denomination is past the expiration time for deposits */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                bdc->rc->connection,
                &cdi->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                bdc->rc->connection,
                &cdi->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                bdc->rc->connection,
                &cdi->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (dk->denom_pub.bsign_pub_key->cipher !=
        cdi->coin.denom_sig.unblinded_sig->cipher)
    {
      /* denomination cipher and denomination signature cipher not the same */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (
                bdc->rc->connection,
                MHD_HTTP_BAD_REQUEST,
                TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }

    *deposit_fee = dk->meta.fees.deposit;
    /* check coin signature */
    switch (dk->denom_pub.bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_RSA:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_RSA]++;
      break;
    case GNUNET_CRYPTO_BSA_CS:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_CS]++;
      break;
    default:
      break;
    }
    if (GNUNET_YES !=
        TALER_test_coin_valid (&cdi->coin,
                               &dk->denom_pub))
    {
      TALER_LOG_WARNING ("Invalid coin passed for /batch-deposit\n");
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (
                bdc->rc->connection,
                MHD_HTTP_FORBIDDEN,
                TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
                NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
  }
  if (0 < TALER_amount_cmp (deposit_fee,
                            &cdi->amount_with_fee))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (
              bdc->rc->connection,
              MHD_HTTP_BAD_REQUEST,
              TALER_EC_EXCHANGE_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE,
              NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
  }

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (
        &cdi->amount_with_fee,
        deposit_fee,
        &bdc->h_wire,
        &bd->h_contract_terms,
        &bd->wallet_data_hash,
        cdi->coin.no_age_commitment
        ? NULL
        : &cdi->coin.h_age_commitment,
        NULL != bdc->policy_json ? &bdc->h_policy : NULL,
        &cdi->coin.denom_pub_hash,
        bd->wallet_timestamp,
        &bd->merchant_pub,
        bd->refund_deadline,
        &cdi->coin.coin_pub,
        &cdi->csig))
  {
    TALER_LOG_WARNING ("Invalid signature on /batch-deposit request\n");
    GNUNET_JSON_parse_free (spec);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (
              bdc->rc->connection,
              MHD_HTTP_FORBIDDEN,
              TALER_EC_EXCHANGE_DEPOSIT_COIN_SIGNATURE_INVALID,
              TALER_B2S (&cdi->coin.coin_pub)))
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Run processing phase that parses the request.
 *
 * @param[in,out] bdc request context
 * @param root JSON object that was POSTed
 */
static void
bdc_phase_parse (struct BatchDepositContext *bdc,
                 const json_t *root)
{
  struct TALER_EXCHANGEDB_BatchDeposit *bd = &bdc->bd;
  const json_t *coins;
  const json_t *policy_json;
  bool no_refund_deadline = true;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_payto_uri ("merchant_payto_uri",
                               &bd->receiver_wire_account),
    GNUNET_JSON_spec_fixed_auto ("wire_salt",
                                 &bd->wire_salt),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &bd->merchant_pub),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &bd->h_contract_terms),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("wallet_data_hash",
                                   &bd->wallet_data_hash),
      &bd->no_wallet_data_hash),
    GNUNET_JSON_spec_array_const ("coins",
                                  &coins),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_object_const ("policy",
                                     &policy_json),
      &bdc->has_no_policy),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &bd->wallet_timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &bd->refund_deadline),
      &no_refund_deadline),
    GNUNET_JSON_spec_timestamp ("wire_transfer_deadline",
                                &bd->wire_deadline),
    GNUNET_JSON_spec_end ()
  };

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (bdc->rc->connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      /* hard failure */
      GNUNET_break (0);
      finish_loop (bdc,
                   MHD_NO);
      return;
    }
    if (GNUNET_NO == res)
    {
      /* failure */
      GNUNET_break_op (0);
      finish_loop (bdc,
                   MHD_YES);
      return;
    }
  }
  bdc->policy_json
    = json_incref ((json_t *) policy_json);

  /* validate merchant's wire details (as far as we can) */
  {
    char *emsg;

    emsg = TALER_payto_validate (bd->receiver_wire_account);
    if (NULL != emsg)
    {
      MHD_RESULT ret;

      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      ret = TALER_MHD_reply_with_error (bdc->rc->connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        emsg);
      GNUNET_free (emsg);
      finish_loop (bdc,
                   ret);
      return;
    }
  }
  if (GNUNET_TIME_timestamp_cmp (bd->refund_deadline,
                                 >,
                                 bd->wire_deadline))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    finish_loop (bdc,
                 TALER_MHD_reply_with_error (
                   bdc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE,
                   NULL));
    return;
  }
  if (GNUNET_TIME_absolute_is_never (bd->wire_deadline.abs_time))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    finish_loop (bdc,
                 TALER_MHD_reply_with_error (
                   bdc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_EXCHANGE_DEPOSIT_WIRE_DEADLINE_IS_NEVER,
                   NULL));
    return;
  }
  TALER_payto_hash (bd->receiver_wire_account,
                    &bd->wire_target_h_payto);
  TALER_merchant_wire_signature_hash (bd->receiver_wire_account,
                                      &bd->wire_salt,
                                      &bdc->h_wire);


  bd->num_cdis = json_array_size (coins);
  if (0 == bd->num_cdis)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    finish_loop (bdc,
                 TALER_MHD_reply_with_error (
                   bdc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_GENERIC_PARAMETER_MALFORMED,
                   "coins"));
    return;
  }
  if (TALER_MAX_FRESH_COINS < bd->num_cdis)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    finish_loop (bdc,
                 TALER_MHD_reply_with_error (
                   bdc->rc->connection,
                   MHD_HTTP_BAD_REQUEST,
                   TALER_EC_GENERIC_PARAMETER_MALFORMED,
                   "coins"));
    return;
  }

  bdc->cdis
    = GNUNET_new_array (bd->num_cdis,
                        struct TALER_EXCHANGEDB_CoinDepositInformation);
  bdc->deposit_fees
    = GNUNET_new_array (bd->num_cdis,
                        struct TALER_Amount);
  bd->cdis = bdc->cdis;
  for (unsigned i = 0; i<bd->num_cdis; i++)
  {
    struct TALER_Amount amount_without_fee;
    enum GNUNET_GenericReturnValue res;

    res = parse_coin (bdc,
                      json_array_get (coins,
                                      i),
                      &bdc->cdis[i],
                      &bdc->deposit_fees[i]);
    if (GNUNET_OK != res)
    {
      finish_loop (bdc,
                   (GNUNET_NO == res)
                   ? MHD_YES
                   : MHD_NO);
      return;
    }
    GNUNET_assert (0 <=
                   TALER_amount_subtract (
                     &amount_without_fee,
                     &bdc->cdis[i].amount_with_fee,
                     &bdc->deposit_fees[i]));

    GNUNET_assert (0 <=
                   TALER_amount_add (
                     &bdc->accumulated_total_without_fee,
                     &bdc->accumulated_total_without_fee,
                     &amount_without_fee));
  }

  GNUNET_JSON_parse_free (spec);
  bdc->phase++;
}


/**
 * Function called to clean up a context.
 *
 * @param rc request context with data to clean up
 */
static void
bdc_cleaner (struct TEH_RequestContext *rc)
{
  struct BatchDepositContext *bdc = rc->rh_ctx;

  if (NULL != bdc->lch)
  {
    TEH_legitimization_check_cancel (bdc->lch);
    bdc->lch = NULL;
  }
  for (unsigned int i = 0; i<bdc->bd.num_cdis; i++)
    TALER_denom_sig_free (&bdc->cdis[i].coin.denom_sig);
  GNUNET_free (bdc->cdis);
  GNUNET_free (bdc->deposit_fees);
  json_decref (bdc->policy_json);
  GNUNET_free (bdc);
}


MHD_RESULT
TEH_handler_batch_deposit (struct TEH_RequestContext *rc,
                           const json_t *root,
                           const char *const args[])
{
  struct BatchDepositContext *bdc = rc->rh_ctx;

  (void) args;
  if (NULL == bdc)
  {
    bdc = GNUNET_new (struct BatchDepositContext);
    bdc->rc = rc;
    rc->rh_ctx = bdc;
    rc->rh_cleaner = &bdc_cleaner;
    bdc->phase = BDC_PHASE_PARSE;
    bdc->exchange_timestamp = GNUNET_TIME_timestamp_get ();
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TEH_currency,
                                          &bdc->accumulated_total_without_fee));
  }
  while (1)
  {
    switch (bdc->phase)
    {
    case BDC_PHASE_INIT:
      GNUNET_break (0);
      bdc->phase = BDC_PHASE_RETURN_NO;
      break;
    case BDC_PHASE_PARSE:
      bdc_phase_parse (bdc,
                       root);
      break;
    case BDC_PHASE_POLICY:
      bdc_phase_policy (bdc);
      break;
    case BDC_PHASE_KYC:
      bdc_phase_kyc (bdc);
      break;
    case BDC_PHASE_TRANSACT:
      bdc_phase_transact (bdc);
      break;
    case BDC_PHASE_REPLY_SUCCESS:
      bdc_phase_reply_success (bdc);
      break;
    case BDC_PHASE_SUSPENDED:
      return MHD_YES;
    case BDC_PHASE_CHECK_KYC_RESULT:
      bdc_phase_check_kyc_result (bdc);
      break;
    case BDC_PHASE_GENERATE_REPLY_FAILURE:
      return MHD_queue_response (bdc->rc->connection,
                                 bdc->http_status,
                                 bdc->response);
    case BDC_PHASE_RETURN_YES:
      return MHD_YES;
    case BDC_PHASE_RETURN_NO:
      return MHD_NO;
    }
  }
}


/* end of taler-exchange-httpd_batch-deposit.c */
