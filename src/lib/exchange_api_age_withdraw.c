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
#include <sys/wait.h>
#include "taler_curl_lib.h"
#include "taler_error_codes.h"
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"
#include "taler_util.h"

/**
 * A CoinCandidate is populated from a master secret
 */
struct CoinCandidate
{
  /**
   * Master key material for the coin candidates.
   */
  struct TALER_PlanchetMasterSecretP secret;

  /**
   * The details derived form the master secrets
   */
  struct TALER_EXCHANGE_AgeWithdrawCoinPrivateDetails details;

  /**
   * Blinded hash of the coin
   **/
  struct TALER_BlindedCoinHashP blinded_coin_h;

};


/**
 * Closure for a call to /csr-withdraw, contains data that is needed to process
 * the result.
 */
struct CSRClosure
{
  /**
   * Points to the actual candidate in CoinData.coin_candidates, to continue
   * to build its contents based on the results from /csr-withdraw
   */
  struct CoinCandidate *candidate;

  /**
   * The planchet to finally generate.  Points to the corresponding candidate
   * in CoindData.planchet_details
   */
  struct TALER_PlanchetDetail *planchet;

  /**
   * Handler to the originating call to /age-withdraw, needed to either
   * cancel the running age-withdraw request (on failure of the current call
   * to /csr-withdraw), or to eventually perform the protocol, once all
   * csr-withdraw requests have successfully finished.
   */
  struct TALER_EXCHANGE_AgeWithdrawHandle *age_withdraw_handle;

  /**
   * Session nonce.
   */
  union GNUNET_CRYPTO_BlindSessionNonce nonce;

  /**
   * Denomination information, needed for CS coins for the
   * step after /csr-withdraw
   */
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;

  /**
   * Handler for the CS R request
   */
  struct TALER_EXCHANGE_CsRWithdrawHandle *csr_withdraw_handle;
};

/**
 * Data we keep per coin in the batch.
 */
struct CoinData
{
  /**
   * The denomination of the coin.  Must support age restriction, i.e
   * its .keys.age_mask MUST not be 0
   */
  struct TALER_EXCHANGE_DenomPublicKey denom_pub;

  /**
   * The Candidates for the coin
   */
  struct CoinCandidate coin_candidates[TALER_CNC_KAPPA];

  /**
   * Details of the planchet(s).
   */
  struct TALER_PlanchetDetail planchet_details[TALER_CNC_KAPPA];

  /**
   * Closure for each candidate of type CS for the preflight request to
   * /csr-withdraw
   */
  struct CSRClosure csr_cls[TALER_CNC_KAPPA];
};

/**
 * A /reserves/$RESERVE_PUB/age-withdraw request-handle for calls with
 * pre-blinded planchets.  Returned by TALER_EXCHANGE_age_withdraw_blinded.
 */
struct TALER_EXCHANGE_AgeWithdrawBlindedHandle
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
   * The age mask, extracted from the denominations.
   * MUST be the same for all denominations
   *
   */
  struct TALER_AgeMask age_mask;

  /**
   * Maximum age to commit to.
   */
  uint8_t max_age;

  /**
   * The commitment calculated as SHA512 hash over all blinded_coin_h
   */
  struct TALER_AgeWithdrawCommitmentHashP h_commitment;

  /**
   * Total amount requested (value plus withdraw fee).
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Length of the @e blinded_input Array
   */
  size_t num_input;

  /**
   * The blinded planchet input for the call to /age-withdraw via
   * TALER_EXCHANGE_age_withdraw_blinded
   */
  const struct TALER_EXCHANGE_AgeWithdrawBlindedInput *blinded_input;

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
  TALER_EXCHANGE_AgeWithdrawBlindedCallback callback;

  /**
   * Closure for @e blinded_callback
   */
  void *callback_cls;
};

/**
 * A /reserves/$RESERVE_PUB/age-withdraw request-handle for calls from
 * a wallet, i. e. when blinding data is available.
 */
struct TALER_EXCHANGE_AgeWithdrawHandle
{

  /**
   * Length of the @e coin_data Array
   */
  size_t num_coins;

