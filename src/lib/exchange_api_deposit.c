/*
   This file is part of TALER
   Copyright (C) 2014-2021 Taler Systems SA

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
 * @file lib/exchange_api_deposit.c
 * @brief Implementation of the /deposit request of the exchange's HTTP API
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
struct TALER_EXCHANGE_DepositHandle
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
  TALER_EXCHANGE_DepositResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct TALER_PrivateContractHash h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHash h_wire GNUNET_PACKED;

  /**
   * Hash over the extension options of the deposit, 0 if there
   * were not extension options.
   */
  struct TALER_ExtensionContractHash h_extensions GNUNET_PACKED;

  /**
   * Time when this confirmation was generated / when the exchange received
   * the deposit request.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * By when does the exchange expect to pay the merchant
   * (as per the merchant's request).
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * How much time does the @e merchant have to issue a refund
   * request?  Zero if refunds are not allowed.  After this time, the
   * coin cannot be refunded.  Note that the wire transfer will not be
   * performed by the exchange until the refund deadline.  This value
   * is taken from the original deposit request.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * Amount to be deposited, excluding fee.  Calculated from the
   * amount with fee and the fee from the deposit request.
   */
  struct TALER_Amount amount_without_fee;

  /**
   * The public key of the coin that was deposited.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Exchange signature, set for #auditor_cb.
   */
  struct TALER_ExchangeSignatureP exchange_sig;

  /**
   * Exchange signing public key, set for #auditor_cb.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * Value of the /deposit transaction, including fee.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * @brief Public information about the coin's denomination key.
   * Note that the "key" field itself has been zero'ed out.
   */
  struct TALER_EXCHANGE_DenomPublicKey dki;

  /**
   * Chance that we will inform the auditor about the deposit
   * is 1:n, where the value of this field is "n".
   */
  unsigned int auditor_chance;

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
  struct TALER_EXCHANGE_DepositHandle *dh = cls;
  const struct TALER_EXCHANGE_Keys *key_state;
  const struct TALER_EXCHANGE_SigningPublicKey *spk;
  struct TEAH_AuditorInteractionEntry *aie;

  if (0 != GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                     dh->auditor_chance))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Not providing deposit confirmation to auditor\n");
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Will provide deposit confirmation to auditor `%s'\n",
              TALER_B2S (auditor_pub));
  key_state = TALER_EXCHANGE_get_keys (dh->exchange);
  spk = TALER_EXCHANGE_get_signing_key_info (key_state,
                                             &dh->exchange_pub);
  if (NULL == spk)
  {
    GNUNET_break_op (0);
    return NULL;
  }
  aie = GNUNET_new (struct TEAH_AuditorInteractionEntry);
  aie->dch = TALER_AUDITOR_deposit_confirmation (
    ah,
    &dh->h_wire,
    &dh->h_extensions,
    &dh->h_contract_terms,
    dh->exchange_timestamp,
    dh->wire_deadline,
    dh->refund_deadline,
    &dh->amount_without_fee,
    &dh->coin_pub,
    &dh->merchant_pub,
    &dh->exchange_pub,
    &dh->exchange_sig,
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
 * Verify that the signatures on the "403 FORBIDDEN" response from the
 * exchange demonstrating customer double-spending are valid.
 *
 * @param dh deposit handle
 * @param json json reply with the signature(s) and transaction history
 * @return #GNUNET_OK if the signature(s) is valid, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_deposit_signature_conflict (
  const struct TALER_EXCHANGE_DepositHandle *dh,
  const json_t *json)
{
  json_t *history;
  struct TALER_Amount total;
  enum TALER_ErrorCode ec;
  struct TALER_DenominationHash h_denom_pub;

  memset (&h_denom_pub,
          0,
          sizeof (h_denom_pub));
  history = json_object_get (json,
                             "history");
  if (GNUNET_OK !=
      TALER_EXCHANGE_verify_coin_history (&dh->dki,
                                          dh->dki.value.currency,
                                          &dh->coin_pub,
                                          history,
                                          &h_denom_pub,
                                          &total))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  ec = TALER_JSON_get_error_code (json);
  switch (ec)
  {
  case TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS:
    if (0 >
        TALER_amount_add (&total,
                          &total,
                          &dh->amount_with_fee))
    {
      /* clearly not OK if our transaction would have caused
         the overflow... */
      return GNUNET_OK;
    }

    if (0 >= TALER_amount_cmp (&total,
                               &dh->dki.value))
    {
      /* transaction should have still fit */
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    /* everything OK, proof of double-spending was provided */
    return GNUNET_OK;
  case TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY:
    if (0 != GNUNET_memcmp (&dh->dki.h_key,
                            &h_denom_pub))
      return GNUNET_OK; /* indeed, proof with different denomination key provided */
    /* invalid proof provided */
    return GNUNET_SYSERR;
  default:
    /* unexpected error code */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
}


/**
 * Function called when we're done processing the
 * HTTP /deposit request.
 *
 * @param cls the `struct TALER_EXCHANGE_DepositHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_deposit_finished (void *cls,
                         long response_code,
                         const void *response)
{
  struct TALER_EXCHANGE_DepositHandle *dh = cls;
  const json_t *j = response;
  struct TALER_EXCHANGE_DepositResult dr = {
    .hr.reply = j,
    .hr.http_status = (unsigned int) response_code
  };

  dh->job = NULL;
  switch (response_code)
  {
  case 0:
    dr.hr.ec = TALER_EC_GENERIC_INVALID_RESPONSE;
    break;
  case MHD_HTTP_OK:
    {
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &dh->exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &dh->exchange_pub),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_string ("transaction_base_url",
                                   &dr.details.success.transaction_base_url)),
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

      if (GNUNET_OK !=
          TALER_exchange_deposit_confirm_verify (&dh->h_contract_terms,
                                                 &dh->h_wire,
                                                 &dh->h_extensions,
                                                 dh->exchange_timestamp,
                                                 dh->wire_deadline,
                                                 dh->refund_deadline,
                                                 &dh->amount_without_fee,
                                                 &dh->coin_pub,
                                                 &dh->merchant_pub,
                                                 &dh->exchange_pub,
                                                 &dh->exchange_sig))
      {
        GNUNET_break_op (0);
        dr.hr.http_status = 0;
        dr.hr.ec = TALER_EC_EXCHANGE_DEPOSIT_INVALID_SIGNATURE_BY_EXCHANGE;
        break;
      }

      TEAH_get_auditors_for_dc (dh->exchange,
                                &auditor_cb,
                                dh);

    }
    dr.details.success.exchange_sig = &dh->exchange_sig;
    dr.details.success.exchange_pub = &dh->exchange_pub;
    dr.details.success.deposit_timestamp = dh->exchange_timestamp;
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
    /* Double spending; check signatures on transaction history */
    if (GNUNET_OK !=
        verify_deposit_signature_conflict (dh,
                                           j))
    {
      GNUNET_break_op (0);
      dr.hr.http_status = 0;
      dr.hr.ec = TALER_EC_EXCHANGE_DEPOSIT_INVALID_SIGNATURE_BY_EXCHANGE;
    }
    else
    {
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
  TALER_EXCHANGE_deposit_cancel (dh);
}


