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
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler-exchange-httpd_metrics.h"
#include "taler_error_codes.h"
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
   * Number of coins to reveal.  MUST be equal to
   * @e num_secrets/(kappa -1).
   */
  uint32_t num_coins;

  /**
   * Number of secrets in the reveal.  MUST be a multiple of (kappa-1).
   */
  uint32_t num_secrets;

  /**
   * @e num_secrets secrets for  disclosed coins.
   */
  struct TALER_PlanchetMasterSecretP *disclosed_coin_secrets;

  /**
   * The data from the original age-withdraw.  Will be retrieved from
   * the DB via @a ach and @a reserve_pub.
   */
  struct TALER_EXCHANGEDB_AgeWithdraw commitment;
};


/**
 * Parse the json body of an '/age-withdraw/$ACH/reveal' request.  It extracts
 * the denomination hashes, blinded coins and disclosed coins and allocates
 * memory for those.
 *
 * @param connection The MHD connection to handle
 * @param j_disclosed_coin_secrets The n*(kappa-1) disclosed coins' private keys in JSON format, from which all other attributes (age restriction, blinding, nonce) will be derived from
 * @param[out] actx The context of the operation, only partially built at call time
 * @param[out] mhd_ret The result if a reply is queued for MHD
 * @return true on success, false on failure, with a reply already queued for MHD.
 */
static enum GNUNET_GenericReturnValue
parse_age_withdraw_reveal_json (
  struct MHD_Connection *connection,
  const json_t *j_disclosed_coin_secrets,
  struct AgeRevealContext *actx,
  MHD_RESULT *mhd_ret)
{
  enum GNUNET_GenericReturnValue result = GNUNET_SYSERR;
  size_t num_entries;

  /* Verify JSON-structure consistency */
  {
    const char *error = NULL;

    num_entries = json_array_size (j_disclosed_coin_secrets); /* 0, if not an array */

    if (! json_is_array (j_disclosed_coin_secrets))
      error = "disclosed_coin_secrets must be an array";
    else if (num_entries == 0)
      error = "disclosed_coin_secrets must not be empty";
    else if (num_entries > TALER_MAX_FRESH_COINS)
      error = "maximum number of coins that can be withdrawn has been exceeded";

    if (NULL != error)
    {
      *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                          TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                          error);
      return GNUNET_SYSERR;
    }

    actx->num_secrets = num_entries * (TALER_CNC_KAPPA - 1);
    actx->num_coins = num_entries;

  }

  /* Continue parsing the parts */
  {
    unsigned int idx = 0;
    unsigned int k = 0;
    json_t *array = NULL;
    json_t *value = NULL;

    /* Parse diclosed keys */
    actx->disclosed_coin_secrets =
      GNUNET_new_array (actx->num_secrets,
                        struct TALER_PlanchetMasterSecretP);

    json_array_foreach (j_disclosed_coin_secrets, idx, array) {
      if (! json_is_array (array) ||
          (TALER_CNC_KAPPA - 1 != json_array_size (array)))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array disclosed_coin_secrets",
                         idx + 1);
        *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                            TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                            msg);
        goto EXIT;

      }

      json_array_foreach (array, k, value)
      {
        struct TALER_PlanchetMasterSecretP *secret =
          &actx->disclosed_coin_secrets[2 * idx + k];
        struct GNUNET_JSON_Specification spec[] = {
          GNUNET_JSON_spec_fixed_auto (NULL, secret),
          GNUNET_JSON_spec_end ()
        };

        if (GNUNET_OK !=
            GNUNET_JSON_parse (value, spec, NULL, NULL))
        {
          char msg[256] = {0};
          GNUNET_snprintf (msg,
                           sizeof(msg),
                           "couldn't parse entry no. %d in array disclosed_coin_secrets[%d]",
                           k + 1,
                           idx + 1);
          *mhd_ret = TALER_MHD_reply_with_ec (connection,
                                              TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                              msg);
          goto EXIT;
        }
      }
    };
  }

  result = GNUNET_OK;

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
 * @return #GNUNET_OK if the withdraw request has been found,
 *   #GNUNET_SYSERR if we did not find the request in the DB
 */
static enum GNUNET_GenericReturnValue
find_original_commitment (
  struct MHD_Connection *connection,
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_EXCHANGEDB_AgeWithdraw *commitment,
  MHD_RESULT *result)
{
  enum GNUNET_DB_QueryStatus qs;

  for (unsigned int try = 0; try < 3; try++)
  {
    qs = TEH_plugin->get_age_withdraw (TEH_plugin->cls,
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
      return GNUNET_SYSERR;
    case GNUNET_DB_STATUS_HARD_ERROR:
      *result = TALER_MHD_reply_with_ec (connection,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "get_age_withdraw_info");
      return GNUNET_SYSERR;
    case GNUNET_DB_STATUS_SOFT_ERROR:
      break; /* try again */
    default:
      GNUNET_break (0);
      *result = TALER_MHD_reply_with_ec (connection,
                                         TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                         NULL);
      return GNUNET_SYSERR;
    }
  }
  /* after unsuccessful retries*/
  *result = TALER_MHD_reply_with_ec (connection,
                                     TALER_EC_GENERIC_DB_FETCH_FAILED,
                                     "get_age_withdraw_info");
  return GNUNET_SYSERR;
}


