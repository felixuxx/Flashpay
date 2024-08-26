/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * Add the headers we want to set for every /keys response.
 *
 * @param cls the key state to use
 * @param[in,out] response the response to modify
 */
static void
add_response_headers (void *cls,
                      struct MHD_Response *response)
{
  (void) cls;
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CACHE_CONTROL,
                                         "no-cache"));
}


MHD_RESULT
TEH_handler_reserves_history (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct TALER_EXCHANGEDB_ReserveHistory *rh = NULL;
  uint64_t start_off = 0;
  struct TALER_Amount balance;
  uint64_t etag_in;
  uint64_t etag_out;
  char etagp[24];
  struct MHD_Response *resp;
  unsigned int http_status;

  TALER_MHD_parse_request_number (rc->connection,
                                  "start",
                                  &start_off);
  {
    struct TALER_ReserveSignatureP reserve_sig;
    bool required = true;

    TALER_MHD_parse_request_header_auto (rc->connection,
                                         TALER_RESERVE_HISTORY_SIGNATURE_HEADER,
                                         &reserve_sig,
                                         required);

    if (GNUNET_OK !=
        TALER_wallet_reserve_history_verify (start_off,
                                             reserve_pub,
                                             &reserve_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_RESERVE_HISTORY_BAD_SIGNATURE,
                                         NULL);
    }
  }

  /* Get etag */
  {
    const char *etags;

    etags = MHD_lookup_connection_value (rc->connection,
                                         MHD_HEADER_KIND,
                                         MHD_HTTP_HEADER_IF_NONE_MATCH);
    if (NULL != etags)
    {
      char dummy;
      unsigned long long ev;

      if (1 != sscanf (etags,
                       "\"%llu\"%c",
                       &ev,
                       &dummy))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Client send malformed `If-None-Match' header `%s'\n",
                    etags);
        etag_in = 0;
      }
      else
      {
        etag_in = (uint64_t) ev;
      }
    }
    else
    {
      etag_in = start_off;
    }
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                          reserve_pub,
                                          start_off,
                                          etag_in,
                                          &etag_out,
                                          &balance,
                                          &rh);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "get_reserve_history");
    case GNUNET_DB_STATUS_SOFT_ERROR:
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                         "get_reserve_history");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      /* Handled below */
      break;
    }
  }

  GNUNET_snprintf (etagp,
                   sizeof (etagp),
                   "\"%llu\"",
                   (unsigned long long) etag_out);
  if (etag_in == etag_out)
  {
    return TEH_RESPONSE_reply_not_modified (rc->connection,
                                            etagp,
                                            &add_response_headers,
                                            NULL);
  }
  if (NULL == rh)
  {
    /* 204: empty history */
    resp = MHD_create_response_from_buffer_static (0,
                                                   "");
    http_status = MHD_HTTP_NO_CONTENT;
  }
  else
  {
    json_t *history;

    http_status = MHD_HTTP_OK;
    history = compile_reserve_history (rh);
    TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                      rh);
    rh = NULL;
    if (NULL == history)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                         NULL);
    }
    resp = TALER_MHD_MAKE_JSON_PACK (
      TALER_JSON_pack_amount ("balance",
                              &balance),
      GNUNET_JSON_pack_array_steal ("history",
                                    history));
  }
  add_response_headers (NULL,
                        resp);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_ETAG,
                                         etagp));
  {
    MHD_RESULT ret;

    ret = MHD_queue_response (rc->connection,
                              http_status,
                              resp);
    GNUNET_break (MHD_YES == ret);
    MHD_destroy_response (resp);
    return ret;
  }
}


/* end of taler-exchange-httpd_reserves_history.c */
