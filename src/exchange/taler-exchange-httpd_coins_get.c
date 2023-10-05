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
 * @file taler-exchange-httpd_coins_get.c
 * @brief Handle GET /coins/$COIN_PUB/history requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_coins_get.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Add the headers we want to set for every response.
 *
 * @param cls the key state to use
 * @param[in,out] response the response to modify
 */
static void
add_response_headers (void *cls,
                      struct MHD_Response *response)
{
  (void) cls;
  TALER_MHD_add_global_headers (response);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CACHE_CONTROL,
                                         "no-cache"));
}


/**
 * Compile the transaction history of a coin into a JSON object.
 *
 * @param coin_pub public key of the coin
 * @param tl transaction history to JSON-ify
 * @return json representation of the @a rh, NULL on error
 */
static json_t *
compile_transaction_history (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_EXCHANGEDB_TransactionList *tl)
{
  json_t *history;

  history = json_array ();
  if (NULL == history)
  {
    GNUNET_break (0); /* out of memory!? */
    return NULL;
  }
  for (const struct TALER_EXCHANGEDB_TransactionList *pos = tl;
       NULL != pos;
       pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      {
        const struct TALER_EXCHANGEDB_DepositListEntry *deposit =
          pos->details.deposit;
        struct TALER_MerchantWireHashP h_wire;

        TALER_merchant_wire_signature_hash (deposit->receiver_wire_account,
                                            &deposit->wire_salt,
                                            &h_wire);
#if ENABLE_SANITY_CHECKS
        /* internal sanity check before we hand out a bogus sig... */
        TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
        if (GNUNET_OK !=
            TALER_wallet_deposit_verify (
              &deposit->amount_with_fee,
              &deposit->deposit_fee,
              &h_wire,
              &deposit->h_contract_terms,
              deposit->no_wallet_data_hash
              ? NULL
              : &deposit->wallet_data_hash,
              deposit->no_age_commitment
              ? NULL
              : &deposit->h_age_commitment,
              &deposit->h_policy,
              &deposit->h_denom_pub,
              deposit->timestamp,
              &deposit->merchant_pub,
              deposit->refund_deadline,
              coin_pub,
              &deposit->csig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
#endif
        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "DEPOSIT"),
                TALER_JSON_pack_amount ("amount",
                                        &deposit->amount_with_fee),
                TALER_JSON_pack_amount ("deposit_fee",
                                        &deposit->deposit_fee),
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            deposit->timestamp),
                GNUNET_JSON_pack_allow_null (
                  GNUNET_JSON_pack_timestamp ("refund_deadline",
                                              deposit->refund_deadline)),
                GNUNET_JSON_pack_data_auto ("merchant_pub",
                                            &deposit->merchant_pub),
                GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                            &deposit->h_contract_terms),
                GNUNET_JSON_pack_data_auto ("h_wire",
                                            &h_wire),
                GNUNET_JSON_pack_allow_null (
                  deposit->no_age_commitment ?
                  GNUNET_JSON_pack_string (
                    "h_age_commitment", NULL) :
                  GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                              &deposit->h_age_commitment)),
                GNUNET_JSON_pack_data_auto ("coin_sig",
                                            &deposit->csig))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        break;
      }
    case TALER_EXCHANGEDB_TT_MELT:
      {
        const struct TALER_EXCHANGEDB_MeltListEntry *melt =
          pos->details.melt;
        const struct TALER_AgeCommitmentHash *phac = NULL;

#if ENABLE_SANITY_CHECKS
        TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
        if (GNUNET_OK !=
            TALER_wallet_melt_verify (
              &melt->amount_with_fee,
              &melt->melt_fee,
              &melt->rc,
              &melt->h_denom_pub,
              &melt->h_age_commitment,
              coin_pub,
              &melt->coin_sig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
#endif

        /* Age restriction is optional.  We communicate a NULL value to
         * JSON_PACK below */
        if (! melt->no_age_commitment)
          phac = &melt->h_age_commitment;

        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "MELT"),
                TALER_JSON_pack_amount ("amount",
                                        &melt->amount_with_fee),
                TALER_JSON_pack_amount ("melt_fee",
                                        &melt->melt_fee),
                GNUNET_JSON_pack_data_auto ("rc",
                                            &melt->rc),
                GNUNET_JSON_pack_allow_null (
                  GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                              phac)),
                GNUNET_JSON_pack_data_auto ("coin_sig",
                                            &melt->coin_sig))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      {
        const struct TALER_EXCHANGEDB_RefundListEntry *refund =
          pos->details.refund;
        struct TALER_Amount value;

#if ENABLE_SANITY_CHECKS
        TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
        if (GNUNET_OK !=
            TALER_merchant_refund_verify (
              coin_pub,
              &refund->h_contract_terms,
              refund->rtransaction_id,
              &refund->refund_amount,
              &refund->merchant_pub,
              &refund->merchant_sig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
#endif
        if (0 >
            TALER_amount_subtract (&value,
                                   &refund->refund_amount,
                                   &refund->refund_fee))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "REFUND"),
                TALER_JSON_pack_amount ("amount",
                                        &value),
                TALER_JSON_pack_amount ("refund_fee",
                                        &refund->refund_fee),
                GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                            &refund->h_contract_terms),
                GNUNET_JSON_pack_data_auto ("merchant_pub",
                                            &refund->merchant_pub),
                GNUNET_JSON_pack_uint64 ("rtransaction_id",
                                         refund->rtransaction_id),
                GNUNET_JSON_pack_data_auto ("merchant_sig",
                                            &refund->merchant_sig))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      {
        struct TALER_EXCHANGEDB_RecoupRefreshListEntry *pr =
          pos->details.old_coin_recoup;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        if (TALER_EC_NONE !=
            TALER_exchange_online_confirm_recoup_refresh_sign (
              &TEH_keys_exchange_sign_,
              pr->timestamp,
              &pr->value,
              &pr->coin.coin_pub,
              &pr->old_coin_pub,
              &epub,
              &esig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        /* NOTE: we could also provide coin_pub's coin_sig, denomination key hash and
           the denomination key's RSA signature over coin_pub, but as the
           wallet should really already have this information (and cannot
           check or do anything with it anyway if it doesn't), it seems
           strictly unnecessary. */
        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "OLD-COIN-RECOUP"),
                TALER_JSON_pack_amount ("amount",
                                        &pr->value),
                GNUNET_JSON_pack_data_auto ("exchange_sig",
                                            &esig),
                GNUNET_JSON_pack_data_auto ("exchange_pub",
                                            &epub),
                GNUNET_JSON_pack_data_auto ("coin_pub",
                                            &pr->coin.coin_pub),
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            pr->timestamp))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        break;
      }
    case TALER_EXCHANGEDB_TT_RECOUP:
      {
        const struct TALER_EXCHANGEDB_RecoupListEntry *recoup =
          pos->details.recoup;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        if (TALER_EC_NONE !=
            TALER_exchange_online_confirm_recoup_sign (
              &TEH_keys_exchange_sign_,
              recoup->timestamp,
              &recoup->value,
              coin_pub,
              &recoup->reserve_pub,
              &epub,
              &esig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "RECOUP"),
                TALER_JSON_pack_amount ("amount",
                                        &recoup->value),
                GNUNET_JSON_pack_data_auto ("exchange_sig",
                                            &esig),
                GNUNET_JSON_pack_data_auto ("exchange_pub",
                                            &epub),
                GNUNET_JSON_pack_data_auto ("reserve_pub",
                                            &recoup->reserve_pub),
                GNUNET_JSON_pack_data_auto ("coin_sig",
                                            &recoup->coin_sig),
                GNUNET_JSON_pack_data_auto ("coin_blind",
                                            &recoup->coin_blind),
                GNUNET_JSON_pack_data_auto ("reserve_pub",
                                            &recoup->reserve_pub),
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            recoup->timestamp))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
      }
      break;
    case TALER_EXCHANGEDB_TT_RECOUP_REFRESH:
      {
        struct TALER_EXCHANGEDB_RecoupRefreshListEntry *pr =
          pos->details.recoup_refresh;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        if (TALER_EC_NONE !=
            TALER_exchange_online_confirm_recoup_refresh_sign (
              &TEH_keys_exchange_sign_,
              pr->timestamp,
              &pr->value,
              coin_pub,
              &pr->old_coin_pub,
              &epub,
              &esig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        /* NOTE: we could also provide coin_pub's coin_sig, denomination key
           hash and the denomination key's RSA signature over coin_pub, but as
           the wallet should really already have this information (and cannot
           check or do anything with it anyway if it doesn't), it seems
           strictly unnecessary. */
        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "RECOUP-REFRESH"),
                TALER_JSON_pack_amount ("amount",
                                        &pr->value),
                GNUNET_JSON_pack_data_auto ("exchange_sig",
                                            &esig),
                GNUNET_JSON_pack_data_auto ("exchange_pub",
                                            &epub),
                GNUNET_JSON_pack_data_auto ("old_coin_pub",
                                            &pr->old_coin_pub),
                GNUNET_JSON_pack_data_auto ("coin_sig",
                                            &pr->coin_sig),
                GNUNET_JSON_pack_data_auto ("coin_blind",
                                            &pr->coin_blind),
                GNUNET_JSON_pack_timestamp ("timestamp",
                                            pr->timestamp))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        break;
      }

    case TALER_EXCHANGEDB_TT_PURSE_DEPOSIT:
      {
        struct TALER_EXCHANGEDB_PurseDepositListEntry *pd
          = pos->details.purse_deposit;
        const struct TALER_AgeCommitmentHash *phac = NULL;

        if (! pd->no_age_commitment)
          phac = &pd->h_age_commitment;

        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "PURSE-DEPOSIT"),
                TALER_JSON_pack_amount ("amount",
                                        &pd->amount),
                GNUNET_JSON_pack_string ("exchange_base_url",
                                         NULL == pd->exchange_base_url
                                         ? TEH_base_url
                                         : pd->exchange_base_url),
                GNUNET_JSON_pack_allow_null (
                  GNUNET_JSON_pack_data_auto ("h_age_commitment",
                                              phac)),
                GNUNET_JSON_pack_data_auto ("purse_pub",
                                            &pd->purse_pub),
                GNUNET_JSON_pack_bool ("refunded",
                                       pd->refunded),
                GNUNET_JSON_pack_data_auto ("coin_sig",
                                            &pd->coin_sig))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        break;
      }

    case TALER_EXCHANGEDB_TT_PURSE_REFUND:
      {
        const struct TALER_EXCHANGEDB_PurseRefundListEntry *prefund =
          pos->details.purse_refund;
        struct TALER_Amount value;
        enum TALER_ErrorCode ec;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        if (0 >
            TALER_amount_subtract (&value,
                                   &prefund->refund_amount,
                                   &prefund->refund_fee))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        ec = TALER_exchange_online_purse_refund_sign (
          &TEH_keys_exchange_sign_,
          &value,
          &prefund->refund_fee,
          coin_pub,
          &prefund->purse_pub,
          &epub,
          &esig);
        if (TALER_EC_NONE != ec)
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "PURSE-REFUND"),
                TALER_JSON_pack_amount ("amount",
                                        &value),
                TALER_JSON_pack_amount ("refund_fee",
                                        &prefund->refund_fee),
                GNUNET_JSON_pack_data_auto ("exchange_sig",
                                            &esig),
                GNUNET_JSON_pack_data_auto ("exchange_pub",
                                            &epub),
                GNUNET_JSON_pack_data_auto ("purse_pub",
                                            &prefund->purse_pub))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
      }
      break;

    case TALER_EXCHANGEDB_TT_RESERVE_OPEN:
      {
        struct TALER_EXCHANGEDB_ReserveOpenListEntry *role
          = pos->details.reserve_open;

        if (0 !=
            json_array_append_new (
              history,
              GNUNET_JSON_PACK (
                GNUNET_JSON_pack_string ("type",
                                         "RESERVE-OPEN-DEPOSIT"),
                TALER_JSON_pack_amount ("coin_contribution",
                                        &role->coin_contribution),
                GNUNET_JSON_pack_data_auto ("reserve_sig",
                                            &role->reserve_sig),
                GNUNET_JSON_pack_data_auto ("coin_sig",
                                            &role->coin_sig))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        break;
      }
    }
  }
  return history;
}


