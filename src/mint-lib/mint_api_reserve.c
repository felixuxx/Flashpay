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
 * @file mint-lib/mint_api_reserve.c
 * @brief Implementation of the /reserve requests of the mint's HTTP API
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


/* ********************** /reserve/status ********************** */

/**
 * @brief A Withdraw Status Handle
 */
struct TALER_MINT_ReserveStatusHandle
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
   * Handle for the request.
   */
  struct MAC_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_MINT_ReserveStatusResultCallback cb;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

};


/**
 * Parse history given in JSON format and return it in binary
 * format.
 *
 * @param[in] history JSON array with the history
 * @param reserve_pub public key of the reserve to inspect
 * @param currency currency we expect the balance to be in
 * @param[out] balance final balance
 * @param history_length number of entries in @a history
 * @param[out] rhistory array of length @a history_length, set to the
 *             parsed history entries
 * @return #GNUNET_OK if history was valid and @a rhistory and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a history
 */
static int
parse_reserve_history (json_t *history,
                       const struct TALER_ReservePublicKeyP *reserve_pub,
                       const char *currency,
                       struct TALER_Amount *balance,
                       unsigned int history_length,
                       struct TALER_MINT_ReserveHistory *rhistory)
{
  struct GNUNET_HashCode uuid[history_length];
  unsigned int uuid_off;
  struct TALER_Amount total_in;
  struct TALER_Amount total_out;
  size_t off;

