/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_age-withdraw_reveal.c
 * @brief Handle /age-withdraw/$ACH/reveal requests
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_age-withdraw_reveal.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"

/**
 * State for an /age-withdraw/$ACH/reveal operation.
 */
struct AgeRevealContext
{

  /**
   * Commitment for the age-withdraw operation.
   */
  struct TALER_AgeWithdrawCommitmentHashP ach;

  /**
   * Public key of the reserve for with the age-withdraw commitment was
   * originally made.  This parameter is provided by the client again
   * during the call to reveal in order to save a database-lookup.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Number of coins/denonations in the reveal
   */
  uint32_t num_coins;

  /**
   * #num_coins hashes of the denominations from which the coins are withdrawn.
   * Those must support age restriction.
   */
  struct TALER_DenominationHashP *denoms_h;

  /**
   * #num_coins denomination keys, found in the system, according to denoms_h;
   */
  struct TEH_DenominationKey *denom_keys;

  /**
   * #num_coins hases of blinded coins.
   */
  struct TALER_BlindedCoinHashP *coin_evs;

  /**
   * Total sum of all denominations' values
   **/
  struct TALER_Amount total_amount;

  /**
   * Total sum of all denominations' fees
   */
  struct TALER_Amount total_fee;

  /**
   * #num_coins*(kappa - 1) disclosed coins.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey *disclosed_coins;

  /**
   * The data from the original age-withdraw.  Will be retrieved from
   * the DB via @a ach.
   */
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment commitment;
};

/**
 * Helper function to free resources in the context
 */
void
age_reveal_context_free (struct AgeRevealContext *actx)
{
  GNUNET_free (actx->denoms_h);
  GNUNET_free (actx->denom_keys);
  GNUNET_free (actx->coin_evs);
  GNUNET_free (actx->disclosed_coins);
}


/**
 * Parse the json body of an '/age-withdraw/$ACH/reveal' request.  It extracts
 * the denomination hashes, blinded coins and disclosed coins and allocates
 * memory for those.
 *
 * @param connection The MHD connection to handle
 * @param j_denoms_h Array of hashes of the denominations for the withdrawal, in JSON format
 * @param j_coin_evs The blinded envelopes in JSON format for the coins that are not revealed and will be signed on success
 * @param j_disclosed_coins The n*(kappa-1) disclosed coins' private keys in JSON format, from which all other attributes (age restriction, blinding, nonce) will be derived from
 * @param[out] actx The context of the operation, only partially built at call time
 * @param[out] mhd_mret The result if a reply is queued for MHD
 * @return true on success, false on failure, with a reply already queued for MHD.
 */
static enum GNUNET_GenericReturnValue
parse_age_withdraw_reveal_json (
  struct MHD_Connection *connection,
  const json_t *j_denoms_h,
  const json_t *j_coin_evs,
  const json_t *j_disclosed_coins,
  struct AgeRevealContext *actx,
  MHD_RESULT *mhd_ret)
{
  enum GNUNET_GenericReturnValue result = GNUNET_SYSERR;

  /* Verify JSON-structure consistency */
  {
    const char *error = NULL;

    actx->num_coins = json_array_size (j_denoms_h); /* 0, if j_denoms_h is not an array */

    if (! json_is_array (j_denoms_h))
      error = "denoms_h must be an array";
    else if (! json_is_array (j_coin_evs))
      error = "coin_evs must be an array";
    else if (! json_is_array (j_disclosed_coins))
      error = "disclosed_coins must be an array";
    else if (actx->num_coins == 0)
      error = "denoms_h must not be empty";
    else if (actx->num_coins != json_array_size (j_coin_evs))
      error = "denoms_h and coins_evs must be arrays of the same size";
    else if (actx->num_coins > TALER_MAX_FRESH_COINS)
      /**
       * The wallet had committed to more than the maximum coins allowed, the
       * reserve has been charged, but now the user can not withdraw any money
       * from it.  Note that the user can't get their money back in this case!
       **/
      error = "maximum number of coins that can be withdrawn has been exceeded";
    else if (actx->num_coins * (TALER_CNC_KAPPA - 1)
             != json_array_size (j_disclosed_coins))
      error = "the size of array disclosed_coins must be "
              TALER_CNC_KAPPA_MINUS_ONE_STR " times the size of denoms_h";

    if (NULL != error)
    {
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                             error);
      return GNUNET_SYSERR;
    }
  }

  /* Continue parsing the parts */
  {
    unsigned int idx = 0;
    json_t *value = NULL;

    /* Parse denomination keys */
    actx->denoms_h = GNUNET_new_array (actx->num_coins,
                                       struct TALER_DenominationHashP);

    json_array_foreach (j_denoms_h, idx, value) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->denoms_h[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (value, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array denoms_h",
                         idx + 1);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                               msg);
        goto EXIT;
      }
    };

    /* Parse blinded envelopes */
    actx->coin_evs = GNUNET_new_array (actx->num_coins,
                                       struct TALER_BlindedCoinHashP);

    json_array_foreach (j_coin_evs, idx, value) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->coin_evs[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (value, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array coin_evs",
                         idx + 1);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                               msg);
        goto EXIT;
      }
    };

    /* Parse diclosed keys */
    actx->disclosed_coins = GNUNET_new_array (
      actx->num_coins * (TALER_CNC_KAPPA - 1),
      struct GNUNET_CRYPTO_EddsaPrivateKey);

    json_array_foreach (j_disclosed_coins, idx, value) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->disclosed_coins[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (value, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array disclosed_coins",
                         idx + 1);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                               msg);
        goto EXIT;
      }
    };
  }

  result = GNUNET_OK;
  *mhd_ret = MHD_YES;


