/*
  This file is part of TALER
  Copyright (C) 2014-2017 Taler Systems SA

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
 * @brief API for generating genric replies of the exchange; these
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
#include "taler-exchange-httpd_keystate.h"


/**
 * Compile the transaction history of a coin into a JSON object.
 *
 * @param coin_pub public key of the coin
 * @param tl transaction history to JSON-ify
 * @return json representation of the @a rh, NULL on error
 */
json_t *
TEH_RESPONSE_compile_transaction_history (const struct
                                          TALER_CoinSpendPublicKeyP *coin_pub,
                                          const struct
                                          TALER_EXCHANGEDB_TransactionList *tl)
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
        struct TALER_DepositRequestPS dr;
        const struct TALER_EXCHANGEDB_DepositListEntry *deposit =
          pos->details.deposit;

        dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
        dr.purpose.size = htonl (sizeof (struct TALER_DepositRequestPS));
        dr.h_contract_terms = deposit->h_contract_terms;
        dr.h_wire = deposit->h_wire;
        dr.timestamp = GNUNET_TIME_absolute_hton (deposit->timestamp);
        dr.refund_deadline = GNUNET_TIME_absolute_hton (
          deposit->refund_deadline);
        TALER_amount_hton (&dr.amount_with_fee,
                           &deposit->amount_with_fee);
        TALER_amount_hton (&dr.deposit_fee,
                           &deposit->deposit_fee);
        dr.merchant = deposit->merchant_pub;
        dr.coin_pub = *coin_pub;
#if ENABLE_SANITY_CHECKS
        /* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                        &dr.purpose,
                                        &deposit->csig.eddsa_signature,
                                        &coin_pub->eddsa_pub))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
#endif
        if (0 !=
            json_array_append_new (history,
                                   json_pack (
                                     "{s:s, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:o}",
                                     "type", "DEPOSIT",
                                     "amount", TALER_JSON_from_amount (
                                       &deposit->amount_with_fee),
                                     "deposit_fee",
                                     TALER_JSON_from_amount (
                                       &deposit->deposit_fee),
                                     "timestamp",
                                     GNUNET_JSON_from_time_abs (
                                       deposit->timestamp),
                                     "refund_deadline",
                                     GNUNET_JSON_from_time_abs (
                                       deposit->refund_deadline),
                                     "merchant_pub",
                                     GNUNET_JSON_from_data_auto (
                                       &deposit->merchant_pub),
                                     "h_contract_terms",
                                     GNUNET_JSON_from_data_auto (
                                       &deposit->h_contract_terms),
                                     "h_wire",
                                     GNUNET_JSON_from_data_auto (
                                       &deposit->h_wire),
                                     "coin_sig",
                                     GNUNET_JSON_from_data_auto (
                                       &deposit->csig))))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        break;
      }
    case TALER_EXCHANGEDB_TT_REFRESH_MELT:
      {
        struct TALER_RefreshMeltCoinAffirmationPS ms;
        const struct TALER_EXCHANGEDB_RefreshMeltListEntry *melt =
          pos->details.melt;

        ms.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
        ms.purpose.size = htonl (sizeof (struct
                                         TALER_RefreshMeltCoinAffirmationPS));
        ms.rc = melt->rc;
        TALER_amount_hton (&ms.amount_with_fee,
                           &melt->amount_with_fee);
        TALER_amount_hton (&ms.melt_fee,
                           &melt->melt_fee);
        ms.coin_pub = *coin_pub;
#if ENABLE_SANITY_CHECKS
        /* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                        &ms.purpose,
                                        &melt->coin_sig.eddsa_signature,
                                        &coin_pub->eddsa_pub))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
#endif
        if (0 !=
            json_array_append_new (history,
                                   json_pack ("{s:s, s:o, s:o, s:o, s:o}",
                                              "type", "MELT",
                                              "amount", TALER_JSON_from_amount (
                                                &melt->amount_with_fee),
                                              "melt_fee",
                                              TALER_JSON_from_amount (
                                                &melt->melt_fee),
                                              "rc", GNUNET_JSON_from_data_auto (
                                                &melt->rc),
                                              "coin_sig",
                                              GNUNET_JSON_from_data_auto (
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
        struct TALER_RefundRequestPS rr;
        const struct TALER_EXCHANGEDB_RefundListEntry *refund =
          pos->details.refund;
        struct TALER_Amount value;

        if (GNUNET_OK !=
            TALER_amount_subtract (&value,
                                   &refund->refund_amount,
                                   &refund->refund_fee))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
        rr.purpose.size = htonl (sizeof (struct TALER_RefundRequestPS));
        rr.h_contract_terms = refund->h_contract_terms;
        rr.coin_pub = *coin_pub;
        rr.merchant = refund->merchant_pub;
        rr.rtransaction_id = GNUNET_htonll (refund->rtransaction_id);
        TALER_amount_hton (&rr.refund_amount,
                           &refund->refund_amount);
        TALER_amount_hton (&rr.refund_fee,
                           &refund->refund_fee);
#if ENABLE_SANITY_CHECKS
        /* internal sanity check before we hand out a bogus sig... */
        if (GNUNET_OK !=
            GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                        &rr.purpose,
                                        &refund->merchant_sig.eddsa_sig,
                                        &refund->merchant_pub.eddsa_pub))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