  /**
   * The base-URL of the exchange.
   */
  const char *exchange_url;

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
   * The age mask, extracted from the denominations.
   * MUST be the same for all denominations
   *
   */
  struct TALER_AgeMask age_mask;

  /**
   * Maximum age to commit to.
   */
  uint8_t max_age;

  /**
   * Array of per-coin data
   */
  struct CoinData *coin_data;

  /**
   * Context for curl.
   */
  struct GNUNET_CURL_Context *curl_ctx;

  struct
  {
    /**
     * Number of /csr-withdraw requests still pending.
     */
    unsigned int pending;

    /**
     * CURL handle for the request job.
     */
    struct GNUNET_CURL_Job *job;
  } csr;


  /**
   * Function to call with age-withdraw response results.
   */
  TALER_EXCHANGE_AgeWithdrawCallback callback;

  /**
   * Closure for @e age_withdraw_cb
   */
  void *callback_cls;

  /* The Handler for the actual call to the exchange */
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *procotol_handle;
};

/**
 * We got a 200 OK response for the /reserves/$RESERVE_PUB/age-withdraw operation.
 * Extract the noreveal_index and return it to the caller.
 *
 * @param awbh operation handle
 * @param j_response reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
reserve_age_withdraw_ok (
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *awbh,
  const json_t *j_response)
{
  struct TALER_EXCHANGE_AgeWithdrawBlindedResponse response = {
    .hr.reply = j_response,
    .hr.http_status = MHD_HTTP_OK,
    .details.ok.h_commitment = awbh->h_commitment
  };
  struct TALER_ExchangeSignatureP exchange_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint8 ("noreveal_index",
                            &response.details.ok.noreveal_index),
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 &response.details.ok.exchange_pub),
    GNUNET_JSON_spec_end ()
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
        &awbh->h_commitment,
        response.details.ok.noreveal_index,
        &response.details.ok.exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;

  }

  awbh->callback (awbh->callback_cls,
                  &response);
  /* make sure the callback isn't called again */
  awbh->callback = NULL;

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
handle_reserve_age_withdraw_blinded_finished (
  void *cls,
  long response_code,
  const void *response)
{
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *awbh = cls;
  const json_t *j_response = response;
  struct TALER_EXCHANGE_AgeWithdrawBlindedResponse awbr = {
    .hr.reply = j_response,
    .hr.http_status = (unsigned int) response_code
  };

  awbh->job = NULL;
  switch (response_code)
  {
  case 0:
    awbr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_age_withdraw_ok (awbh,
                                 j_response))
    {
      GNUNET_break_op (0);
      awbr.hr.http_status = 0;
      awbr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == awbh->callback);
    TALER_EXCHANGE_age_withdraw_blinded_cancel (awbh);
    return;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break_op (0);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know this reserve.  Can happen if we
       query before the wire transfer went through.
       We should simply pass the JSON reply to the application. */
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_CONFLICT:
    /* The age requirements might not have been met */
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    /* only validate reply is well-formed */
    {
      uint64_t ptu;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("requirement_row",
                                 &ptu),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j_response,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        awbr.hr.http_status = 0;
        awbr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    awbr.hr.ec = TALER_JSON_get_error_code (j_response);
    awbr.hr.hint = TALER_JSON_get_error_hint (j_response);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange age-withdraw\n",
                (unsigned int) response_code,
                (int) awbr.hr.ec);
    break;
  }
  awbh->callback (awbh->callback_cls,
                  &awbr);
  TALER_EXCHANGE_age_withdraw_blinded_cancel (awbh);
}


/**
 * Runs the actual age-withdraw operation with the blinded planchets.
 *
 * @param[in,out] awbh age withdraw handler
 */
