/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
#define EXCHANGE_PROTOCOL_CURRENT 23

/**
 * How many versions are we backwards compatible with?
 */
#define EXCHANGE_PROTOCOL_AGE 6

/**
 * Set to 1 for extra debug logging.
 */
#define DEBUG 0

/**
 * Current version for (local) JSON serialization of persisted
 * /keys data.
 */
#define EXCHANGE_SERIALIZATION_FORMAT_VERSION 0

/**
 * How far off do we allow key lifetimes to be?
 */
#define LIFETIME_TOLERANCE GNUNET_TIME_UNIT_HOURS

/**
 * If the "Expire" cache control header is missing, for
 * how long do we assume the reply to be valid at least?
 */
#define DEFAULT_EXPIRATION GNUNET_TIME_UNIT_HOURS

/**
 * If the "Expire" cache control header is missing, for
 * how long do we assume the reply to be valid at least?
 */
#define MINIMUM_EXPIRATION GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_MINUTES, 2)


/**
 * Handle for a GET /keys request.
 */
struct TALER_EXCHANGE_GetKeysHandle
{

  /**
   * The exchange base URL (i.e. "https://exchange.demo.taler.net/")
   */
  char *exchange_url;

  /**
   * The url for the /keys request.
   */
  char *url;

  /**
   * Previous /keys response, NULL for none.
   */
  struct TALER_EXCHANGE_Keys *prev_keys;

  /**
   * Entry for this request with the `struct GNUNET_CURL_Context`.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Expiration time according to "Expire:" header.
   * 0 if not provided by the server.
   */
  struct GNUNET_TIME_Timestamp expire;

  /**
   * Function to call with the exchange's certification data,
   * NULL if this has already been done.
   */
  TALER_EXCHANGE_GetKeysCallback cert_cb;

  /**
   * Closure to pass to @e cert_cb.
   */
  void *cert_cb_cls;

};


/**
 * Element in the `struct SignatureContext` array.
 */
struct SignatureElement
{

  /**
   * Offset of the denomination in the group array,
   * for sorting (2nd rank, ascending).
   */
  unsigned int offset;

  /**
   * Offset of the group in the denominations array,
   * for sorting (2nd rank, ascending).
   */
  unsigned int group_offset;

  /**
   * Pointer to actual master signature to hash over.
   */
  struct TALER_MasterSignatureP master_sig;
};

/**
 * Context for collecting the array of master signatures
 * needed to verify the exchange_sig online signature.
 */
struct SignatureContext
{
  /**
   * Array of signatures to hash over.
   */
  struct SignatureElement *elements;

  /**
   * Write offset in the @e elements array.
   */
  unsigned int elements_pos;

  /**
   * Allocated space for @e elements.
   */
  unsigned int elements_size;
};


/**
 * Determine order to sort two elements by before
 * we hash the master signatures.  Used for
 * sorting with qsort().
 *
 * @param a pointer to a `struct SignatureElement`
 * @param b pointer to a `struct SignatureElement`
 * @return 0 if equal, -1 if a < b, 1 if a > b.
 */
static int
signature_context_sort_cb (const void *a,
                           const void *b)
{
  const struct SignatureElement *sa = a;
  const struct SignatureElement *sb = b;

  if (sa->group_offset < sb->group_offset)
    return -1;
  if (sa->group_offset > sb->group_offset)
    return 1;
  if (sa->offset < sb->offset)
    return -1;
  if (sa->offset > sb->offset)
    return 1;
  /* We should never have two disjoint elements
     with same time and offset */
  GNUNET_assert (sa == sb);
  return 0;
}


/**
 * Append a @a master_sig to the @a sig_ctx using the
 * given attributes for (later) sorting.
 *
 * @param[in,out] sig_ctx signature context to update
 * @param group_offset offset for the group
 * @param offset offset for the entry
 * @param master_sig master signature for the entry
 */
static void
append_signature (struct SignatureContext *sig_ctx,
                  unsigned int group_offset,
                  unsigned int offset,
                  const struct TALER_MasterSignatureP *master_sig)
{
  struct SignatureElement *element;
  unsigned int new_size;

  if (sig_ctx->elements_pos == sig_ctx->elements_size)
  {
    if (0 == sig_ctx->elements_size)
      new_size = 1024;
    else
      new_size = sig_ctx->elements_size * 2;
    GNUNET_array_grow (sig_ctx->elements,
                       sig_ctx->elements_size,
                       new_size);
  }
  element = &sig_ctx->elements[sig_ctx->elements_pos++];
  element->offset = offset;
  element->group_offset = group_offset;
  element->master_sig = *master_sig;
}


/**
 * Frees @a wfm array.
 *
 * @param wfm fee array to release
 * @param wfm_len length of the @a wfm array
 */
static void
free_fees (struct TALER_EXCHANGE_WireFeesByMethod *wfm,
           unsigned int wfm_len)
{
  for (unsigned int i = 0; i<wfm_len; i++)
  {
    struct TALER_EXCHANGE_WireFeesByMethod *wfmi = &wfm[i];

    while (NULL != wfmi->fees_head)
    {
      struct TALER_EXCHANGE_WireAggregateFees *fe
        = wfmi->fees_head;

      wfmi->fees_head = fe->next;
      GNUNET_free (fe);
    }
    GNUNET_free (wfmi->method);
  }
  GNUNET_free (wfm);
}


/**
 * Parse wire @a fees and return array.
 *
 * @param master_pub master public key to use to check signatures
 * @param currency currency amounts are expected in
 * @param fees json AggregateTransferFee to parse
 * @param[out] fees_len set to length of returned array
 * @return NULL on error
 */
static struct TALER_EXCHANGE_WireFeesByMethod *
parse_fees (const struct TALER_MasterPublicKeyP *master_pub,
            const char *currency,
            const json_t *fees,
            unsigned int *fees_len)
{
  struct TALER_EXCHANGE_WireFeesByMethod *fbm;
  size_t fbml = json_object_size (fees);
  unsigned int i = 0;
  const char *key;
  const json_t *fee_array;

  if (UINT_MAX < fbml)
  {
    GNUNET_break (0);
    return NULL;
  }
  fbm = GNUNET_new_array (fbml,
                          struct TALER_EXCHANGE_WireFeesByMethod);
  *fees_len = (unsigned int) fbml;
  json_object_foreach ((json_t *) fees, key, fee_array) {
    struct TALER_EXCHANGE_WireFeesByMethod *fe = &fbm[i++];
    size_t idx;
    json_t *fee;

    fe->method = GNUNET_strdup (key);
    fe->fees_head = NULL;
    json_array_foreach (fee_array, idx, fee)
    {
      struct TALER_EXCHANGE_WireAggregateFees *wa
        = GNUNET_new (struct TALER_EXCHANGE_WireAggregateFees);
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("sig",
                                     &wa->master_sig),
        TALER_JSON_spec_amount ("wire_fee",
                                currency,
                                &wa->fees.wire),
        TALER_JSON_spec_amount ("closing_fee",
                                currency,
                                &wa->fees.closing),
        GNUNET_JSON_spec_timestamp ("start_date",
                                    &wa->start_date),
        GNUNET_JSON_spec_timestamp ("end_date",
                                    &wa->end_date),
        GNUNET_JSON_spec_end ()
      };

      wa->next = fe->fees_head;
      fe->fees_head = wa;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (fee,
                             spec,
                             NULL,
                             NULL))
      {
        GNUNET_break_op (0);
        free_fees (fbm,
                   i);
        return NULL;
      }
      if (GNUNET_OK !=
          TALER_exchange_offline_wire_fee_verify (
            key,
            wa->start_date,
            wa->end_date,
            &wa->fees,
            master_pub,
            &wa->master_sig))
      {
        GNUNET_break_op (0);
        free_fees (fbm,
                   i);
        return NULL;
      }
    } /* for all fees over time */
  } /* for all methods */
  GNUNET_assert (i == fbml);
  return fbm;
}


