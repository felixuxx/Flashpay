/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-exchange-httpd_melt.c
 * @brief Handle melt requests
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
#include "taler-exchange-httpd_melt.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Send a response for a failed "melt" request.  The
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
static MHD_RESULT
reply_melt_insufficient_funds (
  struct MHD_Connection *connection,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *coin_value,
  struct TALER_EXCHANGEDB_TransactionList *tl,
  const struct TALER_Amount *requested,
  const struct TALER_Amount *residual)
{
  json_t *history;

  history = TEH_RESPONSE_compile_transaction_history (coin_pub,
                                                      tl);
  if (NULL == history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_MELT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                       "Failed to compile transaction history");
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_CONFLICT,
                                    "{s:s, s:I, s:o, s:o, s:o, s:o, s:o}",
                                    "hint",
                                    "insufficient funds",
                                    "code",
                                    (json_int_t)
                                    TALER_EC_MELT_INSUFFICIENT_FUNDS,
                                    "coin_pub",
                                    GNUNET_JSON_from_data_auto (coin_pub),
                                    "original_value",
                                    TALER_JSON_from_amount (coin_value),
                                    "residual_value",
                                    TALER_JSON_from_amount (residual),
                                    "requested_value",
                                    TALER_JSON_from_amount (requested),
                                    "history",
                                    history);
}


/**
 * Send a response to a "melt" request.
 *
 * @param connection the connection to send the response to
 * @param rc value the client committed to
 * @param noreveal_index which index will the client not have to reveal
 * @return a MHD status code
 */