/**
 * @brief Derives a age-restricted planchet from a given secret and calculates the hash
 *
 * @param connection Connection to the client
 * @param keys The denomination keys in memory
 * @param secret The secret to a planchet
 * @param denom_pub_h The hash of the denomination for the planchet
 * @param max_age The maximum age allowed
 * @param[out] bch Hashcode to write
 * @param[out] result On error, a HTTP-response will be queued and result set accordingly
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise, with an error message
 * written to the client and @e result set.
 */
static enum GNUNET_GenericReturnValue
calculate_blinded_hash (
  struct MHD_Connection *connection,
  const struct TEH_KeyStateHandle *keys,
  const struct TALER_PlanchetMasterSecretP *secret,
  const struct TALER_DenominationHashP *denom_pub_h,
  uint8_t max_age,
  struct TALER_BlindedCoinHashP *bch,
  MHD_RESULT *result)
{
  enum GNUNET_GenericReturnValue ret;
  struct TEH_DenominationKey *denom_key;
  struct TALER_AgeCommitmentHash ach;

  /* First, retrieve denomination details */
  denom_key = TEH_keys_denomination_by_hash_from_state (keys,
                                                        denom_pub_h,
                                                        connection,
                                                        result);
  if (NULL == denom_key)
  {
    GNUNET_break_op (0);
    *result = TALER_MHD_reply_with_ec (connection,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       NULL);
    return GNUNET_SYSERR;
  }

  /* calculate age commitment hash */
  {
    struct TALER_AgeCommitmentProof acp;

    TALER_age_restriction_from_secret (secret,
                                       &denom_key->denom_pub.age_mask,
                                       max_age,
                                       &acp);
    TALER_age_commitment_hash (&acp.commitment,
                               &ach);
    TALER_age_commitment_proof_free (&acp);
  }

  /* Next: calculate planchet */
  {
    struct TALER_CoinPubHashP c_hash;
    struct TALER_PlanchetDetail detail = {0};
    struct TALER_CoinSpendPrivateKeyP coin_priv;
    union GNUNET_CRYPTO_BlindingSecretP bks;
    struct GNUNET_CRYPTO_BlindingInputValues bi = {
      .cipher = denom_key->denom_pub.bsign_pub_key->cipher
    };
    struct TALER_ExchangeWithdrawValues alg_values = {
      .blinding_inputs = &bi
    };
    union GNUNET_CRYPTO_BlindSessionNonce nonce;
    union GNUNET_CRYPTO_BlindSessionNonce *noncep = NULL;

    // FIXME: add logic to denom.c to do this!
    if (GNUNET_CRYPTO_BSA_CS == bi.cipher)
    {
      struct TEH_CsDeriveData cdd = {
        .h_denom_pub = &denom_key->h_denom_pub,
        .nonce = &nonce.cs_nonce,
      };

      TALER_cs_withdraw_nonce_derive (secret,
                                      &nonce.cs_nonce);
      noncep = &nonce;
      GNUNET_assert (TALER_EC_NONE ==
                     TEH_keys_denomination_cs_r_pub (
                       &cdd,
                       false,
                       &bi.details.cs_values));
    }
    TALER_planchet_blinding_secret_create (secret,
                                           &alg_values,
                                           &bks);
    TALER_planchet_setup_coin_priv (secret,
                                    &alg_values,
                                    &coin_priv);
    ret = TALER_planchet_prepare (&denom_key->denom_pub,
                                  &alg_values,
                                  &bks,
                                  noncep,
                                  &coin_priv,
                                  &ach,
                                  &c_hash,
                                  &detail);
    if (GNUNET_OK != ret)
    {
      GNUNET_break (0);
      *result = TALER_MHD_reply_json_pack (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           "{ss}",
                                           "details",
                                           "failed to prepare planchet from base key");
      return ret;
    }

    TALER_coin_ev_hash (&detail.blinded_planchet,
                        &denom_key->h_denom_pub,
                        bch);
    TALER_blinded_planchet_free (&detail.blinded_planchet);
  }

  return ret;
}


