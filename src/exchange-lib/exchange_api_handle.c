/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file exchange-lib/exchange_api_handle.c
 * @brief Implementation of the "handle" component of the exchange's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "taler_signatures.h"
#include "exchange_api_handle.h"


/**
 * Log error related to CURL operations.
 *
 * @param type log level
 * @param function which function failed to run
 * @param code what was the curl error code
 */
#define CURL_STRERROR(type, function, code)      \
 GNUNET_log (type, "Curl function `%s' has failed at `%s:%d' with error: %s", \
             function, __FILE__, __LINE__, curl_easy_strerror (code));


/**
 * Stages of initialization for the `struct TALER_EXCHANGE_Handle`
 */
enum ExchangeHandleState
{
  /**
   * Just allocated.
   */
  MHS_INIT = 0,

  /**
   * Obtained the exchange's certification data and keys.
   */
  MHS_CERT = 1,

  /**
   * Failed to initialize (fatal).
   */
  MHS_FAILED = 2
};


/**
 * Data for the request to get the /keys of a exchange.
 */
struct KeysRequest;


/**
 * Handle to the exchange
 */
struct TALER_EXCHANGE_Handle
{
  /**
   * The context of this handle
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * The URL of the exchange (i.e. "http://exchange.taler.net/")
   */
  char *url;

  /**
   * Function to call with the exchange's certification data,
   * NULL if this has already been done.
   */
  TALER_EXCHANGE_CertificationCallback cert_cb;

  /**
   * Closure to pass to @e cert_cb.
   */
  void *cert_cb_cls;

  /**
   * Data for the request to get the /keys of a exchange,
   * NULL once we are past stage #MHS_INIT.
   */
  struct KeysRequest *kr;

  /**
   * Key data of the exchange, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  struct TALER_EXCHANGE_Keys key_data;

  /**
   * When does @e key_data expire?
   */
  struct GNUNET_TIME_Absolute key_data_expiration;

  /**
   * Raw key data of the exchange, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  json_t *key_data_raw;

  /**
   * Stage of the exchange's initialization routines.
   */
  enum ExchangeHandleState state;

};


/* ***************** Internal /keys fetching ************* */

/**
 * Data for the request to get the /keys of a exchange.
 */
struct KeysRequest
{
  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this handle
   */
  char *url;

  /**
   * Entry for this request with the `struct GNUNET_CURL_Context`.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Expiration time according to "Expire:" header.
   * 0 if not provided by the server.
   */
  struct GNUNET_TIME_Absolute expire;

};


/**
 * Release memory occupied by a keys request.
 * Note that this does not cancel the request
 * itself.
 *
 * @param kr request to free
 */
static void
free_keys_request (struct KeysRequest *kr)
{
  GNUNET_free (kr->url);
  GNUNET_free (kr);
}


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


