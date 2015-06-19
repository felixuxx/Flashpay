/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file mint-lib/mint_api_handle.c
 * @brief Implementation of the "handle" component of the mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "taler_signatures.h"
#include "mint_api_context.h"
#include "mint_api_handle.h"


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
 * Print JSON parsing related error information
 */
#define JSON_WARN(error)                                                \
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                              \
                "JSON parsing failed at %s:%u: %s (%s)",                \
                __FILE__, __LINE__, error.text, error.source)

/**
 * Stages of initialization for the `struct TALER_MINT_Handle`
 */
enum MintHandleState
{
  /**
   * Just allocated.
   */
  MHS_INIT = 0,

  /**
   * Obtained the mint's certification data and keys.
   */
  MHS_CERT = 1,

  /**
   * Failed to initialize (fatal).
   */
  MHS_FAILED = 2
};


/**
 * Data for the request to get the /keys of a mint.
 */
struct KeysRequest;


/**
 * Handle to the mint
 */
struct TALER_MINT_Handle
{
  /**
   * The context of this handle
   */
  struct TALER_MINT_Context *ctx;

  /**
   * The URL of the mint (i.e. "http://mint.taler.net/")
   */
  char *url;

  /**
   * Function to call with the mint's certification data,
   * NULL if this has already been done.
   */
  TALER_MINT_CertificationCallback cert_cb;

  /**
   * Closure to pass to @e cert_cb.
   */
  void *cert_cb_cls;

  /**
   * Data for the request to get the /keys of a mint,
   * NULL once we are past stage #MHS_INIT.
   */
  struct KeysRequest *kr;

  /**
   * Key data of the mint, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  struct TALER_MINT_Keys key_data;

  /**
   * Stage of the mint's initialization routines.
   */
  enum MintHandleState state;

};


/* ***************** Internal /keys fetching ************* */

/**
 * Data for the request to get the /keys of a mint.
 */
struct KeysRequest
{
  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

  /**
   * The url for this handle
   */
  char *url;

  /**
   * Entry for this request with the `struct TALER_MINT_Context`.
   */
  struct MAC_Job *job;

  /**
   * Error buffer for Curl. Do we need this?
   */
  char emsg[CURL_ERROR_SIZE];

  /**
   * Download buffer
   */
  void *buf;

  /**
   * The size of the download buffer
   */
  size_t buf_size;

  /**
   * Error code (based on libc errno) if we failed to download
   * (i.e. response too large).
   */
  int eno;

};


/**
 * Callback used when downloading the reply to a /keys request.
 * Just appends all of the data to the `buf` in the
 * `struct KeysRequest` for further processing. The size of
 * the download is limited to #GNUNET_MAX_MALLOC_CHECKED, if
 * the download exceeds this size, we abort with an error.
 *
 * @param bufptr data downloaded via HTTP
 * @param size size of an item in @a bufptr
 * @param nitems number of items in @a bufptr
 * @param cls the `struct KeysRequest`
 * @return number of bytes processed from @a bufptr
 */
static size_t
keys_download_cb (char *bufptr,
                  size_t size,
                  size_t nitems,
                  void *cls)
{
  struct KeysRequest *kr = cls;
  size_t msize;
  void *buf;

  if (0 == size * nitems)
  {
    /* Nothing (left) to do */
    return 0;
  }
  msize = size * nitems;
  if ( (msize + kr->buf_size) >= GNUNET_MAX_MALLOC_CHECKED)
  {
    kr->eno = ENOMEM;
    return 0; /* signals an error to curl */
  }
  kr->buf = GNUNET_realloc (kr->buf,
                            kr->buf_size + msize);
  buf = kr->buf + kr->buf_size;
  memcpy (buf, bufptr, msize);
  kr->buf_size += msize;
  return msize;
}


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
  GNUNET_free_non_null (kr->buf);
  GNUNET_free (kr->url);
  GNUNET_free (kr);
}


