/*
  This file is part of TALER
  Copyright (C) 2014-2017 GNUnet e.V.

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
 * @file taler-exchange-httpd_reserve_withdraw.c
 * @brief Handle /reserve/withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler-exchange-httpd_reserve_withdraw.h"
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Perform RSA signature before checking with the database?
 * Reduces time spent in transaction, but may cause us to
 * waste CPU time if DB check fails.
 */
#define OPTIMISTIC_SIGN 1


/**
 * Send reserve status information to client with the
 * message that we have insufficient funds for the
 * requested /reserve/withdraw operation.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
static int
reply_reserve_withdraw_insufficient_funds (struct MHD_Connection *connection,
					   const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_balance;
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = TEH_RESPONSE_compile_reserve_history (rh,
						       &balance);
  if ((NULL == json_history)
      /* Address the case where the ptr is not null, but
       * it fails "internally" to dump as string (= corrupted).  */
      || (0 == json_dumpb (json_history, NULL, 0, 0)))
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
static int
reply_reserve_withdraw_success (struct MHD_Connection *connection,
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
 * Context for #withdraw_transaction.
 */
struct WithdrawContext
{
  /**
   * Details about the withdrawal request.
   */
  struct TALER_WithdrawRequestPS wsrd;

  /**
   * Value of the coin plus withdraw fee.
   */
  struct TALER_Amount amount_required;

  /**
   * Denomination public key.
   */
  struct TALER_DenominationPublicKey denomination_pub;

  /**
   * Signature over the request.
   */
  struct TALER_ReserveSignatureP signature;

  /**
   * Blinded planchet.
   */
  char *blinded_msg;

  /**
   * Key state to use to inspect previous withdrawal values.
   */
  struct TEH_KS_StateHandle *key_state;

  /**
   * Number of bytes in @e blinded_msg.
   */
  size_t blinded_msg_len;

  /**
   * Details about denomination we are about to withdraw.
   */
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

  /**
   * Set to the resulting signed coin data to be returned to the client.
   */
  struct TALER_EXCHANGEDB_CollectableBlindcoin collectable;

};


/**
 * Function implementing /reserve/withdraw transaction.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * Note that "wc->collectable.sig" may already be set before entering
 * this function, either because OPTIMISTIC_SIGN was used and we signed
 * before entering the transaction, or because this function is run
 * twice (!) by #TEH_DB_run_transaction() and the first time created
 * the signature and then failed to commit.  Furthermore, we may get
 * a 2nd correct signature briefly if "get_withdraw_info" suceeds and
 * finds one in the DB.  To avoid signing twice, the function may
 * return a valid signature in "wc->collectable.sig" even if it failed.
 * The caller must thus free the signature in either case.
 *
 * @param cls a `struct WithdrawContext *`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
withdraw_transaction (void *cls,
		      struct MHD_Connection *connection,
		      struct TALER_EXCHANGEDB_Session *session,
		      int *mhd_ret)
{
  struct WithdrawContext *wc = cls;
  struct TALER_EXCHANGEDB_Reserve r;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount fee_withdraw;
  struct TALER_DenominationSignature denom_sig;

#if OPTIMISTIC_SIGN
  /* store away optimistic signature to protect
     it from being overwritten by get_withdraw_info */
  denom_sig = wc->collectable.sig;
  wc->collectable.sig.rsa_signature = NULL;
#endif
  qs = TEH_plugin->get_withdraw_info (TEH_plugin->cls,
				      session,
				      &wc->wsrd.h_coin_envelope,
				      &wc->collectable);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_WITHDRAW_DB_FETCH_ERROR);
    wc->collectable.sig = denom_sig;
    return qs;
  }

  /* Don't sign again if we have already signed the coin */
  if (1 == qs)
  {
#if OPTIMISTIC_SIGN
    GNUNET_CRYPTO_rsa_signature_free (denom_sig.rsa_signature);
#endif
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  GNUNET_assert (0 == qs);
  wc->collectable.sig = denom_sig;



  /* Check if balance is sufficient */
  r.pub = wc->wsrd.reserve_pub;
  qs = TEH_plugin->reserve_get (TEH_plugin->cls,
                                session,
                                &r);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_WITHDRAW_DB_FETCH_ERROR);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TEH_RESPONSE_reply_arg_unknown (connection,
					       TALER_EC_WITHDRAW_RESERVE_UNKNOWN,
					       "reserve_pub");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (0 < TALER_amount_cmp (&wc->amount_required,
                            &r.balance))
  {
    struct TALER_EXCHANGEDB_ReserveHistory *rh;

    GNUNET_break_op (0);
    qs = TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                          session,
                                          &wc->wsrd.reserve_pub,
                                          &rh);
    if (0 >= qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
        *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                         TALER_EC_WITHDRAW_DB_FETCH_ERROR);
      return qs;
    }
    *mhd_ret = reply_reserve_withdraw_insufficient_funds (connection,
							  rh);
    TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                      rh);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Balance is good, sign the coin! */