static void
perform_protocol (
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *awbh)
{
#define FAIL_IF(cond) \
        do { \
          if ((cond)) \
          { \
            GNUNET_break (! (cond)); \
            goto ERROR; \
          } \
        } while (0)

  struct GNUNET_HashContext *coins_hctx = NULL;
  json_t *j_denoms = NULL;
  json_t *j_array_candidates = NULL;
  json_t *j_request_body = NULL;
  CURL *curlh = NULL;

  GNUNET_assert (0 < awbh->num_input);
  awbh->age_mask = awbh->blinded_input[0].denom_pub->key.age_mask;

  FAIL_IF (GNUNET_OK !=
           TALER_amount_set_zero (awbh->keys->currency,
                                  &awbh->amount_with_fee));
  /* Accumulate total value with fees */
  for (size_t i = 0; i < awbh->num_input; i++)
  {
    struct TALER_Amount coin_total;
    const struct TALER_EXCHANGE_DenomPublicKey *dpub =
      awbh->blinded_input[i].denom_pub;

    FAIL_IF (0 >
             TALER_amount_add (&coin_total,
                               &dpub->fees.withdraw,
                               &dpub->value));
    FAIL_IF (0 >
             TALER_amount_add (&awbh->amount_with_fee,
                               &awbh->amount_with_fee,
                               &coin_total));
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Attempting to age-withdraw from reserve %s with maximum age %d\n",
              TALER_B2S (&awbh->reserve_pub),
              awbh->max_age);

  coins_hctx = GNUNET_CRYPTO_hash_context_start ();
  FAIL_IF (NULL == coins_hctx);


  j_denoms = json_array ();
  j_array_candidates = json_array ();
  FAIL_IF ((NULL == j_denoms) ||
           (NULL == j_array_candidates));

  for (size_t i  = 0; i< awbh->num_input; i++)
  {
    /* Build the denomination array */
    {
      const struct TALER_EXCHANGE_DenomPublicKey *denom_pub =
        awbh->blinded_input[i].denom_pub;
      const struct TALER_DenominationHashP *denom_h = &denom_pub->h_key;
      json_t *jdenom;

      /* The mask must be the same for all coins */
      FAIL_IF (awbh->age_mask.bits != denom_pub->key.age_mask.bits);

      jdenom = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto (NULL,
                                    denom_h));
      FAIL_IF (NULL == jdenom);
      FAIL_IF (0 > json_array_append_new (j_denoms,
                                          jdenom));

      /* Build the candidate array */
      {
        json_t *j_can = json_array ();
        FAIL_IF (NULL == j_can);

        for (size_t k = 0; k < TALER_CNC_KAPPA; k++)
        {
          struct TALER_BlindedCoinHashP bch;
          const struct TALER_PlanchetDetail *planchet =
            &awbh->blinded_input[i].planchet_details[k];
          json_t *jc = GNUNET_JSON_PACK (
            TALER_JSON_pack_blinded_planchet (
              NULL,
              &planchet->blinded_planchet));

          FAIL_IF (NULL == jc);
          FAIL_IF (0 > json_array_append_new (j_can,
                                              jc));

          TALER_coin_ev_hash (&planchet->blinded_planchet,
                              &planchet->denom_pub_hash,
                              &bch);

          GNUNET_CRYPTO_hash_context_read (coins_hctx,
                                           &bch,
                                           sizeof(bch));
        }

        FAIL_IF (0 > json_array_append_new (j_array_candidates,
                                            j_can));
      }
    }
  }

  /* Build the hash of the commitment */
  GNUNET_CRYPTO_hash_context_finish (coins_hctx,
                                     &awbh->h_commitment.hash);
  coins_hctx = NULL;

  /* Sign the request */
  TALER_wallet_age_withdraw_sign (&awbh->h_commitment,
                                  &awbh->amount_with_fee,
                                  &awbh->age_mask,
                                  awbh->max_age,
                                  awbh->reserve_priv,
                                  &awbh->reserve_sig);

  /* Initiate the POST-request */
  j_request_body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("denom_hs", j_denoms),
    GNUNET_JSON_pack_array_steal ("blinded_coin_evs", j_array_candidates),
    GNUNET_JSON_pack_uint64 ("max_age", awbh->max_age),
    GNUNET_JSON_pack_data_auto ("reserve_sig", &awbh->reserve_sig));
  FAIL_IF (NULL == j_request_body);

  curlh = TALER_EXCHANGE_curl_easy_get_ (awbh->request_url);
  FAIL_IF (NULL == curlh);
  FAIL_IF (GNUNET_OK !=
           TALER_curl_easy_post (&awbh->post_ctx,
                                 curlh,
                                 j_request_body));
  json_decref (j_request_body);
  j_request_body = NULL;

  awbh->job = GNUNET_CURL_job_add2 (
    awbh->curl_ctx,
    curlh,
    awbh->post_ctx.headers,
    &handle_reserve_age_withdraw_blinded_finished,
    awbh);
  FAIL_IF (NULL == awbh->job);

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
  if (NULL != coins_hctx)
    GNUNET_CRYPTO_hash_context_abort (coins_hctx);
  TALER_EXCHANGE_age_withdraw_blinded_cancel (awbh);
  return;
