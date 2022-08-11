/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
#include "taler_extensions.h"
#include "exchange_api_handle.h"
#include "exchange_api_curl_defaults.h"
#include "backoff.h"
#include "taler_curl_lib.h"

/**
 * Which version of the Taler protocol is implemented
 * by this library?  Used to determine compatibility.
 */
#define EXCHANGE_PROTOCOL_CURRENT 14

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
 * How far off do we allow key liftimes to be?
 */
#define LIFETIME_TOLERANCE GNUNET_TIME_UNIT_HOURS

/**
 * If the "Expire" cache control header is missing, for
 * how long do we assume the reply to be valid at least?
 */
#define DEFAULT_EXPIRATION GNUNET_TIME_UNIT_HOURS

/**
 * Set to 1 for extra debug logging.
 */
#define DEBUG 0

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
  bool is_up;

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
  struct GNUNET_TIME_Timestamp expire;

};


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

    if (! ale->is_up)
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
static enum GNUNET_GenericReturnValue
parse_json_signkey (struct TALER_EXCHANGE_SigningPublicKey *sign_key,
                    bool check_sigs,
                    json_t *sign_key_obj,
                    const struct TALER_MasterPublicKeyP *master_key)
{
  struct TALER_MasterSignatureP sign_key_issue_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &sign_key_issue_sig),
    GNUNET_JSON_spec_fixed_auto ("key",
                                 &sign_key->key),
    GNUNET_JSON_spec_timestamp ("stamp_start",
                                &sign_key->valid_from),
    GNUNET_JSON_spec_timestamp ("stamp_expire",
                                &sign_key->valid_until),
    GNUNET_JSON_spec_timestamp ("stamp_end",
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
  if (GNUNET_OK !=
      TALER_exchange_offline_signkey_validity_verify (
        &sign_key->key,
        sign_key->valid_from,
        sign_key->valid_until,
        sign_key->valid_legal,
        master_key,
        &sign_key_issue_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  sign_key->master_sig = sign_key_issue_sig;
  return GNUNET_OK;
}


/**
 * Parse a exchange's denomination key encoded in JSON partially.
 *
 * Only the values for master_sig, timestamps and the cipher-specific public
 * key are parsed.  All other fields (fees, age_mask, value) MUST have been set
 * prior to calling this function, otherwise the signature verification
 * performed within this function will fail.
 *
 * @param currency expected currency of all fees
 * @param[out] denom_key where to return the result
 * @param cipher cipher type to parse
 * @param check_sigs should we check signatures?
 * @param[in] denom_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @param hash_xor where to accumulate data for signature verification via XOR
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static enum GNUNET_GenericReturnValue
parse_json_denomkey_partially (const char *currency,
                               struct TALER_EXCHANGE_DenomPublicKey *denom_key,
                               enum TALER_DenominationCipher cipher,
                               bool check_sigs,
                               json_t *denom_key_obj,
                               struct TALER_MasterPublicKeyP *master_key,
                               struct GNUNET_HashCode *hash_xor)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &denom_key->master_sig),
    GNUNET_JSON_spec_timestamp ("stamp_expire_deposit",
                                &denom_key->expire_deposit),
    GNUNET_JSON_spec_timestamp ("stamp_expire_withdraw",
                                &denom_key->withdraw_valid_until),
    GNUNET_JSON_spec_timestamp ("stamp_start",
                                &denom_key->valid_from),
    GNUNET_JSON_spec_timestamp ("stamp_expire_legal",
                                &denom_key->expire_legal),
    TALER_JSON_spec_denom_pub_cipher (NULL,
                                      cipher,
                                      &denom_key->key),
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
  TALER_denom_pub_hash (&denom_key->key,
                        &denom_key->h_key);
  if (NULL != hash_xor)
    GNUNET_CRYPTO_hash_xor (&denom_key->h_key.hash,
                            hash_xor,
                            hash_xor);

  if (! check_sigs)
    return GNUNET_OK;
  EXITIF (GNUNET_SYSERR ==
          TALER_exchange_offline_denom_validity_verify (
            &denom_key->h_key,
            denom_key->valid_from,
            denom_key->withdraw_valid_until,
            denom_key->expire_deposit,
            denom_key->expire_legal,
            &denom_key->value,
            &denom_key->fees,
            master_key,
            &denom_key->master_sig));
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
static enum GNUNET_GenericReturnValue
parse_json_auditor (struct TALER_EXCHANGE_AuditorInformation *auditor,
                    bool check_sigs,
                    json_t *auditor_obj,
                    const struct TALER_EXCHANGE_Keys *key_data)
{
  json_t *keys;
  json_t *key;
  unsigned int len;
  unsigned int off;
  unsigned int i;
  const char *auditor_url;
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
#if DEBUG
    json_dumpf (auditor_obj,
                stderr,
                JSON_INDENT (2));
#endif
    return GNUNET_SYSERR;
  }
  auditor->auditor_url = GNUNET_strdup (auditor_url);
  len = json_array_size (keys);
  auditor->denom_keys = GNUNET_new_array (len,
                                          struct
                                          TALER_EXCHANGE_AuditorDenominationInfo);
  off = 0;
  json_array_foreach (keys, i, key) {
    struct TALER_AuditorSignatureP auditor_sig;
    struct TALER_DenominationHashP denom_h;
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
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Auditor signed denomination %s, which we do not know. Ignoring signature.\n",
                  GNUNET_h2s (&denom_h.hash));
      continue;
    }
    if (check_sigs)
    {
      if (GNUNET_OK !=
          TALER_auditor_denom_validity_verify (
            auditor_url,
            &dk->h_key,
            &key_data->master_pub,
            dk->valid_from,
            dk->withdraw_valid_until,
            dk->expire_deposit,
            dk->expire_legal,
            &dk->value,
            &dk->fees,
            &auditor->auditor_pub,
            &auditor_sig))
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
 * Parse a exchange's global fee information encoded in JSON.
 *
 * @param[out] gf where to return the result
 * @param check_sigs should we check signatures
 * @param[in] fee_obj json to parse
 * @param key_data already parsed information about the exchange
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static enum GNUNET_GenericReturnValue
parse_global_fee (struct TALER_EXCHANGE_GlobalFee *gf,
                  bool check_sigs,
                  json_t *fee_obj,
                  const struct TALER_EXCHANGE_Keys *key_data)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("start_date",
                                &gf->start_date),
    GNUNET_JSON_spec_timestamp ("end_date",
                                &gf->end_date),
    GNUNET_JSON_spec_relative_time ("purse_timeout",
                                    &gf->purse_timeout),
    GNUNET_JSON_spec_relative_time ("account_kyc_timeout",
                                    &gf->kyc_timeout),
    GNUNET_JSON_spec_relative_time ("history_expiration",
                                    &gf->history_expiration),
    GNUNET_JSON_spec_uint32 ("purse_account_limit",
                             &gf->purse_account_limit),
    TALER_JSON_SPEC_GLOBAL_FEES (key_data->currency,
                                 &gf->fees),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &gf->master_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (fee_obj,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
#if DEBUG
    json_dumpf (fee_obj,
                stderr,
                JSON_INDENT (2));
#endif
    return GNUNET_SYSERR;
  }
  if (check_sigs)
  {
    if (GNUNET_OK !=
        TALER_exchange_offline_global_fee_verify (
          gf->start_date,
          gf->end_date,
          &gf->fees,
          gf->purse_timeout,
          gf->kyc_timeout,
          gf->history_expiration,
          gf->purse_account_limit,
          &key_data->master_pub,
          &gf->master_sig))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return GNUNET_SYSERR;
    }
  }
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

  (void) hr;
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
  ale->is_up = true;
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
    TALER_LOG_DEBUG ("Found new auditor %s!\n",
                     auditor->auditor_url);
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
denoms_cmp (const struct TALER_EXCHANGE_DenomPublicKey *denom1,
            const struct TALER_EXCHANGE_DenomPublicKey *denom2)
{
  struct TALER_EXCHANGE_DenomPublicKey tmp1;
  struct TALER_EXCHANGE_DenomPublicKey tmp2;

  if (0 !=
      TALER_denom_pub_cmp (&denom1->key,
                           &denom2->key))
    return 1;
  tmp1 = *denom1;
  tmp2 = *denom2;
  tmp1.revoked = false;
  tmp2.revoked = false;
  memset (&tmp1.key,
          0,
          sizeof (tmp1.key));
  memset (&tmp2.key,
          0,
          sizeof (tmp2.key));
  return GNUNET_memcmp (&tmp1,
                        &tmp2);
}


/**
 * Decode the JSON in @a resp_obj from the /keys response
 * and store the data in the @a key_data.
 *
 * @param[in] resp_obj JSON object to parse
 * @param check_sig true if we should check the signature
 * @param[out] key_data where to store the results we decoded
 * @param[out] vc where to store version compatibility data
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 * (malformed JSON)
 */
static enum GNUNET_GenericReturnValue
decode_keys_json (const json_t *resp_obj,
                  bool check_sig,
                  struct TALER_EXCHANGE_Keys *key_data,
                  enum TALER_EXCHANGE_VersionCompatibility *vc)
{
  struct TALER_ExchangeSignatureP denominations_sig;
  struct GNUNET_HashCode hash_xor = {0};
  struct TALER_ExchangePublicKeyP pub;
  const char *currency;
  json_t *wblwk = NULL;
  struct GNUNET_JSON_Specification mspec[] = {
    GNUNET_JSON_spec_fixed_auto ("denominations_sig",
                                 &denominations_sig),
    GNUNET_JSON_spec_fixed_auto ("eddsa_pub",
                                 &pub),
    GNUNET_JSON_spec_fixed_auto ("master_public_key",
                                 &key_data->master_pub),
    GNUNET_JSON_spec_timestamp ("list_issue_date",
                                &key_data->list_issue_date),
    GNUNET_JSON_spec_relative_time ("reserve_closing_delay",
                                    &key_data->reserve_closing_delay),
    GNUNET_JSON_spec_string ("currency",
                             &currency),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_json ("wallet_balance_limit_without_kyc",
                             &wblwk),
      NULL),
    GNUNET_JSON_spec_end ()
  };

  if (JSON_OBJECT != json_typeof (resp_obj))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
#if DEBUG
  json_dumpf (resp_obj,
              stderr,
              JSON_INDENT (2));
#endif
  /* check the version first */
  {
    const char *ver;
    unsigned int age;
    unsigned int revision;
    unsigned int current;
    char dummy;
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
                     "%u:%u:%u%c",
                     &current,
                     &revision,
                     &age,
                     &dummy))
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

  EXITIF (GNUNET_OK !=
          GNUNET_JSON_parse (resp_obj,
                             (check_sig) ? mspec : &mspec[2],
                             NULL, NULL));
  key_data->currency = GNUNET_strdup (currency);

  /* parse the global fees */
  {
    json_t *global_fees;
    json_t *global_fee;
    unsigned int index;

    EXITIF (NULL == (global_fees =
                       json_object_get (resp_obj,
                                        "global_fees")));
    EXITIF (! json_is_array (global_fees));
    if (0 != (key_data->num_global_fees =
                json_array_size (global_fees)))
    {
      key_data->global_fees
        = GNUNET_new_array (key_data->num_global_fees,
                            struct TALER_EXCHANGE_GlobalFee);
      json_array_foreach (global_fees, index, global_fee) {
        EXITIF (GNUNET_SYSERR ==
                parse_global_fee (&key_data->global_fees[index],
                                  check_sig,
                                  global_fee,
                                  key_data));
      }
    }
  }

  /* parse the signing keys */
  {
    json_t *sign_keys_array;
    json_t *sign_key_obj;
    unsigned int index;

    EXITIF (NULL == (sign_keys_array =
                       json_object_get (resp_obj,
                                        "signkeys")));
    EXITIF (! json_is_array (sign_keys_array));
    if (0 != (key_data->num_sign_keys =
                json_array_size (sign_keys_array)))
    {
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
  }

  /* Parse balance limits */
  if (NULL != wblwk)
  {
    key_data->wblwk_length = json_array_size (wblwk);
    key_data->wallet_balance_limit_without_kyc
      = GNUNET_new_array (key_data->wblwk_length,
                          struct TALER_Amount);
    for (unsigned int i = 0; i<key_data->wblwk_length; i++)
    {
      struct TALER_Amount *a = &key_data->wallet_balance_limit_without_kyc[i];
      const json_t *aj = json_array_get (wblwk,
                                         i);
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount (NULL,
                                currency,
                                a),
        GNUNET_JSON_spec_end ()
      };

      EXITIF (GNUNET_OK !=
              GNUNET_JSON_parse (aj,
                                 spec,
                                 NULL, NULL));
    }
  }

  /* Parse the supported extension(s): age-restriction. */
  /* TODO: maybe lift all this into a FP in TALER_Extension ? */
  {
    struct TALER_MasterSignatureP extensions_sig = {0};
    json_t *extensions = NULL;
    struct GNUNET_JSON_Specification ext_spec[] = {
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_json ("extensions",
                               &extensions),
        NULL),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_fixed_auto (
          "extensions_sig",
          &extensions_sig),
        NULL),
      GNUNET_JSON_spec_end ()
    };

    /* 1. Search for extensions in the response to /keys */
    EXITIF (GNUNET_OK !=
            GNUNET_JSON_parse (resp_obj,
                               ext_spec,
                               NULL, NULL));

    if (NULL != extensions)
    {
      /* 2. We have an extensions object. Verify its signature. */
      EXITIF (GNUNET_OK !=
              TALER_extensions_verify_json_config_signature (
                extensions,
                &extensions_sig,
                &key_data->master_pub));

      /* 3. Parse and set the the configuration of the extensions accordingly */
      EXITIF (GNUNET_OK !=
              TALER_extensions_load_json_config (extensions));
    }

    /* 4. assuming we might have now a new value for age_mask, set it in key_data */
    key_data->age_mask = TALER_extensions_age_restriction_ageMask ();
  }

  /**
   * Parse the denomination keys, merging with the
   * possibly EXISTING array as required (/keys cherry picking).
   *
   * The denominations are grouped by common values of
   *    {cipher, value, fee, age_mask}.
   **/
  {
    json_t *denominations_by_group;
    json_t *group_obj;
    unsigned int group_idx;

    denominations_by_group =
      json_object_get (
        resp_obj,
        "denominations");

    EXITIF (JSON_ARRAY !=
            json_typeof (denominations_by_group));

    json_array_foreach (denominations_by_group, group_idx, group_obj) {
      // Running XOR of each SHA512 hash of the denominations' public key in
      // this group.  Used to compare against group.hash after all keys have
      // been parsed.
      struct GNUNET_HashCode group_hash_xor = {0};

      // First, parse { cipher, fees, value, age_mask, hash } of the current
      // group.
      struct TALER_DenominationGroup group = {0};
      struct GNUNET_JSON_Specification group_spec[] = {
        TALER_JSON_spec_denomination_group (NULL, currency, &group),
        GNUNET_JSON_spec_end ()
      };
      EXITIF (GNUNET_SYSERR ==
              GNUNET_JSON_parse (group_obj,
                                 group_spec,
                                 NULL,
                                 NULL));

      // Now, parse the individual denominations
      {
        json_t *denom_keys_array;
        json_t *denom_key_obj;
        unsigned int index;
        denom_keys_array = json_object_get (group_obj, "denoms");
        EXITIF (JSON_ARRAY != json_typeof (denom_keys_array));

        json_array_foreach (denom_keys_array, index, denom_key_obj) {
          struct TALER_EXCHANGE_DenomPublicKey dk = {0};
          bool found = false;

          memset (&dk, 0, sizeof (dk));

          // Set the common fields from the group for this particular
          // denomination.  Required to make the validity check inside
          // parse_json_denomkey_partially pass
          dk.key.cipher = group.cipher;
          dk.value = group.value;
          dk.fees = group.fees;
          dk.key.age_mask = group.age_mask;

          EXITIF (GNUNET_SYSERR ==
                  parse_json_denomkey_partially (key_data->currency,
                                                 &dk,
                                                 group.cipher,
                                                 check_sig,
                                                 denom_key_obj,
                                                 &key_data->master_pub,
                                                 check_sig ? &hash_xor : NULL));

          // Build the running xor of the SHA512-hash of the public keys
          {
            struct TALER_DenominationHashP hc = {0};
            TALER_denom_pub_hash (&dk.key, &hc);
            GNUNET_CRYPTO_hash_xor (&hc.hash,
                                    &group_hash_xor,
                                    &group_hash_xor);
          }

          for (unsigned int j = 0;
               j<key_data->num_denom_keys;
               j++)
          {
            if (0 == denoms_cmp (&dk,
                                 &key_data->denom_keys[j]))
            {
              found = true;
              break;
            }
          }

          if (found)
          {
            /* 0:0:0 did not support /keys cherry picking */
            TALER_LOG_DEBUG ("Skipping denomination key: already know it\n");
            TALER_denom_pub_free (&dk.key);
            continue;
          }

          if (key_data->denom_keys_size == key_data->num_denom_keys)
            GNUNET_array_grow (key_data->denom_keys,
                               key_data->denom_keys_size,
                               key_data->denom_keys_size * 2 + 2);
          key_data->denom_keys[key_data->num_denom_keys++] = dk;

          /* Update "last_denom_issue_date" */
          TALER_LOG_DEBUG ("Adding denomination key that is valid_until %s\n",
                           GNUNET_TIME_timestamp2s (dk.valid_from));
          key_data->last_denom_issue_date
            = GNUNET_TIME_timestamp_max (key_data->last_denom_issue_date,
                                         dk.valid_from);
        }; // json_array_foreach over denominations

        // The calculated group_hash_xor must be the same as group.hash from
        // the json.
        EXITIF (0 !=
                GNUNET_CRYPTO_hash_cmp (&group_hash_xor, &group.hash));

      } // block for parsing individual denominations
    }; // json_array_foreach over groups of denominations
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
      bool found = false;

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
          found = true;
          /* Merge denomination key signatures of downloaded /keys into existing
             auditor information 'aix'. */
          TALER_LOG_DEBUG (
            "Merging %u new audited keys with %u known audited keys\n",
            aix->num_denom_keys,
            ai.num_denom_keys);
          for (unsigned int i = 0; i<ai.num_denom_keys; i++)
          {
            bool kfound = false;

            for (unsigned int k = 0; k<aix->num_denom_keys; k++)
            {
              if (aix->denom_keys[k].denom_key_offset ==
                  ai.denom_keys[i].denom_key_offset)
              {
                kfound = true;
                break;
              }
            }
            if (! kfound)
              GNUNET_array_append (aix->denom_keys,
                                   aix->num_denom_keys,
                                   ai.denom_keys[i]);
          }
          break;
        }
      }
      if (found)
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
        struct TALER_DenominationHashP h_denom_pub;
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
    EXITIF (GNUNET_OK !=
            TALER_EXCHANGE_test_signing_key (key_data,
                                             &pub));

    EXITIF (GNUNET_OK !=
            TALER_exchange_online_key_set_verify (
              key_data->list_issue_date,
              &hash_xor,
              &pub,
              &denominations_sig));
  }

  return GNUNET_OK;