#if !OPTIMISTIC_SIGN
  if (NULL == wc->collectable.sig.rsa_signature)
  {
    wc->collectable.sig.rsa_signature
      = GNUNET_CRYPTO_rsa_sign_blinded (wc->dki->denom_priv.rsa_private_key,
                                        wc->blinded_msg,
                                        wc->blinded_msg_len);
    if (NULL == wc->collectable.sig.rsa_signature)
    {
      GNUNET_break (0);
      *mhd_ret = TEH_RESPONSE_reply_internal_error (connection,
                                                    TALER_EC_WITHDRAW_SIGNATURE_FAILED,
                                                    "Internal error");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
#endif
  TALER_amount_ntoh (&fee_withdraw,
                     &wc->dki->issue.properties.fee_withdraw);
  wc->collectable.denom_pub = wc->denomination_pub;
  wc->collectable.amount_with_fee = wc->amount_required;
  wc->collectable.withdraw_fee = fee_withdraw;
  wc->collectable.reserve_pub = wc->wsrd.reserve_pub;
  wc->collectable.h_coin_envelope = wc->wsrd.h_coin_envelope;
  wc->collectable.reserve_sig = wc->signature;
  qs = TEH_plugin->insert_withdraw_info (TEH_plugin->cls,
					 session,
					 &wc->collectable);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_WITHDRAW_DB_STORE_ERROR);
    return qs;
  }
  return qs;
}


/**
 * Handle a "/reserve/withdraw" request.  Parses the "reserve_pub"
 * EdDSA key of the reserve and the requested "denom_pub" which
 * specifies the key/value of the coin to be withdrawn, and checks
 * that the signature "reserve_sig" makes this a valid withdrawal
 * request from the specified reserve.  If so, the envelope
 * with the blinded coin "coin_ev" is passed down to execute the
 * withdrawl operation.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_RESERVE_handler_reserve_withdraw (struct TEH_RequestHandler *rh,
                                      struct MHD_Connection *connection,
                                      void **connection_cls,
                                      const char *upload_data,
                                      size_t *upload_data_size)
{
  struct WithdrawContext wc;
  json_t *root;
  int res;
  int mhd_ret;
  struct TALER_Amount amount;
  struct TALER_Amount fee_withdraw;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("coin_ev",
                              (void **) &wc.blinded_msg,
                              &wc.blinded_msg_len),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &wc.wsrd.reserve_pub),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &wc.signature),
    TALER_JSON_spec_denomination_public_key ("denom_pub",
                                             &wc.denomination_pub),
    GNUNET_JSON_spec_end ()
  };

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;
  res = TEH_PARSE_json_data (connection,
                             root,
                             spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  wc.key_state = TEH_KS_acquire ();
  if (NULL == wc.key_state)
  {
    TALER_LOG_ERROR ("Lacking keys to operate\n");
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                              "no keys");
  }
  wc.dki = TEH_KS_denomination_key_lookup (wc.key_state,
					   &wc.denomination_pub,
					   TEH_KS_DKU_WITHDRAW);
  if (NULL == wc.dki)
  {
    GNUNET_JSON_parse_free (spec);
    TEH_KS_release (wc.key_state);
    return TEH_RESPONSE_reply_arg_unknown (connection,
					   TALER_EC_WITHDRAW_DENOMINATION_KEY_NOT_FOUND,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&amount,
                     &wc.dki->issue.properties.value);
  TALER_amount_ntoh (&fee_withdraw,
                     &wc.dki->issue.properties.fee_withdraw);
  if (GNUNET_OK !=
      TALER_amount_add (&wc.amount_required,
			&amount,
			&fee_withdraw))
  {
    GNUNET_JSON_parse_free (spec);
    TEH_KS_release (wc.key_state);
    return TEH_RESPONSE_reply_internal_error (connection,
					      TALER_EC_WITHDRAW_AMOUNT_FEE_OVERFLOW,
					      "amount overflow for value plus withdraw fee");
  }
  TALER_amount_hton (&wc.wsrd.amount_with_fee,
                     &wc.amount_required);
  TALER_amount_hton (&wc.wsrd.withdraw_fee,
                     &fee_withdraw);
  /* verify signature! */
  wc.wsrd.purpose.size
    = htonl (sizeof (struct TALER_WithdrawRequestPS));
  wc.wsrd.purpose.purpose
    = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  GNUNET_CRYPTO_rsa_public_key_hash (wc.denomination_pub.rsa_public_key,
                                     &wc.wsrd.h_denomination_pub);
  GNUNET_CRYPTO_hash (wc.blinded_msg,
                      wc.blinded_msg_len,
                      &wc.wsrd.h_coin_envelope);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wc.wsrd.purpose,
                                  &wc.signature.eddsa_signature,
                                  &wc.wsrd.reserve_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Client supplied invalid signature for /reserve/withdraw request\n");
    GNUNET_JSON_parse_free (spec);
    TEH_KS_release (wc.key_state);
    return TEH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                                 "reserve_sig");
  }

#if OPTIMISTIC_SIGN
  /* Sign before transaction! */
  wc.collectable.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_sign_blinded (wc.dki->denom_priv.rsa_private_key,
                                      wc.blinded_msg,
                                      wc.blinded_msg_len);
  if (NULL == wc.collectable.sig.rsa_signature)
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    TEH_KS_release (wc.key_state);
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_WITHDRAW_SIGNATURE_FAILED,
                                              "Internal error");
  }
#endif

  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "run reserve withdraw",
			      &mhd_ret,
			      &withdraw_transaction,
			      &wc))
  {
    TEH_KS_release (wc.key_state);
    /* Even if #withdraw_transaction() failed, it may have created a signature
       (or we might have done it optimistically above). */
    if (NULL != wc.collectable.sig.rsa_signature)
      GNUNET_CRYPTO_rsa_signature_free (wc.collectable.sig.rsa_signature);
    GNUNET_JSON_parse_free (spec);
    return mhd_ret;
  }
  TEH_KS_release (wc.key_state);
  GNUNET_JSON_parse_free (spec);

  mhd_ret = reply_reserve_withdraw_success (connection,
					    &wc.collectable);
  GNUNET_CRYPTO_rsa_signature_free (wc.collectable.sig.rsa_signature);
  return mhd_ret;
}


/* end of taler-exchange-httpd_reserve_withdraw.c */