/**
 * Parse a exchange's signing key encoded in JSON.
 *
 * @param[out] sign_key where to return the result
 * @param[in] sign_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_signkey (struct TALER_EXCHANGE_SigningPublicKey *sign_key,
                    json_t *sign_key_obj,
                    const struct TALER_MasterPublicKeyP *master_key)
{
  struct TALER_ExchangeSigningKeyValidityPS sign_key_issue;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute valid_until;
  struct GNUNET_TIME_Absolute valid_legal;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("key",
                                 &sign_key_issue.signkey_pub),
    GNUNET_JSON_spec_absolute_time ("stamp_start",
                                    &valid_from),
    GNUNET_JSON_spec_absolute_time ("stamp_expire",
                                    &valid_until),
    GNUNET_JSON_spec_absolute_time ("stamp_end",
                                    &valid_legal),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (sign_key_obj,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  sign_key_issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  sign_key_issue.purpose.size =
    htonl (sizeof (struct TALER_ExchangeSigningKeyValidityPS)
           - offsetof (struct TALER_ExchangeSigningKeyValidityPS,
                       purpose));
  sign_key_issue.master_public_key = *master_key;
  sign_key_issue.start = GNUNET_TIME_absolute_hton (valid_from);
  sign_key_issue.expire = GNUNET_TIME_absolute_hton (valid_until);
  sign_key_issue.end = GNUNET_TIME_absolute_hton (valid_legal);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                  &sign_key_issue.purpose,
                                  &sig,
                                  &master_key->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  sign_key->valid_from = valid_from;
  sign_key->valid_until = valid_until;
  sign_key->key = sign_key_issue.signkey_pub;
  return GNUNET_OK;
}


/**
 * Parse a exchange's denomination key encoded in JSON.
 *
 * @param[out] denom_key where to return the result
 * @param[in] denom_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @param hash_context where to accumulate data for signature verification
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_denomkey (struct TALER_EXCHANGE_DenomPublicKey *denom_key,
                     json_t *denom_key_obj,
                     struct TALER_MasterPublicKeyP *master_key,
                     struct GNUNET_HashContext *hash_context)
{
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute withdraw_valid_until;
  struct GNUNET_TIME_Absolute expire_deposit;
  struct GNUNET_TIME_Absolute expire_legal;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct TALER_Amount fee_refund;
  struct TALER_DenominationKeyValidityPS denom_key_issue;
  struct GNUNET_CRYPTO_RsaPublicKey *pk;
  struct GNUNET_CRYPTO_EddsaSignature sig;

  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
				 &sig),
    GNUNET_JSON_spec_absolute_time ("stamp_expire_deposit",
				    &expire_deposit),
    GNUNET_JSON_spec_absolute_time ("stamp_expire_withdraw",
				    &withdraw_valid_until),
    GNUNET_JSON_spec_absolute_time ("stamp_start",
				    &valid_from),
    GNUNET_JSON_spec_absolute_time ("stamp_expire_legal",
				    &expire_legal),
    TALER_JSON_spec_amount ("value",
			    &value),
    TALER_JSON_spec_amount ("fee_withdraw",
			    &fee_withdraw),
    TALER_JSON_spec_amount ("fee_deposit",
			    &fee_deposit),
    TALER_JSON_spec_amount ("fee_refresh",
			    &fee_refresh),
    TALER_JSON_spec_amount ("fee_refund",
			    &fee_refund),
    GNUNET_JSON_spec_rsa_public_key ("denom_pub",
                             &pk),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (denom_key_obj,
                         spec, NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  memset (&denom_key_issue, 0, sizeof (denom_key_issue));
  GNUNET_CRYPTO_rsa_public_key_hash (pk,
                                     &denom_key_issue.denom_hash);
  denom_key_issue.purpose.purpose
    = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  denom_key_issue.purpose.size
    = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
  denom_key_issue.master = *master_key;
  denom_key_issue.start = GNUNET_TIME_absolute_hton (valid_from);
  denom_key_issue.expire_withdraw = GNUNET_TIME_absolute_hton (withdraw_valid_until);
  denom_key_issue.expire_deposit = GNUNET_TIME_absolute_hton (expire_deposit);
  denom_key_issue.expire_legal = GNUNET_TIME_absolute_hton (expire_legal);
  TALER_amount_hton (&denom_key_issue.value,
                     &value);
  TALER_amount_hton (&denom_key_issue.fee_withdraw,
                     &fee_withdraw);
  TALER_amount_hton (&denom_key_issue.fee_deposit,
                     &fee_deposit);
  TALER_amount_hton (&denom_key_issue.fee_refresh,
                     &fee_refresh);
  TALER_amount_hton (&denom_key_issue.fee_refund,
                     &fee_refund);
  EXITIF (GNUNET_SYSERR ==
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
                                      &denom_key_issue.purpose,
                                      &sig,
                                      &master_key->eddsa_pub));
  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   &denom_key_issue.denom_hash,
                                   sizeof (struct GNUNET_HashCode));
  denom_key->key.rsa_public_key = pk;
  denom_key->h_key = denom_key_issue.denom_hash;
  denom_key->valid_from = valid_from;
  denom_key->withdraw_valid_until = withdraw_valid_until;
  denom_key->expire_deposit = expire_deposit;
  denom_key->expire_legal = expire_legal;
  denom_key->value = value;
  denom_key->fee_withdraw = fee_withdraw;
  denom_key->fee_deposit = fee_deposit;
  denom_key->fee_refresh = fee_refresh;
  denom_key->fee_refund = fee_refund;
  return GNUNET_OK;

 EXITIF_exit:
  GNUNET_JSON_parse_free (spec);
  return GNUNET_SYSERR;
}


/**
 * Parse a exchange's auditor information encoded in JSON.
 *
 * @param[out] auditor where to return the result
 * @param[in] auditor_obj json to parse
 * @param key_data information about denomination keys
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_auditor (struct TALER_EXCHANGE_AuditorInformation *auditor,
                    json_t *auditor_obj,
                    const struct TALER_EXCHANGE_Keys *key_data)
{
  json_t *keys;
  json_t *key;
  unsigned int len;
  unsigned int off;
  unsigned int i;
  const char *auditor_url;
  struct TALER_ExchangeKeyValidityPS kv;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("auditor_pub",
                                 &auditor->auditor_pub),
    GNUNET_JSON_spec_string ("auditor_url",
                             &auditor_url),
    GNUNET_JSON_spec_json ("denomination_keys",
                           &keys),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (auditor_obj,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  auditor->auditor_url = GNUNET_strdup (auditor_url);
  kv.purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS);
  kv.purpose.size = htonl (sizeof (struct TALER_ExchangeKeyValidityPS));
  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &kv.auditor_url_hash);
  kv.master = key_data->master_pub;
  len = json_array_size (keys);
  auditor->denom_keys = GNUNET_new_array (len,
                                          const struct TALER_EXCHANGE_DenomPublicKey *);
  i = 0;
  off = 0;
  json_array_foreach (keys, i, key) {
    struct TALER_AuditorSignatureP auditor_sig;
    struct GNUNET_HashCode denom_h;
    const struct TALER_EXCHANGE_DenomPublicKey *dk;
    unsigned int j;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("denom_pub_h",
                           &denom_h),
      GNUNET_JSON_spec_fixed_auto ("auditor_sig",
                           &auditor_sig),
      GNUNET_JSON_spec_end()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (key,
                           spec,
                           NULL, NULL))
      {
      GNUNET_break_op (0);
      continue;
    }
    dk = NULL;
    for (j=0;j<key_data->num_denom_keys;j++)
    {
      if (0 == memcmp (&denom_h,
                       &key_data->denom_keys[j].h_key,
                       sizeof (struct GNUNET_HashCode)))
      {
        dk = &key_data->denom_keys[j];
        break;
      }
    }
    if (NULL == dk)
    {
      GNUNET_break_op (0);
      continue;
    }
    kv.start = GNUNET_TIME_absolute_hton (dk->valid_from);
    kv.expire_withdraw = GNUNET_TIME_absolute_hton (dk->withdraw_valid_until);
    kv.expire_deposit = GNUNET_TIME_absolute_hton (dk->expire_deposit);
    kv.expire_legal = GNUNET_TIME_absolute_hton (dk->expire_legal);
    TALER_amount_hton (&kv.value,
                       &dk->value);
    TALER_amount_hton (&kv.fee_withdraw,
                       &dk->fee_withdraw);
    TALER_amount_hton (&kv.fee_deposit,
                       &dk->fee_deposit);
    TALER_amount_hton (&kv.fee_refresh,
                       &dk->fee_refresh);
    TALER_amount_hton (&kv.fee_refund,
                       &dk->fee_refund);
    kv.denom_hash = dk->h_key;
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS,
                                    &kv.purpose,
                                    &auditor_sig.eddsa_sig,
                                    &auditor->auditor_pub.eddsa_pub))
    {
      GNUNET_break_op (0);
      continue;
    }
    auditor->denom_keys[off] = dk;
    off++;
  }
  auditor->num_denom_keys = off;
  return GNUNET_OK;
}


/**
 * Decode the JSON in @a resp_obj from the /keys response and store the data
 * in the @a key_data.
 *
 * @param[in] resp_obj JSON object to parse
 * @param[out] key_data where to store the results we decoded
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error (malformed JSON)
 */