EXITIF_exit:
  *vc = TALER_EXCHANGE_VC_PROTOCOL_ERROR;
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
    TALER_denom_pub_free (&key_data->denom_keys[i].key);

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
  GNUNET_free (key_data->wallet_balance_limit_without_kyc);
  GNUNET_free (key_data->version);
  GNUNET_free (key_data->currency);
  GNUNET_free (key_data->global_fees);
}


/**
 * Initiate download of /keys from the exchange.
 *
 * @param cls exchange where to download /keys from
 */
static void
request_keys (void *cls);


void
TALER_EXCHANGE_set_last_denom (struct TALER_EXCHANGE_Handle *exchange,
                               struct GNUNET_TIME_Timestamp last_denom_new)
{
  TALER_LOG_DEBUG (
    "Application explicitly set last denomination validity to %s\n",
    GNUNET_TIME_timestamp2s (last_denom_new));
  exchange->key_data.last_denom_issue_date = last_denom_new;
}


struct GNUNET_TIME_Timestamp
TALER_EXCHANGE_check_keys_current (struct TALER_EXCHANGE_Handle *exchange,
                                   enum TALER_EXCHANGE_CheckKeysFlags flags)
{
  bool force_download = 0 != (flags & TALER_EXCHANGE_CKF_FORCE_DOWNLOAD);
  bool pull_all_keys = 0 != (flags & TALER_EXCHANGE_CKF_PULL_ALL_KEYS);

