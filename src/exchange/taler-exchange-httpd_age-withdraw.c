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
#include "taler-exchange-httpd_withdraw.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler_util.h"


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
   * Set to the hash of the payto account that established
   * the reserve.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Timestamp
   */
  struct GNUNET_TIME_Timestamp now;

  /**
   * The data from the age-withdraw request, as we persist it
   */
  struct TALER_EXCHANGEDB_AgeWithdraw commitment;

  /**
   * Number of coins/denonations in the reveal
   */
  uint32_t num_coins;

  /**
   * #num_coins * #kappa hashes of blinded coin planchets.
   */
  struct TALER_BlindedPlanchet (*coin_evs) [ TALER_CNC_KAPPA];

  /**
   * #num_coins hashes of the denominations from which the coins are withdrawn.
   * Those must support age restriction.
   */
  struct TALER_DenominationHashP *denom_hs;

};

/*
 * @brief Free the resources within a AgeWithdrawContext
 *
 * @param awc the context to free
 */
static void
free_age_withdraw_context_resources (struct AgeWithdrawContext *awc)
{
  GNUNET_free (awc->denom_hs);
  for (unsigned int i = 0; i<awc->num_coins; i++)
  {
    for (unsigned int kappa = 0; kappa<TALER_CNC_KAPPA; kappa++)
    {
      TALER_blinded_planchet_free (&awc->coin_evs[i][kappa]);
    }
  }
  GNUNET_free (awc->coin_evs);
  GNUNET_free (awc->commitment.denom_serials);
  /*
   * Note:
   * awc->commitment.denom_sigs and .h_coin_evs were stack allocated and
   * .denom_pub_hashes is NULL for this context.
   */
}


/**
 * Parse the denominations and blinded coin data of an '/age-withdraw' request.
 *
 * @param connection The MHD connection to handle
 * @param j_denom_hs Array of n hashes of the denominations for the withdrawal, in JSON format
 * @param j_blinded_coin_evs Array of n arrays of kappa blinded envelopes of in JSON format for the coins.
 * @param[out] awc The context of the operation, only partially built at call time
 * @param[out] mhd_ret The result if a reply is queued for MHD
 * @return true on success, false on failure, with a reply already queued for MHD
 */
