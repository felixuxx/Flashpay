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
 * @brief Details about a melt operation of an individual coin.
 */
struct TEH_DB_MeltDetails
{

  /**
   * Information about the coin being melted.
   */
  struct TALER_CoinPublicInfo coin_info;

  /**
   * Signature allowing the melt (using
   * a `struct TALER_EXCHANGEDB_RefreshMeltConfirmSignRequestBody`) to sign over.
   */
  struct TALER_CoinSpendSignatureP melt_sig;

  /**
   * How much of the coin's value did the client allow to be melted?
   * This amount includes the fees, so the final amount contributed
   * to the melt is this value minus the fee for melting the coin.
   */
  struct TALER_Amount melt_amount_with_fee;

  /**
   * What fee is earned by the exchange?  Set delayed during
   * #verify_coin_public_info().
   */
  struct TALER_Amount melt_fee;
};


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
				       struct TALER_Amount requested,
				       struct TALER_Amount residual)
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
static int
reply_refresh_melt_success (struct MHD_Connection *connection,
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
 * Context for the /refresh/melt operation.
 */
struct RefreshMeltContext
{

  /**
   * Array of denominations of the fresh coins.
   */
  struct TALER_DenominationPublicKey *denom_pubs;

  /**
   * Number of new coins to be generated in the melt.
   * Size of the @e denom_pubs array.
   */
  unsigned int num_newcoins;

  /**
   * Details about the coin to be melted.
   */
  struct TEH_DB_MeltDetails coin_melt_details;

  /**
   * Set to the session hash once the @e hash_context has finished.
   */ 
  struct GNUNET_HashCode session_hash;

  /**
   * Hash operation used to calculate the session hash.
   */
  struct GNUNET_HashContext *hash_context;

  /**
   * Committments to the blinded envelopes for the fresh coins.
   */
  struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coin[TALER_CNC_KAPPA];

  /**
   * Commmittments to the transfer public keys.
   */
  struct TALER_TransferPublicKeyP transfer_pub[TALER_CNC_KAPPA];

  /**
   * Initialized during #refresh_melt_transaction().
   */
  struct TALER_EXCHANGEDB_RefreshSession refresh_session;

};


/**
 * Parse coin melt requests from a JSON object and write them to
 * the database.
 *
 * @param connection the connection to send errors to
 * @param session the database connection
 * @param key_state the exchange's key state
 * @param session_hash hash identifying the refresh session
 * @param coin_details details about the coin being melted
 * @param[out] meltp on success, set to melt details
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if an error message was generated,
 *         #GNUNET_SYSERR on internal errors (no response generated)
 */
static int
refresh_check_melt (struct MHD_Connection *connection,
                    struct TALER_EXCHANGEDB_Session *session,
                    const struct TEH_KS_StateHandle *key_state,
                    const struct GNUNET_HashCode *session_hash,
                    const struct TEH_DB_MeltDetails *coin_details,
                    struct TALER_EXCHANGEDB_RefreshMelt *meltp)
{
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dk;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_Amount coin_value;
  struct TALER_Amount coin_residual;
  struct TALER_Amount spent;
  int res;
  enum GNUNET_DB_QueryStatus qs;

  dk = TEH_KS_denomination_key_lookup (key_state,
                                       &coin_details->coin_info.denom_pub,
                                       TEH_KS_DKU_DEPOSIT);
  if (NULL == dk)
    return (MHD_YES ==
            TEH_RESPONSE_reply_internal_error (connection,
					       TALER_EC_REFRESH_MELT_DB_DENOMINATION_KEY_NOT_FOUND,
					       "denomination key no longer available while executing transaction"))
        ? GNUNET_NO : GNUNET_SYSERR;
  dki = &dk->issue;
  TALER_amount_ntoh (&coin_value,
                     &dki->properties.value);
  /* fee for THIS transaction; the melt amount includes the fee! */
  spent = coin_details->melt_amount_with_fee;
  /* add historic transaction costs of this coin */
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          session,
                                          &coin_details->coin_info.coin_pub,
					  &tl);
  (void) qs; /* FIXME #5010 */
  if (GNUNET_OK !=
      TEH_DB_calculate_transaction_list_totals (tl,
						&spent,
						&spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return (MHD_YES ==
            TEH_RESPONSE_reply_internal_db_error (connection,
						  TALER_EC_REFRESH_MELT_COIN_HISTORY_COMPUTATION_FAILED))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  /* Refuse to refresh when the coin's value is insufficient
     for the cost of all transactions. */
  if (TALER_amount_cmp (&coin_value,
                        &spent) < 0)
  {
    GNUNET_assert (GNUNET_SYSERR !=
                   TALER_amount_subtract (&coin_residual,
                                          &spent,
                                          &coin_details->melt_amount_with_fee));
    res = (MHD_YES ==
           reply_refresh_melt_insufficient_funds (connection,
						  &coin_details->coin_info.coin_pub,
						  coin_value,
						  tl,
						  coin_details->melt_amount_with_fee,
						  coin_residual))
        ? GNUNET_NO : GNUNET_SYSERR;
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return res;
  }
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);

  meltp->coin = coin_details->coin_info;
  meltp->coin_sig = coin_details->melt_sig;
  meltp->session_hash = *session_hash;
  meltp->amount_with_fee = coin_details->melt_amount_with_fee;
  meltp->melt_fee = coin_details->melt_fee;
  return GNUNET_OK;
}


/**
 * Execute a "/refresh/melt".  We have been given a list of valid
 * coins and a request to melt them into the given
 * @a refresh_session_pub.  Check that the coins all have the
 * required value left and if so, store that they have been
 * melted and confirm the melting operation to the client.
 *
 * If it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
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
  struct TEH_KS_StateHandle *key_state;
  enum GNUNET_DB_QueryStatus qs;
  int res;

  qs = TEH_plugin->get_refresh_session (TEH_plugin->cls,
					session,
					&rmc->session_hash,
					&rmc->refresh_session);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    *mhd_ret = reply_refresh_melt_success (connection,
					   &rmc->session_hash,
					   rmc->refresh_session.noreveal_index);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
						       TALER_EC_REFRESH_MELT_DB_FETCH_ERROR);
    return qs;
  }

  /* store 'global' session data */
  rmc->refresh_session.num_newcoins = rmc->num_newcoins;
  rmc->refresh_session.noreveal_index
    = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
				TALER_CNC_KAPPA);

  key_state = TEH_KS_acquire ();
  if (GNUNET_OK !=
      (res = refresh_check_melt (connection,
				 session,
				 key_state,
				 &rmc->session_hash,
				 &rmc->coin_melt_details,
				 &rmc->refresh_session.melt)))
  {
    TEH_KS_release (key_state);
    *mhd_ret = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
    return GNUNET_DB_STATUS_HARD_ERROR;    
  }
  TEH_KS_release (key_state);

  if ( (0 >=
	(qs = TEH_plugin->create_refresh_session (TEH_plugin->cls,
						  session,
						  &rmc->session_hash,
						  &rmc->refresh_session))) ||
       (0 >=
	(qs = TEH_plugin->insert_refresh_order (TEH_plugin->cls,
						session,
						&rmc->session_hash,
						rmc->num_newcoins,
						rmc->denom_pubs))) ||
       (0 >=
	(qs = TEH_plugin->insert_refresh_commit_coins (TEH_plugin->cls,
						       session,
						       &rmc->session_hash,
						       rmc->num_newcoins,
						       rmc->commit_coin[rmc->refresh_session.noreveal_index]))) ||
       (0 >=
	(qs = TEH_plugin->insert_refresh_transfer_public_key (TEH_plugin->cls,
							      session,
							      &rmc->session_hash,
							      &rmc->transfer_pub[rmc->refresh_session.noreveal_index]))) )
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
 * Handle a "/refresh/melt" request after the main JSON parsing has happened.
 * We now need to validate the coins being melted and the session signature
 * and then hand things of to execute the melt operation.
 *
 * @param connection the MHD connection to handle
 * @param[out] mhd_ret set on failure to return value for MHD
 * @param rmc information about the melt to process
 * @return MHD result code
 */
