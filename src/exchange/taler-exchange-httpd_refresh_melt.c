/*
  This file is part of TALER
  Copyright (C) 2014-2019 Taler Systems SA

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
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
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
                                       const struct
                                       TALER_CoinSpendPublicKeyP *coin_pub,
                                       struct TALER_Amount coin_value,
                                       struct TALER_EXCHANGEDB_TransactionList *
                                       tl,
                                       const struct TALER_Amount *requested,
                                       const struct TALER_Amount *residual)
{
  json_t *history;

  history = TEH_RESPONSE_compile_transaction_history (tl);
  if (NULL == history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_REFRESH_MELT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                       "Failed to compile transaction history");
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_FORBIDDEN,
                                    "{s:s, s:I, s:o, s:o, s:o, s:o, s:o}",
                                    "error",
                                    "insufficient funds",
                                    "code",
                                    (json_int_t)
                                    TALER_EC_REFRESH_MELT_INSUFFICIENT_FUNDS,
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
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                       "no keys");
  }
  sig_json = GNUNET_JSON_from_data_auto (&sig);
  GNUNET_assert (NULL != sig_json);
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_OK,
                                    "{s:i, s:o, s:o}",
                                    "noreveal_index", (int) noreveal_index,
                                    "exchange_sig", sig_json,
                                    "exchange_pub",
                                    GNUNET_JSON_from_data_auto (&pub));
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

  /**
   * Set to #GNUNET_YES if this @a dki was revoked and the operation
   * is thus only allowed for zombie coins where the transaction
   * history includes a #TALER_EXCHANGEDB_TT_OLD_COIN_PAYBACK.
   */
  int zombie_required;

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

  /* add historic transaction costs of this coin, including paybacks as
     we might be a zombie coin */
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          session,
                                          &rmc->refresh_session.coin.coin_pub,
                                          GNUNET_YES,
                                          &tl);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_REFRESH_MELT_DB_FETCH_ERROR,
                                             "failed to fetch old coin history");
    return qs;
  }
  if (rmc->zombie_required)
  {
    for (struct TALER_EXCHANGEDB_TransactionList *tp = tl;
         NULL != tp;
         tp = tp->next)
    {
      if (TALER_EXCHANGEDB_TT_OLD_COIN_PAYBACK == tp->type)
      {
        rmc->zombie_required = GNUNET_NO; /* was satisfied! */
        break;
      }
    }
    if (rmc->zombie_required)
    {
      /* zombie status not satisfied */
      GNUNET_break (0);
      TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                              tl);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_REFRESH_MELT_COIN_EXPIRED_NO_ZOMBIE,
                                             "denomination expired");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  if (GNUNET_OK !=
      TEH_DB_calculate_transaction_list_totals (tl,
                                                &spent,
                                                &spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_REFRESH_MELT_COIN_HISTORY_COMPUTATION_FAILED,
                                           "failed to compute coin transaction history");
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
                                                      &rmc->refresh_session.coin
                                                      .coin_pub,
                                                      coin_value,
                                                      tl,
                                                      &rmc->refresh_session.
                                                      amount_with_fee,
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
  enum GNUNET_DB_QueryStatus qs;
  uint32_t noreveal_index;

  /* Check if we already created such a session */
  qs = TEH_plugin->get_melt_index (TEH_plugin->cls,
                                   session,
                                   &rmc->refresh_session.rc,
                                   &noreveal_index);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    TALER_LOG_DEBUG ("Found already-melted coin\n");
    *mhd_ret = reply_refresh_melt_success (connection,
                                           &rmc->refresh_session.rc,
                                           noreveal_index);
    /* Note: we return "hard error" to ensure the wrapper
       does not retry the transaction, and to also not generate
       a "fresh" response (as we would on "success") */
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_REFRESH_MELT_DB_FETCH_ERROR,
                                             "failed to fetch melt index");
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
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_REFRESH_MELT_DB_STORE_SESSION_ERROR,
                                             "failed to persist melt data");
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
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_REFRESH_MELT_FEES_EXCEED_CONTRIBUTION,
                                         "melt amount smaller than melting fee");
    }
  }

  /* verify signature of coin for melt operation */
  {
    struct TALER_RefreshMeltCoinAffirmationPS body;

    body.purpose.size = htonl (sizeof (struct
                                       TALER_RefreshMeltCoinAffirmationPS));
    body.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
    body.rc = rmc->refresh_session.rc;
    TALER_amount_hton (&body.amount_with_fee,
                       &rmc->refresh_session.amount_with_fee);
    body.melt_fee = rmc->dki->issue.properties.fee_refresh;
    body.coin_pub = rmc->refresh_session.coin.coin_pub;

    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                    &body.purpose,
                                    &rmc->refresh_session.coin_sig.
                                    eddsa_signature,
                                    &rmc->refresh_session.coin.coin_pub.
                                    eddsa_pub))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
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
  unsigned int hc;
  enum TALER_ErrorCode ec;
  struct TEH_KS_StateHandle *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &rmc.refresh_session.coin.coin_pub),
    TALER_JSON_spec_denomination_signature ("denom_sig",
                                            &rmc.refresh_session.coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &rmc.refresh_session.coin.denom_pub_hash),
    GNUNET_JSON_spec_fixed_auto ("confirm_sig",
                                 &rmc.refresh_session.coin_sig),
    TALER_JSON_spec_amount ("value_with_fee",
                            &rmc.refresh_session.amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("rc",
                                 &rmc.refresh_session.rc),
    GNUNET_JSON_spec_end ()
  };

  (void) rh;
  res = TALER_MHD_parse_post_json (connection,
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
  res = TALER_MHD_parse_json_data (connection,
                                   root,
                                   spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

  key_state = TEH_KS_acquire (GNUNET_TIME_absolute_get ());
  if (NULL == key_state)
  {
    TALER_LOG_ERROR ("Lacking keys to operate\n");
    res = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                      "no keys");
    goto cleanup;
  }

  /* Baseline: check if deposits/refreshs are generally
     simply still allowed for this denomination */
  rmc.dki = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                    &rmc.refresh_session.coin.
                                                    denom_pub_hash,
                                                    TEH_KS_DKU_DEPOSIT,
                                                    &ec,
                                                    &hc);
  /* Consider case that denomination was revoked but
     this coin was already seen and thus refresh is OK. */
  if (NULL == rmc.dki)
  {
    struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

    dki = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                  &rmc.refresh_session.coin.
                                                  denom_pub_hash,
                                                  TEH_KS_DKU_PAYBACK,
                                                  &ec,
                                                  &hc);
    if (NULL != dki)
    {
      struct TALER_CoinPublicInfo coin_info;
      enum GNUNET_DB_QueryStatus qs;

      qs = TEH_plugin->get_known_coin (TEH_plugin->cls,
                                       NULL,
                                       &rmc.refresh_session.coin.coin_pub,
                                       &coin_info);
      if (0 > qs)
      {
        GNUNET_break (0);
        res = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_REFRESH_MELT_DB_FETCH_ERROR,
                                          "failed to find information about old coin");
        goto cleanup;
      }
      if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
      {
        /* Coin was known beforehand, so we should allow the refresh */
        rmc.dki = dki;
        GNUNET_CRYPTO_rsa_signature_free (coin_info.denom_sig.rsa_signature);
      }
    }
  }

  /* Consider the case that the denomination expired for deposits,
     but /refresh/payback refilled the balance of the 'zombie' coin
     and we should thus allow the refresh during the legal period. */
  if (NULL == rmc.dki)
  {
    struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;

    dki = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                  &rmc.refresh_session.coin.
                                                  denom_pub_hash,
                                                  TEH_KS_DKU_ZOMBIE,
                                                  &ec,
                                                  &hc);
    if (NULL != dki)
    {
      rmc.dki = dki;
      rmc.zombie_required = GNUNET_YES;
    }
  }

  if (NULL == rmc.dki)
  {
    TALER_LOG_WARNING ("Unknown denomination key in /refresh/melt request\n");
    res = TALER_MHD_reply_with_error (connection,
                                      hc,
                                      ec,
                                      "unknown denomination");
    goto cleanup;
  }

  if (GNUNET_OK !=
      TALER_test_coin_valid (&rmc.refresh_session.coin,
                             &rmc.dki->denom_pub))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    TEH_KS_release (key_state);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_REFRESH_MELT_DENOMINATION_SIGNATURE_INVALID,
                                       "denom_sig");
  }

  /* run actual logic, now that the request was parsed */

  /* make sure coin is 'known' in database */
  {
    struct TEH_DB_KnowCoinContext kcc;
    int mhd_ret;

    kcc.coin = &rmc.refresh_session.coin;
    kcc.connection = connection;
    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "know coin for refresh-melt",
                                &mhd_ret,
                                &TEH_DB_know_coin_transaction,
                                &kcc))
      return mhd_ret;
  }

  res = handle_refresh_melt (connection,
                             &rmc);


cleanup:
  if (NULL != key_state)
  {
    TEH_KS_release (key_state);
    key_state = NULL;
  }
  if (NULL != rmc.refresh_session.coin.denom_sig.rsa_signature)
  {
    GNUNET_CRYPTO_rsa_signature_free (
      rmc.refresh_session.coin.denom_sig.rsa_signature);
    rmc.refresh_session.coin.denom_sig.rsa_signature = NULL;
  }
  GNUNET_JSON_parse_free (spec);

  return res;
}


/* end of taler-exchange-httpd_refresh_melt.c */
