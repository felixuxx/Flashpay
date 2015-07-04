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
 * @file mint-lib/mint_api_deposit.c
 * @brief Implementation of the /deposit request of the mint's HTTP API
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "mint_api_json.h"
#include "mint_api_context.h"
#include "mint_api_handle.h"
#include "taler_signatures.h"


/**
 * Print JSON parsing related error information
 */
#define JSON_WARN(error)                                                \
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,                              \
                "JSON parsing failed at %s:%u: %s (%s)",                \
                __FILE__, __LINE__, error.text, error.source)


/**
 * @brief A Deposit Handle
 */
struct TALER_MINT_DepositHandle
{

  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct MAC_Job *job;

  /**
   * HTTP headers for the request.
   */
  struct curl_slist *headers;

  /**
   * Function to call with the result.
   */
  TALER_MINT_DepositResultCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  void *buf;

  /**
   * Information the mint should sign in response.
   */
  struct TALER_DepositConfirmationPS depconf;

  /**
   * Value of the /deposit transaction, including fee.
   */
  struct TALER_Amount amount_with_fee;

  /**
   * Total value of the coin being transacted with.
   */
  struct TALER_Amount coin_value;

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
 * Verify that the signature on the "200 OK" response
 * from the mint is valid.
 *
 * @param dh deposit handle
 * @param json json reply with the signature
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_deposit_signature_ok (const struct TALER_MINT_DepositHandle *dh,
                             json_t *json)
{
  struct TALER_MintSignatureP mint_sig;
  const struct TALER_MINT_Keys *key_state;
  const struct TALER_MintPublicKeyP *mint_pub;
  struct MAJ_Specification spec[] = {
    MAJ_spec_fixed_auto ("sig", &mint_sig),
    MAJ_spec_end
  };

  if (GNUNET_OK !=
      MAJ_parse_json (json,
                      spec))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  key_state = TALER_MINT_get_keys (dh->mint);
  mint_pub = TALER_MINT_get_signing_key (key_state);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MINT_CONFIRM_DEPOSIT,
                                  &dh->depconf.purpose,
                                  &mint_sig.eddsa_signature,
                                  &mint_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify that the signatures on the "403 FORBIDDEN" response from the
 * mint demonstrating customer double-spending are valid.
 *
 * @param dh deposit handle
 * @param json json reply with the signature(s) and transaction history
 * @return #GNUNET_OK if the signature(s) is valid, #GNUNET_SYSERR if not
 */
static int
verify_deposit_signature_forbidden (const struct TALER_MINT_DepositHandle *dh,
                                    json_t *json)
{
  json_t *history;
  size_t len;
  size_t off;
  struct TALER_Amount total;

  history = json_object_get (json,
                             "history");
  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  if (0 == len)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  TALER_amount_get_zero (dh->coin_value.currency,
                         &total);
  for (off=0;off<len;off++)
  {
    json_t *transaction;
    struct TALER_Amount amount;
    struct GNUNET_CRYPTO_EccSignaturePurpose *purpose;
    struct MAJ_Specification spec[] = {
      MAJ_spec_amount ("amount",
                       &amount),
      MAJ_spec_eddsa_signed_purpose ("signature",
                                     &purpose,
                                     &dh->depconf.coin_pub.eddsa_pub),
      MAJ_spec_end
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        MAJ_parse_json (transaction,
                        spec))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    switch (ntohl (purpose->purpose))
    {
    case TALER_SIGNATURE_WALLET_COIN_DEPOSIT:
      {
        const struct TALER_DepositRequestPS *dr;
        struct TALER_Amount dr_amount;

        if (ntohl (purpose->size) != sizeof (struct TALER_DepositRequestPS))
        {
          GNUNET_break (0);
          MAJ_parse_free (spec);
          return GNUNET_SYSERR;
        }
        dr = (const struct TALER_DepositRequestPS *) purpose;
        TALER_amount_ntoh (&dr_amount,
                           &dr->amount_with_fee);
        if (0 != TALER_amount_cmp (&dr_amount,
                                   &amount))
        {
          GNUNET_break (0);
          MAJ_parse_free (spec);
          return GNUNET_SYSERR;
        }
      }
      break;
    case TALER_SIGNATURE_WALLET_COIN_MELT:
      {
        const struct TALER_RefreshMeltCoinAffirmationPS *rm;
        struct TALER_Amount rm_amount;

        if (ntohl (purpose->size) != sizeof (struct TALER_RefreshMeltCoinAffirmationPS))
        {
          GNUNET_break (0);
          MAJ_parse_free (spec);
          return GNUNET_SYSERR;
        }
        rm = (const struct TALER_RefreshMeltCoinAffirmationPS *) purpose;
        TALER_amount_ntoh (&rm_amount,
                           &rm->amount_with_fee);
        if (0 != TALER_amount_cmp (&rm_amount,
                                   &amount))
        {
          GNUNET_break (0);
          MAJ_parse_free (spec);
          return GNUNET_SYSERR;
        }
      }
      break;
    default:
      /* signature not supported, new version on server? */
      GNUNET_break (0);
      MAJ_parse_free (spec);
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        TALER_amount_add (&total,
                          &total,
                          &amount))
    {
      /* overflow in history already!? inconceivable! Bad mint! */
      GNUNET_break_op (0);
      MAJ_parse_free (spec);
      return GNUNET_SYSERR;
    }
    MAJ_parse_free (spec);
  }
  if (GNUNET_OK !=
      TALER_amount_add (&total,
                        &total,
                        &dh->amount_with_fee))
  {
    /* clearly not OK if our transaction would have caused
       the overflow... */
    return GNUNET_OK;
  }

  if (0 >= TALER_amount_cmp (&total,
                             &dh->coin_value))
  {
    /* transaction should have still fit */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* everything OK, proof of double-spending was provided */
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /deposit request.
 *
 * @param cls the `struct TALER_MINT_DepositHandle`
 */
static void
handle_deposit_finished (void *cls,
                         CURL *eh)
{
  struct TALER_MINT_DepositHandle *dh = cls;
  long response_code;
  json_error_t error;
  json_t *json;

  dh->job = NULL;
  json = NULL;
  if (0 == dh->eno)
  {
    json = json_loadb (dh->buf,
                       dh->buf_size,
                       JSON_REJECT_DUPLICATES | JSON_DISABLE_EOF_CHECK,
                       &error);
    if (NULL == json)
    {
      JSON_WARN (error);
      response_code = 0;
    }
  }
  if (NULL != json)
  {
    if (CURLE_OK !=
        curl_easy_getinfo (eh,
                           CURLINFO_RESPONSE_CODE,
                           &response_code))
    {
      /* unexpected error... */
      GNUNET_break (0);
      response_code = 0;
    }
  }
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_deposit_signature_ok (dh,
                                     json))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Double spending; check signatures on transaction history */
    if (GNUNET_OK !=
        verify_deposit_signature_forbidden (dh,
                                            json))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, mint says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  dh->cb (dh->cb_cls,
          response_code,
          json);
  json_decref (json);
  TALER_MINT_deposit_cancel (dh);
}


/**
 * Verify signature information about the deposit.
 *
 * @param dki public key information
 * @param amount the amount to be deposited
 * @param h_wire hash of the merchant’s account details
 * @param h_contract hash of the contact of the merchant with the customer (further details are never disclosed to the mint)
 * @param coin_pub coin’s public key
 * @param denom_pub denomination key with which the coin is signed
 * @param denom_sig mint’s unblinded signature of the coin
 * @param timestamp timestamp when the contract was finalized, must match approximately the current time of the mint
 * @param transaction_id transaction id for the transaction between merchant and customer
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the mint (can be zero if refunds are not allowed)
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made by the customer with the coin’s private key.
 * @return #GNUNET_OK if signatures are OK, #GNUNET_SYSERR if not
 */
static int
verify_signatures (const struct TALER_MINT_DenomPublicKey *dki,
                   const struct TALER_Amount *amount,
                   const struct GNUNET_HashCode *h_wire,
                   const struct GNUNET_HashCode *h_contract,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   const struct TALER_DenominationSignature *denom_sig,
                   const struct TALER_DenominationPublicKey *denom_pub,
                   struct GNUNET_TIME_Absolute timestamp,
                   uint64_t transaction_id,
                   const struct TALER_MerchantPublicKeyP *merchant_pub,
                   struct GNUNET_TIME_Absolute refund_deadline,
                   const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_DepositRequestPS dr;
  struct TALER_CoinPublicInfo coin_info;

  dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
  dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
  dr.h_contract = *h_contract;
  dr.h_wire = *h_wire;
  dr.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  dr.transaction_id = GNUNET_htonll (transaction_id);
  TALER_amount_hton (&dr.amount_with_fee,
                     amount);
  TALER_amount_hton (&dr.deposit_fee,
                     &dki->fee_deposit);
  dr.merchant = *merchant_pub;
  dr.coin_pub = *coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid coin signature on /deposit request\n");
    return GNUNET_SYSERR;
  }

  /* check coin signature */
  coin_info.coin_pub = *coin_pub;
  coin_info.denom_pub = *denom_pub;
  coin_info.denom_sig = *denom_sig;
  if (GNUNET_YES !=
      TALER_test_coin_valid (&coin_info))
  {
    TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
    return GNUNET_SYSERR;
  }
  if (TALER_amount_cmp (&dki->fee_deposit,
                        amount) < 0)
  {
    TALER_LOG_WARNING ("Deposit amount smaller than fee\n");
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Callback used when downloading the reply to a /deposit request.
 * Just appends all of the data to the `buf` in the
 * `struct TALER_MINT_DepositHandle` for further processing. The size of
 * the download is limited to #GNUNET_MAX_MALLOC_CHECKED, if
 * the download exceeds this size, we abort with an error.
 *
 * @param bufptr data downloaded via HTTP
 * @param size size of an item in @a bufptr
 * @param nitems number of items in @a bufptr
 * @param cls the `struct TALER_MINT_DepositHandle`
 * @return number of bytes processed from @a bufptr
 */
static int
deposit_download_cb (char *bufptr,
                     size_t size,
                     size_t nitems,
                     void *cls)
{
  struct TALER_MINT_DepositHandle *dh = cls;
  size_t msize;
  void *buf;

  if (0 == size * nitems)
  {
    /* Nothing (left) to do */
    return 0;
  }
  msize = size * nitems;
  if ( (msize + dh->buf_size) >= GNUNET_MAX_MALLOC_CHECKED)
  {
    dh->eno = ENOMEM;
    return 0; /* signals an error to curl */
  }
  dh->buf = GNUNET_realloc (dh->buf,
                            dh->buf_size + msize);
  buf = dh->buf + dh->buf_size;
  memcpy (buf, bufptr, msize);
  dh->buf_size += msize;
  return msize;
}


/**
 * Submit a deposit permission to the mint and get the mint's response.
 * Note that while we return the response verbatim to the caller for
 * further processing, we do already verify that the response is
 * well-formed (i.e. that signatures included in the response are all
 * valid).  If the mint's reply is not well-formed, we return an
 * HTTP status code of zero to @a cb.
 *
 * We also verify that the @a coin_sig is valid for this deposit
 * request, and that the @a ub_sig is a valid signature for @a
 * coin_pub.  Also, the @a mint must be ready to operate (i.e.  have
 * finished processing the /keys reply).  If either check fails, we do
 * NOT initiate the transaction with the mint and instead return NULL.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param amount the amount to be deposited
 * @param wire the merchant’s account details, in a format supported by the mint
 * @param h_contract hash of the contact of the merchant with the customer (further details are never disclosed to the mint)
 * @param coin_pub coin’s public key
 * @param denom_pub denomination key with which the coin is signed
 * @param denom_sig mint’s unblinded signature of the coin
 * @param timestamp timestamp when the contract was finalized, must match approximately the current time of the mint
 * @param transaction_id transaction id for the transaction between merchant and customer
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the mint (can be zero if refunds are not allowed)
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT made by the customer with the coin’s private key.
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_MINT_DepositHandle *
TALER_MINT_deposit (struct TALER_MINT_Handle *mint,
                    const struct TALER_Amount *amount,
                    json_t *wire_details,
                    const struct GNUNET_HashCode *h_contract,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const struct TALER_DenominationSignature *denom_sig,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    struct GNUNET_TIME_Absolute timestamp,
                    uint64_t transaction_id,
                    const struct TALER_MerchantPublicKeyP *merchant_pub,
                    struct GNUNET_TIME_Absolute refund_deadline,
                    const struct TALER_CoinSpendSignatureP *coin_sig,
                    TALER_MINT_DepositResultCallback cb,
                    void *cb_cls)
{
  const struct TALER_MINT_Keys *key_state;
  const struct TALER_MINT_DenomPublicKey *dki;
  struct TALER_MINT_DepositHandle *dh;
  struct TALER_MINT_Context *ctx;
  json_t *deposit_obj;
  CURL *eh;
  struct GNUNET_HashCode h_wire;
  struct TALER_Amount amount_without_fee;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  /* initialize h_wire */
  if (GNUNET_OK !=
      TALER_hash_json (wire_details,
                       &h_wire))
  {
    GNUNET_break (0);
    return NULL;
  }
  key_state = TALER_MINT_get_keys (mint);
  dki = TALER_MINT_get_denomination_key (key_state,
                                         denom_pub);
  if (NULL == dki)
  {
    TALER_LOG_WARNING ("Denomination key unknown to mint\n");
    return NULL;
  }

  if (GNUNET_OK !=
      verify_signatures (dki,
                         amount,
                         &h_wire,
                         h_contract,
                         coin_pub,
                         denom_sig,
                         denom_pub,
                         timestamp,
                         transaction_id,
                         merchant_pub,
                         refund_deadline,
                         coin_sig))
  {
    GNUNET_break_op (0);
    return NULL;
  }

  deposit_obj = json_pack ("{s:o, s:o," /* f/wire */
                           " s:s, s:s," /* H_wire, H_contract */
                           " s:s, s:s," /* coin_pub, denom_pub */
                           " s:s, s:s," /* ub_sig, timestamp */
                           " s:I, s:s," /* transaction id, merchant_pub */
                           " s:s, s:s}", /* refund_deadline, coin_sig */
                           "f", TALER_json_from_amount (amount),
                           "wire", wire_details,
                           "H_wire", TALER_json_from_data (&h_wire,
                                                           sizeof (h_wire)),
                           "H_contract", TALER_json_from_data (&h_contract,
                                                               sizeof (h_contract)),
                           "coin_pub", TALER_json_from_data (coin_pub,
                                                             sizeof (*coin_pub)),
                           "denom_pub", TALER_json_from_rsa_public_key (denom_pub->rsa_public_key),
                           "ub_sig", TALER_json_from_rsa_signature (denom_sig->rsa_signature),
                           "timestamp", TALER_json_from_abs (timestamp),
                           "transaction_id", (json_int_t) transaction_id,
                           "merchant_pub", TALER_json_from_data (merchant_pub,
                                                                 sizeof (*merchant_pub)),
                           "refund_deadline", TALER_json_from_abs (refund_deadline),
                           "coin_sig", TALER_json_from_data (coin_sig,
                                                             sizeof (*coin_sig))
                           );

  dh = GNUNET_new (struct TALER_MINT_DepositHandle);
  dh->mint = mint;
  dh->cb = cb;
  dh->cb_cls = cb_cls;
  dh->url = MAH_path_to_url (mint, "/deposit");
  dh->depconf.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS));
  dh->depconf.purpose.purpose = htonl (TALER_SIGNATURE_MINT_CONFIRM_DEPOSIT);
  dh->depconf.h_contract = *h_contract;
  dh->depconf.h_wire = h_wire;
  dh->depconf.transaction_id = GNUNET_htonll (transaction_id);
  dh->depconf.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dh->depconf.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_subtract (&amount_without_fee,
                         amount,
                         &dki->fee_deposit);
  TALER_amount_hton (&dh->depconf.amount_without_fee,
                     &amount_without_fee);
  dh->depconf.coin_pub = *coin_pub;
  dh->depconf.merchant = *merchant_pub;
  dh->amount_with_fee = *amount;
  dh->coin_value = dki->value;

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (dh->json_enc =
                          json_dumps (deposit_obj,
                                      JSON_COMPACT)));
  json_decref (deposit_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   dh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   dh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (dh->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &deposit_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   dh));
  GNUNET_assert (NULL != (dh->headers =
                          curl_slist_append (dh->headers,
                                             "Content-Type: application/json")));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_HTTPHEADER,
                                   dh->headers));
  ctx = MAH_handle_to_context (mint);
  dh->job = MAC_job_add (ctx,
                         eh,
                         &handle_deposit_finished,
                         dh);
  return dh;
}


/**
 * Cancel a deposit permission request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param deposit the deposit permission request handle
 */
void
TALER_MINT_deposit_cancel (struct TALER_MINT_DepositHandle *deposit)
{
  if (NULL != deposit->job)
  {
    MAC_job_cancel (deposit->job);
    deposit->job = NULL;
  }
  curl_slist_free_all (deposit->headers);
  GNUNET_free (deposit->url);
  GNUNET_free (deposit->json_enc);
  GNUNET_free (deposit);
}


/* end of mint_api_deposit.c */