/**
 * Parses the timestamp encoded as ASCII string as UNIX timstamp.
 * FIXME: we might want to move this function into libtalerutil.
 *
 * @param[out] abs successfully parsed timestamp will be returned thru this parameter
 * @param tstamp_enc the ASCII encoding of the timestamp
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
parse_timestamp (struct GNUNET_TIME_Absolute *abs,
                 const char *tstamp_enc)
{
  unsigned long tstamp;

  if (1 != sscanf (tstamp_enc, "%lu", &tstamp))
    return GNUNET_SYSERR;
  *abs = GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get_zero_ (),
                                   GNUNET_TIME_relative_multiply
                                   (GNUNET_TIME_UNIT_SECONDS, tstamp));
  return GNUNET_OK;
}


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)


/**
 * Parse a mint's signing key encoded in JSON.
 *
 * @param[out] sign_key where to return the result
 * @param[in] sign_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_signkey (struct TALER_MINT_SigningPublicKey *sign_key,
                    json_t *sign_key_obj,
                    const struct TALER_MasterPublicKeyP *master_key)
{
  // TODO: try to simplify...
  json_t *valid_from_obj;
  json_t *valid_until_obj;
  json_t *valid_legal_obj;
  json_t *key_obj;
  json_t *sig_obj;
  const char *valid_from_enc;
  const char *valid_until_enc;
  const char *valid_legal_enc;
  const char *key_enc;
  const char *sig_enc;
  struct TALER_MintSigningKeyValidityPS sign_key_issue;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute valid_until;
  struct GNUNET_TIME_Absolute valid_legal;

  EXITIF (JSON_OBJECT != json_typeof (sign_key_obj));
  EXITIF (NULL == (valid_from_obj = json_object_get (sign_key_obj,
                                                     "stamp_start")));
  EXITIF (NULL == (valid_until_obj = json_object_get (sign_key_obj,
                                                     "stamp_expire")));
  EXITIF (NULL == (valid_legal_obj = json_object_get (sign_key_obj,
                                                      "stamp_end")));
  EXITIF (NULL == (key_obj = json_object_get (sign_key_obj, "key")));
  EXITIF (NULL == (sig_obj = json_object_get (sign_key_obj, "master_sig")));
  EXITIF (NULL == (valid_from_enc = json_string_value (valid_from_obj)));
  EXITIF (NULL == (valid_until_enc = json_string_value (valid_until_obj)));
  EXITIF (NULL == (valid_legal_enc = json_string_value (valid_legal_obj)));
  EXITIF (NULL == (key_enc = json_string_value (key_obj)));
  EXITIF (NULL == (sig_enc = json_string_value (sig_obj)));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_from,
                                            valid_from_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_until,
                                            valid_until_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_legal,
                                            valid_legal_enc));
  EXITIF (52 != strlen (key_enc));  /* strlen(base32(char[32])) = 52 */
  EXITIF (103 != strlen (sig_enc)); /* strlen(base32(char[64])) = 103 */
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (sig_enc, 103,
                                                      &sig, sizeof (sig)));
  memset (&sign_key_issue,
          0,
          sizeof (sign_key_issue));
  EXITIF (GNUNET_SYSERR ==
          GNUNET_CRYPTO_eddsa_public_key_from_string (key_enc,
                                                      52,
                                                      &sign_key_issue.signkey_pub.eddsa_pub));
  sign_key_issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  sign_key_issue.purpose.size =
      htonl (sizeof (sign_key_issue)
             - offsetof (struct TALER_MintSigningKeyValidityPS, purpose));
  sign_key_issue.master_public_key = *master_key;
  sign_key_issue.start = GNUNET_TIME_absolute_hton (valid_from);
  sign_key_issue.expire = GNUNET_TIME_absolute_hton (valid_until);
  sign_key_issue.end = GNUNET_TIME_absolute_hton (valid_legal);
  EXITIF (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                      &sign_key_issue.purpose,
                                      &sig,
                                      &master_key->eddsa_pub));
  sign_key->valid_from = valid_from;
  sign_key->valid_until = valid_until;
  sign_key->key = sign_key_issue.signkey_pub;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}


/**
 * Parse an amount given in JSON encoding.
 *
 * @param[in] amount_obj the amount in json
 * @param[out] where to return the parsed amount
 * @return #GNUNET_OK if all is well, #GNUNET_SYSERR on parse errors
 */
static int
parse_json_amount (json_t *amount_obj,
                   struct TALER_Amount *amt)
{
  // FIXME: check for correctness...
  json_t *obj;
  const char *currency_str;
  int value; // FIXME: bad data type! (64 bit!)
  int fraction;

