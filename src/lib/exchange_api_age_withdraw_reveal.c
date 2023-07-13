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
 * @file lib/exchange_api_age_withdraw_reveal.c
 * @brief Implementation of /age-withdraw/$ACH/reveal requests
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

/**
 * Handler for a running age-withdraw-reveal  request
 */
struct TALER_EXCHANGE_AgeWithdrawRevealHandle
{

  /* The index not to be disclosed */
  uint8_t noreveal_index;

  /* The age-withdraw commitment */
  struct TALER_AgeWithdrawCommitmentHashP h_commitment;

  /* Number of coins */
  size_t num_coins;

  /* The n*kappa coin secrets from the age-withdraw commitment */
  const struct TALER_EXCHANGE_AgeWithdrawCoinInput *coins_input;

  /* The curl context for the request */
  struct GNUNET_CURL_Context *curl_ctx;

  /* The url for the reveal request */
  const char *request_url;

  /**
   * CURL handle for the request job.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Post Context
   */
  struct TALER_CURL_PostContext post_ctx;

  /* Callback */
  TALER_EXCHANGE_AgeWithdrawRevealCallback callback;

  /* Reveal */
  void *callback_cls;
};


/**
 * We got a 200 OK response for the /age-withdraw/$ACH/reveal operation.
 * Extract the signed blindedcoins and return it to the caller.
 *
 * @param awrh operation handle
 * @param j_response reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static enum GNUNET_GenericReturnValue
age_withdraw_reveal_ok (
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh,
  const json_t *j_response)
{
  struct TALER_EXCHANGE_AgeWithdrawRevealResponse response = {
    .hr.reply = j_response,
    .hr.http_status = MHD_HTTP_OK,
    .details.ok.num_coins = awrh->num_coins
  };
  const json_t *j_sigs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("ev_sigs",
                                  &j_sigs),
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

  if (awrh->num_coins != json_array_size (j_sigs))
  {
    /* Number of coins generated does not match our expectation */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  for (size_t n = 0; n < awrh->num_coins; n++)
  {
    // TODO[oec] extract the individual coins.
  }

  awrh->callback (awrh->callback_cls,
                  &response);
  /* make sure the callback isn't called again */
  awrh->callback = NULL;

  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /age-withdraw/$ACH/reveal request.
 *
 * @param cls the `struct TALER_EXCHANGE_AgeWithdrawRevealHandle`
 * @param response_code The HTTP response code
 * @param response response data
 */
