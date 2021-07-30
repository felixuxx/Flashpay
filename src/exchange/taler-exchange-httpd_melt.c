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
#include "taler-exchange-httpd_keys.h"
#include "taler_exchangedb_lib.h"


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
                                       TALER_EC_EXCHANGE_MELT_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_CONFLICT,
    GNUNET_JSON_pack_string ("hint",
                             TALER_ErrorCode_get_hint (
                               TALER_EC_EXCHANGE_MELT_INSUFFICIENT_FUNDS)),
    GNUNET_JSON_pack_uint64 ("code",
                             TALER_EC_EXCHANGE_MELT_INSUFFICIENT_FUNDS),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    TALER_JSON_pack_amount ("original_value",
                            coin_value),
    TALER_JSON_pack_amount ("residual_value",
                            residual),
    TALER_JSON_pack_amount ("requested_value",
                            requested),
    GNUNET_JSON_pack_array_steal ("history",
                                  history));
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
  enum TALER_ErrorCode ec;

  if (TALER_EC_NONE !=
      (ec = TEH_keys_exchange_sign (&body,
                                    &pub,
                                    &sig)))
  {
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_uint64 ("noreveal_index",
                             noreveal_index),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
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
   * Set to true if this coin's denomination was revoked and the operation
   * is thus only allowed for zombie coins where the transaction
   * history includes a #TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP.
   */
  bool zombie_required;

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
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "coin transaction history");
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
        rmc->zombie_required = false; /* clear flag: was satisfied! */
        break;
      }
    }
    if (rmc->zombie_required)
    {
      /* zombie status not satisfied */
      GNUNET_break_op (0);
      TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                              tl);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_EXCHANGE_MELT_COIN_EXPIRED_NO_ZOMBIE,
                                             NULL);
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
                                           TALER_EC_EXCHANGE_MELT_COIN_HISTORY_COMPUTATION_FAILED,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Refuse to refresh when the coin's value is insufficient
     for the cost of all transactions. */
  if (0 > TALER_amount_cmp (&rmc->coin_value,
                            &spent))
  {
    struct TALER_Amount coin_residual;
    struct TALER_Amount spent_already;

    /* First subtract the melt cost from 'spent' to
       compute the total amount already spent of the coin */
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&spent_already,
                                          &spent,
                                          &rmc->refresh_session.amount_with_fee));
    /* The residual coin value is the original coin value minus
       what we have spent (before the melt) */
    GNUNET_assert (0 <=
                   TALER_amount_subtract (&coin_residual,
                                          &rmc->coin_value,
                                          &spent_already));
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
    qs = TEH_make_coin_known (&rmc->refresh_session.coin,
                              connection,
                              session,
                              mhd_ret);
    if (qs < 0)
      return qs;
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
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "melt index");
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
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "melt");
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
                                         TALER_EC_EXCHANGE_MELT_COIN_SIGNATURE_INVALID,
                                         NULL);
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
  /* Baseline: check if deposits/refreshs are generally
     simply still allowed for this denomination */
  struct TEH_DenominationKey *dk;
  MHD_RESULT mret;

  dk = TEH_keys_denomination_by_hash (
    &rmc->refresh_session.coin.denom_pub_hash,
    connection,
    &mret);
  if (NULL == dk)
    return mret;
  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_legal))
  {
    struct GNUNET_TIME_Absolute now;

    now = GNUNET_TIME_absolute_get ();
    (void) GNUNET_TIME_round_abs (&now);
    /* Way too late now, even zombies have expired */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &rmc->refresh_session.coin.denom_pub_hash,
      now,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
      "MELT");
  }
  if (GNUNET_TIME_absolute_is_future (dk->meta.start))
  {
    struct GNUNET_TIME_Absolute now;

    now = GNUNET_TIME_absolute_get ();
    (void) GNUNET_TIME_round_abs (&now);
    /* This denomination is not yet valid */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &rmc->refresh_session.coin.denom_pub_hash,
      now,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
      "MELT");
  }
  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit))
  {
    /* We are past deposit expiration time, but maybe this is a zombie? */
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
      /* There is no good reason for a serialization failure here: */
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "coin denomination");
    }
    /* sanity check */
    GNUNET_break (0 ==
                  GNUNET_memcmp (&denom_hash,
                                 &rmc->refresh_session.coin.denom_pub_hash));
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* We never saw this coin before, so _this_ justification is not OK */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &rmc->refresh_session.coin.denom_pub_hash,
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "MELT");
    }
    else
    {
      /* Minor optimization: no need to run the
         "ensure_coin_known" part of the transaction */
      rmc->coin_is_dirty = true;
    }
    rmc->zombie_required = true;   /* check later that zombie is satisfied */
  }

  rmc->coin_refresh_fee = dk->meta.fee_refresh;
  rmc->coin_value = dk->meta.value;
  /* check coin is actually properly signed */
  if (GNUNET_OK !=
      TALER_test_coin_valid (&rmc->refresh_session.coin,
                             &dk->denom_pub))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
                                       NULL);
  }

  /* sanity-check that "total melt amount > melt fee" */
  if (0 <
      TALER_amount_cmp (&rmc->coin_refresh_fee,
                        &rmc->refresh_session.amount_with_fee))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_MELT_FEES_EXCEED_CONTRIBUTION,
                                       NULL);
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
                            TEH_currency,
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
