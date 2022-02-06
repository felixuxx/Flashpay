/*
  This file is part of TALER
  Copyright (C) 2015-2022 Taler Systems SA

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
 * @file lib/exchange_api_melt.c
 * @brief Implementation of the /coins/$COIN_PUB/melt request
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
#include "exchange_api_refresh_common.h"


/**
 * @brief A /coins/$COIN_PUB/melt Handle
 */
struct TALER_EXCHANGE_MeltHandle
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
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with refresh melt failure results.
   */
  TALER_EXCHANGE_MeltCallback melt_cb;

  /**
   * Closure for @e result_cb and @e melt_failure_cb.
   */
  void *melt_cb_cls;

  /**
   * Actual information about the melt operation.
   */
  struct MeltData md;

  /**
   * The secret the entire melt operation is seeded from.
   */
  const struct TALER_PlanchetSecretsP *ps;

  /**
   * Details about the characteristics of the requested melt operation.
   */
  const struct TALER_EXCHANGE_RefreshData *rd;

  /**
   * Array of `num_fresh_coins` contributory values of
   * the exchange to the melt operation.
   */
  struct TALER_ExchangeWithdrawValues *alg_values;

  /**
   * Handle for the preflight request, or NULL.
   */
  struct TALER_EXCHANGE_CsRHandle *csr;

  /**
   * Public key of the coin being melted.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * @brief Public information about the coin's denomination key
   */
  const struct TALER_EXCHANGE_DenomPublicKey *dki;
};


/**
 * Verify that the signature on the "200 OK" response
 * from the exchange is valid.
 *
 * @param mh melt handle
 * @param json json reply with the signature
 * @param[out] exchange_pub public key of the exchange used for the signature
 * @param[out] noreveal_index set to the noreveal index selected by the exchange
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_melt_signature_ok (struct TALER_EXCHANGE_MeltHandle *mh,
                          const json_t *json,
                          struct TALER_ExchangePublicKeyP *exchange_pub,
                          uint32_t *noreveal_index)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 exchange_pub),
    GNUNET_JSON_spec_uint32 ("noreveal_index",
                             noreveal_index),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_RefreshMeltConfirmationPS confirm;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that exchange signing key is permitted */
  key_state = TALER_EXCHANGE_get_keys (mh->exchange);
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                       exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that noreveal index is in permitted range */
  if (TALER_CNC_KAPPA <= *noreveal_index)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* verify signature by exchange */
  confirm.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT);
  confirm.purpose.size
    = htonl (sizeof (struct TALER_RefreshMeltConfirmationPS));
  confirm.rc = mh->md.rc;
  confirm.noreveal_index = htonl (*noreveal_index);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT,
                                  &confirm,
                                  &exchange_sig.eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify that the signatures on the "409 CONFLICT" response from the
 * exchange demonstrating customer denomination key differences
 * resulting from coin private key reuse are valid.
 *
 * @param mh melt handle
 * @param json json reply with the signature(s) and transaction history
 * @return #GNUNET_OK if the signature(s) is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_melt_signature_denom_conflict (struct TALER_EXCHANGE_MeltHandle *mh,
                                      const json_t *json)

{
  json_t *history;
  struct TALER_Amount total;
  struct TALER_DenominationHash h_denom_pub;

  memset (&h_denom_pub,
          0,
          sizeof (h_denom_pub));
  history = json_object_get (json,
                             "history");
  if (GNUNET_OK !=
      TALER_EXCHANGE_verify_coin_history (mh->dki,
                                          mh->dki->value.currency,
                                          &mh->coin_pub,
                                          history,
                                          &h_denom_pub,
                                          &total))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (0 != GNUNET_memcmp (&mh->dki->h_key,
                          &h_denom_pub))
    return GNUNET_OK; /* indeed, proof with different denomination key provided */
  /* invalid proof provided */
  return GNUNET_SYSERR;
}


