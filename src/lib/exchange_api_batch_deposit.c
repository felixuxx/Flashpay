/*
   This file is part of TALER
   Copyright (C) 2014-2024 Taler Systems SA

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
 * Entry in list of ongoing interactions with an auditor.
 */
struct TEAH_AuditorInteractionEntry
{
  /**
   * DLL entry.
   */
  struct TEAH_AuditorInteractionEntry *next;

  /**
   * DLL entry.
   */
  struct TEAH_AuditorInteractionEntry *prev;

  /**
   * URL of our auditor. For logging.
   */
  const char *auditor_url;

  /**
   * Interaction state.
   */
  struct TALER_AUDITOR_DepositConfirmationHandle *dch;

  /**
   * Batch deposit this is for.
   */
  struct TALER_EXCHANGE_BatchDepositHandle *dh;
};


/**
 * @brief A Deposit Handle
 */
struct TALER_EXCHANGE_BatchDepositHandle
{

  /**
   * The keys of the exchange.
   */
  struct TALER_EXCHANGE_Keys *keys;

  /**
   * Context for our curl request(s).
   */
  struct GNUNET_CURL_Context *ctx;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Context for #TEH_curl_easy_post(). Keeps the data that must
   * persist for Curl to make the upload.
   */
  struct TALER_CURL_PostContext post_ctx;

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
   * Exchange signature, set for #auditor_cb.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * Head of DLL of interactions with this auditor.
   */
  struct TEAH_AuditorInteractionEntry *ai_head;

  /**
   * Tail of DLL of interactions with this auditor.
   */
  struct TEAH_AuditorInteractionEntry *ai_tail;

  /**
   * Result to return to the application once @e ai_head is empty.
   */
  struct TALER_EXCHANGE_BatchDepositResult dr;

  /**
   * Exchange signing public key, set for #auditor_cb.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Total amount deposited without fees as calculated by us.
   */
  struct TALER_Amount total_without_fee;

