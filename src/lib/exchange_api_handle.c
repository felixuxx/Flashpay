/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file lib/exchange_api_handle.c
 * @brief Implementation of the "handle" component of the exchange's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "taler_auditor_service.h"
#include "taler_signatures.h"
#include "exchange_api_handle.h"
#include "exchange_api_curl_defaults.h"
#include "backoff.h"
#include "taler_curl_lib.h"

/**
 * Which version of the Taler protocol is implemented
 * by this library?  Used to determine compatibility.
 */
#define EXCHANGE_PROTOCOL_CURRENT 7

/**
 * How many versions are we backwards compatible with?
 */
#define EXCHANGE_PROTOCOL_AGE 0

/**
 * Current version for (local) JSON serialization of persisted
 * /keys data.
 */
#define EXCHANGE_SERIALIZATION_FORMAT_VERSION 0


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
 * Entry in DLL of auditors used by an exchange.
 */
struct TEAH_AuditorListEntry
{
  /**
   * Next pointer of DLL.
   */
  struct TEAH_AuditorListEntry *next;

  /**
   * Prev pointer of DLL.
   */
  struct TEAH_AuditorListEntry *prev;

  /**
   * Base URL of the auditor.
   */
  char *auditor_url;

  /**
   * Handle to the auditor.
   */
  struct TALER_AUDITOR_Handle *ah;

  /**
   * Head of DLL of interactions with this auditor.
   */
  struct TEAH_AuditorInteractionEntry *ai_head;

  /**
   * Tail of DLL of interactions with this auditor.
   */
  struct TEAH_AuditorInteractionEntry *ai_tail;

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * Flag indicating that the auditor is available and that protocol
   * version compatibility is given.
   */
  int is_up;

};


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
   * Task for retrying /keys request.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * Raw key data of the exchange, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  json_t *key_data_raw;

  /**
   * Head of DLL of auditors of this exchange.
   */
  struct TEAH_AuditorListEntry *auditors_head;

  /**
   * Tail of DLL of auditors of this exchange.
   */
  struct TEAH_AuditorListEntry *auditors_tail;

  /**
   * Key data of the exchange, only valid if
   * @e handshake_complete is past stage #MHS_CERT.
   */
  struct TALER_EXCHANGE_Keys key_data;

  /**
   * Retry /keys frequency.
   */
  struct GNUNET_TIME_Relative retry_delay;

  /**
   * When does @e key_data expire?
   */
  struct GNUNET_TIME_Absolute key_data_expiration;

  /**
   * Stage of the exchange's initialization routines.
   */
  enum ExchangeHandleState state;

  /**
   * If #GNUNET_YES, use fake now given by the user, in
   * request of "/keys".
   */
  int with_now;

  /**
   * Fake now given by the user.
   */
  struct GNUNET_TIME_Absolute now;

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
 * Signature of functions called with the result from our call to the
 * auditor's /deposit-confirmation handler.
 *
 * @param cls closure of type `struct TEAH_AuditorInteractionEntry *`
 * @param hr HTTP response
 */
void
TEAH_acc_confirmation_cb (void *cls,
                          const struct TALER_AUDITOR_HttpResponse *hr)
{
  struct TEAH_AuditorInteractionEntry *aie = cls;
  struct TEAH_AuditorListEntry *ale = aie->ale;

  if (MHD_HTTP_OK != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to submit deposit confirmation to auditor `%s' with HTTP status %d (EC: %d). This is acceptable if it does not happen often.\n",
                ale->auditor_url,
                hr->http_status,
                hr->ec);
  }
  GNUNET_CONTAINER_DLL_remove (ale->ai_head,
                               ale->ai_tail,
                               aie);
  GNUNET_free (aie);
}


/**
 * Iterate over all available auditors for @a h, calling
 * @a ac and giving it a chance to start a deposit
 * confirmation interaction.
 *
 * @param h exchange to go over auditors for
 * @param ac function to call per auditor
 * @param ac_cls closure for @a ac
 */
void
TEAH_get_auditors_for_dc (struct TALER_EXCHANGE_Handle *h,
                          TEAH_AuditorCallback ac,
                          void *ac_cls)
{
  if (NULL == h->auditors_head)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No auditor available for exchange `%s'. Not submitting deposit confirmations.\n",
                h->url);
    return;
  }
  for (struct TEAH_AuditorListEntry *ale = h->auditors_head;
       NULL != ale;
       ale = ale->next)
  {
    struct TEAH_AuditorInteractionEntry *aie;

    if (GNUNET_NO == ale->is_up)
      continue;
    aie = ac (ac_cls,
              ale->ah,
              &ale->auditor_pub);
    if (NULL != aie)
    {
      aie->ale = ale;
      GNUNET_CONTAINER_DLL_insert (ale->ai_head,
                                   ale->ai_tail,
                                   aie);
    }
  }
}


