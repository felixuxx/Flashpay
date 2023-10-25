/*
  This file is part of TALER
  Copyright (C) 2015-2023 Taler Systems SA

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
#include "exchange_api_common.h"
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
   * The keys of the this request handle will use
   */
  struct TALER_EXCHANGE_Keys *keys;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * The exchange base url.
   */
  char *exchange_url;

  /**
   * Curl context.
   */
  struct GNUNET_CURL_Context *cctx;

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
  struct TALER_RefreshMasterSecretP rms;

  /**
   * Details about the characteristics of the requested melt operation.
   */
  const struct TALER_EXCHANGE_RefreshData *rd;

  /**
   * Array of `num_fresh_coins` per-coin values
   * returned from melt operation.
   */
  struct TALER_EXCHANGE_MeltBlindingDetail *mbds;

  /**
   * Handle for the preflight request, or NULL.
   */
  struct TALER_EXCHANGE_CsRMeltHandle *csr;

  /**
   * Public key of the coin being melted.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Signature affirming the melt.
   */
  struct TALER_CoinSpendSignatureP coin_sig;

  /**
   * @brief Public information about the coin's denomination key
   */
  const struct TALER_EXCHANGE_DenomPublicKey *dki;

  /**
   * Gamma value chosen by the exchange during melt.
   */
  uint32_t noreveal_index;

  /**
   * True if we need to include @e rms in our melt request.
   */
  bool send_rms;
};


/**
 * Verify that the signature on the "200 OK" response
 * from the exchange is valid.
 *
 * @param[in,out] mh melt handle
 * @param json json reply with the signature
 * @param[out] exchange_pub public key of the exchange used for the signature
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_melt_signature_ok (struct TALER_EXCHANGE_MeltHandle *mh,
                          const json_t *json,
                          struct TALER_ExchangePublicKeyP *exchange_pub)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                 &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                 exchange_pub),
    GNUNET_JSON_spec_uint32 ("noreveal_index",
                             &mh->noreveal_index),
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
  /* check that exchange signing key is permitted */
  key_state = mh->keys;
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                       exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that noreveal index is in permitted range */
  if (TALER_CNC_KAPPA <= mh->noreveal_index)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_exchange_online_melt_confirmation_verify (
        &mh->md.rc,
        mh->noreveal_index,
        exchange_pub,
        &exchange_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
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
  const json_t *j = response;
  struct TALER_EXCHANGE_MeltResponse mr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  mh->job = NULL;
  switch (response_code)
  {
  case 0:
    mr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_melt_signature_ok (mh,
                                  j,
                                  &mr.details.ok.sign_key))
    {
      GNUNET_break_op (0);
      mr.hr.http_status = 0;
      mr.hr.ec = TALER_EC_EXCHANGE_MELT_INVALID_SIGNATURE_BY_EXCHANGE;
      break;
    }
    mr.details.ok.noreveal_index = mh->noreveal_index;
    mr.details.ok.num_mbds = mh->rd->fresh_pks_len;
    mr.details.ok.mbds = mh->mbds;
    mh->melt_cb (mh->melt_cb_cls,
                 &mr);
    mh->melt_cb = NULL;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    mr.hr.ec = TALER_JSON_get_error_code (j);
    mr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_CONFLICT:
    mr.hr.ec = TALER_JSON_get_error_code (j);
    mr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; assuming we checked them, this should never happen, we
       should pass the JSON reply to the application */
    mr.hr.ec = TALER_JSON_get_error_code (j);
    mr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    mr.hr.ec = TALER_JSON_get_error_code (j);
    mr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    mr.hr.ec = TALER_JSON_get_error_code (j);
    mr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  default:
    /* unexpected response code */
    mr.hr.ec = TALER_JSON_get_error_code (j);
    mr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange melt\n",
                (unsigned int) response_code,
                mr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  if (NULL != mh->melt_cb)
    mh->melt_cb (mh->melt_cb_cls,
                 &mr);
  TALER_EXCHANGE_melt_cancel (mh);
}


/**
 * Start the actual melt operation, now that we have
 * the exchange's input values.
 *
 * @param[in,out] mh melt operation to run
 * @return #GNUNET_OK if we could start the operation
 */
