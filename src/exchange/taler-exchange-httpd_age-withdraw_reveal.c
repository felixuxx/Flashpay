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
#include "taler-exchange-httpd_metrics.h"
#include "taler_exchangedb_plugin.h"
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
   * Commitment for the age-withdraw operation, previously called by the
   * client.
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
   * Total sum of all denominations' values
   **/
  struct TALER_Amount total_amount;

  /**
   * Total sum of all denominations' fees
   */
  struct TALER_Amount total_fee;

  /**
   * #num_coins hashes of blinded coin planchets.
   */
  struct TALER_BlindedPlanchet *coin_evs;

  /**
   * secrets for #num_coins*(kappa - 1) disclosed coins.
   */
  struct TALER_PlanchetMasterSecretP *disclosed_coin_secrets;

  /**
   * The data from the original age-withdraw.  Will be retrieved from
   * the DB via @a ach.
   */
  struct TALER_EXCHANGEDB_AgeWithdrawCommitment commitment;
};


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
 * Helper function to free resources in the context
 */
void
age_reveal_context_free (struct AgeRevealContext *actx)
{
  GNUNET_free (actx->denoms_h);
  GNUNET_free (actx->denom_keys);
  GNUNET_free (actx->coin_evs);
  GNUNET_free (actx->disclosed_coin_secrets);
}


/**
 * Parse the json body of an '/age-withdraw/$ACH/reveal' request.  It extracts
 * the denomination hashes, blinded coins and disclosed coins and allocates
 * memory for those.
 *
 * @param connection The MHD connection to handle
 * @param j_denoms_h Array of hashes of the denominations for the withdrawal, in JSON format
 * @param j_coin_evs The blinded envelopes in JSON format for the coins that are not revealed and will be signed on success
 * @param j_disclosed_coin_secrets The n*(kappa-1) disclosed coins' private keys in JSON format, from which all other attributes (age restriction, blinding, nonce) will be derived from
 * @param[out] actx The context of the operation, only partially built at call time
 * @param[out] mhd_ret The result if a reply is queued for MHD
 * @return true on success, false on failure, with a reply already queued for MHD.
 */
static enum GNUNET_GenericReturnValue
parse_age_withdraw_reveal_json (
  struct MHD_Connection *connection,
  const json_t *j_denoms_h,
  const json_t *j_coin_evs,
  const json_t *j_disclosed_coin_secrets,
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
    else if (! json_is_array (j_disclosed_coin_secrets))
      error = "disclosed_coin_secrets must be an array";
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
             != json_array_size (j_disclosed_coin_secrets))
      error = "the size of array disclosed_coin_secrets must be "
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
                                       struct TALER_BlindedPlanchet);

    json_array_foreach (j_coin_evs, idx, value) {
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_blinded_planchet (NULL, &actx->coin_evs[idx]),
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

      /* Check for duplicate planchets */
      for (unsigned int i = 0; i < idx; i++)
      {
        if (0 == TALER_blinded_planchet_cmp (&actx->coin_evs[idx],
                                             &actx->coin_evs[i]))
        {
          GNUNET_break_op (0);
          *mhd_ret = TALER_MHD_reply_with_error (connection,
                                                 MHD_HTTP_BAD_REQUEST,
                                                 TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                                 "duplicate planchet");
          goto EXIT;
        }

      }
    };

    /* Parse diclosed keys */
    actx->disclosed_coin_secrets = GNUNET_new_array (
      actx->num_coins * (TALER_CNC_KAPPA - 1),
      struct TALER_PlanchetMasterSecretP);

    json_array_foreach (j_disclosed_coin_secrets, idx, value) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->disclosed_coin_secrets[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (value, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array disclosed_coin_secrets",
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
  /* FIXME oec: Do we queue a result in this case or retry? */
  default:
    GNUNET_break (0);
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
  dks = TEH_keys_denomination_by_hash2 (ksh,
                                        denom_h,
                                        connection,
                                        result);
  if (NULL == dks)
  {
    /* The denomination doesn't exist */
    GNUNET_assert (result != NULL);
    /* Note: a HTTP-response has been queued and result has been set by
     * TEH_keys_denominations_by_hash2 */
    return false;
  }

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
 * @param coin_evs array of blinded coin planchets
 * @param[out] dks On success, will be filled with the denomination keys.  Caller must deallocate.
 * @param amount_with_fee The committed amount including fees
 * @param[out] total_amount On success, will contain the total sum of all denominations
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
  const struct TALER_BlindedPlanchet *coin_evs,
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
      return GNUNET_SYSERR;

    /* Ensure the ciphers from the planchets match the denominations' */
    if (dks[i]->denom_pub.cipher != coin_evs[i].cipher)
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_BAD_REQUEST,
                                            TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                            NULL);
      return GNUNET_SYSERR;
    }

    /* Accumulate the values */
    if (0 > TALER_amount_add (
          total_amount,
          total_amount,
          &dks[i]->meta.value))
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_BAD_REQUEST,
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
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_BAD_REQUEST,
                                            TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_OVERFLOW,
                                            "fee");
      return GNUNET_SYSERR;
    }
  }

  /* Compare the committed amount against the totals */
  {
    struct TALER_Amount sum;
    TALER_amount_set_zero (TEH_currency, &sum);

    GNUNET_assert (0 < TALER_amount_add (
                     &sum,
                     total_amount,
                     total_fee));

    if (0 != TALER_amount_cmp (&sum, amount_with_fee))
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_error (connection,
                                            MHD_HTTP_BAD_REQUEST,
                                            TALER_EC_EXCHANGE_AGE_WITHDRAW_AMOUNT_INCORRECT,
                                            NULL);
      return GNUNET_SYSERR;
    }
  }

  return GNUNET_OK;
}


