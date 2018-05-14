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
 * @file taler-exchange-httpd_refresh_melt.c
 * @brief Handle /refresh/melt requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_refresh_melt.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


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
static int
reply_refresh_melt_insufficient_funds (struct MHD_Connection *connection,
				       const struct TALER_CoinSpendPublicKeyP *coin_pub,
				       struct TALER_Amount coin_value,
				       struct TALER_EXCHANGEDB_TransactionList *tl,
				       const struct TALER_Amount *requested,
				       const struct TALER_Amount *residual)
{
  json_t *history;

  history = TEH_RESPONSE_compile_transaction_history (tl);
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
                                       TALER_JSON_from_amount (residual),
                                       "requested_value",
                                       TALER_JSON_from_amount (requested),
                                       "history",
                                       history);
}


/**
 * Send a response to a "/refresh/melt" request.
 *
 * @param connection the connection to send the response to
 * @param rc value the client commited to
 * @param noreveal_index which index will the client not have to reveal
 * @return a MHD status code
 */
static int
reply_refresh_melt_success (struct MHD_Connection *connection,
			    const struct TALER_RefreshCommitmentP *rc,
			    uint32_t noreveal_index)
{
  struct TALER_RefreshMeltConfirmationPS body;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  json_t *sig_json;

  body.purpose.size = htonl (sizeof (struct TALER_RefreshMeltConfirmationPS));
  body.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT);
  body.rc = *rc;
  body.noreveal_index = htonl (noreveal_index);
  if (GNUNET_OK !=
      TEH_KS_sign (&body.purpose,
		   &pub,
		   &sig))
  {
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                              "no keys");
  }
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
 * Context for the /refresh/melt operation.
 */
struct RefreshMeltContext
{

  /**
   * noreveal_index is only initialized during
   * #refresh_melt_transaction().
   */
  struct TALER_EXCHANGEDB_RefreshSession refresh_session;

  /**
   * Information about the @e coin's denomination.
   */
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

};