static enum GNUNET_GenericReturnValue
parse_age_withdraw_json (
  struct MHD_Connection *connection,
  const json_t *j_denom_hs,
  const json_t *j_blinded_coin_evs,
  struct AgeWithdrawContext *awc,
  MHD_RESULT *mhd_ret)
{
  char buf[256] = {0};
  const char *error = NULL;
  unsigned int idx = 0;
  json_t *value = NULL;
  struct GNUNET_HashContext *hash_context;


  /* The age value MUST be on the beginning of an age group */
  if (awc->commitment.max_age !=
      TALER_get_lowest_age (&TEH_age_restriction_config.mask,
                            awc->commitment.max_age))
  {
    error = "max_age must be the lower edge of an age group";
    goto EXIT;
  }

  /* Verify JSON-structure consistency */
  {
    uint32_t num_coins = json_array_size (j_denom_hs);

    if (! json_is_array (j_denom_hs))
      error = "denoms_h must be an array";
    else if (! json_is_array (j_blinded_coin_evs))
      error = "coin_evs must be an array";
    else if (num_coins == 0)
      error = "denoms_h must not be empty";
    else if (num_coins != json_array_size (j_blinded_coin_evs))
      error = "denoms_h and coins_evs must be arrays of the same size";
    else if (num_coins > TALER_MAX_FRESH_COINS)
      /**
       * The wallet had committed to more than the maximum coins allowed, the
       * reserve has been charged, but now the user can not withdraw any money
       * from it.  Note that the user can't get their money back in this case!
       **/
      error = "maximum number of coins that can be withdrawn has been exceeded";

    _Static_assert ((TALER_MAX_FRESH_COINS < INT_MAX / TALER_CNC_KAPPA),
                    "TALER_MAX_FRESH_COINS too large");

    if (NULL != error)
      goto EXIT;

    awc->num_coins =  num_coins;
    awc->commitment.num_coins = num_coins;
  }

  /* Continue parsing the parts */

  /* Parse denomination keys */
  awc->denom_hs = GNUNET_new_array (awc->num_coins,
                                    struct TALER_DenominationHashP);

  json_array_foreach (j_denom_hs, idx, value) {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &awc->denom_hs[idx]),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (value, spec, NULL, NULL))
    {
      GNUNET_snprintf (buf,
                       sizeof(buf),
                       "couldn't parse entry no. %d in array denoms_h",
                       idx + 1);
      error = buf;
      goto EXIT;
    }
  };

  {
    typedef struct TALER_BlindedPlanchet
      _array_of_kappa_planchets[TALER_CNC_KAPPA];

    awc->coin_evs = GNUNET_new_array (awc->num_coins,
                                      _array_of_kappa_planchets);
  }

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  GNUNET_assert (NULL != hash_context);

  /* Parse blinded envelopes. */
  json_array_foreach (j_blinded_coin_evs, idx, value) {
    const json_t *j_kappa_coin_evs = value;

    if (! json_is_array (j_kappa_coin_evs))
    {
      GNUNET_snprintf (buf,
                       sizeof(buf),
                       "enxtry %d in array blinded_coin_evs is not an array",
                       idx + 1);
      error = buf;
      goto EXIT;
    }
    else if (TALER_CNC_KAPPA != json_array_size (j_kappa_coin_evs))
    {
      GNUNET_snprintf (buf,
                       sizeof(buf),
                       "array no. %d in coin_evs not of correct size",
                       idx + 1);
      error = buf;
      goto EXIT;
    }

    /* Now parse the individual kappa envelopes and calculate the hash of
     * the commitment along the way. */
    {
      unsigned int kappa = 0;

      json_array_foreach (j_kappa_coin_evs, kappa, value) {
        struct GNUNET_JSON_Specification spec[] = {
          TALER_JSON_spec_blinded_planchet (NULL,
                                            &awc->coin_evs[idx][kappa]),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (value,
                               spec,
                               NULL,
                               NULL))
        {
          GNUNET_snprintf (buf,
                           sizeof(buf),
                           "couldn't parse array no. %d in blinded_coin_evs[%d]",
                           kappa + 1,
                           idx + 1);
          error = buf;
          goto EXIT;
        }

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
          if (0 == TALER_blinded_planchet_cmp (&awc->coin_evs[idx][kappa],
                                               &awc->coin_evs[i][kappa]))
          {
            GNUNET_JSON_parse_free (spec);
            error = "duplicate planchet";
            goto EXIT;
          }
        }
      }
    }
  }; /* json_array_foreach over j_blinded_coin_evs */

  /* Finally, calculate the h_commitment from all blinded envelopes */
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &awc->commitment.h_commitment.hash);

  GNUNET_assert (NULL == error);


EXIT:
  if (NULL != error)
  {
    /* Note: resources are freed in caller */

    *mhd_ret = TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      error);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Check if the given denomination is still or already valid, has not been
 * revoked and supports age restriction.
 *
 * @param connection HTTP-connection to the client
 * @param ksh The handle to the current state of (denomination) keys in the exchange
 * @param denom_h Hash of the denomination key to check
 * @param[out] pdk On success, will contain the denomination key details
 * @param[out] result On failure, an MHD-response will be queued and result will be set to accordingly
 * @return true on success (denomination valid), false otherwise
 */
static bool
denomination_is_valid (
  struct MHD_Connection *connection,
  struct TEH_KeyStateHandle *ksh,
  const struct TALER_DenominationHashP *denom_h,
  struct TEH_DenominationKey **pdk,
  MHD_RESULT *result)
{
  struct TEH_DenominationKey *dk;
  dk = TEH_keys_denomination_by_hash_from_state (ksh,
                                                 denom_h,
                                                 connection,
                                                 result);
  if (NULL == dk)
  {
    /* The denomination doesn't exist */
    /* Note: a HTTP-response has been queued and result has been set by
     * TEH_keys_denominations_by_hash_from_state */
    return false;
  }

  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_withdraw.abs_time))
  {
    /* This denomination is past the expiration time for withdraws */
    /* FIXME[oec]: add idempotency check */
    *result = TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      denom_h,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
      "age-withdraw_reveal");
    return false;
  }

  if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
  {
    /* This denomination is not yet valid */
    *result = TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      denom_h,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
      "age-withdraw_reveal");
    return false;
  }

  if (dk->recoup_possible)
  {
    /* This denomination has been revoked */
    *result = TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
      NULL);
    return false;
  }

  if (0 == dk->denom_pub.age_mask.bits)
  {
    /* This denomation does not support age restriction */
    char msg[256] = {0};
    GNUNET_snprintf (msg,
                     sizeof(msg),
                     "denomination %s does not support age restriction",
                     GNUNET_h2s (&denom_h->hash));

    *result = TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
      msg);
    return false;
  }

  *pdk = dk;
  return true;
}


