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
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/exchange_api_reserve.c
 * @brief Implementation of the /reserve requests of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


/* ********************** /reserve/status ********************** */

/**
 * @brief A Withdraw Status Handle
 */
struct TALER_EXCHANGE_ReserveStatusHandle
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
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ReserveStatusResultCallback cb;

  /**
   * Public key of the reserve we are querying.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

};


/**
 * Parse history given in JSON format and return it in binary
 * format.
 *
 * @param exchange connection to the exchange we can use
 * @param history JSON array with the history
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
parse_reserve_history (struct TALER_EXCHANGE_Handle *exchange,
                       const json_t *history,
                       const struct TALER_ReservePublicKeyP *reserve_pub,
                       const char *currency,
                       struct TALER_Amount *balance,
                       unsigned int history_length,
                       struct TALER_EXCHANGE_ReserveHistory *rhistory)
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
    struct GNUNET_JSON_Specification hist_spec[] = {
      GNUNET_JSON_spec_string ("type", &type),
      TALER_JSON_spec_amount ("amount",
                              &amount),
      /* 'wire' and 'signature' are optional depending on 'type'! */
      GNUNET_JSON_spec_end()
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           hist_spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    rhistory[off].amount = amount;

    if (0 == strcasecmp (type,
                         "DEPOSIT"))
    {
      json_t *wire_account;
      json_t *transfer;

      rhistory[off].type = TALER_EXCHANGE_RTT_DEPOSIT;
      if (GNUNET_OK !=
          TALER_amount_add (&total_in,
                            &total_in,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      wire_account = json_object_get (transaction,
                                      "sender_account_details");
      /* check 'wire_account' is a JSON object (no need to check wireformat,
         but we do at least expect "some" JSON object here) */
      if ( (NULL == wire_account) ||
           (! json_is_object (wire_account)) )
      {
        /* not even a JSON 'wire' specification, not acceptable */
        GNUNET_break_op (0);
        if (NULL != wire_account)
          json_decref (wire_account);
        return GNUNET_SYSERR;
      }
      transfer = json_object_get (transaction,
                                  "transfer_details");
      /* check 'transfer' is a JSON object */
      if ( (NULL == transfer) ||
           (! json_is_object (transfer)) )
      {
        GNUNET_break_op (0);
        json_decref (wire_account);
        if (NULL != transfer)
          json_decref (transfer);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.in_details.sender_account_details = wire_account;
      rhistory[off].details.in_details.transfer_details = transfer;
      /* end type==DEPOSIT */
    }
    else if (0 == strcasecmp (type,
                              "WITHDRAW"))
    {
      struct TALER_ReserveSignatureP sig;
      struct TALER_WithdrawRequestPS withdraw_purpose;
      struct TALER_Amount amount_from_purpose;
      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("signature",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("details",
                                     &withdraw_purpose),
        GNUNET_JSON_spec_end()
      };
      unsigned int i;

      rhistory[off].type = TALER_EXCHANGE_RTT_WITHDRAWAL;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             withdraw_spec,
                             NULL, NULL))
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
        GNUNET_JSON_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      TALER_amount_ntoh (&amount_from_purpose,
                         &withdraw_purpose.amount_with_fee);
      /* TODO #4980 */
      if (0 != TALER_amount_cmp (&amount,
                                 &amount_from_purpose))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.out_authorization_sig = json_object_get (transaction,
                                                                     "signature");
      /* Check check that the same withdraw transaction
         isn't listed twice by the exchange. We use the
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
          GNUNET_JSON_parse_free (withdraw_spec);
          return GNUNET_SYSERR;
        }
      }
      uuid_off++;

      if (GNUNET_OK !=
          TALER_amount_add (&total_out,
                            &total_out,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      /* end type==WITHDRAW */
    }
    else if (0 == strcasecmp (type,
                              "PAYBACK"))
    {
      struct TALER_PaybackConfirmationPS pc;
      struct TALER_Amount amount_from_purpose;
      struct GNUNET_TIME_Absolute timestamp_from_purpose;
      struct GNUNET_TIME_Absolute timestamp;
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_JSON_Specification payback_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("details",
                                     &pc),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &rhistory[off].details.payback_details.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &rhistory[off].details.payback_details.exchange_pub),
        GNUNET_JSON_spec_absolute_time ("timestamp",
                                        &timestamp),
        TALER_JSON_spec_amount ("amount",
                                &rhistory[off].amount),
        GNUNET_JSON_spec_end()
      };

      rhistory[off].type = TALER_EXCHANGE_RTT_PAYBACK;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             payback_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.payback_details.coin_pub = pc.coin_pub;
      TALER_amount_ntoh (&amount_from_purpose,
                         &pc.payback_amount);
      rhistory[off].details.payback_details.timestamp = timestamp;
      timestamp_from_purpose = GNUNET_TIME_absolute_ntoh (pc.timestamp);
      /* TODO #4980 */
      if ( (0 != memcmp (&pc.reserve_pub,
                         reserve_pub,
                         sizeof (*reserve_pub))) ||
           (timestamp_from_purpose.abs_value_us !=
            timestamp.abs_value_us) ||
           (0 != TALER_amount_cmp (&amount_from_purpose,
                                   &rhistory[off].amount)) )
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }

      key_state = TALER_EXCHANGE_get_keys (exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &rhistory[off].details.payback_details.exchange_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK,
                                      &pc.purpose,
                                      &rhistory[off].details.payback_details.exchange_sig.eddsa_signature,
                                      &rhistory[off].details.payback_details.exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_amount_add (&total_in,
                            &total_in,
                            &rhistory[off].amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* end type==PAYBACK */
    }
    else if (0 == strcasecmp (type,
                              "CLOSING"))
    {
      GNUNET_break (0); /* FIXME: implement with #4956 */
      /* end type==CLOSING */
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
    /* total_in < total_out, why did the exchange ever allow this!? */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserve/status request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReserveStatusHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_reserve_status_finished (void *cls,
                                long response_code,
                                const json_t *json)
{
  struct TALER_EXCHANGE_ReserveStatusHandle *rsh = cls;

  rsh->job = NULL;
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
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount ("balance", &balance),
        GNUNET_JSON_spec_end()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (json,
                             spec,
                             NULL,
			     NULL))
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
        struct TALER_EXCHANGE_ReserveHistory rhistory[len];

        if (GNUNET_OK !=
            parse_reserve_history (rsh->exchange,
                                   history,
                                   &rsh->reserve_pub,
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
          /* exchange cannot add up balances!? */
          GNUNET_break_op (0);
          response_code = 0;
          break;
        }
        rsh->cb (rsh->cb_cls,
                 response_code,
		 TALER_EC_NONE,
                 json,
                 &balance,
                 len,
                 rhistory);
        rsh->cb = NULL;
      }
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
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
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != rsh->cb)
    rsh->cb (rsh->cb_cls,
             response_code,
	     TALER_JSON_get_error_code (json),
             json,
             NULL,
             0, NULL);
  TALER_EXCHANGE_reserve_status_cancel (rsh);
}