void
TEAH_get_auditors_for_dc (
  struct TALER_EXCHANGE_Keys *keys,
  TEAH_AuditorCallback ac,
  void *ac_cls)
{
  if (0 == keys->num_auditors)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No auditor available. Not submitting deposit confirmations.\n")
    ;
    return;
  }
  for (unsigned int i = 0; i<keys->num_auditors; i++)
  {
    const struct TALER_EXCHANGE_AuditorInformation *auditor
      = &keys->auditors[i];

    ac (ac_cls,
        auditor->auditor_url,
        &auditor->auditor_pub);
  }
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
 * @param sign_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the @a sign_key_obj is malformed.
 */
static enum GNUNET_GenericReturnValue
parse_json_signkey (struct TALER_EXCHANGE_SigningPublicKey *sign_key,
                    bool check_sigs,
                    const json_t *sign_key_obj,
                    const struct TALER_MasterPublicKeyP *master_key)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &sign_key->master_sig),
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
        &sign_key->master_sig))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
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
 * @param[out] denom_key where to return the result
 * @param cipher cipher type to parse
 * @param check_sigs should we check signatures?
 * @param denom_key_obj json to parse
 * @param master_key master key to use to verify signature
 * @param group_offset offset for the group
 * @param index index of this denomination key in the group
 * @param sig_ctx where to write details about encountered
 *        master signatures, NULL if not used
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static enum GNUNET_GenericReturnValue
parse_json_denomkey_partially (
  struct TALER_EXCHANGE_DenomPublicKey *denom_key,
  enum GNUNET_CRYPTO_BlindSignatureAlgorithm cipher,
  bool check_sigs,
  const json_t *denom_key_obj,
  struct TALER_MasterPublicKeyP *master_key,
  unsigned int group_offset,
  unsigned int index,
  struct SignatureContext *sig_ctx)
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
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_bool ("lost",
                             &denom_key->lost),
      NULL),
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
  if (NULL != sig_ctx)
    append_signature (sig_ctx,
                      group_offset,
                      index,
                      &denom_key->master_sig);
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
  GNUNET_JSON_parse_free (spec);
  /* invalidate denom_key, just to be sure */
  memset (denom_key,
          0,
          sizeof (*denom_key));
  return GNUNET_SYSERR;
}


/**
 * Parse a exchange's auditor information encoded in JSON.
 *
 * @param[out] auditor where to return the result
 * @param check_sigs should we check signatures
 * @param auditor_obj json to parse
 * @param key_data information about denomination keys
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static enum GNUNET_GenericReturnValue
parse_json_auditor (struct TALER_EXCHANGE_AuditorInformation *auditor,
                    bool check_sigs,
                    const json_t *auditor_obj,
                    const struct TALER_EXCHANGE_Keys *key_data)
{
  const json_t *keys;
  json_t *key;
  size_t off;
  size_t pos;
  const char *auditor_url;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("auditor_pub",
                                 &auditor->auditor_pub),
    TALER_JSON_spec_web_url ("auditor_url",
                             &auditor_url),
    GNUNET_JSON_spec_array_const ("denomination_keys",
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
  auditor->denom_keys
    = GNUNET_new_array (json_array_size (keys),
                        struct TALER_EXCHANGE_AuditorDenominationInfo);
  pos = 0;
  json_array_foreach (keys, off, key) {
    struct TALER_AuditorSignatureP auditor_sig;
    struct TALER_DenominationHashP denom_h;
    const struct TALER_EXCHANGE_DenomPublicKey *dk = NULL;
    unsigned int dk_off = UINT_MAX;
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
        return GNUNET_SYSERR;
      }
    }
    auditor->denom_keys[pos].denom_key_offset = dk_off;
    auditor->denom_keys[pos].auditor_sig = auditor_sig;
    pos++;
  }
  if (pos > UINT_MAX)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  auditor->num_denom_keys = (unsigned int) pos;
  return GNUNET_OK;
}


/**
 * Parse a exchange's global fee information encoded in JSON.
 *
 * @param[out] gf where to return the result
 * @param check_sigs should we check signatures
 * @param fee_obj json to parse
 * @param key_data already parsed information about the exchange
 * @return #GNUNET_OK if all is fine, #GNUNET_SYSERR if the signature is
 *        invalid or the json malformed.
 */