/**
 * Check that the coin has sufficient funds left for the selected
 * melt operation.
 *
 * @param connection the connection to send errors to
 * @param session the database connection
 * @param[in,out] rmc melt context
 * @param[out] mhd_ret status code to return to MHD on hard error
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
refresh_check_melt (struct MHD_Connection *connection,
                    struct TALER_EXCHANGEDB_Session *session,
		    struct RefreshMeltContext *rmc,
		    int *mhd_ret)
{
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_Amount coin_value;
  struct TALER_Amount spent;
  enum GNUNET_DB_QueryStatus qs;

  TALER_amount_ntoh (&coin_value,
                     &rmc->dki->issue.properties.value);
  /* Start with cost of this melt transaction */
  spent = rmc->refresh_session.amount_with_fee;

  /* add historic transaction costs of this coin */
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          session,
                                          &rmc->refresh_session.coin.coin_pub,
					  &tl);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_REFRESH_MELT_DB_FETCH_ERROR);
    return qs;
  }
  if (GNUNET_OK !=
      TEH_DB_calculate_transaction_list_totals (tl,
						&spent,
						&spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						     TALER_EC_REFRESH_MELT_COIN_HISTORY_COMPUTATION_FAILED);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Refuse to refresh when the coin's value is insufficient
     for the cost of all transactions. */
  if (TALER_amount_cmp (&coin_value,
                        &spent) < 0)
  {
    struct TALER_Amount coin_residual;

    GNUNET_assert (GNUNET_SYSERR !=
                   TALER_amount_subtract (&coin_residual,
                                          &spent,
                                          &rmc->refresh_session.amount_with_fee));
    *mhd_ret = reply_refresh_melt_insufficient_funds (connection,
						      &rmc->refresh_session.coin.coin_pub,
						      coin_value,
						      tl,
						      &rmc->refresh_session.amount_with_fee,
						      &coin_residual);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* we're good, coin has sufficient funds to be melted */
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Execute a "/refresh/melt".  We have been given a list of valid
 * coins and a request to melt them into the given @a
 * refresh_session_pub.  Check that the coins all have the required
 * value left and if so, store that they have been melted and confirm
 * the melting operation to the client.
 *
 * If it returns a non-error code, the transaction logic MUST NOT
 * queue a MHD response.  IF it returns an hard error, the transaction
 * logic MUST queue a MHD response and set @a mhd_ret.  If it returns
 * the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls our `struct RefreshMeltContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refresh_melt_transaction (void *cls,
			  struct MHD_Connection *connection,
			  struct TALER_EXCHANGEDB_Session *session,
			  int *mhd_ret)
{
  struct RefreshMeltContext *rmc = cls;
  struct TALER_EXCHANGEDB_RefreshMelt rm;
  enum GNUNET_DB_QueryStatus qs;

  /* Check if we already created such a session */
  qs = TEH_plugin->get_melt (TEH_plugin->cls,
                             session,
                             &rmc->refresh_session.rc,
                             &rm);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    TALER_LOG_DEBUG ("Found already-melted coin\n");
    *mhd_ret = reply_refresh_melt_success (connection,
					   &rmc->refresh_session.rc,
					   rm.session.noreveal_index);
    /* FIXME: is it normal to return "hard error" upon
     * _finding_ some data into the database?  */
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_REFRESH_MELT_DB_FETCH_ERROR);
    return qs;
  }

  /* check coin has enough funds remaining on it to cover melt cost */
  qs = refresh_check_melt (connection,
			   session,
			   rmc,
			   mhd_ret);
  if (0 > qs)
    return qs;

  /* pick challenge and persist it */
  rmc->refresh_session.noreveal_index
    = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
				TALER_CNC_KAPPA);

  if (0 >=
      (qs = TEH_plugin->insert_melt (TEH_plugin->cls,
                                     session,
                                     &rmc->refresh_session)))
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR != qs)
    {
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_REFRESH_MELT_DB_STORE_SESSION_ERROR);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    return qs;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Handle a "/refresh/melt" request after the first parsing has
 * happened.  We now need to validate the coins being melted and the
 * session signature and then hand things of to execute the melt
 * operation.  This function parses the JSON arrays and then passes
 * processing on to #handle_refresh_melt_binary().
 *
 * @param connection the MHD connection to handle
 * @param[in,out] rmc details about the melt request
 * @return MHD result code
 */
static int
handle_refresh_melt (struct MHD_Connection *connection,
                     struct RefreshMeltContext *rmc)
{
  /* sanity-check that "total melt amount > melt fee" */
  {
    struct TALER_Amount fee_refresh;

    TALER_amount_ntoh (&fee_refresh,
		       &rmc->dki->issue.properties.fee_refresh);
    if (TALER_amount_cmp (&fee_refresh,
			  &rmc->refresh_session.amount_with_fee) > 0)
    {
      GNUNET_break_op (0);
      return TEH_RESPONSE_reply_external_error (connection,
						TALER_EC_REFRESH_MELT_FEES_EXCEED_CONTRIBUTION,
						"melt amount smaller than melting fee");
    }
  }

  /* verify signature of coin for melt operation */
  {
    struct TALER_RefreshMeltCoinAffirmationPS body;

    body.purpose.size = htonl (sizeof (struct TALER_RefreshMeltCoinAffirmationPS));
    body.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
    body.rc = rmc->refresh_session.rc;
    TALER_amount_hton (&body.amount_with_fee,
		       &rmc->refresh_session.amount_with_fee);
    body.melt_fee = rmc->dki->issue.properties.fee_refresh;
    body.coin_pub = rmc->refresh_session.coin.coin_pub;

    if (GNUNET_OK !=
	GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
				    &body.purpose,
				    &rmc->refresh_session.coin_sig.eddsa_signature,
				    &rmc->refresh_session.coin.coin_pub.eddsa_pub))
    {
      GNUNET_break_op (0);
      return TEH_RESPONSE_reply_signature_invalid (connection,
						   TALER_EC_REFRESH_MELT_COIN_SIGNATURE_INVALID,
						   "confirm_sig");
    }
  }

  /* run transaction */
  {
    int mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run melt",
                                &mhd_ret,
                                &refresh_melt_transaction,
                                rmc))
      return mhd_ret;
  }

  /* generate ordinary response */
  return reply_refresh_melt_success (connection,
                                     &rmc->refresh_session.rc,
                                     rmc->refresh_session.noreveal_index);
}


/**
 * Handle a "/refresh/melt" request.  Parses the request into the JSON
 * components and then hands things of to #handle_refresh_melt_json()
 * to validate the melted coins, the signature and execute the melt
 * using TEH_DB_execute_refresh_melt().
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_REFRESH_handler_refresh_melt (struct TEH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  json_t *root;
  struct RefreshMeltContext rmc;
  int res;
  struct TEH_KS_StateHandle *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &rmc.refresh_session.coin.coin_pub),
    TALER_JSON_spec_denomination_signature ("denom_sig",
                                            &rmc.refresh_session.coin.denom_sig),
    TALER_JSON_spec_denomination_public_key ("denom_pub",
                                             &rmc.refresh_session.coin.denom_pub),
    GNUNET_JSON_spec_fixed_auto ("confirm_sig",
                                 &rmc.refresh_session.coin_sig),
    TALER_JSON_spec_amount ("value_with_fee",
                            &rmc.refresh_session.amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("rc",
                                 &rmc.refresh_session.rc),
    GNUNET_JSON_spec_end ()
  };

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) ||
       (NULL == root) )
    return MHD_YES;

  memset (&rmc,
          0,
          sizeof (rmc));
  res = TEH_PARSE_json_data (connection,
                             root,
                             spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

  if (GNUNET_OK !=
      TALER_test_coin_valid (&rmc.refresh_session.coin))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_signature_invalid (connection,
                                                 TALER_EC_REFRESH_MELT_DENOMINATION_SIGNATURE_INVALID,
                                                 "denom_sig");
  }

  /* run actual logic, now that the request was parsed */
  key_state = TEH_KS_acquire ();
  if (NULL == key_state)
  {
    TALER_LOG_ERROR ("Lacking keys to operate\n");
    res = TEH_RESPONSE_reply_internal_error (connection,
                                             TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                             "no keys");
    goto cleanup;
  }
  rmc.dki = TEH_KS_denomination_key_lookup (key_state,
                                            &rmc.refresh_session.coin.denom_pub,
                                            TEH_KS_DKU_DEPOSIT);
  if (NULL == rmc.dki)
  {
    TALER_LOG_WARNING ("Unknown denomination key in /refresh/melt request\n");
    res = TEH_RESPONSE_reply_arg_unknown (connection,
                                          TALER_EC_REFRESH_MELT_DENOMINATION_KEY_NOT_FOUND,
                                          "denom_pub");
    goto cleanup;
  }

  res = handle_refresh_melt (connection,
                             &rmc);


 cleanup:
  if (NULL != key_state)
  {
    TEH_KS_release (key_state);
    key_state = NULL;
  }
  if (NULL != rmc.refresh_session.coin.denom_pub.rsa_public_key)
  {
    GNUNET_CRYPTO_rsa_public_key_free (rmc.refresh_session.coin.denom_pub.rsa_public_key);
    rmc.refresh_session.coin.denom_pub.rsa_public_key = NULL;
  }
  if (NULL != rmc.refresh_session.coin.denom_sig.rsa_signature)
  {
    GNUNET_CRYPTO_rsa_signature_free (rmc.refresh_session.coin.denom_sig.rsa_signature);
    rmc.refresh_session.coin.denom_sig.rsa_signature = NULL;
  }
  GNUNET_JSON_parse_free (spec);

  return res;
}


/* end of taler-exchange-httpd_refresh_melt.c */
