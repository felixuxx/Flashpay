/*
  This file is part of TALER
  Copyright (C) 2017-2022 Taler Systems SA

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
 * @file taler-exchange-httpd_recoup.c
 * @brief Handle /recoup requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_db.h"
#include "taler-exchange-httpd_recoup.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"
#include "taler_exchangedb_lib.h"

/**
 * Closure for #recoup_transaction.
 */
struct RecoupContext
{
  /**
   * Hash identifying the withdraw request.
   */
  struct TALER_BlindedCoinHashP h_coin_ev;

  /**
   * Set by #recoup_transaction() to the reserve that will
   * receive the recoup, if #refreshed is #GNUNET_NO.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Details about the coin.
   */
  const struct TALER_CoinPublicInfo *coin;

  /**
   * Key used to blind the coin.
   */
  const union GNUNET_CRYPTO_BlindingSecretP *coin_bks;

  /**
   * Signature of the coin requesting recoup.
   */
  const struct TALER_CoinSpendSignatureP *coin_sig;

  /**
   * Unique ID of the withdraw operation in the reserves_out table.
   */
  uint64_t reserve_out_serial_id;

  /**
   * Unique ID of the coin in the known_coins table.
   */
  uint64_t known_coin_id;

  /**
   * Set by #recoup_transaction to the timestamp when the recoup
   * was accepted.
   */
  struct GNUNET_TIME_Timestamp now;

};


/**
 * Execute a "recoup".  The validity of the coin and signature have
 * already been checked.  The database must now check that the coin is
 * not (double) spent, and execute the transaction.
 *
 * IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls the `struct RecoupContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
recoup_transaction (void *cls,
                    struct MHD_Connection *connection,
                    MHD_RESULT *mhd_ret)
{
  struct RecoupContext *pc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool recoup_ok;
  bool internal_failure;

  /* Finally, store new refund data */
  pc->now = GNUNET_TIME_timestamp_get ();
  qs = TEH_plugin->do_recoup (TEH_plugin->cls,
                              &pc->reserve_pub,
                              pc->reserve_out_serial_id,
                              pc->coin_bks,
                              &pc->coin->coin_pub,
                              pc->known_coin_id,
                              pc->coin_sig,
                              &pc->now,
                              &recoup_ok,
                              &internal_failure);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "do_recoup");
    return qs;
  }

  if (internal_failure)
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
      "do_recoup");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! recoup_ok)
  {
    *mhd_ret = TEH_RESPONSE_reply_coin_insufficient_funds (
      connection,
      TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
      &pc->coin->denom_pub_hash,
      &pc->coin->coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * We have parsed the JSON information about the recoup request. Do
 * some basic sanity checks (especially that the signature on the
 * request and coin is valid) and then execute the recoup operation.
 * Note that we need the DB to check the fee structure, so this is not
 * done here but during the recoup_transaction().
 *
 * @param connection the MHD connection to handle
 * @param coin information about the coin
 * @param exchange_vals values contributed by the exchange
 *         during withdrawal
 * @param coin_bks blinding data of the coin (to be checked)
 * @param nonce coin's nonce if CS is used
 * @param coin_sig signature of the coin
 * @return MHD result code
 */
static MHD_RESULT
verify_and_execute_recoup (
  struct MHD_Connection *connection,
  const struct TALER_CoinPublicInfo *coin,
  const struct TALER_ExchangeWithdrawValues *exchange_vals,
  const union GNUNET_CRYPTO_BlindingSecretP *coin_bks,
  const union GNUNET_CRYPTO_BlindSessionNonce *nonce,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct RecoupContext pc;
  const struct TEH_DenominationKey *dk;
  MHD_RESULT mret;

  /* check denomination exists and is in recoup mode */
  dk = TEH_keys_denomination_by_hash (&coin->denom_pub_hash,
                                      connection,
                                      &mret);
  if (NULL == dk)
    return mret;
  if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit.abs_time))
  {
    /* This denomination is past the expiration time for recoup */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &coin->denom_pub_hash,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
      "RECOUP");
  }
  if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
  {
    /* This denomination is not yet valid */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &coin->denom_pub_hash,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
      "RECOUP");
  }
  if (! dk->recoup_possible)
  {
    /* This denomination is not eligible for recoup */
    return TEH_RESPONSE_reply_expired_denom_pub_hash (
      connection,
      &coin->denom_pub_hash,
      TALER_EC_EXCHANGE_RECOUP_NOT_ELIGIBLE,
      "RECOUP");
  }

  /* check denomination signature */
  switch (dk->denom_pub.bsign_pub_key->cipher)
  {
  case GNUNET_CRYPTO_BSA_RSA:
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_RSA]++;
    break;
  case GNUNET_CRYPTO_BSA_CS:
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_CS]++;
    break;
  default:
    break;
  }
  if (GNUNET_YES !=
      TALER_test_coin_valid (coin,
                             &dk->denom_pub))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
      NULL);
  }

  /* check recoup request signature */
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_recoup_verify (&coin->denom_pub_hash,
                                  coin_bks,
                                  &coin->coin_pub,
                                  coin_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_RECOUP_SIGNATURE_INVALID,
      NULL);
  }

  /* re-compute client-side blinding so we can
     (a bit later) check that this coin was indeed
     signed by us. */
  {
    struct TALER_CoinPubHashP c_hash;
    struct TALER_BlindedPlanchet blinded_planchet;

    if (GNUNET_OK !=
        TALER_denom_blind (&dk->denom_pub,
                           coin_bks,
                           nonce,
                           &coin->h_age_commitment,
                           &coin->coin_pub,
                           exchange_vals,
                           &c_hash,
                           &blinded_planchet))
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_EXCHANGE_RECOUP_BLINDING_FAILED,
        NULL);
    }
    TALER_coin_ev_hash (&blinded_planchet,
                        &coin->denom_pub_hash,
                        &pc.h_coin_ev);
    TALER_blinded_planchet_free (&blinded_planchet);
  }

  pc.coin_sig = coin_sig;
  pc.coin_bks = coin_bks;
  pc.coin = coin;

  {
    MHD_RESULT mhd_ret = MHD_NO;
    enum GNUNET_DB_QueryStatus qs;

    /* make sure coin is 'known' in database */
    qs = TEH_make_coin_known (coin,
                              connection,
                              &pc.known_coin_id,
                              &mhd_ret);
    /* no transaction => no serialization failures should be possible */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    if (qs < 0)
      return mhd_ret;
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_reserve_by_h_blind (TEH_plugin->cls,
                                             &pc.h_coin_ev,
                                             &pc.reserve_pub,
                                             &pc.reserve_out_serial_id);
    if (0 > qs)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "get_reserve_by_h_blind");
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Recoup requested for unknown envelope %s\n",
                  GNUNET_h2s (&pc.h_coin_ev.hash));
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_RECOUP_WITHDRAW_NOT_FOUND,
        NULL);
    }
  }

  /* Perform actual recoup transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run recoup",
                                TEH_MT_REQUEST_OTHER,
                                &mhd_ret,
                                &recoup_transaction,
                                &pc))
      return mhd_ret;
  }
  /* Recoup succeeded, return result */
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_OK,
                                    GNUNET_JSON_pack_data_auto (
                                      "reserve_pub",
                                      &pc.reserve_pub));
}