static void
handle_age_withdraw_reveal_finished (
  void *cls,
  long response_code,
  const void *response)
{
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh = cls;
  const json_t *j_response = response;
  struct TALER_EXCHANGE_AgeWithdrawRevealResponse awr = {
    .hr.reply = j_response,
    .hr.http_status = (unsigned int) response_code
  };

  awrh->job = NULL;
  switch (response_code)
  {
  case 0:
    awr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        age_withdraw_reveal_ok (awrh,
                                j_response))
    {
      GNUNET_break_op (0);
      awr.hr.http_status = 0;
      awr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    GNUNET_assert (NULL == awrh->callback);
    TALER_EXCHANGE_age_withdraw_reveal_cancel (awrh);
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
    /**
     * This should never happen, as we don't sent any signatures
     * to the exchange to verify.  We should simply pass the JSON reply
     * to the application
     **/
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
       that it doesn't know this age-withraw commitment. */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
    break;
  case MHD_HTTP_CONFLICT:
    /* An age commitment for one of the coins did not fulfill
     * the required maximum age requirement of the corresponding
     * reserve.
     * Error code: TALER_EC_EXCHANGE_GENERIC_COIN_AGE_REQUIREMENT_FAILURE.
     */
    awr.hr.ec = TALER_JSON_get_error_code (j_response);
    awr.hr.hint = TALER_JSON_get_error_hint (j_response);
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
  awrh->callback (awrh->callback_cls,
                  &awr);
  TALER_EXCHANGE_age_withdraw_reveal_cancel (awrh);
}


/**
 * Prepares the request URL for the age-withdraw-reveal request
 *
 * @param exchange_url The base-URL to the exchange
 * @param[in,out] awrh The handler
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise
 */
static
enum GNUNET_GenericReturnValue
prepare_url (
  const char *exchange_url,
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh)
{
  char arg_str[sizeof (struct TALER_AgeWithdrawCommitmentHashP) * 2 + 32];
  char pub_str[sizeof (struct TALER_AgeWithdrawCommitmentHashP) * 2];
  char *end;

  end = GNUNET_STRINGS_data_to_string (&awrh->h_commitment,
                                       sizeof (awrh->h_commitment),
                                       pub_str,
                                       sizeof (pub_str));
  *end = '\0';
  GNUNET_snprintf (arg_str,
                   sizeof (arg_str),
                   "age-withraw/%s/reveal",
                   pub_str);

  awrh->request_url = TALER_url_join (exchange_url,
                                      arg_str,
                                      NULL);
  if (NULL == awrh->request_url)
  {
    GNUNET_break (0);
    TALER_EXCHANGE_age_withdraw_reveal_cancel (awrh);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Call /age-withdraw/$ACH/reveal
 *
 * @param awrh The handler
 * @param num_coins Number of coin candidates in reveal_inputs
 * @param reveal_inputs The secrets of the coin candidates
 */
static
void
perform_protocol (
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh)
{
  CURL *curlh = NULL;
  json_t *j_request_body = NULL;
  json_t *j_array_of_secrets = NULL;
  json_t *j_secrets = NULL;
  json_t *j_sec = NULL;

#define FAIL_IF(cond) \
  do { \
    if ((cond)) \
    { \
      GNUNET_break (! (cond)); \
      goto ERROR; \
    } \
  } while(0)

  for (size_t n = 0; n < awrh->num_coins; n++)
  {
    const struct TALER_PlanchetMasterSecretP *secrets =
      awrh->coins_input[n].secrets;

    j_secrets = json_array ();
    FAIL_IF (NULL == j_secrets);

    for (uint8_t k = 0; k < TALER_CNC_KAPPA; k++)
    {
      const struct TALER_PlanchetMasterSecretP *secret = &secrets[k];
      if (awrh->noreveal_index == k)
        continue;

      j_sec = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto (NULL, secret));

      FAIL_IF (NULL == j_sec);
      FAIL_IF (0 < json_array_append_new (j_secrets,
                                          j_sec));
    }

    FAIL_IF (0 < json_array_append_new (j_array_of_secrets,
                                        j_secrets));
  }
  j_request_body = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_array_steal ("disclosed_coin_secrets",
                                  j_array_of_secrets));
  FAIL_IF (NULL == j_request_body);

  curlh = TALER_EXCHANGE_curl_easy_get_ (awrh->request_url);
  FAIL_IF (NULL == curlh);
  FAIL_IF (GNUNET_OK !=
           TALER_curl_easy_post (&awrh->post_ctx,
                                 curlh,
                                 j_request_body));
  json_decref (j_request_body);
  j_request_body = NULL;

  awrh->job = GNUNET_CURL_job_add2 (awrh->curl_ctx,
                                    curlh,
                                    awrh->post_ctx.headers,
                                    &handle_age_withdraw_reveal_finished,
                                    awrh);
  FAIL_IF (NULL == awrh->job);

  /* No error, return */
  return;

ERROR:
  if (NULL != j_sec)
    json_decref (j_sec);
  if (NULL != j_secrets)
    json_decref (j_secrets);
  if (NULL != j_array_of_secrets)
    json_decref (j_array_of_secrets);
  if (NULL != j_request_body)
    json_decref (j_request_body);
  if (NULL != curlh)
    curl_easy_cleanup (curlh);
  TALER_EXCHANGE_age_withdraw_reveal_cancel (awrh);
  return;
#undef FAIL_IF
}


struct TALER_EXCHANGE_AgeWithdrawRevealHandle *
TALER_EXCHANGE_age_withdraw_reveal (
  struct GNUNET_CURL_Context *curl_ctx,
  const char *exchange_url,
  size_t num_coins,
  const struct TALER_EXCHANGE_AgeWithdrawCoinInput coins_input[static
                                                               num_coins],
  uint8_t noreveal_index,
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  TALER_EXCHANGE_AgeWithdrawRevealCallback reveal_cb,
  void *reveal_cb_cls)
{
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh =
    GNUNET_new (struct TALER_EXCHANGE_AgeWithdrawRevealHandle);
  awrh->curl_ctx = curl_ctx;
  awrh->noreveal_index = noreveal_index;
  awrh->callback = reveal_cb;
  awrh->callback_cls = reveal_cb_cls;
  awrh->h_commitment = *h_commitment;
  awrh->num_coins = num_coins;
  awrh->coins_input = coins_input;


  if (GNUNET_OK !=
      prepare_url (exchange_url,
                   awrh))
    return NULL;

  perform_protocol (awrh);

  return awrh;
}


void
TALER_EXCHANGE_age_withdraw_reveal_cancel (
  struct TALER_EXCHANGE_AgeWithdrawRevealHandle *awrh)
{
  /* FIXME[oec] */
  (void) awrh;
}


/* exchange_api_age_withdraw_reveal.c */
