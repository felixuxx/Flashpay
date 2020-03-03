/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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
  struct MeltData *md;

  /**
   * @brief Public information about the coin's denomination key
   */
  struct TALER_EXCHANGE_DenomPublicKey dki;
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
static int
verify_melt_signature_ok (struct TALER_EXCHANGE_MeltHandle *mh,
                          const json_t *json,
                          struct TALER_ExchangePublicKeyP *exchange_pub,
                          uint32_t *noreveal_index)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig", &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub", exchange_pub),
    GNUNET_JSON_spec_uint32 ("noreveal_index", noreveal_index),
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
  confirm.purpose.size = htonl (sizeof (struct
                                        TALER_RefreshMeltConfirmationPS));
  confirm.rc = mh->md->rc;
  confirm.noreveal_index = htonl (*noreveal_index);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT,
                                  &confirm.purpose,
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
 * exchange demonstrating customer double-spending are valid.
 *
 * @param mh melt handle
 * @param json json reply with the signature(s) and transaction history
 * @return #GNUNET_OK if the signature(s) is valid, #GNUNET_SYSERR if not
 */
static int
verify_melt_signature_conflict (struct TALER_EXCHANGE_MeltHandle *mh,
                                const json_t *json)
{
  json_t *history;
  struct TALER_Amount original_value;
  struct TALER_Amount melt_value_with_fee;
  struct TALER_Amount total;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("history", &history),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &coin_pub),
    TALER_JSON_spec_amount ("original_value", &original_value),
    TALER_JSON_spec_amount ("requested_value", &melt_value_with_fee),
    GNUNET_JSON_spec_end ()
  };
  const struct MeltedCoin *mc;

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
  mc = &mh->md->melted_coin;

  /* check basic coin properties */
  if (0 != TALER_amount_cmp (&original_value,
                             &mc->original_value))
  {
    /* We disagree on the value of the coin */
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }
  if (0 != TALER_amount_cmp (&melt_value_with_fee,
                             &mc->melt_amount_with_fee))
  {
    /* We disagree on the value of the coin */
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }

  /* verify coin history */
  history = json_object_get (json,
                             "history");
  if (GNUNET_OK !=
      TALER_EXCHANGE_verify_coin_history (&mh->dki,
                                          original_value.currency,
                                          &coin_pub,
                                          history,
                                          &total))
  {
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }
  json_decref (history);

  /* check if melt operation was really too expensive given history */
  if (GNUNET_OK !=
      TALER_amount_add (&total,
                        &total,
                        &melt_value_with_fee))
  {
    /* clearly not OK if our transaction would have caused
       the overflow... */
    return GNUNET_OK;
  }

  if (0 >= TALER_amount_cmp (&total,
                             &original_value))
  {
    /* transaction should have still fit */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* everything OK, valid proof of double-spending was provided */
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
  uint32_t noreveal_index = TALER_CNC_KAPPA; /* invalid value */
  struct TALER_ExchangePublicKeyP exchange_pub;
  const json_t *j = response;

  mh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_melt_signature_ok (mh,
                                  j,
                                  &exchange_pub,
                                  &noreveal_index))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    if (NULL != mh->melt_cb)
    {
      mh->melt_cb (mh->melt_cb_cls,
                   response_code,
                   TALER_JSON_get_error_code (j),
                   noreveal_index,
                   (0 == response_code) ? NULL : &exchange_pub,
                   j);
      mh->melt_cb = NULL;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    /* Double spending; check signatures on transaction history */
    if (GNUNET_OK !=
        verify_melt_signature_conflict (mh,
                                        j))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; assuming we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != mh->melt_cb)
    mh->melt_cb (mh->melt_cb_cls,
                 response_code,
                 TALER_JSON_get_error_code (j),
                 UINT32_MAX,
                 NULL,
                 j);
  TALER_EXCHANGE_melt_cancel (mh);
}