/**
 * Verify that the signatures on the "409 CONFLICT" response from the
 * exchange demonstrating customer double-spending are valid.
 *
 * @param mh melt handle
 * @param json json reply with the signature(s) and transaction history
 * @return #GNUNET_OK if the signature(s) is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_melt_signature_spend_conflict (struct TALER_EXCHANGE_MeltHandle *mh,
                                      const json_t *json)
{
  json_t *history;
  struct TALER_Amount total;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("history",
                           &history),
    GNUNET_JSON_spec_end ()
  };
  const struct MeltedCoin *mc;
  enum TALER_ErrorCode ec;
  struct TALER_DenominationHash h_denom_pub;

  /* parse JSON reply */
  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* Find out which coin was deemed problematic by the exchange */
  mc = &mh->md.melted_coin;
  /* verify coin history */
  memset (&h_denom_pub,
          0,
          sizeof (h_denom_pub));
  history = json_object_get (json,
                             "history");
  if (GNUNET_OK !=
      TALER_EXCHANGE_verify_coin_history (mh->dki,
                                          mc->original_value.currency,
                                          &mh->coin_pub,
                                          history,
                                          &h_denom_pub,
                                          &total))
  {
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }
  json_decref (history);

  ec = TALER_JSON_get_error_code (json);
  switch (ec)
  {
  case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
    /* check if melt operation was really too expensive given history */
    if (0 >
        TALER_amount_add (&total,
                          &total,
                          &mc->melt_amount_with_fee))
    {
      /* clearly not OK if our transaction would have caused
         the overflow... */
      return GNUNET_OK;
    }

    if (0 >= TALER_amount_cmp (&total,
                               &mc->original_value))
    {
      /* transaction should have still fit */
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

    /* everything OK, valid proof of double-spending was provided */
    return GNUNET_OK;
  case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
    if (0 != GNUNET_memcmp (&mh->dki->h_key,
                            &h_denom_pub))
      return GNUNET_OK; /* indeed, proof with different denomination key provided */
    /* invalid proof provided */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  default:
    /* unexpected error code */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


/**
 * Function called when we're done processing the
 * HTTP /coins/$COIN_PUB/melt request.
 *
 * @param cls the `struct TALER_EXCHANGE_MeltHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_melt_finished (void *cls,
                      long response_code,
                      const void *response)
{
  struct TALER_EXCHANGE_MeltHandle *mh = cls;
  uint32_t noreveal_index = TALER_CNC_KAPPA; /* invalid value */
  struct TALER_ExchangePublicKeyP exchange_pub;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  mh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_melt_signature_ok (mh,
                                  j,
                                  &exchange_pub,
                                  &noreveal_index))
    {
      GNUNET_break_op (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_EXCHANGE_MELT_INVALID_SIGNATURE_BY_EXCHANGE;
    }
    if (NULL != mh->melt_cb)
    {
      mh->melt_cb (mh->melt_cb_cls,
                   &hr,
                   (0 == hr.http_status)
                   ? 0
                   : mh->rd->fresh_pks_len,
                   (0 == hr.http_status)
                   ? NULL
                   : mh->alg_values,
                   noreveal_index,
                   (0 == hr.http_status)
                   ? NULL
                   : &exchange_pub);
      mh->melt_cb = NULL;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    hr.ec = TALER_JSON_get_error_code (j);
    switch (hr.ec)
    {
    case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
      /* Double spending; check signatures on transaction history */
      if (GNUNET_OK !=
          verify_melt_signature_spend_conflict (mh,
                                                j))
      {
        GNUNET_break_op (0);
        hr.http_status = 0;
        hr.ec = TALER_EC_EXCHANGE_MELT_INVALID_SIGNATURE_BY_EXCHANGE;
        hr.hint = TALER_JSON_get_error_hint (j);
      }
      break;
    case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
      if (GNUNET_OK !=
          verify_melt_signature_denom_conflict (mh,
                                                j))
      {
        GNUNET_break_op (0);
        hr.http_status = 0;
        hr.ec = TALER_EC_EXCHANGE_MELT_INVALID_SIGNATURE_BY_EXCHANGE;
        hr.hint = TALER_JSON_get_error_hint (j);
      }
      break;
    default:
      GNUNET_break_op (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_EXCHANGE_MELT_INVALID_SIGNATURE_BY_EXCHANGE;
      hr.hint = TALER_JSON_get_error_hint (j);
      break;
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; assuming we checked them, this should never happen, we
       should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange melt\n",
                (unsigned int) response_code,
                hr.ec);
    GNUNET_break_op (0);
    break;
  }
  if (NULL != mh->melt_cb)
    mh->melt_cb (mh->melt_cb_cls,
                 &hr,
                 0,
                 NULL,
                 UINT32_MAX,
                 NULL);
  TALER_EXCHANGE_melt_cancel (mh);
}


static enum GNUNET_GenericReturnValue
start_melt (struct TALER_EXCHANGE_MeltHandle *mh)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  json_t *melt_obj;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  struct TALER_CoinSpendSignatureP confirm_sig;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];
  struct TALER_DenominationHash h_denom_pub;
  struct TALER_CoinSpendPublicKeyP coin_pub;

  if (GNUNET_OK !=
      TALER_EXCHANGE_get_melt_data_ (mh->ps,
                                     mh->rd,
                                     mh->alg_values,
                                     &mh->md))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_denom_pub_hash (&mh->md.melted_coin.pub_key,
                        &h_denom_pub);
  TALER_wallet_melt_sign (&mh->md.melted_coin.melt_amount_with_fee,
                          &mh->md.melted_coin.fee_melt,
                          &mh->md.rc,
                          &h_denom_pub,
                          &mh->md.melted_coin.coin_priv,
                          &confirm_sig);
  GNUNET_CRYPTO_eddsa_key_get_public (&mh->md.melted_coin.coin_priv.eddsa_priv,
                                      &coin_pub.eddsa_pub);
  melt_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                &h_denom_pub),
    TALER_JSON_pack_denom_sig ("denom_sig",
                               &mh->md.melted_coin.sig),
    GNUNET_JSON_pack_data_auto ("confirm_sig",
                                &confirm_sig),
    TALER_JSON_pack_amount ("value_with_fee",
                            &mh->md.melted_coin.melt_amount_with_fee),
    GNUNET_JSON_pack_data_auto ("rc",
                                &mh->md.rc));
  {
    char pub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &coin_pub,
      sizeof (struct TALER_CoinSpendPublicKeyP),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/coins/%s/melt",
                     pub_str);
  }

  ctx = TEAH_handle_to_context (mh->exchange);
  key_state = TALER_EXCHANGE_get_keys (mh->exchange);
  mh->dki = TALER_EXCHANGE_get_denomination_key (key_state,
                                                 &mh->md.melted_coin.pub_key);

  /* and now we can at last begin the actual request handling */

  mh->url = TEAH_path_to_url (mh->exchange,
                              arg_str);
  if (NULL == mh->url)
  {
    json_decref (melt_obj);
    return GNUNET_SYSERR;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (mh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&mh->ctx,
                              eh,
                              melt_obj)) )
  {
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (melt_obj);
    return GNUNET_SYSERR;
  }
  json_decref (melt_obj);
  mh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  mh->ctx.headers,
                                  &handle_melt_finished,
                                  mh);
  return GNUNET_OK;
}


