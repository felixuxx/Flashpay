/*
   This file is part of TALER
   Copyright (C) 2014-2022 Taler Systems SA

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
 * @file lib/exchange_api_batch_deposit.c
 * @brief Implementation of the /batch-deposit request of the exchange's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_auditor_service.h"
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * 1:#AUDITOR_CHANCE is the probability that we report deposits
 * to the auditor.
 *
 * 20==5% of going to auditor. This is possibly still too high, but set
 * deliberately this high for testing
 */
#define AUDITOR_CHANCE 20

/**
 * @brief A Deposit Handle
 */
struct TALER_EXCHANGE_BatchDepositHandle
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
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext ctx;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_BatchDepositResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Details about the contract.
   */
  struct TALER_EXCHANGE_DepositContractDetail dcd;

  /**
   * Array with details about the coins.
   */
  struct TALER_EXCHANGE_CoinDepositDetail *cdds;

  /**
   * Hash of the merchant's wire details.
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * Hash over the extensions, or all zero.
   */
  struct TALER_ExtensionPolicyHashP h_policy;

  /**
   * Time when this confirmation was generated / when the exchange received
   * the deposit request.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Exchange signatures, set for #auditor_cb.
   */
  struct TALER_ExchangeSignatureP *exchange_sigs;

  /**
   * Exchange signing public key, set for #auditor_cb.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Chance that we will inform the auditor about the deposit
   * is 1:n, where the value of this field is "n".
   */
  unsigned int auditor_chance;

  /**
   * Length of the @e cdds array.
   */
  unsigned int num_cdds;

};


/**
 * Function called for each auditor to give us a chance to possibly
 * launch a deposit confirmation interaction.
 *
 * @param cls closure
 * @param ah handle to the auditor
 * @param auditor_pub public key of the auditor
 * @return NULL if no deposit confirmation interaction was launched
 */
