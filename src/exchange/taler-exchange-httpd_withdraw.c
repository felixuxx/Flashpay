/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file taler-exchange-httpd_withdraw.c
 * @brief Handle /reserves/$RESERVE_PUB/withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Context for #withdraw_transaction.
 */
struct WithdrawContext
{

  /**
   * Hash of the (blinded) message to be signed by the Exchange.
   */
  struct TALER_BlindedCoinHashP h_coin_envelope;

  /**
   * Blinded planchet.
   */
  struct TALER_BlindedPlanchet blinded_planchet;

  /**
   * Set to the resulting signed coin data to be returned to the client.
   */
  struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

  /**
   * KYC status for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash of the payto-URI representing the reserve
   * from which we are withdrawing.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Current time for the DB transaction.
   */
  struct GNUNET_TIME_Timestamp now;

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
withdraw_amount_cb (void *cls,
                    struct GNUNET_TIME_Absolute limit,
                    TALER_EXCHANGEDB_KycAmountCallback cb,
                    void *cb_cls)
{
  struct WithdrawContext *wc = cls;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Signaling amount %s for KYC check\n",
              TALER_amount2s (&wc->collectable.amount_with_fee));
  if (GNUNET_OK !=
      cb (cb_cls,
          &wc->collectable.amount_with_fee,
          wc->now.abs_time))
    return;
  qs = TEH_plugin->select_withdraw_amounts_for_kyc_check (
    TEH_plugin->cls,
    &wc->h_payto,
    limit,
    cb,
    cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this withdrawal and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
}


/**
 * Function implementing withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * Note that "wc->collectable.sig" is set before entering this function as we
 * signed before entering the transaction.
 *
 * @param cls a `struct WithdrawContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
withdraw_transaction (void *cls,
                      struct MHD_Connection *connection,
                      MHD_RESULT *mhd_ret)
{
  struct WithdrawContext *wc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool found = false;
  bool balance_ok = false;
  bool nonce_ok = false;
  uint64_t ruuid;
  const struct TALER_CsNonce *nonce;
  const struct TALER_BlindedPlanchet *bp;

  wc->now = GNUNET_TIME_timestamp_get ();
  qs = TEH_plugin->reserves_get_origin (TEH_plugin->cls,
                                        &wc->collectable.reserve_pub,
                                        &wc->h_payto);
  if (qs < 0)
    return qs;
  /* If no results, reserve was created by merge,
     in which case no KYC check is required as the
     merge already did that. */
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    const char *kyc_required;

    kyc_required = TALER_KYCLOGIC_kyc_test_required (
      TALER_KYCLOGIC_KYC_TRIGGER_WITHDRAW,
      &wc->h_payto,
      TEH_plugin->select_satisfied_kyc_processes,
      TEH_plugin->cls,
      &withdraw_amount_cb,
      wc);
    if (NULL != kyc_required)
    {
      /* insert KYC requirement into DB! */
      wc->kyc.ok = false;
      return TEH_plugin->insert_kyc_requirement_for_account (
        TEH_plugin->cls,
        kyc_required,
        &wc->h_payto,
        &wc->kyc.requirement_row);
    }
  }
  wc->kyc.ok = true;
  bp = &wc->blinded_planchet;
  nonce = (TALER_DENOMINATION_CS == bp->cipher)
    ? &bp->details.cs_blinded_planchet.nonce
    : NULL;
  qs = TEH_plugin->do_withdraw (TEH_plugin->cls,
                                nonce,
                                &wc->collectable,
                                wc->now,
                                &found,
                                &balance_ok,
                                &nonce_ok,
                                &ruuid);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "do_withdraw");
    return qs;
  }
  if (! found)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret = TEH_RESPONSE_reply_reserve_insufficient_balance (
      connection,
      &wc->collectable.amount_with_fee,
      &wc->collectable.reserve_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! nonce_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_CONFLICT,
                                           TALER_EC_EXCHANGE_WITHDRAW_NONCE_REUSE,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    TEH_METRICS_num_success[TEH_MT_SUCCESS_WITHDRAW]++;
  return qs;
}