/**
 * Checks the validity of the disclosed coins as follows:
 * - Derives and calculates the disclosed coins'
 *    - public keys,
 *    - nonces (if applicable),
 *    - age commitments,
 *    - blindings
 *    - blinded hashes
 * - Computes h_commitment with those calculated and the undisclosed hashes
 * - Compares h_commitment with the value from the original commitment
 * - Verifies that all public keys in indices larger than the age group
 *   corresponding to max_age are derived from the constant public key.
 *
 * The derivation of the blindings, (potential) nonces and age-commitment from
 * a coin's private keys is defined in
 * https://docs.taler.net/design-documents/024-age-restriction.html#withdraw
 *
 * @param connection HTTP-connection to the client
 * @param h_commitment_orig Original commitment
 * @param max_age Maximum age allowed for the age restriction
 * @param noreveal_idx Index that was given to the client in response to the age-withdraw request
 * @param num_coins Number of coins
 * @param coin_evs The blindet planchets of the undisclosed coins, @a num_coins many
 * @param denom_keys The array of denomination keys, @a num_coins. Needed to detect Clause-Schnorr-based denominations
 * @param disclosed_coin_secrets The secrets of the disclosed coins, (TALER_CNC_KAPPA - 1)*num_coins many
 * @param[out] result On error, a HTTP-response will be queued and result set accordingly
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
verify_commitment_and_max_age (
  struct MHD_Connection *connection,
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment_orig,
  const uint32_t max_age,
  const uint32_t noreveal_idx,
  const uint32_t num_coins,
  const struct TALER_BlindedPlanchet *coin_evs,
  const struct TEH_DenominationKey *denom_keys,
  const struct TALER_PlanchetMasterSecretP *disclosed_coin_secrets,
  MHD_RESULT *result)
{
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct GNUNET_HashContext *hash_context;

  hash_context = GNUNET_CRYPTO_hash_context_start ();

  for (size_t c = 0; c < num_coins; c++)
  {
    size_t k = 0; /* either 0 or 1, to index into coin_evs */

    for (size_t idx = 0; idx<TALER_CNC_KAPPA; idx++)
    {
      if (idx == (size_t) noreveal_idx)
      {
        GNUNET_CRYPTO_hash_context_read (hash_context,
                                         &coin_evs[c],
                                         sizeof(coin_evs[c]));
      }
      else
      {
        /* FIXME[oec] Refactor this block out into its own function */

        size_t j = (TALER_CNC_KAPPA - 1) * c + k; /* Index into disclosed_coin_secrets[] */
        const struct TALER_PlanchetMasterSecretP *secret;
        struct TALER_AgeCommitmentHash ach;
        struct TALER_BlindedCoinHashP bch;

        GNUNET_assert (k<2);
        GNUNET_assert ((TALER_CNC_KAPPA - 1) * num_coins  > j);

        secret = &disclosed_coin_secrets[j];
        k++;

        /* First: calculate age commitment hash */
        {
          struct TALER_AgeCommitmentProof acp;
          ret = TALER_age_restriction_from_secret (
            secret,
            &denom_keys[c].denom_pub.age_mask,
            max_age,
            &acp);

          if (GNUNET_OK != ret)
          {
            GNUNET_break (0);
            *result = TALER_MHD_reply_json_pack (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 "{sssi}",
                                                 "failed to derive age restriction from base key",
                                                 "index",
                                                 j);
            return ret;
          }

          TALER_age_commitment_hash (&acp.commitment, &ach);
        }

        /* Next: calculate planchet */
        {
          struct TALER_CoinPubHashP c_hash;
          struct TALER_PlanchetDetail detail;
          struct TALER_CoinSpendPrivateKeyP coin_priv;
          union TALER_DenominationBlindingKeyP bks;
          struct TALER_ExchangeWithdrawValues alg_values = {
            .cipher = denom_keys[c].denom_pub.cipher,
          };

          if (TALER_DENOMINATION_CS == alg_values.cipher)
          {
            struct TALER_CsNonce nonce;

            TALER_cs_withdraw_nonce_derive (
              secret,
              &nonce);

            {
              enum TALER_ErrorCode ec;
              struct TEH_CsDeriveData cdd = {
                .h_denom_pub = &denom_keys[c].h_denom_pub,
                .nonce = &nonce,
              };

              ec = TEH_keys_denomination_cs_r_pub (&cdd,
                                                   false,
                                                   &alg_values.details.
                                                   cs_values);
              /* FIXME Handle error? */
              GNUNET_assert (TALER_EC_NONE == ec);
            }
          }

          TALER_planchet_blinding_secret_create (secret,
                                                 &alg_values,
                                                 &bks);

          TALER_planchet_setup_coin_priv (secret,
                                          &alg_values,
                                          &coin_priv);

          ret = TALER_planchet_prepare (&denom_keys[c].denom_pub,
                                        &alg_values,
                                        &bks,
                                        &coin_priv,
                                        &ach,
                                        &c_hash,
                                        &detail);

          if (GNUNET_OK != ret)
          {
            GNUNET_break (0);
            *result = TALER_MHD_reply_json_pack (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 "{sssi}",
                                                 "details",
                                                 "failed to prepare planchet from base key",
                                                 "index",
                                                 j);
            return ret;
          }

          ret = TALER_coin_ev_hash (&detail.blinded_planchet,
                                    &denom_keys[c].h_denom_pub,
                                    &bch);
          if (GNUNET_OK != ret)
          {
            GNUNET_break (0);
            *result = TALER_MHD_reply_json_pack (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 "{sssi}",
                                                 "details",
                                                 "failed to hash planchet from base key",
                                                 "index",
                                                 j);
            return ret;
          }

        }

        /* Continue the running hash of all coin hashes with the calculated
         * hash-value of the current, disclosed coin */
        GNUNET_CRYPTO_hash_context_read (hash_context,
                                         &bch,
                                         sizeof(bch));
      }
    }
  }

  /* Finally, compare the calculated hash with the original commitment */
  {
    struct GNUNET_HashCode calc_hash;
    GNUNET_CRYPTO_hash_context_finish (hash_context,
                                       &calc_hash);

    if (0 != GNUNET_CRYPTO_hash_cmp (&h_commitment_orig->hash,
                                     &calc_hash))
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_ec (connection,
                                         TALER_EC_EXCHANGE_AGE_WITHDRAW_REVEAL_INVALID_HASH,
                                         NULL);
      return GNUNET_SYSERR;
    }

  }

  return ret;
}


