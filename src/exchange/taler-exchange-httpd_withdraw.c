/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_withdraw.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Send reserve history information to client with the
 * message that we have insufficient funds for the
 * requested withdraw operation.
 *
 * @param connection connection to the client
 * @param ebalance expected balance based on our database
 * @param rh reserve history to return
 * @return MHD result code
 */
static MHD_RESULT
reply_withdraw_insufficient_funds (
  struct MHD_Connection *connection,
  const struct TALER_Amount *ebalance,
  const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = TEH_RESPONSE_compile_reserve_history (rh,
                                                       &balance);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_WITHDRAW_HISTORY_ERROR_INSUFFICIENT_FUNDS,
                                       NULL);
  if (0 !=
      TALER_amount_cmp (&balance,
                        ebalance))
  {
    GNUNET_break (0);
    json_decref (json_history);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                                       "reserve balance corrupt");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_CONFLICT,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_WITHDRAW_INSUFFICIENT_FUNDS),
    TALER_JSON_pack_amount ("balance",
                            &balance),
    GNUNET_JSON_pack_array_steal ("history",
                                  json_history));
}


/**
 * Context for #withdraw_transaction.
 */
struct WithdrawContext
{
  /**
   * Details about the withdrawal request.
   */
  struct TALER_WithdrawRequestPS wsrd;

  /**
   * Value of the coin plus withdraw fee.
   */
  struct TALER_Amount amount_required;

  /**
   * Hash of the denomination public key.
   */
  struct TALER_DenominationHash denom_pub_hash;

  /**
   * Signature over the request.
   */
  struct TALER_ReserveSignatureP signature;

  /**
   * Blinded planchet.
   */
  char *blinded_msg;

  /**
   * Number of bytes in @e blinded_msg.
   */
  size_t blinded_msg_len;

  /**
   * Set to the resulting signed coin data to be returned to the client.
   */
  struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

  /**
   * KYC status for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Set to true if the operation was denied due to
   * failing @e kyc checks.
   */
  bool kyc_denied;

};


/**
 * Function called with another amount that was
 * already withdrawn. Accumulates all amounts in
 * @a cls.
 *
 * @param[in,out] cls a `struct TALER_Amount`
 * @param val value to add to @a cls
 */