  /**
   * Response object to free at the end.
   */
  json_t *response;

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
 * Finish batch deposit operation by calling the callback.
 *
 * @param[in] dh handle to finished batch deposit operation
 */
static void
finish_dh (struct TALER_EXCHANGE_BatchDepositHandle *dh)
{
  dh->cb (dh->cb_cls,
          &dh->dr);
  TALER_EXCHANGE_batch_deposit_cancel (dh);
}


/**
 * Function called with the result from our call to the
 * auditor's /deposit-confirmation handler.
 *
 * @param cls closure of type `struct TEAH_AuditorInteractionEntry *`
 * @param dcr response
 */
static void
acc_confirmation_cb (
  void *cls,
  const struct TALER_AUDITOR_DepositConfirmationResponse *dcr)
{
  struct TEAH_AuditorInteractionEntry *aie = cls;
  struct TALER_EXCHANGE_BatchDepositHandle *dh = aie->dh;

  if (MHD_HTTP_OK != dcr->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to submit deposit confirmation to auditor `%s' with HTTP status %d (EC: %d). This is acceptable if it does not happen often.\n",
                aie->auditor_url,
                dcr->hr.http_status,
                dcr->hr.ec);
  }
  GNUNET_CONTAINER_DLL_remove (dh->ai_head,
                               dh->ai_tail,
                               aie);
  GNUNET_free (aie);
  if (NULL == dh->ai_head)
    finish_dh (dh);
}


/**
 * Function called for each auditor to give us a chance to possibly
 * launch a deposit confirmation interaction.
 *
 * @param cls closure
 * @param auditor_url base URL of the auditor
 * @param auditor_pub public key of the auditor
 */
static void
auditor_cb (void *cls,
            const char *auditor_url,
            const struct TALER_AuditorPublicKeyP *auditor_pub)
{
  struct TALER_EXCHANGE_BatchDepositHandle *dh = cls;
  const struct TALER_EXCHANGE_SigningPublicKey *spk;
  struct TEAH_AuditorInteractionEntry *aie;
  const struct TALER_CoinSpendSignatureP *csigs[GNUNET_NZL (
                                                  dh->num_cdds)];
  const struct TALER_CoinSpendPublicKeyP *cpubs[GNUNET_NZL (
                                                  dh->num_cdds)];

  for (unsigned int i = 0; i<dh->num_cdds; i++)
  {
    const struct TALER_EXCHANGE_CoinDepositDetail *cdd = &dh->cdds[i];

    csigs[i] = &cdd->coin_sig;
    cpubs[i] = &cdd->coin_pub;
  }

  if (0 !=
      GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                dh->auditor_chance))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Not providing deposit confirmation to auditor\n");
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Will provide deposit confirmation to auditor `%s'\n",
              TALER_B2S (auditor_pub));
  spk = TALER_EXCHANGE_get_signing_key_info (dh->keys,
                                             &dh->exchange_pub);
  if (NULL == spk)
  {
    GNUNET_break_op (0);
    return;
  }
  aie = GNUNET_new (struct TEAH_AuditorInteractionEntry);
  aie->dh = dh;
  aie->auditor_url = auditor_url;
  aie->dch = TALER_AUDITOR_deposit_confirmation (
    dh->ctx,
    auditor_url,
    &dh->h_wire,
    &dh->h_policy,
    &dh->dcd.h_contract_terms,
    dh->exchange_timestamp,
    dh->dcd.wire_deadline,
    dh->dcd.refund_deadline,
    &dh->total_without_fee,
    dh->num_cdds,
    cpubs,
    csigs,
    &dh->dcd.merchant_pub,
    &dh->exchange_pub,
    &dh->exchange_sig,
    &dh->keys->master_pub,
    spk->valid_from,
    spk->valid_until,
    spk->valid_legal,
    &spk->master_sig,
    &acc_confirmation_cb,
    aie);
  GNUNET_CONTAINER_DLL_insert (dh->ai_head,
                               dh->ai_tail,
                               aie);
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
  struct TALER_EXCHANGE_BatchDepositResult *dr = &dh->dr;

  dh->job = NULL;
  dh->response = json_incref ((json_t*) j);
  dr->hr.reply = dh->response;
  dr->hr.http_status = (unsigned int) response_code;
  switch (response_code)
  {
  case 0:
    dr->hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &dh->exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &dh->exchange_pub),
        GNUNET_JSON_spec_mark_optional (
          TALER_JSON_spec_web_url ("transaction_base_url",
                                   &dr->details.ok.transaction_base_url),
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
        dr->hr.http_status = 0;
        dr->hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (dh->keys,
                                           &dh->exchange_pub))
      {
        GNUNET_break_op (0);
        dr->hr.http_status = 0;
        dr->hr.ec = TALER_EC_EXCHANGE_DEPOSIT_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }
      {
        const struct TALER_CoinSpendSignatureP *csigs[
          GNUNET_NZL (dh->num_cdds)];

        for (unsigned int i = 0; i<dh->num_cdds; i++)
          csigs[i] = &dh->cdds[i].coin_sig;
        if (GNUNET_OK !=
            TALER_exchange_online_deposit_confirmation_verify (
              &dh->dcd.h_contract_terms,
              &dh->h_wire,
              &dh->h_policy,
              dh->exchange_timestamp,
              dh->dcd.wire_deadline,
              dh->dcd.refund_deadline,
              &dh->total_without_fee,
              dh->num_cdds,
              csigs,
              &dh->dcd.merchant_pub,
              &dh->exchange_pub,
              &dh->exchange_sig))
        {
          GNUNET_break_op (0);
          dr->hr.http_status = 0;
          dr->hr.ec = TALER_EC_EXCHANGE_DEPOSIT_INVALID_SIGNATURE_BY_EXCHANGE;
          break;
        }
      }
      TEAH_get_auditors_for_dc (dh->keys,
                                &auditor_cb,
                                dh);
    }
    dr->details.ok.exchange_sig = &dh->exchange_sig;
    dr->details.ok.exchange_pub = &dh->exchange_pub;
    dr->details.ok.deposit_timestamp = dh->exchange_timestamp;
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    dr->hr.ec = TALER_JSON_get_error_code (j);
    dr->hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_FORBIDDEN:
    dr->hr.ec = TALER_JSON_get_error_code (j);
    dr->hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    dr->hr.ec = TALER_JSON_get_error_code (j);
    dr->hr.hint = TALER_JSON_get_error_hint (j);
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    {
      dr->hr.ec = TALER_JSON_get_error_code (j);
      dr->hr.hint = TALER_JSON_get_error_hint (j);
      switch (dr->hr.ec)
      {
      case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
        {
          struct GNUNET_JSON_Specification spec[] = {
            GNUNET_JSON_spec_fixed_auto (
              "coin_pub",
              &dr->details.conflict.details
              .insufficient_funds.coin_pub),
            GNUNET_JSON_spec_end ()
          };

          if (GNUNET_OK !=
              GNUNET_JSON_parse (j,
                                 spec,
                                 NULL, NULL))
          {
            GNUNET_break_op (0);
            dr->hr.http_status = 0;
            dr->hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
            break;
          }
        }
        break;
      case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_AGE_HASH:
        {
          struct GNUNET_JSON_Specification spec[] = {
            GNUNET_JSON_spec_fixed_auto (
              "coin_pub",
              &dr->details.conflict.details
              .coin_conflicting_age_hash.coin_pub),
            GNUNET_JSON_spec_end ()
          };

          if (GNUNET_OK !=
              GNUNET_JSON_parse (j,
                                 spec,
                                 NULL, NULL))
          {
            GNUNET_break_op (0);
            dr->hr.http_status = 0;
            dr->hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
            break;
          }
        }
        break;
      case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
        {
          struct GNUNET_JSON_Specification spec[] = {
            GNUNET_JSON_spec_fixed_auto (
              "coin_pub",
              &dr->details.conflict.details
              .coin_conflicting_denomination_key.coin_pub),
            GNUNET_JSON_spec_end ()
          };

          if (GNUNET_OK !=
              GNUNET_JSON_parse (j,
                                 spec,
                                 NULL, NULL))
          {
            GNUNET_break_op (0);
            dr->hr.http_status = 0;
            dr->hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
            break;
          }
        }
        break;
      case TALER_EC_EXCHANGE_DEPOSIT_CONFLICTING_CONTRACT:
        break;
      default:
        GNUNET_break_op (0);
        break;
      }
    }
    break;
  case MHD_HTTP_GONE:
    /* could happen if denomination was revoked */
    /* Note: one might want to check /keys for revocation
       signature here, alas tricky in case our /keys
       is outdated => left to clients */
    dr->hr.ec = TALER_JSON_get_error_code (j);
    dr->hr.hint = TALER_JSON_get_error_hint (j);
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (
          "h_payto",
          &dr->details.unavailable_for_legal_reasons.h_payto),
        GNUNET_JSON_spec_uint64 (
          "requirement_row",
          &dr->details.unavailable_for_legal_reasons.requirement_row),
        GNUNET_JSON_spec_bool (
          "bad_kyc_auth",
          &dr->details.unavailable_for_legal_reasons.bad_kyc_auth),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (j,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        dr->hr.http_status = 0;
        dr->hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    dr->hr.ec = TALER_JSON_get_error_code (j);
    dr->hr.hint = TALER_JSON_get_error_hint (j);
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    dr->hr.ec = TALER_JSON_get_error_code (j);
    dr->hr.hint = TALER_JSON_get_error_hint (j);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d for exchange deposit\n",
                (unsigned int) response_code,
                dr->hr.ec);
    GNUNET_break_op (0);
    break;
  }
  if (NULL != dh->ai_head)
    return;
  finish_dh (dh);
}