/**
 * Check if the given array of hashes of denomination_keys a) belong
 * to valid denominations and b) those are marked as age restricted.
 * Also, calculate the total amount of the denominations including fees
 * for withdraw.
 *
 * @param connection The HTTP connection to the client
 * @param len The lengths of the array @a denoms_h
 * @param denom_hs array of hashes of denomination public keys
 * @param coin_evs array of blinded coin planchet candidates
 * @param[out] denom_serials On success, will be filled with the serial-id's of the denomination keys.  Caller must deallocate.
 * @param[out] amount_with_fee On success, will contain the committed amount including fees
 * @param[out] result In the error cases, a response will be queued with MHD and this will be the result.
 * @return #GNUNET_OK if the denominations are valid and support age-restriction
 *   #GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
are_denominations_valid (
  struct MHD_Connection *connection,
  uint32_t len,
  const struct TALER_DenominationHashP *denom_hs,
  const struct TALER_BlindedPlanchet (*coin_evs) [ TALER_CNC_KAPPA],
  uint64_t **denom_serials,
  struct TALER_Amount *amount_with_fee,
  MHD_RESULT *result)
{
  struct TALER_Amount total_amount;
  struct TALER_Amount total_fee;
  struct TEH_KeyStateHandle *ksh;
  uint64_t *serials;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *result = TALER_MHD_reply_with_ec (connection,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       NULL);
    return GNUNET_SYSERR;
  }

  *denom_serials =
    serials = GNUNET_new_array (len, uint64_t);

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &total_amount));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &total_fee));

  for (uint32_t i = 0; i < len; i++)
  {
    struct TEH_DenominationKey *dk;
    if (! denomination_is_valid (connection,
                                 ksh,
                                 &denom_hs[i],
                                 &dk,
                                 result))
      /* FIXME[oec]: add idempotency check */
      return GNUNET_SYSERR;

    /* Ensure the ciphers from the planchets match the denominations' */
    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      if (dk->denom_pub.bsign_pub_key->cipher !=
          coin_evs[i][k].blinded_message->cipher)
      {
        GNUNET_break_op (0);
        *result = TALER_MHD_reply_with_ec (connection,
                                           TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                           NULL);
        return GNUNET_SYSERR;
      }
    }

    /* Accumulate the values */
    if (0 > TALER_amount_add (&total_amount,
                              &total_amount,
                              &dk->meta.value))
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_BAD_REQUEST,
                                            TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                                            "amount");
      return GNUNET_SYSERR;
    }

    /* Accumulate the withdraw fees */
    if (0 > TALER_amount_add (&total_fee,
                              &total_fee,
                              &dk->meta.fees.withdraw))
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_BAD_REQUEST,
                                            TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                                            "fee");
      return GNUNET_SYSERR;
    }

    serials[i] = dk->meta.serial;
  }

  /* Save the total amount including fees */
  GNUNET_assert (0 < TALER_amount_add (amount_with_fee,
                                       &total_amount,
                                       &total_fee));

  return GNUNET_OK;
}


/**
 * @brief Verify the signature of the request body with the reserve key
 *
 * @param connection the connection to the client
 * @param commitment the age withdraw commitment
 * @param mhd_ret the response to fill in the error case
 * @return GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
verify_reserve_signature (
  struct MHD_Connection *connection,
  const struct TALER_EXCHANGEDB_AgeWithdraw *commitment,
  enum MHD_Result *mhd_ret)
{
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_age_withdraw_verify (&commitment->h_commitment,
                                        &commitment->amount_with_fee,
                                        &TEH_age_restriction_config.mask,
                                        commitment->max_age,
                                        &commitment->reserve_pub,
                                        &commitment->reserve_sig))
  {
    GNUNET_break_op (0);
    *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                        TALER_EC_EXCHANGE_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                        NULL);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


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
  enum TALER_ErrorCode ec;

  ec = TALER_exchange_online_age_withdraw_confirmation_sign (
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
 * Check if the request is replayed and we already have an
 * answer. If so, replay the existing answer and return the
 * HTTP response.
 *
 * @param con connection to the client
 * @param[in,out] awc parsed request data
 * @param[out] mret HTTP status, set if we return true
 * @return true if the request is idempotent with an existing request
 *    false if we did not find the request in the DB and did not set @a mret
 */