/**
 * Submit a request to obtain the transaction history of a reserve
 * from the exchange.  Note that while we return the full response to the
 * caller for further processing, we do already verify that the
 * response is well-formed (i.e. that signatures included in the
 * response are all valid and add up to the balance).  If the exchange's
 * reply is not well-formed, we return an HTTP status code of zero to
 * @a cb.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param reserve_pub public key of the reserve to inspect
 * @param cb the callback to call when a reply for this request is available
 * @param cb_cls closure for the above callback
 * @return a handle for this request; NULL if the inputs are invalid (i.e.
 *         signatures fail to verify).  In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReserveStatusHandle *
TALER_EXCHANGE_reserve_status (struct TALER_EXCHANGE_Handle *exchange,
                               const struct TALER_ReservePublicKeyP *reserve_pub,
                               TALER_EXCHANGE_ReserveStatusResultCallback cb,
                               void *cb_cls)
{
  struct TALER_EXCHANGE_ReserveStatusHandle *rsh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char *pub_str;
  char *arg_str;

  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
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
  rsh = GNUNET_new (struct TALER_EXCHANGE_ReserveStatusHandle);
  rsh->exchange = exchange;
  rsh->cb = cb;
  rsh->cb_cls = cb_cls;
  rsh->reserve_pub = *reserve_pub;
  rsh->url = MAH_path_to_url (exchange,
                              arg_str);
  GNUNET_free (arg_str);

  eh = curl_easy_init ();
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rsh->url));
  ctx = MAH_handle_to_context (exchange);
  rsh->job = GNUNET_CURL_job_add (ctx,
                          eh,
                          GNUNET_NO,
                          &handle_reserve_status_finished,
                          rsh);
  return rsh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rsh the withdraw status request handle
 */
void
TALER_EXCHANGE_reserve_status_cancel (struct TALER_EXCHANGE_ReserveStatusHandle *rsh)
{
  if (NULL != rsh->job)
  {
    GNUNET_CURL_job_cancel (rsh->job);
    rsh->job = NULL;
  }
  GNUNET_free (rsh->url);
  GNUNET_free (rsh);
}


/* ********************** /reserve/withdraw ********************** */

/**
 * @brief A Withdraw Sign Handle
 */
struct TALER_EXCHANGE_ReserveWithdrawHandle
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
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ReserveWithdrawResultCallback cb;

  /**
   * Key used to blind the value.
   */
  struct TALER_DenominationBlindingKeyP blinding_key;

  /**
   * Denomination key we are withdrawing.
   */
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

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
 * The signature we get from the exchange is for the blinded value.
 * Thus, we first must unblind it and then should verify its
 * validity against our coin's hash.
 *
 * If everything checks out, we return the unblinded signature
 * to the application via the callback.
 *
 * @param wsh operation handle
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
reserve_withdraw_ok (struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh,
                     const json_t *json)
{
  struct GNUNET_CRYPTO_RsaSignature *blind_sig;
  struct GNUNET_CRYPTO_RsaSignature *sig;
  struct TALER_DenominationSignature dsig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_rsa_signature ("ev_sig", &blind_sig),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  sig = GNUNET_CRYPTO_rsa_unblind (blind_sig,
                                   &wsh->blinding_key.bks,
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
	   TALER_EC_NONE,
           &dsig,
           json);
  /* make sure callback isn't called again after return */
  wsh->cb = NULL;
  GNUNET_CRYPTO_rsa_signature_free (sig);
  return GNUNET_OK;
}