/**
 * Release memory occupied by a keys request.  Note that this does not
 * cancel the request itself.
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
 * @param check_sigs should we check signatures?
 * @param[in] sign_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_signkey (struct TALER_EXCHANGE_SigningPublicKey *sign_key,
                    int check_sigs,
                    json_t *sign_key_obj,
                    const struct TALER_MasterPublicKeyP *master_key)
{
  struct TALER_MasterSignatureP sign_key_issue_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &sign_key_issue_sig),
    GNUNET_JSON_spec_fixed_auto ("key",
                                 &sign_key->key),
    GNUNET_JSON_spec_absolute_time ("stamp_start",
                                    &sign_key->valid_from),
    GNUNET_JSON_spec_absolute_time ("stamp_expire",
                                    &sign_key->valid_until),
    GNUNET_JSON_spec_absolute_time ("stamp_end",
                                    &sign_key->valid_legal),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (sign_key_obj,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  if (! check_sigs)
    return GNUNET_OK;
  {
    struct TALER_ExchangeSigningKeyValidityPS sign_key_issue = {
      .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY),
      .purpose.size = htonl (sizeof (sign_key_issue)),
      .signkey_pub = sign_key->key,
      .master_public_key = *master_key,
      .start = GNUNET_TIME_absolute_hton (sign_key->valid_from),
      .expire = GNUNET_TIME_absolute_hton (sign_key->valid_until),
      .end = GNUNET_TIME_absolute_hton (sign_key->valid_legal)
    };

    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                    &sign_key_issue,
                                    &sign_key_issue_sig.eddsa_signature,
                                    &master_key->eddsa_pub))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  sign_key->master_sig = sign_key_issue_sig;
  return GNUNET_OK;
}


/**
 * Parse a exchange's denomination key encoded in JSON.
 *
 * @param[out] denom_key where to return the result
 * @param check_sigs should we check signatures?
 * @param[in] denom_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @param hash_context where to accumulate data for signature verification
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_denomkey (struct TALER_EXCHANGE_DenomPublicKey *denom_key,
                     int check_sigs,
                     json_t *denom_key_obj,
                     struct TALER_MasterPublicKeyP *master_key,
                     struct GNUNET_HashContext *hash_context)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &denom_key->master_sig),
    GNUNET_JSON_spec_absolute_time ("stamp_expire_deposit",
                                    &denom_key->expire_deposit),
    GNUNET_JSON_spec_absolute_time ("stamp_expire_withdraw",
                                    &denom_key->withdraw_valid_until),
    GNUNET_JSON_spec_absolute_time ("stamp_start",
                                    &denom_key->valid_from),
    GNUNET_JSON_spec_absolute_time ("stamp_expire_legal",
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
      GNUNET_JSON_parse (denom_key_obj,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  GNUNET_CRYPTO_rsa_public_key_hash (denom_key->key.rsa_public_key,
                                     &denom_key->h_key);
  if (NULL != hash_context)
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &denom_key->h_key,
                                     sizeof (struct GNUNET_HashCode));
  if (! check_sigs)
    return GNUNET_OK;
  {
    struct TALER_DenominationKeyValidityPS denom_key_issue =  {
      .purpose.purpose
        = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY),
      .purpose.size = htonl (sizeof (denom_key_issue)),
      .master = *master_key,
      .denom_hash = denom_key->h_key,
      .start = GNUNET_TIME_absolute_hton (denom_key->valid_from),
      .expire_withdraw
        = GNUNET_TIME_absolute_hton (denom_key->withdraw_valid_until),
      .expire_deposit = GNUNET_TIME_absolute_hton (denom_key->expire_deposit),
      .expire_legal = GNUNET_TIME_absolute_hton (denom_key->expire_legal)
    };

    TALER_amount_hton (&denom_key_issue.value,
                       &denom_key->value);
    TALER_amount_hton (&denom_key_issue.fee_withdraw,
                       &denom_key->fee_withdraw);
    TALER_amount_hton (&denom_key_issue.fee_deposit,
                       &denom_key->fee_deposit);
    TALER_amount_hton (&denom_key_issue.fee_refresh,
                       &denom_key->fee_refresh);
    TALER_amount_hton (&denom_key_issue.fee_refund,
                       &denom_key->fee_refund);
    EXITIF (GNUNET_SYSERR ==
            GNUNET_CRYPTO_eddsa_verify (
              TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
              &denom_key_issue,
              &denom_key->master_sig.eddsa_signature,
              &master_key->eddsa_pub));
  }
  return GNUNET_OK;

EXITIF_exit:
  /* invalidate denom_key, just to be sure */
  memset (denom_key,
          0,
          sizeof (*denom_key));
  GNUNET_JSON_parse_free (spec);
  return GNUNET_SYSERR;
}


/**
 * Parse a exchange's auditor information encoded in JSON.
 *
 * @param[out] auditor where to return the result
 * @param check_sigs should we check signatures
 * @param[in] auditor_obj json to parse
 * @param key_data information about denomination keys
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static int
parse_json_auditor (struct TALER_EXCHANGE_AuditorInformation *auditor,
                    int check_sigs,
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
    GNUNET_JSON_spec_end ()
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
                                          struct
                                          TALER_EXCHANGE_AuditorDenominationInfo);
  off = 0;
  json_array_foreach (keys, i, key) {
    struct TALER_AuditorSignatureP auditor_sig;
    struct GNUNET_HashCode denom_h;
    const struct TALER_EXCHANGE_DenomPublicKey *dk;
    unsigned int dk_off;
    struct GNUNET_JSON_Specification kspec[] = {
      GNUNET_JSON_spec_fixed_auto ("auditor_sig",
                                   &auditor_sig),
      GNUNET_JSON_spec_fixed_auto ("denom_pub_h",
                                   &denom_h),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (key,
                           kspec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      continue;
    }
    dk = NULL;
    dk_off = UINT_MAX;
    for (unsigned int j = 0; j<key_data->num_denom_keys; j++)
    {
      if (0 == GNUNET_memcmp (&denom_h,
                              &key_data->denom_keys[j].h_key))
      {
        dk = &key_data->denom_keys[j];
        dk_off = j;
        break;
      }
    }
    if (NULL == dk)
    {
      GNUNET_break_op (0);
      continue;
    }
    if (check_sigs)
    {
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
                                      &kv,
                                      &auditor_sig.eddsa_sig,
                                      &auditor->auditor_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
    }
    auditor->denom_keys[off].denom_key_offset = dk_off;
    auditor->denom_keys[off].auditor_sig = auditor_sig;
    off++;
  }
  auditor->num_denom_keys = off;
  GNUNET_JSON_parse_free (spec);
  return GNUNET_OK;
}


/**
 * Function called with information about the auditor.  Marks an
 * auditor as 'up'.
 *
 * @param cls closure, a `struct TEAH_AuditorListEntry *`
 * @param hr http response from the auditor
 * @param vi basic information about the auditor
 * @param compat protocol compatibility information
 */
static void
auditor_version_cb (
  void *cls,
  const struct TALER_AUDITOR_HttpResponse *hr,
  const struct TALER_AUDITOR_VersionInformation *vi,
  enum TALER_AUDITOR_VersionCompatibility compat)
{
  struct TEAH_AuditorListEntry *ale = cls;

  if (NULL == vi)
  {
    /* In this case, we don't mark the auditor as 'up' */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Auditor `%s' gave unexpected version response.\n",
                ale->auditor_url);
    return;
  }

  if (0 != (TALER_AUDITOR_VC_INCOMPATIBLE & compat))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Auditor `%s' runs incompatible protocol version!\n",
                ale->auditor_url);
    if (0 != (TALER_AUDITOR_VC_OLDER & compat))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Auditor `%s' runs outdated protocol version!\n",
                  ale->auditor_url);
    }
    if (0 != (TALER_AUDITOR_VC_NEWER & compat))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Auditor `%s' runs more recent incompatible version. We should upgrade!\n",
                  ale->auditor_url);
    }
    return;
  }
  ale->is_up = GNUNET_YES;
}


/**
 * Recalculate our auditor list, we got /keys and it may have
 * changed.
 *
 * @param exchange exchange for which to update the list.
 */