/**
 * Verify signature information about the deposit.
 *
 * @param dki public key information
 * @param amount the amount to be deposited
 * @param h_wire hash of the merchant’s account details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param coin_pub coin’s public key
 * @param denom_sig exchange’s unblinded signature of the coin
 * @param denom_pub denomination key with which the coin is signed
 * @param denom_pub_hash hash of @a denom_pub
 * @param timestamp timestamp when the deposit was finalized
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed)
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made by the customer with the coin’s private key.
 * @return #GNUNET_OK if signatures are OK, #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
verify_signatures (const struct TALER_EXCHANGE_DenomPublicKey *dki,
                   const struct TALER_Amount *amount,
                   const struct TALER_MerchantWireHash *h_wire,
                   const struct TALER_PrivateContractHash *h_contract_terms,
                   const struct TALER_ExtensionContractHash *ech,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   const struct TALER_DenominationSignature *denom_sig,
                   const struct TALER_DenominationPublicKey *denom_pub,
                   const struct TALER_DenominationHash *denom_pub_hash,
                   struct GNUNET_TIME_Timestamp timestamp,
                   const struct TALER_MerchantPublicKeyP *merchant_pub,
                   struct GNUNET_TIME_Timestamp refund_deadline,
                   const struct TALER_CoinSpendSignatureP *coin_sig)
{
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (amount,
                                   &dki->fee_deposit,
                                   h_wire,
                                   h_contract_terms,
                                   ech,
                                   denom_pub_hash,
                                   timestamp,
                                   merchant_pub,
                                   refund_deadline,
                                   coin_pub,
                                   coin_sig))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Invalid coin signature on /deposit request!\n");
    TALER_LOG_DEBUG ("... amount_with_fee was %s\n",
                     TALER_amount2s (amount));
    TALER_LOG_DEBUG ("... deposit_fee was %s\n",
                     TALER_amount2s (&dki->fee_deposit));
    return GNUNET_SYSERR;
  }

  /* check coin signature */
  {
    struct TALER_CoinPublicInfo coin_info = {
      .coin_pub = *coin_pub,
      .denom_pub_hash = *denom_pub_hash,
      .denom_sig = *denom_sig,
      .age_commitment_hash = {{{0}}} /* FIXME-Oec */
    };

    if (GNUNET_YES !=
        TALER_test_coin_valid (&coin_info,
                               denom_pub))
    {
      GNUNET_break_op (0);
      TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
      return GNUNET_SYSERR;
    }
  }

  /* Check coin does make a contribution */
  if (0 < TALER_amount_cmp (&dki->fee_deposit,
                            amount))
  {
    GNUNET_break_op (0);
    TALER_LOG_WARNING ("Deposit amount smaller than fee\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


struct TALER_EXCHANGE_DepositHandle *
TALER_EXCHANGE_deposit (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_Amount *amount,
  struct GNUNET_TIME_Timestamp wire_deadline,
  const char *merchant_payto_uri,
  const struct TALER_WireSalt *wire_salt,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const json_t *extension_details,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_DenominationSignature *denom_sig,
  const struct TALER_DenominationPublicKey *denom_pub,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendSignatureP *coin_sig,
  TALER_EXCHANGE_DepositResultCallback cb,
  void *cb_cls,
  enum TALER_ErrorCode *ec)
{
  const struct TALER_EXCHANGE_Keys *key_state;
  const struct TALER_EXCHANGE_DenomPublicKey *dki;
  struct TALER_EXCHANGE_DepositHandle *dh;
  struct GNUNET_CURL_Context *ctx;
  json_t *deposit_obj;
  CURL *eh;
  struct TALER_MerchantWireHash h_wire;
  struct TALER_DenominationHash denom_pub_hash;
  struct TALER_Amount amount_without_fee;
  struct TALER_ExtensionContractHash ech;
  char arg_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2 + 32];

  if (NULL != extension_details)
    TALER_deposit_extension_hash (extension_details,
                                  &ech);
  {
    char pub_str[sizeof (struct TALER_CoinSpendPublicKeyP) * 2];
    char *end;

    end = GNUNET_STRINGS_data_to_string (
      coin_pub,
      sizeof (struct TALER_CoinSpendPublicKeyP),
      pub_str,
      sizeof (pub_str));
    *end = '\0';
    GNUNET_snprintf (arg_str,
                     sizeof (arg_str),
                     "/coins/%s/deposit",
                     pub_str);
  }
  if (GNUNET_TIME_timestamp_cmp (refund_deadline,
                                 >,
                                 wire_deadline))
  {
    GNUNET_break_op (0);
    *ec = TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE;
    return NULL;
  }
  GNUNET_assert (GNUNET_YES ==
                 TEAH_handle_is_ready (exchange));
  /* initialize h_wire */
  TALER_merchant_wire_signature_hash (merchant_payto_uri,
                                      wire_salt,
                                      &h_wire);
  key_state = TALER_EXCHANGE_get_keys (exchange);
  dki = TALER_EXCHANGE_get_denomination_key (key_state,
                                             denom_pub);
  if (NULL == dki)
  {
    *ec = TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN;
    GNUNET_break_op (0);
    return NULL;
  }
  if (0 >
      TALER_amount_subtract (&amount_without_fee,
                             amount,
                             &dki->fee_deposit))
  {
    *ec = TALER_EC_EXCHANGE_DEPOSIT_FEE_ABOVE_AMOUNT;
    GNUNET_break_op (0);
    return NULL;
  }
  TALER_denom_pub_hash (denom_pub,
                        &denom_pub_hash);
  if (GNUNET_OK !=
      verify_signatures (dki,
                         amount,
                         &h_wire,
                         h_contract_terms,
                         (NULL != extension_details)
                         ? &ech
                         : NULL,
                         coin_pub,
                         denom_sig,
                         denom_pub,
                         &denom_pub_hash,
                         timestamp,
                         merchant_pub,
                         refund_deadline,
                         coin_sig))
  {
    *ec = TALER_EC_EXCHANGE_DEPOSIT_COIN_SIGNATURE_INVALID;
    GNUNET_break_op (0);
    return NULL;
  }

  deposit_obj = GNUNET_JSON_PACK (
    TALER_JSON_pack_amount ("contribution",
                            amount),
    GNUNET_JSON_pack_string ("merchant_payto_uri",
                             merchant_payto_uri),
    GNUNET_JSON_pack_data_auto ("wire_salt",
                                wire_salt),
    GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                h_contract_terms),
    GNUNET_JSON_pack_data_auto ("denom_pub_hash",
                                &denom_pub_hash),
    TALER_JSON_pack_denom_sig ("ub_sig",
                               denom_sig),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                timestamp),
    GNUNET_JSON_pack_data_auto ("merchant_pub",
                                merchant_pub),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_timestamp ("refund_deadline",
                                  refund_deadline)),
    GNUNET_JSON_pack_timestamp ("wire_transfer_deadline",
                                wire_deadline),
    GNUNET_JSON_pack_data_auto ("coin_sig",
                                coin_sig));
  dh = GNUNET_new (struct TALER_EXCHANGE_DepositHandle);
  dh->auditor_chance = AUDITOR_CHANCE;
  dh->exchange = exchange;
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  dh->url = TEAH_path_to_url (exchange,
                              arg_str);
  if (NULL == dh->url)
  {
    GNUNET_break (0);
    *ec = TALER_EC_GENERIC_ALLOCATION_FAILURE;
    GNUNET_free (dh);
    json_decref (deposit_obj);
    return NULL;
  }
  dh->h_contract_terms = *h_contract_terms;
  dh->h_wire = h_wire;
  /* dh->h_extensions = ... */
  dh->refund_deadline = refund_deadline;
  dh->wire_deadline = wire_deadline;
  dh->amount_without_fee = amount_without_fee;
  dh->coin_pub = *coin_pub;
  dh->merchant_pub = *merchant_pub;
  dh->amount_with_fee = *amount;
  dh->dki = *dki;
  memset (&dh->dki.key,
          0,
          sizeof (dh->dki.key)); /* lifetime not warranted, so better
                                    not copy the contents! */

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
TALER_EXCHANGE_deposit_force_dc (struct TALER_EXCHANGE_DepositHandle *deposit)
{
  deposit->auditor_chance = 1;
}


void
TALER_EXCHANGE_deposit_cancel (struct TALER_EXCHANGE_DepositHandle *deposit)
{
  if (NULL != deposit->job)
  {
    GNUNET_CURL_job_cancel (deposit->job);
    deposit->job = NULL;
  }
  GNUNET_free (deposit->url);
  TALER_curl_easy_post_finished (&deposit->ctx);
  GNUNET_free (deposit);
}


/* end of exchange_api_deposit.c */
