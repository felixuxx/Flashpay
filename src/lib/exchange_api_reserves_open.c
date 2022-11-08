/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file lib/exchange_api_reserves_open.c
 * @brief Implementation of the POST /reserves/$RESERVE_PUB/open requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP open codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * Information we keep per coin to validate the reply.
 */
struct CoinData
{
  /**
   * Public key of the coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Signature by the coin.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * The hash of the denomination's public key
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * How much did this coin contribute.
   */
  struct TALER_Amount contribution;
};


/**
 * @brief A /reserves/$RID/open Handle
 */
struct TALER_EXCHANGE_ReservesOpenHandle
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ReservesOpenCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Information we keep per coin to validate the reply.
   */
  struct CoinData *coins;

  /**
   * Length of the @e coins array.
   */
  unsigned int num_coins;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Our signature.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * When did we make the request.
   */
  struct GNUNET_TIME_Timestamp ts;

};


/**
 * We received an #MHD_HTTP_OK open code. Handle the JSON
 * response.
 *
 * @param roh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_open_ok (struct TALER_EXCHANGE_ReservesOpenHandle *roh,
                         const json_t *j)
{
  struct TALER_EXCHANGE_ReserveOpenResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_OK,
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("open_cost",
                                &rs.details.ok.open_cost),
    GNUNET_JSON_spec_timestamp ("reserve_expiration",
                                &rs.details.ok.expiration_time),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  roh->cb (roh->cb_cls,
           &rs);
  roh->cb = NULL;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * We received an #MHD_HTTP_PAYMENT_REQUIRED open code. Handle the JSON
 * response.
 *
 * @param roh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_open_pr (struct TALER_EXCHANGE_ReservesOpenHandle *roh,
                         const json_t *j)
{
  struct TALER_EXCHANGE_ReserveOpenResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_PAYMENT_REQUIRED,
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount_any ("open_cost",
                                &rs.details.payment_required.open_cost),
    GNUNET_JSON_spec_timestamp ("reserve_expiration",
                                &rs.details.payment_required.expiration_time),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  roh->cb (roh->cb_cls,
           &rs);
  roh->cb = NULL;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * We received an #MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS open code. Handle the JSON
 * response.
 *
 * @param roh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
handle_reserves_open_kyc (struct TALER_EXCHANGE_ReservesOpenHandle *roh,
                          const json_t *j)
{
  struct TALER_EXCHANGE_ReserveOpenResult rs = {
    .hr.reply = j,
    .hr.http_status = MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto (
      "h_payto",
      &rs.details.unavailable_for_legal_reasons.h_payto),
    GNUNET_JSON_spec_uint64 (
      "requirement_row",
      &rs.details.unavailable_for_legal_reasons.requirement_row),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  roh->cb (roh->cb_cls,
           &rs);
  roh->cb = NULL;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RID/open request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReservesOpenHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserves_open_finished (void *cls,
                               long response_code,
                               const void *response)
{
  struct TALER_EXCHANGE_ReservesOpenHandle *roh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_ReserveOpenResult rs = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  roh->job = NULL;
  switch (response_code)
  {
  case 0:
    rs.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserves_open_ok (roh,
                                 j))
    {
      GNUNET_break_op (0);
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    json_dumpf (j,
                stderr,
                JSON_INDENT (2));
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_PAYMENT_REQUIRED:
    if (GNUNET_OK !=
        handle_reserves_open_pr (roh,
                                 j))
    {
      GNUNET_break_op (0);
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    GNUNET_break (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    {
      const struct TALER_EXCHANGE_Keys *keys;
      const struct CoinData *cd = NULL;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      const struct TALER_EXCHANGE_DenomPublicKey *dk;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                     &coin_pub),
        GNUNET_JSON_spec_end ()
      };

      keys = TALER_EXCHANGE_get_keys (roh->exchange);
      GNUNET_assert (NULL != keys);
      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        rs.hr.http_status = 0;
        rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      for (unsigned int i = 0; i<roh->num_coins; i++)
      {
        const struct CoinData *cdi = &roh->coins[i];

        if (0 == GNUNET_memcmp (&coin_pub,
                                &cdi->coin_pub))
        {
          cd = cdi;
          break;
        }
      }
      if (NULL == cd)
      {
        GNUNET_break_op (0);
        rs.hr.http_status = 0;
        rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      dk = TALER_EXCHANGE_get_denomination_key_by_hash (keys,
                                                        &cd->h_denom_pub);
      if (NULL == dk)
      {
        GNUNET_break_op (0);
        rs.hr.http_status = 0;
        rs.hr.ec = TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR;
        break;
      }
      if (GNUNET_OK !=
          TALER_EXCHANGE_check_coin_conflict_ (keys,
                                               j,
                                               dk,
                                               &coin_pub,
                                               &cd->coin_sig,
                                               &cd->contribution))
      {
        GNUNET_break_op (0);
        rs.hr.http_status = 0;
        rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      rs.hr.ec = TALER_JSON_get_error_code (j);
      rs.hr.hint = TALER_JSON_get_error_hint (j);
      break;
    }
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    if (GNUNET_OK !=
        handle_reserves_open_kyc (roh,
                                  j))
    {
      GNUNET_break_op (0);
      rs.hr.http_status = 0;
      rs.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
    }
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    rs.hr.ec = TALER_JSON_get_error_code (j);
    rs.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for reserves open\n",
                (unsigned int) response_code,
                (int) rs.hr.ec);
    break;
  }
  if (NULL != roh->cb)
  {
    roh->cb (roh->cb_cls,
             &rs);
    roh->cb = NULL;
  }
  TALER_EXCHANGE_reserves_open_cancel (roh);
}


struct TALER_EXCHANGE_ReservesOpenHandle *
TALER_EXCHANGE_reserves_open (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_Amount *reserve_contribution,
  unsigned int coin_payments_length,
  const struct TALER_EXCHANGE_PurseDeposit *coin_payments,
  struct GNUNET_TIME_Timestamp expiration_time,
  uint32_t min_purses,
  TALER_EXCHANGE_ReservesOpenCallback cb,
  void *cb_cls)
{
  struct TALER_EXCHANGE_ReservesOpenHandle *roh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char arg_str[sizeof (struct TALER_ReservePublicKeyP) * 2 + 32];
  const struct TALER_EXCHANGE_Keys *keys;
  json_t *cpa;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  roh = GNUNET_new (struct TALER_EXCHANGE_ReservesOpenHandle);
  roh->exchange = exchange;
  roh->cb = cb;
  roh->cb_cls = cb_cls;
  roh->ts = GNUNET_TIME_timestamp_get ();
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &roh->reserve_pub.eddsa_pub);
  {
    char pub_str[sizeof (struct TALER_ReservePublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &roh->reserve_pub,
      sizeof (roh->reserve_pub),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/reserves/%s/open",
                     pub_str);
  }
  roh->url = TEAH_path_to_url (exchange,
                               arg_str);
  if (NULL == roh->url)
  {
    GNUNET_free (roh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (roh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (roh->url);
    GNUNET_free (roh);
    return NULL;
  }
  keys = TALER_EXCHANGE_get_keys (exchange);
  if (NULL == keys)
  {
    GNUNET_break (0);
    curl_easy_cleanup (eh);
    GNUNET_free (roh->url);
    GNUNET_free (roh);
    return NULL;
  }
  TALER_wallet_reserve_open_sign (reserve_contribution,
                                  roh->ts,
                                  expiration_time,
                                  min_purses,
                                  reserve_priv,
                                  &roh->reserve_sig);
  roh->coins = GNUNET_new_array (coin_payments_length,
                                 struct CoinData);
  cpa = json_array ();
  GNUNET_assert (NULL != cpa);
  for (unsigned int i = 0; i<coin_payments_length; i++)
  {
    const struct TALER_EXCHANGE_PurseDeposit *pd = &coin_payments[i];
    const struct TALER_AgeCommitmentProof *acp = pd->age_commitment_proof;
    struct TALER_AgeCommitmentHash ahac;
    struct TALER_AgeCommitmentHash *achp = NULL;
    struct CoinData *cd = &roh->coins[i];
    json_t *cp;

    cd->contribution = pd->amount;
    cd->h_denom_pub = pd->h_denom_pub;
    if (NULL != acp)
    {
      TALER_age_commitment_hash (&acp->commitment,
                                 &ahac);
      achp = &ahac;
    }
    TALER_wallet_reserve_open_deposit_sign (&pd->amount,
                                            &roh->reserve_sig,
                                            &pd->coin_priv,
                                            &cd->coin_sig);
    GNUNET_CRYPTO_eddsa_key_get_public (&pd->coin_priv.eddsa_priv,
                                        &cd->coin_pub.eddsa_pub);

    cp = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                    achp)),
      TALER_JSON_pack_amount ("amount",
                              &pd->amount),
      GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                  &pd->h_denom_pub),
      TALER_JSON_pack_denom_sig ("ub_sig",
                                 &pd->denom_sig),
      GNUNET_JSON_pack_data_auto ("coin_pub",
                                  &cd->coin_pub),
      GNUNET_JSON_pack_data_auto ("coin_sig",
                                  &cd->coin_sig));
    GNUNET_assert (0 ==
                   json_array_append_new (cpa,
                                          cp));
  }
  {
    json_t *open_obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_timestamp ("request_timestamp",
                                  roh->ts),
      GNUNET_JSON_pack_timestamp ("reserve_expiration",
                                  expiration_time),
      GNUNET_JSON_pack_array_steal ("payments",
                                    cpa),
      TALER_JSON_pack_amount ("reserve_payment",
                              reserve_contribution),
      GNUNET_JSON_pack_uint64 ("purse_limit",
                               min_purses),
      GNUNET_JSON_pack_data_auto ("reserve_sig",
                                  &roh->reserve_sig));

    if (GNUNET_OK !=
        TALER_curl_easy_post (&roh->post_ctx,
                              eh,
                              open_obj))
    {
      GNUNET_break (0);
      curl_easy_cleanup (eh);
      json_decref (open_obj);
      GNUNET_free (roh->coins);
      GNUNET_free (roh->url);
      GNUNET_free (roh);
      return NULL;
    }
    json_decref (open_obj);
  }
  ctx = TEAH_handle_to_context (exchange);
  roh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   roh->post_ctx.headers,
                                   &handle_reserves_open_finished,
                                   roh);
  return roh;
}


void
TALER_EXCHANGE_reserves_open_cancel (
  struct TALER_EXCHANGE_ReservesOpenHandle *roh)
{
  if (NULL != roh->job)
  {
    GNUNET_CURL_job_cancel (roh->job);
    roh->job = NULL;
  }
  TALER_curl_easy_post_finished (&roh->post_ctx);
  GNUNET_free (roh->coins);
  GNUNET_free (roh->url);
  GNUNET_free (roh);
}


/* end of exchange_api_reserves_open.c */