struct TALER_EXCHANGE_BatchDepositHandle *
TALER_EXCHANGE_batch_deposit (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_EXCHANGE_DepositContractDetail *dcd,
  unsigned int num_cdds,
  const struct TALER_EXCHANGE_CoinDepositDetail cdds[static num_cdds],
  TALER_EXCHANGE_BatchDepositResultCallback cb,
  void *cb_cls,
  enum TALER_ErrorCode *ec)
{
  struct TALER_EXCHANGE_BatchDepositHandle *dh;
  json_t *deposit_obj;
  json_t *deposits;
  CURL *eh;
  const struct GNUNET_HashCode *wallet_data_hashp;

  if (0 == num_cdds)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_TIME_timestamp_cmp (dcd->refund_deadline,
                                 >,
                                 dcd->wire_deadline))
  {
    GNUNET_break_op (0);
    *ec = TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE;
    return NULL;
  }
  dh = GNUNET_new (struct TALER_EXCHANGE_BatchDepositHandle);
  dh->auditor_chance = AUDITOR_CHANCE;
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  dh->cdds = GNUNET_memdup (cdds,
                            num_cdds * sizeof (*cdds));
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
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (cdds[0].amount.currency,
                                        &dh->total_without_fee));
  for (unsigned int i = 0; i<num_cdds; i++)
  {
    const struct TALER_EXCHANGE_CoinDepositDetail *cdd = &cdds[i];
    const struct TALER_EXCHANGE_DenomPublicKey *dki;
    const struct TALER_AgeCommitmentHash *h_age_commitmentp;
    struct TALER_Amount amount_without_fee;

    dki = TALER_EXCHANGE_get_denomination_key_by_hash (keys,
                                                       &cdd->h_denom_pub);
    if (NULL == dki)
    {
      *ec = TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
      GNUNET_break_op (0);
      json_decref (deposits);
      return NULL;
    }
    if (0 >
        TALER_amount_subtract (&amount_without_fee,
                               &cdd->amount,
                               &dki->fees.deposit))
    {
      *ec = TALER_EC_EXCHANGE_DEPOSIT_FEE_ABOVE_AMOUNT;
      GNUNET_break_op (0);
      GNUNET_free (dh->cdds);
      GNUNET_free (dh);
      json_decref (deposits);
      return NULL;
    }
    GNUNET_assert (0 <=
                   TALER_amount_add (&dh->total_without_fee,
                                     &dh->total_without_fee,
                                     &amount_without_fee));
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
      json_decref (deposits);
      return NULL;
    }
    if (! GNUNET_is_zero (&dcd->merchant_sig))
    {
      /* FIXME #9185: check merchant_sig!? */
    }
    if (GNUNET_is_zero (&cdd->h_age_commitment))
      h_age_commitmentp = NULL;
    else
      h_age_commitmentp = &cdd->h_age_commitment;
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
                                        h_age_commitmentp)),
          GNUNET_JSON_pack_data_auto ("coin_sig",
                                      &cdd->coin_sig)
          )));
  }
  dh->url = TALER_url_join (url,
                            "batch-deposit",
                            NULL);
  if (NULL == dh->url)
  {
    GNUNET_break (0);
    *ec = TALER_EC_GENERIC_ALLOCATION_FAILURE;
    GNUNET_free (dh->url);
    GNUNET_free (dh->cdds);
    GNUNET_free (dh);
    json_decref (deposits);
    return NULL;
  }

  if (GNUNET_is_zero (&dcd->wallet_data_hash))
    wallet_data_hashp = NULL;
  else
    wallet_data_hashp = &dcd->wallet_data_hash;

  deposit_obj = GNUNET_JSON_PACK (
    TALER_JSON_pack_full_payto ("merchant_payto_uri",
                                dcd->merchant_payto_uri),
    GNUNET_JSON_pack_data_auto ("wire_salt",
                                &dcd->wire_salt),
    GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                &dcd->h_contract_terms),
    GNUNET_JSON_pack_array_steal ("coins",
                                  deposits),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_data_auto ("wallet_data_hash",
                                  wallet_data_hashp)),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_object_steal ("policy_details",
                                     (json_t *) dcd->policy_details)),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                dcd->wallet_timestamp),
    GNUNET_JSON_pack_data_auto ("merchant_pub",
                                &dcd->merchant_pub),
    GNUNET_JSON_pack_data_auto ("merchant_sig",
                                &dcd->merchant_sig),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp ("refund_deadline",
                                  dcd->refund_deadline)),
    GNUNET_JSON_pack_timestamp ("wire_transfer_deadline",
                                dcd->wire_deadline));
  GNUNET_assert (NULL != deposit_obj);
  eh = TALER_EXCHANGE_curl_easy_get_ (dh->url);
  if ( (NULL == eh) ||
       (GNUNET_OK !=
        TALER_curl_easy_post (&dh->post_ctx,
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
  dh->ctx = ctx;
  dh->keys = TALER_EXCHANGE_keys_incref (keys);
  dh->job = GNUNET_CURL_job_add2 (ctx,
                                  eh,
                                  dh->post_ctx.headers,
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
  struct TEAH_AuditorInteractionEntry *aie;

  while (NULL != (aie = deposit->ai_head))
  {
    GNUNET_assert (aie->dh == deposit);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Not sending deposit confirmation to auditor `%s' due to cancellation\n",
                aie->auditor_url);
    TALER_AUDITOR_deposit_confirmation_cancel (aie->dch);
    GNUNET_CONTAINER_DLL_remove (deposit->ai_head,
                                 deposit->ai_tail,
                                 aie);
    GNUNET_free (aie);
  }
  if (NULL != deposit->job)
  {
    GNUNET_CURL_job_cancel (deposit->job);
    deposit->job = NULL;
  }
  TALER_EXCHANGE_keys_decref (deposit->keys);
  GNUNET_free (deposit->url);
  GNUNET_free (deposit->cdds);
  TALER_curl_easy_post_finished (&deposit->post_ctx);
  json_decref (deposit->response);
  GNUNET_free (deposit);
}


/* end of exchange_api_batch_deposit.c */
