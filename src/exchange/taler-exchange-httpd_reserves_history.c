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
 * @file taler-exchange-httpd_reserves_history.c
 * @brief Handle /reserves/$RESERVE_PUB HISTORY requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_history.h"
#include "taler-exchange-httpd_responses.h"

/**
 * How far do we allow a client's time to be off when
 * checking the request timestamp?
 */
#define TIMESTAMP_TOLERANCE \
  GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES, 15)


/**
 * Closure for #reserve_history_transaction.
 */
struct ReserveHistoryContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * History of the reserve, set in the callback.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

  /**
   * Requested startin offset for the reserve history.
   */
  uint64_t start_off;

  /**
   * Current reserve balance.
   */
  struct TALER_Amount balance;
};


/**
 * Compile the history of a reserve into a JSON object.
 *
 * @param rh reserve history to JSON-ify
 * @return json representation of the @a rh, NULL on error
 */
static json_t *
compile_reserve_history (
  const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_history;

  json_history = json_array ();
  GNUNET_assert (NULL != json_history);
  for (const struct TALER_EXCHANGEDB_ReserveHistory *pos = rh;
       NULL != pos;
       pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      {
        const struct TALER_EXCHANGEDB_BankTransfer *bank =
          pos->details.bank;

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "CREDIT"),
                // FIXME: offset missing! (here and in all other cases!)
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            bank->execution_date),
                GNUNET_JSON_pack_string ("sender_account_url",
                                         bank->sender_account_details),
                GNUNET_JSON_pack_uint64 ("wire_reference",
                                         bank->wire_reference),
                TALER_JSON_pack_amount ("amount",
                                        &bank->amount))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
        break;
      }
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      {
        const struct TALER_EXCHANGEDB_CollectableBlindcoin *withdraw
          = pos->details.withdraw;

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "WITHDRAW"),
                GNUNET_JSON_pack_data_auto ("reserve_sig",
                                            &withdraw->reserve_sig),
                GNUNET_JSON_pack_data_auto ("h_coin_envelope",
                                            &withdraw->h_coin_envelope),
                GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                            &withdraw->denom_pub_hash),
                TALER_JSON_pack_amount ("withdraw_fee",
                                        &withdraw->withdraw_fee),
                TALER_JSON_pack_amount ("amount",
                                        &withdraw->amount_with_fee))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_RO_RECOUP_COIN:
      {
        const struct TALER_EXCHANGEDB_Recoup *recoup
          = pos->details.recoup;
        struct TALER_ExchangePublicKeyP pub;
        struct TALER_ExchangeSignatureP sig;

        if (TALER_EC_NONE !=
            TALER_exchange_online_confirm_recoup_sign (
              &TEH_keys_exchange_sign_,
              recoup->timestamp,
              &recoup->value,
              &recoup->coin.coin_pub,
              &recoup->reserve_pub,
              &pub,
              &sig))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "RECOUP"),
                GNUNET_JSON_pack_data_auto ("exchange_pub",
                                            &pub),
                GNUNET_JSON_pack_data_auto ("exchange_sig",
                                            &sig),
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            recoup->timestamp),
                TALER_JSON_pack_amount ("amount",
                                        &recoup->value),
                GNUNET_JSON_pack_data_auto ("coin_pub",
                                            &recoup->coin.coin_pub))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      {
        const struct TALER_EXCHANGEDB_ClosingTransfer *closing =
          pos->details.closing;
        struct TALER_ExchangePublicKeyP pub;
        struct TALER_ExchangeSignatureP sig;

        if (TALER_EC_NONE !=
            TALER_exchange_online_reserve_closed_sign (
              &TEH_keys_exchange_sign_,
              closing->execution_date,
              &closing->amount,
              &closing->closing_fee,
              closing->receiver_account_details,
              &closing->wtid,
              &pos->details.closing->reserve_pub,
              &pub,
              &sig))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "CLOSING"),
                GNUNET_JSON_pack_string ("receiver_account_details",
                                         closing->receiver_account_details),
                GNUNET_JSON_pack_data_auto ("wtid",
                                            &closing->wtid),
                GNUNET_JSON_pack_data_auto ("exchange_pub",
                                            &pub),
                GNUNET_JSON_pack_data_auto ("exchange_sig",
                                            &sig),
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            closing->execution_date),
                TALER_JSON_pack_amount ("amount",
                                        &closing->amount),
                TALER_JSON_pack_amount ("closing_fee",
                                        &closing->closing_fee))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_RO_PURSE_MERGE:
      {
        const struct TALER_EXCHANGEDB_PurseMerge *merge =
          pos->details.merge;

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "MERGE"),
                GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                            &merge->h_contract_terms),
                GNUNET_JSON_pack_data_auto ("merge_pub",
                                            &merge->merge_pub),
                GNUNET_JSON_pack_uint64 ("min_age",
                                         merge->min_age),
                GNUNET_JSON_pack_uint64 ("flags",
                                         merge->flags),
                GNUNET_JSON_pack_data_auto ("purse_pub",
                                            &merge->purse_pub),
                GNUNET_JSON_pack_data_auto ("reserve_sig",
                                            &merge->reserve_sig),
                GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                            merge->merge_timestamp),
                GNUNET_JSON_pack_timestamp ("purse_expiration",
                                            merge->purse_expiration),
                TALER_JSON_pack_amount ("purse_fee",
                                        &merge->purse_fee),
                TALER_JSON_pack_amount ("amount",
                                        &merge->amount_with_fee),
                GNUNET_JSON_pack_bool ("merged",
                                       merge->merged))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_RO_HISTORY_REQUEST:
      {
        const struct TALER_EXCHANGEDB_HistoryRequest *history =
          pos->details.history;

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "HISTORY"),
                GNUNET_JSON_pack_data_auto ("reserve_sig",
                                            &history->reserve_sig),
                GNUNET_JSON_pack_timestamp ("request_timestamp",
                                            history->request_timestamp),
                TALER_JSON_pack_amount ("amount",
                                        &history->history_fee))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;

    case TALER_EXCHANGEDB_RO_OPEN_REQUEST:
      {
        const struct TALER_EXCHANGEDB_OpenRequest *orq =
          pos->details.open_request;

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "OPEN"),
                GNUNET_JSON_pack_uint64 ("requested_min_purses",
                                         orq->purse_limit),
                GNUNET_JSON_pack_data_auto ("reserve_sig",
                                            &orq->reserve_sig),
                GNUNET_JSON_pack_timestamp ("request_timestamp",
                                            orq->request_timestamp),
                GNUNET_JSON_pack_timestamp ("requested_expiration",
                                            orq->reserve_expiration),
                TALER_JSON_pack_amount ("open_fee",
                                        &orq->open_fee))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;

    case TALER_EXCHANGEDB_RO_CLOSE_REQUEST:
      {
        const struct TALER_EXCHANGEDB_CloseRequest *crq =
          pos->details.close_request;

        if (0 !=
            json_array_append_new (
              json_history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "CLOSE"),
                GNUNET_JSON_pack_data_auto ("reserve_sig",
                                            &crq->reserve_sig),
                GNUNET_is_zero (&crq->target_account_h_payto)
                ? GNUNET_JSON_pack_allow_null (
                  GNUNET_JSON_pack_string ("h_payto",
                                           NULL))
                : GNUNET_JSON_pack_data_auto ("h_payto",
                                              &crq->target_account_h_payto),
                GNUNET_JSON_pack_timestamp ("request_timestamp",
                                            crq->request_timestamp))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    }
  }

  return json_history;
}


