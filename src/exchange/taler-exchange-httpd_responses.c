/*
  This file is part of TALER
  Copyright (C) 2014-2017 Inria & GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_responses.c
 * @brief API for generating the various replies of the exchange; these
 *        functions are called TEH_RESPONSE_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <zlib.h>
#include "taler-exchange-httpd_responses.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Add headers we want to return in every response.
 * Useful for testing, like if we want to always close
 * connections.
 *
 * @param response response to modify
 */
void
TEH_RESPONSE_add_global_headers (struct MHD_Response *response)
{
  if (TEH_exchange_connection_close)
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (response,
                                           MHD_HTTP_HEADER_CONNECTION,
                                           "close"));
}


/**
 * Is HTTP body deflate compression supported by the client?
 *
 * @param connection connection to check
 * @return #MHD_YES if 'deflate' compression is allowed
 */
int
TEH_RESPONSE_can_compress (struct MHD_Connection *connection)
{
  const char *ae;
  const char *de;

  ae = MHD_lookup_connection_value (connection,
				    MHD_HEADER_KIND,
				    MHD_HTTP_HEADER_ACCEPT_ENCODING);
  if (NULL == ae)
    return MHD_NO;
  de = strstr (ae,
	       "deflate");
  if (NULL == de)
    return MHD_NO;
  if ( ( (de == ae) ||
	 ( de[-1] == ',') ||
	 (de[-1] == ' ') ) &&
       ( (de[strlen ("deflate")] == '\0') ||
	 (de[strlen ("deflate")] == ',') ) )
    return MHD_YES;
  return MHD_NO;
}


/**
 * Try to compress a response body.  Updates @a buf and @a buf_size.
 *
 * @param[in,out] buf pointer to body to compress
 * @param[in,out] buf_size pointer to initial size of @a buf
 * @return #MHD_TES if @a buf was compressed
 */
