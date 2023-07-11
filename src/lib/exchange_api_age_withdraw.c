/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_age_withdraw.c
 * @brief Implementation of /reserves/$RESERVE_PUB/age-withdraw requests
 * @author Özgür Kesim
 */

#include "platform.h"
#include <gnunet/gnunet_common.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_curl_lib.h"
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"

struct CoinCandidate
{
  /**
   * Master key material for the coin candidates.
   */
  struct TALER_PlanchetMasterSecretP secret;

  /**
   * Age commitment for the coin candidates, calculated from the @e ps and a
   * given maximum age
   */
  struct TALER_AgeCommitmentProof age_commitment_proof;

  /**
   * Age commitment for the coin.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   *  blinding secret
   */
  union TALER_DenominationBlindingKeyP blinding_key;

  /**
   * Private key of the coin we are withdrawing.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Details of the planchet.
   */
  struct TALER_PlanchetDetail planchet_detail;

  /**
   * Values of the @cipher selected
   */
  struct TALER_ExchangeWithdrawValues alg_values;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct TALER_CoinPubHashP h_coin_pub;

  /* Blinded hash of the coin */
  struct TALER_BlindedCoinHashP blinded_coin_h;

  /**
   * The following fields are needed as closure for the call to /csr-withdrwaw
   * per coin-candidate.
   */

  /* Denomination information, needed for CS coins for the step after /csr-withdraw */
  struct TALER_EXCHANGE_DenomPublicKey *denom_pub;

  /**
   * Handler for the CS R request (only used for TALER_DENOMINATION_CS denominations)
   */
  struct TALER_EXCHANGE_CsRWithdrawHandle *csr_withdraw_handle;

  /* Needed in the closure for csr-withdraw calls */
  struct TALER_EXCHANGE_AgeWithdrawHandle *age_withdraw_handle;

};


/**
 * Data we keep per coin in the batch.
 */
struct CoinData
{

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey denom_pub;

  /**
   * The Candidates for the coin
   */
  struct CoinCandidate coin_candidates[TALER_CNC_KAPPA];

};


/**
 * @brief A /reserves/$RESERVE_PUB/age-withdraw request-handle
 */
struct TALER_EXCHANGE_AgeWithdrawHandle
{

  /**
   * Reserve private key.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

  /**
   * Reserve public key, calculated
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Signature of the reserve for the request, calculated after all
   * parameters for the coins are collected.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /*
   * The denomination keys of the exchange
   */
  struct TALER_EXCHANGE_Keys *keys;

  /**
   * The base-URL of the exchange.
   */
  const char *exchange_url;

  /**
   * The age mask, extacted from the denominations.
   * MUST be the same for all denominations
   *
   */
  struct TALER_AgeMask age_mask;

  /**
   * Maximum age to commit to.
   */
  uint8_t max_age;

  /**
   * Length of the @e coin_data Array
   */
  size_t num_coins;

  /**
   * Array of per-coin data
   */
  struct CoinData *coin_data;

  /**
   * The commitment calculated as SHA512 hash over all blinded_coin_h
   */
  struct TALER_AgeWithdrawCommitmentHashP h_commitment;

  /**
   * Total amount requested (value plus withdraw fee).
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Number of /csr-withdraw requests still pending.
   */
  unsigned int csr_pending;

  /**
   * The url for this request.
   */
  char *request_url;

  /**
   * Context for curl.
   */
  struct GNUNET_CURL_Context *curl_ctx;

  /**
   * CURL handle for the request job.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Post Context
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Function to call with age-withdraw response results.
   */
  TALER_EXCHANGE_AgeWithdrawCallback callback;

  /**
   * Closure for @e age_withdraw_cb
   */
  void *callback_cls;

};