static MHD_RESULT
reply_melt_success (struct MHD_Connection *connection,
                    const struct TALER_RefreshCommitmentP *rc,
                    uint32_t noreveal_index)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_RefreshMeltConfirmationPS body = {
    .purpose.size = htonl (sizeof (body)),
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT),
    .rc = *rc,
    .noreveal_index = htonl (noreveal_index)
  };

  if (GNUNET_OK !=
      TEH_KS_sign (&body,
                   &pub,
                   &sig))
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                       "no keys");
  }
  return TALER_MHD_reply_json_pack (
    connection,
    MHD_HTTP_OK,
    "{s:i, s:o, s:o}",
    "noreveal_index", (int) noreveal_index,
    "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
    "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Context for the melt operation.
 */
struct MeltContext
{

  /**
   * noreveal_index is only initialized during
   * #melt_transaction().
   */
  struct TALER_EXCHANGEDB_Refresh refresh_session;

  /**
   * Information about the @e coin's value.
   */
  struct TALER_Amount coin_value;

  /**
   * Information about the @e coin's refresh fee.
   */
  struct TALER_Amount coin_refresh_fee;

  /**
   * Set to #GNUNET_YES if this coin's denomination was revoked and the operation
   * is thus only allowed for zombie coins where the transaction
   * history includes a #TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP.
   */
  int zombie_required;

  /**
   * We already checked and noticed that the coin is known. Hence we
   * can skip the "ensure_coin_known" step of the transaction.
   */
  bool coin_is_dirty;

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
                    struct MeltContext *rmc,
                    MHD_RESULT *mhd_ret)
{
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_Amount spent;
  enum GNUNET_DB_QueryStatus qs;

  /* Start with cost of this melt transaction */
  spent = rmc->refresh_session.amount_with_fee;

  /* get historic transaction costs of this coin, including recoups as
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
                                             TALER_EC_MELT_DB_FETCH_ERROR,
                                             "failed to fetch old coin history");
    return qs;
  }
  if (rmc->zombie_required)
  {
    /* The denomination key is only usable for a melt if this is a true
       zombie coin, i.e. it was refreshed and the resulting fresh coin was
       then recouped. Check that this is truly the case. */
    for (struct TALER_EXCHANGEDB_TransactionList *tp = tl;
         NULL != tp;
         tp = tp->next)
    {
      if (TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP == tp->type)
      {
        rmc->zombie_required = GNUNET_NO; /* clear flag: was satisfied! */
        break;
      }
    }
    if (GNUNET_YES == rmc->zombie_required)
    {
      /* zombie status not satisfied */
      GNUNET_break_op (0);
      TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                              tl);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_MELT_COIN_EXPIRED_NO_ZOMBIE,
                                             "denomination expired");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_calculate_transaction_list_totals (tl,
                                                          &spent,
                                                          &spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_MELT_COIN_HISTORY_COMPUTATION_FAILED,
                                           "failed to compute coin transaction history");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Refuse to refresh when the coin's value is insufficient
     for the cost of all transactions. */
  if (0 > TALER_amount_cmp (&rmc->coin_value,
                            &spent))
  {
    struct TALER_Amount coin_residual;

    GNUNET_assert (0 <=
                   TALER_amount_subtract (&coin_residual,
                                          &spent,
                                          &rmc->refresh_session.amount_with_fee));
    *mhd_ret = reply_melt_insufficient_funds (
      connection,
      &rmc->refresh_session.coin.coin_pub,
      &rmc->coin_value,
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
 * Execute a "melt".  We have been given a list of valid
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
 * @param cls our `struct MeltContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
melt_transaction (void *cls,
                  struct MHD_Connection *connection,
                  struct TALER_EXCHANGEDB_Session *session,
                  MHD_RESULT *mhd_ret)
{
  struct MeltContext *rmc = cls;
  enum GNUNET_DB_QueryStatus qs;
  uint32_t noreveal_index;

  /* First, make sure coin is 'known' in database */
  if (! rmc->coin_is_dirty)
  {
    qs = TEH_plugin->ensure_coin_known (TEH_plugin->cls,
                                        session,
                                        &rmc->refresh_session.coin);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      *mhd_ret
        = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_DB_COIN_HISTORY_STORE_ERROR,
                                      "could not persist coin data");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  /* Check if we already created a matching refresh_session */
  qs = TEH_plugin->get_melt_index (TEH_plugin->cls,
                                   session,
                                   &rmc->refresh_session.rc,
                                   &noreveal_index);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    TALER_LOG_DEBUG ("Coin was previously melted, returning old reply\n");
    *mhd_ret = reply_melt_success (connection,
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
                                             TALER_EC_MELT_DB_FETCH_ERROR,
                                             "failed to fetch melt index");
    return qs;
  }

  /* check coin has enough funds remaining on it to cover melt cost */
  qs = refresh_check_melt (connection,
                           session,
                           rmc,
                           mhd_ret);
  if (0 > qs)
    return qs; /* if we failed, tell caller */

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
                                             TALER_EC_MELT_DB_STORE_SESSION_ERROR,
                                             "failed to persist melt data");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    return qs;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Handle a "melt" request after the first parsing has
 * happened.  We now need to validate the coins being melted and the
 * session signature and then hand things of to execute the melt
 * operation.  This function parses the JSON arrays and then passes
 * processing on to #melt_transaction().
 *
 * @param connection the MHD connection to handle
 * @param[in,out] rmc details about the melt request
 * @return MHD result code
 */
static MHD_RESULT
handle_melt (struct MHD_Connection *connection,
             struct MeltContext *rmc)
{
  /* verify signature of coin for melt operation */
  {
    struct TALER_RefreshMeltCoinAffirmationPS body = {
      .purpose.size = htonl (sizeof (body)),
      .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT),
      .rc = rmc->refresh_session.rc,
      .h_denom_pub = rmc->refresh_session.coin.denom_pub_hash,
      .coin_pub = rmc->refresh_session.coin.coin_pub
    };

    TALER_amount_hton (&body.amount_with_fee,
                       &rmc->refresh_session.amount_with_fee);
    TALER_amount_hton (&body.melt_fee,
                       &rmc->coin_refresh_fee);

    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_WALLET_COIN_MELT,
          &body,
          &rmc->refresh_session.coin_sig.eddsa_signature,
          &rmc->refresh_session.coin.coin_pub.eddsa_pub))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_MELT_COIN_SIGNATURE_INVALID,
                                         "confirm_sig");
    }
  }

  /* run database transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run melt",
                                &mhd_ret,
                                &melt_transaction,
                                rmc))
      return mhd_ret;
  }

  /* Success. Generate ordinary response. */
  return reply_melt_success (connection,
                             &rmc->refresh_session.rc,
                             rmc->refresh_session.noreveal_index);
}


/**
 * Check for information about the melted coin's denomination,
 * extracting its validity status and fee structure.
 *
 * @param connection HTTP connection we are handling
 * @param rmc parsed request information
 * @return MHD status code
 */
static MHD_RESULT
check_for_denomination_key (struct MHD_Connection *connection,
                            struct MeltContext *rmc)
{
  struct TEH_KS_StateHandle *key_state;

  key_state = TEH_KS_acquire (GNUNET_TIME_absolute_get ());
  if (NULL == key_state)
  {
    TALER_LOG_ERROR ("Lacking keys to operate\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                       "no keys");
  }

  {
    /* Baseline: check if deposits/refreshs are generally
       simply still allowed for this denomination */
    struct TALER_EXCHANGEDB_DenominationKey *dki;
    unsigned int hc;
    enum TALER_ErrorCode ec;

    dki = TEH_KS_denomination_key_lookup_by_hash (
      key_state,
      &rmc->refresh_session.coin.denom_pub_hash,
      TEH_KS_DKU_DEPOSIT,
      &ec,
      &hc);
    /* Consider case that denomination was revoked but
       this coin was already seen and thus refresh is OK. */
    if (NULL == dki)
    {
      dki = TEH_KS_denomination_key_lookup_by_hash (
        key_state,
        &rmc->refresh_session.coin.denom_pub_hash,
        TEH_KS_DKU_RECOUP,
        &ec,
        &hc);
      if (NULL != dki)
      {
        struct GNUNET_HashCode denom_hash;
        enum GNUNET_DB_QueryStatus qs;

        /* Check that the coin is dirty (we have seen it before), as we will
           not just allow melting of a *fresh* coin where the denomination was
           revoked (those must be recouped) */
        qs = TEH_plugin->get_coin_denomination (
          TEH_plugin->cls,
          NULL,
          &rmc->refresh_session.coin.coin_pub,
          &denom_hash);
        if (0 > qs)
        {
          TEH_KS_release (key_state);
          /* There is no good reason for a serialization failure here: */
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
          return TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_MELT_DB_FETCH_ERROR,
                                             "failed to find information about old coin");
        }
        /* sanity check */
        GNUNET_break (0 ==
                      GNUNET_memcmp (&denom_hash,
                                     &rmc->refresh_session.coin.denom_pub_hash));
        if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
        {
          /* We never saw this coin before, so _this_ justification is not OK */
          dki = NULL;
        }
        else
        {
          /* Minor optimization: no need to run the
             "ensure_coin_known" part of the transaction */
          rmc->coin_is_dirty = true;
        }
      }
    }

    /* Consider the case that the denomination expired for deposits, but
       recoup of a refreshed coin refilled the balance of the 'zombie' coin
       and we should thus allow the refresh during the legal period. */
    if (NULL == dki)
    {
      dki = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                    &rmc->refresh_session.coin.
                                                    denom_pub_hash,
                                                    TEH_KS_DKU_ZOMBIE,
                                                    &ec,
                                                    &hc);
      if (NULL != dki)
        rmc->zombie_required = GNUNET_YES; /* check later that zombie is satisfied */
    }
    if (NULL == dki)
    {
      TEH_KS_release (key_state);
      return TALER_MHD_reply_with_error (connection,
                                         hc,
                                         ec,
                                         "unknown denomination");
    }

    TALER_amount_ntoh (&rmc->coin_refresh_fee,
                       &dki->issue.properties.fee_refresh);
    TALER_amount_ntoh (&rmc->coin_value,
                       &dki->issue.properties.value);
    /* check client used sane currency */
    if (GNUNET_YES !=
        TALER_amount_cmp_currency (&rmc->refresh_session.amount_with_fee,
                                   &rmc->coin_value) )
    {
      GNUNET_break_op (0);
      TEH_KS_release (key_state);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_MELT_CURRENCY_MISMATCH,
                                         "value_with_fee");

    }
    /* check coin is actually properly signed */
    if (GNUNET_OK !=
        TALER_test_coin_valid (&rmc->refresh_session.coin,
                               &dki->denom_pub))
    {
      GNUNET_break_op (0);
      TEH_KS_release (key_state);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_MELT_DENOMINATION_SIGNATURE_INVALID,
                                         "denom_sig");
    }
  }
  TEH_KS_release (key_state);

  /* sanity-check that "total melt amount > melt fee" */
  if (0 <
      TALER_amount_cmp (&rmc->coin_refresh_fee,
                        &rmc->refresh_session.amount_with_fee))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_MELT_FEES_EXCEED_CONTRIBUTION,
                                       "melt amount smaller than melting fee");
  }
  return handle_melt (connection,
                      rmc);
}


/**
 * Handle a "/coins/$COIN_PUB/melt" request.  Parses the request into the JSON
 * components and then hands things of to #check_for_denomination_key() to
 * validate the melted coins, the signature and execute the melt using
 * handle_melt().

 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_melt (struct MHD_Connection *connection,
                  const struct TALER_CoinSpendPublicKeyP *coin_pub,
                  const json_t *root)
{
  struct MeltContext rmc;
  enum GNUNET_GenericReturnValue ret;
  MHD_RESULT res;
  struct GNUNET_JSON_Specification spec[] = {
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

  memset (&rmc,
          0,
          sizeof (rmc));
  rmc.refresh_session.coin.coin_pub = *coin_pub;
  ret = TALER_MHD_parse_json_data (connection,
                                   root,
                                   spec);
  if (GNUNET_OK != ret)
    return (GNUNET_SYSERR == ret) ? MHD_NO : MHD_YES;

  res = check_for_denomination_key (connection,
                                    &rmc);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_melt.c */
