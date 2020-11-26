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
 * @file lib/exchange_api_management_get_keys.c
 * @brief functions to obtain future online keys of the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_json_lib.h"

/**
 * @brief Handle for a GET /management/keys request.
 */
struct TALER_EXCHANGE_ManagementGetKeysHandle
{

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
  TALER_EXCHANGE_ManagementGetKeysCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Reference to the execution context.
   */
  struct GNUNET_CURL_Context *ctx;
};


/**
 * Handle the case that the response was of type #MHD_HTTP_OK.
 *
 * @param[in,out] gh request handle
 * @param response the response
 * @return #MHD_OK if the response was well-formed
 */
static int
handle_ok (struct TALER_EXCHANGE_ManagementGetKeysHandle *gh,
           const json_t *response)
{
  struct TALER_EXCHANGE_FutureKeys fk;
  json_t *sk;
  json_t *dk;
  bool ok;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("future_denoms",
                           &dk),
    GNUNET_JSON_spec_json ("future_signkeys",
                           &sk),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &fk.master_pub),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_public_key",
                                 &fk.denom_secmod_public_key),
    GNUNET_JSON_spec_fixed_auto ("signkey_secmod_public_key",
                                 &fk.signkey_secmod_public_key),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (response,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  fk.num_sign_keys = json_array_size (sk);
  fk.num_denom_keys = json_array_size (dk);
  fk.sign_keys = GNUNET_new_array (
    fk.num_sign_keys,
    struct TALER_EXCHANGE_FutureSigningPublicKey);
  fk.denom_keys = GNUNET_new_array (
    fk.num_denom_keys,
    struct TALER_EXCHANGE_FutureDenomPublicKey);
  ok = true;
  for (unsigned int i = 0; i<fk.num_sign_keys; i++)
  {
    json_t *j = json_array_get (sk,
                                i);
    struct TALER_EXCHANGE_FutureSigningPublicKey *sign_key
      = &fk.sign_keys[i];
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("key",
                                   &sign_key->key),
      GNUNET_JSON_spec_fixed_auto ("signkey_secmod_sig",
                                   &sign_key->signkey_secmod_sig),
      TALER_JSON_spec_absolute_time ("stamp_start",
                                     &sign_key->valid_from),
      TALER_JSON_spec_absolute_time ("stamp_expire",
                                     &sign_key->valid_until),
      TALER_JSON_spec_absolute_time ("stamp_end",
                                     &sign_key->valid_legal),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (j,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      ok = false;
      break;
    }
    {
      struct GNUNET_TIME_Relative duration
        = GNUNET_TIME_absolute_get_difference (sign_key->valid_from,
                                               sign_key->valid_until);
      struct TALER_SigningKeyAnnouncementPS ska = {
        .purpose.purpose = htonl (TALER_SIGNATURE_SM_SIGNING_KEY),
        .purpose.size = htonl (sizeof (ska)),
        .exchange_pub = sign_key->key,
        .anchor_time = GNUNET_TIME_absolute_hton (sign_key->valid_from),
        .duration = GNUNET_TIME_relative_hton (duration)
      };

      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_SM_SIGNING_KEY,
            &ska,
            &sign_key->signkey_secmod_sig.eddsa_signature,
            &fk.signkey_secmod_public_key.eddsa_pub))
      {
        GNUNET_break_op (0);
        ok = false;
        break;
      }
    }
  }
  for (unsigned int i = 0; i<fk.num_denom_keys; i++)
  {
    json_t *j = json_array_get (dk,
                                i);
    struct TALER_EXCHANGE_FutureDenomPublicKey *denom_key
      = &fk.denom_keys[i];
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("denom_secmod_sig",
                                   &denom_key->denom_secmod_sig),
      TALER_JSON_spec_absolute_time ("stamp_expire_deposit",
                                     &denom_key->expire_deposit),
      TALER_JSON_spec_absolute_time ("stamp_expire_withdraw",
                                     &denom_key->withdraw_valid_until),
      TALER_JSON_spec_absolute_time ("stamp_start",
                                     &denom_key->valid_from),
      TALER_JSON_spec_absolute_time ("stamp_expire_legal",
                                     &denom_key->expire_legal),
      TALER_JSON_spec_amount ("value",
                              &denom_key->value),
      TALER_JSON_spec_amount ("fee_withdraw",
                              &denom_key->fee_withdraw),
      TALER_JSON_spec_amount ("fee_deposit",
                              &denom_key->fee_deposit),
      TALER_JSON_spec_amount ("fee_refresh",
                              &denom_key->fee_refresh),
      TALER_JSON_spec_amount ("fee_refund",
                              &denom_key->fee_refund),
      GNUNET_JSON_spec_rsa_public_key ("denom_pub",
                                       &denom_key->key.rsa_public_key),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (j,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      ok = false;
      break;
    }

    {
      struct GNUNET_TIME_Relative duration
        = GNUNET_TIME_absolute_get_difference (denom_key->valid_from,
                                               denom_key->withdraw_valid_until);
      struct TALER_DenominationKeyAnnouncementPS dka = {
        .purpose.purpose = htonl (TALER_SIGNATURE_SM_DENOMINATION_KEY),
        .purpose.size = htonl (sizeof (dka)),
        .anchor_time = GNUNET_TIME_absolute_hton (denom_key->valid_from),
        .duration_withdraw = GNUNET_TIME_relative_hton (duration)
      };

      GNUNET_CRYPTO_rsa_public_key_hash (denom_key->key.rsa_public_key,
                                         &dka.h_denom_pub);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_SM_DENOMINATION_KEY,
            &dka,
            &denom_key->denom_secmod_sig.eddsa_signature,
            &fk.denom_secmod_public_key.eddsa_pub))
      {
        GNUNET_break_op (0);
        ok = false;
        break;
      }
    }
  }
  if (ok)
  {
    struct TALER_EXCHANGE_HttpResponse hr = {
      .http_status = MHD_HTTP_OK,
      .reply = response
    };

    gh->cb (gh->cb_cls,
            &hr,
            &fk);
  }
  for (unsigned int i = 0; i<fk.num_denom_keys; i++)
  {
    if (NULL != fk.denom_keys[i].key.rsa_public_key)
    {
      GNUNET_CRYPTO_rsa_public_key_free (
        fk.denom_keys[i].key.rsa_public_key);
      fk.denom_keys[i].key.rsa_public_key = NULL;
    }
  }
  GNUNET_free (fk.sign_keys);
  GNUNET_free (fk.denom_keys);
  GNUNET_JSON_parse_free (spec);
  return (ok) ? GNUNET_OK : GNUNET_SYSERR;
}


