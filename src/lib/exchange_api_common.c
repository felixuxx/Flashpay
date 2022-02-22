/*
  This file is part of TALER
  Copyright (C) 2015-2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_common.c
 * @brief common functions for the exchange API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_parse_reserve_history (
  struct TALER_EXCHANGE_Handle *exchange,
  const json_t *history,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *currency,
  struct TALER_Amount *balance,
  unsigned int history_length,
  struct TALER_EXCHANGE_ReserveHistory *rhistory)
{
  struct GNUNET_HashCode uuid[history_length];
  unsigned int uuid_off;
  struct TALER_Amount total_in;
  struct TALER_Amount total_out;

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &total_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &total_out));
  uuid_off = 0;
  for (unsigned int off = 0; off<history_length; off++)
  {
    struct TALER_EXCHANGE_ReserveHistory *rh = &rhistory[off];
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification hist_spec[] = {
      GNUNET_JSON_spec_string ("type",
                               &type),
      TALER_JSON_spec_amount_any ("amount",
                                  &amount),
      /* 'wire' and 'signature' are optional depending on 'type'! */
      GNUNET_JSON_spec_end ()
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           hist_spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    rhistory[off].amount = amount;
    if (GNUNET_YES !=
        TALER_amount_cmp_currency (&amount,
                                   &total_in))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (0 == strcasecmp (type,
                         "CREDIT"))
    {
      const char *wire_url;
      uint64_t wire_reference;
      struct GNUNET_TIME_Timestamp timestamp;
      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_uint64 ("wire_reference",
                                 &wire_reference),
        GNUNET_JSON_spec_timestamp ("timestamp",
                                    &timestamp),
        GNUNET_JSON_spec_string ("sender_account_url",
                                 &wire_url),
        GNUNET_JSON_spec_end ()
      };

      rh->type = TALER_EXCHANGE_RTT_CREDIT;
      if (0 >
          TALER_amount_add (&total_in,
                            &total_in,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             withdraw_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      rh->details.in_details.sender_url = GNUNET_strdup (wire_url);
      rh->details.in_details.wire_reference = wire_reference;
      rh->details.in_details.timestamp = timestamp;
      /* end type==DEPOSIT */
    }
    else if (0 == strcasecmp (type,
                              "WITHDRAW"))
    {
      struct TALER_ReserveSignatureP sig;
      struct TALER_DenominationHashP h_denom_pub;
      struct TALER_BlindedCoinHashP bch;
      struct TALER_Amount withdraw_fee;
      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &sig),
        TALER_JSON_spec_amount_any ("withdraw_fee",
                                    &withdraw_fee),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     &h_denom_pub),
        GNUNET_JSON_spec_fixed_auto ("h_coin_envelope",
                                     &bch),
        GNUNET_JSON_spec_end ()
      };

      rh->type = TALER_EXCHANGE_RTT_WITHDRAWAL;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             withdraw_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }

      /* Check that the signature is a valid withdraw request */
      if (GNUNET_OK !=
          TALER_wallet_withdraw_verify (&h_denom_pub,
                                        &amount,
                                        &bch,
                                        reserve_pub,
                                        &sig))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      /* check that withdraw fee matches expectations! */
      {
        const struct TALER_EXCHANGE_Keys *key_state;
        const struct TALER_EXCHANGE_DenomPublicKey *dki;

        key_state = TALER_EXCHANGE_get_keys (exchange);
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                           &h_denom_pub);
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&withdraw_fee,
                                         &dki->fees.withdraw)) ||
             (0 !=
              TALER_amount_cmp (&withdraw_fee,
                                &dki->fees.withdraw)) )
        {
          GNUNET_break_op (0);
          GNUNET_JSON_parse_free (withdraw_spec);
          return GNUNET_SYSERR;
        }
        rh->details.withdraw.fee = withdraw_fee;
      }
      rh->details.withdraw.out_authorization_sig
        = json_object_get (transaction,
                           "signature");
      /* Check check that the same withdraw transaction
         isn't listed twice by the exchange. We use the
         "uuid" array to remember the hashes of all
         signatures, and compare the hashes to find
         duplicates. */
      GNUNET_CRYPTO_hash (&sig,
                          sizeof (sig),
                          &uuid[uuid_off]);
      for (unsigned int i = 0; i<uuid_off; i++)
      {
        if (0 == GNUNET_memcmp (&uuid[uuid_off],
                                &uuid[i]))
        {
          GNUNET_break_op (0);
          GNUNET_JSON_parse_free (withdraw_spec);
          return GNUNET_SYSERR;
        }
      }
      uuid_off++;

      if (0 >
          TALER_amount_add (&total_out,
                            &total_out,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      /* end type==WITHDRAW */
    }
    else if (0 == strcasecmp (type,
                              "RECOUP"))
    {
      struct TALER_RecoupConfirmationPS pc;
      struct GNUNET_TIME_Timestamp timestamp;
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_JSON_Specification recoup_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                     &pc.coin_pub),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &rh->details.recoup_details.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &rh->details.recoup_details.exchange_pub),
        GNUNET_JSON_spec_timestamp_nbo ("timestamp",
                                        &pc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      rh->type = TALER_EXCHANGE_RTT_RECOUP;
      rh->amount = amount;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             recoup_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      rh->details.recoup_details.coin_pub = pc.coin_pub;
      TALER_amount_hton (&pc.recoup_amount,
                         &amount);
      pc.purpose.size = htonl (sizeof (pc));
      pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP);
      pc.reserve_pub = *reserve_pub;
      timestamp = GNUNET_TIME_timestamp_ntoh (pc.timestamp);
      rh->details.recoup_details.timestamp = timestamp;

      key_state = TALER_EXCHANGE_get_keys (exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &rh->details.
                                           recoup_details.exchange_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP,
            &pc,
            &rh->details.recoup_details.exchange_sig.eddsa_signature,
            &rh->details.recoup_details.exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (0 >
          TALER_amount_add (&total_in,
                            &total_in,
                            &rh->amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* end type==RECOUP */
    }
    else if (0 == strcasecmp (type,
                              "CLOSING"))
    {
      const struct TALER_EXCHANGE_Keys *key_state;
      struct TALER_ReserveCloseConfirmationPS rcc;
      struct GNUNET_TIME_Timestamp timestamp;
      struct GNUNET_JSON_Specification closing_spec[] = {
        GNUNET_JSON_spec_string (
          "receiver_account_details",
          &rh->details.close_details.receiver_account_details),
        GNUNET_JSON_spec_fixed_auto ("wtid",
                                     &rh->details.close_details.wtid),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &rh->details.close_details.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &rh->details.close_details.exchange_pub),
        TALER_JSON_spec_amount_any_nbo ("closing_fee",
                                        &rcc.closing_fee),
        GNUNET_JSON_spec_timestamp_nbo ("timestamp",
                                        &rcc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      rh->type = TALER_EXCHANGE_RTT_CLOSE;
      rh->amount = amount;
      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             closing_spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      TALER_amount_hton (&rcc.closing_amount,
                         &amount);
      TALER_payto_hash (rh->details.close_details.receiver_account_details,
                        &rcc.h_payto);
      rcc.wtid = rh->details.close_details.wtid;
      rcc.purpose.size = htonl (sizeof (rcc));
      rcc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED);
      rcc.reserve_pub = *reserve_pub;
      timestamp = GNUNET_TIME_timestamp_ntoh (rcc.timestamp);
      rh->details.close_details.timestamp = timestamp;
      TALER_amount_ntoh (&rh->details.close_details.fee,
                         &rcc.closing_fee);
      key_state = TALER_EXCHANGE_get_keys (exchange);
      if (GNUNET_OK !=
          TALER_EXCHANGE_test_signing_key (key_state,
                                           &rh->details.close_details.
                                           exchange_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED,
            &rcc,
            &rh->details.close_details.exchange_sig.eddsa_signature,
            &rh->details.close_details.exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (0 >
          TALER_amount_add (&total_out,
                            &total_out,
                            &rh->amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* end type==CLOSING */
    }
    else
    {
      /* unexpected 'type', protocol incompatibility, complain! */
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
  }

  /* check balance = total_in - total_out < withdraw-amount */
  if (0 >
      TALER_amount_subtract (balance,
                             &total_in,
                             &total_out))
  {
    /* total_in < total_out, why did the exchange ever allow this!? */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


void
TALER_EXCHANGE_free_reserve_history (
  struct TALER_EXCHANGE_ReserveHistory *rhistory,
  unsigned int len)
{
  for (unsigned int i = 0; i<len; i++)
  {
    switch (rhistory[i].type)
    {
    case TALER_EXCHANGE_RTT_CREDIT:
      GNUNET_free (rhistory[i].details.in_details.sender_url);
      break;
    case TALER_EXCHANGE_RTT_WITHDRAWAL:
      break;
    case TALER_EXCHANGE_RTT_RECOUP:
      break;
    case TALER_EXCHANGE_RTT_CLOSE:
      break;
    }
  }
  GNUNET_free (rhistory);
}


enum GNUNET_GenericReturnValue
TALER_EXCHANGE_verify_coin_history (
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const char *currency,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  json_t *history,
  struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_Amount *total)
{
  size_t len;
  struct TALER_Amount rtotal;
  struct TALER_Amount fee;

  if (NULL == history)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  len = json_array_size (history);
  if (0 == len)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        total));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (currency,
                                        &rtotal));
  for (size_t off = 0; off<len; off++)
  {
    int add;
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification spec_glob[] = {
      TALER_JSON_spec_amount_any ("amount",
                                  &amount),
      GNUNET_JSON_spec_string ("type",
                               &type),
      GNUNET_JSON_spec_end ()
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           spec_glob,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    if (GNUNET_YES !=
        TALER_amount_cmp_currency (&amount,
                                   &rtotal))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    add = GNUNET_SYSERR;
    if (0 == strcasecmp (type,
                         "DEPOSIT"))
    {
      struct TALER_MerchantWireHashP h_wire;
      struct TALER_PrivateContractHashP h_contract_terms;
      // struct TALER_ExtensionContractHashP h_extensions; // FIXME!
      struct GNUNET_TIME_Timestamp wallet_timestamp;
      struct TALER_MerchantPublicKeyP merchant_pub;
      struct GNUNET_TIME_Timestamp refund_deadline = {0};
      struct TALER_CoinSpendSignatureP sig;
      struct TALER_AgeCommitmentHash hac = {0};
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("h_wire",
                                     &h_wire),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     h_denom_pub),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                       &hac)),
        GNUNET_JSON_spec_timestamp ("timestamp",
                                    &wallet_timestamp),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_timestamp ("refund_deadline",
                                      &refund_deadline)),
        TALER_JSON_spec_amount_any ("deposit_fee",
                                    &fee),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &merchant_pub),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_wallet_deposit_verify (
            &amount,
            &fee,
            &h_wire,
            &h_contract_terms,
            TALER_AgeCommitmentHash_isNullOrZero (&hac) ?  NULL : &hac,
            NULL /* h_extensions! */,
            h_denom_pub,
            wallet_timestamp,
            &merchant_pub,
            refund_deadline,
            coin_pub,
            &sig))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (NULL != dk)
      {
        /* check that deposit fee matches our expectations from /keys! */
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dk->fees.deposit)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dk->fees.deposit)) )
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "MELT"))
    {
      struct TALER_CoinSpendSignatureP sig;
      struct TALER_RefreshCommitmentP rc;
      struct TALER_AgeCommitmentHash h_age_commitment = {0};
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("rc",
                                     &rc),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     h_denom_pub),
        GNUNET_JSON_spec_mark_optional (
          GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                       &h_age_commitment)),
        TALER_JSON_spec_amount_any ("melt_fee",
                                    &fee),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }

      if (NULL != dk)
      {
        /* check that melt fee matches our expectations from /keys! */
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dk->fees.refresh)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dk->fees.refresh)) )
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }


      if (GNUNET_OK !=
          TALER_wallet_melt_verify (
            &amount,
            &fee,
            &rc,
            h_denom_pub,
            TALER_AgeCommitmentHash_isNullOrZero (&h_age_commitment) ?
            NULL : &h_age_commitment,
            coin_pub,
            &sig))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "REFUND"))
    {
      struct TALER_PrivateContractHashP h_contract_terms;
      struct TALER_MerchantPublicKeyP merchant_pub;
      struct TALER_MerchantSignatureP sig;
      struct TALER_Amount refund_fee;
      struct TALER_Amount sig_amount;
      uint64_t rtransaction_id;
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount_any ("refund_fee",
                                    &refund_fee),
        GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &merchant_pub),
        GNUNET_JSON_spec_uint64 ("rtransaction_id",
                                 &rtransaction_id),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (0 >
          TALER_amount_add (&sig_amount,
                            &refund_fee,
                            &amount))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_merchant_refund_verify (coin_pub,
                                        &h_contract_terms,
                                        rtransaction_id,
                                        &sig_amount,
                                        &merchant_pub,
                                        &sig))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* NOTE: theoretically, we could also check that the given
         merchant_pub and h_contract_terms appear in the
         history under deposits.  However, there is really no benefit
         for the exchange to lie here, so not checking is probably OK
         (an auditor ought to check, though). Then again, we similarly
         had no reason to check the merchant's signature (other than a
         well-formendess check). */

      /* check that refund fee matches our expectations from /keys! */
      if (NULL != dk)
      {
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&refund_fee,
                                         &dk->fees.refund)) ||
             (0 !=
              TALER_amount_cmp (&refund_fee,
                                &dk->fees.refund)) )
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      add = GNUNET_NO;
    }
    else if (0 == strcasecmp (type,
                              "RECOUP"))
    {
      struct TALER_RecoupConfirmationPS pc = {
        .purpose.size = htonl (sizeof (pc)),
        .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP),
        .coin_pub = *coin_pub
      };
      union TALER_DenominationBlindingKeyP coin_bks;
      struct TALER_Amount recoup_amount;
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct TALER_CoinSpendSignatureP coin_sig;
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount_any_nbo ("amount",
                                        &pc.recoup_amount),
        TALER_JSON_spec_amount_any ("amount",
                                    &recoup_amount),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                     &pc.reserve_pub),
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &coin_sig),
        GNUNET_JSON_spec_fixed_auto ("coin_blind",
                                     &coin_bks),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     h_denom_pub),
        GNUNET_JSON_spec_timestamp_nbo ("timestamp",
                                        &pc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      TALER_amount_hton (&pc.recoup_amount,
                         &amount);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP,
                                      &pc,
                                      &exchange_sig.eddsa_signature,
                                      &exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_wallet_recoup_verify (h_denom_pub,
                                      &coin_bks,
                                      coin_pub,
                                      &coin_sig))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "RECOUP-REFRESH"))
    {
      /* This is the coin that was subjected to a recoup,
         the value being credited to the old coin. */
      struct TALER_RecoupRefreshConfirmationPS pc = {
        .purpose.size = htonl (sizeof (pc)),
        .purpose.purpose = htonl (
          TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH),
        .coin_pub = *coin_pub
      };
      union TALER_DenominationBlindingKeyP coin_bks;
      struct TALER_Amount recoup_amount;
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct TALER_CoinSpendSignatureP coin_sig;
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount_any_nbo ("amount",
                                        &pc.recoup_amount),
        TALER_JSON_spec_amount_any ("amount",
                                    &recoup_amount),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &coin_sig),
        GNUNET_JSON_spec_fixed_auto ("old_coin_pub",
                                     &pc.old_coin_pub),
        GNUNET_JSON_spec_fixed_auto ("coin_blind",
                                     &coin_bks),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     h_denom_pub),
        GNUNET_JSON_spec_timestamp_nbo ("timestamp",
                                        &pc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      TALER_amount_hton (&pc.recoup_amount,
                         &amount);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH,
            &pc,
            &exchange_sig.eddsa_signature,
            &exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_wallet_recoup_verify (h_denom_pub,
                                      &coin_bks,
                                      coin_pub,
                                      &coin_sig))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "OLD-COIN-RECOUP"))
    {
      /* This is the coin that was credited in a recoup,
         the value being credited to the this coin. */
      struct TALER_RecoupRefreshConfirmationPS pc = {
        .purpose.size = htonl (sizeof (pc)),
        .purpose.purpose = htonl (
          TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH),
        .old_coin_pub = *coin_pub
      };
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount_any_nbo ("amount",
                                        &pc.recoup_amount),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                     &pc.coin_pub),
        GNUNET_JSON_spec_timestamp_nbo ("timestamp",
                                        &pc.timestamp),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (transaction,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      TALER_amount_hton (&pc.recoup_amount,
                         &amount);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP_REFRESH,
            &pc,
            &exchange_sig.eddsa_signature,
            &exchange_pub.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      add = GNUNET_NO;
    }
    else if (0 == strcasecmp (type,
                              "LOCK_NONCE"))
    {
      GNUNET_break (0); // FIXME: implement!
    }
    else
    {
      /* signature not supported, new version on server? */
      GNUNET_break_op (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected type `%s' in response\n",
                  type);
      GNUNET_assert (GNUNET_SYSERR == add);
      return GNUNET_SYSERR;
    }

    if (GNUNET_YES == add)
    {
      /* This amount should be added to the total */
      if (0 >
          TALER_amount_add (total,
                            total,
                            &amount))
      {
        /* overflow in history already!? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
    }
    else
    {
      /* This amount should be subtracted from the total.

         However, for the implementation, we first *add* up all of
         these negative amounts, as we might get refunds before
         deposits from a semi-evil exchange.  Then, at the end, we do
         the subtraction by calculating "total = total - rtotal" */
      GNUNET_assert (GNUNET_NO == add);
      if (0 >
          TALER_amount_add (&rtotal,
                            &rtotal,
                            &amount))
      {
        /* overflow in refund history? inconceivable! Bad exchange! */
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }

    }
  }


  /* Finally, subtract 'rtotal' from total to handle the subtractions */
  if (0 >
      TALER_amount_subtract (total,
                             total,
                             &rtotal))
  {
    /* underflow in history? inconceivable! Bad exchange! */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


const struct TALER_EXCHANGE_SigningPublicKey *
TALER_EXCHANGE_get_signing_key_info (
  const struct TALER_EXCHANGE_Keys *keys,
  const struct TALER_ExchangePublicKeyP *exchange_pub)
{
  for (unsigned int i = 0; i<keys->num_sign_keys; i++)
  {
    const struct TALER_EXCHANGE_SigningPublicKey *spk
      = &keys->sign_keys[i];

    if (0 == GNUNET_memcmp (exchange_pub,
                            &spk->key))
      return spk;
  }
  return NULL;
}


/* end of exchange_api_common.c */