EXIT:
  return result;
}


/**
 * Check if the request belongs to an existing age-withdraw request.
 * If so, sets the commitment object with the request data.
 * Otherwise, it queues an appropriate MHD response.
 *
 * @param connection The HTTP connection to the client
 * @param h_commitment Original commitment value sent with the age-withdraw request
 * @param reserve_pub Reserve public key used in the original age-withdraw request
 * @param[out] commitment Data from the original age-withdraw request
 * @param[out] result In the error cases, a response will be queued with MHD and this will be the result.
 * @return GNUNET_OK if the withdraw request has been found,
 *   GNUNET_SYSERROR if we did not find the request in the DB
 */
static enum GNUNET_GenericReturnValue
find_original_commitment (
  struct MHD_Connection *connection,
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment *commitment,
  MHD_RESULT *result)
{
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->get_age_withdraw_info (TEH_plugin->cls,
                                          reserve_pub,
                                          h_commitment,
                                          commitment);
  switch (qs)
  {
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    return GNUNET_OK; /* Only happy case */

  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    *result = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          TALER_EC_EXCHANGE_AGE_WITHDRAW_COMMITMENT_UNKNOWN,
                                          NULL);
    break;

  case GNUNET_DB_STATUS_HARD_ERROR:
    *result = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_FETCH_FAILED,
                                          "get_age_withdraw_info");
    break;

  case GNUNET_DB_STATUS_SOFT_ERROR:
  /* FIXME: Do we queue a result in this case or retry? */
  default:
    GNUNET_break (0);       /* should be impossible */
    *result = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                          NULL);
  }

  return GNUNET_SYSERR;
}


/**
 * Check if the given denomination is still or already valid, has not been
 * revoked and supports age restriction.
 *
 * @param connection HTTP-connection to the client
 * @param ksh The handle to the current state of (denomination) keys in the exchange
 * @param denom_h Hash of the denomination key to check
 * @param[out] dks On success, will contain the denomination key details
 * @param[out] result On failure, an MHD-response will be qeued and result will be set to accordingly
 * @return true on success (denomination valid), false otherwise
 */
static bool
denomination_is_valid (
  struct MHD_Connection *connection,
  struct TEH_KeyStateHandle *ksh,
  const struct TALER_DenominationHashP *denom_h,
  struct TEH_DenominationKey *dks,
  MHD_RESULT *result)
{
  dks = TEH_keys_denomination_by_hash2 (
    ksh,
    denom_h,
    connection,
    result);

  /* Does the denomination exist? */
  if (NULL == dks)
  {
    GNUNET_assert (result != NULL);
    /* Note: a HTTP-response has been queued and result has been set by
     * TEH_keys_denominations_by_hash2 */
    return false;
  }

  /* Is the denomation still and already valid? */

  if (GNUNET_TIME_absolute_is_past (dks->meta.expire_withdraw.abs_time))
  {
    /* This denomination is past the expiration time for withdraws */
    *result = TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      denom_h,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
      "age-withdraw_reveal");
    return false;
  }

  if (GNUNET_TIME_absolute_is_future (dks->meta.start.abs_time))
  {
    /* This denomination is not yet valid */
    *result = TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      denom_h,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
      "age-withdraw_reveal");
    return false;
  }

  if (dks->recoup_possible)
  {
    /* This denomination has been revoked */
    *result = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_GONE,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
      NULL);
    return false;
  }

  if (0 == dks->denom_pub.age_mask.bits)
  {
    /* This denomation does not support age restriction */
    char msg[256] = {0};
    GNUNET_snprintf (msg,
                     sizeof(msg),
                     "denomination %s does not support age restriction",
                     GNUNET_h2s (&denom_h->hash));

    *result = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
      msg);
    return false;
  }

  return true;
}