static struct TEAH_AuditorInteractionEntry *
auditor_cb (void *cls,
            struct TALER_AUDITOR_Handle *ah,
            const struct TALER_AuditorPublicKeyP *auditor_pub)
{
  struct TALER_EXCHANGE_BatchDepositHandle *dh = cls;
  const struct TALER_EXCHANGE_Keys *key_state;
  const struct TALER_EXCHANGE_SigningPublicKey *spk;
  struct TEAH_AuditorInteractionEntry *aie;
  struct TALER_Amount amount_without_fee;
  const struct TALER_EXCHANGE_DenomPublicKey *dki;
  unsigned int coin;

  if (0 !=
      GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                dh->auditor_chance))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Not providing deposit confirmation to auditor\n");
    return NULL;
  }
  coin = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                   dh->num_cdds);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Will provide deposit confirmation to auditor `%s'\n",
              TALER_B2S (auditor_pub));
  key_state = TALER_EXCHANGE_get_keys (dh->exchange);
  dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                     &dh->cdds[coin].h_denom_pub);
  GNUNET_assert (NULL != dki);
  spk = TALER_EXCHANGE_get_signing_key_info (key_state,
                                             &dh->exchange_pub);
  if (NULL == spk)
  {
    GNUNET_break_op (0);
    return NULL;
  }
  GNUNET_assert (0 <=
                 TALER_amount_subtract (&amount_without_fee,
                                        &dh->cdds[coin].amount,
                                        &dki->fees.deposit));
  aie = GNUNET_new (struct TEAH_AuditorInteractionEntry);
  aie->dch = TALER_AUDITOR_deposit_confirmation (
    ah,
    &dh->h_wire,
    &dh->h_policy,
    &dh->dcd.h_contract_terms,
    dh->exchange_timestamp,
    dh->dcd.wire_deadline,
    dh->dcd.refund_deadline,
    &amount_without_fee,
    &dh->cdds[coin].coin_pub,
    &dh->dcd.merchant_pub,
    &dh->exchange_pub,
    &dh->exchange_sigs[coin],
    &key_state->master_pub,
    spk->valid_from,
    spk->valid_until,
    spk->valid_legal,
    &spk->master_sig,
    &TEAH_acc_confirmation_cb,
    aie);
  return aie;
}


/**
 * Function called when we're done processing the
 * HTTP /deposit request.
 *
 * @param cls the `struct TALER_EXCHANGE_BatchDepositHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_deposit_finished (void *cls,
                         long response_code,
                         const void *response)
{
  struct TALER_EXCHANGE_BatchDepositHandle *dh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_BatchDepositResult dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };
  const struct TALER_EXCHANGE_Keys *keys;

  dh->job = NULL;
  keys = TALER_EXCHANGE_get_keys (dh->exchange);
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      const struct TALER_EXCHANGE_Keys *key_state;
      const json_t *sigs;
      json_t *sig;
      unsigned int idx;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_array_const ("exchange_sigs",
                                      &sigs),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &dh->exchange_pub),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_string ("transaction_base_url",
                                   &dr.details.ok.transaction_base_url),
          NULL),
        GNUNET_JSON_spec_timestamp ("exchange_timestamp",
                                    &dh->exchange_timestamp),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      if (json_array_size (sigs) != dh->num_cdds)
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      dh->exchange_sigs = GNUNET_new_array (dh->num_cdds,
                                            struct TALER_ExchangeSignatureP);
      key_state = TALER_EXCHANGE_get_keys (dh->exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &dh->exchange_pub))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_DEPOSIT_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }
      json_array_foreach (sigs, idx, sig)
      {
        struct GNUNET_JSON_Specification ispec[] = {
          GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                       &dh->exchange_sigs[idx]),
          GNUNET_JSON_spec_end ()
        };
        struct TALER_Amount amount_without_fee;
        const struct TALER_EXCHANGE_DenomPublicKey *dki;

        if (GNUNET_OK !=
            GNUNET_JSON_parse (sig,
                               ispec,
                               NULL, NULL))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                           &dh->cdds[idx].
                                                           h_denom_pub);
        GNUNET_assert (NULL != dki);
        GNUNET_assert (0 <=
                       TALER_amount_subtract (&amount_without_fee,
                                              &dh->cdds[idx].amount,
                                              &dki->fees.deposit));

        if (GNUNET_OK !=
            TALER_exchange_online_deposit_confirmation_verify (
              &dh->dcd.h_contract_terms,
              &dh->h_wire,
              &dh->h_policy,
              dh->exchange_timestamp,
              dh->dcd.wire_deadline,
              dh->dcd.refund_deadline,
              &amount_without_fee,
              &dh->cdds[idx].coin_pub,
              &dh->dcd.merchant_pub,
              &dh->exchange_pub,
              &dh->exchange_sigs[idx]))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_EXCHANGE_DEPOSIT_INVALID_SIGNATURE_BY_EXCHANGE;
          break;
        }
      }
      TEAH_get_auditors_for_dc (dh->exchange,
                                &auditor_cb,
                                dh);
    }
    dr.details.ok.exchange_sigs = dh->exchange_sigs;
    dr.details.ok.exchange_pub = &dh->exchange_pub;
    dr.details.ok.deposit_timestamp = dh->exchange_timestamp;
    dr.details.ok.num_signatures = dh->num_cdds;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    {
      const struct TALER_EXCHANGE_Keys *key_state;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                     &coin_pub),
        GNUNET_JSON_spec_end ()
      };
      const struct TALER_EXCHANGE_DenomPublicKey *dki;
      bool found = false;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      for (unsigned int i = 0; i<dh->num_cdds; i++)
      {
        if (0 !=
            GNUNET_memcmp (&coin_pub,
                           &dh->cdds[i].coin_pub))
          continue;
        key_state = TALER_EXCHANGE_get_keys (dh->exchange);
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                           &dh->cdds[i].
                                                           h_denom_pub);
        GNUNET_assert (NULL != dki);
        if (GNUNET_OK !=
            TALER_EXCHANGE_check_coin_conflict_ (
              keys,
              j,
              dki,
              &dh->cdds[i].coin_pub,
              &dh->cdds[i].coin_sig,
              &dh->cdds[i].amount))
        {
          GNUNET_break_op (0);
          dr.hr.http_status = 0;
          dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
          break;
        }
        found = true;
        break;
      }
      if (! found)
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      dr.hr.ec = TALER_JSON_get_error_code (j);
      dr.hr.hint = TALER_JSON_get_error_hint (j);
    }
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dr.hr.ec = TALER_JSON_get_error_code (j);
    dr.hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange deposit\n",
                (unsigned int) response_code,
                dr.hr.ec);
    GNUNET_break_op (0);
    break;
  }
  dh->cb (dh->cb_cls,
          &dr);
  TALER_EXCHANGE_batch_deposit_cancel (dh);
}