MHD_RESULT
TEH_handler_coins_get (struct TEH_RequestContext *rc,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  struct TALER_EXCHANGEDB_TransactionList *tl = NULL;
  uint64_t start_off = 0;
  uint64_t etag_in;
  uint64_t etag_out;
  char etagp[24];
  struct MHD_Response *resp;
  unsigned int http_status;
  struct TALER_DenominationHashP h_denom_pub;
  struct TALER_Amount balance;

  TALER_MHD_parse_request_number (rc->connection,
                                  "start",
                                  &start_off);
  /* Check signature */
  {
    struct TALER_CoinSpendSignatureP coin_sig;
    bool required = true;

    TALER_MHD_parse_request_header_auto (rc->connection,
                                         TALER_COIN_HISTORY_SIGNATURE_HEADER,
                                         &coin_sig,
                                         required);
    if (GNUNET_OK !=
        TALER_wallet_coin_history_verify (start_off,
                                          coin_pub,
                                          &coin_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_COIN_HISTORY_BAD_SIGNATURE,
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
        etag_in = start_off;
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

  /* Get history from DB between etag and now */
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                            coin_pub,
                                            start_off,
                                            etag_in,
                                            &etag_out,
                                            &balance,
                                            &h_denom_pub,
                                            &tl);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "get_coin_history");
    case GNUNET_DB_STATUS_SOFT_ERROR:
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                         "get_coin_history");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_COIN_UNKNOWN,
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
  if (NULL == tl)
  {
    /* 204: empty history */
    resp = MHD_create_response_from_buffer (0,
                                            "",
                                            MHD_RESPMEM_PERSISTENT);
    http_status = MHD_HTTP_NO_CONTENT;
  }
  else
  {
    /* 200: regular history */
    json_t *history;

    history = compile_transaction_history (coin_pub,
                                           tl);
    TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                            tl);
    tl = NULL;
    if (NULL == history)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                         "Failed to compile coin history");
    }
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                  &h_denom_pub),
      TALER_JSON_pack_amount ("balance",
                              &balance),
      GNUNET_JSON_pack_array_steal ("history",
                                    history));
    http_status = MHD_HTTP_OK;
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


/* end of taler-exchange-httpd_coins_get.c */
