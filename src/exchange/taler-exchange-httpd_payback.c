/*
  This file is part of TALER
  Copyright (C) 2017 Inria and GNUnet e.V.

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
 * @file taler-exchange-httpd_payback.c
 * @brief Handle /payback requests; parses the POST and JSON and
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
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_payback.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_validation.h"


/**
 * A wallet asked for /payback, but we do not know anything about the
 * original withdraw operation specified. Generates a 404 reply.
 *
 * @param connection connection to the client
 * @param ec Taler error code
 * @return MHD result code
 */
static int
reply_payback_unknown (struct MHD_Connection *connection,
                       enum TALER_ErrorCode ec)
{
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s, s:I}",
                                       "error", "blinded coin unknown",
                                       "code", (json_int_t) ec);
}


/**
 * A wallet asked for /payback, return the successful response.
 *
 * @param connection connection to the client
 * @param coin_pub coin for which we are processing the payback request
 * @param old_coin_pub public key of the old coin that will receive the payback
 * @param amount the amount we will wire back
 * @param timestamp when did the exchange receive the /payback request
 * @return MHD result code
 */
static int
reply_payback_refresh_success (struct MHD_Connection *connection,
                               const struct TALER_CoinSpendPublicKeyP *coin_pub,
                               const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
                               const struct TALER_Amount *amount,
                               struct GNUNET_TIME_Absolute timestamp)
{
  struct TALER_PaybackRefreshConfirmationPS pc;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK_REFRESH);
  pc.purpose.size = htonl (sizeof (struct TALER_PaybackRefreshConfirmationPS));
  pc.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  TALER_amount_hton (&pc.payback_amount,
                     amount);
  pc.coin_pub = *coin_pub;
  pc.old_coin_pub = *old_coin_pub;
  if (GNUNET_OK !=
      TEH_KS_sign (&pc.purpose,
                   &pub,
                   &sig))
  {
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                              "no keys");
  }
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o, s:o, s:o, s:o}",
                                       "old_coin_pub", GNUNET_JSON_from_data_auto (old_coin_pub),
                                       "timestamp", GNUNET_JSON_from_time_abs (timestamp),
                                       "amount", TALER_JSON_from_amount (amount),
                                       "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
                                       "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * A wallet asked for /payback, return the successful response.
 *
 * @param connection connection to the client
 * @param coin_pub coin for which we are processing the payback request
 * @param reserve_pub public key of the reserve that will receive the payback
 * @param amount the amount we will wire back
 * @param timestamp when did the exchange receive the /payback request
 * @return MHD result code
 */
static int
reply_payback_success (struct MHD_Connection *connection,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       const struct TALER_ReservePublicKeyP *reserve_pub,
                       const struct TALER_Amount *amount,
                       struct GNUNET_TIME_Absolute timestamp)
{
  struct TALER_PaybackConfirmationPS pc;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK);
  pc.purpose.size = htonl (sizeof (struct TALER_PaybackConfirmationPS));
  pc.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  TALER_amount_hton (&pc.payback_amount,
                     amount);
  pc.coin_pub = *coin_pub;
  pc.reserve_pub = *reserve_pub;
  if (GNUNET_OK !=
      TEH_KS_sign (&pc.purpose,
                   &pub,
                   &sig))
  {
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                              "no keys");
  }
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_OK,
                                       "{s:o, s:o, s:o, s:o, s:o}",
                                       "reserve_pub", GNUNET_JSON_from_data_auto (reserve_pub),
                                       "timestamp", GNUNET_JSON_from_time_abs (timestamp),
                                       "amount", TALER_JSON_from_amount (amount),
                                       "exchange_sig", GNUNET_JSON_from_data_auto (&sig),
                                       "exchange_pub", GNUNET_JSON_from_data_auto (&pub));
}


/**
 * Closure for #payback_transaction.
 */
struct PaybackContext
{
  /**
   * Hash of the blinded coin.
   */
  struct GNUNET_HashCode h_blind;

  /**
   * Full value of the coin.
   */
  struct TALER_Amount value;

  /**
   * Details about the coin.
   */
  const struct TALER_CoinPublicInfo *coin;

  /**
   * Key used to blind the coin.
   */
  const struct TALER_DenominationBlindingKeyP *coin_bks;

  /**
   * Signature of the coin requesting payback.
   */
  const struct TALER_CoinSpendSignatureP *coin_sig;

  union
  {
    /**
     * Set by #payback_transaction() to the reserve that will
     * receive the payback, if #refreshed is #GNUNET_NO.
     */
    struct TALER_ReservePublicKeyP reserve_pub;

    /**
     * Set by #payback_transaction() to the old coin that will
     * receive the payback, if #refreshed is #GNUNET_YES.
     */
    struct TALER_CoinSpendPublicKeyP old_coin_pub;
  } target;

  /**
   * Set by #payback_transaction() to the amount that will be paid back
   */
  struct TALER_Amount amount;