static enum GNUNET_GenericReturnValue
parse_global_fee (struct TALER_EXCHANGE_GlobalFee *gf,
                  bool check_sigs,
                  const json_t *fee_obj,
                  const struct TALER_EXCHANGE_Keys *key_data)
{
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("start_date",
                                &gf->start_date),
    GNUNET_JSON_spec_timestamp ("end_date",
                                &gf->end_date),
    GNUNET_JSON_spec_relative_time ("purse_timeout",
                                    &gf->purse_timeout),
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
 * Compare two denomination keys.  Ignores revocation data.
 *
 * @param denom1 first denomination key
 * @param denom2 second denomination key
 * @return 0 if the two keys are equal (not necessarily
 *  the same object), non-zero otherwise.
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
 * Decode the JSON array in @a hard_limits from the /keys response
 * and store the data in `hard_limits` array the @a key_data.
 *
 * @param[in] hard_limits JSON array to parse
 * @param[out] key_data where to store the results we decoded
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 * (malformed JSON)
 */
static enum GNUNET_GenericReturnValue
parse_hard_limits (const json_t *hard_limits,
                   struct TALER_EXCHANGE_Keys *key_data)
{
  json_t *obj;
  size_t off;

  key_data->hard_limits_length
    = (unsigned int) json_array_size (hard_limits);
  if ( ((size_t) key_data->hard_limits_length)
       != json_array_size (hard_limits))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  key_data->hard_limits
    = GNUNET_new_array (key_data->hard_limits_length,
                        struct TALER_EXCHANGE_AccountLimit);

  json_array_foreach (hard_limits, off, obj)
  {
    struct TALER_EXCHANGE_AccountLimit *al
      = &key_data->hard_limits[off];
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_kycte ("operation_type",
                             &al->operation_type),
      TALER_JSON_spec_amount_any ("threshold",
                                  &al->threshold),
      GNUNET_JSON_spec_relative_time ("timeframe",
                                      &al->timeframe),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (obj,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Decode the JSON array in @a zero_limits from the /keys response
 * and store the data in `zero_limits` array the @a key_data.
 *
 * @param[in] zero_limits JSON array to parse
 * @param[out] key_data where to store the results we decoded
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 * (malformed JSON)
 */
static enum GNUNET_GenericReturnValue
parse_zero_limits (const json_t *zero_limits,
                   struct TALER_EXCHANGE_Keys *key_data)
{
  json_t *obj;
  size_t off;

  key_data->zero_limits_length
    = (unsigned int) json_array_size (zero_limits);
  if ( ((size_t) key_data->zero_limits_length)
       != json_array_size (zero_limits))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  key_data->zero_limits
    = GNUNET_new_array (key_data->zero_limits_length,
                        struct TALER_EXCHANGE_ZeroLimitedOperation);

  json_array_foreach (zero_limits, off, obj)
  {
    struct TALER_EXCHANGE_ZeroLimitedOperation *zol
      = &key_data->zero_limits[off];
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_kycte ("operation_type",
                             &zol->operation_type),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK !=
        GNUNET_JSON_parse (obj,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
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
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_ExchangePublicKeyP exchange_pub;
  const json_t *wblwk = NULL;
  const json_t *global_fees;
  const json_t *sign_keys_array;
  const json_t *denominations_by_group;
  const json_t *auditors_array;
  const json_t *recoup_array = NULL;
  const json_t *manifests = NULL;
  bool no_extensions = false;
  bool no_signature = false;
  const json_t *accounts;
  const json_t *fees;
  const json_t *wads;
  struct SignatureContext sig_ctx = { 0 };

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
    struct TALER_JSON_ProtocolVersion pv;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_version ("version",
                               &pv),
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
    *vc = TALER_EXCHANGE_VC_MATCH;
    if (EXCHANGE_PROTOCOL_CURRENT < pv.current)
    {
      *vc |= TALER_EXCHANGE_VC_NEWER;
      if (EXCHANGE_PROTOCOL_CURRENT < pv.current - pv.age)
        *vc |= TALER_EXCHANGE_VC_INCOMPATIBLE;
    }
    if (EXCHANGE_PROTOCOL_CURRENT > pv.current)
    {
      *vc |= TALER_EXCHANGE_VC_OLDER;
      if (EXCHANGE_PROTOCOL_CURRENT - EXCHANGE_PROTOCOL_AGE > pv.current)
        *vc |= TALER_EXCHANGE_VC_INCOMPATIBLE;
    }
  }

  {
    const char *ver;
    const char *currency;
    const char *asset_type;
    struct GNUNET_JSON_Specification mspec[] = {
      GNUNET_JSON_spec_fixed_auto (
        "exchange_sig",
        &exchange_sig),
      GNUNET_JSON_spec_fixed_auto (
        "exchange_pub",
        &exchange_pub),
      GNUNET_JSON_spec_fixed_auto (
        "master_public_key",
        &key_data->master_pub),
      GNUNET_JSON_spec_array_const ("accounts",
                                    &accounts),
      GNUNET_JSON_spec_object_const ("wire_fees",
                                     &fees),
      GNUNET_JSON_spec_array_const ("wads",
                                    &wads),
      GNUNET_JSON_spec_timestamp (
        "list_issue_date",
        &key_data->list_issue_date),
      GNUNET_JSON_spec_relative_time (
        "reserve_closing_delay",
        &key_data->reserve_closing_delay),
      GNUNET_JSON_spec_string (
        "currency",
        &currency),
      GNUNET_JSON_spec_string (
        "asset_type",
        &asset_type),
      GNUNET_JSON_spec_array_const (
        "global_fees",
        &global_fees),
      GNUNET_JSON_spec_array_const (
        "signkeys",
        &sign_keys_array),
      GNUNET_JSON_spec_array_const (
        "denominations",
        &denominations_by_group),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_array_const (
          "recoup",
          &recoup_array),
        NULL),
      GNUNET_JSON_spec_array_const (
        "auditors",
        &auditors_array),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_bool (
          "rewards_allowed",
          &key_data->rewards_allowed),
        NULL),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_object_const ("extensions",
                                       &manifests),
        &no_extensions),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_fixed_auto (
          "extensions_sig",
          &key_data->extensions_sig),
        &no_signature),
      GNUNET_JSON_spec_string ("version",
                               &ver),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_array_const (
          "wallet_balance_limit_without_kyc",
          &wblwk),
        NULL),
      GNUNET_JSON_spec_end ()
    };
    const char *emsg;
    unsigned int eline;

    if (GNUNET_OK !=
        GNUNET_JSON_parse (resp_obj,
                           (check_sig) ? mspec : &mspec[2],
                           &emsg,
                           &eline))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Parsing /keys failed for `%s' (%u)\n",
                  emsg,
                  eline);
      EXITIF (1);
    }
    {
      const json_t *hard_limits = NULL;
      const json_t *zero_limits = NULL;
      struct GNUNET_JSON_Specification sspec[] = {
        TALER_JSON_spec_currency_specification (
          "currency_specification",
          currency,
          &key_data->cspec),
        TALER_JSON_spec_amount (
          "stefan_abs",
          currency,
          &key_data->stefan_abs),
        TALER_JSON_spec_amount (
          "stefan_log",
          currency,
          &key_data->stefan_log),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_array_const (
            "hard_limits",
            &hard_limits),
          NULL),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_array_const (
            "zero_limits",
            &zero_limits),
          NULL),
        GNUNET_JSON_spec_double (
          "stefan_lin",
          &key_data->stefan_lin),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (resp_obj,
                             sspec,
                             &emsg,
                             &eline))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Parsing /keys failed for `%s' (%u)\n",
                    emsg,
                    eline);
        EXITIF (1);
      }
      if ( (NULL != hard_limits) &&
           (GNUNET_OK !=
            parse_hard_limits (hard_limits,
                               key_data)) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Parsing hard limits of /keys failed\n");
        EXITIF (1);
      }
      if ( (NULL != zero_limits) &&
           (GNUNET_OK !=
            parse_zero_limits (zero_limits,
                               key_data)) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Parsing hard limits of /keys failed\n");
        EXITIF (1);
      }
    }

    key_data->currency = GNUNET_strdup (currency);
    key_data->version = GNUNET_strdup (ver);
    key_data->asset_type = GNUNET_strdup (asset_type);
    if (! no_extensions)
      key_data->extensions = json_incref ((json_t *) manifests);
  }

  /* parse the global fees */
  EXITIF (json_array_size (global_fees) > UINT_MAX);
  key_data->num_global_fees
    = (unsigned int) json_array_size (global_fees);
  if (0 != key_data->num_global_fees)
  {
    json_t *global_fee;
    size_t index;

    key_data->global_fees
      = GNUNET_new_array (key_data->num_global_fees,
                          struct TALER_EXCHANGE_GlobalFee);
    json_array_foreach (global_fees, index, global_fee)
    {
      EXITIF (GNUNET_SYSERR ==
              parse_global_fee (&key_data->global_fees[index],
                                check_sig,
                                global_fee,
                                key_data));
    }
  }

  /* parse the signing keys */
  EXITIF (json_array_size (sign_keys_array) > UINT_MAX);
  key_data->num_sign_keys
    = (unsigned int) json_array_size (sign_keys_array);
  if (0 != key_data->num_sign_keys)
  {
    json_t *sign_key_obj;
    size_t index;

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

  /* Parse balance limits */
  if (NULL != wblwk)
  {
    EXITIF (json_array_size (wblwk) > UINT_MAX);
    key_data->wblwk_length
      = (unsigned int) json_array_size (wblwk);
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
                                key_data->currency,
                                a),
        GNUNET_JSON_spec_end ()
      };

      EXITIF (GNUNET_OK !=
              GNUNET_JSON_parse (aj,
                                 spec,
                                 NULL, NULL));
    }
  }

  /* Parse wire accounts */
  key_data->fees = parse_fees (&key_data->master_pub,
                               key_data->currency,
                               fees,
                               &key_data->fees_len);
  EXITIF (NULL == key_data->fees);
  /* parse accounts */
  EXITIF (json_array_size (accounts) > UINT_MAX);
  GNUNET_array_grow (key_data->accounts,
                     key_data->accounts_len,
                     json_array_size (accounts));
  EXITIF (GNUNET_OK !=
          TALER_EXCHANGE_parse_accounts (&key_data->master_pub,
                                         accounts,
                                         key_data->accounts_len,
                                         key_data->accounts));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Parsed %u wire accounts from JSON\n",
              key_data->accounts_len);


  /* Parse the supported extension(s): age-restriction. */
  /* TODO: maybe lift all this into a FP in TALER_Extension ? */
  if (! no_extensions)
  {
    if (no_signature)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "found extensions without signature\n");
    }
    else
    {
      /* We have an extensions object. Verify its signature. */
      EXITIF (GNUNET_OK !=
              TALER_extensions_verify_manifests_signature (
                manifests,
                &key_data->extensions_sig,
                &key_data->master_pub));

      /* Parse and set the the configuration of the extensions accordingly */
      EXITIF (GNUNET_OK !=
              TALER_extensions_load_manifests (manifests));
    }

    /* Assuming we might have now a new value for age_mask, set it in key_data */
    key_data->age_mask = TALER_extensions_get_age_restriction_mask ();
  }

  /*
   * Parse the denomination keys, merging with the
   * possibly EXISTING array as required (/keys cherry picking).
   *
   * The denominations are grouped by common values of
   *    {cipher, value, fee, age_mask}.
   */
  {
    json_t *group_obj;
    unsigned int group_idx;

    json_array_foreach (denominations_by_group,
                        group_idx,
                        group_obj)
    {
      /* First, parse { cipher, fees, value, age_mask, hash } of the current
         group. */
      struct TALER_DenominationGroup group = {0};
      const json_t *denom_keys_array;
      struct GNUNET_JSON_Specification group_spec[] = {
        TALER_JSON_spec_denomination_group (NULL,
                                            key_data->currency,
                                            &group),
        GNUNET_JSON_spec_array_const ("denoms",
                                      &denom_keys_array),
        GNUNET_JSON_spec_end ()
      };
      json_t *denom_key_obj;
      unsigned int index;

      EXITIF (GNUNET_SYSERR ==
              GNUNET_JSON_parse (group_obj,
                                 group_spec,
                                 NULL,
                                 NULL));

      /* Now, parse the individual denominations */
      json_array_foreach (denom_keys_array,
                          index,
                          denom_key_obj)
      {
        /* Set the common fields from the group for this particular
           denomination.  Required to make the validity check inside
           parse_json_denomkey_partially pass */
        struct TALER_EXCHANGE_DenomPublicKey dk = {
          .value = group.value,
          .fees = group.fees,
          .key.age_mask = group.age_mask
        };
        bool found = false;

        EXITIF (GNUNET_SYSERR ==
                parse_json_denomkey_partially (&dk,
                                               group.cipher,
                                               check_sig,
                                               denom_key_obj,
                                               &key_data->master_pub,
                                               group_idx,
                                               index,
                                               check_sig
                                               ? &sig_ctx
                                               : NULL));
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
        GNUNET_assert (key_data->denom_keys_size >
                       key_data->num_denom_keys);
        GNUNET_assert (key_data->num_denom_keys < UINT_MAX);
        key_data->denom_keys[key_data->num_denom_keys++] = dk;

        /* Update "last_denom_issue_date" */
        TALER_LOG_DEBUG ("Adding denomination key that is valid_until %s\n",
                         GNUNET_TIME_timestamp2s (dk.valid_from));
        key_data->last_denom_issue_date
          = GNUNET_TIME_timestamp_max (key_data->last_denom_issue_date,
                                       dk.valid_from);
      };   /* end of json_array_foreach over denominations */
    } /* end of json_array_foreach over groups of denominations */
  } /* end of scope for group_ojb/group_idx */

  /* parse the auditor information */
  {
    json_t *auditor_info;
    unsigned int index;

    /* Merge with the existing auditor information we have (/keys cherry picking) */
    json_array_foreach (auditors_array, index, auditor_info)
    {
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
      GNUNET_assert (key_data->auditors_size >
                     key_data->num_auditors);
      GNUNET_assert (NULL != ai.auditor_url);
      GNUNET_assert (key_data->num_auditors < UINT_MAX);
      key_data->auditors[key_data->num_auditors++] = ai;
    };
  }

  /* parse the revocation/recoup information */
  if (NULL != recoup_array)
  {
    json_t *recoup_info;
    unsigned int index;

    json_array_foreach (recoup_array, index, recoup_info)
    {
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
          key_data->denom_keys[j].revoked = true;
          break;
        }
      }
    }
  }

  if (check_sig)
  {
    struct GNUNET_HashContext *hash_context;
    struct GNUNET_HashCode hc;

    hash_context = GNUNET_CRYPTO_hash_context_start ();
    qsort (sig_ctx.elements,
           sig_ctx.elements_pos,
           sizeof (struct SignatureElement),
           &signature_context_sort_cb);
    for (unsigned int i = 0; i<sig_ctx.elements_pos; i++)
    {
      struct SignatureElement *element = &sig_ctx.elements[i];

      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Adding %u,%u,%s\n",
                  element->group_offset,
                  element->offset,
                  TALER_B2S (&element->master_sig));
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &element->master_sig,
                                       sizeof (element->master_sig));
    }
    GNUNET_array_grow (sig_ctx.elements,
                       sig_ctx.elements_size,
                       0);
    GNUNET_CRYPTO_hash_context_finish (hash_context,
                                       &hc);
    EXITIF (GNUNET_OK !=
            TALER_EXCHANGE_test_signing_key (key_data,
                                             &exchange_pub));
    EXITIF (GNUNET_OK !=
            TALER_exchange_online_key_set_verify (
              key_data->list_issue_date,
              &hc,
              &exchange_pub,
              &exchange_sig));
  }
  return GNUNET_OK;