/**
 * @brief Send a response for "/age-withdraw/$RCH/reveal"
 *
 * @param connection The http connection to the client to send the response to
 * @param num_coins Number of new coins with age restriction for which we reveal data
 * @param awrcs array of @a num_coins signatures revealed
 * @return a MHD result code
 */
static MHD_RESULT
reply_age_withdraw_reveal_success (
  struct MHD_Connection *connection,
  unsigned int num_coins,
  const struct TALER_EXCHANGEDB_AgeWithdrawRevealedCoin *awrcs)
{
  json_t *list = json_array ();
  GNUNET_assert (NULL != list);

  for (unsigned int index = 0;
       index < num_coins;
       index++)
  {
    json_t *obj = GNUNET_JSON_PACK (
      TALER_JSON_pack_blinded_denom_sig ("ev_sig",
                                         &awrcs[index].coin_sig));
    GNUNET_assert (0 ==
                   json_array_append_new (list,
                                          obj));
  }

  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("ev_sigs",
                                  list));
}


/**
 * @brief Signs and persists the undisclosed coins
 *
 * @param connection HTTP-connection to the client
 * @param h_commitment Original commitment
 * @param num_coins Number of coins
 * @param coin_evs The Hashes of the undisclosed, blinded coins, @a num_coins many
 * @param denom_keys The array of denomination keys, @a num_coins. Needed to detect Clause-Schnorr-based denominations
 * @param[out] result On error, a HTTP-response will be queued and result set accordingly
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
sign_and_finalize_age_withdraw (
  struct MHD_Connection *connection,
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  const uint32_t num_coins,
  const struct TALER_BlindedPlanchet *coin_evs,
  const struct TEH_DenominationKey *denom_keys,
  MHD_RESULT *result)
{
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct TEH_CoinSignData csds[num_coins];
  struct TALER_BlindedDenominationSignature bds[num_coins];
  struct TALER_EXCHANGEDB_AgeWithdrawRevealedCoin awrcs[num_coins];
  enum GNUNET_DB_QueryStatus qs;

  for (uint32_t i = 0; i<num_coins; i++)
  {
    csds[i].h_denom_pub = &denom_keys[i].h_denom_pub;
    csds[i].bp = &coin_evs[i];
  }

  /* Sign the the blinded coins first */
  {
    enum TALER_ErrorCode ec;
    ec = TEH_keys_denomination_batch_sign (csds,
                                           num_coins,
                                           false,
                                           bds);
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

  /* Prepare the data for insertion */
  for (uint32_t i = 0; i<num_coins; i++)
  {
    TALER_coin_ev_hash (&coin_evs[i],
                        csds[i].h_denom_pub,
                        &awrcs[i].h_coin_ev);
    awrcs[i].h_denom_pub = *csds[i].h_denom_pub;
    awrcs[i].coin_sig = bds[i];
  }

  /* Persist operation result in DB, transactionally */
  for (unsigned int r = 0; r < MAX_TRANSACTION_COMMIT_RETRIES; r++)
  {
    bool changed = false;

    /* Transaction start */
    if (GNUNET_OK !=
        TEH_plugin->start (TEH_plugin->cls,
                           "insert_age_withdraw_reveal batch"))
    {
      GNUNET_break (0);
      ret = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_GENERIC_DB_START_FAILED,
                                        NULL);
      goto cleanup;
    }

    qs = TEH_plugin->insert_age_withdraw_reveal (TEH_plugin->cls,
                                                 h_commitment,
                                                 num_coins,
                                                 awrcs);

    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      TEH_plugin->rollback (TEH_plugin->cls);
      continue;
    }
    else if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls);
      ret = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_GENERIC_DB_STORE_FAILED,
                                        "insert_age_withdraw_reveal");
      goto cleanup;
    }

    changed = (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);

    /* Commit the transaction */
    qs = TEH_plugin->commit (TEH_plugin->cls);
    if (qs >= 0)
    {
      if (changed)
        TEH_METRICS_num_success[TEH_MT_SUCCESS_AGE_WITHDRAW_REVEAL]++;

      break; /* success */

    }
    else if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls);
      ret = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_GENERIC_DB_COMMIT_FAILED,
                                        NULL);
      goto cleanup;
    }
    else
    {
      TEH_plugin->rollback (TEH_plugin->cls);
    }
  } /* end of retry */

  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
  {
    GNUNET_break (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    ret = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                      NULL);
    goto cleanup;
  }

  /* Generate final (positive) response */
  ret = reply_age_withdraw_reveal_success (connection,
                                           num_coins,
                                           awrcs);
