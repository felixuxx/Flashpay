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
 * @brief API for generating genric replies of the exchange; these
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
 *
 * Note that right now we're ignoring q-values, which is technically
 * not correct, and also do not support "*" anywhere but in a line by
 * itself.  This should eventually be fixed, see also
 * https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
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
  if (0 == strcmp (de,
                   "*"))
    return MHD_YES;
  if ( ( (de == ae) ||
	 ( de[-1] == ',') ||
	 (de[-1] == ' ') ) &&
       ( (de[strlen ("deflate")] == '\0') ||
	 (de[strlen ("deflate")] == ',') ||
         (de[strlen ("deflate")] == ';') ) )
    return MHD_YES;
  return MHD_NO;
}


/**
 * Try to compress a response body.  Updates @a buf and @a buf_size.
 *
 * @param[in,out] buf pointer to body to compress
 * @param[in,out] buf_size pointer to initial size of @a buf
 * @return #MHD_YES if @a buf was compressed
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
 * Compile the transaction history of a coin into a JSON object.
 *
 * @param tl transaction history to JSON-ify
 * @return json representation of the @a rh, NULL on error
 */
json_t *
TEH_RESPONSE_compile_transaction_history (const struct TALER_EXCHANGEDB_TransactionList *tl)
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
        ms.rc = melt->session.rc;
        TALER_amount_hton (&ms.amount_with_fee,
                           &melt->session.amount_with_fee);
        TALER_amount_hton (&ms.melt_fee,
                           &melt->melt_fee);
        ms.coin_pub = melt->session.coin.coin_pub;
	/* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                        &ms.purpose,
                                        &melt->session.coin_sig.eddsa_signature,
                                        &melt->session.coin.coin_pub.eddsa_pub))
	{
	  GNUNET_break (0);
	  json_decref (history);
	  return NULL;
	}

	GNUNET_assert (0 ==
		       json_array_append_new (history,
					      json_pack ("{s:s, s:o, s:o, s:o, s:o}",
							 "type", "MELT",
							 "amount", TALER_JSON_from_amount (&melt->session.amount_with_fee),
							 "melt_fee", TALER_JSON_from_amount (&melt->melt_fee),
							 "rc", GNUNET_JSON_from_data_auto (&melt->session.rc),
							 "coin_sig", GNUNET_JSON_from_data_auto (&melt->session.coin_sig))));
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
        if (GNUNET_OK !=
	    TEH_KS_sign (&pc.purpose,
			 &epub,
			 &esig))
	{
	  GNUNET_break (0);
	  json_decref (history);
	  return NULL;
	}
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

  history = TEH_RESPONSE_compile_transaction_history (tl);
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
json_t *
TEH_RESPONSE_compile_reserve_history (const struct TALER_EXCHANGEDB_ReserveHistory *rh,
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
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      ret |= 1;
      GNUNET_assert (0 ==
                     json_array_append_new (json_history,
                                            json_pack ("{s:s, s:O, s:o, s:o}",
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
            GNUNET_break (0);
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
            GNUNET_break (0);
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
	if (GNUNET_OK !=
	    TEH_KS_sign (&pc.purpose,
			 &pub,
			 &sig))
	{
	  GNUNET_break (0);
	  json_decref (json_history);
	  return NULL;
	}

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
	if (GNUNET_OK !=
            TALER_JSON_hash (pos->details.closing->receiver_account_details,
                             &rcc.h_wire))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
	rcc.wtid = pos->details.closing->wtid;
	if (GNUNET_OK !=
	    TEH_KS_sign (&rcc.purpose,
			 &pub,
			 &sig))
	{
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
	}
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
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (deposit_total.currency,
                                          &withdraw_total));
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


/* end of taler-exchange-httpd_responses.c */