static void
update_auditors (struct TALER_EXCHANGE_Handle *exchange)
{
  struct TALER_EXCHANGE_Keys *kd = &exchange->key_data;

  TALER_LOG_DEBUG ("Updating auditors\n");
  for (unsigned int i = 0; i<kd->num_auditors; i++)
  {
    /* Compare auditor data from /keys with auditor data
     * from owned exchange structures.  */
    struct TALER_EXCHANGE_AuditorInformation *auditor = &kd->auditors[i];
    struct TEAH_AuditorListEntry *ale = NULL;

    for (struct TEAH_AuditorListEntry *a = exchange->auditors_head;
         NULL != a;
         a = a->next)
    {
      if (0 == GNUNET_memcmp (&auditor->auditor_pub,
                              &a->auditor_pub))
      {
        ale = a;
        break;
      }
    }
    if (NULL != ale)
      continue; /* found, no need to add */

    /* new auditor, add */
    TALER_LOG_DEBUG ("Found new auditor!\n");
    ale = GNUNET_new (struct TEAH_AuditorListEntry);
    ale->auditor_pub = auditor->auditor_pub;
    ale->auditor_url = GNUNET_strdup (auditor->auditor_url);
    GNUNET_CONTAINER_DLL_insert (exchange->auditors_head,
                                 exchange->auditors_tail,
                                 ale);

    ale->ah = TALER_AUDITOR_connect (exchange->ctx,
                                     ale->auditor_url,
                                     &auditor_version_cb,
                                     ale);
  }
}


/**
 * Compare two denomination keys.  Ignores revocation data.
 *
 * @param denom1 first denomination key
 * @param denom2 second denomination key
 * @return 0 if the two keys are equal (not necessarily
 *  the same object), 1 otherwise.
 */
static unsigned int
denoms_cmp (struct TALER_EXCHANGE_DenomPublicKey *denom1,
            struct TALER_EXCHANGE_DenomPublicKey *denom2)
{
  struct GNUNET_CRYPTO_RsaPublicKey *tmp1;
  struct GNUNET_CRYPTO_RsaPublicKey *tmp2;
  int r1;
  int r2;
  int ret;

  /* First check if pub is the same.  */
  if (0 != GNUNET_CRYPTO_rsa_public_key_cmp
        (denom1->key.rsa_public_key,
        denom2->key.rsa_public_key))
    return 1;

  tmp1 = denom1->key.rsa_public_key;
  tmp2 = denom2->key.rsa_public_key;
  r1 = denom1->revoked;
  r2 = denom2->revoked;

  denom1->key.rsa_public_key = NULL;
  denom2->key.rsa_public_key = NULL;
  /* Then proceed with the rest of the object.  */
  ret = GNUNET_memcmp (denom1,
                       denom2);
  denom1->revoked = r1;
  denom2->revoked = r2;
  denom1->key.rsa_public_key = tmp1;
  denom2->key.rsa_public_key = tmp2;
  return ret;
}


/**
 * Decode the JSON in @a resp_obj from the /keys response
 * and store the data in the @a key_data.
 *
 * @param[in] resp_obj JSON object to parse
 * @param check_sig #GNUNET_YES if we should check the signature
 * @param[out] key_data where to store the results we decoded
 * @param[out] vc where to store version compatibility data
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 * (malformed JSON)
 */
static int
decode_keys_json (const json_t *resp_obj,
                  int check_sig,
                  struct TALER_EXCHANGE_Keys *key_data,
                  enum TALER_EXCHANGE_VersionCompatibility *vc)
{
  struct TALER_ExchangeSignatureP sig;
  struct GNUNET_HashContext *hash_context;
  struct TALER_ExchangePublicKeyP pub;
  struct GNUNET_JSON_Specification mspec[] = {
    GNUNET_JSON_spec_fixed_auto ("eddsa_sig",
                                 &sig),
    GNUNET_JSON_spec_fixed_auto ("eddsa_pub",
                                 &pub),
    /* sig and pub must be first, as we skip those if
       check_sig is false! */
    GNUNET_JSON_spec_fixed_auto ("master_public_key",
                                 &key_data->master_pub),
    GNUNET_JSON_spec_absolute_time ("list_issue_date",
                                    &key_data->list_issue_date),
    GNUNET_JSON_spec_relative_time ("reserve_closing_delay",
                                    &key_data->reserve_closing_delay),
    GNUNET_JSON_spec_end ()
  };

  if (JSON_OBJECT != json_typeof (resp_obj))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* check the version */
  {
    const char *ver;
    unsigned int age;
    unsigned int revision;
    unsigned int current;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_string ("version",
                               &ver),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (resp_obj,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (3 != sscanf (ver,
                     "%u:%u:%u",
                     &current,
                     &revision,
                     &age))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    *vc = TALER_EXCHANGE_VC_MATCH;
    if (EXCHANGE_PROTOCOL_CURRENT < current)
    {
      *vc |= TALER_EXCHANGE_VC_NEWER;
      if (EXCHANGE_PROTOCOL_CURRENT < current - age)
        *vc |= TALER_EXCHANGE_VC_INCOMPATIBLE;
    }
    if (EXCHANGE_PROTOCOL_CURRENT > current)
    {
      *vc |= TALER_EXCHANGE_VC_OLDER;
      if (EXCHANGE_PROTOCOL_CURRENT - EXCHANGE_PROTOCOL_AGE > current)
        *vc |= TALER_EXCHANGE_VC_INCOMPATIBLE;
    }
    key_data->version = GNUNET_strdup (ver);
  }

  hash_context = NULL;
  EXITIF (GNUNET_OK !=
          GNUNET_JSON_parse (resp_obj,
                             (check_sig) ? mspec : &mspec[2],
                             NULL, NULL));

  /* parse the master public key and issue date of the response */
  if (check_sig)
    hash_context = GNUNET_CRYPTO_hash_context_start ();

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
    json_array_foreach (sign_keys_array, index, sign_key_obj) {
      EXITIF (GNUNET_SYSERR ==
              parse_json_signkey (&key_data->sign_keys[index],
                                  check_sig,
                                  sign_key_obj,
                                  &key_data->master_pub));
    }
  }

  /* parse the denomination keys, merging with the
     possibly EXISTING array as required (/keys cherry picking) */
  {
    json_t *denom_keys_array;
    json_t *denom_key_obj;
    unsigned int index;

    EXITIF (NULL == (denom_keys_array =
                       json_object_get (resp_obj,
                                        "denoms")));
    EXITIF (JSON_ARRAY != json_typeof (denom_keys_array));

    json_array_foreach (denom_keys_array, index, denom_key_obj) {
      struct TALER_EXCHANGE_DenomPublicKey dk;
      int found = GNUNET_NO;

      memset (&dk,
              0,
              sizeof (dk));
      EXITIF (GNUNET_SYSERR ==
              parse_json_denomkey (&dk,
                                   check_sig,
                                   denom_key_obj,
                                   &key_data->master_pub,
                                   hash_context));

      for (unsigned int j = 0;
           j<key_data->num_denom_keys;
           j++)
      {
        if (0 == denoms_cmp (&dk,
                             &key_data->denom_keys[j]))
        {
          found = GNUNET_YES;
          break;
        }
      }
      if (GNUNET_YES == found)
      {
        /* 0:0:0 did not support /keys cherry picking */
        TALER_LOG_DEBUG ("Skipping denomination key: already know it\n");
        GNUNET_CRYPTO_rsa_public_key_free (dk.key.rsa_public_key);
        continue;
      }
      if (key_data->denom_keys_size == key_data->num_denom_keys)
        GNUNET_array_grow (key_data->denom_keys,
                           key_data->denom_keys_size,
                           key_data->denom_keys_size * 2 + 2);
      key_data->denom_keys[key_data->num_denom_keys++] = dk;

      /* Update "last_denom_issue_date" */
      TALER_LOG_DEBUG ("Adding denomination key that is valid_from %s\n",
                       GNUNET_STRINGS_absolute_time_to_string (dk.valid_from));
      key_data->last_denom_issue_date
        = GNUNET_TIME_absolute_max (key_data->last_denom_issue_date,
                                    dk.valid_from);
    };
  }

