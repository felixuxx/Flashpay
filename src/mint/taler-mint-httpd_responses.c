/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_responses.c
 * @brief API for generating the various replies of the mint; these
 *        functions are called TALER_MINT_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler-mint-httpd_responses.h"
#include "taler_util.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler-mint-httpd_keystate.h"


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TALER_MINT_reply_json (struct MHD_Connection *connection,
                       const json_t *json,
                       unsigned int response_code)
{
  struct MHD_Response *resp;
  char *json_str;
  int ret;

  json_str = json_dumps (json, JSON_INDENT(2));
  resp = MHD_create_response_from_buffer (strlen (json_str), json_str,
                                          MHD_RESPMEM_MUST_FREE);
  if (NULL == resp)
    return MHD_NO;
  (void) MHD_add_response_header (resp,
                                  MHD_HTTP_HEADER_CONTENT_TYPE,
                                  "application/json");
  ret = MHD_queue_response (connection, response_code, resp);
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
TALER_MINT_reply_json_pack (struct MHD_Connection *connection,
                            unsigned int response_code,
                            const char *fmt,
                            ...)
{
  json_t *json;
  va_list argp;
  int ret;

  va_start (argp, fmt);
  json = json_vpack_ex (NULL, 0, fmt, argp);
  va_end (argp);
  if (NULL == json)
    return MHD_NO;
  ret = TALER_MINT_reply_json (connection,
                               json,
                               response_code);
  json_decref (json);
  return ret;
}


/**
 * Send a response indicating an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TALER_MINT_reply_arg_invalid (struct MHD_Connection *connection,
                              const char *param_name)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{s:s, s:s}",
                                     "error", "invalid parameter",
                                     "parameter", param_name);
}


/**
 * Send a response indicating an invalid coin.  (I.e. the signature
 * over the public key of the coin does not match a valid signing key
 * of this mint).
 *
 * @param connection the MHD connection to use
 * @return MHD result code
 */
int
TALER_MINT_reply_coin_invalid (struct MHD_Connection *connection)
{
  /* TODO: may want to be more precise in the future and
     distinguish bogus signatures from bogus public keys. */
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     "{s:s}",
                                     "error", "Coin is not valid");
}


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TALER_MINT_reply_arg_missing (struct MHD_Connection *connection,
                              const char *param_name)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{ s:s, s:s}",
                                     "error", "missing parameter",
                                     "parameter", param_name);
}


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TALER_MINT_reply_internal_error (struct MHD_Connection *connection,
                                 const char *hint)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{s:s, s:s}",
                                     "error", "internal error",
                                     "hint", hint);
}


/**
 * Send a response indicating an external error.
 *
 * @param connection the MHD connection to use
 * @param hint hint about the error's nature
 * @return a MHD result code
 */
int
TALER_MINT_reply_external_error (struct MHD_Connection *connection,
                                 const char *hint)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{s:s, s:s}",
                                     "error", "client error",
                                     "hint", hint);
}


/**
 * Send a response indicating an error committing a
 * transaction (concurrent interference).
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_commit_error (struct MHD_Connection *connection)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{s:s}",
                                     "error", "commit failure");
}


/**
 * Send a response indicating a failure to talk to the Mint's
 * database.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_internal_db_error (struct MHD_Connection *connection)
{
  return TALER_MINT_reply_internal_error (connection,
                                          "Failed to connect to database");
}


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_request_too_large (struct MHD_Connection *connection)
{
  struct MHD_Response *resp;
  int ret;

  resp = MHD_create_response_from_buffer (0,
                                          NULL,
                                          MHD_RESPMEM_PERSISTENT);
  if (NULL == resp)
    return MHD_NO;
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
TALER_MINT_reply_invalid_json (struct MHD_Connection *connection)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{s:s}",
                                     "error",
                                     "invalid json");
}


/**
 * Send confirmation of deposit success to client.  This function
 * will create a signed message affirming the given information
 * and return it to the client.  By this, the mint affirms that
 * the coin had sufficient (residual) value for the specified
 * transaction and that it will execute the requested deposit
 * operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param h_wire hash of wire details
 * @param h_contract hash of contract details
 * @param transaction_id transaction ID
 * @param merchant merchant public key
 * @param amount fraction of coin value to deposit
 * @return MHD result code
 */