/**
 * Handle a "/coins/$COIN_PUB/recoup" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #verify_and_execute_recoup() to further
 * check the details of the operation specified.  If everything checks out,
 * this will ultimately lead to the refund being executed, or rejected.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_recoup (struct MHD_Connection *connection,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const json_t *root)
{
  enum GNUNET_GenericReturnValue ret;
  struct TALER_CoinPublicInfo coin;
  union GNUNET_CRYPTO_BlindingSecretP coin_bks;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct TALER_ExchangeWithdrawValues exchange_vals;
  union GNUNET_CRYPTO_BlindSessionNonce nonce;
  bool no_nonce;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &coin.denom_pub_hash),
    TALER_JSON_spec_denom_sig ("denom_sig",
                               &coin.denom_sig),
    TALER_JSON_spec_exchange_withdraw_values ("ewv",
                                              &exchange_vals),
    GNUNET_JSON_spec_fixed_auto ("coin_blind_key_secret",
                                 &coin_bks),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &coin.h_age_commitment),
      &coin.no_age_commitment),
    // FIXME: should be renamed to just 'nonce'!
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("cs_nonce",
                                   &nonce),
      &no_nonce),
    GNUNET_JSON_spec_end ()
  };

  memset (&coin,
          0,
          sizeof (coin));
  coin.coin_pub = *coin_pub;
  ret = TALER_MHD_parse_json_data (connection,
                                   root,
                                   spec);
  if (GNUNET_SYSERR == ret)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == ret)
    return MHD_YES; /* failure */
  {
    MHD_RESULT res;

    res = verify_and_execute_recoup (connection,
                                     &coin,
                                     &exchange_vals,
                                     &coin_bks,
                                     no_nonce
                                     ? NULL
                                     : &nonce,
                                     &coin_sig);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_recoup.c */
