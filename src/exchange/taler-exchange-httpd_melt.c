/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
   * UUID of the coin in the known_coins table.
   */
  uint64_t known_coin_id;

  /**
   * Information about the @e coin's value.
   */
  struct TALER_Amount coin_value;

  /**
   * Information about the @e coin's refresh fee.
   */
  struct TALER_Amount coin_refresh_fee;

  /**
   * Refresh master secret, if any of the fresh denominations use CS.
   */
  struct TALER_RefreshMasterSecretP rms;

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

  /**
   * True if @e rms is set.
   */
  bool have_rms;
};


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
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
melt_transaction (void *cls,
                  struct MHD_Connection *connection,
                  MHD_RESULT *mhd_ret)
{
  struct MeltContext *rmc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool balance_ok;

  /* pick challenge and persist it */
  rmc->refresh_session.noreveal_index
    = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_STRONG,
                                TALER_CNC_KAPPA);

  if (0 >
      (qs = TEH_plugin->do_melt (TEH_plugin->cls,
                                 rmc->have_rms
                                 ? &rmc->rms
                                 : NULL,
                                 &rmc->refresh_session,
                                 rmc->known_coin_id,
                                 &rmc->zombie_required,
                                 &balance_ok)))
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
  GNUNET_break (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
  if (rmc->zombie_required)
  {
    GNUNET_break_op (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_EXCHANGE_MELT_COIN_EXPIRED_NO_ZOMBIE,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    GNUNET_break_op (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret
      = TEH_RESPONSE_reply_coin_insufficient_funds (
          connection,
          TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
          &rmc->refresh_session.coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  /* All good, commit, final response will be generated by caller */
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Handle a "melt" request after the first parsing has
 * happened.  Performs the database transactions.
 *
 * @param connection the MHD connection to handle
 * @param[in,out] rmc details about the melt request
 * @return MHD result code
 */
static MHD_RESULT
database_melt (struct MHD_Connection *connection,
               struct MeltContext *rmc)
{
  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_START_FAILED,
                                       "preflight failure");
  }

  /* first, make sure coin is known */
  if (! rmc->coin_is_dirty)
  {
    MHD_RESULT mhd_ret = MHD_NO;
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_make_coin_known (&rmc->refresh_session.coin,
                              connection,
                              &rmc->known_coin_id,
                              &mhd_ret);
    /* no transaction => no serialization failures should be possible */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    if (qs < 0)
      return mhd_ret;
  }

  /* run main database transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run melt",
                                TEH_MT_MELT,
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
check_melt_valid (struct MHD_Connection *connection,
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

  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_legal.abs_time))
  {
    /* Way too late now, even zombies have expired */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &rmc->refresh_session.coin.denom_pub_hash,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
      "MELT");
  }

  if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
  {
    /* This denomination is not yet valid */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &rmc->refresh_session.coin.denom_pub_hash,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
      "MELT");
  }

  rmc->coin_refresh_fee = dk->meta.fees.refresh;
  rmc->coin_value = dk->meta.value;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Melted coin's denomination is worth %s\n",
              TALER_amount2s (&dk->meta.value));

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

  /* verify signature of coin for melt operation */
  if (GNUNET_OK !=
      TALER_wallet_melt_verify (&rmc->refresh_session.amount_with_fee,
                                &rmc->coin_refresh_fee,
                                &rmc->refresh_session.rc,
                                &rmc->refresh_session.coin.denom_pub_hash,
                                &rmc->refresh_session.coin.h_age_commitment,
                                &rmc->refresh_session.coin.coin_pub,
                                &rmc->refresh_session.coin_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_MELT_COIN_SIGNATURE_INVALID,
                                       NULL);
  }

  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit.abs_time))
  {
    /* We are past deposit expiration time, but maybe this is a zombie? */
    struct TALER_DenominationHashP denom_hash;
    enum GNUNET_DB_QueryStatus qs;

    /* Check that the coin is dirty (we have seen it before), as we will
       not just allow melting of a *fresh* coin where the denomination was
       revoked (those must be recouped) */
    qs = TEH_plugin->get_coin_denomination (
      TEH_plugin->cls,
      &rmc->refresh_session.coin.coin_pub,
      &rmc->known_coin_id,
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
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
    {
      /* We never saw this coin before, so _this_ justification is not OK */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &rmc->refresh_session.coin.denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "MELT");
    }
    /* Minor optimization: no need to run the
       "ensure_coin_known" part of the transaction */
    rmc->coin_is_dirty = true;
    /* sanity check */
    if (0 !=
        GNUNET_memcmp (&denom_hash,
                       &rmc->refresh_session.coin.denom_pub_hash))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_ec (
        connection,
        TALER_EC_EXCHANGE_GENERIC_COIN_CONFLICTING_DENOMINATION_KEY,
        TALER_B2S (&denom_hash));
    }
    rmc->zombie_required = true;   /* check later that zombie is satisfied */
  }

  return database_melt (connection,
                        rmc);
}


MHD_RESULT
TEH_handler_melt (struct MHD_Connection *connection,
                  const struct TALER_CoinSpendPublicKeyP *coin_pub,
                  const json_t *root)
{
  struct MeltContext rmc;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_denom_sig ("denom_sig",
                               &rmc.refresh_session.coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &rmc.refresh_session.coin.denom_pub_hash),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("age_commitment_hash",
                                   &rmc.refresh_session.coin.h_age_commitment)),
    GNUNET_JSON_spec_fixed_auto ("confirm_sig",
                                 &rmc.refresh_session.coin_sig),
    TALER_JSON_spec_amount ("value_with_fee",
                            TEH_currency,
                            &rmc.refresh_session.amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("rc",
                                 &rmc.refresh_session.rc),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("rms",
                                   &rmc.rms)),
    GNUNET_JSON_spec_end ()
  };

  memset (&rmc, 0, sizeof (rmc));
  rmc.refresh_session.coin.coin_pub = *coin_pub;

  {
    enum GNUNET_GenericReturnValue ret;
    ret = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_OK != ret)
      return (GNUNET_SYSERR == ret) ? MHD_NO : MHD_YES;
  }

  rmc.have_rms = (NULL != json_object_get (root,
                                           "rms"));

  {
    MHD_RESULT res;

    res = check_melt_valid (connection,
                            &rmc);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_melt.c */