cleanup:
  GNUNET_break (GNUNET_OK != ret);

  /* Free resources */
  for (unsigned int i = 0; i<num_coins; i++)
    TALER_blinded_denom_sig_free (&awrcs[i].coin_sig);
  return ret;
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
  json_t *j_disclosed_coin_secrets;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_pub", &actx.reserve_pub),
    GNUNET_JSON_spec_json ("denoms_h", &j_denoms_h),
    GNUNET_JSON_spec_json ("coin_evs", &j_coin_evs),
    GNUNET_JSON_spec_json ("disclosed_coin_secrets", &j_disclosed_coin_secrets),
    GNUNET_JSON_spec_end ()
  };

  actx.ach = *ach;

  /* Parse JSON body*/
  ret = TALER_MHD_parse_json_data (rc->connection,
                                   root,
                                   spec);
  if (GNUNET_OK != ret)
  {
    GNUNET_break_op (0);
    return (GNUNET_SYSERR == ret) ? MHD_NO : MHD_YES;
  }


  do {
    /* Extract denominations, blinded and disclosed coins */
    if (GNUNET_OK != parse_age_withdraw_reveal_json (
          rc->connection,
          j_denoms_h,
          j_coin_evs,
          j_disclosed_coin_secrets,
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
          actx.coin_evs,
          &actx.denom_keys,
          &actx.commitment.amount_with_fee,
          &actx.total_amount,
          &actx.total_fee,
          &result))
      break;

    /* Verify the computed h_commitment equals the committed one and that coins
     * have a maximum age group corresponding max_age (age-mask dependent) */
    if (GNUNET_OK != verify_commitment_and_max_age (
          rc->connection,
          &actx.commitment.h_commitment,
          actx.commitment.max_age,
          actx.commitment.noreveal_index,
          actx.num_coins,
          actx.coin_evs,
          actx.denom_keys,
          actx.disclosed_coin_secrets,
          &result))
      break;

    /* Finally, sign and persist the coins */
    if (GNUNET_OK != sign_and_finalize_age_withdraw (
          rc->connection,
          &actx.commitment.h_commitment,
          actx.num_coins,
          actx.coin_evs,
          actx.denom_keys,
          &result))
      break;

  } while(0);

  age_reveal_context_free (&actx);
  GNUNET_JSON_parse_free (spec);
  return result;
}


/* end of taler-exchange-httpd_age-withdraw_reveal.c */