#undef FAIL_IF
}


/**
 * @brief Callback to copy the results from the call to TALER_age_withdraw_blinded
 * to the result for the originating call from TALER_age_withdraw.
 *
 * @param cls struct TALER_AgeWithdrawHandle
 * @param awbr The response
 */
static void
copy_results (
  void *cls,
  const struct TALER_EXCHANGE_AgeWithdrawBlindedResponse *awbr)
{
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh = cls;
  uint8_t k =  awbr->details.ok.noreveal_index;
  struct TALER_EXCHANGE_AgeWithdrawCoinPrivateDetails details[awh->num_coins];
  struct TALER_BlindedCoinHashP blinded_coin_hs[awh->num_coins];
  struct TALER_EXCHANGE_AgeWithdrawResponse resp = {
    .hr = awbr->hr,
    .details = {
      .ok = {
        .noreveal_index = awbr->details.ok.noreveal_index,
        .h_commitment = awbr->details.ok.h_commitment,
        .exchange_pub = awbr->details.ok.exchange_pub,
        .num_coins = awh->num_coins,
        .coin_details = details,
        .blinded_coin_hs = blinded_coin_hs
      },
    },
  };

  for (size_t n = 0; n< awh->num_coins; n++)
  {
    details[n] = awh->coin_data[n].coin_candidates[k].details;
    details[n].planchet = awh->coin_data[n].planchet_details[k];
    blinded_coin_hs[n] = awh->coin_data[n].coin_candidates[k].blinded_coin_h;
  }
  awh->callback (awh->callback_cls,
                 &resp);
  awh->callback = NULL;
}


/**
 * @brief Prepares and executes TALER_EXCHANGE_age_withdraw_blinded.
 * If there were CS-denominations involved, started once the all calls
 * to /csr-withdraw are done.
 */
static void
call_age_withdraw_blinded (
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh)
{
  struct TALER_EXCHANGE_AgeWithdrawBlindedInput blinded_input[awh->num_coins];

  /* Prepare the blinded planchets as input */
  for (size_t n = 0; n < awh->num_coins; n++)
  {
    blinded_input[n].denom_pub = &awh->coin_data[n].denom_pub;
    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
      blinded_input[n].planchet_details[k] =
        awh->coin_data[n].planchet_details[k];
  }

  awh->procotol_handle =
    TALER_EXCHANGE_age_withdraw_blinded (
      awh->curl_ctx,
      awh->keys,
      awh->exchange_url,
      awh->reserve_priv,
      awh->max_age,
      awh->num_coins,
      blinded_input,
      copy_results,
      awh);
}


/**
 * Prepares the request URL for the age-withdraw request
 *
 * @param awbh The handler
 * @param exchange_url The base-URL to the exchange
 */