static int
decode_keys_json (const json_t *resp_obj,
                  struct TALER_EXCHANGE_Keys *key_data)
{
  struct GNUNET_TIME_Absolute list_issue_date;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_ExchangeKeySetPS ks;
  struct GNUNET_HashContext *hash_context;
  struct TALER_ExchangePublicKeyP pub;

  memset (key_data, 0, sizeof (struct TALER_EXCHANGE_Keys));
  if (JSON_OBJECT != json_typeof (resp_obj))
    return GNUNET_SYSERR;

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  /* parse the master public key and issue date of the response */
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto ("master_public_key",
                                   &key_data->master_pub),
      GNUNET_JSON_spec_fixed_auto ("eddsa_sig",
                                   &sig),
      GNUNET_JSON_spec_fixed_auto ("eddsa_pub",
                                   &pub),
      GNUNET_JSON_spec_absolute_time ("list_issue_date",
                                      &list_issue_date),
      GNUNET_JSON_spec_end()
    };

    EXITIF (GNUNET_OK !=
            GNUNET_JSON_parse (resp_obj,
                               spec,
                               NULL, NULL));
  }

  /* parse the signing keys */
  {
    json_t *sign_keys_array;
    json_t *sign_key_obj;
    unsigned int index;

    EXITIF (NULL == (sign_keys_array =
                     json_object_get (resp_obj,
                                      "signkeys")));
    EXITIF (JSON_ARRAY != json_typeof (sign_keys_array));
    EXITIF (0 == (key_data->num_sign_keys =
                  json_array_size (sign_keys_array)));
    key_data->sign_keys
      = GNUNET_new_array (key_data->num_sign_keys,
                          struct TALER_EXCHANGE_SigningPublicKey);
    index = 0;
    json_array_foreach (sign_keys_array, index, sign_key_obj) {
      EXITIF (GNUNET_SYSERR ==
              parse_json_signkey (&key_data->sign_keys[index],
                                  sign_key_obj,
                                  &key_data->master_pub));
    }
  }

  /* parse the denomination keys */
  {
    json_t *denom_keys_array;
    json_t *denom_key_obj;
    unsigned int index;

    EXITIF (NULL == (denom_keys_array =
                     json_object_get (resp_obj, "denoms")));
    EXITIF (JSON_ARRAY != json_typeof (denom_keys_array));
    if (0 == (key_data->num_denom_keys = json_array_size (denom_keys_array)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Found no denomination keys at this exchange\n");
      goto EXITIF_exit;
    }
    key_data->denom_keys = GNUNET_new_array (key_data->num_denom_keys,
                                             struct TALER_EXCHANGE_DenomPublicKey);
    index = 0;
    json_array_foreach (denom_keys_array, index, denom_key_obj) {
      EXITIF (GNUNET_SYSERR ==
              parse_json_denomkey (&key_data->denom_keys[index],
                                   denom_key_obj,
                                   &key_data->master_pub,
                                   hash_context));
    }
  }

  /* parse the auditor information */
  {
    json_t *auditors_array;
    json_t *auditor_info;
    unsigned int len;
    unsigned int index;

    EXITIF (NULL == (auditors_array =
                     json_object_get (resp_obj, "auditors")));
    EXITIF (JSON_ARRAY != json_typeof (auditors_array));
    len = json_array_size (auditors_array);
    if (0 != len)
    {
      key_data->auditors = GNUNET_new_array (len,
                                             struct TALER_EXCHANGE_AuditorInformation);
      index = 0;
      json_array_foreach (auditors_array, index, auditor_info) {
        EXITIF (GNUNET_SYSERR ==
                parse_json_auditor (&key_data->auditors[index],
                                    auditor_info,
                                    key_data));
      }
    }
  }

  /* Validate signature... */
  ks.purpose.size = htonl (sizeof (ks));
  ks.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET);
  ks.list_issue_date = GNUNET_TIME_absolute_hton (list_issue_date);
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &ks.hc);
  hash_context = NULL;
  EXITIF (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_data,
                                       &pub));
  EXITIF (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_KEY_SET,
                                      &ks.purpose,
                                      &sig.eddsa_signature,
                                      &pub.eddsa_pub));
  return GNUNET_OK;
 EXITIF_exit:

  if (NULL != hash_context)
    GNUNET_CRYPTO_hash_context_abort (hash_context);
  return GNUNET_SYSERR;
}