  TALER_amount_get_zero (currency,
                         &total_in);
  TALER_amount_get_zero (currency,
                         &total_out);
  uuid_off = 0;
  for (off=0;off<history_length;off++)
  {
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct MAJ_Specification hist_spec[] = {
      MAJ_spec_string ("type", &type),
      MAJ_spec_amount ("amount",
                       &amount),
      /* 'wire' and 'signature' are optional depending on 'type'! */
      MAJ_spec_end
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        MAJ_parse_json (transaction,
                        hist_spec))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    rhistory[off].amount = amount;

    if (0 == strcasecmp (type,
                         "DEPOSIT"))
    {
      json_t *wire;

      rhistory[off].type = TALER_MINT_RTT_DEPOSIT;
      if (GNUNET_OK !=
          TALER_amount_add (&total_in,
                            &total_in,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad mint! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      wire = json_object_get (transaction,
                              "wire");
      /* check 'wire' is a JSON object (no need to check wireformat,
         but we do at least expect "some" JSON object here) */
      if ( (NULL == wire) ||
           (! json_is_object (wire)) )
      {
        /* not even a JSON 'wire' specification, not acceptable */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.wire_in_details = wire;
      /* end type==DEPOSIT */
    }
    else if (0 == strcasecmp (type,
                              "WITHDRAW"))
    {
      struct TALER_ReserveSignatureP sig;
      struct TALER_WithdrawRequestPS withdraw_purpose;
      struct TALER_Amount amount_from_purpose;
      struct MAJ_Specification withdraw_spec[] = {
        MAJ_spec_fixed_auto ("signature",
                             &sig),
        MAJ_spec_fixed_auto ("details",
                             &withdraw_purpose),
        MAJ_spec_end
      };
      unsigned int i;

      rhistory[off].type = TALER_MINT_RTT_WITHDRAWAL;
      if (GNUNET_OK !=
          MAJ_parse_json (transaction,
                          withdraw_spec))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* Check that the signature is a valid withdraw request */
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                      &withdraw_purpose.purpose,
                                      &sig.eddsa_signature,
                                      &reserve_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        MAJ_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      TALER_amount_ntoh (&amount_from_purpose,
                         &withdraw_purpose.amount_with_fee);
      if (0 != TALER_amount_cmp (&amount,
                                 &amount_from_purpose))
      {
        GNUNET_break_op (0);
        MAJ_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.out_authorization_sig = json_object_get (transaction,
                                                                     "signature");
      /* Check check that the same withdraw transaction
         isn't listed twice by the mint. We use the
         "uuid" array to remember the hashes of all
         purposes, and compare the hashes to find
         duplicates. */
      GNUNET_CRYPTO_hash (&withdraw_purpose,
                          ntohl (withdraw_purpose.purpose.size),
                          &uuid[uuid_off]);
      for (i=0;i<uuid_off;i++)
      {
        if (0 == memcmp (&uuid[uuid_off],
                         &uuid[i],
                         sizeof (struct GNUNET_HashCode)))
        {
          GNUNET_break_op (0);
          MAJ_parse_free (withdraw_spec);
          return GNUNET_SYSERR;
        }
      }
      uuid_off++;

      if (GNUNET_OK !=
          TALER_amount_add (&total_out,
                            &total_out,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad mint! */
        GNUNET_break_op (0);
        MAJ_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      /* end type==WITHDRAW */
    }
    else
    {
      /* unexpected 'type', protocol incompatibility, complain! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }

  /* check balance = total_in - total_out < withdraw-amount */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (balance,
                             &total_in,
                             &total_out))
  {
    /* total_in < total_out, why did the mint ever allow this!? */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserve/status request.
 *
 * @param cls the `struct TALER_MINT_ReserveStatusHandle`
 * @param eh curl handle of the request that finished
 */
static void
handle_reserve_status_finished (void *cls,
                                CURL *eh)
{
  struct TALER_MINT_ReserveStatusHandle *wsh = cls;
  long response_code;
  json_t *json;

  wsh->job = NULL;
  json = MAC_download_get_result (&wsh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      /* TODO: move into separate function... */
      json_t *history;
      unsigned int len;
      struct TALER_Amount balance;
      struct TALER_Amount balance_from_history;
      struct MAJ_Specification spec[] = {
        MAJ_spec_amount ("balance", &balance),
        MAJ_spec_end
      };

      if (GNUNET_OK !=
          MAJ_parse_json (json,
                          spec))
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      history = json_object_get (json,
                                 "history");
      if (NULL == history)
      {
        GNUNET_break_op (0);
        response_code = 0;
        break;
      }
      len = json_array_size (history);
      {
        struct TALER_MINT_ReserveHistory rhistory[len];

        if (GNUNET_OK !=
            parse_reserve_history (history,
                                   &wsh->reserve_pub,
                                   balance.currency,
                                   &balance_from_history,
                                   len,
                                   rhistory))
        {
          GNUNET_break_op (0);
          response_code = 0;
          break;
        }
        if (0 !=
            TALER_amount_cmp (&balance_from_history,
                              &balance))
        {
          /* mint cannot add up balances!? */
          GNUNET_break_op (0);
          response_code = 0;
          break;
        }
        wsh->cb (wsh->cb_cls,
                 response_code,
                 json,
                 &balance,
                 len,
                 rhistory);
        wsh->cb = NULL;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
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
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != wsh->cb)
    wsh->cb (wsh->cb_cls,
             response_code,
             json,
             NULL,
             0, NULL);
  json_decref (json);
  TALER_MINT_reserve_status_cancel (wsh);
}


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the mint.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the mint's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param reserve_pub public key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_MINT_ReserveStatusHandle *
TALER_MINT_reserve_status (struct TALER_MINT_Handle *mint,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           TALER_MINT_ReserveStatusResultCallback cb,
                           void *cb_cls)
{
  struct TALER_MINT_ReserveStatusHandle *wsh;
  struct TALER_MINT_Context *ctx;
  CURL *eh;
  char *pub_str;
  char *arg_str;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
  {
    GNUNET_break (0);
    return NULL;
  }
  pub_str = GNUNET_STRINGS_data_to_string_alloc (reserve_pub,
                                                 sizeof (struct TALER_ReservePublicKeyP));
  GNUNET_asprintf (&arg_str,
                   "/reserve/status?reserve_pub=%s",
                   pub_str);
  GNUNET_free (pub_str);
  wsh = GNUNET_new (struct TALER_MINT_ReserveStatusHandle);
  wsh->mint = mint;
  wsh->cb = cb;
  wsh->cb_cls = cb_cls;
  wsh->reserve_pub = *reserve_pub;
  wsh->url = MAH_path_to_url (mint,
                              arg_str);
  GNUNET_free (arg_str);

  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wsh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &wsh->db));
  ctx = MAH_handle_to_context (mint);
  wsh->job = MAC_job_add (ctx,
                          eh,
                          GNUNET_NO,
                          &handle_reserve_status_finished,
                          wsh);
  return wsh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wsh the withdraw status request handle
 */
void
TALER_MINT_reserve_status_cancel (struct TALER_MINT_ReserveStatusHandle *wsh)
{
  if (NULL != wsh->job)
  {
    MAC_job_cancel (wsh->job);
    wsh->job = NULL;
  }
  GNUNET_free_non_null (wsh->db.buf);
  GNUNET_free (wsh->url);
  GNUNET_free (wsh);
}


/* ********************** /reserve/withdraw ********************** */

/**
 * @brief A Withdraw Sign Handle
 */
struct TALER_MINT_ReserveWithdrawHandle
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
   * Function to call with the result.
   */
  TALER_MINT_ReserveWithdrawResultCallback cb;

  /**
   * Key used to blind the value.
   */
  const struct TALER_DenominationBlindingKey *blinding_key;

  /**
   * Denomination key we are withdrawing.
   */
  const struct TALER_MINT_DenomPublicKey *pk;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct GNUNET_HashCode c_hash;

  /**
   * Public key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

};


/**
 * We got a 200 OK response for the /reserve/withdraw operation.
 * Extract the coin's signature and return it to the caller.
 * The signature we get from the mint is for the blinded value.
 * Thus, we first must unblind it and then should verify its
 * validity against our coin's hash.
 *
 * If everything checks out, we return the unblinded signature
 * to the application via the callback.
 *
 * @param wsh operation handle
 * @param json reply from the mint
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
reserve_withdraw_ok (struct TALER_MINT_ReserveWithdrawHandle *wsh,
                  json_t *json)
{
  struct GNUNET_CRYPTO_rsa_Signature *blind_sig;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct TALER_DenominationSignature dsig;
  struct MAJ_Specification spec[] = {
    MAJ_spec_rsa_signature ("ev_sig", &blind_sig),
    MAJ_spec_end
  };

  if (GNUNET_OK !=
      MAJ_parse_json (json,
                      spec))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  sig = GNUNET_CRYPTO_rsa_unblind (blind_sig,
                                   wsh->blinding_key->rsa_blinding_key,
                                   wsh->pk->key.rsa_public_key);
  GNUNET_CRYPTO_rsa_signature_free (blind_sig);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_rsa_verify (&wsh->c_hash,
                                sig,
                                wsh->pk->key.rsa_public_key))
  {
    GNUNET_break_op (0);
    GNUNET_CRYPTO_rsa_signature_free (sig);
    return GNUNET_SYSERR;
  }
  /* signature is valid, return it to the application */
  dsig.rsa_signature = sig;
  wsh->cb (wsh->cb_cls,
           MHD_HTTP_OK,
           &dsig,
           json);
  /* make sure callback isn't called again after return */
  wsh->cb = NULL;
  GNUNET_CRYPTO_rsa_signature_free (sig);
  return GNUNET_OK;
}


/**
 * We got a 402 PAYMENT REQUIRED response for the /reserve/withdraw operation.
 * Check the signatures on the withdraw transactions in the provided
 * history and that the balances add up.  We don't do anything directly
 * with the information, as the JSON will be returned to the application.
 * However, our job is ensuring that the mint followed the protocol, and
 * this in particular means checking all of the signatures in the history.
 *
 * @param wsh operation handle
 * @param json reply from the mint
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
reserve_withdraw_payment_required (struct TALER_MINT_ReserveWithdrawHandle *wsh,
                                   json_t *json)
{
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
  struct TALER_Amount requested_amount;
  json_t *history;
  size_t len;
  struct MAJ_Specification spec[] = {
    MAJ_spec_amount ("balance", &balance),
    MAJ_spec_end
  };

  if (GNUNET_OK !=
      MAJ_parse_json (json,
                      spec))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  history = json_object_get (json,
                             "history");
  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* go over transaction history and compute
     total incoming and outgoing amounts */
  len = json_array_size (history);
  {
    struct TALER_MINT_ReserveHistory rhistory[len];

    if (GNUNET_OK !=
        parse_reserve_history (history,
                               &wsh->reserve_pub,
                               balance.currency,
                               &balance_from_history,
                               len,
                               rhistory))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }

  if (0 !=
      TALER_amount_cmp (&balance_from_history,
                        &balance))
  {
    /* mint cannot add up balances!? */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  /* Compute how much we expected to charge to the reserve */
  if (GNUNET_OK !=
      TALER_amount_add (&requested_amount,
                        &wsh->pk->value,
                        &wsh->pk->fee_withdraw))
  {
    /* Overflow here? Very strange, our CPU must be fried... */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* Check that funds were really insufficient */
  if (0 >= TALER_amount_cmp (&requested_amount,
                             &balance))
  {
    /* Requested amount is smaller or equal to reported balance,
       so this should not have failed. */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserve/withdraw request.
 *
 * @param cls the `struct TALER_MINT_ReserveWithdrawHandle`
 * @param eh curl handle of the request that finished
 */
static void
handle_reserve_withdraw_finished (void *cls,
                                  CURL *eh)
{
  struct TALER_MINT_ReserveWithdrawHandle *wsh = cls;
  long response_code;
  json_t *json;

  wsh->job = NULL;
  json = MAC_download_get_result (&wsh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_withdraw_ok (wsh,
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
  case MHD_HTTP_PAYMENT_REQUIRED:
    /* The mint says that the reserve has insufficient funds;
       check the signatures in the history... */
    if (GNUNET_OK !=
        reserve_withdraw_payment_required (wsh,
                                        json))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_UNAUTHORIZED:
    GNUNET_break (0);
    /* Nothing really to verify, mint says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the mint basically just says
       that it doesn't know this reserve.  Can happen if we
       query before the wire transfer went through.
       We should simply pass the JSON reply to the application. */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != wsh->cb)
    wsh->cb (wsh->cb_cls,
             response_code,
             NULL,
             json);
  json_decref (json);
  TALER_MINT_reserve_withdraw_cancel (wsh);
}


/**
 * Withdraw a coin from the mint using a /reserve/withdraw request.  Note
 * that to ensure that no money is lost in case of hardware failures,
 * the caller must have committed (most of) the arguments to disk
 * before calling, and be ready to repeat the request with the same
 * arguments in case of failures.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param coin_priv where to store the coin's private key,
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param blinding_key where to store the coin's blinding key
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return #GNUNET_OK on success, #GNUNET_SYSERR
 *         if the inputs are invalid (i.e. denomination key not with this mint).
 *         In this case, the callback is not called.
 */
struct TALER_MINT_ReserveWithdrawHandle *
TALER_MINT_reserve_withdraw (struct TALER_MINT_Handle *mint,
                             const struct TALER_MINT_DenomPublicKey *pk,
                             const struct TALER_ReservePrivateKeyP *reserve_priv,
                             const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                             const struct TALER_DenominationBlindingKey *blinding_key,
                             TALER_MINT_ReserveWithdrawResultCallback res_cb,
                             void *res_cb_cls)
{
  struct TALER_MINT_ReserveWithdrawHandle *wsh;
  struct TALER_WithdrawRequestPS req;
  struct TALER_ReserveSignatureP reserve_sig;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_MINT_Context *ctx;
  struct TALER_Amount amount_with_fee;
  char *coin_ev;
  size_t coin_ev_size;
  json_t *withdraw_obj;
  CURL *eh;

  wsh = GNUNET_new (struct TALER_MINT_ReserveWithdrawHandle);
  wsh->mint = mint;
  wsh->cb = res_cb;
  wsh->cb_cls = res_cb_cls;
  wsh->pk = pk;

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &wsh->c_hash);
  coin_ev_size = GNUNET_CRYPTO_rsa_blind (&wsh->c_hash,
                                          blinding_key->rsa_blinding_key,
                                          pk->key.rsa_public_key,
                                          &coin_ev);
  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &wsh->reserve_pub.eddsa_pub);
  req.purpose.size = htonl (sizeof (struct TALER_WithdrawRequestPS));
  req.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  req.reserve_pub = wsh->reserve_pub;
  if (GNUNET_OK !=
      TALER_amount_add (&amount_with_fee,
                        &pk->fee_withdraw,
                        &pk->value))
  {
    /* mint gave us denomination keys that overflow like this!? */
    GNUNET_break_op (0);
    GNUNET_free (coin_ev);
    GNUNET_free (wsh);
    return NULL;
  }
  TALER_amount_hton (&req.amount_with_fee,
                     &amount_with_fee);
  TALER_amount_hton (&req.withdraw_fee,
                     &pk->fee_withdraw);
  GNUNET_CRYPTO_rsa_public_key_hash (pk->key.rsa_public_key,
                                     &req.h_denomination_pub);
  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &req.h_coin_envelope);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                                           &req.purpose,
                                           &reserve_sig.eddsa_signature));
  withdraw_obj = json_pack ("{s:o, s:o," /* denom_pub and coin_ev */
                            " s:o, s:o}",/* reserve_pub and reserve_sig */
                            "denom_pub", TALER_json_from_rsa_public_key (pk->key.rsa_public_key),
                            "coin_ev", TALER_json_from_data (coin_ev,
                                                             coin_ev_size),
                            "reserve_pub", TALER_json_from_data (&wsh->reserve_pub,
                                                                 sizeof (struct TALER_ReservePublicKeyP)),
                            "reserve_sig", TALER_json_from_data (&reserve_sig,
                                                                 sizeof (reserve_sig)));
  GNUNET_free (coin_ev);

  wsh->blinding_key = blinding_key;
  wsh->url = MAH_path_to_url (mint, "/reserve/withdraw");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (wsh->json_enc =
                          json_dumps (withdraw_obj,
                                      JSON_COMPACT)));
  json_decref (withdraw_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   wsh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   wsh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (wsh->json_enc)));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &wsh->db));
  ctx = MAH_handle_to_context (mint);
  wsh->job = MAC_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_reserve_withdraw_finished,
                          wsh);
  return wsh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param sign the withdraw sign request handle
 */
void
TALER_MINT_reserve_withdraw_cancel (struct TALER_MINT_ReserveWithdrawHandle *sign)
{
  if (NULL != sign->job)
  {
    MAC_job_cancel (sign->job);
    sign->job = NULL;
  }
  GNUNET_free_non_null (sign->db.buf);
  GNUNET_free (sign->url);
  GNUNET_free (sign->json_enc);
  GNUNET_free (sign);
}


/* end of mint_api_reserve.c */