/**
 * We got a 200 OK response for the /reserves/$RESERVE_PUB/age-withdraw operation.
 * Extract the noreveal_index and return it to the caller.
 *
 * @param awh operation handle
 * @param j_response reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
reserve_age_withdraw_ok (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh,
  const json_t *j_response)
{
  struct TALER_EXCHANGE_AgeWithdrawResponse response = {
    .hr.reply = j_response,
    .hr.http_status = MHD_HTTP_OK
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint8 ("noreaveal_index",
                            &response.details.ok.noreveal_index),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &response.details.ok.exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &response.details.ok.exchange_pub)
  };

  if (GNUNET_OK!=
      GNUNET_JSON_parse (j_response,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_exchange_online_age_withdraw_confirmation_verify (
        &awh->h_commitment,
        response.details.ok.noreveal_index,
        &response.details.ok.exchange_pub,
        &response.details.ok.exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;

  }
  awh->callback (awh->callback_cls,
                 &response);
  /* make sure the callback isn't called again */
  awh->callback = NULL;

  return GNUNET_OK;
}


/**
 * FIXME: This function should be common to batch- and age-withdraw
 *
 * We got a 409 CONFLICT response for the /reserves/$RESERVE_PUB/age-withdraw operation.
 * Check the signatures on the batch withdraw transactions in the provided
 * history and that the balances add up.  We don't do anything directly
 * with the information, as the JSON will be returned to the application.
 * However, our job is ensuring that the exchange followed the protocol, and
 * this in particular means checking all of the signatures in the history.
 *
 * @param keys The denomination keys from the exchange
 * @param reserve_pub The reserve's public key
 * @param requested_amount The requested amount
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
reserve_age_withdraw_payment_required (
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *requested_amount,
  const json_t *json)
{
  struct TALER_Amount balance;
  struct TALER_Amount total_in_from_history;
  struct TALER_Amount total_out_from_history;
  json_t *history;
  size_t len;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("balance",
                                &balance),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  history = json_object_get (json,
                             "history");
  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* go over transaction history and compute
     total incoming and outgoing amounts */
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_ReserveHistoryEntry *rhistory;

    /* Use heap allocation as "len" may be very big and thus this may
       not fit on the stack. Use "GNUNET_malloc_large" as a malicious
       exchange may theoretically try to crash us by giving a history
       that does not fit into our memory. */
    rhistory = GNUNET_malloc_large (
      sizeof (struct TALER_EXCHANGE_ReserveHistoryEntry)
      * len);
    if (NULL == rhistory)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    if (GNUNET_OK !=
        TALER_EXCHANGE_parse_reserve_history (
          keys,
          history,
          reserve_pub,
          balance.currency,
          &total_in_from_history,
          &total_out_from_history,
          len,
          rhistory))
    {
      GNUNET_break_op (0);
      TALER_EXCHANGE_free_reserve_history (len,
                                           rhistory);
      return GNUNET_SYSERR;
    }
    TALER_EXCHANGE_free_reserve_history (len,
                                         rhistory);
  }

  /* Check that funds were really insufficient */
  if (0 >= TALER_amount_cmp (requested_amount,
                             &balance))
  {
    /* Requested amount is smaller or equal to reported balance,
       so this should not have failed. */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RESERVE_PUB/age-withdraw request.
 *
 * @param cls the `struct TALER_EXCHANGE_AgeWithdrawHandle`
 * @param response_code The HTTP response code
 * @param response response data
 */
static void
handle_reserve_age_withdraw_finished (
  void *cls,
  long response_code,
  const void *response)
{
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh = cls;
  const json_t *j_response = response;
  struct TALER_EXCHANGE_AgeWithdrawResponse awr = {
    .hr.reply = j_response,
    .hr.http_status = (unsigned int) response_code
  };

  awh->job = NULL;
  switch (response_code)
  {
  case 0:
    awr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_age_withdraw_ok (awh,
                                 j_response))
    {
      GNUNET_break_op (0);
      awr.hr.http_status = 0;
      awr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == awh->callback);
    TALER_EXCHANGE_age_withdraw_cancel (awh);
    return;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    /* only validate reply is well-formed */
    {
      uint64_t ptu;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("legitimization_uuid",
                                 &ptu),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j_response,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        awr.hr.http_status = 0;
        awr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break_op (0);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know this reserve.  Can happen if we
       query before the wire transfer went through.
       We should simply pass the JSON reply to the application. */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_CONFLICT:
    /* The exchange says that the reserve has insufficient funds;
       check the signatures in the history... */
    if (GNUNET_OK !=
        reserve_age_withdraw_payment_required (awh->keys,
                                               &awh->reserve_pub,
                                               &awh->amount_with_fee,
                                               j_response))
    {
      GNUNET_break_op (0);
      awr.hr.http_status = 0;
      awr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    else
    {
      awr.hr.ec = TALER_JSON_get_error_code (j_response);
      awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    }
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange age-withdraw\n",
                (unsigned int) response_code,
                (int) awr.hr.ec);
    break;
  }
  awh->callback (awh->callback_cls,
                 &awr);
  TALER_EXCHANGE_age_withdraw_cancel (awh);
}


/**
 * Runs the actual age-withdraw operation. If there were CS-denominations
 * involved, started once the all calls to /csr-withdraw are done.
 *
 * @param[in,out] awh age withdraw handler
 */
static void
perform_protocol (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh)
{
#define FAIL_IF(cond) \
  do { \
    if ((cond)) \
    { \
      GNUNET_break (! (cond)); \
      goto ERROR; \
    } \
  } while(0)

  struct GNUNET_HashContext *coins_hctx;
  json_t *j_denoms = NULL;
  json_t *j_array_candidates = NULL;
  json_t *j_request_body = NULL;
  CURL *curlh = NULL;


  GNUNET_assert (0 == awh->csr_pending);

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Attempting to age-withdraw from reserve %s with maximum age %d\n",
              TALER_B2S (&awh->reserve_pub),
              awh->max_age);

  coins_hctx = GNUNET_CRYPTO_hash_context_start ();
  FAIL_IF (NULL == coins_hctx);


  j_denoms = json_array ();
  j_array_candidates = json_array ();
  FAIL_IF ((NULL == j_denoms) ||
           (NULL == j_array_candidates));

  for (size_t i  = 0; i< awh->num_coins; i++)
  {
    /* Build the denomination array */
    {
      struct TALER_EXCHANGE_DenomPublicKey *denom =
        &awh->coin_data[i].denom_pub;
      json_t *jdenom = GNUNET_JSON_PACK (
        TALER_JSON_pack_denom_pub (NULL,
                                   &denom->key));

      FAIL_IF (NULL == jdenom);
      FAIL_IF (0 < json_array_append_new (j_denoms,
                                          jdenom));

      /* Build the candidate array */
      {
        const struct CoinCandidate *can = awh->coin_data[i].coin_candidates;
        json_t *j_can = json_array ();
        FAIL_IF (NULL == j_can);

        for (size_t k = 0; k < TALER_CNC_KAPPA; k++)
        {
          json_t *jc = GNUNET_JSON_PACK (
            TALER_JSON_pack_blinded_planchet (
              NULL,
              &can->planchet_detail.blinded_planchet));

          FAIL_IF (NULL == jc);
          FAIL_IF (0 < json_array_append_new (j_can,
                                              jc));

          GNUNET_CRYPTO_hash_context_read (coins_hctx,
                                           &can->blinded_coin_h,
                                           sizeof(can->blinded_coin_h));
        }
      }
    }
  }

  /* Sign the request */
  {
    struct TALER_AgeWithdrawCommitmentHashP coins_commitment_h;

    GNUNET_CRYPTO_hash_context_finish (coins_hctx,
                                       &coins_commitment_h.hash);

    TALER_wallet_age_withdraw_sign (&coins_commitment_h,
                                    &awh->amount_with_fee,
                                    &awh->age_mask,
                                    awh->max_age,
                                    awh->reserve_priv,
                                    &awh->reserve_sig);
  }

  /* Initiate the POST-request */
  j_request_body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("denoms_h", j_denoms),
    GNUNET_JSON_pack_array_steal ("blinded_coin_evs", j_array_candidates),
    GNUNET_JSON_pack_uint64 ("max_age", awh->max_age),
    GNUNET_JSON_pack_data_auto ("reserve_sig", &awh->reserve_sig));
  FAIL_IF (NULL == j_request_body);

  curlh = TALER_EXCHANGE_curl_easy_get_ (awh->request_url);
  FAIL_IF (NULL == curlh);
  FAIL_IF (GNUNET_OK !=
           TALER_curl_easy_post (&awh->post_ctx,
                                 curlh,
                                 j_request_body));
  json_decref (j_request_body);
  j_request_body = NULL;

  awh->job = GNUNET_CURL_job_add2 (awh->curl_ctx,
                                   curlh,
                                   awh->post_ctx.headers,
                                   &handle_reserve_age_withdraw_finished,
                                   awh);
  FAIL_IF (NULL == awh->job);

  /* No errors, return */
  return;