  if (NULL != exchange->kr)
    return GNUNET_TIME_UNIT_ZERO_TS;

  if (pull_all_keys)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Forcing re-download of all exchange keys\n");
    GNUNET_break (GNUNET_YES == force_download);
    exchange->state = MHS_INIT;
  }
  if ( (! force_download) &&
       (GNUNET_TIME_absolute_is_future (
          exchange->key_data_expiration.abs_time)) )
    return exchange->key_data_expiration;
  if (NULL == exchange->retry_task)
    exchange->retry_task = GNUNET_SCHEDULER_add_now (&request_keys,
                                                     exchange);
  return GNUNET_TIME_UNIT_ZERO_TS;
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
              "Received keys from URL `%s' with status %ld and expiration %s.\n",
              kr->url,
              response_code,
              GNUNET_TIME_timestamp2s (kr->expire));
  if (GNUNET_TIME_absolute_is_past (kr->expire.abs_time))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Exchange failed to give expiration time, assuming in %s\n",
                GNUNET_TIME_relative2s (DEFAULT_EXPIRATION,
                                        true));
    kr->expire
      = GNUNET_TIME_absolute_to_timestamp (
          GNUNET_TIME_relative_to_absolute (DEFAULT_EXPIRATION));
  }
  kd_old = exchange->key_data;
  memset (&kd,
          0,
          sizeof (struct TALER_EXCHANGE_Keys));
  vc = TALER_EXCHANGE_VC_PROTOCOL_ERROR;
  switch (response_code)
  {
  case 0:
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to receive /keys response from exchange %s\n",
                exchange->url);
    free_keys_request (kr);
    exchange->keys_error_count++;
    exchange->kr = NULL;
    GNUNET_assert (NULL == exchange->retry_task);
    exchange->retry_delay = EXCHANGE_LIB_BACKOFF (exchange->retry_delay);
    exchange->retry_task = GNUNET_SCHEDULER_add_delayed (exchange->retry_delay,
                                                         &request_keys,
                                                         exchange);
    return;
  case MHD_HTTP_OK:
    exchange->keys_error_count = 0;
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
      TALER_denom_pub_deep_copy (&kd.denom_keys[i].key,
                                 &kd_old.denom_keys[i].key);

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
                          true,
                          &kd,
                          &vc))
    {
      TALER_LOG_ERROR ("Could not decode /keys response\n");
      hr.http_status = 0;
      hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
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
        TALER_denom_pub_free (&kd.denom_keys[i].key);
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
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_UNAUTHORIZED:
  case MHD_HTTP_FORBIDDEN:
  case MHD_HTTP_NOT_FOUND:
    if (NULL == j)
    {
      hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      hr.hint = TALER_ErrorCode_get_hint (hr.ec);
    }
    else
    {
      hr.ec = TALER_JSON_get_error_code (j);
      hr.hint = TALER_JSON_get_error_hint (j);
    }
    break;
  default:
    if (MHD_HTTP_GATEWAY_TIMEOUT == response_code)
      exchange->keys_error_count++;
    if (NULL == j)
    {
      hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      hr.hint = TALER_ErrorCode_get_hint (hr.ec);
    }
    else
    {
      hr.ec = TALER_JSON_get_error_code (j);
      hr.hint = TALER_JSON_get_error_hint (j);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) hr.ec);
    break;
  }
  exchange->key_data = kd;
  if (GNUNET_TIME_absolute_is_past (
        exchange->key_data.last_denom_issue_date.abs_time))
    TALER_LOG_WARNING ("Last DK issue date from exchange is in the past: %s\n",
                       GNUNET_TIME_timestamp2s (
                         exchange->key_data.last_denom_issue_date));
  else
    TALER_LOG_DEBUG ("Last DK issue date updated to: %s\n",
                     GNUNET_TIME_timestamp2s (
                       exchange->key_data.last_denom_issue_date));


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