/**
 * Free key data object.
 *
 * @param key_data data to free (pointer itself excluded)
 */
static void
free_key_data (struct TALER_EXCHANGE_Keys *key_data)
{
  unsigned int i;

  GNUNET_array_grow (key_data->sign_keys,
                     key_data->num_sign_keys,
                     0);
  for (i=0;i<key_data->num_denom_keys;i++)
    GNUNET_CRYPTO_rsa_public_key_free (key_data->denom_keys[i].key.rsa_public_key);
  GNUNET_array_grow (key_data->denom_keys,
                     key_data->num_denom_keys,
                     0);
  GNUNET_array_grow (key_data->auditors,
                     key_data->num_auditors,
                     0);
}


/**
 * Initiate download of /keys from the exchange.
 *
 * @param exchange where to download /keys from
 */
static void
request_keys (struct TALER_EXCHANGE_Handle *exchange);


/**
 * Check if our current response for /keys is valid, and if
 * not trigger download.
 *
 * @param exchange exchange to check keys for
 * @return until when the response is current, 0 if we are re-downloading
 */
struct GNUNET_TIME_Absolute
TALER_EXCHANGE_check_keys_current (struct TALER_EXCHANGE_Handle *exchange)
{
  if (NULL != exchange->kr)
    return GNUNET_TIME_UNIT_ZERO_ABS;
  if (0 < GNUNET_TIME_absolute_get_remaining (exchange->key_data_expiration).rel_value_us)
    return exchange->key_data_expiration;
  request_keys (exchange);
  return GNUNET_TIME_UNIT_ZERO_ABS;
}


