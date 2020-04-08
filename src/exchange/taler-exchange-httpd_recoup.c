/*
  This file is part of TALER
  Copyright (C) 2017-2020 Taler Systems SA

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
#include "taler-exchange-httpd_recoup.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Closure for #recoup_transaction.
 */
struct RecoupContext
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
   * Signature of the coin requesting recoup.
   */
  const struct TALER_CoinSpendSignatureP *coin_sig;

  /**
   * Where does the value of the recouped coin go? Which member
   * of the union is valid depends on @e refreshed.
   */
  union
  {
    /**
     * Set by #recoup_transaction() to the reserve that will
     * receive the recoup, if #refreshed is #GNUNET_NO.
     */
    struct TALER_ReservePublicKeyP reserve_pub;

    /**
     * Set by #recoup_transaction() to the old coin that will
     * receive the recoup, if #refreshed is #GNUNET_YES.
     */
    struct TALER_CoinSpendPublicKeyP old_coin_pub;
  } target;

  /**
   * Set by #recoup_transaction() to the amount that will be paid back
   */
  struct TALER_Amount amount;

  /**
   * Set by #recoup_transaction to the timestamp when the recoup
   * was accepted.
   */
  struct GNUNET_TIME_Absolute now;

  /**
   * #GNUNET_YES if the client claims the coin originated from a refresh.
   */
  int refreshed;

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
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
recoup_transaction (void *cls,
                    struct MHD_Connection *connection,
                    struct TALER_EXCHANGEDB_Session *session,
                    MHD_RESULT *mhd_ret)
{
  struct RecoupContext *pc = cls;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_Amount spent;
  struct TALER_Amount recouped;
  enum GNUNET_DB_QueryStatus qs;
  int existing_recoup_found;

  /* Check whether a recoup is allowed, and if so, to which
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
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_RECOUP_DB_FETCH_FAILED,
                                               "failed to fetch old coin of blind coin");
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
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_RECOUP_DB_FETCH_FAILED,
                                               "failed to fetch reserve of blinded coin");
      }
      return qs;
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Recoup requested for unknown envelope %s\n",
                GNUNET_h2s (&pc->h_blind));
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_RECOUP_WITHDRAW_NOT_FOUND,
                                           "envelope unknown");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Calculate remaining balance, including recoups already applied. */
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
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_RECOUP_DB_FETCH_FAILED,
                                             "failed to fetch coin transaction history");
    }
    return qs;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (pc->value.currency,
                                        &spent));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (pc->value.currency,
                                        &recouped));
  /* Check if this coin has been recouped already at least once */
  existing_recoup_found = GNUNET_NO;
  for (struct TALER_EXCHANGEDB_TransactionList *pos = tl;
       NULL != pos;
       pos = pos->next)
  {
    if ( (TALER_EXCHANGEDB_TT_RECOUP == pos->type) ||
         (TALER_EXCHANGEDB_TT_RECOUP_REFRESH == pos->type) )
    {
      existing_recoup_found = GNUNET_YES;
      break;
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
                                           TALER_EC_RECOUP_HISTORY_DB_ERROR,
                                           "failed to calculate old coin transaction history");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Recoup: calculated spent %s\n",
              TALER_amount2s (&spent));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Recoup: coin value %s\n",
              TALER_amount2s (&pc->value));
  if (0 >
      TALER_amount_subtract (&pc->amount,
                             &pc->value,
                             &spent))
  {
    GNUNET_break (0);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_RECOUP_COIN_BALANCE_NEGATIVE,
                                           "calculated negative coin balance");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if ( (0 == pc->amount.fraction) &&
       (0 == pc->amount.value) )
  {
    /* Recoup has no effect: coin fully spent! */
    enum GNUNET_DB_QueryStatus ret;

    TEH_plugin->rollback (TEH_plugin->cls,
                          session);
    if (GNUNET_NO == existing_recoup_found)
    {
      /* Refuse: insufficient funds for recoup */
      *mhd_ret = TEH_RESPONSE_reply_coin_insufficient_funds (connection,
                                                             TALER_EC_RECOUP_COIN_BALANCE_ZERO,
                                                             &pc->coin->coin_pub,
                                                             tl);
      ret = GNUNET_DB_STATUS_HARD_ERROR;
    }
    else
    {
      /* We didn't add any new recoup transaction, but there was at least
         one recoup before, so we give a success response (idempotency!) */
      ret = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    }
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    return ret;
  }
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);
  pc->now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&pc->now);

  /* add coin to list of wire transfers for recoup */
  if (pc->refreshed)
  {
    qs = TEH_plugin->insert_recoup_refresh_request (TEH_plugin->cls,
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
    qs = TEH_plugin->insert_recoup_request (TEH_plugin->cls,
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
      TALER_LOG_WARNING ("Failed to store recoup information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_RECOUP_DB_PUT_FAILED,
                                             "failed to persist recoup data");
    }
    return qs;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
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
 * @param coin_bks blinding data of the coin (to be checked)
 * @param coin_sig signature of the coin
 * @param refreshed #GNUNET_YES if the coin was refreshed
 * @return MHD result code
 */
static MHD_RESULT
verify_and_execute_recoup (struct MHD_Connection *connection,
                           const struct TALER_CoinPublicInfo *coin,
                           const struct
                           TALER_DenominationBlindingKeyP *coin_bks,
                           const struct TALER_CoinSpendSignatureP *coin_sig,
                           int refreshed)
{
  struct RecoupContext pc;
  const struct TALER_EXCHANGEDB_DenominationKey *dki;
  struct GNUNET_HashCode c_hash;
  void *coin_ev;
  size_t coin_ev_size;
  enum TALER_ErrorCode ec;
  unsigned int hc;

  /* check denomination exists and is in recoup mode */
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
    dki = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                  &coin->denom_pub_hash,
                                                  TEH_KS_DKU_RECOUP,
                                                  &ec,
                                                  &hc);
    if (NULL == dki)
    {
      TEH_KS_release (key_state);
      TALER_LOG_WARNING (
        "Denomination key in recoup request not in recoup mode\n");
      return TALER_MHD_reply_with_error (connection,
                                         hc,
                                         ec,
                                         "denomination not valid for recoup");
    }
    TALER_amount_ntoh (&pc.value,
                       &dki->issue.properties.value);

    /* check denomination signature */
    if (GNUNET_YES !=
        TALER_test_coin_valid (coin,
                               &dki->denom_pub))
    {
      TALER_LOG_WARNING ("Invalid coin passed for recoup\n");
      TEH_KS_release (key_state);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_RECOUP_DENOMINATION_SIGNATURE_INVALID,
                                         "denom_sig");
    }

    /* check recoup request signature */
    {
      struct TALER_RecoupRequestPS pr = {
        .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP),
        .purpose.size = htonl (sizeof (struct TALER_RecoupRequestPS)),
        .coin_pub = coin->coin_pub,
        .h_denom_pub = dki->issue.properties.denom_hash,
        .coin_blind = *coin_bks
      };

      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_RECOUP,
                                      &pr,
                                      &coin_sig->eddsa_signature,
                                      &coin->coin_pub.eddsa_pub))
      {
        TALER_LOG_WARNING ("Invalid signature on recoup request\n");
        TEH_KS_release (key_state);
        return TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_FORBIDDEN,
                                           TALER_EC_RECOUP_SIGNATURE_INVALID,
                                           "coin_sig");
      }
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
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_RECOUP_BLINDING_FAILED,
                                         "coin_bks");
    }
    TEH_KS_release (key_state);
  }
  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &pc.h_blind);
  GNUNET_free (coin_ev);

  /* make sure coin is 'known' in database */
  {
    struct TEH_DB_KnowCoinContext kcc;
    MHD_RESULT mhd_ret;

    kcc.coin = coin;
    kcc.connection = connection;
    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "know coin for recoup",
                                &mhd_ret,
                                &TEH_DB_know_coin_transaction,
                                &kcc))
      return mhd_ret;
  }

  /* Perform actual recoup transaction */
  pc.coin_sig = coin_sig;
  pc.coin_bks = coin_bks;
  pc.coin = coin;
  pc.refreshed = refreshed;
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run recoup",
                                &mhd_ret,
                                &recoup_transaction,
                                &pc))
      return mhd_ret;
  }
  /* Recoup succeeded, return result */
  return (refreshed)
         ? TALER_MHD_reply_json_pack (connection,
                                      MHD_HTTP_OK,
                                      "{s:o, s:b}",
                                      "old_coin_pub",
                                      GNUNET_JSON_from_data_auto (
                                        &pc.target.old_coin_pub),
                                      "refreshed", 1)
         : TALER_MHD_reply_json_pack (connection,
                                      MHD_HTTP_OK,
                                      "{s:o, s:b}",
                                      "reserve_pub",
                                      GNUNET_JSON_from_data_auto (
                                        &pc.target.reserve_pub),
                                      "refreshed", 0);
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
  struct TALER_DenominationBlindingKeyP coin_bks;
  struct TALER_CoinSpendSignatureP coin_sig;
  int refreshed = GNUNET_NO;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &coin.denom_pub_hash),
    TALER_JSON_spec_denomination_signature ("denom_sig",
                                            &coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_blind_key_secret",
                                 &coin_bks),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_mark_optional
      (GNUNET_JSON_spec_boolean ("refreshed",
                                 &refreshed)),
    GNUNET_JSON_spec_end ()
  };

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
                                     &coin_bks,
                                     &coin_sig,
                                     refreshed);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_recoup.c */