static bool
request_is_idempotent (struct MHD_Connection *con,
                       struct AgeWithdrawContext *awc,
                       MHD_RESULT *mret)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_AgeWithdraw commitment;

  qs = TEH_plugin->get_age_withdraw (TEH_plugin->cls,
                                     &awc->commitment.reserve_pub,
                                     &awc->commitment.h_commitment,
                                     &commitment);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mret = TALER_MHD_reply_with_ec (con,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "get_age_withdraw");
    return true; /* Well, kind-of.  At least we have set mret. */
  }

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    return false;

  /* Generate idempotent reply */
  TEH_METRICS_num_requests[TEH_MT_REQUEST_IDEMPOTENT_AGE_WITHDRAW]++;
  *mret = reply_age_withdraw_success (con,
                                      &commitment.h_commitment,
                                      commitment.noreveal_index);
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
age_withdraw_transaction (void *cls,
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

  qs = TEH_withdraw_kyc_check (&awc->kyc,
                               &awc->h_payto,
                               connection,
                               mhd_ret,
                               &awc->commitment.reserve_pub,
                               &awc->commitment.amount_with_fee,
                               awc->now);
  if ( (qs < 0) ||
       (! awc->kyc.ok) )
    return qs;
  qs = TEH_plugin->do_age_withdraw (TEH_plugin->cls,
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
      *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                          TALER_EC_GENERIC_DB_FETCH_FAILED,
                                          "do_age_withdraw");
    return qs;
  }
  if (! found)
  {
    *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                        TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                        NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! age_ok)
  {
    enum TALER_ErrorCode ec =
      TALER_EC_EXCHANGE_AGE_WITHDRAW_MAXIMUM_AGE_TOO_LARGE;

    *mhd_ret =
      TALER_MHD_REPLY_JSON_PACK (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_MHD_PACK_EC (ec),
        GNUNET_JSON_pack_uint64 ("allowed_maximum_age",
                                 allowed_maximum_age),
        GNUNET_JSON_pack_uint64 ("reserve_birthday",
                                 reserve_birthday));

    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);

    *mhd_ret = TEH_RESPONSE_reply_reserve_insufficient_balance (
      connection,
      TALER_EC_EXCHANGE_AGE_WITHDRAW_INSUFFICIENT_FUNDS,
      &reserve_balance,
      &awc->commitment.amount_with_fee,
      &awc->commitment.reserve_pub);

    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (conflict)
  {
    /* do_age_withdraw signaled a conflict, so there MUST be an entry
     * in the DB.  Put that into the response */
    bool ok = request_is_idempotent (connection,
                                     awc,
                                     mhd_ret);
    GNUNET_assert (ok);
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  *mhd_ret = -1;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    TEH_METRICS_num_success[TEH_MT_SUCCESS_AGE_WITHDRAW]++;
  return qs;
}