/**
 * Submit a melt request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument should have been constructed using
 * #TALER_EXCHANGE_refresh_prepare and committed to persistent storage
 * prior to calling this function.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_EXCHANGE_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_EXCHANGE_refresh_prepare())
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_MeltHandle *
TALER_EXCHANGE_melt (struct TALER_EXCHANGE_Handle *exchange,
                     size_t refresh_data_length,
                     const char *refresh_data,
                     TALER_EXCHANGE_MeltCallback melt_cb,
                     void *melt_cb_cls)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  const struct TALER_EXCHANGE_DenomPublicKey *dki;
  json_t *melt_obj;
  struct TALER_EXCHANGE_MeltHandle *mh;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  struct MeltData *md;
  struct TALER_CoinSpendSignatureP confirm_sig;
  struct TALER_RefreshMeltCoinAffirmationPS melt;
  struct GNUNET_HashCode h_denom_pub;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];

  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  md = TALER_EXCHANGE_deserialize_melt_data_ (refresh_data,
                                              refresh_data_length);
  if (NULL == md)
  {
    GNUNET_break (0);
    return NULL;
  }
  melt.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
  melt.purpose.size = htonl (sizeof (struct
                                     TALER_RefreshMeltCoinAffirmationPS));
  melt.rc = md->rc;
  TALER_amount_hton (&melt.amount_with_fee,
                     &md->melted_coin.melt_amount_with_fee);
  TALER_amount_hton (&melt.melt_fee,
                     &md->melted_coin.fee_melt);
  GNUNET_CRYPTO_eddsa_key_get_public (&md->melted_coin.coin_priv.eddsa_priv,
                                      &melt.coin_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_sign (&md->melted_coin.coin_priv.eddsa_priv,
                            &melt.purpose,
                            &confirm_sig.eddsa_signature);
  GNUNET_CRYPTO_rsa_public_key_hash (md->melted_coin.pub_key.rsa_public_key,
                                     &h_denom_pub);
  melt_obj = json_pack ("{s:o, s:o, s:o, s:o, s:o, s:o}",
                        "coin_pub",
                        GNUNET_JSON_from_data_auto (&melt.coin_pub),
                        "denom_pub_hash",
                        GNUNET_JSON_from_data_auto (&h_denom_pub),
                        "denom_sig",
                        GNUNET_JSON_from_rsa_signature (
                          md->melted_coin.sig.rsa_signature),
                        "confirm_sig",
                        GNUNET_JSON_from_data_auto (&confirm_sig),
                        "value_with_fee",
                        TALER_JSON_from_amount (
                          &md->melted_coin.melt_amount_with_fee),
                        "rc",
                        GNUNET_JSON_from_data_auto (&melt.rc));
  if (NULL == melt_obj)
  {
    GNUNET_break (0);
    TALER_EXCHANGE_free_melt_data_ (md);
    return NULL;
  }
  {
    char pub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (&melt.coin_pub,
                                         sizeof (struct
                                                 TALER_CoinSpendPublicKeyP),
                                         pub_str,
                                         sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/coins/%s/melt",
                     pub_str);
  }

  key_state = TALER_EXCHANGE_get_keys (exchange);
  dki = TALER_EXCHANGE_get_denomination_key (key_state,
                                             &md->melted_coin.pub_key);

  /* and now we can at last begin the actual request handling */
  mh = GNUNET_new (struct TALER_EXCHANGE_MeltHandle);
  mh->exchange = exchange;
  mh->dki = *dki;
  mh->dki.key.rsa_public_key = NULL; /* lifetime not warranted, so better
                                         not copy the pointer */
  mh->melt_cb = melt_cb;
  mh->melt_cb_cls = melt_cb_cls;
  mh->md = md;
  mh->url = TEAH_path_to_url (exchange,
                              arg_str);
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
    GNUNET_free (mh->url);
    GNUNET_free (mh);
    return NULL;
  }
  json_decref (melt_obj);
  ctx = TEAH_handle_to_context (exchange);
  mh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  mh->ctx.headers,
                                  &handle_melt_finished,
                                  mh);
  return mh;
}


/**
 * Cancel a melt request.  This function cannot be used
 * on a request handle if either callback was already invoked.
 *
 * @param mh the refresh melt handle
 */
void
TALER_EXCHANGE_melt_cancel (struct TALER_EXCHANGE_MeltHandle *mh)
{
  if (NULL != mh->job)
  {
    GNUNET_CURL_job_cancel (mh->job);
    mh->job = NULL;
  }
  TALER_EXCHANGE_free_melt_data_ (mh->md); /* does not free 'md' itself */
  GNUNET_free (mh->md);
  GNUNET_free (mh->url);
  TALER_curl_easy_post_finished (&mh->ctx);
  GNUNET_free (mh);
}


/* end of exchange_api_melt.c */