static enum GNUNET_GenericReturnValue
start_melt (struct TALER_EXCHANGE_MeltHandle *mh)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  json_t *melt_obj;
  CURL *eh;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];
  struct TALER_DenominationHashP h_denom_pub;
  struct TALER_ExchangeWithdrawValues alg_values[mh->rd->fresh_pks_len];

  for (unsigned int i = 0; i<mh->rd->fresh_pks_len; i++)
    alg_values[i] = mh->mbds[i].alg_value;
  if (GNUNET_OK !=
      TALER_EXCHANGE_get_melt_data_ (&mh->rms,
                                     mh->rd,
                                     alg_values,
                                     &mh->md))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_denom_pub_hash (&mh->md.melted_coin.pub_key,
                        &h_denom_pub);
  TALER_wallet_melt_sign (
    &mh->md.melted_coin.melt_amount_with_fee,
    &mh->md.melted_coin.fee_melt,
    &mh->md.rc,
    &h_denom_pub,
    mh->md.melted_coin.h_age_commitment,
    &mh->md.melted_coin.coin_priv,
    &mh->coin_sig);
  GNUNET_CRYPTO_eddsa_key_get_public (&mh->md.melted_coin.coin_priv.eddsa_priv,
                                      &mh->coin_pub.eddsa_pub);
  melt_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                &h_denom_pub),
    TALER_JSON_pack_denom_sig ("denom_sig",
                               &mh->md.melted_coin.sig),
    GNUNET_JSON_pack_data_auto ("confirm_sig",
                                &mh->coin_sig),
    TALER_JSON_pack_amount ("value_with_fee",
                            &mh->md.melted_coin.melt_amount_with_fee),
    GNUNET_JSON_pack_data_auto ("rc",
                                &mh->md.rc),
    GNUNET_JSON_pack_allow_null (
      (NULL != mh->md.melted_coin.h_age_commitment)
      ? GNUNET_JSON_pack_data_auto ("age_commitment_hash",
                                    mh->md.melted_coin.h_age_commitment)
      : GNUNET_JSON_pack_string ("age_commitment_hash",
                                 NULL)),
    GNUNET_JSON_pack_allow_null (
      mh->send_rms
      ? GNUNET_JSON_pack_data_auto ("rms",
                                    &mh->rms)
      : GNUNET_JSON_pack_string ("rms",
                                 NULL)));
  {
    char pub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      &mh->coin_pub,
      sizeof (struct TALER_CoinSpendPublicKeyP),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "coins/%s/melt",
                     pub_str);
  }

  key_state = mh->keys;
  mh->dki = TALER_EXCHANGE_get_denomination_key (key_state,
                                                 &mh->md.melted_coin.pub_key);

  /* and now we can at last begin the actual request handling */

  mh->url = TALER_url_join (mh->exchange_url,
                            arg_str,
                            NULL);
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
  mh->job = GNUNET_CURL_job_add2 (mh->cctx,
                                  eh,
                                  mh->ctx.headers,
                                  &handle_melt_finished,
                                  mh);
  return GNUNET_OK;
}


/**
 * The melt request @a mh failed, return an error to
 * the application and cancel the operation.
 *
 * @param[in] mh melt request that failed
 * @param ec error code to fail with
 */
static void
fail_mh (struct TALER_EXCHANGE_MeltHandle *mh,
         enum TALER_ErrorCode ec)
{
  struct TALER_EXCHANGE_MeltResponse mr = {
    .hr.ec = ec
  };

  mh->melt_cb (mh->melt_cb_cls,
               &mr);
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
        const struct TALER_EXCHANGE_CsRMeltResponse *csrr)
{
  struct TALER_EXCHANGE_MeltHandle *mh = cls;
  unsigned int nks_off = 0;

  mh->csr = NULL;
  if (MHD_HTTP_OK != csrr->hr.http_status)
  {
    struct TALER_EXCHANGE_MeltResponse mr = {
      .hr = csrr->hr
    };

    mr.hr.hint = "/csr-melt failed";
    mh->melt_cb (mh->melt_cb_cls,
                 &mr);
    TALER_EXCHANGE_melt_cancel (mh);
    return;
  }
  for (unsigned int i = 0; i<mh->rd->fresh_pks_len; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *fresh_pk =
      &mh->rd->fresh_pks[i];
    struct TALER_ExchangeWithdrawValues *wv = &mh->mbds[i].alg_value;

    switch (fresh_pk->key.bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_INVALID:
      GNUNET_break (0);
      fail_mh (mh,
               TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR);
      return;
    case GNUNET_CRYPTO_BSA_RSA:
      break;
    case GNUNET_CRYPTO_BSA_CS:
      *wv = csrr->details.ok.alg_values[nks_off];
      nks_off++;
      break;
    }
  }
  mh->send_rms = true;
  if (GNUNET_OK !=
      start_melt (mh))
  {
    GNUNET_break (0);
    fail_mh (mh,
             TALER_EC_GENERIC_CLIENT_INTERNAL_ERROR);
    return;
  }
}


struct TALER_EXCHANGE_MeltHandle *
TALER_EXCHANGE_melt (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_RefreshMasterSecretP *rms,
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
  mh = GNUNET_new (struct TALER_EXCHANGE_MeltHandle);
  mh->noreveal_index = TALER_CNC_KAPPA; /* invalid value */
  mh->cctx = ctx;
  mh->exchange_url = GNUNET_strdup (url);
  mh->rd = rd;
  mh->rms = *rms;
  mh->melt_cb = melt_cb;
  mh->melt_cb_cls = melt_cb_cls;
  mh->mbds = GNUNET_new_array (rd->fresh_pks_len,
                               struct TALER_EXCHANGE_MeltBlindingDetail);
  for (unsigned int i = 0; i<rd->fresh_pks_len; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *fresh_pk = &rd->fresh_pks[i];

    switch (fresh_pk->key.bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_INVALID:
      GNUNET_break (0);
      GNUNET_free (mh->mbds);
      GNUNET_free (mh);
      return NULL;
    case GNUNET_CRYPTO_BSA_RSA:
      break;
    case GNUNET_CRYPTO_BSA_CS:
      nks[nks_off].pk = fresh_pk;
      nks[nks_off].cnc_num = nks_off;
      nks_off++;
      break;
    }
  }
  mh->keys = TALER_EXCHANGE_keys_incref (keys);
  if (0 != nks_off)
  {
    mh->csr = TALER_EXCHANGE_csr_melt (ctx,
                                       url,
                                       rms,
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
    TALER_EXCHANGE_csr_melt_cancel (mh->csr);
    mh->csr = NULL;
  }
  TALER_EXCHANGE_free_melt_data_ (&mh->md); /* does not free 'md' itself */
  GNUNET_free (mh->mbds);
  GNUNET_free (mh->url);
  GNUNET_free (mh->exchange_url);
  TALER_curl_easy_post_finished (&mh->ctx);
  TALER_EXCHANGE_keys_decref (mh->keys);
  GNUNET_free (mh);
}


/* end of exchange_api_melt.c */
