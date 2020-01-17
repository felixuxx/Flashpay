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
 * @file lib/exchange_api_reserve.c
 * @brief Implementation of the /reserve requests of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


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

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_out));
  uuid_off = 0;
  for (off = 0; off<history_length; off++)
  {
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification hist_spec[] = {
      GNUNET_JSON_spec_string ("type", &type),
      TALER_JSON_spec_amount ("amount",
                              &amount),
      /* 'wire' and 'signature' are optional depending on 'type'! */
      GNUNET_JSON_spec_end ()
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
      const char *wire_url;
      void *wire_reference;
      size_t wire_reference_size;
      struct GNUNET_TIME_Absolute timestamp;

      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_varsize ("wire_reference",
                                  &wire_reference,
                                  &wire_reference_size),
        GNUNET_JSON_spec_absolute_time ("timestamp",
                                        &timestamp),
        GNUNET_JSON_spec_string ("sender_account_url",
                                 &wire_url),
        GNUNET_JSON_spec_end ()
      };

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
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             withdraw_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.in_details.sender_url = GNUNET_strdup (wire_url);
      rhistory[off].details.in_details.wire_reference = wire_reference;
      rhistory[off].details.in_details.wire_reference_size =
        wire_reference_size;
      rhistory[off].details.in_details.timestamp = timestamp;
      /* end type==DEPOSIT */
    }
    else if (0 == strcasecmp (type,
                              "WITHDRAW"))
    {
      struct TALER_ReserveSignatureP sig;
      struct TALER_WithdrawRequestPS withdraw_purpose;
      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &sig),
        TALER_JSON_spec_amount_nbo ("withdraw_fee",
                                    &withdraw_purpose.withdraw_fee),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     &withdraw_purpose.h_denomination_pub),
        GNUNET_JSON_spec_fixed_auto ("h_coin_envelope",
                                     &withdraw_purpose.h_coin_envelope),
        GNUNET_JSON_spec_end ()
      };

      rhistory[off].type = TALER_EXCHANGE_RTT_WITHDRAWAL;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             withdraw_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      withdraw_purpose.purpose.size
        = htonl (sizeof (withdraw_purpose));
      withdraw_purpose.purpose.purpose
        = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
      withdraw_purpose.reserve_pub = *reserve_pub;
      TALER_amount_hton (&withdraw_purpose.amount_with_fee,
                         &amount);
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
      /* check that withdraw fee matches expectations! */
      {
        const struct TALER_EXCHANGE_Keys *key_state;
        const struct TALER_EXCHANGE_DenomPublicKey *dki;
        struct TALER_Amount fee;

        key_state = TALER_EXCHANGE_get_keys (exchange);
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                           &withdraw_purpose.
                                                           h_denomination_pub);
        TALER_amount_ntoh (&fee,
                           &withdraw_purpose.withdraw_fee);
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dki->fee_withdraw)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dki->fee_withdraw)) )
        {
          GNUNET_break_op (0);
          GNUNET_JSON_parse_free (withdraw_spec);
          return GNUNET_SYSERR;
        }
      }
      rhistory[off].details.out_authorization_sig
        = json_object_get (transaction,
                           "signature");
      /* Check check that the same withdraw transaction
         isn't listed twice by the exchange. We use the
         "uuid" array to remember the hashes of all
         purposes, and compare the hashes to find
         duplicates. *///
      GNUNET_CRYPTO_hash (&withdraw_purpose,
                          ntohl (withdraw_purpose.purpose.size),
                          &uuid[uuid_off]);
      for (unsigned int i = 0; i<uuid_off; i++)
      {
        if (0 == GNUNET_memcmp (&uuid[uuid_off],
                                &uuid[i]))
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
      struct GNUNET_TIME_Absolute timestamp;
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_JSON_Specification payback_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                     &pc.coin_pub),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &rhistory[off].details.payback_details.
                                     exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &rhistory[off].details.payback_details.
                                     exchange_pub),
        GNUNET_JSON_spec_absolute_time_nbo ("timestamp",
                                            &pc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      rhistory[off].type = TALER_EXCHANGE_RTT_PAYBACK;
      rhistory[off].amount = amount;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             payback_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      rhistory[off].details.payback_details.coin_pub = pc.coin_pub;
      TALER_amount_hton (&pc.payback_amount,
                         &amount);
      pc.purpose.size = htonl (sizeof (pc));
      pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK);
      pc.reserve_pub = *reserve_pub;
      timestamp = GNUNET_TIME_absolute_ntoh (pc.timestamp);
      rhistory[off].details.payback_details.timestamp = timestamp;

      key_state = TALER_EXCHANGE_get_keys (exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &rhistory[off].details.
                                           payback_details.exchange_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK,
                                      &pc.purpose,
                                      &rhistory[off].details.payback_details.
                                      exchange_sig.eddsa_signature,
                                      &rhistory[off].details.payback_details.
                                      exchange_pub.eddsa_pub))
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
      const struct TALER_EXCHANGE_Keys *key_state;
      struct TALER_ReserveCloseConfirmationPS rcc;
      struct GNUNET_TIME_Absolute timestamp;
      struct GNUNET_JSON_Specification closing_spec[] = {
        GNUNET_JSON_spec_string ("receiver_account_details",
                                 &rhistory[off].details.close_details.
                                 receiver_account_details),
        GNUNET_JSON_spec_fixed_auto ("wtid",
                                     &rhistory[off].details.close_details.wtid),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &rhistory[off].details.close_details.
                                     exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &rhistory[off].details.close_details.
                                     exchange_pub),
        TALER_JSON_spec_amount_nbo ("closing_fee",
                                    &rcc.closing_fee),
        GNUNET_JSON_spec_absolute_time_nbo ("timestamp",
                                            &rcc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      rhistory[off].type = TALER_EXCHANGE_RTT_CLOSE;
      rhistory[off].amount = amount;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             closing_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      TALER_amount_hton (&rcc.closing_amount,
                         &amount);
      GNUNET_CRYPTO_hash (
        rhistory[off].details.close_details.receiver_account_details,
        strlen (
          rhistory[off].details.close_details.receiver_account_details) + 1,
        &rcc.h_wire);
      rcc.wtid = rhistory[off].details.close_details.wtid;
      rcc.purpose.size = htonl (sizeof (rcc));
      rcc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED);
      rcc.reserve_pub = *reserve_pub;
      timestamp = GNUNET_TIME_absolute_ntoh (rcc.timestamp);
      rhistory[off].details.close_details.timestamp = timestamp;

      key_state = TALER_EXCHANGE_get_keys (exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &rhistory[off].details.close_details.
                                           exchange_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED,
                                      &rcc.purpose,
                                      &rhistory[off].details.close_details.
                                      exchange_sig.eddsa_signature,
                                      &rhistory[off].details.close_details.
                                      exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_amount_add (&total_out,
                            &total_out,
                            &rhistory[off].amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
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
 * Free memory (potentially) allocated by #parse_reserve_history().
 *
 * @param rhistory result to free
 * @param len number of entries in @a rhistory
 */
static void
free_rhistory (struct TALER_EXCHANGE_ReserveHistory *rhistory,
               unsigned int len)
{
  for (unsigned int i = 0; i<len; i++)
  {
    switch (rhistory[i].type)
    {
    case TALER_EXCHANGE_RTT_DEPOSIT:
      GNUNET_free_non_null (rhistory[i].details.in_details.wire_reference);
      GNUNET_free_non_null (rhistory[i].details.in_details.sender_url);
      break;
    case TALER_EXCHANGE_RTT_WITHDRAWAL:
      break;
    case TALER_EXCHANGE_RTT_PAYBACK:
      break;
    case TALER_EXCHANGE_RTT_CLOSE:
      // should we free "receiver_account_details" ?
      break;
    }
  }
  GNUNET_free (rhistory);
}


/**
 * We received an #MHD_HTTP_OK status code. Handle the JSON
 * response.
 *
 * @param rsh handle of the request
 * @param j JSON response
 * @return #GNUNET_OK on success
 */
static int
handle_reserve_status_ok (struct TALER_EXCHANGE_ReserveStatusHandle *rsh,
                          const json_t *j)
{
  json_t *history;
  unsigned int len;
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("balance", &balance),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (j,
                         spec,
                         NULL,
                         NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  history = json_object_get (j,
                             "history");
  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  {
    struct TALER_EXCHANGE_ReserveHistory *rhistory;

    rhistory = GNUNET_new_array (len,
                                 struct TALER_EXCHANGE_ReserveHistory);
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
      free_rhistory (rhistory,
                     len);
      return GNUNET_SYSERR;
    }
    if (0 !=
        TALER_amount_cmp (&balance_from_history,
                          &balance))
    {
      /* exchange cannot add up balances!? */
      GNUNET_break_op (0);
      free_rhistory (rhistory,
                     len);
      return GNUNET_SYSERR;
    }
    if (NULL != rsh->cb)
    {
      rsh->cb (rsh->cb_cls,
               MHD_HTTP_OK,
               TALER_EC_NONE,
               j,
               &balance,
               len,
               rhistory);
      rsh->cb = NULL;
    }
    free_rhistory (rhistory,
                   len);
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /reserve/status request.
 *
 * @param cls the `struct TALER_EXCHANGE_ReserveStatusHandle`
 * @param response_code HTTP response code, 0 on error
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserve_status_finished (void *cls,
                                long response_code,
                                const void *response)
{
  struct TALER_EXCHANGE_ReserveStatusHandle *rsh = cls;
  const json_t *j = response;

  rsh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        handle_reserve_status_ok (rsh,
                                  j))
      response_code = 0;
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
  {
    rsh->cb (rsh->cb_cls,
             response_code,
             TALER_JSON_get_error_code (j),
             j,
             NULL,
             0, NULL);
    rsh->cb = NULL;
  }
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
                               const struct
                               TALER_ReservePublicKeyP *reserve_pub,
                               TALER_EXCHANGE_ReserveStatusResultCallback cb,
                               void *cb_cls)
{
  struct TALER_EXCHANGE_ReserveStatusHandle *rsh;
  struct GNUNET_CURL_Context *ctx;
  CURL *eh;
  char *pub_str;
  char *arg_str;

  if (GNUNET_YES !=
      TEAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  pub_str = GNUNET_STRINGS_data_to_string_alloc (reserve_pub,
                                                 sizeof (struct
                                                         TALER_ReservePublicKeyP));
  GNUNET_asprintf (&arg_str,
                   "/reserve/status?reserve_pub=%s",
                   pub_str);
  GNUNET_free (pub_str);
  rsh = GNUNET_new (struct TALER_EXCHANGE_ReserveStatusHandle);
  rsh->exchange = exchange;
  rsh->cb = cb;
  rsh->cb_cls = cb_cls;
  rsh->reserve_pub = *reserve_pub;
  rsh->url = TEAH_path_to_url (exchange,
                               arg_str);
  GNUNET_free (arg_str);

  eh = TEL_curl_easy_get (rsh->url);
  ctx = TEAH_handle_to_context (exchange);
  rsh->job = GNUNET_CURL_job_add (ctx,
                                  eh,
                                  GNUNET_NO,
                                  &handle_reserve_status_finished,
                                  rsh);
  return rsh;
}


/**
 * Cancel a reserve status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param rsh the reserve status request handle
 */
void
TALER_EXCHANGE_reserve_status_cancel (struct
                                      TALER_EXCHANGE_ReserveStatusHandle *rsh)
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
  TALER_EXCHANGE_ReserveWithdrawResultCallback cb;

  /**
   * Secrets of the planchet.
   */
  struct TALER_PlanchetSecretsP ps;

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

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
  struct TALER_FreshCoin fc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_rsa_signature ("ev_sig",
                                    &blind_sig),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_planchet_to_coin (&wsh->pk.key,
                              blind_sig,
                              &wsh->ps,
                              &wsh->c_hash,
                              &fc))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return GNUNET_SYSERR;
  }
  GNUNET_JSON_parse_free (spec);

  /* signature is valid, return it to the application */
  wsh->cb (wsh->cb_cls,
           MHD_HTTP_OK,
           TALER_EC_NONE,
           &fc.sig,
           json);
  /* make sure callback isn't called again after return */
  wsh->cb = NULL;
  GNUNET_CRYPTO_rsa_signature_free (fc.sig.rsa_signature);
  return GNUNET_OK;
}


/**
 * We got a 409 CONFLICT response for the /reserve/withdraw operation.
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
reserve_withdraw_payment_required (struct
                                   TALER_EXCHANGE_ReserveWithdrawHandle *wsh,
                                   const json_t *json)
{
  struct TALER_Amount balance;
  struct TALER_Amount balance_from_history;
  struct TALER_Amount requested_amount;
  json_t *history;
  size_t len;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("balance", &balance),
    GNUNET_JSON_spec_end ()
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
    struct TALER_EXCHANGE_ReserveHistory *rhistory;

    /* Use heap allocation as "len" may be very big and thus this may
       not fit on the stack. Use "GNUNET_malloc_large" as a malicious
       exchange may theoretically try to crash us by giving a history
       that does not fit into our memory. */
    rhistory = GNUNET_malloc_large (sizeof (struct
                                            TALER_EXCHANGE_ReserveHistory)
                                    * len);
    if (NULL == rhistory)
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }

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
      free_rhistory (rhistory,
                     len);
      return GNUNET_SYSERR;
    }
    free_rhistory (rhistory,
                   len);
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
                        &wsh->pk.value,
                        &wsh->pk.fee_withdraw))
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
 * @param response parsed JSON result, NULL on error
 */