/**
 * Check if the @a rc is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param rc request context
 * @param[in,out] wc parsed request data
 * @param[out] mret HTTP status, set if we return true
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
check_request_idempotent (struct TEH_RequestContext *rc,
                          struct WithdrawContext *wc,
                          MHD_RESULT *mret)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->get_withdraw_info (TEH_plugin->cls,
                                      &wc->h_coin_envelope,
                                      &wc->collectable);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mret = TALER_MHD_reply_with_error (rc->connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_FETCH_FAILED,
                                          "get_withdraw_info");
    return true; /* well, kind-of */
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return false;
  /* generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_WITHDRAW]++;
  *mret = TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_blinded_denom_sig ("ev_sig",
                                       &wc->collectable.sig));
  TALER_blinded_denom_sig_free (&wc->collectable.sig);
  return true;
}


MHD_RESULT
TEH_handler_withdraw (struct TEH_RequestContext *rc,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const json_t *root)
{
  struct WithdrawContext wc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &wc.collectable.reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &wc.collectable.denom_pub_hash),
    TALER_JSON_spec_blinded_planchet ("coin_ev",
                                      &wc.blinded_planchet),
    GNUNET_JSON_spec_end ()
  };
  enum TALER_ErrorCode ec;
  struct TEH_DenominationKey *dk;

  memset (&wc,
          0,
          sizeof (wc));
  wc.collectable.reserve_pub = *reserve_pub;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  {
    MHD_RESULT mret;
    struct TEH_KeyStateHandle *ksh;

    ksh = TEH_keys_get_state ();
    if (NULL == ksh)
    {
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                           NULL);
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    dk = TEH_keys_denomination_by_hash2 (ksh,
                                         &wc.collectable.denom_pub_hash,
                                         NULL,
                                         NULL);
    if (NULL == dk)
    {
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TEH_RESPONSE_reply_unknown_denom_pub_hash (
          rc->connection,
          &wc.collectable.denom_pub_hash);
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw.abs_time))
    {
      /* This denomination is past the expiration time for withdraws */
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TEH_RESPONSE_reply_expired_denom_pub_hash (
          rc->connection,
          &wc.collectable.denom_pub_hash,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
          "WITHDRAW");
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid, no need to check
         for idempotency! */
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &wc.collectable.denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "WITHDRAW");
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TEH_RESPONSE_reply_expired_denom_pub_hash (
          rc->connection,
          &wc.collectable.denom_pub_hash,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
          "WITHDRAW");
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    if (dk->denom_pub.cipher != wc.blinded_planchet.cipher)
    {
      /* denomination cipher and blinded planchet cipher not the same */
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                         NULL);
    }
  }

  if (0 >
      TALER_amount_add (&wc.collectable.amount_with_fee,
                        &dk->meta.value,
                        &dk->meta.fees.withdraw))
  {
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                                       NULL);
  }

  if (GNUNET_OK !=
      TALER_coin_ev_hash (&wc.blinded_planchet,
                          &wc.collectable.denom_pub_hash,
                          &wc.collectable.h_coin_envelope))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                       NULL);
  }

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_withdraw_verify (&wc.collectable.denom_pub_hash,
                                    &wc.collectable.amount_with_fee,
                                    &wc.collectable.h_coin_envelope,
                                    &wc.collectable.reserve_pub,
                                    &wc.collectable.reserve_sig))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                       NULL);
  }

  /* Sign before transaction! */
  ec = TEH_keys_denomination_sign_withdraw (
    &wc.collectable.denom_pub_hash,
    &wc.blinded_planchet,
    &wc.collectable.sig);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to sign coin: %d\n",
                ec);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_ec (rc->connection,
                                    ec,
                                    NULL);
  }

  /* run transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "run withdraw",
                                TEH_MT_REQUEST_WITHDRAW,
                                &mhd_ret,
                                &withdraw_transaction,
                                &wc))
    {
      /* Even if #withdraw_transaction() failed, it may have created a signature
         (or we might have done it optimistically above). */
      TALER_blinded_denom_sig_free (&wc.collectable.sig);
      GNUNET_JSON_parse_free (spec);
      return mhd_ret;
    }
  }

  /* Clean up and send back final response */
  GNUNET_JSON_parse_free (spec);

  if (! wc.kyc.ok)
    return TEH_RESPONSE_reply_kyc_required (rc->connection,
                                            &wc.h_payto,
                                            &wc.kyc);
  {
    MHD_RESULT ret;

    ret = TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      TALER_JSON_pack_blinded_denom_sig ("ev_sig",
                                         &wc.collectable.sig));
    TALER_blinded_denom_sig_free (&wc.collectable.sig);
    return ret;
  }
}


/* end of taler-exchange-httpd_withdraw.c */