int
TALER_MINT_reply_deposit_success (struct MHD_Connection *connection,
                                  const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                                  const struct GNUNET_HashCode *h_wire,
                                  const struct GNUNET_HashCode *h_contract,
                                  uint64_t transaction_id,
                                  const struct GNUNET_CRYPTO_EddsaPublicKey *merchant,
                                  const struct TALER_Amount *amount)
{
  struct TALER_DepositConfirmation dc;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  json_t *sig_json;
  int ret;

  dc.purpose.purpose = htonl (TALER_SIGNATURE_MINT_DEPOSIT);
  dc.purpose.size = htonl (sizeof (struct TALER_DepositConfirmation));
  dc.h_contract = *h_contract;
  dc.h_wire = *h_wire;
  dc.transaction_id = GNUNET_htonll (transaction_id);
  dc.amount = TALER_amount_hton (*amount);
  dc.coin_pub = *coin_pub;
  dc.merchant = *merchant;
  TALER_MINT_keys_sign (&dc.purpose,
                        &sig);
  sig_json = TALER_JSON_from_eddsa_sig (&dc.purpose, &sig);
  ret = TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:s, s:o}",
                                    "status", "DEPOSIT_OK",
                                    "signature", sig_json);
  json_decref (sig_json);
  return ret;
}

/**
 * Compile the transaction history of a coin into a JSON object.
 *
 * @param tl transaction history to JSON-ify
 * @return json representation of the @a rh
 */
static json_t *
compile_transaction_history (const struct TALER_MINT_DB_TransactionList *tl)
{
  json_t *transaction;
  const char *type;
  struct TALER_Amount value;
  json_t *history;
  const struct TALER_MINT_DB_TransactionList *pos;

  history = json_array ();
  for (pos = tl; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_MINT_DB_TT_DEPOSIT:
      {
        struct TALER_DepositRequest dr;
        const struct Deposit *deposit = pos->details.deposit;

        type = "deposit";
        value = deposit->amount;
        dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_DEPOSIT);
        dr.purpose.size = htonl (sizeof (struct TALER_DepositRequest));
        dr.h_contract = deposit->h_contract;
        dr.h_wire = deposit->h_wire;
        dr.transaction_id = GNUNET_htonll (deposit->transaction_id);
        dr.amount = TALER_amount_hton (deposit->amount);
        dr.coin_pub = deposit->coin.coin_pub;
        transaction = TALER_JSON_from_ecdsa_sig (&dr.purpose,
                                                 &deposit->csig);
        break;
      }
    case TALER_MINT_DB_TT_REFRESH_MELT:
      {
        struct RefreshMeltCoinSignature ms;
        const struct RefreshMelt *melt = pos->details.melt;

        type = "melt";
        value = melt->amount;
        ms.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_MELT_COIN);
        ms.purpose.size = htonl (sizeof (struct RefreshMeltCoinSignature));
        ms.melt_hash = melt->melt_hash;
        ms.amount = TALER_amount_hton (melt->amount);
        ms.coin_pub = melt->coin.coin_pub;
        transaction = TALER_JSON_from_ecdsa_sig (&ms.purpose,
                                                 &melt->coin_sig);
      }
      break;
    case TALER_MINT_DB_TT_LOCK:
      {
        type = "lock";
        value = pos->details.lock->amount;
        transaction = NULL;
        GNUNET_break (0); /* #3625: Lock NOT implemented! */
        break;
      }
    default:
      GNUNET_assert (0);
    }
    json_array_append_new (history,
                           json_pack ("{s:s, s:o}",
                                      "type", type,
                                      "amount", TALER_JSON_from_amount (value),
                                      "signature", transaction));
  }
  return history;
}