/**
 * Function called when we're done processing the
 * HTTP GET /management/keys request.
 *
 * @param cls the `struct TALER_EXCHANGE_ManagementGetKeysHandle *`
 * @param response_code HTTP response code, 0 on error
 * @param response response body, NULL if not in JSON
 */
static void
handle_get_keys_finished (void *cls,
                          long response_code,
                          const void *response)
{
  struct TALER_EXCHANGE_ManagementGetKeysHandle *gh = cls;
  const json_t *json = response;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .http_status = (unsigned int) response_code,
    .reply = json
  };

  gh->job = NULL;
  switch (response_code)
  {
  case MHD_HTTP_OK:
    if (GNUNET_OK ==
        handle_ok (gh,
                   response))
    {
      gh->cb = NULL;
    }
    else
    {
      response_code = 0;
    }
    break;
  default:
    /* unexpected response code */
    GNUNET_break_op (0);
    hr.ec = TALER_JSON_get_error_code (json);
    hr.hint = TALER_JSON_get_error_hint (json);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  if (NULL != gh->cb)
  {
    gh->cb (gh->cb_cls,
            &hr,
            NULL);
    gh->cb = NULL;
  }
  TALER_EXCHANGE_get_management_keys_cancel (gh);
};


/**
 * Request future keys from the exchange.  The obtained information will be
 * passed to the @a cb.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param cb function to call with the exchange's future keys result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementGetKeysHandle *
TALER_EXCHANGE_get_management_keys (struct GNUNET_CURL_Context *ctx,
                                    const char *url,
                                    TALER_EXCHANGE_ManagementGetKeysCallback cb,
                                    void *cb_cls)
{
  struct TALER_EXCHANGE_ManagementGetKeysHandle *gh;
  CURL *eh;

  gh = GNUNET_new (struct TALER_EXCHANGE_ManagementGetKeysHandle);
  gh->cb = cb;
  gh->cb_cls = cb_cls;
  gh->ctx = ctx;
  gh->url = TALER_url_join (url,
                            "management/keys",
                            NULL);
  if (NULL == gh->url)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Could not construct request URL.\n");
    GNUNET_free (gh);
    return NULL;
  }
  eh = curl_easy_init ();
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              gh->url);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   gh->url));
  gh->job = GNUNET_CURL_job_add (ctx,
                                 eh,
                                 &handle_get_keys_finished,
                                 gh);
  if (NULL == gh->job)
  {
    TALER_EXCHANGE_get_management_keys_cancel (gh);
    return NULL;
  }
  return gh;
}


/**
 * Cancel #TALER_EXCHANGE_get_management_keys() operation.
 *
 * @param gh handle of the operation to cancel
 */
void
TALER_EXCHANGE_get_management_keys_cancel (
  struct TALER_EXCHANGE_ManagementGetKeysHandle *gh)
{
  if (NULL != gh->job)
  {
    GNUNET_CURL_job_cancel (gh->job);
    gh->job = NULL;
  }
  GNUNET_free (gh->url);
  GNUNET_free (gh);
}