int
TEH_RESPONSE_body_compress (void **buf,
			    size_t *buf_size)
{
  Bytef *cbuf;
  uLongf cbuf_size;
  int ret;

  cbuf_size = compressBound (*buf_size);
  cbuf = malloc (cbuf_size);
  if (NULL == cbuf)
    return MHD_NO;
  ret = compress (cbuf,
		  &cbuf_size,
		  (const Bytef *) *buf,
		  *buf_size);
  if ( (Z_OK != ret) ||
       (cbuf_size >= *buf_size) )
  {
    /* compression failed */
    free (cbuf);
    return MHD_NO;
  }
  free (*buf);
  *buf = (void *) cbuf;
  *buf_size = (size_t) cbuf_size;
  return MHD_YES;
}


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_json (struct MHD_Connection *connection,
                         const json_t *json,
                         unsigned int response_code)
{
  struct MHD_Response *resp;
  void *json_str;
  size_t json_len;
  int ret;
  int comp;

  json_str = json_dumps (json,
			 JSON_INDENT(2));
  if (NULL == json_str)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  json_len = strlen (json_str);
  /* try to compress the body */
  comp = MHD_NO;
  if (MHD_YES ==
      TEH_RESPONSE_can_compress (connection))
    comp = TEH_RESPONSE_body_compress (&json_str,
				       &json_len);
  resp = MHD_create_response_from_buffer (json_len,
                                          json_str,
                                          MHD_RESPMEM_MUST_FREE);
  if (NULL == resp)
  {
    free (json_str);
    GNUNET_break (0);
    return MHD_NO;
  }
  TEH_RESPONSE_add_global_headers (resp);
  (void) MHD_add_response_header (resp,
                                  MHD_HTTP_HEADER_CONTENT_TYPE,
                                  "application/json");
  if (MHD_YES == comp)
  {
    /* Need to indicate to client that body is compressed */
    if (MHD_NO ==
	MHD_add_response_header (resp,
				 MHD_HTTP_HEADER_CONTENT_ENCODING,
				 "deflate"))
    {
      GNUNET_break (0);
      MHD_destroy_response (resp);
      return MHD_NO;
    }
  }
  ret = MHD_queue_response (connection,
                            response_code,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Function to call to handle the request by building a JSON
 * reply from a format string and varargs.
 *
 * @param connection the MHD connection to handle
 * @param response_code HTTP response code to use
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_json_pack (struct MHD_Connection *connection,
                              unsigned int response_code,
                              const char *fmt,
                              ...)
{
  json_t *json;
  va_list argp;
  int ret;
  json_error_t jerror;

  va_start (argp, fmt);
  json = json_vpack_ex (&jerror, 0, fmt, argp);
  va_end (argp);
  if (NULL == json)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to pack JSON with format `%s': %s\n",
                fmt,
                jerror.text);
    GNUNET_break (0);
    return MHD_NO;
  }
  ret = TEH_RESPONSE_reply_json (connection,
                                 json,
                                 response_code);
  json_decref (json);
  return ret;
}


/**
 * Send a response indicating an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_arg_invalid (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I, s:s}",
                                       "error", "invalid parameter",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating an argument refering to a
 * resource unknown to the exchange (i.e. unknown reserve or
 * denomination key).
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_arg_unknown (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s, s:I, s:s}",
                                       "error", "unknown entity referenced",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating an invalid signature.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_signature_invalid (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec,
                                      const char *param_name)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       "{s:s, s:I, s:s}",
                                       "error", "invalid signature",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_arg_missing (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I, s:s}",
                                       "error", "missing parameter",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating permission denied.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about why access was denied
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_permission_denied (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec,
                                      const char *hint)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s, s:I, s:s}",
                                       "error", "permission denied",
				       "code", (json_int_t) ec,
                                       "hint", hint);
}


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_internal_error (struct MHD_Connection *connection,
				   enum TALER_ErrorCode ec,
                                   const char *hint)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       "{s:s, s:I, s:s}",
                                       "error", "internal error",
				       "code", (json_int_t) ec,
                                       "hint", hint);
}


/**
 * Send a response indicating an external error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about the error's nature
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_external_error (struct MHD_Connection *connection,
				   enum TALER_ErrorCode ec,
                                   const char *hint)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I, s:s}",
                                       "error", "client error",
				       "code", (json_int_t) ec,
                                       "hint", hint);
}


/**
 * Send a response indicating an error committing a
 * transaction (concurrent interference).
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_commit_error (struct MHD_Connection *connection,
				 enum TALER_ErrorCode ec)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I}",
                                       "error", "commit failure",
				       "code", (json_int_t) ec);
}


/**
 * Send a response indicating a failure to talk to the Exchange's
 * database.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_internal_db_error (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec)
{
  return TEH_RESPONSE_reply_internal_error (connection,
					    ec,
                                            "Failure in database interaction");
}


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_request_too_large (struct MHD_Connection *connection)
{
  struct MHD_Response *resp;
  int ret;

  resp = MHD_create_response_from_buffer (0,
                                          NULL,
                                          MHD_RESPMEM_PERSISTENT);
  if (NULL == resp)
    return MHD_NO;
  TEH_RESPONSE_add_global_headers (resp);
  ret = MHD_queue_response (connection,
                            MHD_HTTP_REQUEST_ENTITY_TOO_LARGE,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Send a response indicating that the JSON was malformed.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_invalid_json (struct MHD_Connection *connection)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I}",
                                       "error", "invalid json",
				       "code", (json_int_t) TALER_EC_JSON_INVALID);
}


/**
 * Send confirmation of deposit success to client.  This function
 * will create a signed message affirming the given information
 * and return it to the client.  By this, the exchange affirms that
 * the coin had sufficient (residual) value for the specified
 * transaction and that it will execute the requested deposit
 * operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param h_wire hash of wire details
 * @param h_contract_terms hash of contract details
 * @param timestamp client's timestamp
 * @param refund_deadline until when this deposit be refunded
 * @param merchant merchant public key
 * @param amount_without_fee fraction of coin value to deposit, without the fee
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_deposit_success (struct MHD_Connection *connection,
                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct GNUNET_HashCode *h_wire,
                                    const struct GNUNET_HashCode *h_contract_terms,
                                    struct GNUNET_TIME_Absolute timestamp,
                                    struct GNUNET_TIME_Absolute refund_deadline,
                                    const struct TALER_MerchantPublicKeyP *merchant,
                                    const struct TALER_Amount *amount_without_fee)
{
  struct TALER_DepositConfirmationPS dc;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  dc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT);
  dc.purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS));
  dc.h_contract_terms = *h_contract_terms;
  dc.h_wire = *h_wire;
  dc.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dc.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  dc.coin_pub = *coin_pub;
  dc.merchant = *merchant;
  TEH_KS_sign (&dc.purpose,
               &pub,
               &sig);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:s, s:o, s:o}",
                                       "status", "DEPOSIT_OK",
                                       "sig", GNUNET_JSON_from_data_auto (&sig),
                                       "pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Compile the transaction history of a coin into a JSON object.
 *
 * @param tl transaction history to JSON-ify
 * @return json representation of the @a rh
 */
static json_t *
compile_transaction_history (const struct TALER_EXCHANGEDB_TransactionList *tl)
{
  json_t *history;

  history = json_array ();
  if (NULL == history)
  {
    GNUNET_break (0); /* out of memory!? */
    return NULL;
  }
  for (const struct TALER_EXCHANGEDB_TransactionList *pos = tl; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      {
        struct TALER_DepositRequestPS dr;
        const struct TALER_EXCHANGEDB_Deposit *deposit = pos->details.deposit;

        dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
        dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
        dr.h_contract_terms = deposit->h_contract_terms;
        dr.h_wire = deposit->h_wire;
        dr.timestamp = GNUNET_TIME_absolute_hton (deposit->timestamp);
        dr.refund_deadline = GNUNET_TIME_absolute_hton (deposit->refund_deadline);
        TALER_amount_hton (&dr.amount_with_fee,
                           &deposit->amount_with_fee);
        TALER_amount_hton (&dr.deposit_fee,
                           &deposit->deposit_fee);
        dr.merchant = deposit->merchant_pub;
        dr.coin_pub = deposit->coin.coin_pub;
	/* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                        &dr.purpose,
                                        &deposit->csig.eddsa_signature,
                                        &deposit->coin.coin_pub.eddsa_pub))
	{
	  GNUNET_break (0);
	  json_decref (history);
	  return NULL;
	}

	GNUNET_assert (0 ==
		       json_array_append_new (history,
					      json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
							 "type", "DEPOSIT",
							 "amount", TALER_JSON_from_amount (&deposit->amount_with_fee),
							 "deposit_fee", TALER_JSON_from_amount (&deposit->deposit_fee),
							 "timestamp", GNUNET_JSON_from_time_abs (deposit->timestamp),
							 "refund_deadline", GNUNET_JSON_from_time_abs (deposit->refund_deadline),
							 "merchant_pub", GNUNET_JSON_from_data_auto (&deposit->merchant_pub),
							 "h_contract_terms", GNUNET_JSON_from_data_auto (&deposit->h_contract_terms),
							 "h_wire", GNUNET_JSON_from_data_auto (&deposit->h_wire),
							 "coin_sig", GNUNET_JSON_from_data_auto (&deposit->csig))));
	break;
      }
    case TALER_EXCHANGEDB_TT_REFRESH_MELT:
      {
        struct TALER_RefreshMeltCoinAffirmationPS ms;
        const struct TALER_EXCHANGEDB_RefreshMelt *melt = pos->details.melt;

        ms.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
        ms.purpose.size = htonl (sizeof (struct TALER_RefreshMeltCoinAffirmationPS));
        ms.session_hash = melt->session_hash;
        TALER_amount_hton (&ms.amount_with_fee,
                           &melt->amount_with_fee);
        TALER_amount_hton (&ms.melt_fee,
                           &melt->melt_fee);
        ms.coin_pub = melt->coin.coin_pub;
	/* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                        &ms.purpose,
                                        &melt->coin_sig.eddsa_signature,
                                        &melt->coin.coin_pub.eddsa_pub))
	{
	  GNUNET_break (0);
	  json_decref (history);
	  return NULL;
	}

	GNUNET_assert (0 ==
		       json_array_append_new (history,
					      json_pack ("{s:s, s:o, s:o, s:o, s:o}",
							 "type", "MELT",
							 "amount", TALER_JSON_from_amount (&melt->amount_with_fee),
							 "melt_fee", TALER_JSON_from_amount (&melt->melt_fee),
							 "session_hash", GNUNET_JSON_from_data_auto (&melt->session_hash),
							 "coin_sig", GNUNET_JSON_from_data_auto (&melt->coin_sig))));
      }
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      {
        struct TALER_RefundRequestPS rr;
        const struct TALER_EXCHANGEDB_Refund *refund = pos->details.refund;
	struct TALER_Amount value;

        if (GNUNET_OK !=
            TALER_amount_subtract (&value,
                                   &refund->refund_amount,
                                   &refund->refund_fee))
        {
	  GNUNET_break (0);
	  json_decref (history);
	  return NULL;
        }
        rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
        rr.purpose.size = htonl (sizeof (struct TALER_RefundRequestPS));
        rr.h_contract_terms = refund->h_contract_terms;
        rr.coin_pub = refund->coin.coin_pub;
        rr.merchant = refund->merchant_pub;
        rr.rtransaction_id = GNUNET_htonll (refund->rtransaction_id);
        TALER_amount_hton (&rr.refund_amount,
                           &refund->refund_amount);
        TALER_amount_hton (&rr.refund_fee,
                           &refund->refund_fee);
	/* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                        &rr.purpose,
                                        &refund->merchant_sig.eddsa_sig,
                                        &refund->merchant_pub.eddsa_pub))
	{
	  GNUNET_break (0);
	  json_decref (history);
	  return NULL;
	}

	GNUNET_assert (0 ==
		       json_array_append_new (history,
					      json_pack ("{s:s, s:o, s:o, s:o, s:o, s:I, s:o}",
							 "type", "REFUND",
							 "amount", TALER_JSON_from_amount (&value),
							 "refund_fee", TALER_JSON_from_amount (&refund->refund_fee),
							 "h_contract_terms", GNUNET_JSON_from_data_auto (&refund->h_contract_terms),
							 "merchant_pub", GNUNET_JSON_from_data_auto (&refund->merchant_pub),
							 "rtransaction_id", (json_int_t) refund->rtransaction_id,
							 "merchant_sig", GNUNET_JSON_from_data_auto (&refund->merchant_sig))));
      }
      break;
    case TALER_EXCHANGEDB_TT_PAYBACK:
      {
        const struct TALER_EXCHANGEDB_Payback *payback = pos->details.payback;
        struct TALER_PaybackConfirmationPS pc;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK);
        pc.purpose.size = htonl (sizeof (pc));
        pc.timestamp = GNUNET_TIME_absolute_hton (payback->timestamp);
        TALER_amount_hton (&pc.payback_amount,
                           &payback->value);
        pc.coin_pub = payback->coin.coin_pub;
        pc.reserve_pub = payback->reserve_pub;
        TEH_KS_sign (&pc.purpose,
                     &epub,
                     &esig);
        GNUNET_assert (0 ==
                       json_array_append_new (history,
                                              json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                                                         "type", "PAYBACK",
                                                         "amount", TALER_JSON_from_amount (&payback->value),
                                                         "exchange_sig", GNUNET_JSON_from_data_auto (&esig),
                                                         "exchange_pub", GNUNET_JSON_from_data_auto (&epub),
							 "reserve_pub", GNUNET_JSON_from_data_auto (&payback->reserve_pub),
							 "timestamp", GNUNET_JSON_from_time_abs (payback->timestamp))));
      }
      break;
    default:
      GNUNET_assert (0);
    }
  }
  return history;
}


/**
 * Send proof that a request is invalid to client because of
 * insufficient funds.  This function will create a message with all
 * of the operations affecting the coin that demonstrate that the coin
 * has insufficient value.
 *
 * @param connection connection to the client
 * @param ec error code to return
 * @param tl transaction list to use to build reply
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_coin_insufficient_funds (struct MHD_Connection *connection,
                                            enum TALER_ErrorCode ec,
                                            const struct TALER_EXCHANGEDB_TransactionList *tl)
{
  json_t *history;

  history = compile_transaction_history (tl);
  if (NULL == history)
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_COIN_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                              "failed to convert transaction history to JSON");
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s, s:I, s:o}",
                                       "error", "insufficient funds",
				       "code", (json_int_t) ec,
                                       "history", history);
}


/**
 * Compile the history of a reserve into a JSON object
 * and calculate the total balance.
 *
 * @param rh reserve history to JSON-ify
 * @param[out] balance set to current reserve balance
 * @return json representation of the @a rh, NULL on error
 */
static json_t *
compile_reserve_history (const struct TALER_EXCHANGEDB_ReserveHistory *rh,
                         struct TALER_Amount *balance)
{
  struct TALER_Amount deposit_total;
  struct TALER_Amount withdraw_total;
  json_t *json_history;
  int ret;

  json_history = json_array ();
  ret = 0;
  for (const struct TALER_EXCHANGEDB_ReserveHistory *pos = rh; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      if (0 == (1 & ret))
        deposit_total = pos->details.bank->amount;
      else
        if (GNUNET_OK !=
            TALER_amount_add (&deposit_total,
                              &deposit_total,
                              &pos->details.bank->amount))
        {
          json_decref (json_history);
          return NULL;
        }
      ret |= 1;
      GNUNET_assert (0 ==
                     json_array_append_new (json_history,
                                            json_pack ("{s:s, s:O, s:O, s:o}",
                                                       "type", "DEPOSIT",
                                                       "sender_account_details", pos->details.bank->sender_account_details,
                                                       "wire_reference", GNUNET_JSON_from_data (pos->details.bank->wire_reference,
                                                                                                pos->details.bank->wire_reference_size),
                                                       "amount", TALER_JSON_from_amount (&pos->details.bank->amount))));
      break;
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      {
	struct GNUNET_HashCode h_denom_pub;
	struct TALER_Amount value;

	value = pos->details.withdraw->amount_with_fee;
	if (0 == (2 & ret))
	{
	  withdraw_total = value;
	}
	else
	{
	  if (GNUNET_OK !=
	      TALER_amount_add (&withdraw_total,
				&withdraw_total,
				&value))
	  {
	    json_decref (json_history);
	    return NULL;
	  }
	}
	ret |= 2;
	GNUNET_CRYPTO_rsa_public_key_hash (pos->details.withdraw->denom_pub.rsa_public_key,
					   &h_denom_pub);
	GNUNET_assert (0 ==
		       json_array_append_new (json_history,
					      json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
							 "type", "WITHDRAW",
							 "reserve_sig", GNUNET_JSON_from_data_auto (&pos->details.withdraw->reserve_sig),
							 "h_coin_envelope", GNUNET_JSON_from_data_auto (&pos->details.withdraw->h_coin_envelope),
							 "h_denom_pub", GNUNET_JSON_from_data_auto (&h_denom_pub),
							 "withdraw_fee", TALER_JSON_from_amount (&pos->details.withdraw->withdraw_fee),
							 "amount", TALER_JSON_from_amount (&value))));
      }
      break;
    case TALER_EXCHANGEDB_RO_PAYBACK_COIN:
      {
	const struct TALER_EXCHANGEDB_Payback *payback;
	struct TALER_PaybackConfirmationPS pc;
	struct TALER_ExchangePublicKeyP pub;
	struct TALER_ExchangeSignatureP sig;

	payback = pos->details.payback;
	if (0 == (1 & ret))
	  deposit_total = payback->value;
	else
	  if (GNUNET_OK !=
	      TALER_amount_add (&deposit_total,
				&deposit_total,
				&payback->value))
	  {
	    json_decref (json_history);
	    return NULL;
	  }
	ret |= 1;
	pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK);
	pc.purpose.size = htonl (sizeof (struct TALER_PaybackConfirmationPS));
	pc.timestamp = GNUNET_TIME_absolute_hton (payback->timestamp);
	TALER_amount_hton (&pc.payback_amount,
			   &payback->value);
	pc.coin_pub = payback->coin.coin_pub;
	pc.reserve_pub = payback->reserve_pub;
	TEH_KS_sign (&pc.purpose,
		     &pub,
		     &sig);

	GNUNET_assert (0 ==
		       json_array_append_new (json_history,
					      json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
							 "type", "PAYBACK",
							 "exchange_pub", GNUNET_JSON_from_data_auto (&pub),
							 "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
							 "timestamp", GNUNET_JSON_from_time_abs (payback->timestamp),
							 "amount", TALER_JSON_from_amount (&payback->value),
							 "coin_pub", GNUNET_JSON_from_data_auto (&payback->coin.coin_pub))));
      }
      break;
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      {
	struct TALER_ReserveCloseConfirmationPS rcc;
	struct TALER_ExchangePublicKeyP pub;
	struct TALER_ExchangeSignatureP sig;
	struct TALER_Amount value;

	value = pos->details.closing->amount;
	if (0 == (2 & ret))
	{
	  withdraw_total = value;
	}
	else
	{
	  if (GNUNET_OK !=
	      TALER_amount_add (&withdraw_total,
				&withdraw_total,
				&value))
	  {
	    json_decref (json_history);
	    return NULL;
	  }
	}
	ret |= 2;
	rcc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED);
	rcc.purpose.size = htonl (sizeof (struct TALER_ReserveCloseConfirmationPS));
	rcc.timestamp = GNUNET_TIME_absolute_hton (pos->details.closing->execution_date);
	TALER_amount_hton (&rcc.closing_amount,
			   &value);
	TALER_amount_hton (&rcc.closing_fee,
			   &pos->details.closing->closing_fee);
	rcc.reserve_pub = pos->details.closing->reserve_pub;
	TALER_JSON_hash (pos->details.closing->receiver_account_details,
			 &rcc.h_wire);
	rcc.wtid = pos->details.closing->wtid;
	TEH_KS_sign (&rcc.purpose,
		     &pub,
		     &sig);
	GNUNET_assert (0 ==
		       json_array_append_new (json_history,
					      json_pack ("{s:s, s:O, s:o, s:o, s:o, s:o, s:o, s:o}",
							 "type", "CLOSING",
							 "receiver_account_details", pos->details.closing->receiver_account_details,
							 "wtid", GNUNET_JSON_from_data_auto (&pos->details.closing->wtid),
							 "exchange_pub", GNUNET_JSON_from_data_auto (&pub),
							 "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
							 "timestamp", GNUNET_JSON_from_time_abs (pos->details.closing->execution_date),
							 "amount", TALER_JSON_from_amount (&value),
							 "closing_fee", TALER_JSON_from_amount (&pos->details.closing->closing_fee))));
      }
      break;
    }
  }
  if (0 == (1 & ret))
  {
    GNUNET_break (0);
    json_decref (json_history);
    return NULL;
  }
  if (0 == (2 & ret))
  {
    /* did not encounter any withdraw operations, set to zero */
    TALER_amount_get_zero (deposit_total.currency,
                           &withdraw_total);
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (balance,
                             &deposit_total,
                             &withdraw_total))
  {
    GNUNET_break (0);
    json_decref (json_history);
    return NULL;
  }

  return json_history;
}


/**
 * Generate refund conflict failure message. Returns the
 * transaction list @a tl with the details about the conflict.
 *
 * @param connection connection to the client
 * @param tl transaction list showing the conflict
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_refund_conflict (struct MHD_Connection *connection,
                                    const struct TALER_EXCHANGEDB_TransactionList *tl)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_CONFLICT,
                                       "{s:s, s:I, s:o}",
                                       "status", "conflicting refund",
				       "code", (json_int_t) TALER_EC_REFUND_CONFLICT,
                                       "history", compile_transaction_history (tl));
}


/**
 * Generate generic refund failure message. All the details
 * are in the @a response_code.  The body can be empty.
 *
 * @param connection connection to the client
 * @param response_code response code to generate
 * @param ec taler error code to include
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_refund_failure (struct MHD_Connection *connection,
                                   unsigned int response_code,
				   enum TALER_ErrorCode ec)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       response_code,
                                       "{s:s, s:I}",
                                       "status", "refund failure",
				       "code", (json_int_t) ec);
}


/**
 * Generate successful refund confirmation message.
 *
 * @param connection connection to the client
 * @param refund details about the successful refund
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_refund_success (struct MHD_Connection *connection,
                                   const struct TALER_EXCHANGEDB_Refund *refund)
{
  struct TALER_RefundConfirmationPS rc;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  rc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND);
  rc.purpose.size = htonl (sizeof (struct TALER_RefundConfirmationPS));
  rc.h_contract_terms = refund->h_contract_terms;
  rc.coin_pub = refund->coin.coin_pub;
  rc.merchant = refund->merchant_pub;
  rc.rtransaction_id = GNUNET_htonll (refund->rtransaction_id);
  TALER_amount_hton (&rc.refund_amount,
                     &refund->refund_amount);
  TALER_amount_hton (&rc.refund_fee,
                     &refund->refund_fee);
  TEH_KS_sign (&rc.purpose,
               &pub,
               &sig);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:s, s:o, s:o}",
                                       "status", "REFUND_OK",
                                       "sig", GNUNET_JSON_from_data_auto (&sig),
                                       "pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_reserve_status_success (struct MHD_Connection *connection,
                                           const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_balance;
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = compile_reserve_history (rh,
                                          &balance);
  if (NULL == json_history)
    return TEH_RESPONSE_reply_internal_error (connection,
					      TALER_EC_RESERVE_STATUS_DB_ERROR,
                                              "balance calculation failure");
  json_balance = TALER_JSON_from_amount (&balance);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o}",
                                       "balance", json_balance,
                                       "history", json_history);
}


/**
 * Send reserve status information to client with the
 * message that we have insufficient funds for the
 * requested /reserve/withdraw operation.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_reserve_withdraw_insufficient_funds (struct MHD_Connection *connection,
                                                        const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_balance;
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = compile_reserve_history (rh,
                                          &balance);
  if (NULL == json_history)
    return TEH_RESPONSE_reply_internal_error (connection,
					      TALER_EC_WITHDRAW_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                              "balance calculation failure");
  json_balance = TALER_JSON_from_amount (&balance);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s, s:I, s:o, s:o}",
                                       "error", "Insufficient funds",
				       "code", (json_int_t) TALER_EC_WITHDRAW_INSUFFICIENT_FUNDS,
                                       "balance", json_balance,
                                       "history", json_history);
}


/**
 * Send blinded coin information to client.
 *
 * @param connection connection to the client
 * @param collectable blinded coin to return
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_reserve_withdraw_success (struct MHD_Connection *connection,
					     const struct TALER_EXCHANGEDB_CollectableBlindcoin *collectable)
{
  json_t *sig_json;

  sig_json = GNUNET_JSON_from_rsa_signature (collectable->sig.rsa_signature);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o}",
                                       "ev_sig", sig_json);
}


/**
 * Send a response for a failed "/refresh/melt" request.  The
 * transaction history of the given coin demonstrates that the
 * @a residual value of the coin is below the @a requested
 * contribution of the coin for the melt.  Thus, the exchange
 * refuses the melt operation.
 *
 * @param connection the connection to send the response to
 * @param coin_pub public key of the coin
 * @param coin_value original value of the coin
 * @param tl transaction history for the coin
 * @param requested how much this coin was supposed to contribute, including fee
 * @param residual remaining value of the coin (after subtracting @a tl)
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_refresh_melt_insufficient_funds (struct MHD_Connection *connection,
                                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                                    struct TALER_Amount coin_value,
                                                    struct TALER_EXCHANGEDB_TransactionList *tl,
                                                    struct TALER_Amount requested,
                                                    struct TALER_Amount residual)
{
  json_t *history;

  history = compile_transaction_history (tl);
  if (NULL == history)
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_REFRESH_MELT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s, s:I, s:o, s:o, s:o, s:o, s:o}",
                                       "error",
				       "insufficient funds",
				       "code",
				       (json_int_t) TALER_EC_REFRESH_MELT_INSUFFICIENT_FUNDS,
                                       "coin_pub",
                                       GNUNET_JSON_from_data_auto (coin_pub),
                                       "original_value",
                                       TALER_JSON_from_amount (&coin_value),
                                       "residual_value",
                                       TALER_JSON_from_amount (&residual),
                                       "requested_value",
                                       TALER_JSON_from_amount (&requested),
                                       "history",
                                       history);
}


/**
 * Send a response to a "/refresh/melt" request.
 *
 * @param connection the connection to send the response to
 * @param session_hash hash of the refresh session
 * @param noreveal_index which index will the client not have to reveal
 * @return a MHD status code
 */
int
TEH_RESPONSE_reply_refresh_melt_success (struct MHD_Connection *connection,
                                         const struct GNUNET_HashCode *session_hash,
                                         uint16_t noreveal_index)
{
  struct TALER_RefreshMeltConfirmationPS body;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  json_t *sig_json;

  body.purpose.size = htonl (sizeof (struct TALER_RefreshMeltConfirmationPS));
  body.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT);
  body.session_hash = *session_hash;
  body.noreveal_index = htons (noreveal_index);
  body.reserved = htons (0);
  TEH_KS_sign (&body.purpose,
               &pub,
               &sig);
  sig_json = GNUNET_JSON_from_data_auto (&sig);
  GNUNET_assert (NULL != sig_json);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:i, s:o, s:o}",
                                       "noreveal_index", (int) noreveal_index,
                                       "exchange_sig", sig_json,
                                       "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Send a response for "/refresh/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_newcoins number of new coins for which we reveal data
 * @param sigs array of @a num_newcoins signatures revealed
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_refresh_reveal_success (struct MHD_Connection *connection,
                                           unsigned int num_newcoins,
                                           const struct TALER_DenominationSignature *sigs)
{
  int newcoin_index;
  json_t *root;
  json_t *obj;
  json_t *list;
  int ret;

  list = json_array ();
  for (newcoin_index = 0; newcoin_index < num_newcoins; newcoin_index++)
  {
    obj = json_object ();
    json_object_set_new (obj,
			 "ev_sig",
			 GNUNET_JSON_from_rsa_signature (sigs[newcoin_index].rsa_signature));
    GNUNET_assert (0 ==
                   json_array_append_new (list,
                                          obj));
  }
  root = json_object ();
  json_object_set_new (root,
                       "ev_sigs",
                       list);
  ret = TEH_RESPONSE_reply_json (connection,
                                 root,
                                 MHD_HTTP_OK);
  json_decref (root);
  return ret;
}


/**
 * Send a response for a failed "/refresh/reveal", where the
 * revealed value(s) do not match the original commitment.
 *
 * @param connection the connection to send the response to
 * @param session info about session
 * @param commit_coins array of @a num_newcoins committed envelopes at offset @a gamma
 * @param denom_pubs array of @a num_newcoins denomination keys for the new coins
 * @param gamma_tp transfer public key at offset @a gamma
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_refresh_reveal_missmatch (struct MHD_Connection *connection,
                                             const struct TALER_EXCHANGEDB_RefreshSession *session,
                                             const struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins,
                                             const struct TALER_DenominationPublicKey *denom_pubs,
                                             const struct TALER_TransferPublicKeyP *gamma_tp)
{
  json_t *info_new;
  json_t *info_commit_k;
  unsigned int i;

  info_new = json_array ();
  info_commit_k = json_array ();
  for (i=0;i<session->num_newcoins;i++)
  {
    const struct TALER_EXCHANGEDB_RefreshCommitCoin *cc;
    json_t *cc_json;

    GNUNET_assert (0 ==
                   json_array_append_new (info_new,
                                          GNUNET_JSON_from_rsa_public_key (denom_pubs[i].rsa_public_key)));

    cc = &commit_coins[i];
    cc_json = json_pack ("{s:o}",
                         "coin_ev",
                         GNUNET_JSON_from_data (cc->coin_ev,
                                                cc->coin_ev_size));
    GNUNET_assert (0 ==
                   json_array_append_new (info_commit_k,
                                          cc_json));
  }
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_CONFLICT,
                                       "{s:s, s:I, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:i}",
                                       "error", "commitment violation",
				       "code", (json_int_t) TALER_EC_REFRESH_REVEAL_COMMITMENT_VIOLATION,
                                       "coin_sig", GNUNET_JSON_from_data_auto (&session->melt.coin_sig),
                                       "coin_pub", GNUNET_JSON_from_data_auto (&session->melt.coin.coin_pub),
                                       "melt_amount_with_fee", TALER_JSON_from_amount (&session->melt.amount_with_fee),
                                       "melt_fee", TALER_JSON_from_amount (&session->melt.melt_fee),
                                       "newcoin_infos", info_new,
                                       "commit_infos", info_commit_k,
                                       "gamma_tp", GNUNET_JSON_from_data_auto (gamma_tp),
                                       "gamma", (int) session->noreveal_index);
}


/**
 * Send a response for "/refresh/link".
 *
 * @param connection the connection to send the response to
 * @param num_sessions number of sessions the coin was used in
 * @param sessions array of @a num_session entries with
 *                  information for each session
 * @return a MHD result code
 */
int
TEH_RESPONSE_reply_refresh_link_success (struct MHD_Connection *connection,
                                         unsigned int num_sessions,
                                         const struct TEH_RESPONSE_LinkSessionInfo *sessions)
{
  json_t *root;
  json_t *mlist;
  int res;
  unsigned int i;

  mlist = json_array ();
  for (i=0;i<num_sessions;i++)
  {
    const struct TALER_EXCHANGEDB_LinkDataList *pos;
    json_t *list = json_array ();

    for (pos = sessions[i].ldl; NULL != pos; pos = pos->next)
    {
      json_t *obj;

      obj = json_object ();
      json_object_set_new (obj,
                           "denom_pub",
                           GNUNET_JSON_from_rsa_public_key (pos->denom_pub.rsa_public_key));
      json_object_set_new (obj,
                           "ev_sig",
                           GNUNET_JSON_from_rsa_signature (pos->ev_sig.rsa_signature));
      GNUNET_assert (0 ==
                     json_array_append_new (list,
                                            obj));
    }
    root = json_object ();
    json_object_set_new (root,
                         "new_coins",
                         list);
    json_object_set_new (root,
                         "transfer_pub",
                         GNUNET_JSON_from_data_auto (&sessions[i].transfer_pub));
    GNUNET_assert (0 ==
                   json_array_append_new (mlist,
                                          root));
  }
  res = TEH_RESPONSE_reply_json (connection,
                                 mlist,
                                 MHD_HTTP_OK);
  json_decref (mlist);
  return res;
}


/**
 * A merchant asked for details about a deposit, but
 * we do not know anything about the deposit. Generate the
 * 404 reply.
 *
 * @param connection connection to the client
 * @param ec Taler error code
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_transaction_unknown (struct MHD_Connection *connection,
					enum TALER_ErrorCode ec)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s, s:I}",
                                       "error", "Deposit unknown",
				       "code", (json_int_t) ec);
}


/**
 * A merchant asked for details about a deposit, but
 * we did not execute the deposit yet. Generate a 202 reply.
 *
 * @param connection connection to the client
 * @param planned_exec_time planned execution time
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_transfer_pending (struct MHD_Connection *connection,
                                     struct GNUNET_TIME_Absolute planned_exec_time)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_ACCEPTED,
                                       "{s:o}",
                                       "execution_time", GNUNET_JSON_from_time_abs (planned_exec_time));
}


/**
 * A merchant asked for details about a deposit.  Provide
 * them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param h_contract_terms hash of the contract
 * @param h_wire hash of wire account details
 * @param coin_pub public key of the coin
 * @param coin_contribution how much did the coin we asked about
 *        contribute to the total transfer value? (deposit value minus fee)
 * @param wtid raw wire transfer identifier
 * @param exec_time execution time of the wire transfer
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_track_transaction (struct MHD_Connection *connection,
                                      const struct GNUNET_HashCode *h_contract_terms,
                                      const struct GNUNET_HashCode *h_wire,
                                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                      const struct TALER_Amount *coin_contribution,
                                      const struct TALER_WireTransferIdentifierRawP *wtid,
                                      struct GNUNET_TIME_Absolute exec_time)
{
  struct TALER_ConfirmWirePS cw;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  cw.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE);
  cw.purpose.size = htonl (sizeof (struct TALER_ConfirmWirePS));
  cw.h_wire = *h_wire;
  cw.h_contract_terms = *h_contract_terms;
  cw.wtid = *wtid;
  cw.coin_pub = *coin_pub;
  cw.execution_time = GNUNET_TIME_absolute_hton (exec_time);
  TALER_amount_hton (&cw.coin_contribution,
                     coin_contribution);
  TEH_KS_sign (&cw.purpose,
               &pub,
               &sig);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o, s:o, s:o, s:o}",
                                       "wtid", GNUNET_JSON_from_data_auto (wtid),
                                       "execution_time", GNUNET_JSON_from_time_abs (exec_time),
                                       "coin_contribution", TALER_JSON_from_amount (coin_contribution),
                                       "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
                                       "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * A merchant asked for transaction details about a wire transfer.
 * Provide them. Generates the 200 reply.
 *
 * @param connection connection to the client
 * @param total total amount that was transferred
 * @param merchant_pub public key of the merchant
 * @param h_wire destination account
 * @param wire_fee wire fee that was charged
 * @param exec_time execution time of the wire transfer
 * @param wdd_head linked list with details about the combined deposits
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_track_transfer_details (struct MHD_Connection *connection,
                                           const struct TALER_Amount *total,
                                           const struct TALER_MerchantPublicKeyP *merchant_pub,
                                           const struct GNUNET_HashCode *h_wire,
                                           const struct TALER_Amount *wire_fee,
                                           struct GNUNET_TIME_Absolute exec_time,
                                           const struct TEH_TrackTransferDetail *wdd_head)
{
  const struct TEH_TrackTransferDetail *wdd_pos;
  json_t *deposits;
  struct TALER_WireDepositDetailP dd;
  struct GNUNET_HashContext *hash_context;
  struct TALER_WireDepositDataPS wdp;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  GNUNET_TIME_round_abs (&exec_time);
  deposits = json_array ();
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  for (wdd_pos = wdd_head; NULL != wdd_pos; wdd_pos = wdd_pos->next)
  {
    dd.h_contract_terms = wdd_pos->h_contract_terms;
    dd.execution_time = GNUNET_TIME_absolute_hton (exec_time);
    dd.coin_pub = wdd_pos->coin_pub;
    TALER_amount_hton (&dd.deposit_value,
                       &wdd_pos->deposit_value);
    TALER_amount_hton (&dd.deposit_fee,
                       &wdd_pos->deposit_fee);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &dd,
                                     sizeof (struct TALER_WireDepositDetailP));
    GNUNET_assert (0 ==
                   json_array_append_new (deposits,
                                          json_pack ("{s:o, s:o, s:o, s:o}",
                                                     "h_contract_terms", GNUNET_JSON_from_data_auto (&wdd_pos->h_contract_terms),
                                                     "coin_pub", GNUNET_JSON_from_data_auto (&wdd_pos->coin_pub),
                                                     "deposit_value", TALER_JSON_from_amount (&wdd_pos->deposit_value),
                                                     "deposit_fee", TALER_JSON_from_amount (&wdd_pos->deposit_fee))));
  }
  wdp.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_WIRE_DEPOSIT);
  wdp.purpose.size = htonl (sizeof (struct TALER_WireDepositDataPS));
  TALER_amount_hton (&wdp.total,
                     total);
  TALER_amount_hton (&wdp.wire_fee,
                     wire_fee);
  wdp.merchant_pub = *merchant_pub;
  wdp.h_wire = *h_wire;
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &wdp.h_details);
  TEH_KS_sign (&wdp.purpose,
               &pub,
               &sig);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
                                       "total", TALER_JSON_from_amount (total),
                                       "wire_fee", TALER_JSON_from_amount (wire_fee),
                                       "merchant_pub", GNUNET_JSON_from_data_auto (merchant_pub),
                                       "H_wire", GNUNET_JSON_from_data_auto (h_wire),
                                       "execution_time", GNUNET_JSON_from_time_abs (exec_time),
                                       "deposits", deposits,
                                       "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
                                       "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}



/**
 * A wallet asked for /payback, but we do not know anything about the
 * original withdraw operation specified. Generates a 404 reply.
 *
 * @param connection connection to the client
 * @param ec Taler error code
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_payback_unknown (struct MHD_Connection *connection,
                                    enum TALER_ErrorCode ec)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s, s:I}",
                                       "error", "blinded coin unknown",
				       "code", (json_int_t) ec);
}


/**
 * A wallet asked for /payback, return the successful response.
 *
 * @param connection connection to the client
 * @param coin_pub coin for which we are processing the payback request
 * @param reserve_pub public key of the reserve that will receive the payback
 * @param amount the amount we will wire back
 * @param timestamp when did the exchange receive the /payback request
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_payback_success (struct MHD_Connection *connection,
                                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                    const struct TALER_ReservePublicKeyP *reserve_pub,
                                    const struct TALER_Amount *amount,
                                    struct GNUNET_TIME_Absolute timestamp)
{
  struct TALER_PaybackConfirmationPS pc;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK);
  pc.purpose.size = htonl (sizeof (struct TALER_PaybackConfirmationPS));
  pc.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  TALER_amount_hton (&pc.payback_amount,
                     amount);
  pc.coin_pub = *coin_pub;
  pc.reserve_pub = *reserve_pub;
  TEH_KS_sign (&pc.purpose,
               &pub,
               &sig);
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o, s:o, s:o, s:o}",
                                       "reserve_pub", GNUNET_JSON_from_data_auto (reserve_pub),
                                       "timestamp", GNUNET_JSON_from_time_abs (timestamp),
                                       "amount", TALER_JSON_from_amount (amount),
                                       "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
                                       "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}



/* end of taler-exchange-httpd_responses.c */