/**
 * Callback used when downloading the reply to a /keys request
 * is complete.
 *
 * @param cls the `struct KeysRequest`
 * @param response_code HTTP response code, 0 on error
 * @param resp_obj parsed JSON result, NULL on error
 */
static void
keys_completed_cb (void *cls,
                   long response_code,
                   const json_t *resp_obj)
{
  struct KeysRequest *kr = cls;
  struct TALER_EXCHANGE_Handle *exchange = kr->exchange;
  struct TALER_EXCHANGE_Keys kd;
  struct TALER_EXCHANGE_Keys kd_old;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Received keys from URL `%s' with status %ld.\n",
              kr->url,
              response_code);
  kd_old = exchange->key_data;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (NULL == resp_obj)
    {
      response_code = 0;
      break;
    }
    if (GNUNET_OK !=
        decode_keys_json (resp_obj,
                          &kd))
    {
      response_code = 0;
      break;
    }
    exchange->key_data = kd;
    json_decref (exchange->key_data_raw);
    exchange->key_data_raw = json_deep_copy (resp_obj);
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    break;
  }

  if (MHD_HTTP_OK != response_code)
  {
    exchange->kr = NULL;
    free_keys_request (kr);
    exchange->state = MHS_FAILED;
    /* notify application that we failed */
    exchange->cert_cb (exchange->cert_cb_cls,
                       NULL);
    if (NULL != exchange->key_data_raw)
      {
        json_decref (exchange->key_data_raw);
        exchange->key_data_raw = NULL;
      }
    free_key_data (&kd_old);
    return;
  }

  exchange->kr = NULL;
  exchange->key_data_expiration = kr->expire;
  free_keys_request (kr);
  exchange->state = MHS_CERT;
  /* notify application about the key information */
  exchange->cert_cb (exchange->cert_cb_cls,
                     &exchange->key_data);
  free_key_data (&kd_old);
}


/* ********************* library internal API ********* */


/**
 * Get the context of a exchange.
 *
 * @param h the exchange handle to query
 * @return ctx context to execute jobs in
 */
struct GNUNET_CURL_Context *
MAH_handle_to_context (struct TALER_EXCHANGE_Handle *h)
{
  return h->ctx;
}


/**
 * Check if the handle is ready to process requests.
 *
 * @param h the exchange handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
int
MAH_handle_is_ready (struct TALER_EXCHANGE_Handle *h)
{
  return (MHS_CERT == h->state) ? GNUNET_YES : GNUNET_NO;
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param base_url base URL of the exchange (i.e. "http://exchange/")
 * @param path Taler API path (i.e. "/reserve/withdraw")
 * @return the full URI to use with cURL
 */
char *
MAH_path_to_url (struct TALER_EXCHANGE_Handle *exchange,
                 const char *path)
{
  return MAH_path_to_url2 (exchange->url,
                           path);
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param base_url base URL of the exchange (i.e. "http://exchange/")
 * @param path Taler API path (i.e. "/reserve/withdraw")
 * @return the full URI to use with cURL
 */
char *
MAH_path_to_url2 (const char *base_url,
                  const char *path)
{
  char *url;

  if ( ('/' == path[0]) &&
       (0 < strlen (base_url)) &&
       ('/' == base_url[strlen (base_url) - 1]) )
    path++; /* avoid generating URL with "//" from concat */
  GNUNET_asprintf (&url,
                   "%s%s",
                   base_url,
                   path);
  return url;
}


/**
 * Parse HTTP timestamp.
 *
 * @param date header to parse header
 * @param at where to write the result
 * @return #GNUNET_OK on success
 */
static int
parse_date_string (const char *date,
                   struct GNUNET_TIME_Absolute *at)
{
  static const char *const days[] =
    { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
  static const char *const mons[] =
    { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"  };
  struct tm now;
  time_t t;
  char day[3];
  char mon[3];
  unsigned int i;
  unsigned int mday;
  unsigned int year;
  unsigned int h;
  unsigned int m;
  unsigned int s;

  if (7 != sscanf (date,
                   "%3s, %02u %3s %04u %02u:%02u:%02u GMT",
                   day,
                   &mday,
                   mon,
                   &year,
                   &h,
                   &m,
                   &s))
    return GNUNET_SYSERR;
  memset (&now, 0, sizeof (now));
  now.tm_year = year - 1900;
  now.tm_mday = mday;
  now.tm_hour = h;
  now.tm_min = m;
  now.tm_sec = s;
  now.tm_wday = 7;
  for (i=0;i<7;i++)
    if (0 == strcasecmp (days[i], day))
      now.tm_wday = i;
  now.tm_mon = 12;
  for (i=0;i<12;i++)
    if (0 == strcasecmp (mons[i], mon))
      now.tm_mon = i;
  if ( (7 == now.tm_mday) ||
       (12 == now.tm_mon) )
    return GNUNET_SYSERR;
  t = mktime (&now);
  at->abs_value_us = 1000LL * 1000LL * t;
  return GNUNET_OK;
}


/**
 * Function called for each header in the HTTP /keys response.
 * Finds the "Expire:" header and parses it, storing the result
 * in the "expire" field fo the keys request.
 *
 * @param buffer header data received
 * @param size size of an item in @a buffer
 * @param nitems number of items in @a buffer
 * @param userdata the `struct KeysRequest`
 * @return `size * nitems` on success (everything else aborts)
 */
static size_t
header_cb (char *buffer,
           size_t size,
           size_t nitems,
           void *userdata)
{
  struct KeysRequest *kr = userdata;
  size_t total = size * nitems;
  char *val;

  if (total < strlen (MHD_HTTP_HEADER_EXPIRES ": "))
    return total;
  if (0 != strncasecmp (MHD_HTTP_HEADER_EXPIRES ": ",
                        buffer,
                        strlen (MHD_HTTP_HEADER_EXPIRES ": ")))
    return total;
  val = GNUNET_strndup (&buffer[strlen (MHD_HTTP_HEADER_EXPIRES ": ")],
                        total - strlen (MHD_HTTP_HEADER_EXPIRES ": "));
  if (GNUNET_OK !=
      parse_date_string (val,
                         &kr->expire))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to parse %s-header `%s'\n",
                MHD_HTTP_HEADER_EXPIRES,
                val);
  }
  GNUNET_free (val);
  return total;
}