static void
fail_mh (struct TALER_EXCHANGE_MeltHandle *mh)
{
  // FIXME: do return more than NULLs if
  // the /csr failed!
  mh->melt_cb (mh->melt_cb_cls,
               NULL,
               0,
               NULL,
               UINT32_MAX,
               NULL);
  TALER_EXCHANGE_melt_cancel (mh);
}


/**
 * Callbacks of this type are used to serve the result of submitting a
 * CS R request to a exchange.
 *
 * @param cls closure with our `struct TALER_EXCHANGE_MeltHandle *`
 * @param csrr response details
 */
static void
csr_cb (void *cls,
        const struct TALER_EXCHANGE_CsRResponse *csrr)
{
  struct TALER_EXCHANGE_MeltHandle *mh = cls;
  unsigned int nks_off = 0;

  for (unsigned int i = 0; i<mh->rd->fresh_pks_len; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *fresh_pk =
      &mh->rd->fresh_pks[i];
    struct TALER_ExchangeWithdrawValues *wv = &mh->alg_values[i];

    switch (fresh_pk->key.cipher)
    {
    case TALER_DENOMINATION_INVALID:
      GNUNET_break (0);
      // FIXME:
      // fail_mh (mh).
      return;
    case TALER_DENOMINATION_RSA:
      GNUNET_assert (TALER_DENOMINATION_RSA == wv->cipher);
      break;
    case TALER_DENOMINATION_CS:
      GNUNET_assert (TALER_DENOMINATION_CS == wv->cipher);
      *wv = csrr->details.success.alg_values[nks_off];
      nks_off++;
      break;
    }
  }
  if (GNUNET_OK !=
      start_melt (mh))
  {
    GNUNET_break (0);
    fail_mh (mh);
    return;
  }
}