static
enum GNUNET_GenericReturnValue
prepare_url (
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *awbh,
  const char *exchange_url)
{
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
  char *end;

  end = GNUNET_STRINGS_data_to_string (
    &awbh->reserve_pub,
    sizeof (awbh->reserve_pub),
    pub_str,
    sizeof (pub_str));
  *end = '\0';
  GNUNET_snprintf (arg_str,
                   sizeof (arg_str),
                   "reserves/%s/age-withdraw",
                   pub_str);

  awbh->request_url = TALER_url_join (exchange_url,
                                      arg_str,
                                      NULL);
  if (NULL == awbh->request_url)
  {
    GNUNET_break (0);
    TALER_EXCHANGE_age_withdraw_blinded_cancel (awbh);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * @brief Function called when CSR withdraw retrieval is finished
 *
 * @param cls the `struct CSRClosure *`
 * @param csrr replies from the /csr-withdraw request
 */
static void
csr_withdraw_done (
  void *cls,
  const struct TALER_EXCHANGE_CsRWithdrawResponse *csrr)
{
  struct CSRClosure *csr = cls;
  struct CoinCandidate *can;
  struct TALER_PlanchetDetail *planchet;
  struct TALER_EXCHANGE_AgeWithdrawHandle *awh;

  GNUNET_assert (NULL != csr);
  awh = csr->age_withdraw_handle;
  planchet = csr->planchet;
  can = csr->candidate;

  GNUNET_assert (NULL != can);
  GNUNET_assert (NULL != planchet);
  GNUNET_assert (NULL != awh);

  csr->csr_withdraw_handle = NULL;

  switch (csrr->hr.http_status)
  {
  case MHD_HTTP_OK:
    {
      bool success = false;
      /* Complete the initialization of the coin with CS denomination */

      TALER_denom_ewv_deep_copy (&can->details.alg_values,
                                 &csrr->details.ok.alg_values);
      GNUNET_assert (can->details.alg_values.blinding_inputs->cipher
                     == GNUNET_CRYPTO_BSA_CS);
      TALER_planchet_setup_coin_priv (&can->secret,
                                      &can->details.alg_values,
                                      &can->details.coin_priv);
      TALER_planchet_blinding_secret_create (&can->secret,
                                             &can->details.alg_values,
                                             &can->details.blinding_key);
      /* This initializes the 2nd half of the
         can->planchet_detail.blinded_planchet! */
      do {
        if (GNUNET_OK !=
            TALER_planchet_prepare (&csr->denom_pub->key,
                                    &can->details.alg_values,
                                    &can->details.blinding_key,
                                    &csr->nonce,
                                    &can->details.coin_priv,
                                    &can->details.h_age_commitment,
                                    &can->details.h_coin_pub,
                                    planchet))
        {
          GNUNET_break (0);
          break;
        }

        TALER_coin_ev_hash (&planchet->blinded_planchet,
                            &planchet->denom_pub_hash,
                            &can->blinded_coin_h);
        success = true;
      } while (0);

      awh->csr.pending--;

      /* No more pending requests to /csr-withdraw, we can now perform the
       * actual age-withdraw operation */
      if (0 == awh->csr.pending && success)
        call_age_withdraw_blinded (awh);
      return;
    }
  default:
    break;
  }
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
        } while (0)

  GNUNET_assert (0 < num_coins);
  awh->age_mask = coin_inputs[0].denom_pub->key.age_mask;

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

    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      struct CoinCandidate *can = &cd->coin_candidates[k];
      struct TALER_PlanchetDetail *planchet = &cd->planchet_details[k];

      can->secret = input->secrets[k];
      /* Derive the age restriction from the given secret and
       * the maximum age */
      TALER_age_restriction_from_secret (
        &can->secret,
        &input->denom_pub->key.age_mask,
        awh->max_age,
        &can->details.age_commitment_proof);

      TALER_age_commitment_hash (&can->details.age_commitment_proof.commitment,
                                 &can->details.h_age_commitment);

      switch (input->denom_pub->key.bsign_pub_key->cipher)
      {
      case GNUNET_CRYPTO_BSA_RSA:
        TALER_denom_ewv_deep_copy (&can->details.alg_values,
                                   TALER_denom_ewv_rsa_singleton ());
        TALER_planchet_setup_coin_priv (&can->secret,
                                        &can->details.alg_values,
                                        &can->details.coin_priv);
        TALER_planchet_blinding_secret_create (&can->secret,
                                               &can->details.alg_values,
                                               &can->details.blinding_key);
        FAIL_IF (GNUNET_OK !=
                 TALER_planchet_prepare (&cd->denom_pub.key,
                                         &can->details.alg_values,
                                         &can->details.blinding_key,
                                         NULL,
                                         &can->details.coin_priv,
                                         &can->details.h_age_commitment,
                                         &can->details.h_coin_pub,
                                         planchet));
        TALER_coin_ev_hash (&planchet->blinded_planchet,
                            &planchet->denom_pub_hash,
                            &can->blinded_coin_h);
        break;
      case GNUNET_CRYPTO_BSA_CS:
        {
          struct CSRClosure *cls = &cd->csr_cls[k];
          /**
           * Save the handler and the denomination for the callback
           * after the call to csr-withdraw */
          cls->age_withdraw_handle = awh;
          cls->candidate = can;
          cls->planchet = planchet;
          cls->denom_pub = &cd->denom_pub;
          TALER_cs_withdraw_nonce_derive (
            &can->secret,
            &cls->nonce.cs_nonce);
          cls->csr_withdraw_handle =
            TALER_EXCHANGE_csr_withdraw (
              awh->curl_ctx,
              awh->exchange_url,
              &cd->denom_pub,
              &cls->nonce.cs_nonce,
              &csr_withdraw_done,
              cls);
          FAIL_IF (NULL == cls->csr_withdraw_handle);

          awh->csr.pending++;
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
  struct TALER_EXCHANGE_Keys *keys,
  const char *exchange_url,
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


  if (GNUNET_OK != prepare_coins (awh,
                                  num_coins,
                                  coin_inputs))
  {
    GNUNET_free (awh);
    return NULL;
  }

  /* If there were no CS denominations, we can now perform the actual
   * age-withdraw protocol.  Otherwise, there are calls to /csr-withdraw
   * in flight and once they finish, the age-withdraw-protocol will be
   * called from within the csr_withdraw_done-function.
   */
  if (0 == awh->csr.pending)
    call_age_withdraw_blinded (awh);

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
      struct TALER_PlanchetDetail *planchet = &cd->planchet_details[k];
      struct CSRClosure *cls = &cd->csr_cls[k];
      struct CoinCandidate *can = &cd->coin_candidates[k];

      if (NULL != cls->csr_withdraw_handle)
      {
        TALER_EXCHANGE_csr_withdraw_cancel (cls->csr_withdraw_handle);
        cls->csr_withdraw_handle = NULL;
      }
      TALER_blinded_planchet_free (&planchet->blinded_planchet);
      TALER_denom_ewv_free (&can->details.alg_values);
    }
    TALER_denom_pub_free (&cd->denom_pub.key);
  }
  GNUNET_free (awh->coin_data);
  TALER_EXCHANGE_keys_decref (awh->keys);
  TALER_EXCHANGE_age_withdraw_blinded_cancel (awh->procotol_handle);
  awh->procotol_handle = NULL;
  GNUNET_free (awh);
}


struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *
TALER_EXCHANGE_age_withdraw_blinded (
  struct GNUNET_CURL_Context *curl_ctx,
  struct TALER_EXCHANGE_Keys *keys,
  const char *exchange_url,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  uint8_t max_age,
  unsigned int num_input,
  const struct TALER_EXCHANGE_AgeWithdrawBlindedInput blinded_input[static
                                                                    num_input],
  TALER_EXCHANGE_AgeWithdrawBlindedCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *awbh =
    GNUNET_new (struct TALER_EXCHANGE_AgeWithdrawBlindedHandle);

  awbh->num_input = num_input;
  awbh->blinded_input = blinded_input;
  awbh->keys = TALER_EXCHANGE_keys_incref (keys);
  awbh->curl_ctx = curl_ctx;
  awbh->reserve_priv = reserve_priv;
  awbh->callback = res_cb;
  awbh->callback_cls = res_cb_cls;
  awbh->max_age = max_age;

  GNUNET_CRYPTO_eddsa_key_get_public (&awbh->reserve_priv->eddsa_priv,
                                      &awbh->reserve_pub.eddsa_pub);

  if (GNUNET_OK != prepare_url (awbh,
                                exchange_url))
    return NULL;

  perform_protocol (awbh);
  return awbh;
}


void
TALER_EXCHANGE_age_withdraw_blinded_cancel (
  struct TALER_EXCHANGE_AgeWithdrawBlindedHandle *awbh)
{
  if (NULL == awbh)
    return;

  if (NULL != awbh->job)
  {
    GNUNET_CURL_job_cancel (awbh->job);
    awbh->job = NULL;
  }
  GNUNET_free (awbh->request_url);
  TALER_EXCHANGE_keys_decref (awbh->keys);
  TALER_curl_easy_post_finished (&awbh->post_ctx);
  GNUNET_free (awbh);
}


/* exchange_api_age_withdraw.c */
