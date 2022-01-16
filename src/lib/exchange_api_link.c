/*
  This file is part of TALER
  Copyright (C) 2015-2021 Taler Systems SA

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
 * @file lib/exchange_api_link.c
 * @brief Implementation of the /coins/$COIN_PUB/link request
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A /coins/$COIN_PUB/link Handle
 */
struct TALER_EXCHANGE_LinkHandle
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
   * Function to call with the result.
   */
  TALER_EXCHANGE_LinkCallback link_cb;

  /**
   * Closure for @e cb.
   */
  void *link_cb_cls;

  /**
   * Private key of the coin, required to decode link information.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

};


/**
 * Parse the provided linkage data from the "200 OK" response
 * for one of the coins.
 *
 * @param lh link handle
 * @param json json reply with the data for one coin
 * @param coin_num number of the coin
 * @param trans_pub our transfer public key
 * @param[out] coin_priv where to return private coin key
 * @param[out] sig where to return private coin signature
 * @param[out] pub where to return the public key for the coin
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static enum GNUNET_GenericReturnValue
parse_link_coin (const struct TALER_EXCHANGE_LinkHandle *lh,
                 const json_t *json,
                 uint32_t coin_num,
                 const struct TALER_TransferPublicKeyP *trans_pub,
                 struct TALER_CoinSpendPrivateKeyP *coin_priv,
                 struct TALER_DenominationSignature *sig,
                 struct TALER_DenominationPublicKey *pub)
{
  struct TALER_BlindedDenominationSignature bsig;
  struct TALER_DenominationPublicKey rpub;
  struct TALER_CoinSpendSignatureP link_sig;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_denom_pub ("denom_pub",
                               &rpub),
    TALER_JSON_spec_blinded_denom_sig ("ev_sig",
                                       &bsig),
    GNUNET_JSON_spec_fixed_auto ("link_sig",
                                 &link_sig),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_TransferSecretP secret;
  struct TALER_PlanchetSecretsP fc;

  /* parse reply */
  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  TALER_link_recover_transfer_secret (trans_pub,
                                      &lh->coin_priv,
                                      &secret);
  TALER_planchet_setup_refresh (&secret,
                                coin_num,
                                &fc);

  /* extract coin and signature */
  if (GNUNET_OK !=
      TALER_denom_sig_unblind (sig,
                               &bsig,
                               &fc.blinding_key,
                               &rpub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  *coin_priv = fc.coin_priv;
  /* verify link_sig */
  {
    struct TALER_ExchangeWithdrawValues alg_values;
    struct TALER_PlanchetDetail pd;
    struct TALER_CoinPubHash c_hash;
    struct TALER_CoinSpendPublicKeyP old_coin_pub;
    struct TALER_BlindedCoinHash coin_envelope_hash;

    GNUNET_CRYPTO_eddsa_key_get_public (&lh->coin_priv.eddsa_priv,
                                        &old_coin_pub.eddsa_pub);
    // TODO: implement cipher handling
    alg_values.cipher = TALER_DENOMINATION_RSA;
    if (GNUNET_OK !=
        TALER_planchet_prepare (&rpub,
                                &alg_values,
                                &fc,
                                &c_hash,
                                &pd))
    {
      GNUNET_break (0);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_hash (pd.coin_ev,
                        pd.coin_ev_size,
                        &coin_envelope_hash.hash);
    //FIXME: 
    if (GNUNET_OK !=
        TALER_wallet_link_verify (&pd.denom_pub_hash,
                                  trans_pub,
                                  &coin_envelope_hash,
                                  pd.blinded_planchet.details.
                                  rsa_blinded_planchet.blinded_msg,
                                  pd.blinded_planchet.details.
                                  rsa_blinded_planchet.blinded_msg_size,
                                  &old_coin_pub,
                                  &link_sig))
    {
      GNUNET_break_op (0);
      TALER_blinded_planchet_free (&pd.blinded_planchet);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
    TALER_blinded_planchet_free (&pd.blinded_planchet);
  }

  /* clean up */
  TALER_denom_pub_deep_copy (pub,
                             &rpub);
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Parse the provided linkage data from the "200 OK" response
 * for one of the coins.
 *
 * @param[in,out] lh link handle (callback may be zero'ed out)
 * @param json json reply with the data for one coin
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static enum GNUNET_GenericReturnValue
parse_link_ok (struct TALER_EXCHANGE_LinkHandle *lh,
               const json_t *json)
{
  unsigned int session;
  unsigned int num_coins;
  int ret;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = json,
    .http_status = MHD_HTTP_OK
  };

  if (! json_is_array (json))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  num_coins = 0;
  /* Theoretically, a coin may have been melted repeatedly
     into different sessions; so the response is an array
     which contains information by melting session.  That
     array contains another array.  However, our API returns
     a single 1d array, so we flatten the 2d array that is
     returned into a single array. Note that usually a coin
     is melted at most once, and so we'll only run this
     loop once for 'session=0' in most cases.

     num_coins tracks the size of the 1d array we return,
     whilst 'i' and 'session' track the 2d array. *///
  for (session = 0; session<json_array_size (json); session++)
  {
    json_t *jsona;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_json ("new_coins", &jsona),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (json_array_get (json,
                                           session),
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (! json_is_array (jsona))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }

    /* count all coins over all sessions */
    num_coins += json_array_size (jsona);
    GNUNET_JSON_parse_free (spec);
  }
  /* Now that we know how big the 1d array is, allocate
     and fill it. */
  {
    unsigned int off_coin; /* index into 1d array */
    unsigned int i;
    struct TALER_CoinSpendPrivateKeyP coin_privs[GNUNET_NZL (num_coins)];
    struct TALER_DenominationSignature sigs[GNUNET_NZL (num_coins)];
    struct TALER_DenominationPublicKey pubs[GNUNET_NZL (num_coins)];

    memset (sigs, 0, sizeof (sigs));
    memset (pubs, 0, sizeof (pubs));
    off_coin = 0;
    for (session = 0; session<json_array_size (json); session++)
    {
      json_t *jsona;
      struct TALER_TransferPublicKeyP trans_pub;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_json ("new_coins",
                               &jsona),
        GNUNET_JSON_spec_fixed_auto ("transfer_pub",
                                     &trans_pub),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (json_array_get (json,
                                             session),
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (! json_is_array (jsona))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }

      /* decode all coins */
      for (i = 0; i<json_array_size (jsona); i++)
      {
        GNUNET_assert (i + off_coin < num_coins);
        if (GNUNET_OK !=
            parse_link_coin (lh,
                             json_array_get (jsona,
                                             i),
                             i,
                             &trans_pub,
                             &coin_privs[i + off_coin],
                             &sigs[i + off_coin],
                             &pubs[i + off_coin]))
        {
          GNUNET_break_op (0);
          break;
        }
      }
      /* check if we really got all, then invoke callback */
      off_coin += i;
      if (i != json_array_size (jsona))
      {
        GNUNET_break_op (0);
        ret = GNUNET_SYSERR;
        GNUNET_JSON_parse_free (spec);
        break;
      }
      GNUNET_JSON_parse_free (spec);
    } /* end of for (session) */

    if (off_coin == num_coins)
    {
      lh->link_cb (lh->link_cb_cls,
                   &hr,
                   num_coins,
                   coin_privs,
                   sigs,
                   pubs);
      lh->link_cb = NULL;
      ret = GNUNET_OK;
    }
    else
    {
      GNUNET_break_op (0);
      ret = GNUNET_SYSERR;
    }

    /* clean up */
    GNUNET_assert (off_coin <= num_coins);
    for (i = 0; i<off_coin; i++)
    {
      TALER_denom_sig_free (&sigs[i]);
      TALER_denom_pub_free (&pubs[i]);
    }
  }
  return ret;
}


/**
 * Function called when we're done processing the
 * HTTP /coins/$COIN_PUB/link request.
 *
 * @param cls the `struct TALER_EXCHANGE_LinkHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_link_finished (void *cls,
                      long response_code,
                      const void *response)
{
  struct TALER_EXCHANGE_LinkHandle *lh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  lh->job = NULL;
  switch (response_code)
  {
  case 0:
    hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        parse_link_ok (lh,
                       j))
    {
      GNUNET_break_op (0);
      hr.http_status = 0;
      hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == lh->link_cb);
    TALER_EXCHANGE_link_cancel (lh);
    return;
  case MHD_HTTP_BAD_REQUEST:
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says this coin was not melted; we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange link\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != lh->link_cb)
    lh->link_cb (lh->link_cb_cls,
                 &hr,
                 0,
                 NULL,
                 NULL,
                 NULL);
  TALER_EXCHANGE_link_cancel (lh);
}


struct TALER_EXCHANGE_LinkHandle *
TALER_EXCHANGE_link (struct TALER_EXCHANGE_Handle *exchange,
                     const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                     TALER_EXCHANGE_LinkCallback link_cb,
                     void *link_cb_cls)
{
  struct TALER_EXCHANGE_LinkHandle *lh;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
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
                     "/coins/%s/link",
                     pub_str);
  }
  lh = GNUNET_new (struct TALER_EXCHANGE_LinkHandle);
  lh->exchange = exchange;
  lh->link_cb = link_cb;
  lh->link_cb_cls = link_cb_cls;
  lh->coin_priv = *coin_priv;
  lh->url = TEAH_path_to_url (exchange,
                              arg_str);
  if (NULL == lh->url)
  {
    GNUNET_free (lh);
    return NULL;
  }
  eh = TALER_EXCHANGE_curl_easy_get_ (lh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (lh->url);
    GNUNET_free (lh);
    return NULL;
  }
  ctx = TEAH_handle_to_context (exchange);
  lh->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                              eh,
                                              &handle_link_finished,
                                              lh);
  return lh;
}


void
TALER_EXCHANGE_link_cancel (struct TALER_EXCHANGE_LinkHandle *lh)
{
  if (NULL != lh->job)
  {
    GNUNET_CURL_job_cancel (lh->job);
    lh->job = NULL;
  }
  GNUNET_free (lh->url);
  GNUNET_free (lh);
}


/* end of exchange_api_link.c */
