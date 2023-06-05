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
#include "exchange_api_curl_defaults.h"
#include "taler_signatures.h"
#include "taler_curl_lib.h"
#include "taler_util.h"
#include "taler_json_lib.h"

/**
 * Set to 1 for extra debug logging.
 */
#define DEBUG 0


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
 * @return #GNUNET_OK if the response was well-formed
 */
static enum GNUNET_GenericReturnValue
handle_ok (struct TALER_EXCHANGE_ManagementGetKeysHandle *gh,
           const json_t *response)
{
  struct TALER_EXCHANGE_ManagementGetKeysResponse gkr = {
    .hr.http_status = MHD_HTTP_OK,
    .hr.reply = response,
  };
  struct TALER_EXCHANGE_FutureKeys *fk
    = &gkr.details.ok.keys;
  const json_t *sk;
  const json_t *dk;
  bool ok;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("future_denoms",
                                  &dk),
    GNUNET_JSON_spec_array_const ("future_signkeys",
                                  &sk),
    GNUNET_JSON_spec_fixed_auto ("master_pub",
                                 &fk->master_pub),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_public_key",
                                 &fk->denom_secmod_public_key),
    GNUNET_JSON_spec_fixed_auto ("denom_secmod_cs_public_key",
                                 &fk->denom_secmod_cs_public_key),
    GNUNET_JSON_spec_fixed_auto ("signkey_secmod_public_key",
                                 &fk->signkey_secmod_public_key),
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
  fk->num_sign_keys = json_array_size (sk);
  fk->num_denom_keys = json_array_size (dk);
  fk->sign_keys = GNUNET_new_array (
    fk->num_sign_keys,
    struct TALER_EXCHANGE_FutureSigningPublicKey);
  fk->denom_keys = GNUNET_new_array (
    fk->num_denom_keys,
    struct TALER_EXCHANGE_FutureDenomPublicKey);
  ok = true;
  for (unsigned int i = 0; i<fk->num_sign_keys; i++)
  {
    json_t *j = json_array_get (sk,
                                i);
    struct TALER_EXCHANGE_FutureSigningPublicKey *sign_key
      = &fk->sign_keys[i];
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_fixed_auto ("key",
                                   &sign_key->key),
      GNUNET_JSON_spec_fixed_auto ("signkey_secmod_sig",
                                   &sign_key->signkey_secmod_sig),
      GNUNET_JSON_spec_timestamp ("stamp_start",
                                  &sign_key->valid_from),
      GNUNET_JSON_spec_timestamp ("stamp_expire",
                                  &sign_key->valid_until),
      GNUNET_JSON_spec_timestamp ("stamp_end",
                                  &sign_key->valid_legal),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (j,
                           ispec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      ok = false;
      break;
    }
    {
      struct GNUNET_TIME_Relative duration
        = GNUNET_TIME_absolute_get_difference (sign_key->valid_from.abs_time,
                                               sign_key->valid_until.abs_time);

      if (GNUNET_OK !=
          TALER_exchange_secmod_eddsa_verify (
            &sign_key->key,
            sign_key->valid_from,
            duration,
            &fk->signkey_secmod_public_key,
            &sign_key->signkey_secmod_sig))
      {
        GNUNET_break_op (0);
        ok = false;
        break;
      }
    }
  }
  for (unsigned int i = 0; i<fk->num_denom_keys; i++)
  {
    json_t *j = json_array_get (dk,
                                i);
    struct TALER_EXCHANGE_FutureDenomPublicKey *denom_key
      = &fk->denom_keys[i];
    const char *section_name;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_amount_any ("value",
                                  &denom_key->value),
      GNUNET_JSON_spec_timestamp ("stamp_start",
                                  &denom_key->valid_from),
      GNUNET_JSON_spec_timestamp ("stamp_expire_withdraw",
                                  &denom_key->withdraw_valid_until),
      GNUNET_JSON_spec_timestamp ("stamp_expire_deposit",
                                  &denom_key->expire_deposit),
      GNUNET_JSON_spec_timestamp ("stamp_expire_legal",
                                  &denom_key->expire_legal),
      TALER_JSON_spec_denom_pub ("denom_pub",
                                 &denom_key->key),
      TALER_JSON_spec_amount_any ("fee_withdraw",
                                  &denom_key->fee_withdraw),
      TALER_JSON_spec_amount_any ("fee_deposit",
                                  &denom_key->fee_deposit),
      TALER_JSON_spec_amount_any ("fee_refresh",
                                  &denom_key->fee_refresh),
      TALER_JSON_spec_amount_any ("fee_refund",
                                  &denom_key->fee_refund),
      GNUNET_JSON_spec_fixed_auto ("denom_secmod_sig",
                                   &denom_key->denom_secmod_sig),
      GNUNET_JSON_spec_string ("section_name",
                               &section_name),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (j,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
#if DEBUG
      json_dumpf (j,
                  stderr,
                  JSON_INDENT (2));
#endif
      ok = false;
      break;
    }

    {
      struct TALER_DenominationHashP h_denom_pub;
      struct GNUNET_TIME_Relative duration
        = GNUNET_TIME_absolute_get_difference (
            denom_key->valid_from.abs_time,
            denom_key->withdraw_valid_until.abs_time);

      TALER_denom_pub_hash (&denom_key->key,
                            &h_denom_pub);
      switch (denom_key->key.cipher)
      {
      case TALER_DENOMINATION_RSA:
        {
          struct TALER_RsaPubHashP h_rsa;

          TALER_rsa_pub_hash (denom_key->key.details.rsa_public_key,
                              &h_rsa);
          if (GNUNET_OK !=
              TALER_exchange_secmod_rsa_verify (&h_rsa,
                                                section_name,
                                                denom_key->valid_from,
                                                duration,
                                                &fk->denom_secmod_public_key,
                                                &denom_key->denom_secmod_sig))
          {
            GNUNET_break_op (0);
            ok = false;
            break;
          }
        }
        break;
      case TALER_DENOMINATION_CS:
        {
          struct TALER_CsPubHashP h_cs;

          TALER_cs_pub_hash (&denom_key->key.details.cs_public_key,
                             &h_cs);
          if (GNUNET_OK !=
              TALER_exchange_secmod_cs_verify (&h_cs,
                                               section_name,
                                               denom_key->valid_from,
                                               duration,
                                               &fk->denom_secmod_cs_public_key,
                                               &denom_key->denom_secmod_sig))
          {
            GNUNET_break_op (0);
            ok = false;
            break;
          }
        }
        break;
      default:
        GNUNET_break_op (0);
        ok = false;
        break;
      }
    }
    if (! ok)
      break;
  }
  if (ok)
  {
    gh->cb (gh->cb_cls,
            &gkr);
  }
  for (unsigned int i = 0; i<fk->num_denom_keys; i++)
    TALER_denom_pub_free (&fk->denom_keys[i].key);
  GNUNET_free (fk->sign_keys);
  GNUNET_free (fk->denom_keys);
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
  struct TALER_EXCHANGE_ManagementGetKeysResponse gkr = {
    .hr.http_status = (unsigned int) response_code,
    .hr.reply = json
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
    if (NULL != json)
    {
      gkr.hr.ec = TALER_JSON_get_error_code (json);
      gkr.hr.hint = TALER_JSON_get_error_hint (json);
    }
    else
    {
      gkr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      gkr.hr.hint = TALER_ErrorCode_get_hint (gkr.hr.ec);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange management get keys\n",
                (unsigned int) response_code,
                (int) gkr.hr.ec);
    break;
  }
  if (NULL != gh->cb)
  {
    gh->cb (gh->cb_cls,
            &gkr);
    gh->cb = NULL;
  }
  TALER_EXCHANGE_get_management_keys_cancel (gh);
};


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
  eh = TALER_EXCHANGE_curl_easy_get_ (gh->url);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting URL '%s'\n",
              gh->url);
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