static void
handle_reserve_withdraw_finished (void *cls,
                                  long response_code,
                                  const void *response)
{
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh = cls;
  const json_t *j = response;

  wsh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        reserve_withdraw_ok (wsh,
                             j))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    /* The exchange says that the reserve has insufficient funds;
       check the signatures in the history... */
    if (GNUNET_OK !=
        reserve_withdraw_payment_required (wsh,
                                           j))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_FORBIDDEN:
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
  {
    wsh->cb (wsh->cb_cls,
             response_code,
             TALER_JSON_get_error_code (j),
             NULL,
             j);
    wsh->cb = NULL;
  }
  TALER_EXCHANGE_reserve_withdraw_cancel (wsh);
}


/**
 * Helper function for #TALER_EXCHANGE_reserve_withdraw2() and
 * #TALER_EXCHANGE_reserve_withdraw().
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_sig signature from the reserve authorizing the withdrawal
 * @param reserve_pub public key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param pd planchet details matching @a ps
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReserveWithdrawHandle *
reserve_withdraw_internal (struct TALER_EXCHANGE_Handle *exchange,
                           const struct TALER_EXCHANGE_DenomPublicKey *pk,
                           const struct TALER_ReserveSignatureP *reserve_sig,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_PlanchetSecretsP *ps,
                           const struct TALER_PlanchetDetail *pd,
                           TALER_EXCHANGE_ReserveWithdrawResultCallback res_cb,
                           void *res_cb_cls)
{
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;
  struct GNUNET_CURL_Context *ctx;
  json_t *withdraw_obj;
  CURL *eh;
  struct GNUNET_HashCode h_denom_pub;

  wsh = GNUNET_new (struct TALER_EXCHANGE_ReserveWithdrawHandle);
  wsh->exchange = exchange;
  wsh->cb = res_cb;
  wsh->cb_cls = res_cb_cls;
  wsh->pk = *pk;
  wsh->pk.key.rsa_public_key = GNUNET_CRYPTO_rsa_public_key_dup (
    pk->key.rsa_public_key);
  wsh->reserve_pub = *reserve_pub;
  wsh->c_hash = pd->c_hash;
  GNUNET_CRYPTO_rsa_public_key_hash (pk->key.rsa_public_key,
                                     &h_denom_pub);
  withdraw_obj = json_pack ("{s:o, s:o," /* denom_pub_hash and coin_ev */
                            " s:o, s:o}",/* reserve_pub and reserve_sig */
                            "denom_pub_hash", GNUNET_JSON_from_data_auto (
                              &h_denom_pub),
                            "coin_ev", GNUNET_JSON_from_data (pd->coin_ev,
                                                              pd->coin_ev_size),
                            "reserve_pub", GNUNET_JSON_from_data_auto (
                              reserve_pub),
                            "reserve_sig", GNUNET_JSON_from_data_auto (
                              reserve_sig));
  if (NULL == withdraw_obj)
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_public_key_free (wsh->pk.key.rsa_public_key);
    GNUNET_free (wsh);
    return NULL;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Attempting to withdraw from reserve %s\n",
              TALER_B2S (reserve_pub));

  wsh->ps = *ps;
  wsh->url = TEAH_path_to_url (exchange, "/reserve/withdraw");
  eh = TEL_curl_easy_get (wsh->url);
  if (GNUNET_OK !=
      TALER_curl_easy_post (&wsh->ctx,
                            eh,
                            withdraw_obj))
  {
    GNUNET_break (0);
    curl_easy_cleanup (eh);
    json_decref (withdraw_obj);
    GNUNET_free (wsh->url);
    GNUNET_CRYPTO_rsa_public_key_free (wsh->pk.key.rsa_public_key);
    GNUNET_free (wsh);
    return NULL;
  }
  json_decref (withdraw_obj);
  ctx = TEAH_handle_to_context (exchange);
  wsh->job = GNUNET_CURL_job_add2 (ctx,
                                   eh,
                                   wsh->ctx.headers,
                                   &handle_reserve_withdraw_finished,
                                   wsh);
  return wsh;
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
 * @param ps secrets of the planchet
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
                                 const struct
                                 TALER_ReservePrivateKeyP *reserve_priv,
                                 const struct TALER_PlanchetSecretsP *ps,
                                 TALER_EXCHANGE_ReserveWithdrawResultCallback
                                 res_cb,
                                 void *res_cb_cls)
{
  struct TALER_Amount amount_with_fee;
  struct TALER_ReserveSignatureP reserve_sig;
  struct TALER_WithdrawRequestPS req;
  struct TALER_PlanchetDetail pd;
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &req.reserve_pub.eddsa_pub);
  req.purpose.size = htonl (sizeof (struct TALER_WithdrawRequestPS));
  req.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  if (GNUNET_OK !=
      TALER_amount_add (&amount_with_fee,
                        &pk->fee_withdraw,
                        &pk->value))
  {
    /* exchange gave us denomination keys that overflow like this!? */
    GNUNET_break_op (0);
    return NULL;
  }
  TALER_amount_hton (&req.amount_with_fee,
                     &amount_with_fee);
  TALER_amount_hton (&req.withdraw_fee,
                     &pk->fee_withdraw);
  if (GNUNET_OK !=
      TALER_planchet_prepare (&pk->key,
                              ps,
                              &pd))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  req.h_denomination_pub = pd.denom_pub_hash;
  GNUNET_CRYPTO_hash (pd.coin_ev,
                      pd.coin_ev_size,
                      &req.h_coin_envelope);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                                           &req.purpose,
                                           &reserve_sig.eddsa_signature));
  wsh = reserve_withdraw_internal (exchange,
                                   pk,
                                   &reserve_sig,
                                   &req.reserve_pub,
                                   ps,
                                   &pd,
                                   res_cb,
                                   res_cb_cls);
  GNUNET_free (pd.coin_ev);
  return wsh;
}