struct TALER_EXCHANGE_MeltHandle *
TALER_EXCHANGE_melt (struct TALER_EXCHANGE_Handle *exchange,
                     const struct TALER_PlanchetSecretsP *ps,
                     const struct TALER_EXCHANGE_RefreshData *rd,
                     TALER_EXCHANGE_MeltCallback melt_cb,
                     void *melt_cb_cls)
{
  struct TALER_EXCHANGE_NonceKey nks[GNUNET_NZL (rd->fresh_pks_len)];
  unsigned int nks_off = 0;
  struct TALER_EXCHANGE_MeltHandle *mh;

  if (0 == rd->fresh_pks_len)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  mh = GNUNET_new (struct TALER_EXCHANGE_MeltHandle);
  mh->exchange = exchange;
  mh->rd = rd;
  mh->ps = ps;
  mh->melt_cb = melt_cb;
  mh->melt_cb_cls = melt_cb_cls;
  mh->alg_values = GNUNET_new_array (rd->fresh_pks_len,
                                     struct TALER_ExchangeWithdrawValues);
  for (unsigned int i = 0; i<rd->fresh_pks_len; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *fresh_pk = &rd->fresh_pks[i];
    struct TALER_ExchangeWithdrawValues *wv = &mh->alg_values[i];

    switch (fresh_pk->key.cipher)
    {
    case TALER_DENOMINATION_INVALID:
      GNUNET_break (0);
      GNUNET_free (mh->alg_values);
      GNUNET_free (mh);
      return NULL;
    case TALER_DENOMINATION_RSA:
      wv->cipher = TALER_DENOMINATION_RSA;
      break;
    case TALER_DENOMINATION_CS:
      wv->cipher = TALER_DENOMINATION_CS;
      nks[nks_off].pk = fresh_pk;
      TALER_cs_refresh_nonce_derive (ps,
                                     i,
                                     &nks[nks_off].nonce);
      nks_off++;
      break;
    }
  }
  if (0 != nks_off)
  {
    mh->csr = TALER_EXCHANGE_csr (exchange,
                                  nks_off,
                                  nks,
                                  &csr_cb,
                                  mh);
    if (NULL == mh->csr)
    {
      GNUNET_break (0);
      TALER_EXCHANGE_melt_cancel (mh);
      return NULL;
    }
    return mh;
  }
  if (GNUNET_OK !=
      start_melt (mh))
  {
    GNUNET_break (0);
    TALER_EXCHANGE_melt_cancel (mh);
    return NULL;
  }
  return mh;
}


void
TALER_EXCHANGE_melt_cancel (struct TALER_EXCHANGE_MeltHandle *mh)
{
  if (NULL != mh->job)
  {
    GNUNET_CURL_job_cancel (mh->job);
    mh->job = NULL;
  }
  if (NULL != mh->csr)
  {
    TALER_EXCHANGE_csr_cancel (mh->csr);
    mh->csr = NULL;
  }
  TALER_EXCHANGE_free_melt_data_ (&mh->md); /* does not free 'md' itself */
  GNUNET_free (mh->url);
  TALER_curl_easy_post_finished (&mh->ctx);
  GNUNET_free (mh);
}


/* end of exchange_api_melt.c */