/* ********************* public API ******************* */

/**
 * Initialise a connection to the exchange. Will connect to the
 * exchange and obtain information about the exchange's master public
 * key and the exchange's auditor.  The respective information will
 * be passed to the @a cert_cb once available, and all future
 * interactions with the exchange will be checked to be signed
 * (where appropriate) by the respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param cert_cb function to call with the exchange's certification information
 * @param cert_cb_cls closure for @a cert_cb
 * @param ... list of additional arguments, terminated by #TALER_EXCHANGE_OPTION_END.
 * @return the exchange handle; NULL upon error
 */
struct TALER_EXCHANGE_Handle *
TALER_EXCHANGE_connect (struct GNUNET_CURL_Context *ctx,
                        const char *url,
                        TALER_EXCHANGE_CertificationCallback cert_cb,
                        void *cert_cb_cls,
                        ...)
{
  struct TALER_EXCHANGE_Handle *exchange;

  exchange = GNUNET_new (struct TALER_EXCHANGE_Handle);
  exchange->ctx = ctx;
  exchange->url = GNUNET_strdup (url);
  exchange->cert_cb = cert_cb;
  exchange->cert_cb_cls = cert_cb_cls;
  request_keys (exchange);
  return exchange;
}


/**
 * Initiate download of /keys from the exchange.
 *
 * @param exchange where to download /keys from
 */