/**
 * Withdraw a coin from the exchange using a /reserve/withdraw
 * request.  This API is typically used by a wallet to withdraw a tip
 * where the reserve's signature was created by the merchant already.
 *
 * Note that to ensure that no money is lost in case of hardware
 * failures, the caller must have committed (most of) the arguments to
 * disk before calling, and be ready to repeat the request with the
 * same arguments in case of failures.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_sig signature from the reserve authorizing the withdrawal
 * @param reserve_pub public key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for @a res_cb
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_ReserveWithdrawHandle *
TALER_EXCHANGE_reserve_withdraw2 (struct TALER_EXCHANGE_Handle *exchange,
                                  const struct
                                  TALER_EXCHANGE_DenomPublicKey *pk,
                                  const struct
                                  TALER_ReserveSignatureP *reserve_sig,
                                  const struct
                                  TALER_ReservePublicKeyP *reserve_pub,
                                  const struct TALER_PlanchetSecretsP *ps,
                                  TALER_EXCHANGE_ReserveWithdrawResultCallback
                                  res_cb,
                                  void *res_cb_cls)
{
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;
  struct TALER_PlanchetDetail pd;

  if (GNUNET_OK !=
      TALER_planchet_prepare (&pk->key,
                              ps,
                              &pd))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  wsh = reserve_withdraw_internal (exchange,
                                   pk,
                                   reserve_sig,
                                   reserve_pub,
                                   ps,
                                   &pd,
                                   res_cb,
                                   res_cb_cls);
  GNUNET_free (pd.coin_ev);
  return wsh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param sign the withdraw sign request handle
 */
void
TALER_EXCHANGE_reserve_withdraw_cancel (struct
                                        TALER_EXCHANGE_ReserveWithdrawHandle *
                                        sign)
{
  if (NULL != sign->job)
  {
    GNUNET_CURL_job_cancel (sign->job);
    sign->job = NULL;
  }
  GNUNET_free (sign->url);
  TALER_curl_easy_post_finished (&sign->ctx);
  GNUNET_CRYPTO_rsa_public_key_free (sign->pk.key.rsa_public_key);
  GNUNET_free (sign);
}


/* end of exchange_api_reserve.c */