  /**
   * Set by #payback_transaction to the timestamp when the payback
   * was accepted.
   */
  struct GNUNET_TIME_Absolute now;

  /**
   * #GNUNET_YES if the client claims the coin originated from a refresh.
   */
  int refreshed;

};


/**
 * Execute a "/payback".  The validity of the coin and signature have
 * already been checked.  The database must now check that the coin is
 * not (double) spent, and execute the transaction.
 *
 * IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls the `struct PaybackContext *`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
payback_transaction (void *cls,
                     struct MHD_Connection *connection,
                     struct TALER_EXCHANGEDB_Session *session,
                     int *mhd_ret)
{
  struct PaybackContext *pc = cls;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_Amount spent;
  enum GNUNET_DB_QueryStatus qs;

  /* Check whether a payback is allowed, and if so, to which
     reserve / account the money should go */
  if (pc->refreshed)
  {
    qs = TEH_plugin->get_old_coin_by_h_blind (TEH_plugin->cls,
                                              session,
                                              &pc->h_blind,
                                              &pc->target.old_coin_pub);
    if (0 > qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_break (0);
        *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                         TALER_EC_PAYBACK_DB_FETCH_FAILED);
      }
      return qs;
    }
  }
  else
  {
    qs = TEH_plugin->get_reserve_by_h_blind (TEH_plugin->cls,
                                             session,
                                             &pc->h_blind,
                                             &pc->target.reserve_pub);
    if (0 > qs)
    {
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_break (0);
        *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                         TALER_EC_PAYBACK_DB_FETCH_FAILED);
      }
      return qs;
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_break_op (0);
    *mhd_ret = reply_payback_unknown (connection,
                                      TALER_EC_PAYBACK_WITHDRAW_NOT_FOUND);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Calculate remaining balance. */
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          session,
                                          &pc->coin->coin_pub,
                                          GNUNET_YES,
                                          &tl);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                       TALER_EC_PAYBACK_DB_FETCH_FAILED);
    }
    return qs;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (pc->value.currency,
                                        &spent));
  if (GNUNET_OK !=
      TEH_DB_calculate_transaction_list_totals (tl,
                                                &spent,
                                                &spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                     TALER_EC_PAYBACK_HISTORY_DB_ERROR);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&pc->amount,
                             &pc->value,
                             &spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                     TALER_EC_PAYBACK_COIN_BALANCE_NEGATIVE);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if ( (0 == pc->amount.fraction) &&
       (0 == pc->amount.value) )
  {
    TEH_plugin->rollback (TEH_plugin->cls,
                          session);
    *mhd_ret = TEH_RESPONSE_reply_coin_insufficient_funds (connection,
                                                           TALER_EC_PAYBACK_COIN_BALANCE_ZERO,
                                                           tl);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);
  pc->now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&pc->now);

  /* add coin to list of wire transfers for payback */
  if (pc->refreshed)
  {
    qs = TEH_plugin->insert_payback_refresh_request (TEH_plugin->cls,
                                                     session,
                                                     pc->coin,
                                                     pc->coin_sig,
                                                     pc->coin_bks,
                                                     &pc->amount,
                                                     &pc->h_blind,
                                                     pc->now);
  }
  else
  {
    qs = TEH_plugin->insert_payback_request (TEH_plugin->cls,
                                             session,
                                             &pc->target.reserve_pub,
                                             pc->coin,
                                             pc->coin_sig,
                                             pc->coin_bks,
                                             &pc->amount,
                                             &pc->h_blind,
                                             pc->now);
  }
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      TALER_LOG_WARNING ("Failed to store /payback information in database\n");
      *mhd_ret = TEH_RESPONSE_reply_internal_db_error (connection,
                                                       TALER_EC_PAYBACK_DB_PUT_FAILED);
    }
    return qs;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * We have parsed the JSON information about the payback request. Do
 * some basic sanity checks (especially that the signature on the
 * request and coin is valid) and then execute the payback operation.
 * Note that we need the DB to check the fee structure, so this is not
 * done here.
 *
 * @param connection the MHD connection to handle
 * @param coin information about the coin
 * @param coin_bks blinding data of the coin (to be checked)
 * @param coin_sig signature of the coin
 * @param refreshed #GNUNET_YES if the coin was refreshed
 * @return MHD result code
 */