static void
request_keys (struct TALER_EXCHANGE_Handle *exchange)
{
  struct KeysRequest *kr;
  CURL *eh;

  GNUNET_assert (NULL == exchange->kr);
  kr = GNUNET_new (struct KeysRequest);
  kr->exchange = exchange;
  kr->url = MAH_path_to_url (exchange, "/keys");
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting keys with URL `%s'.\n",
              kr->url);
  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_VERBOSE,
                                   0));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_TIMEOUT,
                                   (long) 300));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HEADERFUNCTION,
                                   &header_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HEADERDATA,
                                   kr));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   kr->url));
  kr->job = GNUNET_CURL_job_add (exchange->ctx,
                                 eh,
                                 GNUNET_NO,
                                 &keys_completed_cb,
                                 kr);
  exchange->kr = kr;
}


/**
 * Disconnect from the exchange
 *
 * @param exchange the exchange handle
 */
void
TALER_EXCHANGE_disconnect (struct TALER_EXCHANGE_Handle *exchange)
{
  if (NULL != exchange->kr)
  {
    GNUNET_CURL_job_cancel (exchange->kr->job);
    free_keys_request (exchange->kr);
    exchange->kr = NULL;
  }
  free_key_data (&exchange->key_data);
  if (NULL != exchange->key_data_raw)
  {
    json_decref (exchange->key_data_raw);
    exchange->key_data_raw = NULL;
  }
  GNUNET_free (exchange->url);
  GNUNET_free (exchange);
}


/**
 * Test if the given @a pub is a the current signing key from the exchange
 * according to @a keys.
 *
 * @param keys the exchange's key set
 * @param pub claimed current online signing key for the exchange
 * @return #GNUNET_OK if @a pub is (according to /keys) a current signing key
 */
int
TALER_EXCHANGE_test_signing_key (const struct TALER_EXCHANGE_Keys *keys,
                                 const struct TALER_ExchangePublicKeyP *pub)
{
  struct GNUNET_TIME_Absolute now;
  unsigned int i;

  /* we will check using a tolerance of 1h for the time */
  now = GNUNET_TIME_absolute_get ();
  for (i=0;i<keys->num_sign_keys;i++)
    if ( (keys->sign_keys[i].valid_from.abs_value_us <= now.abs_value_us + 60 * 60 * 1000LL * 1000LL) &&
         (keys->sign_keys[i].valid_until.abs_value_us > now.abs_value_us - 60 * 60 * 1000LL * 1000LL) &&
         (0 == memcmp (pub,
                       &keys->sign_keys[i].key,
                       sizeof (struct TALER_ExchangePublicKeyP))) )
      return GNUNET_OK;
  return GNUNET_SYSERR;
}


/**
 * Obtain the denomination key details from the exchange.
 *
 * @param keys the exchange's key set
 * @param pk public key of the denomination to lookup
 * @return details about the given denomination key, NULL if the key is
 * not found
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key (const struct TALER_EXCHANGE_Keys *keys,
                                     const struct TALER_DenominationPublicKey *pk)
{
  unsigned int i;

  for (i=0;i<keys->num_denom_keys;i++)
    if (0 == GNUNET_CRYPTO_rsa_public_key_cmp (pk->rsa_public_key,
                                               keys->denom_keys[i].key.rsa_public_key))
      return &keys->denom_keys[i];
  return NULL;
}


/**
 * Obtain the denomination key details from the exchange.
 *
 * @param keys the exchange's key set
 * @param hc hash of the public key of the denomination to lookup
 * @return details about the given denomination key
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key_by_hash (const struct TALER_EXCHANGE_Keys *keys,
                                             const struct GNUNET_HashCode *hc)
{
  unsigned int i;

  for (i=0;i<keys->num_denom_keys;i++)
    if (0 == memcmp (hc,
                     &keys->denom_keys[i].h_key,
                     sizeof (struct GNUNET_HashCode)))
      return &keys->denom_keys[i];
  return NULL;
}


/**
 * Obtain the keys from the exchange.
 *
 * @param exchange the exchange handle
 * @return the exchange's key set
 */
const struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_get_keys (struct TALER_EXCHANGE_Handle *exchange)
{
  (void) TALER_EXCHANGE_check_keys_current (exchange);
  return &exchange->key_data;
}


/**
 * Obtain the keys from the exchange in the
 * raw JSON format
 *
 * @param exchange the exchange handle
 * @return the exchange's keys in raw JSON
 */
json_t *
TALER_EXCHANGE_get_keys_raw (struct TALER_EXCHANGE_Handle *exchange)
{
  (void) TALER_EXCHANGE_check_keys_current (exchange);
  return json_deep_copy (exchange->key_data_raw);
}



/* end of exchange_api_handle.c */