static void
accumulate_withdraws (void *cls,
                      const struct TALER_Amount *val)
{
  struct TALER_Amount *acc = cls;

  if (GNUNET_OK !=
      TALER_amount_is_valid (acc))
    return; /* ignore */
  GNUNET_break (0 <=
                TALER_amount_add (acc,
                                  acc,
                                  val));
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
  struct TALER_EXCHANGEDB_Reserve r;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_BlindedDenominationSignature denom_sig;

  /* store away optimistic signature to protect
     it from being overwritten by get_withdraw_info */
  denom_sig = wc->collectable.sig;
  memset (&wc->collectable.sig,
          0,
          sizeof (wc->collectable.sig));
  qs = TEH_plugin->get_withdraw_info (TEH_plugin->cls,
                                      &wc->wsrd.h_coin_envelope,
                                      &wc->collectable);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "withdraw details");
    wc->collectable.sig = denom_sig;
    return qs;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Asked to withdraw from %s amount of %s\n",
              TALER_B2S (&wc->wsrd.reserve_pub),
              TALER_amount2s (&wc->amount_required));
  /* Don't sign again if we have already signed the coin */
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    /* Toss out the optimistic signature, we got another one from the DB;
       optimization trade-off loses in this case: we unnecessarily computed
       a signature :-( */
    TALER_blinded_denom_sig_free (&denom_sig);
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  /* We should never get more than one result, and we handled
     the errors (negative case) above, so that leaves no results. */
  GNUNET_assert (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs);
  wc->collectable.sig = denom_sig;

  /* Check if balance is sufficient */
  r.pub = wc->wsrd.reserve_pub; /* other fields of 'r' initialized in reserves_get (if successful) */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to withdraw from reserve: %s\n",
              TALER_B2S (&r.pub));
  qs = TEH_plugin->reserves_get (TEH_plugin->cls,
                                 &r,
                                 &wc->kyc);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "reserves");
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_WITHDRAW_RESERVE_UNKNOWN,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 < TALER_amount_cmp (&wc->amount_required,
                            &r.balance))
  {
    struct TALER_EXCHANGEDB_ReserveHistory *rh;

    /* The reserve does not have the required amount (actual
     * amount + withdraw fee) */
#if GNUNET_EXTRA_LOGGING
    {
      char *amount_required;
      char *r_balance;

      amount_required = TALER_amount_to_string (&wc->amount_required);
      r_balance = TALER_amount_to_string (&r.balance);
      TALER_LOG_DEBUG ("Asked %s over a reserve worth %s\n",
                       amount_required,
                       r_balance);
      GNUNET_free (amount_required);
      GNUNET_free (r_balance);
    }
#endif
    qs = TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                          &wc->wsrd.reserve_pub,
                                          &rh);
    if (NULL == rh)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "reserve history");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    *mhd_ret = reply_withdraw_insufficient_funds (connection,
                                                  &r.balance,
                                                  rh);
    TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                      rh);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC status is %s for %s\n",
              wc->kyc.ok ? "ok" : "missing",
              TALER_B2S (&r.pub));
  if ( (! wc->kyc.ok) &&
       (TEH_KYC_NONE != TEH_kyc_config.mode) &&
       (TALER_EXCHANGEDB_KYC_W2W == wc->kyc.type) )
  {
    /* Wallet-to-wallet payments _always_ require KYC */
    wc->kyc_denied = true;
    return qs;
  }
  if ( (! wc->kyc.ok) &&
       (TEH_KYC_NONE != TEH_kyc_config.mode) &&
       (TALER_EXCHANGEDB_KYC_WITHDRAW == wc->kyc.type) &&
       (! GNUNET_TIME_relative_is_zero (TEH_kyc_config.withdraw_period)) )
  {
    /* Withdraws require KYC if above threshold */
    struct TALER_Amount acc;
    enum GNUNET_DB_QueryStatus qs2;

    acc = wc->amount_required;
    qs2 = TEH_plugin->select_withdraw_amounts_by_account (
      TEH_plugin->cls,
      &wc->wsrd.reserve_pub,
      TEH_kyc_config.withdraw_period,
      &accumulate_withdraws,
      &acc);
    if (0 > qs2)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs2);
      if (GNUNET_DB_STATUS_HARD_ERROR == qs2)
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "withdraw details");
      return qs2;
    }

    if (GNUNET_OK !=
        TALER_amount_is_valid (&acc))
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                          TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                          NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Amount withdrawn so far is %s\n",
                TALER_amount2s (&acc));
    if (1 == /* 1: acc > withdraw_limit */
        TALER_amount_cmp (&acc,
                          &TEH_kyc_config.withdraw_limit))
    {
      wc->kyc_denied = true;
      return qs;
    }
  }

  /* Balance is good, persist signature */
  wc->collectable.denom_pub_hash = wc->denom_pub_hash;
  wc->collectable.amount_with_fee = wc->amount_required;
  wc->collectable.reserve_pub = wc->wsrd.reserve_pub;
  wc->collectable.h_coin_envelope = wc->wsrd.h_coin_envelope;
  wc->collectable.reserve_sig = wc->signature;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Persisting withdraw from %s over %s\n",
              TALER_B2S (&r.pub),
              TALER_amount2s (&wc->amount_required));
  qs = TEH_plugin->insert_withdraw_info (TEH_plugin->cls,
                                         &wc->collectable);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "withdraw details");
    return qs;
  }
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
                                      &wc->wsrd.h_coin_envelope,
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
                      const json_t *root,
                      const char *const args[2])
{
  struct WithdrawContext wc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("coin_ev",
                              (void **) &wc.blinded_msg,
                              &wc.blinded_msg_len),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &wc.signature),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &wc.denom_pub_hash),
    GNUNET_JSON_spec_end ()
  };
  enum TALER_ErrorCode ec;
  struct TEH_DenominationKey *dk;

  memset (&wc,
          0,
          sizeof (wc));
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &wc.wsrd.reserve_pub,
                                     sizeof (wc.wsrd.reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_MERCHANT_GENERIC_RESERVE_PUB_MALFORMED,
                                       args[0]);
  }

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
    struct GNUNET_TIME_Absolute now;
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
                                         &wc.denom_pub_hash,
                                         NULL,
                                         NULL);
    if (NULL == dk)
    {
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TEH_RESPONSE_reply_unknown_denom_pub_hash (rc->connection,
                                                          &wc.denom_pub_hash);
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    now = GNUNET_TIME_absolute_get ();
    (void) GNUNET_TIME_round_abs (&now);
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw))
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* This denomination is past the expiration time for withdraws */
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TEH_RESPONSE_reply_expired_denom_pub_hash (
          rc->connection,
          &wc.denom_pub_hash,
          now,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
          "WITHDRAW");
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start))
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* This denomination is not yet valid, no need to check
         for idempotency! */
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &wc.denom_pub_hash,
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "WITHDRAW");
    }
    if (dk->recoup_possible)
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* This denomination has been revoked */
      if (! check_request_idempotent (rc,
                                      &wc,
                                      &mret))
      {
        GNUNET_JSON_parse_free (spec);
        return TEH_RESPONSE_reply_expired_denom_pub_hash (
          rc->connection,
          &wc.denom_pub_hash,
          now,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
          "WITHDRAW");
      }
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
  }

  {
    if (0 >
        TALER_amount_add (&wc.amount_required,
                          &dk->meta.value,
                          &dk->meta.fee_withdraw))
    {
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                                         NULL);
    }
    TALER_amount_hton (&wc.wsrd.amount_with_fee,
                       &wc.amount_required);
  }

  /* verify signature! */
  wc.wsrd.purpose.size
    = htonl (sizeof (wc.wsrd));
  wc.wsrd.purpose.purpose
    = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  wc.wsrd.h_denomination_pub
    = wc.denom_pub_hash;
  TALER_coin_ev_hash (wc.blinded_msg,
                      wc.blinded_msg_len,
                      &wc.wsrd.h_coin_envelope);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wc.wsrd,
                                  &wc.signature.eddsa_signature,
                                  &wc.wsrd.reserve_pub.eddsa_pub))
  {
    TALER_LOG_WARNING (
      "Client supplied invalid signature for withdraw request\n");
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                       NULL);
  }

  /* Sign before transaction! */
  ec = TALER_EC_NONE;
  wc.collectable.sig
    = TEH_keys_denomination_sign (&wc.denom_pub_hash,
                                  wc.blinded_msg,
                                  wc.blinded_msg_len,
                                  &ec);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_ec (rc->connection,
                                    ec,
                                    NULL);
  }

  /* run transaction and sign (if not optimistically signed before) */
  wc.kyc_denied = false;
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "run withdraw",
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

  if (wc.kyc_denied)
  {
    TALER_blinded_denom_sig_free (&wc.collectable.sig);
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_ACCEPTED,
      GNUNET_JSON_pack_uint64 ("payment_target_uuid",
                               wc.kyc.payment_target_uuid));
  }

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