#endif
        if (0 !=
            json_array_append_new (history,
                                   json_pack (
                                     "{s:s, s:o, s:o, s:o, s:o, s:I, s:o}",
                                     "type", "REFUND",
                                     "amount", TALER_JSON_from_amount (
                                       &value),
                                     "refund_fee",
                                     TALER_JSON_from_amount (
                                       &refund->refund_fee),
                                     "h_contract_terms",
                                     GNUNET_JSON_from_data_auto (
                                       &refund->h_contract_terms),
                                     "merchant_pub",
                                     GNUNET_JSON_from_data_auto (
                                       &refund->merchant_pub),
                                     "rtransaction_id",
                                     (json_int_t) refund->rtransaction_id,
                                     "merchant_sig",
                                     GNUNET_JSON_from_data_auto (
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
        struct TALER_RecoupRefreshConfirmationPS pc;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        pc.purpose.purpose = htonl (
          TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH);
        pc.purpose.size = htonl (sizeof (pc));
        pc.timestamp = GNUNET_TIME_absolute_hton (pr->timestamp);
        TALER_amount_hton (&pc.recoup_amount,
                           &pr->value);
        pc.coin_pub = *coin_pub;
        pc.old_coin_pub = pr->old_coin_pub;
        if (GNUNET_OK !=
            TEH_KS_sign (&pc.purpose,
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
           strictly unnecessary. */if (0 !=
            json_array_append_new (history,
                                   json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                                              "type", "OLD-COIN-RECOUP",
                                              "amount", TALER_JSON_from_amount (
                                                &pr->value),
                                              "exchange_sig",
                                              GNUNET_JSON_from_data_auto (
                                                &esig),
                                              "exchange_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &epub),
                                              "coin_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &pr->coin.coin_pub),
                                              "timestamp",
                                              GNUNET_JSON_from_time_abs (
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
        struct TALER_RecoupConfirmationPS pc;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP);
        pc.purpose.size = htonl (sizeof (pc));
        pc.timestamp = GNUNET_TIME_absolute_hton (recoup->timestamp);
        TALER_amount_hton (&pc.recoup_amount,
                           &recoup->value);
        pc.coin_pub = *coin_pub;
        pc.reserve_pub = recoup->reserve_pub;
        if (GNUNET_OK !=
            TEH_KS_sign (&pc.purpose,
                         &epub,
                         &esig))
        {
          GNUNET_break (0);
          json_decref (history);
          return NULL;
        }
        if (0 !=
            json_array_append_new (history,
                                   json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                                              "type", "RECOUP",
                                              "amount", TALER_JSON_from_amount (
                                                &recoup->value),
                                              "exchange_sig",
                                              GNUNET_JSON_from_data_auto (
                                                &esig),
                                              "exchange_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &epub),
                                              "reserve_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &recoup->reserve_pub),
                                              "timestamp",
                                              GNUNET_JSON_from_time_abs (
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
        struct TALER_RecoupRefreshConfirmationPS pc;
        struct TALER_ExchangePublicKeyP epub;
        struct TALER_ExchangeSignatureP esig;

        pc.purpose.purpose = htonl (
          TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH);
        pc.purpose.size = htonl (sizeof (pc));
        pc.timestamp = GNUNET_TIME_absolute_hton (pr->timestamp);
        TALER_amount_hton (&pc.recoup_amount,
                           &pr->value);
        pc.coin_pub = *coin_pub;
        pc.old_coin_pub = pr->old_coin_pub;
        if (GNUNET_OK !=
            TEH_KS_sign (&pc.purpose,
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
           strictly unnecessary. */if (0 !=
            json_array_append_new (history,
                                   json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                                              "type", "RECOUP-REFRESH",
                                              "amount", TALER_JSON_from_amount (
                                                &pr->value),
                                              "exchange_sig",
                                              GNUNET_JSON_from_data_auto (
                                                &esig),
                                              "exchange_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &epub),
                                              "old_coin_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &pr->old_coin_pub),
                                              "timestamp",
                                              GNUNET_JSON_from_time_abs (
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


/**
 * Send proof that a request is invalid to client because of
 * insufficient funds.  This function will create a message with all
 * of the operations affecting the coin that demonstrate that the coin
 * has insufficient value.
 *
 * @param connection connection to the client
 * @param ec error code to return
 * @param coin_pub public key of the coin
 * @param tl transaction list to use to build reply
 * @return MHD result code
 */
int
TEH_RESPONSE_reply_coin_insufficient_funds (struct MHD_Connection *connection,
                                            enum TALER_ErrorCode ec,
                                            const struct
                                            TALER_CoinSpendPublicKeyP *coin_pub,
                                            const struct
                                            TALER_EXCHANGEDB_TransactionList *tl)
{
  json_t *history;

  history = TEH_RESPONSE_compile_transaction_history (coin_pub,
                                                      tl);
  if (NULL == history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_COIN_HISTORY_DB_ERROR_INSUFFICIENT_FUNDS,
                                       "failed to convert transaction history to JSON");
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_CONFLICT,
                                    "{s:s, s:I, s:o}",
                                    "hint", "insufficient funds",
                                    "code", (json_int_t) ec,
                                    "history", history);
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
TEH_RESPONSE_compile_reserve_history (const struct
                                      TALER_EXCHANGEDB_ReserveHistory *rh,
                                      struct TALER_Amount *balance)
{
  struct TALER_Amount deposit_total;
  struct TALER_Amount withdraw_total;
  json_t *json_history;
  int ret;

  json_history = json_array ();
  ret = 0;
  for (const struct TALER_EXCHANGEDB_ReserveHistory *pos = rh;
       NULL != pos;
       pos = pos->next)
  {
    switch (pos->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      if (0 == (1 & ret))
        deposit_total = pos->details.bank->amount;
      else if (GNUNET_OK !=
               TALER_amount_add (&deposit_total,
                                 &deposit_total,
                                 &pos->details.bank->amount))
      {
        GNUNET_break (0);
        json_decref (json_history);
        return NULL;
      }
      ret |= 1;
      if (0 !=
          json_array_append_new (json_history,
                                 json_pack ("{s:s, s:o, s:s, s:o, s:o}",
                                            "type", "DEPOSIT",
                                            "timestamp",
                                            GNUNET_JSON_from_time_abs (
                                              pos->details.bank->execution_date),
                                            "sender_account_url",
                                            pos->details.bank->
                                            sender_account_details,
                                            "wire_reference",
                                            GNUNET_JSON_from_data (
                                              pos->details.bank->wire_reference,
                                              pos
                                              ->details.
                                              bank->wire_reference_size),
                                            "amount", TALER_JSON_from_amount (
                                              &pos->details.bank->amount))))
      {
        GNUNET_break (0);
        json_decref (json_history);
        return NULL;
      }
      break;
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      {
        struct TALER_Amount value;

        value = pos->details.withdraw->amount_with_fee;
        if (0 == (2 & ret))
        {
          withdraw_total = value;
        }
        else
        {
          if (GNUNET_OK !=
              TALER_amount_add (&withdraw_total,
                                &withdraw_total,
                                &value))
          {
            GNUNET_break (0);
            json_decref (json_history);
            return NULL;
          }
        }
        ret |= 2;
        if (0 !=
            json_array_append_new (json_history,
                                   json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                                              "type", "WITHDRAW",
                                              "reserve_sig",
                                              GNUNET_JSON_from_data_auto (
                                                &pos->details.withdraw->
                                                reserve_sig),
                                              "h_coin_envelope",
                                              GNUNET_JSON_from_data_auto (
                                                &pos->details.withdraw->
                                                h_coin_envelope),
                                              "h_denom_pub",
                                              GNUNET_JSON_from_data_auto (
                                                &pos->details.withdraw->
                                                denom_pub_hash),
                                              "withdraw_fee",
                                              TALER_JSON_from_amount (
                                                &pos->details.withdraw->
                                                withdraw_fee),
                                              "amount", TALER_JSON_from_amount (
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
        const struct TALER_EXCHANGEDB_Recoup *recoup;
        struct TALER_RecoupConfirmationPS pc;
        struct TALER_ExchangePublicKeyP pub;
        struct TALER_ExchangeSignatureP sig;

        recoup = pos->details.recoup;
        if (0 == (1 & ret))
          deposit_total = recoup->value;
        else if (GNUNET_OK !=
                 TALER_amount_add (&deposit_total,
                                   &deposit_total,
                                   &recoup->value))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
        ret |= 1;
        pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP);
        pc.purpose.size = htonl (sizeof (struct TALER_RecoupConfirmationPS));
        pc.timestamp = GNUNET_TIME_absolute_hton (recoup->timestamp);
        TALER_amount_hton (&pc.recoup_amount,
                           &recoup->value);
        pc.coin_pub = recoup->coin.coin_pub;
        pc.reserve_pub = recoup->reserve_pub;
        if (GNUNET_OK !=
            TEH_KS_sign (&pc.purpose,
                         &pub,
                         &sig))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }

        if (0 !=
            json_array_append_new (json_history,
                                   json_pack ("{s:s, s:o, s:o, s:o, s:o, s:o}",
                                              "type", "RECOUP",
                                              "exchange_pub",
                                              GNUNET_JSON_from_data_auto (&pub),
                                              "exchange_sig",
                                              GNUNET_JSON_from_data_auto (&sig),
                                              "timestamp",
                                              GNUNET_JSON_from_time_abs (
                                                recoup->timestamp),
                                              "amount", TALER_JSON_from_amount (
                                                &recoup->value),
                                              "coin_pub",
                                              GNUNET_JSON_from_data_auto (
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
        struct TALER_ReserveCloseConfirmationPS rcc;
        struct TALER_ExchangePublicKeyP pub;
        struct TALER_ExchangeSignatureP sig;
        struct TALER_Amount value;

        value = pos->details.closing->amount;
        if (0 == (2 & ret))
        {
          withdraw_total = value;
        }
        else
        {
          if (GNUNET_OK !=
              TALER_amount_add (&withdraw_total,
                                &withdraw_total,
                                &value))
          {
            GNUNET_break (0);
            json_decref (json_history);
            return NULL;
          }
        }
        ret |= 2;
        rcc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED);
        rcc.purpose.size = htonl (sizeof (struct
                                          TALER_ReserveCloseConfirmationPS));
        rcc.timestamp = GNUNET_TIME_absolute_hton (
          pos->details.closing->execution_date);
        TALER_amount_hton (&rcc.closing_amount,
                           &value);
        TALER_amount_hton (&rcc.closing_fee,
                           &pos->details.closing->closing_fee);
        rcc.reserve_pub = pos->details.closing->reserve_pub;
        GNUNET_CRYPTO_hash (pos->details.closing->receiver_account_details,
                            strlen (
                              pos->details.closing->receiver_account_details)
                            + 1,
                            &rcc.h_wire);
        rcc.wtid = pos->details.closing->wtid;
        if (GNUNET_OK !=
            TEH_KS_sign (&rcc.purpose,
                         &pub,
                         &sig))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
        if (0 !=
            json_array_append_new (json_history,
                                   json_pack (
                                     "{s:s, s:s, s:o, s:o, s:o, s:o, s:o, s:o}",
                                     "type", "CLOSING",
                                     "receiver_account_details",
                                     pos->details.closing->
                                     receiver_account_details,
                                     "wtid",
                                     GNUNET_JSON_from_data_auto (
                                       &pos->details.closing->wtid),
                                     "exchange_pub",
                                     GNUNET_JSON_from_data_auto (&pub),
                                     "exchange_sig",
                                     GNUNET_JSON_from_data_auto (&sig),
                                     "timestamp",
                                     GNUNET_JSON_from_time_abs (
                                       pos->details.closing->execution_date),
                                     "amount", TALER_JSON_from_amount (
                                       &value),
                                     "closing_fee",
                                     TALER_JSON_from_amount (
                                       &pos->details.closing->closing_fee))))
        {
          GNUNET_break (0);
          json_decref (json_history);
          return NULL;
        }
      }
      break;
    }
  }

  if (0 == (1 & ret))
  {
    GNUNET_break (0);
    json_decref (json_history);
    return NULL;
  }
  if (0 == (2 & ret))
  {
    /* did not encounter any withdraw operations, set to zero */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (deposit_total.currency,
                                          &withdraw_total));
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (balance,
                             &deposit_total,
                             &withdraw_total))
  {
    GNUNET_break (0);
    json_decref (json_history);
    return NULL;
  }

  return json_history;
}


/* end of taler-exchange-httpd_responses.c */
