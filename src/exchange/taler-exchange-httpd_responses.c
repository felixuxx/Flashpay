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
 * @file taler-exchange-httpd_responses.c
 * @brief API for generating generic replies of the exchange; these
 *        functions are called TEH_RESPONSE_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <zlib.h>
#include "taler-exchange-httpd_responses.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Compile the transaction history of a coin into a JSON object.
 *
 * @param coin_pub public key of the coin
 * @param tl transaction history to JSON-ify
 * @return json representation of the @a rh, NULL on error
 */
json_t *
TEH_RESPONSE_compile_transaction_history (
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
              &deposit->h_age_commitment,
              NULL /* h_extensions! */,
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
    }
  }
  return history;
}


MHD_RESULT
TEH_RESPONSE_reply_unknown_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  struct GNUNET_TIME_Timestamp now;
  enum TALER_ErrorCode ec;

  now = GNUNET_TIME_timestamp_get ();
  ec = TALER_exchange_online_denomination_unknown_sign (
    &TEH_keys_exchange_sign_,
    now,
    dph,
    &epub,
    &esig);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       ec,
                                       NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_NOT_FOUND,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                now),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &epub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &esig),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                dph));
}


MHD_RESULT
TEH_RESPONSE_reply_expired_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph,
  enum TALER_ErrorCode ec,
  const char *oper)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  enum TALER_ErrorCode ecr;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();

  ecr = TALER_exchange_online_denomination_expired_sign (
    &TEH_keys_exchange_sign_,
    now,
    dph,
    oper,
    &epub,
    &esig);
  if (TALER_EC_NONE != ecr)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       ec,
                                       NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_GONE,
    TALER_JSON_pack_ec (ec),
    GNUNET_JSON_pack_string ("oper",
                             oper),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                now),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &epub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &esig),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                dph));
}


MHD_RESULT
TEH_RESPONSE_reply_invalid_denom_cipher_for_operation (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  struct GNUNET_TIME_Timestamp now;
  enum TALER_ErrorCode ec;

  now = GNUNET_TIME_timestamp_get ();
  ec = TALER_exchange_online_denomination_unknown_sign (
    &TEH_keys_exchange_sign_,
    now,
    dph,
    &epub,
    &esig);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       ec,
                                       NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_NOT_FOUND,
    TALER_JSON_pack_ec (
      TALER_EC_EXCHANGE_GENERIC_INVALID_DENOMINATION_CIPHER_FOR_OPERATION),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                now),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &epub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &esig),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                dph));
}


MHD_RESULT
TEH_RESPONSE_reply_coin_insufficient_funds (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  struct TALER_EXCHANGEDB_TransactionList *tl;
  enum GNUNET_DB_QueryStatus qs;
  json_t *history;

  TEH_plugin->rollback (TEH_plugin->cls);
  // FIXME: maybe start read-only transaction here?
  if (GNUNET_OK !=
      TEH_plugin->start_read_committed (TEH_plugin->cls,
                                        "get_coin_transactions"))
  {
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_START_FAILED,
      NULL);
  }
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          coin_pub,
                                          &tl);
  TEH_plugin->rollback (TEH_plugin->cls);
  if (0 > qs)
  {
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      NULL);
  }

  history = TEH_RESPONSE_compile_transaction_history (coin_pub,
                                                      tl);
  TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                          tl);
  if (NULL == history)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       "Failed to generated proof of insufficient funds");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    TALER_ErrorCode_get_http_status_safe (ec),
    TALER_JSON_pack_ec (ec),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                h_denom_pub),
    GNUNET_JSON_pack_array_steal ("history",
                                  history));
}


json_t *
TEH_RESPONSE_compile_reserve_history (
  const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_history;

  json_history = json_array ();
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
                TALER_JSON_pack_amount ("amount",
                                        &merge->amount_with_fee),
                TALER_JSON_pack_amount ("purse_fee",
                                        &merge->purse_fee),
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
    }
  }

  return json_history;
}


/**
 * Send reserve history information to client with the
 * message that we have insufficient funds for the
 * requested withdraw operation.
 *
 * @param connection connection to the client
 * @param ebalance expected balance based on our database
 * @param withdraw_amount amount that the client requested to withdraw
 * @param rh reserve history to return
 * @return MHD result code
 */
static MHD_RESULT
reply_withdraw_insufficient_funds (
  struct MHD_Connection *connection,
  const struct TALER_Amount *ebalance,
  const struct TALER_Amount *withdraw_amount,
  const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_history;

  json_history = TEH_RESPONSE_compile_reserve_history (rh);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_WITHDRAW_HISTORY_ERROR_INSUFFICIENT_FUNDS,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_CONFLICT,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_WITHDRAW_INSUFFICIENT_FUNDS),
    TALER_JSON_pack_amount ("balance",
                            ebalance),
    TALER_JSON_pack_amount ("requested_amount",
                            withdraw_amount),
    GNUNET_JSON_pack_array_steal ("history",
                                  json_history));
}


MHD_RESULT
TEH_RESPONSE_reply_reserve_insufficient_balance (
  struct MHD_Connection *connection,
  const struct TALER_Amount *balance_required,
  const struct TALER_ReservePublicKeyP *reserve_pub)
{
  struct TALER_EXCHANGEDB_ReserveHistory *rh = NULL;
  struct TALER_Amount balance;
  enum GNUNET_DB_QueryStatus qs;
  MHD_RESULT mhd_ret;

  // FIXME: maybe start read-committed here?
  if (GNUNET_OK !=
      TEH_plugin->start (TEH_plugin->cls,
                         "get_reserve_history on insufficient balance"))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_START_FAILED,
                                       NULL);
  }
  /* The reserve does not have the required amount (actual
   * amount + withdraw fee) */
  qs = TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                        reserve_pub,
                                        &balance,
                                        &rh);
  TEH_plugin->rollback (TEH_plugin->cls);
  if ( (qs < 0) ||
       (NULL == rh) )
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "reserve history");
  }
  mhd_ret = reply_withdraw_insufficient_funds (
    connection,
    &balance,
    balance_required,
    rh);
  TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                    rh);
  return mhd_ret;
}


/* end of taler-exchange-httpd_responses.c */