struct GNUNET_CURL_Context *
TEAH_handle_to_context (struct TALER_EXCHANGE_Handle *h)
{
  return h->ctx;
}


enum GNUNET_GenericReturnValue
TEAH_handle_is_ready (struct TALER_EXCHANGE_Handle *h)
{
  return (MHS_CERT == h->state) ? GNUNET_YES : GNUNET_NO;
}


char *
TEAH_path_to_url (struct TALER_EXCHANGE_Handle *h,
                  const char *path)
{
  GNUNET_assert ('/' == path[0]);
  return TALER_url_join (h->url,
                         path + 1,
                         NULL);
}


/**
 * Define a max length for the HTTP "Expire:" header
 */
#define MAX_DATE_LINE_LEN 32


/**
 * Parse HTTP timestamp.
 *
 * @param dateline header to parse header
 * @param at where to write the result
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
parse_date_string (const char *dateline,
                   struct GNUNET_TIME_Timestamp *at)
{
  static const char *MONTHS[] =
  { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec", NULL };
  int year;
  int mon;
  int day;
  int hour;
  int min;
  int sec;
  char month[4];
  struct tm tm;
  time_t t;

  /* We recognize the three formats in RFC2616, section 3.3.1.  Month
     names are always in English.  The formats are:
      Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
      Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
      Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
     Note that the first is preferred.
   */

  if (strlen (dateline) > MAX_DATE_LINE_LEN)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  while (*dateline == ' ')
    ++dateline;
  while (*dateline && *dateline != ' ')
    ++dateline;
  while (*dateline == ' ')
    ++dateline;
  /* We just skipped over the day of the week. Now we have:*/
  if ( (sscanf (dateline,
                "%d %3s %d %d:%d:%d",
                &day, month, &year, &hour, &min, &sec) != 6) &&
       (sscanf (dateline,
                "%d-%3s-%d %d:%d:%d",
                &day, month, &year, &hour, &min, &sec) != 6) &&
       (sscanf (dateline,
                "%3s %d %d:%d:%d %d",
                month, &day, &hour, &min, &sec, &year) != 6) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* Two digit dates are defined to be relative to 1900; all other dates
   * are supposed to be represented as four digits. */
  if (year < 100)
    year += 1900;

  for (mon = 0; ; mon++)
  {
    if (! MONTHS[mon])
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (0 == strcasecmp (month,
                         MONTHS[mon]))
      break;
  }

  memset (&tm, 0, sizeof(tm));
  tm.tm_year = year - 1900;
  tm.tm_mon = mon;
  tm.tm_mday = day;
  tm.tm_hour = hour;
  tm.tm_min = min;
  tm.tm_sec = sec;

  t = mktime (&tm);
  if (((time_t) -1) == t)
  {
    GNUNET_log_strerror (GNUNET_ERROR_TYPE_ERROR,
                         "mktime");
    return GNUNET_SYSERR;
  }
  if (t < 0)
    t = 0; /* can happen due to timezone issues if date was 1.1.1970 */
  *at = GNUNET_TIME_timestamp_from_s (t);
  return GNUNET_OK;
}


