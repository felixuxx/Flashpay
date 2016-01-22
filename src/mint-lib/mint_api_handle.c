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
#include <microhttpd.h>
#include "taler_mint_service.h"
#include "taler_signatures.h"
#include "mint_api_context.h"
#include "mint_api_json.h"
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
   * Data structure for the download.
   */
  struct MAC_DownloadBuffer db;

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
  GNUNET_free_non_null (kr->db.buf);
  GNUNET_free (kr->url);
  GNUNET_free (kr);
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
  struct TALER_MintSigningKeyValidityPS sign_key_issue;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  struct GNUNET_TIME_Absolute valid_from;
  struct GNUNET_TIME_Absolute valid_until;
  struct GNUNET_TIME_Absolute valid_legal;
  struct MAJ_Specification spec[] = {
    MAJ_spec_fixed_auto ("master_sig",
                         &sig),
    MAJ_spec_fixed_auto ("key",
                         &sign_key_issue.signkey_pub),
    MAJ_spec_absolute_time ("stamp_start",
                            &valid_from),
    MAJ_spec_absolute_time ("stamp_expire",
                            &valid_until),
    MAJ_spec_absolute_time ("stamp_end",
                            &valid_legal),
    MAJ_spec_end
  };

  if (GNUNET_OK !=
      MAJ_parse_json (sign_key_obj,
                      spec))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  sign_key_issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY);
  sign_key_issue.purpose.size =
    htonl (sizeof (struct TALER_MintSigningKeyValidityPS)
           - offsetof (struct TALER_MintSigningKeyValidityPS,
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
 * Parse a mint's denomination key encoded in JSON.
 *
 * @param[out] denom_key where to return the result
 * @param[in] denom_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @param hash_context where to accumulate data for signature verification
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_denomkey (struct TALER_MINT_DenomPublicKey *denom_key,
                     json_t *denom_key_obj,
                     struct TALER_MasterPublicKeyP *master_key,
                     struct GNUNET_HashContext *hash_context)
{
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

  struct MAJ_Specification spec[] = {
    MAJ_spec_fixed_auto ("master_sig",
                         &sig),
    MAJ_spec_absolute_time ("stamp_expire_deposit",
                            &deposit_valid_until),
    MAJ_spec_absolute_time ("stamp_expire_withdraw",
                            &withdraw_valid_until),
    MAJ_spec_absolute_time ("stamp_start",
                            &valid_from),
    MAJ_spec_absolute_time ("stamp_expire_legal",
                            &expire_legal),
    MAJ_spec_amount ("value",
                     &value),
    MAJ_spec_amount ("fee_withdraw",
                     &fee_withdraw),
    MAJ_spec_amount ("fee_deposit",
                     &fee_deposit),
    MAJ_spec_amount ("fee_refresh",
                     &fee_refresh),
    MAJ_spec_rsa_public_key ("denom_pub",
                             &pk),
    MAJ_spec_end
  };

  if (GNUNET_OK !=
      MAJ_parse_json (denom_key_obj,
                      spec))
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
  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   &denom_key_issue.denom_hash,
                                   sizeof (struct GNUNET_HashCode));
  denom_key->key.rsa_public_key = pk;
  denom_key->h_key = denom_key_issue.denom_hash;
  denom_key->valid_from = valid_from;
  denom_key->withdraw_valid_until = withdraw_valid_until;
  denom_key->deposit_valid_until = deposit_valid_until;
  denom_key->expire_legal = expire_legal;
  denom_key->value = value;
  denom_key->fee_withdraw = fee_withdraw;
  denom_key->fee_deposit = fee_deposit;
  denom_key->fee_refresh = fee_refresh;
  return GNUNET_OK;

 EXITIF_exit:
  MAJ_parse_free (spec);
  return GNUNET_SYSERR;
}


/**
 * Parse a mint's auditor information encoded in JSON.
 *
 * @param[out] auditor where to return the result
 * @param[in] auditor_obj json to parse
 * @param key_data information about denomination keys
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_auditor (struct TALER_MINT_AuditorInformation *auditor,
                    json_t *auditor_obj,
                    const struct TALER_MINT_Keys *key_data)
{
  json_t *keys;
  json_t *key;
  unsigned int len;
  unsigned int off;
  unsigned int i;
  struct TALER_MintKeyValidityPS kv;
  struct MAJ_Specification spec[] = {
    MAJ_spec_fixed_auto ("auditor_pub",
                         &auditor->auditor_pub),
    MAJ_spec_json ("denomination_keys",
                   &keys),
    MAJ_spec_end
  };

  auditor->auditor_url = NULL; /* #3987 */
  if (GNUNET_OK !=
      MAJ_parse_json (auditor_obj,
                      spec))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  kv.purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_MINT_KEYS);
  kv.purpose.size = htonl (sizeof (struct TALER_MintKeyValidityPS));
  kv.master = key_data->master_pub;
  len = json_array_size (keys);
  auditor->denom_keys = GNUNET_new_array (len,
                                          const struct TALER_MINT_DenomPublicKey *);
  i = 0;
  off = 0;
  json_array_foreach (keys, i, key) {
    struct TALER_AuditorSignatureP auditor_sig;
    struct GNUNET_HashCode denom_h;
    const struct TALER_MINT_DenomPublicKey *dk;
    unsigned int j;
    struct MAJ_Specification spec[] = {
      MAJ_spec_fixed_auto ("denom_pub_h",
                           &denom_h),
      MAJ_spec_fixed_auto ("auditor_sig",
                           &auditor_sig),
      MAJ_spec_end
    };

    if (GNUNET_OK !=
        MAJ_parse_json (key,
                        spec))
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
    kv.expire_spend = GNUNET_TIME_absolute_hton (dk->deposit_valid_until);
    kv.expire_legal = GNUNET_TIME_absolute_hton (dk->expire_legal);
    TALER_amount_hton (&kv.value,
                       &dk->value);
    TALER_amount_hton (&kv.fee_withdraw,
                       &dk->fee_withdraw);
    TALER_amount_hton (&kv.fee_deposit,
                       &dk->fee_deposit);
    TALER_amount_hton (&kv.fee_refresh,
                       &dk->fee_refresh);
    kv.denom_hash = dk->h_key;
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_AUDITOR_MINT_KEYS,
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
decode_keys_json (json_t *resp_obj,
                  struct TALER_MINT_Keys *key_data)
{
  struct GNUNET_TIME_Absolute list_issue_date;
  struct TALER_MintSignatureP sig;
  struct TALER_MintKeySetPS ks;
  struct GNUNET_HashContext *hash_context;
  struct TALER_MintPublicKeyP pub;

  if (JSON_OBJECT != json_typeof (resp_obj))
    return GNUNET_SYSERR;

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  /* parse the master public key and issue date of the response */
  {
    struct MAJ_Specification spec[] = {
      MAJ_spec_fixed_auto ("master_public_key",
                           &key_data->master_pub),
      MAJ_spec_fixed_auto ("eddsa_sig",
                           &sig),
      MAJ_spec_fixed_auto ("eddsa_pub",
                           &pub),
      MAJ_spec_absolute_time ("list_issue_date",
                              &list_issue_date),
      MAJ_spec_end
    };

    EXITIF (GNUNET_OK !=
            MAJ_parse_json (resp_obj,
                            spec));
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
                          struct TALER_MINT_SigningPublicKey);
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
    key_data->denom_keys = GNUNET_new_array (key_data->num_denom_keys,
                                             struct TALER_MINT_DenomPublicKey);
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
                                             struct TALER_MINT_AuditorInformation);
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
  ks.purpose.purpose = htonl (TALER_SIGNATURE_MINT_KEY_SET);
  ks.list_issue_date = GNUNET_TIME_absolute_hton (list_issue_date);
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &ks.hc);
  hash_context = NULL;
  EXITIF (GNUNET_OK !=
          TALER_MINT_test_signing_key (key_data,
                                       &pub));
  EXITIF (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MINT_KEY_SET,
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
 * Callback used when downloading the reply to a /keys request
 * is complete.
 *
 * @param cls the `struct KeysRequest`
 * @param eh easy handle of the original request
 */
static void
keys_completed_cb (void *cls,
                   CURL *eh)
{
  struct KeysRequest *kr = cls;
  struct TALER_MINT_Handle *mint = kr->mint;
  json_t *resp_obj;
  long response_code;
  TALER_MINT_CertificationCallback cb;

  resp_obj = MAC_download_get_result (&kr->db,
                                      eh,
                                      &response_code);

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Received keys from URL `%s' with status %ld.\n",
              kr->url,
              response_code);

  switch (response_code) {
  case 0:
    break;
  case MHD_HTTP_OK:
    if ( (NULL == resp_obj) ||
         (GNUNET_OK !=
          decode_keys_json (resp_obj,
                            &kr->mint->key_data)) )
      response_code = 0;
    break;
  default:
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                response_code);
    break;
  }
  if (NULL != resp_obj)
    json_decref (resp_obj);

  if (MHD_HTTP_OK != response_code)
  {
    mint->kr = NULL;
    free_keys_request (kr);
    mint->state = MHS_FAILED;
    /* notify application that we failed */
    if (NULL != (cb = mint->cert_cb))
    {
      mint->cert_cb = NULL;
      cb (mint->cert_cb_cls,
	  NULL);
    }
    return;
  }
  mint->kr = NULL;
  free_keys_request (kr);
  mint->state = MHS_CERT;
  /* notify application about the key information */
  if (NULL != (cb = mint->cert_cb))
  {
    mint->cert_cb = NULL;
    cb (mint->cert_cb_cls,
	&mint->key_data);
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
 * @param path Taler API path (i.e. "/reserve/withdraw")
 * @return the full URI to use with cURL
 */
char *
MAH_path_to_url (struct TALER_MINT_Handle *h,
                 const char *path)
{
  char *url;

  if ( ('/' == path[0]) &&
       (0 < strlen (h->url)) &&
       ('/' == h->url[strlen (h->url) - 1]) )
    path++; /* avoid generating URL with "//" from concat */
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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting keys with URL `%s'.\n",
              kr->url);
  c = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_VERBOSE,
                                   0));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_STDERR,
                                   stdout));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_URL,
                                   kr->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (c,
                                   CURLOPT_WRITEDATA,
                                   &kr->db));
  kr->job = MAC_job_add (mint->ctx,
                         c,
                         GNUNET_NO,
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
  unsigned int i;

  if (NULL != mint->kr)
  {
    MAC_job_cancel (mint->kr->job);
    free_keys_request (mint->kr);
    mint->kr = NULL;
  }
  GNUNET_array_grow (mint->key_data.sign_keys,
                     mint->key_data.num_sign_keys,
                     0);
  for (i=0;i<mint->key_data.num_denom_keys;i++)
    GNUNET_CRYPTO_rsa_public_key_free (mint->key_data.denom_keys[i].key.rsa_public_key);
  GNUNET_array_grow (mint->key_data.denom_keys,
                     mint->key_data.num_denom_keys,
                     0);
  GNUNET_array_grow (mint->key_data.auditors,
                     mint->key_data.num_auditors,
                     0);
  GNUNET_free (mint->url);
  GNUNET_free (mint);
}