static int
verify_and_execute_payback (struct MHD_Connection *connection,
                            const struct TALER_CoinPublicInfo *coin,
                            const struct TALER_DenominationBlindingKeyP *coin_bks,
                            const struct TALER_CoinSpendSignatureP *coin_sig,
                            int refreshed)
{
  struct PaybackContext pc;
  struct TEH_KS_StateHandle *key_state;
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TALER_PaybackRequestPS pr;
  struct GNUNET_HashCode c_hash;
  char *coin_ev;
  size_t coin_ev_size;

  /* check denomination exists and is in payback mode */
  key_state = TEH_KS_acquire (GNUNET_TIME_absolute_get ());
  if (NULL == key_state)
  {
    TALER_LOG_ERROR ("Lacking keys to operate\n");
    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_EXCHANGE_BAD_CONFIGURATION,
                                              "no keys");
  }
  dki = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                &coin->denom_pub_hash,
                                                TEH_KS_DKU_PAYBACK);
  if (NULL == dki)
  {
    TEH_KS_release (key_state);
    TALER_LOG_WARNING ("Denomination key in /payback request not in payback mode\n");
    return TEH_RESPONSE_reply_arg_unknown (connection,
                                           TALER_EC_PAYBACK_DENOMINATION_KEY_UNKNOWN,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&pc.value,
                     &dki->issue.properties.value);

  /* check denomination signature */
  if (GNUNET_YES !=
      TALER_test_coin_valid (coin,
                             &dki->denom_pub))
  {
    TALER_LOG_WARNING ("Invalid coin passed for /payback\n");
    TEH_KS_release (key_state);
    return TEH_RESPONSE_reply_signature_invalid (connection,
                                                 TALER_EC_PAYBACK_DENOMINATION_SIGNATURE_INVALID,
                                                 "denom_sig");
  }

  /* check payback request signature */
  pr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_PAYBACK);
  pr.purpose.size = htonl (sizeof (struct TALER_PaybackRequestPS));
  pr.coin_pub = coin->coin_pub;
  pr.h_denom_pub = dki->issue.properties.denom_hash;
  pr.coin_blind = *coin_bks;

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_PAYBACK,
                                  &pr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin->coin_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on /payback request\n");
    TEH_KS_release (key_state);
    return TEH_RESPONSE_reply_signature_invalid (connection,
                                                 TALER_EC_PAYBACK_SIGNATURE_INVALID,
                                                 "coin_sig");
  }

  GNUNET_CRYPTO_hash (&coin->coin_pub.eddsa_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &c_hash);
  if (GNUNET_YES !=
      GNUNET_CRYPTO_rsa_blind (&c_hash,
                               &coin_bks->bks,
                               dki->denom_pub.rsa_public_key,
                               &coin_ev,
                               &coin_ev_size))
  {
    GNUNET_break (0);
    TEH_KS_release (key_state);

    return TEH_RESPONSE_reply_internal_error (connection,
                                              TALER_EC_PAYBACK_BLINDING_FAILED,
                                              "coin_bks");
  }
  TEH_KS_release (key_state);
  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &pc.h_blind);
  GNUNET_free (coin_ev);

  /* make sure coin is 'known' in database */
  {
    struct TEH_DB_KnowCoinContext kcc;
    int mhd_ret;

    kcc.coin = coin;
    kcc.connection = connection;
    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "know coin for payback",
                                &mhd_ret,
                                &TEH_DB_know_coin_transaction,
                                &kcc))
      return mhd_ret;
  }

  pc.coin_sig = coin_sig;
  pc.coin_bks = coin_bks;
  pc.coin = coin;
  pc.refreshed = refreshed;
  {
    int mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run payback",
                                &mhd_ret,
                                &payback_transaction,
                                &pc))
      return mhd_ret;
  }
  return (refreshed)
    ? reply_payback_refresh_success (connection,
                                     &coin->coin_pub,
                                     &pc.target.old_coin_pub,
                                     &pc.amount,
                                     pc.now)
    : reply_payback_success (connection,
                             &coin->coin_pub,
                             &pc.target.reserve_pub,
                             &pc.amount,
                             pc.now);
}


/**
 * Handle a "/payback" request.  Parses the JSON, and, if successful,
 * passes the JSON data to #verify_and_execute_payback() to
 * further check the details of the operation specified.  If
 * everything checks out, this will ultimately lead to the "/refund"
 * being executed, or rejected.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_PAYBACK_handler_payback (struct TEH_RequestHandler *rh,
                             struct MHD_Connection *connection,
                             void **connection_cls,
                             const char *upload_data,
                             size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct TALER_CoinPublicInfo coin;
  struct TALER_DenominationBlindingKeyP coin_bks;
  struct TALER_CoinSpendSignatureP coin_sig;
  int refreshed = GNUNET_NO;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &coin.denom_pub_hash),
    TALER_JSON_spec_denomination_signature ("denom_sig",
                                            &coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &coin.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_blind_key_secret",
                                 &coin_bks),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_mark_optional
    (GNUNET_JSON_spec_boolean ("refreshed",
                               &refreshed)),
    GNUNET_JSON_spec_end ()
  };

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TEH_PARSE_json_data (connection,
                             json,
                             spec);
  json_decref (json);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == res)
    return MHD_YES; /* failure */
  res = verify_and_execute_payback (connection,
                                    &coin,
                                    &coin_bks,
                                    &coin_sig,
                                    refreshed);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_payback.c */