EXITIF_exit:
  *vc = TALER_EXCHANGE_VC_PROTOCOL_ERROR;
  return GNUNET_SYSERR;
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
  struct TALER_EXCHANGE_GetKeysHandle *gkh = cls;
  const json_t *j = resp_obj;
  struct TALER_EXCHANGE_Keys *kd = NULL;
  struct TALER_EXCHANGE_KeysResponse kresp = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code,
    .details.ok.compat = TALER_EXCHANGE_VC_PROTOCOL_ERROR,
  };

  gkh->job = NULL;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received keys from URL `%s' with status %ld and expiration %s.\n",
              gkh->url,
              response_code,
              GNUNET_TIME_timestamp2s (gkh->expire));
  if (GNUNET_TIME_absolute_is_past (gkh->expire.abs_time))
  {
    if (MHD_HTTP_OK == response_code)
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Exchange failed to give expiration time, assuming in %s\n",
                  GNUNET_TIME_relative2s (DEFAULT_EXPIRATION,
                                          true));
    gkh->expire
      = GNUNET_TIME_absolute_to_timestamp (
          GNUNET_TIME_relative_to_absolute (DEFAULT_EXPIRATION));
  }
  switch (response_code)
  {
  case 0:
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to receive /keys response from exchange %s\n",
                gkh->exchange_url);
    break;
  case MHD_HTTP_OK:
    if (NULL == j)
    {
      GNUNET_break (0);
      response_code = 0;
      break;
    }
    kd = GNUNET_new (struct TALER_EXCHANGE_Keys);
    kd->exchange_url = GNUNET_strdup (gkh->exchange_url);
    if (NULL != gkh->prev_keys)
    {
      const struct TALER_EXCHANGE_Keys *kd_old = gkh->prev_keys;

      /* We keep the denomination keys and auditor signatures from the
         previous iteration (/keys cherry picking) */
      kd->num_denom_keys
        = kd_old->num_denom_keys;
      kd->last_denom_issue_date
        = kd_old->last_denom_issue_date;
      GNUNET_array_grow (kd->denom_keys,
                         kd->denom_keys_size,
                         kd->num_denom_keys);
      /* First make a shallow copy, we then need another pass for the RSA key... */
      GNUNET_memcpy (kd->denom_keys,
                     kd_old->denom_keys,
                     kd_old->num_denom_keys
                     * sizeof (struct TALER_EXCHANGE_DenomPublicKey));
      for (unsigned int i = 0; i<kd_old->num_denom_keys; i++)
        TALER_denom_pub_copy (&kd->denom_keys[i].key,
                              &kd_old->denom_keys[i].key);
      kd->num_auditors = kd_old->num_auditors;
      kd->auditors = GNUNET_new_array (kd->num_auditors,
                                       struct TALER_EXCHANGE_AuditorInformation)
      ;
      /* Now the necessary deep copy... */
      for (unsigned int i = 0; i<kd_old->num_auditors; i++)
      {
        const struct TALER_EXCHANGE_AuditorInformation *aold =
          &kd_old->auditors[i];
        struct TALER_EXCHANGE_AuditorInformation *anew = &kd->auditors[i];

        anew->auditor_pub = aold->auditor_pub;
        anew->auditor_url = GNUNET_strdup (aold->auditor_url);
        GNUNET_array_grow (anew->denom_keys,
                           anew->num_denom_keys,
                           aold->num_denom_keys);
        GNUNET_memcpy (
          anew->denom_keys,
          aold->denom_keys,
          aold->num_denom_keys
          * sizeof (struct TALER_EXCHANGE_AuditorDenominationInfo));
      }
    }
    /* Now decode fresh /keys response */
    if (GNUNET_OK !=
        decode_keys_json (j,
                          true,
                          kd,
                          &kresp.details.ok.compat))
    {
      TALER_LOG_ERROR ("Could not decode /keys response\n");
      kd->rc = 1;
      TALER_EXCHANGE_keys_decref (kd);
      kd = NULL;
      kresp.hr.http_status = 0;
      kresp.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
      break;
    }
    kd->rc = 1;
    kd->key_data_expiration = gkh->expire;
    if (GNUNET_TIME_relative_cmp (
          GNUNET_TIME_absolute_get_remaining (gkh->expire.abs_time),
          <,
          MINIMUM_EXPIRATION))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Exchange returned keys with expiration time below %s. Compensating.\n",
                  GNUNET_TIME_relative2s (MINIMUM_EXPIRATION,
                                          true));
      kd->key_data_expiration
        = GNUNET_TIME_relative_to_timestamp (MINIMUM_EXPIRATION);
    }

    kresp.details.ok.keys = kd;
    break;
  case MHD_HTTP_BAD_REQUEST:
  case MHD_HTTP_UNAUTHORIZED:
  case MHD_HTTP_FORBIDDEN:
  case MHD_HTTP_NOT_FOUND:
    if (NULL == j)
    {
      kresp.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      kresp.hr.hint = TALER_ErrorCode_get_hint (kresp.hr.ec);
    }
    else
    {
      kresp.hr.ec = TALER_JSON_get_error_code (j);
      kresp.hr.hint = TALER_JSON_get_error_hint (j);
    }
    break;
  default:
    if (NULL == j)
    {
      kresp.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
      kresp.hr.hint = TALER_ErrorCode_get_hint (kresp.hr.ec);
    }
    else
    {
      kresp.hr.ec = TALER_JSON_get_error_code (j);
      kresp.hr.hint = TALER_JSON_get_error_hint (j);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d\n",
                (unsigned int) response_code,
                (int) kresp.hr.ec);
    break;
  }
  gkh->cert_cb (gkh->cert_cb_cls,
                &kresp,
                kd);
  TALER_EXCHANGE_get_keys_cancel (gkh);
}


/**
 * Define a max length for the HTTP "Expire:" header
 */
#define MAX_DATE_LINE_LEN 32


/**
 * Parse HTTP timestamp.
 *
 * @param dateline header to parse header
 * @param[out] at where to write the result
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
 * @param userdata the `struct TALER_EXCHANGE_GetKeysHandle`
 * @return `size * nitems` on success (everything else aborts)
 */
static size_t
header_cb (char *buffer,
           size_t size,
           size_t nitems,
           void *userdata)
{
  struct TALER_EXCHANGE_GetKeysHandle *kr = userdata;
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
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Found %s header `%s'\n",
              MHD_HTTP_HEADER_EXPIRES,
              val);
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