/**
 * Send proof that a /withdraw request is invalid to client.  This
 * function will create a message with all of the operations affecting
 * the coin that demonstrate that the coin has insufficient value.
 *
 * @param connection connection to the client
 * @param tl transaction list to use to build reply
 * @return MHD result code
 */
int
TALER_MINT_reply_deposit_insufficient_funds (struct MHD_Connection *connection,
                                             const struct TALER_MINT_DB_TransactionList *tl)
{
  json_t *history;

  history = compile_transaction_history (tl);
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_FORBIDDEN,
                                     "{s:s, s:o}",
                                     "error", "insufficient funds",
                                     "history", history);
}


/**
 * Compile the history of a reserve into a JSON object
 * and calculate the total balance.
 *
 * @param rh reserve history to JSON-ify
 * @param balance[OUT] set to current reserve balance
 * @return json representation of the @a rh
 */
static json_t *
compile_reserve_history (const struct ReserveHistory *rh,
                         struct TALER_Amount *balance)
{
  struct TALER_Amount deposit_total;
  struct TALER_Amount withdraw_total;
  struct TALER_Amount value;
  json_t *json_history;
  json_t *transaction;
  int ret;
  const struct ReserveHistory *pos;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct MintKeyState *key_state;
  struct TALER_WithdrawRequest wr;

  json_history = json_array ();
  ret = 0;
  for (pos = rh; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_MINT_DB_RO_BANK_TO_MINT:
      if (0 == ret)
        deposit_total = pos->details.bank->amount;
      else
        deposit_total = TALER_amount_add (deposit_total,
                                          pos->details.bank->amount);
      ret = 1;
      json_array_append_new (json_history,
                             json_pack ("{s:s, s:o, s:o}",
                                        "type", "DEPOSIT",
                                        "wire", pos->details.bank->wire,
                                        "amount", TALER_JSON_from_amount (pos->details.bank->amount)));
      break;
    case TALER_MINT_DB_RO_WITHDRAW_COIN:
      break;
    }
  }

  key_state = TALER_MINT_key_state_acquire ();
  ret = 0;
  for (pos = rh; NULL != pos; pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_MINT_DB_RO_BANK_TO_MINT:
      break;
    case TALER_MINT_DB_RO_WITHDRAW_COIN:

      dki = TALER_MINT_get_denom_key (key_state,
                                      pos->details.withdraw->denom_pub);
      value = TALER_amount_ntoh (dki->issue.value);
      if (0 == ret)
        withdraw_total = value;
      else
        withdraw_total = TALER_amount_add (withdraw_total,
                                           value);
      ret = 1;
      wr.purpose.purpose = htonl (TALER_SIGNATURE_WITHDRAW);
      wr.purpose.size = htonl (sizeof (struct TALER_WithdrawRequest));
      wr.reserve_pub = pos->details.withdraw->reserve_pub;
      GNUNET_CRYPTO_rsa_public_key_hash (pos->details.withdraw->denom_pub,
                                         &wr.h_denomination_pub);
      wr.h_coin_envelope = pos->details.withdraw->h_coin_envelope;

      transaction = TALER_JSON_from_eddsa_sig (&wr.purpose,
                                               &pos->details.withdraw->reserve_sig);

      json_array_append_new (json_history,
                             json_pack ("{s:s, s:o, s:o}",
                                        "type", "WITHDRAW",
                                        "signature", transaction,
                                        "amount", TALER_JSON_from_amount (value)));

      break;
    }
  }
  TALER_MINT_key_state_release (key_state);

  *balance = TALER_amount_subtract (deposit_total,
                                    withdraw_total);
  return json_history;
}


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_status_success (struct MHD_Connection *connection,
                                          const struct ReserveHistory *rh)
{
  json_t *json_balance;
  json_t *json_history;
  struct TALER_Amount balance;
  int ret;

  json_history = compile_reserve_history (rh,
                                          &balance);
  json_balance = TALER_JSON_from_amount (balance);
  ret = TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o, s:o}",
                                    "balance", json_balance,
                                    "history", json_history);
  json_decref (json_history);
  json_decref (json_balance);
  return ret;
}


