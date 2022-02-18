/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
        struct TALER_MerchantWireHash h_wire;

        TALER_merchant_wire_signature_hash (deposit->receiver_wire_account,
                                            &deposit->wire_salt,
                                            &h_wire);
#if ENABLE_SANITY_CHECKS
        /* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            TALER_wallet_deposit_verify (&deposit->amount_with_fee,
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
                GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                            &deposit->h_denom_pub),
                GNUNET_JSON_pack_allow_null (
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
        if (GNUNET_OK !=
            TALER_wallet_melt_verify (&melt->amount_with_fee,
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
        if (! TALER_AgeCommitmentHash_isNullOrZero (&melt->h_age_commitment))
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
                GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                            &melt->h_denom_pub),
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
        if (GNUNET_OK !=
            TALER_merchant_refund_verify (coin_pub,
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
        struct TALER_RecoupRefreshConfirmationPS pc = {
          .purpose.purpose = htonl (
            TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH),
          .purpose.size = htonl (sizeof (pc)),
          .timestamp = GNUNET_TIME_timestamp_hton (pr->timestamp),
          .coin_pub = pr->coin.coin_pub,
          .old_coin_pub = pr->old_coin_pub
        };

        TALER_amount_hton (&pc.recoup_amount,
                           &pr->value);
        if (TALER_EC_NONE !=
            TEH_keys_exchange_sign (&pc,
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
        struct TALER_RecoupConfirmationPS pc = {
          .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP),
          .purpose.size = htonl (sizeof (pc)),
          .timestamp = GNUNET_TIME_timestamp_hton (recoup->timestamp),
          .coin_pub = *coin_pub,
          .reserve_pub = recoup->reserve_pub
        };

        TALER_amount_hton (&pc.recoup_amount,
                           &recoup->value);
        if (TALER_EC_NONE !=
            TEH_keys_exchange_sign (&pc,
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
                GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                            &recoup->h_denom_pub),
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
        struct TALER_RecoupRefreshConfirmationPS pc = {
          .purpose.purpose = htonl (
            TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH),
          .purpose.size = htonl (sizeof (pc)),
          .timestamp = GNUNET_TIME_timestamp_hton (pr->timestamp),
          .coin_pub = *coin_pub,
          .old_coin_pub = pr->old_coin_pub
        };

        TALER_amount_hton (&pc.recoup_amount,
                           &pr->value);
        if (TALER_EC_NONE !=
            TEH_keys_exchange_sign (&pc,
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
           strictly unnecessary. *///
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
                GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                            &pr->coin.denom_pub_hash),
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
    default:
      GNUNET_assert (0);
    }
  }
  return history;
}


MHD_RESULT
TEH_RESPONSE_reply_unknown_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHash *dph)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  struct GNUNET_TIME_Timestamp now;
  enum TALER_ErrorCode ec;

  now = GNUNET_TIME_timestamp_get ();
  {
    struct TALER_DenominationUnknownAffirmationPS dua = {
      .purpose.size = htonl (sizeof (dua)),
      .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN),
      .timestamp = GNUNET_TIME_timestamp_hton (now),
      .h_denom_pub = *dph,
    };

    ec = TEH_keys_exchange_sign (&dua,
                                 &epub,
                                 &esig);
  }
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
  const struct TALER_DenominationHash *dph,
  enum TALER_ErrorCode ec,
  const char *oper)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  enum TALER_ErrorCode ecr;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();
  struct TALER_DenominationExpiredAffirmationPS dua = {
    .purpose.size = htonl (sizeof (dua)),
    .purpose.purpose = htonl (
      TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_EXPIRED),
    .timestamp = GNUNET_TIME_timestamp_hton (now),
    .h_denom_pub = *dph,
  };

  /* strncpy would create a compiler warning */
  memcpy (dua.operation,
          oper,
          GNUNET_MIN (sizeof (dua.operation),
                      strlen (oper)));
  ecr = TEH_keys_exchange_sign (&dua,
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
  const struct TALER_DenominationHash *dph)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  struct GNUNET_TIME_Timestamp now;
  enum TALER_ErrorCode ec;

  now = GNUNET_TIME_timestamp_get ();
  {
    struct TALER_DenominationUnknownAffirmationPS dua = {
      .purpose.size = htonl (sizeof (dua)),
      .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_AFFIRM_DENOM_UNKNOWN),
      .timestamp = GNUNET_TIME_timestamp_hton (now),
      .h_denom_pub = *dph,
    };

    ec = TEH_keys_exchange_sign (&dua,
                                 &epub,
                                 &esig);
  }
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
  const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  struct TALER_EXCHANGEDB_TransactionList *tl;
  enum GNUNET_DB_QueryStatus qs;
  json_t *history;

  // FIXME: maybe start read-committed transaction here?
  // => check all callers (that they aborted already!)
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          coin_pub,
                                          GNUNET_NO,
                                          &tl);
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
    GNUNET_JSON_pack_array_steal ("history",
                                  history));
}