/**
 * @brief Checks the validity of the disclosed coins as follows:
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
 * @param commitment Original commitment
 * @param disclosed_coin_secrets The secrets of the disclosed coins, (TALER_CNC_KAPPA - 1)*num_coins many
 * @param num_coins number of coins to reveal via @a disclosed_coin_secrets
 * @param[out] result On error, a HTTP-response will be queued and result set accordingly
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
verify_commitment_and_max_age (
  struct MHD_Connection *connection,
  const struct TALER_EXCHANGEDB_AgeWithdraw *commitment,
  const struct TALER_PlanchetMasterSecretP *disclosed_coin_secrets,
  uint32_t num_coins,
  MHD_RESULT *result)
{
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct GNUNET_HashContext *hash_context;
  struct TEH_KeyStateHandle *keys;

  if (num_coins != commitment->num_coins)
  {
    GNUNET_break_op (0);
    *result = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_BAD_REQUEST,
                                          TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                          "#coins");
    return GNUNET_SYSERR;
  }

  /* We need the current keys in memory for the meta-data of the denominations */
  keys = TEH_keys_get_state ();
  if (NULL == keys)
  {
    *result = TALER_MHD_reply_with_ec (connection,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       NULL);
    return GNUNET_SYSERR;
  }

  hash_context = GNUNET_CRYPTO_hash_context_start ();

  for (size_t coin_idx = 0; coin_idx < num_coins; coin_idx++)
  {
    size_t i = 0; /* either 0 or 1, to index into coin_evs */

    for (size_t k = 0; k<TALER_CNC_KAPPA; k++)
    {
      if (k == (size_t) commitment->noreveal_index)
      {
        GNUNET_CRYPTO_hash_context_read (hash_context,
                                         &commitment->h_coin_evs[coin_idx],
                                         sizeof(commitment->h_coin_evs[coin_idx]));
      }
      else
      {
        /* j is the index into disclosed_coin_secrets[] */
        size_t j = (TALER_CNC_KAPPA - 1) * coin_idx + i;
        const struct TALER_PlanchetMasterSecretP *secret;
        struct TALER_BlindedCoinHashP bch;

        GNUNET_assert (2>i);
        GNUNET_assert ((TALER_CNC_KAPPA - 1) * num_coins  > j);

        secret = &disclosed_coin_secrets[j];
        i++;

        ret = calculate_blinded_hash (connection,
                                      keys,
                                      secret,
                                      &commitment->denom_pub_hashes[coin_idx],
                                      commitment->max_age,
                                      &bch,
                                      result);

        if (GNUNET_OK != ret)
        {
          GNUNET_CRYPTO_hash_context_abort (hash_context);
          return GNUNET_SYSERR;
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

    if (0 != GNUNET_CRYPTO_hash_cmp (&commitment->h_commitment.hash,
                                     &calc_hash))
    {
      GNUNET_break_op (0);
      *result = TALER_MHD_reply_with_ec (connection,
                                         TALER_EC_EXCHANGE_AGE_WITHDRAW_REVEAL_INVALID_HASH,
                                         NULL);
      return GNUNET_SYSERR;
    }

  }
  return GNUNET_OK;
}


/**
 * @brief Send a response for "/age-withdraw/$RCH/reveal"
 *
 * @param connection The http connection to the client to send the response to
 * @param commitment The data from the commitment with signatures
 * @return a MHD result code
 */
static MHD_RESULT
reply_age_withdraw_reveal_success (
  struct MHD_Connection *connection,
  const struct TALER_EXCHANGEDB_AgeWithdraw *commitment)
{
  json_t *list = json_array ();
  GNUNET_assert (NULL != list);

  for (unsigned int i = 0; i < commitment->num_coins; i++)
  {
    json_t *obj = GNUNET_JSON_PACK (
      TALER_JSON_pack_blinded_denom_sig (NULL,
                                         &commitment->denom_sigs[i]));
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


MHD_RESULT
TEH_handler_age_withdraw_reveal (
  struct TEH_RequestContext *rc,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  const json_t *root)
{
  MHD_RESULT result = MHD_NO;
  enum GNUNET_GenericReturnValue ret = GNUNET_SYSERR;
  struct AgeRevealContext actx = {0};
  const json_t *j_disclosed_coin_secrets;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &actx.reserve_pub),
    GNUNET_JSON_spec_array_const ("disclosed_coin_secrets",
                                  &j_disclosed_coin_secrets),
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
    if (GNUNET_OK !=
        parse_age_withdraw_reveal_json (
          rc->connection,
          j_disclosed_coin_secrets,
          &actx,
          &result))
      break;

    /* Find original commitment */
    if (GNUNET_OK !=
        find_original_commitment (
          rc->connection,
          &actx.ach,
          &actx.reserve_pub,
          &actx.commitment,
          &result))
      break;

    /* Verify the computed h_commitment equals the committed one and that coins
     * have a maximum age group corresponding max_age (age-mask dependent) */
    if (GNUNET_OK !=
        verify_commitment_and_max_age (
          rc->connection,
          &actx.commitment,
          actx.disclosed_coin_secrets,
          actx.num_coins,
          &result))
      break;

    /* Finally, return the signatures */
    result = reply_age_withdraw_reveal_success (rc->connection,
                                                &actx.commitment);

  } while (0);

  GNUNET_JSON_parse_free (spec);
  if (NULL != actx.commitment.denom_sigs)
    for (unsigned int i = 0; i<actx.num_coins; i++)
      TALER_blinded_denom_sig_free (&actx.commitment.denom_sigs[i]);
  GNUNET_free (actx.commitment.denom_sigs);
  GNUNET_free (actx.commitment.denom_pub_hashes);
  GNUNET_free (actx.commitment.denom_serials);
  GNUNET_free (actx.disclosed_coin_secrets);
  return result;
}


/* end of taler-exchange-httpd_age-withdraw_reveal.c */