  EXITIF (NULL == (obj = json_object_get (amount_obj, "currency")));
  EXITIF (NULL == (currency_str = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (amount_obj, "value")));
  EXITIF (JSON_INTEGER != json_typeof (obj));
  EXITIF (0 > (value = json_integer_value (obj)));
  EXITIF (NULL == (obj = json_object_get (amount_obj, "fraction")));
  EXITIF (JSON_INTEGER != json_typeof (obj));
  EXITIF (0 > (fraction = json_integer_value (obj)));
  (void) memset (amt->currency, 0, sizeof (amt->currency));
  (void) strncpy (amt->currency, currency_str, sizeof (amt->currency) - 1);
  amt->value = (uint32_t) value;
  amt->fraction = (uint32_t) fraction;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
}


/**
 * Parse a mint's denomination key encoded in JSON.
 *
 * @param[out] denom_key where to return the result
 * @param[in] denom_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_denomkey (struct TALER_MINT_DenomPublicKey *denom_key,
                     json_t *denom_key_obj,
                     struct TALER_MasterPublicKeyP *master_key)
{
  // FIXME: check logic, try to simplify
  json_t *obj;
  const char *sig_enc;
  const char *deposit_valid_until_enc;
  const char *withdraw_valid_until_enc;
  const char *valid_from_enc;
  const char *expire_legal_enc;
  const char *key_enc;
  char *buf;
  size_t buf_size;
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute withdraw_valid_until;
  struct GNUNET_TIME_Absolute deposit_valid_until;
  struct GNUNET_TIME_Absolute expire_legal;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct TALER_DenominationKeyValidityPS denom_key_issue;
  struct GNUNET_CRYPTO_rsa_PublicKey *pk;
  struct GNUNET_CRYPTO_EddsaSignature sig;

  EXITIF (JSON_OBJECT != json_typeof (denom_key_obj));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "master_sig")));
  EXITIF (NULL == (sig_enc = json_string_value (obj)));
  EXITIF (103 != strlen (sig_enc));
  EXITIF (GNUNET_OK != GNUNET_STRINGS_string_to_data (sig_enc, 103,
                                                      &sig, sizeof (sig)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_expire_deposit")));
  EXITIF (NULL == (deposit_valid_until_enc = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_expire_withdraw")));
  EXITIF (NULL == (withdraw_valid_until_enc = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_start")));
  EXITIF (NULL == (valid_from_enc = json_string_value (obj)));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "stamp_expire_legal")));
  EXITIF (NULL == (expire_legal_enc = json_string_value (obj)));

  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "denom_pub")));
  EXITIF (NULL == (key_enc = json_string_value (obj)));

  EXITIF (GNUNET_SYSERR == parse_timestamp (&valid_from, valid_from_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&withdraw_valid_until,
                                            withdraw_valid_until_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&deposit_valid_until,
                                            deposit_valid_until_enc));
  EXITIF (GNUNET_SYSERR == parse_timestamp (&expire_legal,
                                            expire_legal_enc));

  memset (&denom_key_issue, 0, sizeof (denom_key_issue));

  buf_size = (strlen (key_enc) * 5) / 8;
  buf = GNUNET_malloc (buf_size);

  EXITIF (GNUNET_OK !=
          GNUNET_STRINGS_string_to_data (key_enc, strlen (key_enc),
                                         buf,
                                         buf_size));
  pk = GNUNET_CRYPTO_rsa_public_key_decode (buf, buf_size);
  GNUNET_free (buf);

  EXITIF (NULL == pk);
  GNUNET_CRYPTO_rsa_public_key_hash (pk,
                                     &denom_key_issue.denom_hash);
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "value")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &value));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "fee_withdraw")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &fee_withdraw));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "fee_deposit")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &fee_deposit));
  EXITIF (NULL == (obj = json_object_get (denom_key_obj, "fee_refresh")));
  EXITIF (GNUNET_SYSERR == parse_json_amount (obj, &fee_refresh));
  denom_key_issue.purpose.purpose
    = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  denom_key_issue.purpose.size
    = htonl (sizeof (struct TALER_DenominationKeyValidityPS) -
             offsetof (struct TALER_DenominationKeyValidityPS,
                       purpose));
  denom_key_issue.master = *master_key;
  denom_key_issue.start = GNUNET_TIME_absolute_hton (valid_from);
  denom_key_issue.expire_withdraw = GNUNET_TIME_absolute_hton (withdraw_valid_until);
  denom_key_issue.expire_spend = GNUNET_TIME_absolute_hton (deposit_valid_until);
  denom_key_issue.expire_legal = GNUNET_TIME_absolute_hton (expire_legal);
  TALER_amount_hton (&denom_key_issue.value,
                     &value);
  TALER_amount_hton (&denom_key_issue.fee_withdraw,
                     &fee_withdraw);
  TALER_amount_hton (&denom_key_issue.fee_deposit,
                     &fee_deposit);
  TALER_amount_hton (&denom_key_issue.fee_refresh,
                     &fee_refresh);
  EXITIF (GNUNET_SYSERR ==
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
                                      &denom_key_issue.purpose,
                                      &sig,
                                      &master_key->eddsa_pub));
  denom_key->key.rsa_public_key = pk;
  denom_key->valid_from = valid_from;
  denom_key->withdraw_valid_until = withdraw_valid_until;
  denom_key->deposit_valid_until = deposit_valid_until;
  denom_key->value = value;
  denom_key->fee_withdraw = fee_withdraw;
  denom_key->fee_deposit = fee_deposit;
  denom_key->fee_refresh = fee_refresh;
  return GNUNET_OK;

 EXITIF_exit:
  return GNUNET_SYSERR;
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
decode_keys_json (json_t *resp_obj,
                  struct TALER_MINT_Keys *key_data)
{
  struct GNUNET_TIME_Absolute list_issue_date;

  if (JSON_OBJECT != json_typeof (resp_obj))
    return GNUNET_SYSERR;

  /* parse the master public key */
  {
    json_t *master_key_obj;
    const char *master_key_enc;

    EXITIF (NULL == (master_key_obj =
                     json_object_get (resp_obj,
                                      "master_public_key")));
    EXITIF (NULL == (master_key_enc =
                     json_string_value (master_key_obj)));
    EXITIF (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_public_key_from_string (master_key_enc,
                                                        strlen (master_key_enc),
                                                        &key_data->master_pub.eddsa_pub));
  }

  /* parse the issue date of the response */
  {
    json_t *list_issue_date_obj;
    const char *tstamp_enc;

    EXITIF (NULL == (list_issue_date_obj =
                     json_object_get (resp_obj,
                                      "list_issue_date")));
    EXITIF (NULL == (tstamp_enc = json_string_value (list_issue_date_obj)));
    EXITIF (GNUNET_SYSERR == parse_timestamp (&list_issue_date,
                                              tstamp_enc));
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
      = GNUNET_malloc (sizeof (struct TALER_MINT_SigningPublicKey)
                       * key_data->num_sign_keys);
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
    EXITIF (0 == (key_data->num_denom_keys = json_array_size (denom_keys_array)));
    key_data->denom_keys = GNUNET_malloc (sizeof (struct TALER_MINT_DenomPublicKey)
                                          * key_data->num_denom_keys);
    index = 0;
    json_array_foreach (denom_keys_array, index, denom_key_obj) {
      EXITIF (GNUNET_SYSERR ==
              parse_json_denomkey (&key_data->denom_keys[index],
                                   denom_key_obj,
                                   &key_data->master_pub));
    }
  }
  return GNUNET_OK;

  /* FIXME: parse the auditor keys */

  /* FIXME: parse 'eddsa_sig' */

  /* FIXME: validate signature... */

 EXITIF_exit:
  return GNUNET_OK;
}