/**
 * Compile the history of a reserve into a JSON object
 * and calculate the total balance.
 *
 * @param rh reserve history to JSON-ify
 * @param[out] balance set to current reserve balance
 * @return json representation of the @a rh, NULL on error
 */
json_t *
TEH_RESPONSE_compile_reserve_history (
  const struct TALER_EXCHANGEDB_ReserveHistory *rh,
  struct TALER_Amount *balance)
{
  struct TALER_Amount credit_total;
  struct TALER_Amount withdraw_total;
  json_t *json_history;
  enum InitAmounts
  {
    /** Nothing initialized */
    IA_NONE = 0,
    /** credit_total initialized */
    IA_CREDIT = 1,
    /** withdraw_total initialized */
    IA_WITHDRAW = 2
  } init = IA_NONE;

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
        if (0 == (IA_CREDIT & init))
        {
          credit_total = bank->amount;
          init |= IA_CREDIT;
        }
        else if (0 >
                 TALER_amount_add (&credit_total,
                                   &credit_total,
                                   &bank->amount))
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
        struct TALER_Amount value;

        value = withdraw->amount_with_fee;
        if (0 == (IA_WITHDRAW & init))
        {
          withdraw_total = value;
          init |= IA_WITHDRAW;
        }
        else
        {
          if (0 >
              TALER_amount_add (&withdraw_total,
                                &withdraw_total,
                                &value))
          {
            GNUNET_break (0);
            json_decref (json_history);
            return NULL;
          }
        }
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
                                        &value))))
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

        if (0 == (IA_CREDIT & init))
        {
          credit_total = recoup->value;
          init |= IA_CREDIT;
        }
        else if (0 >
                 TALER_amount_add (&credit_total,
                                   &credit_total,
                                   &recoup->value))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
        {
          struct TALER_RecoupConfirmationPS pc = {
            .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP),
            .purpose.size = htonl (sizeof (pc)),
            .timestamp = GNUNET_TIME_timestamp_hton (recoup->timestamp),
            .coin_pub = recoup->coin.coin_pub,
            .reserve_pub = recoup->reserve_pub
          };

          TALER_amount_hton (&pc.recoup_amount,
                             &recoup->value);
          if (TALER_EC_NONE !=
              TEH_keys_exchange_sign (&pc,
                                      &pub,
                                      &sig))
          {
            GNUNET_break (0);
            json_decref (json_history);
            return NULL;
          }
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
        struct TALER_Amount value;

        value = closing->amount;
        if (0 == (IA_WITHDRAW & init))
        {
          withdraw_total = value;
          init |= IA_WITHDRAW;
        }
        else
        {
          if (0 >
              TALER_amount_add (&withdraw_total,
                                &withdraw_total,
                                &value))
          {
            GNUNET_break (0);
            json_decref (json_history);
            return NULL;
          }
        }
        {
          struct TALER_ReserveCloseConfirmationPS rcc = {
            .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED),
            .purpose.size = htonl (sizeof (rcc)),
            .timestamp = GNUNET_TIME_timestamp_hton (closing->execution_date),
            .reserve_pub = pos->details.closing->reserve_pub,
            .wtid = closing->wtid
          };

          TALER_amount_hton (&rcc.closing_amount,
                             &value);
          TALER_amount_hton (&rcc.closing_fee,
                             &closing->closing_fee);
          TALER_payto_hash (closing->receiver_account_details,
                            &rcc.h_payto);
          if (TALER_EC_NONE !=
              TEH_keys_exchange_sign (&rcc,
                                      &pub,
                                      &sig))
          {
            GNUNET_break (0);
            json_decref (json_history);
            return NULL;
          }
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
                                        &value),
                TALER_JSON_pack_amount ("closing_fee",
                                        &closing->closing_fee))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    }
  }

  if (0 == (IA_CREDIT & init))
  {
    /* We should not have gotten here, without credits no reserve
       should exist! */
    GNUNET_break (0);
    json_decref (json_history);
    return NULL;
  }
  if (0 == (IA_WITHDRAW & init))
  {
    /* did not encounter any withdraw operations, set withdraw_total to zero */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (credit_total.currency,
                                          &withdraw_total));
  }
  if (0 >
      TALER_amount_subtract (balance,
                             &credit_total,
                             &withdraw_total))
  {
    GNUNET_break (0);
    json_decref (json_history);
    return NULL;
  }

  return json_history;
}


/* end of taler-exchange-httpd_responses.c */