/**
 * Function called for each header in the HTTP /keys response.
 * Finds the "Expire:" header and parses it, storing the result
 * in the "expire" field of the keys request.
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
    kr->expire = GNUNET_TIME_UNIT_ZERO_TS;
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
  struct GNUNET_TIME_Timestamp expire;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint32 ("version",
                             &version),
    GNUNET_JSON_spec_json ("keys",
                           &keys),
    GNUNET_JSON_spec_string ("exchange_url",
                             &url),
    GNUNET_JSON_spec_timestamp ("expire",
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
                        false,
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


json_t *
TALER_EXCHANGE_serialize_data (struct TALER_EXCHANGE_Handle *exchange)
{
  const struct TALER_EXCHANGE_Keys *kd = &exchange->key_data;
  struct GNUNET_TIME_Timestamp now;
  json_t *keys;
  json_t *signkeys;
  json_t *denoms;
  json_t *auditors;

  now = GNUNET_TIME_timestamp_get ();
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

    if (GNUNET_TIME_timestamp_cmp (now,
                                   >,
                                   sk->valid_until))
      continue; /* skip keys that have expired */
    signkey = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto ("key",
                                  &sk->key),
      GNUNET_JSON_pack_data_auto ("master_sig",
                                  &sk->master_sig),
      GNUNET_JSON_pack_timestamp ("stamp_start",
                                  sk->valid_from),
      GNUNET_JSON_pack_timestamp ("stamp_expire",
                                  sk->valid_until),
      GNUNET_JSON_pack_timestamp ("stamp_end",
                                  sk->valid_legal));
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

    if (GNUNET_TIME_timestamp_cmp (now,
                                   >,
                                   dk->expire_deposit))
      continue; /* skip keys that have expired */
    denom = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_timestamp ("stamp_expire_deposit",
                                  dk->expire_deposit),
      GNUNET_JSON_pack_timestamp ("stamp_expire_withdraw",
                                  dk->withdraw_valid_until),
      GNUNET_JSON_pack_timestamp ("stamp_start",
                                  dk->valid_from),
      GNUNET_JSON_pack_timestamp ("stamp_expire_legal",
                                  dk->expire_legal),
      TALER_JSON_pack_amount ("value",
                              &dk->value),
      TALER_JSON_PACK_DENOM_FEES ("fee",
                                  &dk->fees),
      GNUNET_JSON_pack_data_auto ("master_sig",
                                  &dk->master_sig),
      TALER_JSON_pack_denom_pub ("denom_pub",
                                 &dk->key));
    GNUNET_assert (0 ==
                   json_array_append_new (denoms,
                                          denom));
  }
  auditors = json_array ();
  GNUNET_assert (NULL != auditors);
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

      if (GNUNET_TIME_timestamp_cmp (now,
                                     >,
                                     dk->expire_deposit))
        continue; /* skip auditor signatures for denomination keys that have expired */
      GNUNET_assert (adi->denom_key_offset < kd->num_denom_keys);
      k = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("denom_pub_h",
                                    &dk->h_key),
        GNUNET_JSON_pack_data_auto ("auditor_sig",
                                    &adi->auditor_sig));
      GNUNET_assert (0 ==
                     json_array_append_new (adenoms,
                                            k));
    }

    a = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_data_auto ("auditor_pub",
                                  &ai->auditor_pub),
      GNUNET_JSON_pack_string ("auditor_url",
                               ai->auditor_url),
      GNUNET_JSON_pack_array_steal ("denomination_keys",
                                    adenoms));
    GNUNET_assert (0 ==
                   json_array_append_new (auditors,
                                          a));
  }
  keys = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("version",
                             kd->version),
    GNUNET_JSON_pack_string ("currency",
                             kd->currency),
    GNUNET_JSON_pack_data_auto ("master_public_key",
                                &kd->master_pub),
    GNUNET_JSON_pack_time_rel ("reserve_closing_delay",
                               kd->reserve_closing_delay),
    GNUNET_JSON_pack_timestamp ("list_issue_date",
                                kd->list_issue_date),
    GNUNET_JSON_pack_array_steal ("signkeys",
                                  signkeys),
    GNUNET_JSON_pack_array_steal ("denoms",
                                  denoms),
    GNUNET_JSON_pack_array_steal ("auditors",
                                  auditors));
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("version",
                             EXCHANGE_SERIALIZATION_FORMAT_VERSION),
    GNUNET_JSON_pack_timestamp ("expire",
                                exchange->key_data_expiration),
    GNUNET_JSON_pack_string ("exchange_url",
                             exchange->url),
    GNUNET_JSON_pack_object_steal ("keys",
                                   keys));
}


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
                                           MHD_HTTP_HEADER_EXPECT ":"));
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
 * Compute the network timeout for the next request to /keys.
 *
 * @param exchange the exchange handle
 * @returns the timeout in seconds (for use by CURL)
 */