/**
 * We have successfully received the reply to the /keys
 * request from the mint. We now need to parse the reply
 * and, if successful, store the resulting information
 * in the `key_data` structure.
 *
 * @param kr key request with all of the data to parse
 *        and references to the `struct TALER_MINT_Handle`
 *        where we need to store the result
 * @return #GNUNET_OK on success,
 *         #GNUNET_SYSERR on failure
 */
static int
parse_response_keys_get (struct KeysRequest *kr)
{
  json_t *resp_obj;
  json_error_t error;
  int ret;

  resp_obj = json_loadb (kr->buf,
                         kr->buf_size,
                         JSON_REJECT_DUPLICATES | JSON_DISABLE_EOF_CHECK,
                         &error);
  if (NULL == resp_obj)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unable to parse received /keys data as JSON object\n");
    GNUNET_free_non_null (kr->buf);
    kr->buf = NULL;
    kr->buf_size = 0;
    return GNUNET_SYSERR;
  }
  GNUNET_free_non_null (kr->buf);
  kr->buf = NULL;
  kr->buf_size = 0;
  ret = decode_keys_json (resp_obj,
                          &kr->mint->key_data);
  json_decref (resp_obj);
  return ret;
}


/**
 * Callback used when downloading the reply to a /keys request
 * is complete.
 *
 * @param cls the `struct KeysRequest`
 */