struct TALER_EXCHANGE_BatchDepositHandle *
TALER_EXCHANGE_batch_deposit (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_EXCHANGE_DepositContractDetail *dcd,
  unsigned int num_cdds,
  const struct TALER_EXCHANGE_CoinDepositDetail *cdds,
  TALER_EXCHANGE_BatchDepositResultCallback cb,
  void *cb_cls,
  enum TALER_ErrorCode *ec)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  struct TALER_EXCHANGE_BatchDepositHandle *dh;
  struct GNUNET_CURL_Context *ctx;
  json_t *deposit_obj;
  json_t *deposits;
  CURL *eh;
  struct TALER_Amount amount_without_fee;

  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  if (GNUNET_TIME_timestamp_cmp (dcd->refund_deadline,
                                 >,
                                 dcd->wire_deadline))
  {
    GNUNET_break_op (0);
    *ec = TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE;
    return NULL;
  }
  key_state = TALER_EXCHANGE_get_keys (exchange);
  dh = GNUNET_new (struct TALER_EXCHANGE_BatchDepositHandle);
  dh->auditor_chance = AUDITOR_CHANCE;
  dh->exchange = exchange;
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  dh->cdds = GNUNET_memdup (cdds,
                            num_cdds
                            * sizeof (*cdds));
  dh->num_cdds = num_cdds;
  dh->dcd = *dcd;
  if (NULL != dcd->policy_details)
    TALER_deposit_policy_hash (dcd->policy_details,
                               &dh->h_policy);
  TALER_merchant_wire_signature_hash (dcd->merchant_payto_uri,
                                      &dcd->wire_salt,
                                      &dh->h_wire);
  deposits = json_array ();
  GNUNET_assert (NULL != deposits);
  for (unsigned int i = 0; i<num_cdds; i++)
  {
    const struct TALER_EXCHANGE_CoinDepositDetail *cdd = &cdds[i];
    const struct TALER_EXCHANGE_DenomPublicKey *dki;

    dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                       &cdd->h_denom_pub);
    if (NULL == dki)
    {
      *ec = TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
      GNUNET_break_op (0);
      return NULL;
    }
    if (0 >
        TALER_amount_subtract (&amount_without_fee,
                               &cdd->amount,
                               &dki->fees.deposit))
    {
      *ec = TALER_EC_EXCHANGE_DEPOSIT_FEE_ABOVE_AMOUNT;
      GNUNET_break_op (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Amount: %s\n",
                  TALER_amount2s (&cdd->amount));
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Fee: %s\n",
                  TALER_amount2s (&dki->fees.deposit));
      GNUNET_free (dh->cdds);
      GNUNET_free (dh);
      return NULL;
    }

    if (GNUNET_OK !=
        TALER_EXCHANGE_verify_deposit_signature_ (dcd,
                                                  &dh->h_policy,
                                                  &dh->h_wire,
                                                  cdd,
                                                  dki))
    {
      *ec = TALER_EC_EXCHANGE_DEPOSIT_COIN_SIGNATURE_INVALID;
      GNUNET_break_op (0);
      GNUNET_free (dh->cdds);
      GNUNET_free (dh);
      return NULL;
    }
    GNUNET_assert (
      0 ==
      json_array_append_new (
        deposits,
        GNUNET_JSON_PACK (
          TALER_JSON_pack_amount ("contribution",
                                  &cdd->amount),
          GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                      &cdd->h_denom_pub),
          TALER_JSON_pack_denom_sig ("ub_sig",
                                     &cdd->denom_sig),
          GNUNET_JSON_pack_data_auto ("coin_pub",
                                      &cdd->coin_pub),
          GNUNET_JSON_pack_allow_null (
            GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                        &cdd->h_age_commitment)),
          GNUNET_JSON_pack_data_auto ("coin_sig",
                                      &cdd->coin_sig)
          )));
  }
  dh->url = TEAH_path_to_url (exchange,
                              "/batch-deposit");
  if (NULL == dh->url)
  {
    GNUNET_break (0);
    *ec = TALER_EC_GENERIC_ALLOCATION_FAILURE;
    GNUNET_free (dh->url);
    GNUNET_free (dh->cdds);
    GNUNET_free (dh);
    return NULL;
  }

  deposit_obj = GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("merchant_payto_uri",
                             dcd->merchant_payto_uri),
    GNUNET_JSON_pack_data_auto ("wire_salt",
                                &dcd->wire_salt),
    GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                &dcd->h_contract_terms),
    GNUNET_JSON_pack_array_steal ("coins",
                                  deposits),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_steal ("policy_details",
                                     dcd->policy_details)),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                dcd->timestamp),
    GNUNET_JSON_pack_data_auto ("merchant_pub",
                                &dcd->merchant_pub),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp ("refund_deadline",
                                  dcd->refund_deadline)),
    GNUNET_JSON_pack_timestamp ("wire_transfer_deadline",
                                dcd->wire_deadline));
  GNUNET_assert (NULL != deposit_obj);
  eh = TALER_EXCHANGE_curl_easy_get_ (dh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&dh->ctx,
                              eh,
                              deposit_obj)) )
  {
    *ec = TALER_EC_GENERIC_CURL_ALLOCATION_FAILURE;
    GNUNET_break (0);
    if (NULL != eh)
      curl_easy_cleanup (eh);
    json_decref (deposit_obj);
    GNUNET_free (dh->cdds);
    GNUNET_free (dh->url);
    GNUNET_free (dh);
    return NULL;
  }
  json_decref (deposit_obj);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "URL for deposit: `%s'\n",
              dh->url);
  ctx = TEAH_handle_to_context (exchange);
  dh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  dh->ctx.headers,
                                  &handle_deposit_finished,
                                  dh);
  return dh;
}


void
TALER_EXCHANGE_batch_deposit_force_dc (
  struct TALER_EXCHANGE_BatchDepositHandle *deposit)
{
  deposit->auditor_chance = 1;
}


void
TALER_EXCHANGE_batch_deposit_cancel (
  struct TALER_EXCHANGE_BatchDepositHandle *deposit)
{
  if (NULL != deposit->job)
  {
    GNUNET_CURL_job_cancel (deposit->job);
    deposit->job = NULL;
  }
  GNUNET_free (deposit->url);
  GNUNET_free (deposit->cdds);
  GNUNET_free (deposit->exchange_sigs);
  TALER_curl_easy_post_finished (&deposit->ctx);
  GNUNET_free (deposit);
}


/* end of exchange_api_batch_deposit.c */