  /* parse the auditor information */
  {
    json_t *auditors_array;
    json_t *auditor_info;
    unsigned int index;

    EXITIF (NULL == (auditors_array =
                       json_object_get (resp_obj,
                                        "auditors")));
    EXITIF (JSON_ARRAY != json_typeof (auditors_array));

    /* Merge with the existing auditor information we have (/keys cherry picking) */
    json_array_foreach (auditors_array, index, auditor_info) {
      struct TALER_EXCHANGE_AuditorInformation ai;
      int found = GNUNET_NO;

      memset (&ai,
              0,
              sizeof (ai));
      EXITIF (GNUNET_SYSERR ==
              parse_json_auditor (&ai,
                                  check_sig,
                                  auditor_info,
                                  key_data));
      for (unsigned int j = 0; j<key_data->num_auditors; j++)
      {
        struct TALER_EXCHANGE_AuditorInformation *aix = &key_data->auditors[j];

        if (0 == GNUNET_memcmp (&ai.auditor_pub,
                                &aix->auditor_pub))
        {
          found = GNUNET_YES;
          /* Merge denomination key signatures of downloaded /keys into existing
             auditor information 'aix'. */
          TALER_LOG_DEBUG (
            "Merging %u new audited keys with %u known audited keys\n",
            aix->num_denom_keys,
            ai.num_denom_keys);

          GNUNET_array_concatenate (aix->denom_keys,
                                    aix->num_denom_keys,
                                    ai.denom_keys,
                                    ai.num_denom_keys);
          break;
        }
      }
      if (GNUNET_YES == found)
      {
        GNUNET_array_grow (ai.denom_keys,
                           ai.num_denom_keys,
                           0);
        GNUNET_free (ai.auditor_url);
        continue; /* we are done */
      }
      if (key_data->auditors_size == key_data->num_auditors)
        GNUNET_array_grow (key_data->auditors,
                           key_data->auditors_size,
                           key_data->auditors_size * 2 + 2);
      GNUNET_assert (NULL != ai.auditor_url);
      key_data->auditors[key_data->num_auditors++] = ai;
    };
  }

  /* parse the revocation/recoup information */
  {
    json_t *recoup_array;
    json_t *recoup_info;
    unsigned int index;

    if (NULL != (recoup_array =
                   json_object_get (resp_obj,
                                    "recoup")))
    {
      EXITIF (JSON_ARRAY != json_typeof (recoup_array));

      json_array_foreach (recoup_array, index, recoup_info) {
        struct GNUNET_HashCode h_denom_pub;
        struct GNUNET_JSON_Specification spec[] = {
          GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                       &h_denom_pub),
          GNUNET_JSON_spec_end ()
        };

        EXITIF (GNUNET_OK !=
                GNUNET_JSON_parse (recoup_info,
                                   spec,
                                   NULL, NULL));
        for (unsigned int j = 0;
             j<key_data->num_denom_keys;
             j++)
        {
          if (0 == GNUNET_memcmp (&h_denom_pub,
                                  &key_data->denom_keys[j].h_key))
          {
            key_data->denom_keys[j].revoked = GNUNET_YES;
            break;
          }
        }
      };
    }
  }

  if (check_sig)
  {
    struct TALER_ExchangeKeySetPS ks;

    /* Validate signature... */
    ks.purpose.size = htonl (sizeof (ks));
    ks.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_KEY_SET);
    ks.list_issue_date = GNUNET_TIME_absolute_hton (key_data->list_issue_date);
    GNUNET_CRYPTO_hash_context_finish (hash_context,
                                       &ks.hc);
    hash_context = NULL;
    EXITIF (GNUNET_OK !=
            TALER_EXCHANGE_test_signing_key (key_data,
                                             &pub));
    EXITIF (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_KEY_SET,
                                        &ks,
                                        &sig.eddsa_signature,
                                        &pub.eddsa_pub));
  }
  return GNUNET_OK;
EXITIF_exit:

  *vc = TALER_EXCHANGE_VC_PROTOCOL_ERROR;
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
  GNUNET_array_grow (key_data->sign_keys,
                     key_data->num_sign_keys,
                     0);
  for (unsigned int i = 0; i<key_data->num_denom_keys; i++)
    GNUNET_CRYPTO_rsa_public_key_free (
      key_data->denom_keys[i].key.rsa_public_key);

  GNUNET_array_grow (key_data->denom_keys,
                     key_data->denom_keys_size,
                     0);
  for (unsigned int i = 0; i<key_data->num_auditors; i++)
  {
    GNUNET_array_grow (key_data->auditors[i].denom_keys,
                       key_data->auditors[i].num_denom_keys,
                       0);
    GNUNET_free (key_data->auditors[i].auditor_url);
  }
  GNUNET_array_grow (key_data->auditors,
                     key_data->auditors_size,
                     0);
  GNUNET_free (key_data->version);
  key_data->version = NULL;
}


/**
 * Initiate download of /keys from the exchange.
 *
 * @param cls exchange where to download /keys from
 */
static void
request_keys (void *cls);


/**
 * Set the fake now to be used when requesting "/keys".
 *
 * @param exchange exchange handle.
 * @param now fake now to use.  Note: this value will be
 *        used _until_ its use will be unset via @a TALER_EXCHANGE_unset_now()
 */
void
TALER_EXCHANGE_set_now (struct TALER_EXCHANGE_Handle *exchange,
                        struct GNUNET_TIME_Absolute now)
{
  exchange->with_now = GNUNET_YES;
  exchange->now = now;
}


/**
 * Unset the fake now to be used when requesting "/keys".
 *
 * @param exchange exchange handle.
 */
void
TALER_EXCHANGE_unset_now (struct TALER_EXCHANGE_Handle *exchange)
{
  exchange->with_now = GNUNET_NO;
}


/**
 * Let the user set the last valid denomination time manually.
 *
 * @param exchange the exchange handle.
 * @param last_denom_new new last denomination time.
 */