/**
 * Check if the given array of hashes of denomination_keys a) belong
 * to valid denominations and b) those are marked as age restricted.
 *
 * @param connection The HTTP connection to the client
 * @param len The lengths of the array @a denoms_h
 * @param denoms_h array of hashes of denomination public keys
 * @param[out] dks On success, will be filled with the denomination keys.  Caller must deallocate.
 * @param amount_with_fee The commited amount including fees
 * @param[out] total_sum On success, will contain the total sum of all denominations
 * @param[out] total_fee On success, will contain the total sum of all fees
 * @param[out] result In the error cases, a response will be queued with MHD and this will be the result.
 * @return GNUNET_OK if the denominations are valid and support age-restriction
 *   GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
are_denominations_valid (
  struct MHD_Connection *connection,
  uint32_t len,
  const struct TALER_DenominationHashP *denoms_h,
  struct TEH_DenominationKey **dks,
  const struct TALER_Amount *amount_with_fee,
  struct TALER_Amount *total_amount,
  struct TALER_Amount *total_fee,
  MHD_RESULT *result)
{
  struct TEH_KeyStateHandle *ksh;

  GNUNET_assert (*dks == NULL);

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    *result = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                          NULL);
    return GNUNET_SYSERR;
  }

  *dks = GNUNET_new_array (len, struct TEH_DenominationKey);
  TALER_amount_set_zero (TEH_currency, total_amount);
  TALER_amount_set_zero (TEH_currency, total_fee);

  for (uint32_t i = 0; i < len; i++)
  {
    if (! denomination_is_valid (connection,
                                 ksh,
                                 &denoms_h[i],
                                 dks[i],
                                 result))
    {
      return GNUNET_SYSERR;
    }

    /* Accumulate the values */
    if (0 > TALER_amount_add (
          total_amount,
          total_amount,
          &dks[i]->meta.value))
    {
      GNUNET_break (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_INTERNAL_SERVER_ERROR,
                                            TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                                            "amount");
      return GNUNET_SYSERR;
    }

    /* Accumulate the withdraw fees */
    if (0 > TALER_amount_add (
          total_fee,
          total_fee,
          &dks[i]->meta.fees.withdraw))
    {
      GNUNET_break (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_INTERNAL_SERVER_ERROR,
                                            TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                                            "fee");
      return GNUNET_SYSERR;
    }
  }

  /* Compare the commited amount against the totals */
  {
    struct TALER_Amount sum;
    TALER_amount_set_zero (TEH_currency, &sum);

    GNUNET_assert (0 < TALER_amount_add (
                     &sum,
                     total_amount,
                     total_fee));

    if (0 != TALER_amount_cmp (&sum, amount_with_fee))
    {
      GNUNET_break (0);
      *result = TALER_MHD_reply_with_ec (connection,
                                         TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_INCORRECT,
                                         NULL);
      return GNUNET_SYSERR;
    }
  }

  return GNUNET_OK;
}


MHD_RESULT
TEH_handler_age_withdraw_reveal (
  struct TEH_RequestContext *rc,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  const json_t *root)
{
  MHD_RESULT result = MHD_NO;
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct AgeRevealContext actx = {0};
  json_t *j_denoms_h;
  json_t *j_coin_evs;
  json_t *j_disclosed_coins;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_pub", &actx.reserve_pub),
    GNUNET_JSON_spec_json ("denoms_h", &j_denoms_h),
    GNUNET_JSON_spec_json ("coin_evs", &j_coin_evs),
    GNUNET_JSON_spec_json ("disclosed_coins", &j_disclosed_coins),
    GNUNET_JSON_spec_end ()
  };

  actx.ach = *ach;

  /* Parse JSON body*/
  {
    ret = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != ret)
    {
      GNUNET_break_op (0);
      return (GNUNET_SYSERR == ret) ? MHD_NO : MHD_YES;
    }
  }


  do {
    /* Extract denominations, blinded and disclosed coins */
    if (GNUNET_OK != parse_age_withdraw_reveal_json (
          rc->connection,
          j_denoms_h,
          j_coin_evs,
          j_disclosed_coins,
          &actx,
          &result))
      break;

    /* Find original commitment */
    if (GNUNET_OK != find_original_commitment (
          rc->connection,
          &actx.ach,
          &actx.reserve_pub,
          &actx.commitment,
          &result))
      break;

    /* Ensure validity of denoms and the sum of amounts and fees */
    if (GNUNET_OK != are_denominations_valid (
          rc->connection,
          actx.num_coins,
          actx.denoms_h,
          &actx.denom_keys,
          &actx.commitment.amount_with_fee,
          &actx.total_amount,
          &actx.total_fee,
          &result))
      break;


  } while(0);

  /* TODO:oec: compute the disclosed blinded coins */
  /* TODO:oec: generate h_commitment_comp */
  /* TODO:oec: compare h_commitment_comp against h_commitment */
  /* TODO:oec: sign the coins */
  /* TODO:oec: send response */

  age_reveal_context_free (&actx);
  GNUNET_JSON_parse_free (spec);
  return result;
}


/* end of taler-exchange-httpd_age-withdraw_reveal.c */
