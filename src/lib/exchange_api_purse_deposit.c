/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

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
 * @file lib/exchange_api_purse_deposit.c
 * @brief Implementation of the client to create a purse with
 *        an initial set of deposits (and a contract)
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * Information we track per coin.
 */
struct Coin
{
  /**
   * Coin's public key.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Coin's denomination.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * How much did we say the coin contributed.
   */
  struct TALER_Amount contribution;
};


/**
 * @brief A purse create with deposit handle
 */
struct TALER_EXCHANGE_PurseDepositHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * The base url of the exchange we are talking to.
   */
  char *base_url;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_PurseDepositCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Public key of the purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Array of @e num_deposits coins we are depositing.
   */
  struct Coin *coins;

  /**
   * Number of coins we are depositing.
   */
  unsigned int num_deposits;
};


/**
 * Function called when we're done processing the
 * HTTP /purses/$PID/deposit request.
 *
 * @param cls the `struct TALER_EXCHANGE_PurseDepositHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_purse_deposit_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_EXCHANGE_PurseDepositHandle *pch = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_PurseDepositResponse dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };
  const struct TALER_EXCHANGE_Keys *keys;

  pch->job = NULL;
  keys = TALER_EXCHANGE_get_keys (pch->exchange);
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_TIME_Timestamp etime;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &dr.details.success.h_contract_terms),
        GNUNET_JSON_spec_timestamp ("exchange_timestamp",
                                    &etime),
        GNUNET_JSON_spec_timestamp ("purse_expiration",
                                    &dr.details.success.purse_expiration),
        TALER_JSON_spec_amount ("total_deposited",
                                keys->currency,
                                &dr.details.success.total_deposited),
        TALER_JSON_spec_amount ("purse_value_after_fees",
                                keys->currency,
                                &dr.details.success.purse_value_after_fees),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (keys,
                                           &exchange_pub))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_PURSE_DEPOSIT_EXCHANGE_SIGNATURE_INVALID;
        break;
      }
      if (GNUNET_OK !=
          TALER_exchange_online_purse_created_verify (
            etime,
            dr.details.success.purse_expiration,
            &dr.details.success.purse_value_after_fees,
            &dr.details.success.total_deposited,
            &pch->purse_pub,
            &dr.details.success.h_contract_terms,
            &exchange_pub,
            &exchange_sig))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_PURSE_DEPOSIT_EXCHANGE_SIGNATURE_INVALID;
        break;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    switch (dr.hr.ec)
    {
    case TALER_EC_EXCHANGE_PURSE_DEPOSIT_CONFLICTING_META_DATA:
      {
        const char *partner_url = NULL;
        struct TALER_CoinSpendPublicKeyP coin_pub;
        struct TALER_CoinSpendSignatureP coin_sig;
        struct TALER_Amount amount;
        struct GNUNET_JSON_Specification spec[] = {
          GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                       &coin_sig),
          GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                       &coin_pub),
          GNUNET_JSON_spec_mark_optional (
            GNUNET_JSON_spec_string ("partner_url",
                                     &partner_url),
            NULL),
          TALER_JSON_spec_amount ("amount",
                                  keys->currency,
                                  &amount),
          GNUNET_JSON_spec_end ()
        };
        bool found = false;

        if (GNUNET_OK !=
            GNUNET_JSON_parse (j,
                               spec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        for (unsigned int i = 0; i<pch->num_deposits; i++)
          if (0 == GNUNET_memcmp (&coin_pub,
                                  &pch->coins[i].coin_pub))
          {
            found = true;
            break;
          }
        if (! found)
        {
          /* proof is about a coin we did not even deposit */
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        if (NULL == partner_url)
          partner_url = pch->base_url;
        if (GNUNET_OK !=
            TALER_wallet_purse_deposit_verify (
              partner_url,
              &pch->purse_pub,
              &amount,
              &coin_pub,
              &coin_sig))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        /* meta data conflict is real! */
        break;
      }
    case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
      {
        json_t *history;
        struct TALER_Amount total;
        struct TALER_DenominationHashP h_denom_pub;
        const struct TALER_EXCHANGE_DenomPublicKey *dki;
        struct TALER_CoinSpendPublicKeyP coin_pub;
        struct GNUNET_JSON_Specification spec[] = {
          GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                       &coin_pub),
          GNUNET_JSON_spec_json ("history",
                                 &history),
          GNUNET_JSON_spec_end ()
        };
        bool found = false;
        const struct Coin *my_coin;

        if (GNUNET_OK !=
            GNUNET_JSON_parse (j,
                               spec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        for (unsigned int i = 0; i<pch->num_deposits; i++)
        {
          if (0 == GNUNET_memcmp (&coin_pub,
                                  &pch->coins[i].coin_pub))
          {
            found = true;
            my_coin = &pch->coins[i];
            break;
          }
        }
        if (! found)
        {
          /* proof is about a coin we did not even deposit */
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (
          keys,
          &my_coin->h_denom_pub);
        if (NULL == dki)
        {
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
          GNUNET_break_op (0);
          break;
        }
        if (GNUNET_OK !=
            TALER_EXCHANGE_verify_coin_history (dki,
                                                dki->value.currency,
                                                &coin_pub,
                                                history,
                                                &h_denom_pub,
                                                &total))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          json_decref (history);
          break;
        }
        json_decref (history);
        if (0 >
            TALER_amount_add (&total,
                              &total,
                              &my_coin->contribution))
        {
          /* clearly not OK if our transaction would have caused
             the overflow... */
          break;
        }
        if (0 >= TALER_amount_cmp (&total,
                                   &dki->value))
        {
          /* transaction should have still fit */
          GNUNET_break (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        /* everything OK, proof of double-spending was provided */
        break;
      }
    case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
      {
        json_t *history;
        struct TALER_Amount total;
        struct TALER_DenominationHashP h_denom_pub;
        const struct Coin *my_coin;
        const struct TALER_EXCHANGE_DenomPublicKey *dki;
        struct TALER_CoinSpendPublicKeyP coin_pub;
        struct GNUNET_JSON_Specification spec[] = {
          GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                       &coin_pub),
          GNUNET_JSON_spec_json ("history",
                                 &history),
          GNUNET_JSON_spec_end ()
        };
        bool found = false;

        if (GNUNET_OK !=
            GNUNET_JSON_parse (j,
                               spec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        for (unsigned int i = 0; i<pch->num_deposits; i++)
        {
          if (0 == GNUNET_memcmp (&coin_pub,
                                  &pch->coins[i].coin_pub))
          {
            found = true;
            my_coin = &pch->coins[i];
            break;
          }
        }
        if (! found)
        {
          /* proof is about a coin we did not even deposit */
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (
          keys,
          &my_coin->h_denom_pub);
        memset (&h_denom_pub,
                0,
                sizeof (h_denom_pub));
        if (GNUNET_OK !=
            TALER_EXCHANGE_verify_coin_history (dki,
                                                dki->value.currency,
                                                &coin_pub,
                                                history,
                                                &h_denom_pub,
                                                &total))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          json_decref (history);
          break;
        }
        json_decref (history);
        if (0 == GNUNET_memcmp (&dki->h_key,
                                &h_denom_pub))
        {
          /* sorry, this proves nothing */
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        /* everything OK, proof of conflicting denomination was provided */
        break;
      }
    default:
      GNUNET_break_op (0);
      dr.hr.http_status = 0;
      dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    } /* ec switch */
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange deposit\n",
                (unsigned int) response_code,
                dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  if (TALER_EC_NONE == dr.hr.ec)
    dr.hr.hint = NULL;
  else
    dr.hr.hint = TALER_ErrorCode_get_hint (dr.hr.ec);
  pch->cb (pch->cb_cls,
           &dr);
  TALER_EXCHANGE_purse_deposit_cancel (pch);
}


struct TALER_EXCHANGE_PurseDepositHandle *
TALER_EXCHANGE_purse_deposit (
  struct TALER_EXCHANGE_Handle *exchange,
  const char *purse_exchange_url,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  uint8_t min_age,
  unsigned int num_deposits,
  const struct TALER_EXCHANGE_PurseDeposit *deposits,
  TALER_EXCHANGE_PurseDepositCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_PurseDepositHandle *pch;
  struct GNUNET_CURL_Context *ctx;
  json_t *create_obj;
  json_t *deposit_arr;
  CURL *eh;
  char arg_str[sizeof (pch->purse_pub) * 2 + 32];

  if (0 == num_deposits)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  pch = GNUNET_new (struct TALER_EXCHANGE_PurseDepositHandle);
  pch->purse_pub = *purse_pub;
  pch->exchange = exchange;
  pch->cb = cb;
  pch->cb_cls = cb_cls;
  {
    char pub_str[sizeof (pch->purse_pub) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &pch->purse_pub,
      sizeof (pch->purse_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/purses/%s/deposit",
                     pub_str);
  }
  pch->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == pch->url)
  {
    GNUNET_break (0);
    GNUNET_free (pch);
    return NULL;
  }
  deposit_arr = json_array ();
  GNUNET_assert (NULL != deposit_arr);
  pch->base_url = TEAH_path_to_url (exchange,
                                    "/");
  pch->num_deposits = num_deposits;
  pch->coins = GNUNET_new_array (num_deposits,
                                 struct Coin);
  for (unsigned int i = 0; i<num_deposits; i++)
  {
    const struct TALER_EXCHANGE_PurseDeposit *deposit = &deposits[i];
    struct Coin *coin = &pch->coins[i];
    json_t *jdeposit;
    struct TALER_CoinSpendSignatureP coin_sig;
#if FIXME_OEC
    struct TALER_AgeCommitmentHash agh;
    struct TALER_AgeCommitmentHash *aghp = NULL;
    struct TALER_AgeAttestation attest;

    TALER_age_commitment_hash (&deposit->age_commitment,
                               &agh);
    aghp = &agh;
    if (GNUNET_OK !=
        TALER_age_commitment_attest (&deposit->age_proof,
                                     min_age,
                                     &attest))
    {
      GNUNET_break (0);
      json_decref (deposit_arr);
      GNUNET_free (pch->base_url);
      GNUNET_free (pch->coins);
      GNUNET_free (pch);
      return NULL;
    }
#endif
    GNUNET_CRYPTO_eddsa_key_get_public (&deposit->coin_priv.eddsa_priv,
                                        &coin->coin_pub.eddsa_pub);
    coin->h_denom_pub = deposit->h_denom_pub;
    coin->contribution = deposit->amount;
    TALER_wallet_purse_deposit_sign (
      pch->base_url,
      &pch->purse_pub,
      &deposit->amount,
      &deposit->coin_priv,
      &coin_sig);
    jdeposit = GNUNET_JSON_PACK (
#if FIXME_OEC
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                    aghp)),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_data_auto ("age_attestation",
                                    &attest)),
#endif
      TALER_JSON_pack_amount ("amount",
                              &deposit->amount),
      GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                  &deposit->h_denom_pub),
      TALER_JSON_pack_denom_sig ("ub_sig",
                                 &deposit->denom_sig),
      GNUNET_JSON_pack_data_auto ("coin_pub",
                                  &coin->coin_pub),
      GNUNET_JSON_pack_data_auto ("coin_sig",
                                  &coin_sig));
    GNUNET_assert (0 ==
                   json_array_append_new (deposit_arr,
                                          jdeposit));
  }
  create_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("deposits",
                                  deposit_arr));
  GNUNET_assert (NULL != create_obj);
  eh = TALER_EXCHANGE_curl_easy_get_ (pch->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&pch->ctx,
                              eh,
                              create_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (create_obj);
    GNUNET_free (pch->base_url);
    GNUNET_free (pch->url);
    GNUNET_free (pch->coins);
    GNUNET_free (pch);
    return NULL;
  }
  json_decref (create_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for purse deposit: `%s'\n",
              pch->url);
  ctx = TEAH_handle_to_context (exchange);
  pch->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   pch->ctx.headers,
                                   &handle_purse_deposit_finished,
                                   pch);
  return pch;
}


void
TALER_EXCHANGE_purse_deposit_cancel (
  struct TALER_EXCHANGE_PurseDepositHandle *pch)
{
  if (NULL != pch->job)
  {
    GNUNET_CURL_job_cancel (pch->job);
    pch->job = NULL;
  }
  GNUNET_free (pch->base_url);
  GNUNET_free (pch->url);
  GNUNET_free (pch->coins);
  TALER_curl_easy_post_finished (&pch->ctx);
  GNUNET_free (pch);
}


/* end of exchange_api_purse_deposit.c */