/**
 * Test if the given @a pub is a the current signing key from the mint
 * according to @a keys.
 *
 * @param keys the mint's key set
 * @param pub claimed current online signing key for the mint
 * @return #GNUNET_OK if @a pub is (according to /keys) a current signing key
 */
int
TALER_MINT_test_signing_key (const struct TALER_MINT_Keys *keys,
                             const struct TALER_MintPublicKeyP *pub)
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
                       sizeof (struct TALER_MintPublicKeyP))) )
      return GNUNET_OK;
  return GNUNET_SYSERR;
}


/**
 * Obtain the denomination key details from the mint.
 *
 * @param keys the mint's key set
 * @param pk public key of the denomination to lookup
 * @return details about the given denomination key, NULL if the key is
 * not found
 */
const struct TALER_MINT_DenomPublicKey *
TALER_MINT_get_denomination_key (const struct TALER_MINT_Keys *keys,
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
 * Obtain the denomination key details from the mint.
 *
 * @param keys the mint's key set
 * @param hc hash of the public key of the denomination to lookup
 * @return details about the given denomination key
 */
const struct TALER_MINT_DenomPublicKey *
TALER_MINT_get_denomination_key_by_hash (const struct TALER_MINT_Keys *keys,
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
 * Obtain the keys from the mint.
 *
 * @param mint the mint handle
 * @return the mint's key set
 */
const struct TALER_MINT_Keys *
TALER_MINT_get_keys (const struct TALER_MINT_Handle *mint)
{
  return &mint->key_data;
}


/* end of mint_api_handle.c */