/**
 * Send reserve status information to client with the
 * message that we have insufficient funds for the
 * requested /withdraw/sign operation.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_sign_insufficient_funds (struct MHD_Connection *connection,
                                                   const struct ReserveHistory *rh)
{
  json_t *json_balance;
  json_t *json_history;
  struct TALER_Amount balance;
  int ret;

  json_history = compile_reserve_history (rh,
                                          &balance);
  json_balance = TALER_JSON_from_amount (balance);
  ret = TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_PAYMENT_REQUIRED,
                                    "{s:s, s:o, s:o}",
                                    "error", "Insufficient funds"
                                    "balance", json_balance,
                                    "history", json_history);
  json_decref (json_history);
  json_decref (json_balance);
  return ret;
}


/**
 * Send blinded coin information to client.
 *
 * @param connection connection to the client
 * @param collectable blinded coin to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_sign_success (struct MHD_Connection *connection,
                                        const struct CollectableBlindcoin *collectable)
{
  json_t *sig_json;
  size_t sig_buf_size;
  char *sig_buf;
  int ret;

  sig_buf_size = GNUNET_CRYPTO_rsa_signature_encode (collectable->sig,
                                                     &sig_buf);
  sig_json = TALER_JSON_from_data (sig_buf,
                                   sig_buf_size);
  GNUNET_free (sig_buf);
  ret = TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:o}",
                                    "ev_sig", sig_json);
  json_decref (sig_json);
  return ret;
}


/**
 * Send a response for a failed "/refresh/melt" request.  The
 * transaction history of the given coin demonstrates that the
 * @a residual value of the coin is below the @a requested
 * contribution of the coin for the melt.  Thus, the mint
 * refuses the melt operation.
 *
 * @param connection the connection to send the response to
 * @param coin_pub public key of the coin
 * @param coin_value original value of the coin
 * @param tl transaction history for the coin
 * @param requested how much this coin was supposed to contribute
 * @param residual remaining value of the coin (after subtracting @a tl)
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_melt_insufficient_funds (struct MHD_Connection *connection,
                                                  const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                                                  struct TALER_Amount coin_value,
                                                  struct TALER_MINT_DB_TransactionList *tl,
                                                  struct TALER_Amount requested,
                                                  struct TALER_Amount residual)
{
  json_t *history;

  history = compile_transaction_history (tl);
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_NOT_FOUND,
                                     "{s:s, s:o, s:o, s:o, s:o, s:o}",
                                     "error", "insufficient funds",
                                     "coin-pub", TALER_JSON_from_data (coin_pub,
                                                                       sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey)),
                                     "original-value", TALER_JSON_from_amount (coin_value),
                                     "residual-value", TALER_JSON_from_amount (residual),
                                     "requested-value", TALER_JSON_from_amount (requested),
                                     "history", history);
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
TALER_MINT_reply_refresh_melt_success (struct MHD_Connection *connection,
                                       const struct GNUNET_HashCode *session_hash,
                                       uint16_t noreveal_index)
{
  struct RefreshMeltResponseSignatureBody body;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  json_t *sig_json;
  int ret;

  body.purpose.size = htonl (sizeof (struct RefreshMeltResponseSignatureBody));
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_MELT_RESPONSE);
  body.session_hash = *session_hash;
  body.noreveal_index = htons (noreveal_index);
  TALER_MINT_keys_sign (&body.purpose,
                        &sig);
  sig_json = TALER_JSON_from_eddsa_sig (&body.purpose,
                                        &sig);
  GNUNET_assert (NULL != sig_json);
  ret = TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_OK,
                                     "{s:i, s:o}",
                                     "noreveal_index", (int) noreveal_index,
                                     "signature", sig_json);
  json_decref (sig_json);
  return ret;
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
TALER_MINT_reply_refresh_reveal_success (struct MHD_Connection *connection,
                                         unsigned int num_newcoins,
                                         struct GNUNET_CRYPTO_rsa_Signature **sigs)
{
  int newcoin_index;
  json_t *root;
  json_t *list;
  char *buf;
  size_t buf_size;
  int ret;

  root = json_object ();
  list = json_array ();
  json_object_set_new (root, "ev_sigs", list);
  for (newcoin_index = 0; newcoin_index < num_newcoins; newcoin_index++)
  {
    buf_size = GNUNET_CRYPTO_rsa_signature_encode (sigs[newcoin_index],
                                                   &buf);
    json_array_append_new (list,
                           TALER_JSON_from_data (buf,
                                                 buf_size));
    GNUNET_free (buf);
  }
  ret = TALER_MINT_reply_json (connection,
                               root,
                               MHD_HTTP_OK);
  json_decref (root);
  return ret;
}


/**
 * Send a response for a failed "/refresh/reveal", where the
 * revealed value(s) do not match the original commitment.
 *
 * FIXME: should also include the client's signature over
 * the original reveal operation and the data that was signed
 * over eventually... (#3712)
 *
 * @param connection the connection to send the response to
 * @param off offset in the array of kappa-commitments where
 *            the missmatch was detected
 * @param j index of the coin for which the missmatch was
 *            detected
 * @param missmatch_object name of the object that was
 *            bogus (i.e. "transfer key").
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_reveal_missmatch (struct MHD_Connection *connection,
					   unsigned int off,
					   unsigned int j,
					   const char *missmatch_object)
{
  return TALER_MINT_reply_json_pack (connection,
				     MHD_HTTP_BAD_REQUEST,
				     "{s:s, s:i, s:i, s:s}",
				     "error", "commitment violation",
				     "offset", (int) off,
				     "index", (int) j,
				     "object", missmatch_object);
}


/**
 * Send a response for "/refresh/link".
 *
 * @param connection the connection to send the response to
 * @param transfer_pub transfer public key
 * @param shared_secret_enc encrypted shared secret
 * @param ldl linked list with link data
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_link_success (struct MHD_Connection *connection,
                                       const struct GNUNET_CRYPTO_EcdsaPublicKey *transfer_pub,
                                       const struct TALER_EncryptedLinkSecret *shared_secret_enc,
                                       const struct LinkDataList *ldl)
{
  const struct LinkDataList *pos;
  json_t *root;
  json_t *list;
  int res;

  list = json_array ();
  for (pos = ldl; NULL != pos; pos = pos->next)
  {
    json_t *obj;
    char *buf;
    size_t buf_len;

    obj = json_object ();
    json_object_set_new (obj, "link_enc",
                         TALER_JSON_from_data (ldl->link_data_enc->coin_priv_enc,
                                               sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey) +
                                               ldl->link_data_enc->blinding_key_enc_size));
    buf_len = GNUNET_CRYPTO_rsa_public_key_encode (ldl->denom_pub,
                                                   &buf);
    json_object_set_new (obj, "denom_pub",
                         TALER_JSON_from_data (buf,
                                               buf_len));
    GNUNET_free (buf);
    buf_len = GNUNET_CRYPTO_rsa_signature_encode (ldl->ev_sig,
                                                  &buf);
    json_object_set_new (obj, "ev_sig",
                         TALER_JSON_from_data (buf,
                                               buf_len));
    GNUNET_free (buf);
    json_array_append_new (list, obj);
  }

  root = json_object ();
  json_object_set_new (root,
                       "new_coins",
                       list);
  json_object_set_new (root,
                       "transfer_pub",
                       TALER_JSON_from_data (transfer_pub,
                                             sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)));
  json_object_set_new (root,
                       "secret_enc",
                       TALER_JSON_from_data (shared_secret_enc,
                                             sizeof (struct TALER_EncryptedLinkSecret)));
  res = TALER_MINT_reply_json (connection,
                               root,
                               MHD_HTTP_OK);
  json_decref (root);
  return res;
}


/* end of taler-mint-httpd_responses.c */