struct TALER_EXCHANGE_GetKeysHandle *
TALER_EXCHANGE_get_keys (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *last_keys,
  TALER_EXCHANGE_GetKeysCallback cert_cb,
  void *cert_cb_cls)
{
  struct TALER_EXCHANGE_GetKeysHandle *gkh;
  CURL *eh;
  char last_date[80] = { 0 };

  TALER_LOG_DEBUG ("Connecting to the exchange (%s)\n",
                   url);
  gkh = GNUNET_new (struct TALER_EXCHANGE_GetKeysHandle);
  gkh->exchange_url = GNUNET_strdup (url);
  gkh->cert_cb = cert_cb;
  gkh->cert_cb_cls = cert_cb_cls;
  if (NULL != last_keys)
  {
    gkh->prev_keys = TALER_EXCHANGE_keys_incref (last_keys);
    TALER_LOG_DEBUG ("Last DK issue date (before GETting /keys): %s\n",
                     GNUNET_TIME_timestamp2s (
                       last_keys->last_denom_issue_date));
    GNUNET_snprintf (last_date,
                     sizeof (last_date),
                     "%llu",
                     (unsigned long long)
                     last_keys->last_denom_issue_date.abs_time.abs_value_us
                     / 1000000LLU);
  }
  gkh->url = TALER_url_join (url,
                             "keys",
                             (NULL != last_keys)
                             ? "last_issue_date"
                             : NULL,
                             (NULL != last_keys)
                             ? last_date
                             : NULL,
                             NULL);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Requesting keys with URL `%s'.\n",
              gkh->url);
  eh = TALER_EXCHANGE_curl_easy_get_ (gkh->url);
  if (NULL == eh)
  {
    GNUNET_break (0);
    GNUNET_free (gkh->exchange_url);
    GNUNET_free (gkh->url);
    GNUNET_free (gkh);
    return NULL;
  }
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_VERBOSE,
                                  0));
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_TIMEOUT,
                                  120 /* seconds */));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HEADERFUNCTION,
                                   &header_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HEADERDATA,
                                   gkh));
  gkh->job = GNUNET_CURL_job_add_with_ct_json (ctx,
                                               eh,
                                               &keys_completed_cb,
                                               gkh);
  return gkh;
}


void
TALER_EXCHANGE_get_keys_cancel (
  struct TALER_EXCHANGE_GetKeysHandle *gkh)
{
  if (NULL != gkh->job)
  {
    GNUNET_CURL_job_cancel (gkh->job);
    gkh->job = NULL;
  }
  TALER_EXCHANGE_keys_decref (gkh->prev_keys);
  GNUNET_free (gkh->exchange_url);
  GNUNET_free (gkh->url);
  GNUNET_free (gkh);
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_test_signing_key (
  const struct TALER_EXCHANGE_Keys *keys,
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
  TALER_denom_pub_copy (&copy->key,
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


struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_keys_incref (struct TALER_EXCHANGE_Keys *keys)
{
  GNUNET_assert (keys->rc < UINT_MAX);
  keys->rc++;
  return keys;
}


void
TALER_EXCHANGE_keys_decref (struct TALER_EXCHANGE_Keys *keys)
{
  if (NULL == keys)
    return;
  GNUNET_assert (0 < keys->rc);
  keys->rc--;
  if (0 != keys->rc)
    return;
  GNUNET_array_grow (keys->sign_keys,
                     keys->num_sign_keys,
                     0);
  for (unsigned int i = 0; i<keys->num_denom_keys; i++)
    TALER_denom_pub_free (&keys->denom_keys[i].key);

  GNUNET_array_grow (keys->denom_keys,
                     keys->denom_keys_size,
                     0);
  for (unsigned int i = 0; i<keys->num_auditors; i++)
  {
    GNUNET_array_grow (keys->auditors[i].denom_keys,
                       keys->auditors[i].num_denom_keys,
                       0);
    GNUNET_free (keys->auditors[i].auditor_url);
  }
  GNUNET_array_grow (keys->auditors,
                     keys->auditors_size,
                     0);
  TALER_EXCHANGE_free_accounts (keys->accounts_len,
                                keys->accounts);
  GNUNET_array_grow (keys->accounts,
                     keys->accounts_len,
                     0);
  free_fees (keys->fees,
             keys->fees_len);
  GNUNET_array_grow (keys->hard_limits,
                     keys->hard_limits_length,
                     0);
  GNUNET_array_grow (keys->zero_limits,
                     keys->zero_limits_length,
                     0);
  json_decref (keys->extensions);
  GNUNET_free (keys->cspec.name);
  json_decref (keys->cspec.map_alt_unit_names);
  GNUNET_free (keys->wallet_balance_limit_without_kyc);
  GNUNET_free (keys->version);
  GNUNET_free (keys->currency);
  GNUNET_free (keys->asset_type);
  GNUNET_free (keys->global_fees);
  GNUNET_free (keys->exchange_url);
  GNUNET_free (keys);
}


struct TALER_EXCHANGE_Keys *
TALER_EXCHANGE_keys_from_json (const json_t *j)
{
  const json_t *jkeys;
  const char *url;
  uint32_t version;
  struct GNUNET_TIME_Timestamp expire
    = GNUNET_TIME_UNIT_ZERO_TS;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint32 ("version",
                             &version),
    GNUNET_JSON_spec_object_const ("keys",
                                   &jkeys),
    TALER_JSON_spec_web_url ("exchange_url",
                             &url),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("expire",
                                  &expire),
      NULL),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_EXCHANGE_Keys *keys;
  enum TALER_EXCHANGE_VersionCompatibility compat;

  if (NULL == j)
    return NULL;
  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  if (0 != version)
  {
    return NULL; /* unsupported version */
  }
  keys = GNUNET_new (struct TALER_EXCHANGE_Keys);
  if (GNUNET_OK !=
      decode_keys_json (jkeys,
                        false,
                        keys,
                        &compat))
  {
    GNUNET_break (0);
    return NULL;
  }
  keys->rc = 1;
  keys->key_data_expiration = expire;
  keys->exchange_url = GNUNET_strdup (url);
  return keys;
}


/**
 * Data we track per denomination group.
 */
struct GroupData
{
  /**
   * The json blob with the group meta-data and list of denominations
   */
  json_t *json;

  /**
   * Meta data for this group.
   */
  struct TALER_DenominationGroup meta;
};


/**
 * Add denomination group represented by @a value
 * to list of denominations in @a cls. Also frees
 * the @a value.
 *
 * @param[in,out] cls a `json_t *` with an array to build
 * @param key unused
 * @param value a `struct GroupData *`
 * @return #GNUNET_OK (continue to iterate)
 */
static enum GNUNET_GenericReturnValue
add_grp (void *cls,
         const struct GNUNET_HashCode *key,
         void *value)
{
  json_t *denominations_by_group = cls;
  struct GroupData *gd = value;
  const char *cipher;
  json_t *ge;
  bool age_restricted = gd->meta.age_mask.bits != 0;

  (void) key;
  switch (gd->meta.cipher)
  {
  case GNUNET_CRYPTO_BSA_RSA:
    cipher = age_restricted ? "RSA+age_restricted" : "RSA";
    break;
  case GNUNET_CRYPTO_BSA_CS:
    cipher = age_restricted ? "CS+age_restricted" : "CS";
    break;
  default:
    GNUNET_assert (false);
  }

  ge = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("cipher",
                             cipher),
    GNUNET_JSON_pack_array_steal ("denoms",
                                  gd->json),
    TALER_JSON_PACK_DENOM_FEES ("fee",
                                &gd->meta.fees),
    GNUNET_JSON_pack_allow_null (
      age_restricted
          ? GNUNET_JSON_pack_uint64 ("age_mask",
                                     gd->meta.age_mask.bits)
          : GNUNET_JSON_pack_string ("dummy",
                                     NULL)),
    TALER_JSON_pack_amount ("value",
                            &gd->meta.value));
  GNUNET_assert (0 ==
                 json_array_append_new (denominations_by_group,
                                        ge));
  GNUNET_free (gd);
  return GNUNET_OK;
}


/**
 * Convert array of account restrictions @a ars to JSON.
 *
 * @param ar_len length of @a ars
 * @param ars account restrictions to convert
 * @return JSON representation
 */
static json_t *
ar_to_json (unsigned int ar_len,
            const struct TALER_EXCHANGE_AccountRestriction ars[static ar_len])
{
  json_t *rval;

  rval = json_array ();
  GNUNET_assert (NULL != rval);
  for (unsigned int i = 0; i<ar_len; i++)
  {
    const struct TALER_EXCHANGE_AccountRestriction *ar = &ars[i];

    switch (ar->type)
    {
    case TALER_EXCHANGE_AR_INVALID:
      GNUNET_break (0);
      json_decref (rval);
      return NULL;
    case TALER_EXCHANGE_AR_DENY:
      GNUNET_assert (
        0 ==
        json_array_append_new (
          rval,
          GNUNET_JSON_PACK (
            GNUNET_JSON_pack_string ("type",
                                     "deny"))));
      break;
    case TALER_EXCHANGE_AR_REGEX:
      GNUNET_assert (
        0 ==
        json_array_append_new (
          rval,
          GNUNET_JSON_PACK (
            GNUNET_JSON_pack_string (
              "type",
              "regex"),
            GNUNET_JSON_pack_string (
              "payto_regex",
              ar->details.regex.posix_egrep),
            GNUNET_JSON_pack_string (
              "human_hint",
              ar->details.regex.human_hint),
            GNUNET_JSON_pack_object_incref (
              "human_hint_i18n",
              (json_t *) ar->details.regex.human_hint_i18n)
            )));
      break;
    }
  }
  return rval;
}


json_t *
TALER_EXCHANGE_keys_to_json (const struct TALER_EXCHANGE_Keys *kd)
{
  struct GNUNET_TIME_Timestamp now;
  json_t *keys;
  json_t *signkeys;
  json_t *denominations_by_group;
  json_t *auditors;
  json_t *recoup;
  json_t *wire_fees;
  json_t *accounts;
  json_t *global_fees;
  json_t *wblwk = NULL;
  json_t *hard_limits;
  json_t *zero_limits;

  now = GNUNET_TIME_timestamp_get ();
  signkeys = json_array ();
  GNUNET_assert (NULL != signkeys);
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
    GNUNET_assert (NULL != signkey);
    GNUNET_assert (0 ==
                   json_array_append_new (signkeys,
                                          signkey));
  }

  denominations_by_group = json_array ();
  GNUNET_assert (NULL != denominations_by_group);
  {
    struct GNUNET_CONTAINER_MultiHashMap *dbg;

    dbg = GNUNET_CONTAINER_multihashmap_create (128,
                                                false);
    for (unsigned int i = 0; i<kd->num_denom_keys; i++)
    {
      const struct TALER_EXCHANGE_DenomPublicKey *dk = &kd->denom_keys[i];
      struct TALER_DenominationGroup meta = {
        .cipher = dk->key.bsign_pub_key->cipher,
        .value = dk->value,
        .fees = dk->fees,
        .age_mask = dk->key.age_mask
      };
      struct GNUNET_HashCode key;
      struct GroupData *gd;
      json_t *denom;
      struct GNUNET_JSON_PackSpec key_spec;

      if (GNUNET_TIME_timestamp_cmp (now,
                                     >,
                                     dk->expire_deposit))
        continue; /* skip keys that have expired */
      TALER_denomination_group_get_key (&meta,
                                        &key);
      gd = GNUNET_CONTAINER_multihashmap_get (dbg,
                                              &key);
      if (NULL == gd)
      {
        gd = GNUNET_new (struct GroupData);
        gd->meta = meta;
        gd->json = json_array ();
        GNUNET_assert (NULL != gd->json);
        GNUNET_assert (
          GNUNET_OK ==
          GNUNET_CONTAINER_multihashmap_put (dbg,
                                             &key,
                                             gd,
                                             GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));

      }
      switch (meta.cipher)
      {
      case GNUNET_CRYPTO_BSA_RSA:
        key_spec =
          GNUNET_JSON_pack_rsa_public_key (
            "rsa_pub",
            dk->key.bsign_pub_key->details.rsa_public_key);
        break;
      case GNUNET_CRYPTO_BSA_CS:
        key_spec =
          GNUNET_JSON_pack_data_varsize (
            "cs_pub",
            &dk->key.bsign_pub_key->details.cs_public_key,
            sizeof (dk->key.bsign_pub_key->details.cs_public_key));
        break;
      default:
        GNUNET_assert (false);
      }
      denom = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_timestamp ("stamp_expire_deposit",
                                    dk->expire_deposit),
        GNUNET_JSON_pack_timestamp ("stamp_expire_withdraw",
                                    dk->withdraw_valid_until),
        GNUNET_JSON_pack_timestamp ("stamp_start",
                                    dk->valid_from),
        GNUNET_JSON_pack_timestamp ("stamp_expire_legal",
                                    dk->expire_legal),
        GNUNET_JSON_pack_data_auto ("master_sig",
                                    &dk->master_sig),
        key_spec
        );
      GNUNET_assert (0 ==
                     json_array_append_new (gd->json,
                                            denom));
    }
    GNUNET_CONTAINER_multihashmap_iterate (dbg,
                                           &add_grp,
                                           denominations_by_group);
    GNUNET_CONTAINER_multihashmap_destroy (dbg);
  }

  auditors = json_array ();
  GNUNET_assert (NULL != auditors);
  for (unsigned int i = 0; i<kd->num_auditors; i++)
  {
    const struct TALER_EXCHANGE_AuditorInformation *ai = &kd->auditors[i];
    json_t *a;
    json_t *adenoms;

    adenoms = json_array ();
    GNUNET_assert (NULL != adenoms);
    for (unsigned int j = 0; j<ai->num_denom_keys; j++)
    {
      const struct TALER_EXCHANGE_AuditorDenominationInfo *adi =
        &ai->denom_keys[j];
      const struct TALER_EXCHANGE_DenomPublicKey *dk =
        &kd->denom_keys[adi->denom_key_offset];
      json_t *k;

      GNUNET_assert (adi->denom_key_offset < kd->num_denom_keys);
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

  global_fees = json_array ();
  GNUNET_assert (NULL != global_fees);
  for (unsigned int i = 0; i<kd->num_global_fees; i++)
  {
    const struct TALER_EXCHANGE_GlobalFee *gf
      = &kd->global_fees[i];

    if (GNUNET_TIME_absolute_is_past (gf->end_date.abs_time))
      continue;
    GNUNET_assert (
      0 ==
      json_array_append_new (
        global_fees,
        GNUNET_JSON_PACK (
          GNUNET_JSON_pack_timestamp ("start_date",
                                      gf->start_date),
          GNUNET_JSON_pack_timestamp ("end_date",
                                      gf->end_date),
          TALER_JSON_PACK_GLOBAL_FEES (&gf->fees),
          GNUNET_JSON_pack_time_rel ("history_expiration",
                                     gf->history_expiration),
          GNUNET_JSON_pack_time_rel ("purse_timeout",
                                     gf->purse_timeout),
          GNUNET_JSON_pack_uint64 ("purse_account_limit",
                                   gf->purse_account_limit),
          GNUNET_JSON_pack_data_auto ("master_sig",
                                      &gf->master_sig))));
  }

  accounts = json_array ();
  GNUNET_assert (NULL != accounts);
  for (unsigned int i = 0; i<kd->accounts_len; i++)
  {
    const struct TALER_EXCHANGE_WireAccount *acc
      = &kd->accounts[i];
    json_t *credit_restrictions;
    json_t *debit_restrictions;

    credit_restrictions
      = ar_to_json (acc->credit_restrictions_length,
                    acc->credit_restrictions);
    GNUNET_assert (NULL != credit_restrictions);
    debit_restrictions
      = ar_to_json (acc->debit_restrictions_length,
                    acc->debit_restrictions);
    GNUNET_assert (NULL != debit_restrictions);
    GNUNET_assert (
      0 ==
      json_array_append_new (
        accounts,
        GNUNET_JSON_PACK (
          TALER_JSON_pack_full_payto ("payto_uri",
                                      acc->fpayto_uri),
          GNUNET_JSON_pack_allow_null (
            GNUNET_JSON_pack_string ("conversion_url",
                                     acc->conversion_url)),
          GNUNET_JSON_pack_int64 ("priority",
                                  acc->priority),
          GNUNET_JSON_pack_allow_null (
            GNUNET_JSON_pack_string ("bank_label",
                                     acc->bank_label)),
          GNUNET_JSON_pack_array_steal ("debit_restrictions",
                                        debit_restrictions),
          GNUNET_JSON_pack_array_steal ("credit_restrictions",
                                        credit_restrictions),
          GNUNET_JSON_pack_data_auto ("master_sig",
                                      &acc->master_sig))));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Serialized %u/%u wire accounts to JSON\n",
              (unsigned int) json_array_size (accounts),
              kd->accounts_len);

  wire_fees = json_object ();
  GNUNET_assert (NULL != wire_fees);
  for (unsigned int i = 0; i<kd->fees_len; i++)
  {
    const struct TALER_EXCHANGE_WireFeesByMethod *fbw
      = &kd->fees[i];
    json_t *wf;

    wf = json_array ();
    GNUNET_assert (NULL != wf);
    for (struct TALER_EXCHANGE_WireAggregateFees *p = fbw->fees_head;
         NULL != p;
         p = p->next)
    {
      GNUNET_assert (
        0 ==
        json_array_append_new (
          wf,
          GNUNET_JSON_PACK (
            TALER_JSON_pack_amount ("wire_fee",
                                    &p->fees.wire),
            TALER_JSON_pack_amount ("closing_fee",
                                    &p->fees.closing),
            GNUNET_JSON_pack_timestamp ("start_date",
                                        p->start_date),
            GNUNET_JSON_pack_timestamp ("end_date",
                                        p->end_date),
            GNUNET_JSON_pack_data_auto ("sig",
                                        &p->master_sig))));
    }
    GNUNET_assert (0 ==
                   json_object_set_new (wire_fees,
                                        fbw->method,
                                        wf));
  }

  recoup = json_array ();
  GNUNET_assert (NULL != recoup);
  for (unsigned int i = 0; i<kd->num_denom_keys; i++)
  {
    const struct TALER_EXCHANGE_DenomPublicKey *dk
      = &kd->denom_keys[i];
    if (! dk->revoked)
      continue;
    GNUNET_assert (0 ==
                   json_array_append_new (
                     recoup,
                     GNUNET_JSON_PACK (
                       GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                                   &dk->h_key))));
  }

  wblwk = json_array ();
  GNUNET_assert (NULL != wblwk);
  for (unsigned int i = 0; i<kd->wblwk_length; i++)
  {
    const struct TALER_Amount *a = &kd->wallet_balance_limit_without_kyc[i];

    GNUNET_assert (0 ==
                   json_array_append_new (
                     wblwk,
                     TALER_JSON_from_amount (a)));
  }

  hard_limits = json_array ();
  for (unsigned int i = 0; i < kd->hard_limits_length; i++)
  {
    const struct TALER_EXCHANGE_AccountLimit *al
      = &kd->hard_limits[i];
    json_t *j;

    j = GNUNET_JSON_PACK (
      TALER_JSON_pack_amount ("threshold",
                              &al->threshold),
      GNUNET_JSON_pack_time_rel ("timeframe",
                                 al->timeframe),
      TALER_JSON_pack_kycte ("operation_type",
                             al->operation_type)
      );
    GNUNET_assert (0 ==
                   json_array_append_new (
                     hard_limits,
                     j));
  }

  zero_limits = json_array ();
  for (unsigned int i = 0; i < kd->zero_limits_length; i++)
  {
    const struct TALER_EXCHANGE_ZeroLimitedOperation *zol
      = &kd->zero_limits[i];
    json_t *j;

    j = GNUNET_JSON_PACK (
      TALER_JSON_pack_kycte ("operation_type",
                             zol->operation_type)
      );
    GNUNET_assert (0 ==
                   json_array_append_new (
                     zero_limits,
                     j));
  }

  keys = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("version",
                             kd->version),
    GNUNET_JSON_pack_string ("currency",
                             kd->currency),
    GNUNET_JSON_pack_object_steal ("currency_specification",
                                   TALER_CONFIG_currency_specs_to_json (
                                     &kd->cspec)),
    TALER_JSON_pack_amount ("stefan_abs",
                            &kd->stefan_abs),
    TALER_JSON_pack_amount ("stefan_log",
                            &kd->stefan_log),
    GNUNET_JSON_pack_double ("stefan_lin",
                             kd->stefan_lin),
    GNUNET_JSON_pack_string ("asset_type",
                             kd->asset_type),
    GNUNET_JSON_pack_data_auto ("master_public_key",
                                &kd->master_pub),
    GNUNET_JSON_pack_time_rel ("reserve_closing_delay",
                               kd->reserve_closing_delay),
    GNUNET_JSON_pack_timestamp ("list_issue_date",
                                kd->list_issue_date),
    GNUNET_JSON_pack_array_steal ("global_fees",
                                  global_fees),
    GNUNET_JSON_pack_array_steal ("signkeys",
                                  signkeys),
    GNUNET_JSON_pack_object_steal ("wire_fees",
                                   wire_fees),
    GNUNET_JSON_pack_array_steal ("accounts",
                                  accounts),
    GNUNET_JSON_pack_array_steal ("wads",
                                  json_array ()),
    GNUNET_JSON_pack_array_steal ("hard_limits",
                                  hard_limits),
    GNUNET_JSON_pack_array_steal ("zero_limits",
                                  zero_limits),
    GNUNET_JSON_pack_array_steal ("denominations",
                                  denominations_by_group),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_array_steal ("recoup",
                                    recoup)),
    GNUNET_JSON_pack_array_steal ("auditors",
                                  auditors),
    GNUNET_JSON_pack_bool ("rewards_allowed",
                           kd->rewards_allowed),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_incref ("extensions",
                                      kd->extensions)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_is_zero (&kd->extensions_sig)
      ? GNUNET_JSON_pack_string ("dummy",
                                 NULL)
      : GNUNET_JSON_pack_data_auto ("extensions_sig",
                                    &kd->extensions_sig)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_array_steal ("wallet_balance_limit_without_kyc",
                                    wblwk))

    );
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_uint64 ("version",
                             EXCHANGE_SERIALIZATION_FORMAT_VERSION),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp ("expire",
                                  kd->key_data_expiration)),
    GNUNET_JSON_pack_string ("exchange_url",
                             kd->exchange_url),
    GNUNET_JSON_pack_object_steal ("keys",
                                   keys));
}


/* end of exchange_api_handle.c */