static void
keys_completed_cb (void *cls)
{
  struct KeysRequest *kr = cls;
  struct TALER_MINT_Handle *mint = kr->mint;

  if ( (0 != kr->eno) ||
       (GNUNET_OK !=
        parse_response_keys_get (kr)) )
  {
    mint->kr = NULL;
    free_keys_request (kr);
    mint->state = MHS_FAILED;
    /* notify application that we failed */
    if (NULL != mint->cert_cb)
    {
      mint->cert_cb (mint->cert_cb_cls,
                     NULL);
      mint->cert_cb = NULL;
    }
    return;
  }
  mint->kr = NULL;
  free_keys_request (kr);
  mint->state = MHS_CERT;
  /* notify application about the key information */
  if (NULL != mint->cert_cb)
  {
    mint->cert_cb (mint->cert_cb_cls,
                   &mint->key_data);
    mint->cert_cb = NULL;
  }
}


/* ********************* library internal API ********* */


/**
 * Get the context of a mint.
 *
 * @param h the mint handle to query
 * @return ctx context to execute jobs in
 */
struct TALER_MINT_Context *
MAH_handle_to_context (struct TALER_MINT_Handle *h)
{
  return h->ctx;
}


/**
 * Check if the handle is ready to process requests.
 *
 * @param h the mint handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
int
MAH_handle_is_ready (struct TALER_MINT_Handle *h)
{
  return (MHS_CERT == h->state) ? GNUNET_YES : GNUNET_NO;
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param h the mint handle to query
 * @param path Taler API path (i.e. "/withdraw/sign")
 * @return the full URI to use with cURL
 */
char *
MAH_path_to_url (struct TALER_MINT_Handle *h,
                 const char *path)
{
  char *url;

  GNUNET_asprintf (&url,
                   "%s%s",
                   h->url,
                   path);
  return url;
}


/* ********************* public API ******************* */

/**
 * Initialise a connection to the mint. Will connect to the
 * mint and obtain information about the mint's master public
 * key and the mint's auditor.  The respective information will
 * be passed to the @a cert_cb once available, and all future
 * interactions with the mint will be checked to be signed
 * (where appropriate) by the respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the mint
 * @param cert_cb function to call with the mint's certification information
 * @param cert_cb_cls closure for @a cert_cb
 * @param ... list of additional arguments, terminated by #TALER_MINT_OPTION_END.
 * @return the mint handle; NULL upon error
 */
struct TALER_MINT_Handle *
TALER_MINT_connect (struct TALER_MINT_Context *ctx,
                    const char *url,
                    TALER_MINT_CertificationCallback cert_cb,
                    void *cert_cb_cls,
                    ...)
{
  struct TALER_MINT_Handle *mint;
  struct KeysRequest *kr;
  CURL *c;

  mint = GNUNET_new (struct TALER_MINT_Handle);
  mint->ctx = ctx;
  mint->url = GNUNET_strdup (url);
  mint->cert_cb = cert_cb;
  mint->cert_cb_cls = cert_cb_cls;
  kr = GNUNET_new (struct KeysRequest);
  kr->mint = mint;
  kr->url = MAH_path_to_url (mint, "/keys");
  c = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_URL,
                                   kr->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_ERRORBUFFER,
                                   kr->emsg));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_WRITEFUNCTION,
                                   &keys_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_WRITEDATA,
                                   kr));
  kr->job = MAC_job_add (mint->ctx,
                         c,
                         &keys_completed_cb,
                         kr);
  mint->kr = kr;
  return mint;
}


/**
 * Disconnect from the mint
 *
 * @param mint the mint handle
 */
void
TALER_MINT_disconnect (struct TALER_MINT_Handle *mint)
{
  if (NULL != mint->kr)
  {
    MAC_job_cancel (mint->kr->job);
    free_keys_request (mint->kr);
    mint->kr = NULL;
  }
  GNUNET_array_grow (mint->key_data.sign_keys,
                     mint->key_data.num_sign_keys,
                     0);
  GNUNET_array_grow (mint->key_data.denom_keys,
                     mint->key_data.num_denom_keys,
                     0);
  GNUNET_array_grow (mint->key_data.auditors,
                     mint->key_data.num_auditors,
                     0);
  GNUNET_free (mint->url);
  GNUNET_free (mint);
}


/* end of mint_api_handle.c */