/**
 * We got a 403 FORBIDDEN response for the /reserve/withdraw operation.
 * Check the signatures on the withdraw transactions in the provided
 * history and that the balances add up.  We don't do anything directly
 * with the information, as the JSON will be returned to the application.
 * However, our job is ensuring that the exchange followed the protocol, and
 * this in particular means checking all of the signatures in the history.
 *
 * @param wsh operation handle
 * @param json reply from the exchange
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
reserve_withdraw_payment_required (struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh,
                                   const json_t *json)
{
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
  struct TALER_Amount requested_amount;
  json_t *history;
  size_t len;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("balance", &balance),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
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
    struct TALER_EXCHANGE_ReserveHistory rhistory[len];

    if (GNUNET_OK !=
        parse_reserve_history (wsh->exchange,
                               history,
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
    /* exchange cannot add up balances!? */
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
 * @param cls the `struct TALER_EXCHANGE_ReserveWithdrawHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_reserve_withdraw_finished (void *cls,
                                  long response_code,
                                  const json_t *json)
{
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh = cls;

  wsh->job = NULL;
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
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* The exchange says that the reserve has insufficient funds;
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
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; as we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, the exchange basically just says
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
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != wsh->cb)
    wsh->cb (wsh->cb_cls,
             response_code,
	     TALER_JSON_get_error_code (json),
             NULL,
             json);
  TALER_EXCHANGE_reserve_withdraw_cancel (wsh);
}


/**
 * Withdraw a coin from the exchange using a /reserve/withdraw request.  Note
 * that to ensure that no money is lost in case of hardware failures,
 * the caller must have committed (most of) the arguments to disk
 * before calling, and be ready to repeat the request with the same
 * arguments in case of failures.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param coin_priv where to fetch the coin's private key,
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param blinding_key where to fetch the coin's blinding key
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return handle for the operation on success, NULL on error, i.e.
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReserveWithdrawHandle *
TALER_EXCHANGE_reserve_withdraw (struct TALER_EXCHANGE_Handle *exchange,
                                 const struct TALER_EXCHANGE_DenomPublicKey *pk,
                                 const struct TALER_ReservePrivateKeyP *reserve_priv,
                                 const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                                 const struct TALER_DenominationBlindingKeyP *blinding_key,
                                 TALER_EXCHANGE_ReserveWithdrawResultCallback res_cb,
                                 void *res_cb_cls)
{
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;
  struct TALER_WithdrawRequestPS req;
  struct TALER_ReserveSignatureP reserve_sig;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct GNUNET_CURL_Context *ctx;
  struct TALER_Amount amount_with_fee;
  char *coin_ev;
  size_t coin_ev_size;
  json_t *withdraw_obj;
  CURL *eh;

  wsh = GNUNET_new (struct TALER_EXCHANGE_ReserveWithdrawHandle);
  wsh->exchange = exchange;
  wsh->cb = res_cb;
  wsh->cb_cls = res_cb_cls;
  wsh->pk = pk;

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &wsh->c_hash);
  if (GNUNET_YES !=
      GNUNET_CRYPTO_rsa_blind (&wsh->c_hash,
                               &blinding_key->bks,
                               pk->key.rsa_public_key,
                               &coin_ev,
                               &coin_ev_size))
  {
    GNUNET_break_op (0);
    GNUNET_free (wsh);
    return NULL;
  }
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
    /* exchange gave us denomination keys that overflow like this!? */
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
                            "denom_pub", GNUNET_JSON_from_rsa_public_key (pk->key.rsa_public_key),
                            "coin_ev", GNUNET_JSON_from_data (coin_ev,
                                                              coin_ev_size),
                            "reserve_pub", GNUNET_JSON_from_data_auto (&wsh->reserve_pub),
                            "reserve_sig", GNUNET_JSON_from_data_auto (&reserve_sig));
  GNUNET_free (coin_ev);

  wsh->blinding_key = *blinding_key;
  wsh->url = MAH_path_to_url (exchange, "/reserve/withdraw");

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
  ctx = MAH_handle_to_context (exchange);
  wsh->job = GNUNET_CURL_job_add (ctx,
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
TALER_EXCHANGE_reserve_withdraw_cancel (struct TALER_EXCHANGE_ReserveWithdrawHandle *sign)
{
  if (NULL != sign->job)
  {
    GNUNET_CURL_job_cancel (sign->job);
    sign->job = NULL;
  }
  GNUNET_free (sign->url);
  GNUNET_free (sign->json_enc);
  GNUNET_free (sign);
}


/* end of exchange_api_reserve.c */