/**
 * Send reserve history to client.
 *
 * @param connection connection to the client
 * @param rhc reserve history to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_history_success (struct MHD_Connection *connection,
                               const struct ReserveHistoryContext *rhc)
{
  const struct TALER_EXCHANGEDB_ReserveHistory *rh = rhc->rh;
  json_t *json_history;

  json_history = compile_reserve_history (rh);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("balance",
                            &rhc->balance),
    GNUNET_JSON_pack_array_steal ("history",
                                  json_history));
}


/**
 * Function implementing /reserves/ HISTORY transaction.
 * Execute a /reserves/ HISTORY.  Given the public key of a reserve,
 * return the associated transaction history.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response history for @a connection,
 *             if transaction failed (!); unused
 * @return transaction history
 */
static enum GNUNET_DB_QueryStatus
reserve_history_transaction (void *cls,
                             struct MHD_Connection *connection,
                             MHD_RESULT *mhd_ret)
{
  struct ReserveHistoryContext *rsc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                        rsc->reserve_pub,
                                        rsc->start_off,
                                        &rsc->balance,
                                        &rsc->rh);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "get_reserve_history");
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_history (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct ReserveHistoryContext rsc = {
    .reserve_pub = reserve_pub
  };
  MHD_RESULT mhd_ret;
  struct TALER_ReserveSignatureP reserve_sig;
  bool required = true;

  TALER_MHD_parse_request_header_auto (rc->connection,
                                       TALER_RESERVE_HISTORY_SIGNATURE_HEADER,
                                       &reserve_sig,
                                       required);
  TALER_MHD_parse_request_number (rc->connection,
                                  "start",
                                  &rsc.start_off);
  rsc.reserve_pub = reserve_pub;

  if (GNUNET_OK !=
      TALER_wallet_reserve_history_verify (rsc.start_off,
                                           reserve_pub,
                                           &reserve_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_RESERVE_HISTORY_BAD_SIGNATURE,
                                       NULL);
  }
  rsc.rh = NULL;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "get reserve history",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &reserve_history_transaction,
                              &rsc))
  {
    return mhd_ret;
  }
  if (NULL == rsc.rh)
  {
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                       NULL);
  }
  mhd_ret = reply_reserve_history_success (rc->connection,
                                           &rsc);
  TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                    rsc.rh);
  return mhd_ret;
}


/* end of taler-exchange-httpd_reserves_history.c */