/**
 * @brief Sign the chosen blinded coins, debit the reserve and persist
 * the commitment.
 *
 * On conflict, the noreveal_index from the previous, existing
 * commitment is returned to the client, returning success.
 *
 * On error (like, insufficient funds), the client is notified.
 *
 * Note that on success, there are two possible states:
 *  1.) KYC is required (awc.kyc.ok == false) or
 *  2.) age withdraw was successful.
 *
 * @param connection HTTP-connection to the client
 * @param awc The context for the current age withdraw request
 * @param[out] result On error, a HTTP-response will be queued and result set accordingly
 * @return #GNUNET_OK on success, #GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
sign_and_do_age_withdraw (
  struct MHD_Connection *connection,
  struct AgeWithdrawContext *awc,
  MHD_RESULT *result)
{
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct TALER_BlindedCoinHashP h_coin_evs[awc->num_coins];
  struct TALER_BlindedDenominationSignature denom_sigs[awc->num_coins];
  uint8_t noreveal_index;

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
      csds[i].bp = &awc->coin_evs[i][noreveal_index];
      csds[i].h_denom_pub = &awc->denom_hs[i];
    }

    ec = TEH_keys_denomination_batch_sign (awc->num_coins,
                                           csds,
                                           false,
                                           denom_sigs);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      *result = TALER_MHD_reply_with_ec (connection,
                                         ec,
                                         NULL);
      return GNUNET_SYSERR;
    }
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Signatures ready, starting DB interaction\n");

  /* Prepare the hashes of the coins for insertion */
  for (uint32_t i = 0; i<awc->num_coins; i++)
  {
    TALER_coin_ev_hash (&awc->coin_evs[i][noreveal_index],
                        &awc->denom_hs[i],
                        &h_coin_evs[i]);
  }

  /* Run the transaction */
  awc->commitment.h_coin_evs = h_coin_evs;
  awc->commitment.denom_sigs = denom_sigs;
  ret = TEH_DB_run_transaction (connection,
                                "run age withdraw",
                                TEH_MT_REQUEST_AGE_WITHDRAW,
                                result,
                                &age_withdraw_transaction,
                                awc);
  /* Free resources */
  for (unsigned int i = 0; i<awc->num_coins; i++)
    TALER_blinded_denom_sig_free (&denom_sigs[i]);
  awc->commitment.h_coin_evs = NULL;
  awc->commitment.denom_sigs = NULL;
  return ret;
}


MHD_RESULT
TEH_handler_age_withdraw (struct TEH_RequestContext *rc,
                          const struct TALER_ReservePublicKeyP *reserve_pub,
                          const json_t *root)
{
  MHD_RESULT mhd_ret;
  const json_t *j_denom_hs;
  const json_t *j_blinded_coin_evs;
  struct AgeWithdrawContext awc = {
    .commitment.reserve_pub = *reserve_pub,
    .now = GNUNET_TIME_timestamp_get ()
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("denom_hs",
                                  &j_denom_hs),
    GNUNET_JSON_spec_array_const ("blinded_coin_evs",
                                  &j_blinded_coin_evs),
    GNUNET_JSON_spec_uint16 ("max_age",
                             &awc.commitment.max_age),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &awc.commitment.reserve_sig),
    GNUNET_JSON_spec_end ()
  };

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
    /* Note: If we break the statement here at any point,
     * a response to the client MUST have been populated
     * with an appropriate answer and mhd_ret MUST have
     * been set accordingly.
     */

    /* Parse denoms_h and blinded_coins_evs, partially fill awc */
    if (GNUNET_OK !=
        parse_age_withdraw_json (rc->connection,
                                 j_denom_hs,
                                 j_blinded_coin_evs,
                                 &awc,
                                 &mhd_ret))
      break;

    /* Ensure validity of denoms and calculate amounts and fees */
    if (GNUNET_OK !=
        are_denominations_valid (rc->connection,
                                 awc.num_coins,
                                 awc.denom_hs,
                                 awc.coin_evs,
                                 &awc.commitment.denom_serials,
                                 &awc.commitment.amount_with_fee,
                                 &mhd_ret))
      break;

    /* Now that amount_with_fee is calculated, verify the signature of
     * the request body with the reserve key.
     */
    if (GNUNET_OK !=
        verify_reserve_signature (rc->connection,
                                  &awc.commitment,
                                  &mhd_ret))
      break;

    /* Sign the chosen blinded coins, persist the commitment and
     * charge the reserve.
     * On error (like, insufficient funds), the client is notified.
     * On conflict, the noreveal_index from the previous, existing
     * commitment is returned to the client, returning success.
     * Note that on success, there are two possible states:
     *    KYC is required (awc.kyc.ok == false) or
     *    age withdraw was successful.
     */
    if (GNUNET_OK !=
        sign_and_do_age_withdraw (rc->connection,
                                  &awc,
                                  &mhd_ret))
      break;

    /* Send back final response, depending on the outcome of
     * the DB-transaction */
    if (! awc.kyc.ok)
      mhd_ret = TEH_RESPONSE_reply_kyc_required (
        rc->connection,
        &awc.h_payto,
        &awc.kyc);
    else
      mhd_ret = reply_age_withdraw_success (
        rc->connection,
        &awc.commitment.h_commitment,
        awc.commitment.noreveal_index);

  } while (0);

  GNUNET_JSON_parse_free (spec);
  free_age_withdraw_context_resources (&awc);
  return mhd_ret;
}


/* end of taler-exchange-httpd_age-withdraw.c */