ERROR:
  if (NULL != j_denoms)
    json_decref (j_denoms);
  if (NULL != j_array_candidates)
    json_decref (j_array_candidates);
  if (NULL != j_request_body)
    json_decref (j_request_body);
  if (NULL != curlh)
    curl_easy_cleanup (curlh);
  TALER_EXCHANGE_age_withdraw_cancel (awh);
  return;
#undef FAIL_IF
}


/**
 * Prepares the request URL for the age-withdraw request
 *
 * @param awh The handler
 * @param exchange_url The base-URL to the exchange
 */
static
enum GNUNET_GenericReturnValue
prepare_url (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh,
  const char *exchange_url)
{
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
  char *end;

  end = GNUNET_STRINGS_data_to_string (
    &awh->reserve_pub,
    sizeof (awh->reserve_pub),
    pub_str,
    sizeof (pub_str));
  *end = '\0';
  GNUNET_snprintf (arg_str,
                   sizeof (arg_str),
                   "reserves/%s/age-withdraw",
                   pub_str);

  awh->request_url = TALER_url_join (exchange_url,
                                     arg_str,
                                     NULL);
  if (NULL == awh->request_url)
  {
    GNUNET_break (0);
    TALER_EXCHANGE_age_withdraw_cancel (awh);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * @brief Function called when CSR withdraw retrieval is finished
 *
 * @param cls the `struct CoinCandidate *`
 * @param csrr replies from the /csr-withdraw request
 */
static void
csr_withdraw_done (
  void *cls,
  const struct TALER_EXCHANGE_CsRWithdrawResponse *csrr)
{
  struct CoinCandidate *can = cls;
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh = can->age_withdraw_handle;
  struct TALER_EXCHANGE_AgeWithdrawResponse awr = { .hr = csrr->hr };

  can->csr_withdraw_handle = NULL;

  switch (csrr->hr.http_status)
  {
  case MHD_HTTP_OK:
    {
      bool success = true;
      /* Complete the initialization of the coin with CS denomination */
      can->alg_values = csrr->details.ok.alg_values;
      TALER_planchet_setup_coin_priv (&can->secret,
                                      &can->alg_values,
                                      &can->coin_priv);
      TALER_planchet_blinding_secret_create (&can->secret,
                                             &can->alg_values,
                                             &can->blinding_key);
      /* This initializes the 2nd half of the
         can->planchet_detail.blinded_planchet! */
      if (GNUNET_OK !=
          TALER_planchet_prepare (&can->denom_pub->key,
                                  &can->alg_values,
                                  &can->blinding_key,
                                  &can->coin_priv,
                                  &can->h_age_commitment,
                                  &can->h_coin_pub,
                                  &can->planchet_detail))
      {
        GNUNET_break (0);
        success = false;
        TALER_EXCHANGE_age_withdraw_cancel (awh);
      }

      if (GNUNET_OK !=
          TALER_coin_ev_hash (&can->planchet_detail.blinded_planchet,
                              &can->planchet_detail.denom_pub_hash,
                              &can->blinded_coin_h))
      {
        GNUNET_break (0);
        success = false;
        TALER_EXCHANGE_age_withdraw_cancel (awh);
      }

      awh->csr_pending--;

      /* No more pending requests to /csr-withdraw, we can now perform the
       * actual age-withdraw operation */
      if (0 == awh->csr_pending && success)
        perform_protocol (awh);
      return;
    }
  default:
    break;
  }

  awh->callback (awh->callback_cls,
                 &awr);
  TALER_EXCHANGE_age_withdraw_cancel (awh);
}


/**
 * @brief Prepare the coins for the call to age-withdraw and calculates
 * the total amount with fees.
 *
 * For denomination with CS as cipher, initiates the preflight to retrieve the
 * csr-parameter via /csr-withdraw.
 *
 * @param awh The handler to the age-withdraw
 * @param num_coins The number of coins in @e coin_inputs
 * @param coin_inputs The input for the individual coin(-candidates)
 * @return GNUNET_OK on success, GNUNET_SYSERR on failure
 */
static
enum GNUNET_GenericReturnValue
prepare_coins (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh,
  size_t num_coins,
  const struct TALER_EXCHANGE_AgeWithdrawCoinInput coin_inputs[
    static num_coins])
{
#define FAIL_IF(cond) \
  do { \
    if ((cond)) \
    { \
      GNUNET_break (! (cond)); \
      goto ERROR; \
    } \
  } while(0)

  GNUNET_assert (0 < num_coins);
  awh->age_mask = coin_inputs[0].denom_pub->key.age_mask;

  FAIL_IF (GNUNET_OK !=
           TALER_amount_set_zero (awh->keys->currency,
                                  &awh->amount_with_fee));

  awh->coin_data = GNUNET_new_array (awh->num_coins,
                                     struct CoinData);

  for (size_t i = 0; i < num_coins; i++)
  {
    struct CoinData *cd = &awh->coin_data[i];
    const struct TALER_EXCHANGE_AgeWithdrawCoinInput *input = &coin_inputs[i];
    cd->denom_pub = *input->denom_pub;

    /* The mask must be the same for all coins */
    FAIL_IF (awh->age_mask.bits != input->denom_pub->key.age_mask.bits);

    TALER_denom_pub_deep_copy (&cd->denom_pub.key,
                               &input->denom_pub->key);

    /* Accumulate total value with fees */
    {
      struct TALER_Amount coin_total;

      FAIL_IF (0 >
               TALER_amount_add (&coin_total,
                                 &cd->denom_pub.fees.withdraw,
                                 &cd->denom_pub.value));

      FAIL_IF (0 >
               TALER_amount_add (&awh->amount_with_fee,
                                 &awh->amount_with_fee,
                                 &coin_total));
    }

    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      struct CoinCandidate *can = &cd->coin_candidates[k];

      can->secret = input->secret[k];

      /* Derive the age restriction from the given secret and
       * the maximum age */
      FAIL_IF (GNUNET_OK !=
               TALER_age_restriction_from_secret (
                 &can->secret,
                 &input->denom_pub->key.age_mask,
                 awh->max_age,
                 &can->age_commitment_proof));

      TALER_age_commitment_hash (&can->age_commitment_proof.commitment,
                                 &can->h_age_commitment);

      switch (input->denom_pub->key.cipher)
      {
      case TALER_DENOMINATION_RSA:
        {
          can->alg_values.cipher = TALER_DENOMINATION_RSA;
          TALER_planchet_setup_coin_priv (&can->secret,
                                          &can->alg_values,
                                          &can->coin_priv);
          TALER_planchet_blinding_secret_create (&can->secret,
                                                 &can->alg_values,
                                                 &can->blinding_key);
          FAIL_IF (GNUNET_OK !=
                   TALER_planchet_prepare (&cd->denom_pub.key,
                                           &can->alg_values,
                                           &can->blinding_key,
                                           &can->coin_priv,
                                           &can->h_age_commitment,
                                           &can->h_coin_pub,
                                           &can->planchet_detail));
          FAIL_IF (GNUNET_OK !=
                   TALER_coin_ev_hash (&can->planchet_detail.blinded_planchet,
                                       &can->planchet_detail.denom_pub_hash,
                                       &can->blinded_coin_h));
          break;
        }
      case TALER_DENOMINATION_CS:
        {
          /**
           * Save the handler and the denomination for the callback
           * after the call to csr-withdraw */
          can->age_withdraw_handle = awh;
          can->denom_pub = &cd->denom_pub;

          TALER_cs_withdraw_nonce_derive (
            &can->secret,
            &can->planchet_detail
            .blinded_planchet
            .details
            .cs_blinded_planchet
            .nonce);

          /* Note that we only initialize the first half
             of the blinded_planchet here; the other part
             will be done after the /csr-withdraw request! */
          can->planchet_detail.blinded_planchet.cipher = TALER_DENOMINATION_CS;
          can->csr_withdraw_handle =
            TALER_EXCHANGE_csr_withdraw (awh->curl_ctx,
                                         awh->exchange_url,
                                         &cd->denom_pub,
                                         &can->planchet_detail
                                         .blinded_planchet
                                         .details
                                         .cs_blinded_planchet
                                         .nonce,
                                         &csr_withdraw_done,
                                         &can);
          FAIL_IF (NULL == can->csr_withdraw_handle);

          awh->csr_pending++;
          break;
        }
      default:
        FAIL_IF (1);
      }
    }
  }
  return GNUNET_OK;

ERROR:
  TALER_EXCHANGE_age_withdraw_cancel (awh);
  return GNUNET_SYSERR;
#undef FAIL_IF
};

struct TALER_EXCHANGE_AgeWithdrawHandle *
TALER_EXCHANGE_age_withdraw (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  size_t num_coins,
  const struct TALER_EXCHANGE_AgeWithdrawCoinInput coin_inputs[const static
                                                               num_coins],
  uint8_t max_age,
  TALER_EXCHANGE_AgeWithdrawCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh;

  awh = GNUNET_new (struct TALER_EXCHANGE_AgeWithdrawHandle);
  awh->exchange_url = exchange_url;
  awh->keys = TALER_EXCHANGE_keys_incref (keys);
  awh->curl_ctx = curl_ctx;
  awh->reserve_priv = reserve_priv;
  awh->callback = res_cb;
  awh->callback_cls = res_cb_cls;
  awh->num_coins = num_coins;
  awh->max_age = max_age;

  GNUNET_CRYPTO_eddsa_key_get_public (&awh->reserve_priv->eddsa_priv,
                                      &awh->reserve_pub.eddsa_pub);


  if (GNUNET_OK != prepare_url (awh,
                                exchange_url))
    return NULL;

  if (GNUNET_OK != prepare_coins (awh,
                                  num_coins,
                                  coin_inputs))
    return NULL;

  /* If there were no CS denominations, we can now perform the actual
   * age-withdraw protocol.  Otherwise, there are calls to /csr-withdraw
   * in flight and once they finish, the age-withdraw-protocol will be
   * called from within the csr_withdraw_done-function.
   */
  if (0 == awh->csr_pending)
    perform_protocol (awh);

  return awh;
}


void
TALER_EXCHANGE_age_withdraw_cancel (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh)
{
  /* Cleanup coin data */
  for (unsigned int i = 0; i<awh->num_coins; i++)
  {
    struct CoinData *cd = &awh->coin_data[i];

    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      struct CoinCandidate *can = &cd->coin_candidates[k];

      if (NULL != can->csr_withdraw_handle)
      {
        TALER_EXCHANGE_csr_withdraw_cancel (can->csr_withdraw_handle);
        can->csr_withdraw_handle = NULL;
      }
      TALER_blinded_planchet_free (&can->planchet_detail.blinded_planchet);
    }
    TALER_denom_pub_free (&cd->denom_pub.key);
  }
  GNUNET_free (awh->coin_data);

  /* Cleanup CURL job data */
  if (NULL != awh->job)
  {
    GNUNET_CURL_job_cancel (awh->job);
    awh->job = NULL;
  }
  TALER_curl_easy_post_finished (&awh->post_ctx);
  TALER_EXCHANGE_keys_decref (awh->keys);
  GNUNET_free (awh->request_url);
  GNUNET_free (awh);

}


/* exchange_api_age_withdraw.c */