static int
refresh_melt_prepare (struct MHD_Connection *connection,
		      int *mhd_ret,
		      struct RefreshMeltContext *rmc)
{
  struct TEH_KS_StateHandle *key_state;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dk;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount cost;
  struct TALER_Amount total_cost;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_melt;
  struct TALER_Amount total_melt;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "/refresh/melt request for session %s\n",
              GNUNET_h2s (&rmc->session_hash));
  
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TEH_exchange_currency_string,
                                        &total_cost));
  key_state = TEH_KS_acquire ();
  for (unsigned int i=0;i<rmc->num_newcoins;i++)
  {
    dk = TEH_KS_denomination_key_lookup (key_state,
                                         &rmc->denom_pubs[i],
                                         TEH_KS_DKU_WITHDRAW);
    if (NULL == dk)
    {
      GNUNET_break_op (0);
      TEH_KS_release (key_state);
      *mhd_ret = TEH_RESPONSE_reply_arg_invalid (connection,
						 TALER_EC_REFRESH_MELT_FRESH_DENOMINATION_KEY_NOT_FOUND,
						 "new_denoms");
      return GNUNET_SYSERR;
    }
    dki = &dk->issue;
    TALER_amount_ntoh (&value,
                       &dki->properties.value);
    TALER_amount_ntoh (&fee_withdraw,
                       &dki->properties.fee_withdraw);
    if ( (GNUNET_OK !=
          TALER_amount_add (&cost,
                            &value,
                            &fee_withdraw)) ||
         (GNUNET_OK !=
          TALER_amount_add (&total_cost,
                            &cost,
                            &total_cost)) )
    {
      GNUNET_break_op (0);
      TEH_KS_release (key_state);
      *mhd_ret = TEH_RESPONSE_reply_internal_error (connection,
						    TALER_EC_REFRESH_MELT_COST_CALCULATION_OVERFLOW,
						    "cost calculation failure");
      return GNUNET_SYSERR;
    }
  }

  dk = TEH_KS_denomination_key_lookup (key_state,
                                       &rmc->coin_melt_details.coin_info.denom_pub,
                                       TEH_KS_DKU_DEPOSIT);
  if (NULL == dk)
  {
    GNUNET_break (0);
    *mhd_ret = TEH_RESPONSE_reply_arg_unknown (connection,
					       TALER_EC_REFRESH_MELT_DENOMINATION_KEY_NOT_FOUND,
					       "denom_pub");
    return GNUNET_SYSERR;
  }
  dki = &dk->issue;
  TALER_amount_ntoh (&fee_melt,
                     &dki->properties.fee_refresh);
  if (GNUNET_OK !=
      TALER_amount_subtract (&total_melt,
                             &rmc->coin_melt_details.melt_amount_with_fee,
                             &fee_melt))
  {
    GNUNET_break_op (0);
    TEH_KS_release (key_state);
    *mhd_ret = TEH_RESPONSE_reply_external_error (connection,
						  TALER_EC_REFRESH_MELT_FEES_EXCEED_CONTRIBUTION,
						  "Melt contribution below melting fee");
    return GNUNET_SYSERR;
  }
  TEH_KS_release (key_state);
  if (0 !=
      TALER_amount_cmp (&total_cost,
                        &total_melt))
  {
    GNUNET_break_op (0);
    /* We require total value of coins being melted and
       total value of coins being generated to match! */
    *mhd_ret = TEH_RESPONSE_reply_json_pack (connection,
					     MHD_HTTP_BAD_REQUEST,
					     "{s:s, s:I}",
					     "error", "value mismatch",
					     "code", (json_int_t) TALER_EC_REFRESH_MELT_FEES_MISSMATCH);
    return GNUNET_SYSERR;
  }
  return TEH_DB_run_transaction (connection,
				 mhd_ret,
				 &refresh_melt_transaction,
				 rmc);
}