static long
get_keys_timeout_seconds (struct TALER_EXCHANGE_Handle *exchange)
{
  unsigned int kec;

  /* if retry counter >= 8, do not bother to go further, we
     stop the exponential back-off at 128 anyway. */
  kec = GNUNET_MIN (7,
                    exchange->keys_error_count);
  return GNUNET_MIN (120,
                     5 + (1L << kec));
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
                     GNUNET_TIME_timestamp2s (
                       exchange->key_data.last_denom_issue_date));
    sprintf (&url[strlen (url)],
             "last_issue_date=%llu&",
             (unsigned long long)
             exchange->key_data.last_denom_issue_date.abs_time.abs_value_us
             / 1000000LLU);
  }

  /* Clean the last '&'/'?' sign that we optimistically put.  */
  url[strlen (url) - 1] = '\0';
  kr->url = TEAH_path_to_url (exchange,
                              url);
  if (NULL == kr->url)
  {
    struct TALER_EXCHANGE_HttpResponse hr = {
      .ec = TALER_EC_GENERIC_CONFIGURATION_INVALID
    };

    GNUNET_free (kr);
    exchange->keys_error_count++;
    exchange->state = MHS_FAILED;
    exchange->cert_cb (exchange->cert_cb_cls,
                       &hr,
                       NULL,
                       TALER_EXCHANGE_VC_PROTOCOL_ERROR);
    return;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Requesting keys with URL `%s'.\n",
              kr->url);
  eh = TALER_EXCHANGE_curl_easy_get_ (kr->url);
  if (NULL == eh)
  {
    GNUNET_free (kr->url);
    GNUNET_free (kr);
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
                                  get_keys_timeout_seconds (exchange)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HEADERFUNCTION,
                                   &header_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HEADERDATA,
                                   kr));
  kr->job = GNUNET_CURL_job_add_with_ct_json (exchange->ctx,
                                              eh,
                                              &keys_completed_cb,
                                              kr);
  exchange->kr = kr;
}


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


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_test_signing_key (const struct TALER_EXCHANGE_Keys *keys,
                                 const struct TALER_ExchangePublicKeyP *pub)
{
  struct GNUNET_TIME_Absolute now;

  /* we will check using a tolerance of 1h for the time */
  now = GNUNET_TIME_absolute_get ();
  for (unsigned int i = 0; i<keys->num_sign_keys; i++)
    if ( (GNUNET_TIME_absolute_cmp (
            keys->sign_keys[i].valid_from.abs_time,
            <=,
            GNUNET_TIME_absolute_add (now,
                                      LIFETIME_TOLERANCE))) &&
         (GNUNET_TIME_absolute_cmp (
            keys->sign_keys[i].valid_until.abs_time,
            >,
            GNUNET_TIME_absolute_subtract (now,
                                           LIFETIME_TOLERANCE))) &&
         (0 == GNUNET_memcmp (pub,
                              &keys->sign_keys[i].key)) )
      return GNUNET_OK;
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
              "Signing key not valid at time %s\n",
              GNUNET_TIME_absolute2s (now));
  return GNUNET_SYSERR;
}


const char *
TALER_EXCHANGE_get_base_url (const struct TALER_EXCHANGE_Handle *exchange)
{
  return exchange->url;
}


const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_DenominationPublicKey *pk)
{
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
    if (0 ==
        TALER_denom_pub_cmp (pk,
                             &keys->denom_keys[i].key))
      return &keys->denom_keys[i];
  return NULL;
}


const struct TALER_EXCHANGE_GlobalFee *
TALER_EXCHANGE_get_global_fee (
  const struct TALER_EXCHANGE_Keys *keys,
  struct GNUNET_TIME_Timestamp ts)
{
  for (unsigned int i = 0; i<keys->num_global_fees; i++)
  {
    const struct TALER_EXCHANGE_GlobalFee *gf = &keys->global_fees[i];

    if (GNUNET_TIME_timestamp_cmp (ts,
                                   >=,
                                   gf->start_date) &&
        GNUNET_TIME_timestamp_cmp (ts,
                                   <,
                                   gf->end_date))
      return gf;
  }
  return NULL;
}


struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_copy_denomination_key (
  const struct TALER_EXCHANGE_DenomPublicKey *key)
{
  struct TALER_EXCHANGE_DenomPublicKey *copy;

  copy = GNUNET_new (struct TALER_EXCHANGE_DenomPublicKey);
  *copy = *key;
  TALER_denom_pub_deep_copy (&copy->key,
                             &key->key);
  return copy;
}


void
TALER_EXCHANGE_destroy_denomination_key (
  struct TALER_EXCHANGE_DenomPublicKey *key)
{
  TALER_denom_pub_free (&key->key);
  GNUNET_free (key);
}


const struct TALER_EXCHANGE_DenomPublicKey *
TALER_EXCHANGE_get_denomination_key_by_hash (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_DenominationHashP *hc)
{
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
    if (0 == GNUNET_memcmp (hc,
                            &keys->denom_keys[i].h_key))
      return &keys->denom_keys[i];
  return NULL;
}


const struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_get_keys (struct TALER_EXCHANGE_Handle *exchange)
{
  (void) TALER_EXCHANGE_check_keys_current (exchange,
                                            TALER_EXCHANGE_CKF_NONE);
  return &exchange->key_data;
}


json_t *
TALER_EXCHANGE_get_keys_raw (struct TALER_EXCHANGE_Handle *exchange)
{
  (void) TALER_EXCHANGE_check_keys_current (exchange,
                                            TALER_EXCHANGE_CKF_NONE);
  return json_deep_copy (exchange->key_data_raw);
}


/* end of exchange_api_handle.c */
