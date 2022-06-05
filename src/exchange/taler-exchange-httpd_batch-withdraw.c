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
 * @file taler-exchange-httpd_batch-withdraw.c
 * @brief Handle /reserves/$RESERVE_PUB/batch-withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_batch-withdraw.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Information per planchet in the batch.
 */
struct PlanchetContext
{

  /**
   * Hash of the (blinded) message to be signed by the Exchange.
   */
  struct TALER_BlindedCoinHashP h_coin_envelope;

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
   * Public key of the reserv.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * KYC status of the reserve used for the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Array of @e planchets_length planchets we are processing.
   */
  struct PlanchetContext *planchets;

  /**
   * Total amount from all coins with fees.
   */
  struct TALER_Amount batch_total;

  /**
   * Length of the @e planchets array.
   */
  unsigned int planchets_length;

};


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
 * @param cls a `struct BatchWithdrawContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
batch_withdraw_transaction (void *cls,
                            struct MHD_Connection *connection,
                            MHD_RESULT *mhd_ret)
{
  struct BatchWithdrawContext *wc = cls;
  struct GNUNET_TIME_Timestamp now;
  uint64_t ruuid;
  enum GNUNET_DB_QueryStatus qs;
  bool balance_ok = false;
  bool found = false;

  now = GNUNET_TIME_timestamp_get ();
  qs = TEH_plugin->do_batch_withdraw (TEH_plugin->cls,
                                      now,
                                      wc->reserve_pub,
                                      &wc->batch_total,
                                      &found,
                                      &balance_ok,
                                      &wc->kyc,
                                      &ruuid);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "update_reserve_batch_withdraw");
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
      &wc->batch_total,
      wc->reserve_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if ( (TEH_KYC_NONE != TEH_kyc_config.mode) &&
       (! wc->kyc.ok) &&
       (TALER_EXCHANGEDB_KYC_W2W == wc->kyc.type) )
  {
    /* Wallet-to-wallet payments _always_ require KYC */
    *mhd_ret = TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
      GNUNET_JSON_pack_uint64 ("payment_target_uuid",
                               wc->kyc.payment_target_uuid));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if ( (TEH_KYC_NONE != TEH_kyc_config.mode) &&
       (! wc->kyc.ok) &&
       (TALER_EXCHANGEDB_KYC_WITHDRAW == wc->kyc.type) &&
       (! GNUNET_TIME_relative_is_zero (TEH_kyc_config.withdraw_period)) )
  {
    /* Withdraws require KYC if above threshold */
    enum GNUNET_DB_QueryStatus qs2;
    bool below_limit;

    qs2 = TEH_plugin->do_withdraw_limit_check (
      TEH_plugin->cls,
      ruuid,
      GNUNET_TIME_absolute_subtract (now.abs_time,
                                     TEH_kyc_config.withdraw_period),
      &TEH_kyc_config.withdraw_limit,
      &below_limit);
    if (0 > qs2)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs2);
      if (GNUNET_DB_STATUS_HARD_ERROR == qs2)
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "do_withdraw_limit_check");
      return qs2;
    }
    if (! below_limit)
    {
      *mhd_ret = TALER_MHD_REPLY_JSON_PACK (
        connection,
        MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
        GNUNET_JSON_pack_uint64 ("payment_target_uuid",
                                 wc->kyc.payment_target_uuid));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  /* Add information about each planchet in the batch */
  for (unsigned int i = 0; i<wc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &wc->planchets[i];
    const struct TALER_BlindedPlanchet *bp = &pc->blinded_planchet;
    const struct TALER_CsNonce *nonce;
    bool denom_unknown = true;
    bool conflict = true;
    bool nonce_reuse = true;

    nonce = (TALER_DENOMINATION_CS == bp->cipher)
            ? &bp->details.cs_blinded_planchet.nonce
            : NULL;
    qs = TEH_plugin->do_batch_withdraw_insert (TEH_plugin->cls,
                                               nonce,
                                               &pc->collectable,
                                               now,
                                               ruuid,
                                               &denom_unknown,
                                               &conflict,
                                               &nonce_reuse);
    if (0 > qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "do_withdraw");
      return qs;
    }
    if (denom_unknown)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                                             NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs) ||
         (conflict) )
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Idempotent coin in batch, not allowed. Aborting.\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_CONFLICT,
                                             TALER_EC_EXCHANGE_WITHDRAW_BATCH_IDEMPOTENT_PLANCHET,
                                             NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (nonce_reuse)
    {
      GNUNET_break_op (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_EXCHANGE_WITHDRAW_NONCE_REUSE,
                                             NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Generates our final (successful) response.
 *
 * @param rc request context
 * @param wc operation context
 * @return MHD queue status
 */
static MHD_RESULT
generate_reply_success (const struct TEH_RequestContext *rc,
                        const struct BatchWithdrawContext *wc)
{
  json_t *sigs;

  sigs = json_array ();
  GNUNET_assert (NULL != sigs);
  for (unsigned int i = 0; i<wc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &wc->planchets[i];

    GNUNET_assert (
      0 ==
      json_array_append_new (
        sigs,
        GNUNET_JSON_PACK (
          TALER_JSON_pack_blinded_denom_sig (
            "ev_sig",
            &pc->collectable.sig))));
  }
  TEH_METRICS_batch_withdraw_num_coins += wc->planchets_length;
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("ev_sigs",
                                  sigs));
}


/**
 * Check if the @a rc is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param rc request context
 * @param wc parsed request data
 * @param[out] mret HTTP status, set if we return true
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
check_request_idempotent (const struct TEH_RequestContext *rc,
                          const struct BatchWithdrawContext *wc,
                          MHD_RESULT *mret)
{
  for (unsigned int i = 0; i<wc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &wc->planchets[i];
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_withdraw_info (TEH_plugin->cls,
                                        &pc->h_coin_envelope,
                                        &pc->collectable);
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
  }
  /* generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_BATCH_WITHDRAW]++;
  *mret = generate_reply_success (rc,
                                  wc);
  return true;
}


/**
 * The request was parsed successfully. Prepare
 * our side for the main DB transaction.
 *
 * @param rc request details
 * @param wc storage for request processing
 * @return MHD result for the @a rc
 */
static MHD_RESULT
prepare_transaction (const struct TEH_RequestContext *rc,
                     struct BatchWithdrawContext *wc)
{
  /* Note: We could check the reserve balance here,
     just to be reasonably sure that the reserve has
     a sufficient balance before doing the "expensive"
     signatures... */
  /* Sign before transaction! */
  for (unsigned int i = 0; i<wc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &wc->planchets[i];
    enum TALER_ErrorCode ec;

    ec = TEH_keys_denomination_sign_withdraw (
      &pc->collectable.denom_pub_hash,
      &pc->blinded_planchet,
      &pc->collectable.sig);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_ec (rc->connection,
                                      ec,
                                      NULL);
    }
  }

  /* run transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "run batch withdraw",
                                TEH_MT_REQUEST_WITHDRAW,
                                &mhd_ret,
                                &batch_withdraw_transaction,
                                wc))
    {
      return mhd_ret;
    }
  }
  /* return final positive response */
  return generate_reply_success (rc,
                                 wc);
}


/**
 * Continue processing the request @a rc by parsing the
 * @a planchets and then running the transaction.
 *
 * @param rc request details
 * @param wc storage for request processing
 * @param planchets array of planchets to parse
 * @return MHD result for the @a rc
 */
static MHD_RESULT
parse_planchets (const struct TEH_RequestContext *rc,
                 struct BatchWithdrawContext *wc,
                 const json_t *planchets)
{
  struct TEH_KeyStateHandle *ksh;
  MHD_RESULT mret;

  for (unsigned int i = 0; i<wc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &wc->planchets[i];
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                   &pc->collectable.reserve_sig),
      GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                   &pc->collectable.denom_pub_hash),
      TALER_JSON_spec_blinded_planchet ("coin_ev",
                                        &pc->blinded_planchet),
      GNUNET_JSON_spec_end ()
    };

    {
      enum GNUNET_GenericReturnValue res;

      res = TALER_MHD_parse_json_data (rc->connection,
                                       json_array_get (planchets,
                                                       i),
                                       ispec);
      if (GNUNET_OK != res)
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
    }
    pc->collectable.reserve_pub = *wc->reserve_pub;
    for (unsigned int k = 0; k<i; k++)
    {
      const struct PlanchetContext *kpc = &wc->planchets[k];

      if (0 ==
          TALER_blinded_planchet_cmp (&kpc->blinded_planchet,
                                      &pc->blinded_planchet))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "duplicate planchet");
      }
    }
  }

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    if (! check_request_idempotent (rc,
                                    wc,
                                    &mret))
    {
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         NULL);
    }
    return mret;
  }
  for (unsigned int i = 0; i<wc->planchets_length; i++)
  {
    struct PlanchetContext *pc = &wc->planchets[i];
    struct TEH_DenominationKey *dk;

    dk = TEH_keys_denomination_by_hash2 (ksh,
                                         &pc->collectable.denom_pub_hash,
                                         NULL,
                                         NULL);
    if (NULL == dk)
    {
      if (! check_request_idempotent (rc,
                                      wc,
                                      &mret))
      {
        return TEH_RESPONSE_reply_unknown_denom_pub_hash (
          rc->connection,
          &pc->collectable.denom_pub_hash);
      }
      return mret;
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw.abs_time))
    {
      /* This denomination is past the expiration time for withdraws */
      if (! check_request_idempotent (rc,
                                      wc,
                                      &mret))
      {
        return TEH_RESPONSE_reply_expired_denom_pub_hash (
          rc->connection,
          &pc->collectable.denom_pub_hash,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
          "WITHDRAW");
      }
      return mret;
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid, no need to check
         for idempotency! */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        rc->connection,
        &pc->collectable.denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "WITHDRAW");
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      if (! check_request_idempotent (rc,
                                      wc,
                                      &mret))
      {
        return TEH_RESPONSE_reply_expired_denom_pub_hash (
          rc->connection,
          &pc->collectable.denom_pub_hash,
          TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
          "WITHDRAW");
      }
      return mret;
    }
    if (dk->denom_pub.cipher != pc->blinded_planchet.cipher)
    {
      /* denomination cipher and blinded planchet cipher not the same */
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                         NULL);
    }
    if (0 >
        TALER_amount_add (&pc->collectable.amount_with_fee,
                          &dk->meta.value,
                          &dk->meta.fees.withdraw))
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                                         NULL);
    }
    if (0 >
        TALER_amount_add (&wc->batch_total,
                          &wc->batch_total,
                          &pc->collectable.amount_with_fee))
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_WITHDRAW_AMOUNT_FEE_OVERFLOW,
                                         NULL);
    }

    if (GNUNET_OK !=
        TALER_coin_ev_hash (&pc->blinded_planchet,
                            &pc->collectable.denom_pub_hash,
                            &pc->collectable.h_coin_envelope))
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                         NULL);
    }
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_withdraw_verify (&pc->collectable.denom_pub_hash,
                                      &pc->collectable.amount_with_fee,
                                      &pc->collectable.h_coin_envelope,
                                      &pc->collectable.reserve_pub,
                                      &pc->collectable.reserve_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                         NULL);
    }
  }
  /* everything parsed */
  return prepare_transaction (rc,
                              wc);
}


MHD_RESULT
TEH_handler_batch_withdraw (struct TEH_RequestContext *rc,
                            const struct TALER_ReservePublicKeyP *reserve_pub,
                            const json_t *root)
{
  struct BatchWithdrawContext wc;
  json_t *planchets;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("planchets",
                           &planchets),
    GNUNET_JSON_spec_end ()
  };

  memset (&wc,
          0,
          sizeof (wc));
  TALER_amount_set_zero (TEH_currency,
                         &wc.batch_total);
  wc.reserve_pub = reserve_pub;

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  if ( (! json_is_array (planchets)) ||
       (0 == json_array_size (planchets)) )
  {
    GNUNET_JSON_parse_free (spec);
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "planchets");
  }
  wc.planchets_length = json_array_size (planchets);
  if (wc.planchets_length > TALER_MAX_FRESH_COINS)
  {
    GNUNET_JSON_parse_free (spec);
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "too many planchets");
  }
  {
    struct PlanchetContext splanchets[wc.planchets_length];
    MHD_RESULT ret;

    memset (splanchets,
            0,
            sizeof (splanchets));
    wc.planchets = splanchets;
    ret = parse_planchets (rc,
                           &wc,
                           planchets);
    /* Clean up */
    for (unsigned int i = 0; i<wc.planchets_length; i++)
    {
      struct PlanchetContext *pc = &wc.planchets[i];

      TALER_blinded_planchet_free (&pc->blinded_planchet);
      TALER_blinded_denom_sig_free (&pc->collectable.sig);
    }
    GNUNET_JSON_parse_free (spec);
    return ret;
  }
}


/* end of taler-exchange-httpd_batch-withdraw.c */