void
TALER_EXCHANGE_set_last_denom (struct TALER_EXCHANGE_Handle *exchange,
                               struct GNUNET_TIME_Absolute last_denom_new)
{
  exchange->key_data.last_denom_issue_date = last_denom_new;
}


/**
 * Check if our current response for /keys is valid, and if
 * not trigger download.
 *
 * @param exchange exchange to check keys for
 * @param force_download #GNUNET_YES to force download even if /keys is still valid
 * @param pull_all_keys if #GNUNET_YES, then the exchange state is reset to #MHS_INIT,
 *        and all denoms will be redownloaded.
 * @return until when the response is current, 0 if we are re-downloading
 */
struct GNUNET_TIME_Absolute
TALER_EXCHANGE_check_keys_current (struct TALER_EXCHANGE_Handle *exchange,
                                   int force_download,
                                   int pull_all_keys)
{
  if (NULL != exchange->kr)
    return GNUNET_TIME_UNIT_ZERO_ABS;

  if (GNUNET_YES == pull_all_keys)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Forcing re-download of all exchange keys\n");
    GNUNET_break (GNUNET_YES == force_download);
    exchange->state = MHS_INIT;
  }
  if ( (GNUNET_NO == force_download) &&
       (0 < GNUNET_TIME_absolute_get_remaining (
          exchange->key_data_expiration).rel_value_us) )
    return exchange->key_data_expiration;
  if (NULL == exchange->retry_task)
    exchange->retry_task = GNUNET_SCHEDULER_add_now (&request_keys,
                                                     exchange);
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
                   const void *resp_obj)
{
  struct KeysRequest *kr = cls;
  struct TALER_EXCHANGE_Handle *exchange = kr->exchange;
  struct TALER_EXCHANGE_Keys kd;
  struct TALER_EXCHANGE_Keys kd_old;
  enum TALER_EXCHANGE_VersionCompatibility vc;
  const json_t *j = resp_obj;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .reply = j,
    .http_status = (unsigned int) response_code
  };

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received keys from URL `%s' with status %ld.\n",
              kr->url,
              response_code);
  kd_old = exchange->key_data;
  memset (&kd,
          0,
          sizeof (struct TALER_EXCHANGE_Keys));
  vc = TALER_EXCHANGE_VC_PROTOCOL_ERROR;
  switch (response_code)
  {
  case 0:
    free_keys_request (kr);
    exchange->kr = NULL;
    GNUNET_assert (NULL == exchange->retry_task);
    exchange->retry_delay = EXCHANGE_LIB_BACKOFF (exchange->retry_delay);
    exchange->retry_task = GNUNET_SCHEDULER_add_delayed (exchange->retry_delay,
                                                         &request_keys,
                                                         exchange);
    return;
  case MHD_HTTP_OK:
    if (NULL == j)
    {
      response_code = 0;
      break;
    }
    /* We keep the denomination keys and auditor signatures from the
       previous iteration (/keys cherry picking) */
    kd.num_denom_keys = kd_old.num_denom_keys;
    kd.last_denom_issue_date = kd_old.last_denom_issue_date;
    GNUNET_array_grow (kd.denom_keys,
                       kd.denom_keys_size,
                       kd.num_denom_keys);

    /* First make a shallow copy, we then need another pass for the RSA key... */
    memcpy (kd.denom_keys,
            kd_old.denom_keys,
            kd_old.num_denom_keys * sizeof (struct
                                            TALER_EXCHANGE_DenomPublicKey));

    for (unsigned int i = 0; i<kd_old.num_denom_keys; i++)
      kd.denom_keys[i].key.rsa_public_key
        = GNUNET_CRYPTO_rsa_public_key_dup (
            kd_old.denom_keys[i].key.rsa_public_key);

    kd.num_auditors = kd_old.num_auditors;
    kd.auditors = GNUNET_new_array (kd.num_auditors,
                                    struct TALER_EXCHANGE_AuditorInformation);
    /* Now the necessary deep copy... */
    for (unsigned int i = 0; i<kd_old.num_auditors; i++)
    {
      const struct TALER_EXCHANGE_AuditorInformation *aold =
        &kd_old.auditors[i];
      struct TALER_EXCHANGE_AuditorInformation *anew = &kd.auditors[i];

      anew->auditor_pub = aold->auditor_pub;
      GNUNET_assert (NULL != aold->auditor_url);
      anew->auditor_url = GNUNET_strdup (aold->auditor_url);
      GNUNET_array_grow (anew->denom_keys,
                         anew->num_denom_keys,
                         aold->num_denom_keys);
      memcpy (anew->denom_keys,
              aold->denom_keys,
              aold->num_denom_keys
              * sizeof (struct TALER_EXCHANGE_AuditorDenominationInfo));
    }

    /* Old auditors got just copied into new ones.  */
    if (GNUNET_OK !=
        decode_keys_json (j,
                          GNUNET_YES,
                          &kd,
                          &vc))
    {
      TALER_LOG_ERROR ("Could not decode /keys response\n");
      hr.http_status = 0;
      hr.ec = TALER_EC_KEYS_INVALID;
      for (unsigned int i = 0; i<kd.num_auditors; i++)
      {
        struct TALER_EXCHANGE_AuditorInformation *anew = &kd.auditors[i];

        GNUNET_array_grow (anew->denom_keys,
                           anew->num_denom_keys,
                           0);
        GNUNET_free (anew->auditor_url);
      }
      GNUNET_free (kd.auditors);
      kd.auditors = NULL;
      kd.num_auditors = 0;
      for (unsigned int i = 0; i<kd_old.num_denom_keys; i++)
        GNUNET_CRYPTO_rsa_public_key_free (kd.denom_keys[i].key.rsa_public_key);
      GNUNET_array_grow (kd.denom_keys,
                         kd.denom_keys_size,
                         0);
      kd.num_denom_keys = 0;
      break;
    }
    json_decref (exchange->key_data_raw);
    exchange->key_data_raw = json_deep_copy (j);
    exchange->retry_delay = GNUNET_TIME_UNIT_ZERO;
    break;
  default:
    hr.ec = TALER_JSON_get_error_code (j);
    hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  exchange->key_data = kd;
  TALER_LOG_DEBUG ("Last DK issue date update to: %s\n",
                   GNUNET_STRINGS_absolute_time_to_string
                     (exchange->key_data.last_denom_issue_date));


  if (MHD_HTTP_OK != response_code)
  {
    exchange->kr = NULL;
    free_keys_request (kr);
    exchange->state = MHS_FAILED;
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Exchange keys download failed\n");
    if (NULL != exchange->key_data_raw)
    {
      json_decref (exchange->key_data_raw);
      exchange->key_data_raw = NULL;
    }
    free_key_data (&kd_old);
    /* notify application that we failed */
    exchange->cert_cb (exchange->cert_cb_cls,
                       &hr,
                       NULL,
                       vc);
    return;
  }

  exchange->kr = NULL;
  exchange->key_data_expiration = kr->expire;
  free_keys_request (kr);
  exchange->state = MHS_CERT;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Successfully downloaded exchange's keys\n");
  update_auditors (exchange);
  /* notify application about the key information */
  exchange->cert_cb (exchange->cert_cb_cls,
                     &hr,
                     &exchange->key_data,
                     vc);
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
TEAH_handle_to_context (struct TALER_EXCHANGE_Handle *h)
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
TEAH_handle_is_ready (struct TALER_EXCHANGE_Handle *h)
{
  return (MHS_CERT == h->state) ? GNUNET_YES : GNUNET_NO;
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param h handle for the exchange
 * @param path Taler API path (i.e. "/reserve/withdraw")
 * @return the full URL to use with cURL
 */
char *
TEAH_path_to_url (struct TALER_EXCHANGE_Handle *h,
                  const char *path)
{
  char *ret;

  GNUNET_assert ('/' == path[0]);
  ret = TALER_url_join (h->url,
                        path + 1,
                        NULL);
  GNUNET_assert (NULL != ret);
  return ret;
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
  struct tm now;
  time_t t;
  const char *end;

  memset (&now,
          0,
          sizeof (now));
  end = strptime (date,
                  "%a, %d %b %Y %H:%M:%S %Z", /* RFC-1123 standard spec */
                  &now);
  if ( (NULL == end) ||
       ( (*end != '\n') &&
         (*end != '\r') ) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  t = mktime (&now);
  if (((time_t) -1) == t)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "mktime");
    return GNUNET_SYSERR;
  }
  if (t < 0)
    t = 0; /* can happen due to timezone issues if date was 1.1.1970 */
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
    kr->expire = GNUNET_TIME_UNIT_ZERO_ABS;
  }
  GNUNET_free (val);
  return total;
}


/* ********************* public API ******************* */


/**
 * Deserialize the key data and use it to bootstrap @a exchange to
 * more efficiently recover the state.  Errors in @a data must be
 * tolerated (i.e. by re-downloading instead).
 *
 * @param exchange which exchange's key and wire data should be deserialized
 * @param data the data to deserialize
 */
static void
deserialize_data (struct TALER_EXCHANGE_Handle *exchange,
                  const json_t *data)
{
  enum TALER_EXCHANGE_VersionCompatibility vc;
  json_t *keys;
  const char *url;
  uint32_t version;
  struct GNUNET_TIME_Absolute expire;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint32 ("version",
                             &version),
    GNUNET_JSON_spec_json ("keys",
                           &keys),
    GNUNET_JSON_spec_string ("exchange_url",
                             &url),
    GNUNET_JSON_spec_absolute_time ("expire",
                                    &expire),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_EXCHANGE_Keys key_data;
  struct TALER_EXCHANGE_HttpResponse hr = {
    .ec = TALER_EC_NONE,
    .http_status = MHD_HTTP_OK,
    .reply = data
  };

  if (NULL == data)
    return;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (data,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return;
  }
  if (0 != version)
  {
    GNUNET_JSON_parse_free (spec);
    return; /* unsupported version */
  }
  if (0 != strcmp (url,
                   exchange->url))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return;
  }
  memset (&key_data,
          0,
          sizeof (struct TALER_EXCHANGE_Keys));
  if (GNUNET_OK !=
      decode_keys_json (keys,
                        GNUNET_NO,
                        &key_data,
                        &vc))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return;
  }
  /* decode successful, initialize with the result */
  GNUNET_assert (NULL == exchange->key_data_raw);
  exchange->key_data_raw = json_deep_copy (keys);
  exchange->key_data = key_data;
  exchange->key_data_expiration = expire;
  exchange->state = MHS_CERT;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Successfully loaded exchange's keys via deserialization\n");
  update_auditors (exchange);
  /* notify application about the key information */
  exchange->cert_cb (exchange->cert_cb_cls,
                     &hr,
                     &exchange->key_data,
                     vc);
  GNUNET_JSON_parse_free (spec);
}


/**
 * Serialize the latest key data from @a
 * exchange to be persisted on disk (to be used with
 * #TALER_EXCHANGE_OPTION_DATA to more efficiently recover
 * the state).
 *
 * @param exchange which exchange's key and wire data should be
 *        serialized
 * @return NULL on error (i.e. no current data available);
 *         otherwise JSON object owned by the caller
 */
json_t *
TALER_EXCHANGE_serialize_data (struct TALER_EXCHANGE_Handle *exchange)
{
  const struct TALER_EXCHANGE_Keys *kd = &exchange->key_data;
  struct GNUNET_TIME_Absolute now;
  json_t *keys;
  json_t *signkeys;
  json_t *denoms;
  json_t *auditors;

  now = GNUNET_TIME_absolute_get ();
  signkeys = json_array ();
  if (NULL == signkeys)
  {
    GNUNET_break (0);
    return NULL;
  }
  for (unsigned int i = 0; i<kd->num_sign_keys; i++)
  {
    const struct TALER_EXCHANGE_SigningPublicKey *sk = &kd->sign_keys[i];
    json_t *signkey;

    if (now.abs_value_us > sk->valid_until.abs_value_us)
      continue; /* skip keys that have expired */
    signkey = json_pack ("{s:o, s:o, s:o, s:o, s:o}",
                         "key",
                         GNUNET_JSON_from_data_auto
                           (&sk->key),
                         "master_sig",
                         GNUNET_JSON_from_data_auto
                           (&sk->master_sig),
                         "stamp_start",
                         GNUNET_JSON_from_time_abs
                           (sk->valid_from),
                         "stamp_expire",
                         GNUNET_JSON_from_time_abs
                           (sk->valid_until),
                         "stamp_end",
                         GNUNET_JSON_from_time_abs
                           (sk->valid_legal));
    if (NULL == signkey)
    {
      GNUNET_break (0);
      continue;
    }
    if (0 != json_array_append_new (signkeys,
                                    signkey))
    {
      GNUNET_break (0);
      json_decref (signkey);
      json_decref (signkeys);
      return NULL;
    }
  }
  denoms = json_array ();
  if (NULL == denoms)
  {
    GNUNET_break (0);
    json_decref (signkeys);
    return NULL;
  }
  for (unsigned int i = 0; i<kd->num_denom_keys; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *dk = &kd->denom_keys[i];
    json_t *denom;

    if (now.abs_value_us > dk->expire_deposit.abs_value_us)
      continue; /* skip keys that have expired */
    denom = json_pack ("{s:o, s:o, s:o, s:o, s:o "
                       ",s:o, s:o, s:o, s:o, s:o "
                       ",s:o}",
                       "stamp_expire_deposit",
                       GNUNET_JSON_from_time_abs (dk->expire_deposit),
                       "stamp_expire_withdraw",
                       GNUNET_JSON_from_time_abs (dk->withdraw_valid_until),
                       "stamp_start",
                       GNUNET_JSON_from_time_abs (dk->valid_from),
                       "stamp_expire_legal",
                       GNUNET_JSON_from_time_abs (dk->expire_legal),
                       "value",
                       TALER_JSON_from_amount (&dk->value),
                       "fee_withdraw",
                       /* #6 */
                       TALER_JSON_from_amount (&dk->fee_withdraw),
                       "fee_deposit",
                       TALER_JSON_from_amount (&dk->fee_deposit),
                       "fee_refresh",
                       TALER_JSON_from_amount (&dk->fee_refresh),
                       "fee_refund",
                       TALER_JSON_from_amount (&dk->fee_refund),
                       "master_sig",
                       GNUNET_JSON_from_data_auto (&dk->master_sig),
                       /* #10 */
                       "denom_pub",
                       GNUNET_JSON_from_rsa_public_key (
                         dk->key.rsa_public_key));
    if (NULL == denom)
    {
      GNUNET_break (0);
      continue;
    }
    if (0 != json_array_append_new (denoms,
                                    denom))
    {
      GNUNET_break (0);
      json_decref (denom);
      json_decref (denoms);
      json_decref (signkeys);
      return NULL;
    }
  }
  auditors = json_array ();
  if (NULL == auditors)
  {
    GNUNET_break (0);
    json_decref (denoms);
    json_decref (signkeys);
    return NULL;
  }
  for (unsigned int i = 0; i<kd->num_auditors; i++)
  {
    const struct TALER_EXCHANGE_AuditorInformation *ai = &kd->auditors[i];
    json_t *a;
    json_t *adenoms;

    adenoms = json_array ();
    if (NULL == adenoms)
    {
      GNUNET_break (0);
      json_decref (denoms);
      json_decref (signkeys);
      json_decref (auditors);
      return NULL;
    }
    for (unsigned int j = 0; j<ai->num_denom_keys; j++)
    {
      const struct TALER_EXCHANGE_AuditorDenominationInfo *adi =
        &ai->denom_keys[j];
      const struct TALER_EXCHANGE_DenomPublicKey *dk =
        &kd->denom_keys[adi->denom_key_offset];
      json_t *k;

      if (now.abs_value_us > dk->expire_deposit.abs_value_us)
        continue; /* skip auditor signatures for denomination keys that have expired */
      GNUNET_assert (adi->denom_key_offset < kd->num_denom_keys);
      k = json_pack ("{s:o, s:o}",
                     "denom_pub_h",
                     GNUNET_JSON_from_data_auto (&dk->h_key),
                     "auditor_sig",
                     GNUNET_JSON_from_data_auto (&adi->auditor_sig));
      if (NULL == k)
      {
        GNUNET_break (0);
        json_decref (adenoms);
        json_decref (denoms);
        json_decref (signkeys);
        json_decref (auditors);
        return NULL;
      }
      if (0 != json_array_append_new (adenoms,
                                      k))
      {
        GNUNET_break (0);
        json_decref (k);
        json_decref (adenoms);
        json_decref (denoms);
        json_decref (signkeys);
        json_decref (auditors);
        return NULL;
      }
    }

    a = json_pack ("{s:o, s:s, s:o}",
                   "auditor_pub",
                   GNUNET_JSON_from_data_auto (&ai->auditor_pub),
                   "auditor_url",
                   ai->auditor_url,
                   "denomination_keys",
                   adenoms);
    if (NULL == a)
    {
      json_decref (adenoms);
      json_decref (denoms);
      json_decref (signkeys);
      json_decref (auditors);
      return NULL;
    }
    if (0 != json_array_append_new (auditors,
                                    a))
    {
      json_decref (a);
      json_decref (denoms);
      json_decref (signkeys);
      json_decref (auditors);
      return NULL;
    }
  }
  keys = json_pack ("{s:s, s:o, s:o, s:o, s:o"
                    ",s:o, s:o}",
                    /* 1 */
                    "version",
                    kd->version,
                    "master_public_key",
                    GNUNET_JSON_from_data_auto (&kd->master_pub),
                    "reserve_closing_delay",
                    GNUNET_JSON_from_time_rel (kd->reserve_closing_delay),
                    "list_issue_date",
                    GNUNET_JSON_from_time_abs (kd->list_issue_date),
                    "signkeys",
                    signkeys,
                    /* #6 */
                    "denoms",
                    denoms,
                    "auditors",
                    auditors);
  if (NULL == keys)
  {
    GNUNET_break (0);
    return NULL;
  }
  return json_pack ("{s:I, s:o, s:s, s:o}",
                    "version",
                    (json_int_t) EXCHANGE_SERIALIZATION_FORMAT_VERSION,
                    "expire",
                    GNUNET_JSON_from_time_abs (exchange->key_data_expiration),
                    "exchange_url",
                    exchange->url,
                    "keys",
                    keys);
}


/**
 * Initialise a connection to the exchange. Will connect to the
 * exchange and obtain information about the exchange's master
 * public key and the exchange's auditor.
 * The respective information will be passed to the @a cert_cb
 * once available, and all future interactions with the exchange
 * will be checked to be signed (where appropriate) by the
 * respective master key.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param cert_cb function to call with the exchange's
 *        certification information
 * @param cert_cb_cls closure for @a cert_cb
 * @param ... list of additional arguments,
 *        terminated by #TALER_EXCHANGE_OPTION_END.
 * @return the exchange handle; NULL upon error
 */
struct TALER_EXCHANGE_Handle *
TALER_EXCHANGE_connect (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  TALER_EXCHANGE_CertificationCallback cert_cb,
  void *cert_cb_cls,
  ...)
{
  struct TALER_EXCHANGE_Handle *exchange;
  va_list ap;
  enum TALER_EXCHANGE_Option opt;

  TALER_LOG_DEBUG ("Connecting to the exchange (%s)\n",
                   url);
  /* Disable 100 continue processing */
  GNUNET_break (GNUNET_OK ==
                GNUNET_CURL_append_header (ctx,
                                           "Expect:"));
  exchange = GNUNET_new (struct TALER_EXCHANGE_Handle);
  exchange->ctx = ctx;
  exchange->url = GNUNET_strdup (url);
  exchange->cert_cb = cert_cb;
  exchange->cert_cb_cls = cert_cb_cls;
  exchange->retry_task = GNUNET_SCHEDULER_add_now (&request_keys,
                                                   exchange);
  va_start (ap, cert_cb_cls);
  while (TALER_EXCHANGE_OPTION_END !=
         (opt = va_arg (ap, int)))
  {
    switch (opt)
    {
    case TALER_EXCHANGE_OPTION_END:
      GNUNET_assert (0);
      break;
    case TALER_EXCHANGE_OPTION_DATA:
      {
        const json_t *data = va_arg (ap, const json_t *);

        deserialize_data (exchange,
                          data);
        break;
      }
    default:
      GNUNET_assert (0);
      break;
    }
  }
  va_end (ap);
  return exchange;
}


/**
 * Initiate download of /keys from the exchange.
 *
 * @param cls exchange where to download /keys from
 */
static void
request_keys (void *cls)
{
  struct TALER_EXCHANGE_Handle *exchange = cls;
  struct KeysRequest *kr;
  CURL *eh;
  char url[200] = "/keys?";

  exchange->retry_task = NULL;
  GNUNET_assert (NULL == exchange->kr);
  kr = GNUNET_new (struct KeysRequest);
  kr->exchange = exchange;

  if (GNUNET_YES == TEAH_handle_is_ready (exchange))
  {
    TALER_LOG_DEBUG ("Last DK issue date (before GETting /keys): %s\n",
                     GNUNET_STRINGS_absolute_time_to_string (
                       exchange->key_data.last_denom_issue_date));
    sprintf (&url[strlen (url)],
             "last_issue_date=%llu&",
             (unsigned long
              long) exchange->key_data.last_denom_issue_date.abs_value_us
             / 1000000LLU);
  }

  if (GNUNET_YES == exchange->with_now)
  {
    TALER_LOG_DEBUG ("Faking now to GET /keys: %s\n",
                     GNUNET_STRINGS_absolute_time_to_string (exchange->now));
    sprintf (&url[strlen (url)],
             "now=%llu&",
             (unsigned long long) exchange->now.abs_value_us / 1000000LLU);
  }

  /* Clean the last '&'/'?' sign that we optimistically put.  */
  url[strlen (url) - 1] = '\0';
  kr->url = TEAH_path_to_url (exchange,
                              url);

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting keys with URL `%s'.\n",
              kr->url);
  eh = TALER_EXCHANGE_curl_easy_get_ (kr->url);
  if (NULL == eh)
  {
    exchange->retry_delay = EXCHANGE_LIB_BACKOFF (exchange->retry_delay);
    exchange->retry_task = GNUNET_SCHEDULER_add_delayed (exchange->retry_delay,
                                                         &request_keys,
                                                         exchange);
    return;
  }
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  0));
  GNUNET_break (CURLE_OK ==
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
  kr->job = GNUNET_CURL_job_add (exchange->ctx,
                                 eh,
                                 GNUNET_YES,
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
  struct TEAH_AuditorListEntry *ale;

  while (NULL != (ale = exchange->auditors_head))
  {
    struct TEAH_AuditorInteractionEntry *aie;

    while (NULL != (aie = ale->ai_head))
    {
      GNUNET_assert (aie->ale == ale);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Not sending deposit confirmation to auditor `%s' due to exchange disconnect\n",
                  ale->auditor_url);
      TALER_AUDITOR_deposit_confirmation_cancel (aie->dch);
      GNUNET_CONTAINER_DLL_remove (ale->ai_head,
                                   ale->ai_tail,
                                   aie);
      GNUNET_free (aie);
    }
    GNUNET_CONTAINER_DLL_remove (exchange->auditors_head,
                                 exchange->auditors_tail,
                                 ale);
    TALER_LOG_DEBUG ("Disconnecting the auditor `%s'\n",
                     ale->auditor_url);
    TALER_AUDITOR_disconnect (ale->ah);
    GNUNET_free (ale->auditor_url);
    GNUNET_free (ale);
  }
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
  if (NULL != exchange->retry_task)
  {
    GNUNET_SCHEDULER_cancel (exchange->retry_task);
    exchange->retry_task = NULL;
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

  /* we will check using a tolerance of 1h for the time */
  now = GNUNET_TIME_absolute_get ();
  for (unsigned int i = 0; i<keys->num_sign_keys; i++)
    if ( (keys->sign_keys[i].valid_from.abs_value_us <= now.abs_value_us + 60
          * 60 * 1000LL * 1000LL) &&
         (keys->sign_keys[i].valid_until.abs_value_us > now.abs_value_us - 60
          * 60 * 1000LL * 1000LL) &&
         (0 == GNUNET_memcmp (pub,
                              &keys->sign_keys[i].key)) )
      return GNUNET_OK;
  return GNUNET_SYSERR;
}


/**
 * Get exchange's base URL.
 *
 * @param exchange exchange handle.
 * @return the base URL from the handle.
 */
const char *
TALER_EXCHANGE_get_base_url (const struct TALER_EXCHANGE_Handle *exchange)
{
  return exchange->url;
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
TALER_EXCHANGE_get_denomination_key (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_DenominationPublicKey *pk)
{
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
    if (0 == GNUNET_CRYPTO_rsa_public_key_cmp (pk->rsa_public_key,
                                               keys->denom_keys[i].key.
                                               rsa_public_key))
      return &keys->denom_keys[i];
  return NULL;
}


/**
 * Create a copy of a denomination public key.
 *
 * @param key key to copy
 * @returns a copy, must be freed with #TALER_EXCHANGE_destroy_denomination_key
 */
struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_copy_denomination_key (
  const struct TALER_EXCHANGE_DenomPublicKey *key)
{
  struct TALER_EXCHANGE_DenomPublicKey *copy;

  copy = GNUNET_new (struct TALER_EXCHANGE_DenomPublicKey);
  *copy = *key;
  copy->key.rsa_public_key = GNUNET_CRYPTO_rsa_public_key_dup (
    key->key.rsa_public_key);

  return copy;
}


/**
 * Destroy a denomination public key.
 * Should only be called with keys created by #TALER_EXCHANGE_copy_denomination_key.
 *
 * @param key key to destroy.
 */
void
TALER_EXCHANGE_destroy_denomination_key (
  struct TALER_EXCHANGE_DenomPublicKey *key)
{
  GNUNET_CRYPTO_rsa_public_key_free (key->key.rsa_public_key);;
  GNUNET_free (key);
}


/**
 * Obtain the denomination key details from the exchange.
 *
 * @param keys the exchange's key set
 * @param hc hash of the public key of the denomination to lookup
 * @return details about the given denomination key
 */
const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key_by_hash (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct GNUNET_HashCode *hc)
{
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
    if (0 == GNUNET_memcmp (hc,
                            &keys->denom_keys[i].h_key))
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
  (void) TALER_EXCHANGE_check_keys_current (exchange,
                                            GNUNET_NO,
                                            GNUNET_NO);
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
  (void) TALER_EXCHANGE_check_keys_current (exchange,
                                            GNUNET_NO,
                                            GNUNET_NO);
  return json_deep_copy (exchange->key_data_raw);
}


/* end of exchange_api_handle.c */