/**
 * Extract public coin information from a JSON object.
 *
 * @param connection the connection to send error responses to
 * @param coin_info the JSON object to extract the coin info from
 * @param[out] r_melt_detail set to details about the coin's melting permission (if valid)
 * @return #GNUNET_YES if coin public info in JSON was valid
 *         #GNUNET_NO JSON was invalid, response was generated
 *         #GNUNET_SYSERR on internal error
 */
static int
get_coin_public_info (struct MHD_Connection *connection,
                      const json_t *coin_info,
                      struct TEH_DB_MeltDetails *r_melt_detail)
{
  int ret;
  struct TALER_CoinSpendSignatureP melt_sig;
  struct TALER_DenominationSignature sig;
  struct TALER_DenominationPublicKey pk;
  struct TALER_Amount amount;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &r_melt_detail->coin_info.coin_pub),
    TALER_JSON_spec_denomination_signature ("denom_sig", &sig),
    TALER_JSON_spec_denomination_public_key ("denom_pub", &pk),
    GNUNET_JSON_spec_fixed_auto ("confirm_sig", &melt_sig),
    TALER_JSON_spec_amount ("value_with_fee", &amount),
    GNUNET_JSON_spec_end ()
  };

  ret = TEH_PARSE_json_data (connection,
                             coin_info,
                             spec);
  if (GNUNET_OK != ret)
  {
    GNUNET_break_op (0);
    return ret;
  }
  /* check exchange signature on the coin */
  r_melt_detail->coin_info.denom_sig = sig;
  r_melt_detail->coin_info.denom_pub = pk;
  if (GNUNET_OK !=
      TALER_test_coin_valid (&r_melt_detail->coin_info))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    r_melt_detail->coin_info.denom_sig.rsa_signature = NULL;
    r_melt_detail->coin_info.denom_pub.rsa_public_key = NULL;
    return (MHD_YES ==
            TEH_RESPONSE_reply_signature_invalid (connection,
						  TALER_EC_REFRESH_MELT_DENOMINATION_SIGNATURE_INVALID,
                                                  "denom_sig"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  r_melt_detail->melt_sig = melt_sig;
  r_melt_detail->melt_amount_with_fee = amount;
  return GNUNET_OK;
}


/**
 * Verify that the signature shows that this coin is to be melted into
 * the given @a session_hash melting session, and that this is a valid
 * coin (we know the denomination key and the signature on it is
 * valid).  Essentially, this does all of the per-coin checks that can
 * be done before the transaction starts.
 *
 * @param connection the connection to send error responses to
 * @param session_hash hash over refresh session the coin is melted into
 * @param[in,out] melt_detail details about the coin's melting permission,
 *                            the `melt_fee` is updated
 * @return #GNUNET_YES if coin public info in JSON was valid
 *         #GNUNET_NO JSON was invalid, response was generated
 *         #GNUNET_SYSERR on internal error
 */
static int
verify_coin_public_info (struct MHD_Connection *connection,
                         const struct GNUNET_HashCode *session_hash,
                         struct TEH_DB_MeltDetails *melt_detail)
{
  struct TALER_RefreshMeltCoinAffirmationPS body;
  struct TEH_KS_StateHandle *key_state;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TALER_Amount fee_refresh;

  /* FIXME: we lookup the dki twice during /refresh/melt.
     This should be avoided. */
  key_state = TEH_KS_acquire ();
  dki = TEH_KS_denomination_key_lookup (key_state,
                                        &melt_detail->coin_info.denom_pub,
					TEH_KS_DKU_DEPOSIT);
  if (NULL == dki)
  {
    TEH_KS_release (key_state);
    TALER_LOG_WARNING ("Unknown denomination key in /refresh/melt request\n");
    return TEH_RESPONSE_reply_arg_unknown (connection,
					   TALER_EC_REFRESH_MELT_DENOMINATION_KEY_NOT_FOUND,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&fee_refresh,
                     &dki->issue.properties.fee_refresh);
  melt_detail->melt_fee = fee_refresh;
  body.purpose.size = htonl (sizeof (struct TALER_RefreshMeltCoinAffirmationPS));
  body.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
  body.session_hash = *session_hash;
  TALER_amount_hton (&body.amount_with_fee,
                     &melt_detail->melt_amount_with_fee);
  TALER_amount_hton (&body.melt_fee,
                     &fee_refresh);
  body.coin_pub = melt_detail->coin_info.coin_pub;
  if (TALER_amount_cmp (&fee_refresh,
                        &melt_detail->melt_amount_with_fee) > 0)
  {
    GNUNET_break_op (0);
    TEH_KS_release (key_state);
    return (MHD_YES ==
            TEH_RESPONSE_reply_external_error (connection,
					       TALER_EC_REFRESH_MELT_AMOUNT_INSUFFICIENT,
                                               "melt amount smaller than melting fee"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }

  TEH_KS_release (key_state);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                  &body.purpose,
                                  &melt_detail->melt_sig.eddsa_signature,
                                  &melt_detail->coin_info.coin_pub.eddsa_pub))
  {
    GNUNET_break_op (0);
    if (MHD_YES !=
        TEH_RESPONSE_reply_signature_invalid (connection,
					      TALER_EC_REFRESH_MELT_COIN_SIGNATURE_INVALID,
                                              "confirm_sig"))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Release memory from the @a commit_coin array.
 *
 * @param commit_coin array to release
 * @param kappa size of 1st dimension
 * @param num_new_coins size of 2nd dimension
 */
static void
free_commit_coins (struct TALER_EXCHANGEDB_RefreshCommitCoin **commit_coin,
                   unsigned int kappa,
                   unsigned int num_new_coins)
{
  for (unsigned int i=0;i<kappa;i++)
  {
    if (NULL == commit_coin[i])
      break;
    for (unsigned int j=0;j<num_new_coins;j++)
      GNUNET_free_non_null (commit_coin[i][j].coin_ev);
    GNUNET_free (commit_coin[i]);
  }
}


/**
 * Cleanup state kept in the @a rmc.
 *
 * @param rmc state to clean up; does not free @a rmc itself
 */
static void
cleanup_rmc (struct RefreshMeltContext *rmc)
{
  free_commit_coins (rmc->commit_coin,
                     TALER_CNC_KAPPA,
                     rmc->num_newcoins);
  if (NULL != rmc->coin_melt_details.coin_info.denom_pub.rsa_public_key)
    GNUNET_CRYPTO_rsa_public_key_free (rmc->coin_melt_details.coin_info.denom_pub.rsa_public_key);
  if (NULL != rmc->coin_melt_details.coin_info.denom_sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (rmc->coin_melt_details.coin_info.denom_sig.rsa_signature);
  if (NULL != rmc->denom_pubs)
  {
    for (unsigned int j=0;j<rmc->num_newcoins;j++)
      if (NULL != rmc->denom_pubs[j].rsa_public_key)
        GNUNET_CRYPTO_rsa_public_key_free (rmc->denom_pubs[j].rsa_public_key);
    GNUNET_free (rmc->denom_pubs);
  }
  if (NULL != rmc->hash_context)
    GNUNET_CRYPTO_hash_context_abort (rmc->hash_context);
}


/**
 * Handle a "/refresh/melt" request after the first parsing has happened.
 * We now need to validate the coins being melted and the session signature
 * and then hand things of to execute the melt operation.  This function
 * parses the JSON arrays and then passes processing on to
 * #handle_refresh_melt_binary().
 *
 * @param connection the MHD connection to handle
 * @param new_denoms array of denomination keys
 * @param melt_coin coin to melt
 * @param transfer_pubs #TALER_CNC_KAPPA-dimensional array of transfer keys
 * @param coin_evs #TALER_CNC_KAPPA-dimensional array of envelopes to sign
 * @return MHD result code
 */
static int
handle_refresh_melt_json (struct MHD_Connection *connection,
                          const json_t *new_denoms,
                          const json_t *melt_coin,
                          const json_t *transfer_pubs,
                          const json_t *coin_evs)
{
  int res;
  int mhd_ret;
  struct RefreshMeltContext rmc;

  memset (&rmc,
	  0,
	  sizeof (rmc));
  /* For the signature check, we hash most of the inputs together
     (except for the signatures on the coins). */
  rmc.hash_context = GNUNET_CRYPTO_hash_context_start ();

  for (unsigned int i = 0; i < TALER_CNC_KAPPA; i++)
  {
    struct GNUNET_JSON_Specification trans_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &rmc.transfer_pub[i]),
      GNUNET_JSON_spec_end ()
    };

    res = TEH_PARSE_json_array (connection,
                                transfer_pubs,
                                trans_spec,
                                i, -1);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      mhd_ret = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      cleanup_rmc (&rmc);
      return mhd_ret;
    }
    GNUNET_CRYPTO_hash_context_read (rmc.hash_context,
                                     &rmc.transfer_pub[i],
                                     sizeof (struct TALER_TransferPublicKeyP));
  }


  rmc.num_newcoins = json_array_size (new_denoms);
  rmc.denom_pubs = GNUNET_new_array (rmc.num_newcoins,
				     struct TALER_DenominationPublicKey);
  for (unsigned int i=0;i<rmc.num_newcoins;i++)
  {
    char *buf;
    size_t buf_size;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_denomination_public_key (NULL,
                                               &rmc.denom_pubs[i]),
      GNUNET_JSON_spec_end ()
    };

    res = TEH_PARSE_json_array (connection,
                                new_denoms,
                                spec,
                                i,
				-1);
    if (GNUNET_OK != res)
    {
      mhd_ret = (GNUNET_NO == res) ? MHD_YES : MHD_NO;
      cleanup_rmc (&rmc);
      return mhd_ret;
    }
    buf_size = GNUNET_CRYPTO_rsa_public_key_encode (rmc.denom_pubs[i].rsa_public_key,
                                                    &buf);
    GNUNET_CRYPTO_hash_context_read (rmc.hash_context,
                                     buf,
                                     buf_size);
    GNUNET_free (buf);
  }

  {
    /* decode JSON data on coin to melt */
    struct TALER_AmountNBO melt_amount;

    res = get_coin_public_info (connection,
                                melt_coin,
                                &rmc.coin_melt_details);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      mhd_ret = (GNUNET_NO == res) ? MHD_YES : MHD_NO;
      cleanup_rmc (&rmc);
      return mhd_ret;
    }
    TALER_amount_hton (&melt_amount,
                       &rmc.coin_melt_details.melt_amount_with_fee);
    GNUNET_CRYPTO_hash_context_read (rmc.hash_context,
                                     &rmc.coin_melt_details.coin_info.coin_pub,
                                     sizeof (struct TALER_CoinSpendPublicKeyP));
    GNUNET_CRYPTO_hash_context_read (rmc.hash_context,
                                     &melt_amount,
                                     sizeof (struct TALER_AmountNBO));
  }

  /* parse JSON arrays into binary arrays and hash everything
     together for the signature check */
  for (unsigned int i = 0; i < TALER_CNC_KAPPA; i++)
  {
    rmc.commit_coin[i] = GNUNET_new_array (rmc.num_newcoins,
					   struct TALER_EXCHANGEDB_RefreshCommitCoin);
    for (unsigned int j = 0; j < rmc.num_newcoins; j++)
    {
      struct TALER_EXCHANGEDB_RefreshCommitCoin *rcc = &rmc.commit_coin[i][j];
      struct GNUNET_JSON_Specification coin_spec[] = {
        GNUNET_JSON_spec_varsize (NULL,
                                  (void **) &rcc->coin_ev,
                                  &rcc->coin_ev_size),
        GNUNET_JSON_spec_end ()
      };

      res = TEH_PARSE_json_array (connection,
                                  coin_evs,
                                  coin_spec,
                                  i,
				  j,
				  -1);
      if (GNUNET_OK != res)
      {
        GNUNET_break_op (0);
        mhd_ret = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
        cleanup_rmc (&rmc);
	return mhd_ret;
      }

      GNUNET_CRYPTO_hash_context_read (rmc.hash_context,
                                       rcc->coin_ev,
                                       rcc->coin_ev_size);
    }
  }

  GNUNET_CRYPTO_hash_context_finish (rmc.hash_context,
                                     &rmc.session_hash);
  rmc.hash_context = NULL;
  /* verify signature on coins to melt */
  res = verify_coin_public_info (connection,
                                 &rmc.session_hash,
                                 &rmc.coin_melt_details);
  if (GNUNET_OK != res)
  {
    GNUNET_break_op (0);
    mhd_ret = (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    cleanup_rmc (&rmc);
    return mhd_ret;
  }

  /* prepare commit */
  if (GNUNET_OK !=
      refresh_melt_prepare (connection,
			    &mhd_ret,
			    &rmc))
  {
    cleanup_rmc (&rmc);
    return mhd_ret;
  }
  mhd_ret = reply_refresh_melt_success (connection,
					&rmc.session_hash,
					rmc.refresh_session.noreveal_index);
  cleanup_rmc (&rmc);
  return mhd_ret;
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
  json_t *new_denoms;
  json_t *melt_coin;
  json_t *coin_evs;
  json_t *transfer_pubs;
  int res;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("new_denoms", &new_denoms),
    GNUNET_JSON_spec_json ("melt_coin", &melt_coin),
    GNUNET_JSON_spec_json ("coin_evs", &coin_evs),
    GNUNET_JSON_spec_json ("transfer_pubs", &transfer_pubs),
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

  res = TEH_PARSE_json_data (connection,
                             root,
                             spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

  /* Determine dimensionality of the request (kappa, #old and #new coins) */
  if (TALER_CNC_KAPPA != json_array_size (coin_evs))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_REFRESH_MELT_CNC_COIN_ARRAY_SIZE_INVALID,
                                           "coin_evs");
  }
  if (TALER_CNC_KAPPA != json_array_size (transfer_pubs))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_REFRESH_MELT_CNC_TRANSFER_ARRAY_SIZE_INVALID,
                                           "transfer_pubs");
  }
  res = handle_refresh_melt_json (connection,
                                  new_denoms,
                                  melt_coin,
                                  transfer_pubs,
                                  coin_evs);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_refresh_melt.c */
