/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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


/**
 * Parse history given in JSON format and return it in binary
 * format.
 *
 * @param exchange connection to the exchange we can use
 * @param history JSON array with the history
 * @param reserve_pub public key of the reserve to inspect
 * @param currency currency we expect the balance to be in
 * @param[out] balance final balance
 * @param history_length number of entries in @a history
 * @param[out] rhistory array of length @a history_length, set to the
 *             parsed history entries
 * @return #GNUNET_OK if history was valid and @a rhistory and @a balance
 *         were set,
 *         #GNUNET_SYSERR if there was a protocol violation in @a history
 */
int
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
                 TALER_amount_get_zero (currency,
                                        &total_in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
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
      TALER_JSON_spec_amount ("amount",
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
      void *wire_reference;
      size_t wire_reference_size;
      struct GNUNET_TIME_Absolute timestamp;

      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_varsize ("wire_reference",
                                  &wire_reference,
                                  &wire_reference_size),
        GNUNET_JSON_spec_absolute_time ("timestamp",
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
      rh->details.in_details.wire_reference_size =
        wire_reference_size;
      rh->details.in_details.timestamp = timestamp;
      /* end type==DEPOSIT */
    }
    else if (0 == strcasecmp (type,
                              "WITHDRAW"))
    {
      struct TALER_ReserveSignatureP sig;
      struct TALER_WithdrawRequestPS withdraw_purpose;
      struct GNUNET_JSON_Specification withdraw_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &sig),
        TALER_JSON_spec_amount_nbo ("withdraw_fee",
                                    &withdraw_purpose.withdraw_fee),
        GNUNET_JSON_spec_fixed_auto ("h_denom_pub",
                                     &withdraw_purpose.h_denomination_pub),
        GNUNET_JSON_spec_fixed_auto ("h_coin_envelope",
                                     &withdraw_purpose.h_coin_envelope),
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
      withdraw_purpose.purpose.size
        = htonl (sizeof (withdraw_purpose));
      withdraw_purpose.purpose.purpose
        = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
      withdraw_purpose.reserve_pub = *reserve_pub;
      TALER_amount_hton (&withdraw_purpose.amount_with_fee,
                         &amount);
      /* Check that the signature is a valid withdraw request */
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                      &withdraw_purpose,
                                      &sig.eddsa_signature,
                                      &reserve_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (withdraw_spec);
        return GNUNET_SYSERR;
      }
      /* check that withdraw fee matches expectations! */
      {
        const struct TALER_EXCHANGE_Keys *key_state;
        const struct TALER_EXCHANGE_DenomPublicKey *dki;
        struct TALER_Amount fee;

        key_state = TALER_EXCHANGE_get_keys (exchange);
        dki = TALER_EXCHANGE_get_denomination_key_by_hash (key_state,
                                                           &withdraw_purpose.
                                                           h_denomination_pub);
        TALER_amount_ntoh (&fee,
                           &withdraw_purpose.withdraw_fee);
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dki->fee_withdraw)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dki->fee_withdraw)) )
        {
          GNUNET_break_op (0);
          GNUNET_JSON_parse_free (withdraw_spec);
          return GNUNET_SYSERR;
        }
        rh->details.withdraw.fee = fee;
      }
      rh->details.withdraw.out_authorization_sig
        = json_object_get (transaction,
                           "signature");
      /* Check check that the same withdraw transaction
         isn't listed twice by the exchange. We use the
         "uuid" array to remember the hashes of all
         purposes, and compare the hashes to find
         duplicates. *///
      GNUNET_CRYPTO_hash (&withdraw_purpose,
                          ntohl (withdraw_purpose.purpose.size),
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
      struct GNUNET_TIME_Absolute timestamp;
      const struct TALER_EXCHANGE_Keys *key_state;
      struct GNUNET_JSON_Specification recoup_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                     &pc.coin_pub),
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &rh->details.recoup_details.exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &rh->details.recoup_details.exchange_pub),
        GNUNET_JSON_spec_absolute_time_nbo ("timestamp",
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
      timestamp = GNUNET_TIME_absolute_ntoh (pc.timestamp);
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
      struct GNUNET_TIME_Absolute timestamp;
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
        TALER_JSON_spec_amount_nbo ("closing_fee",
                                    &rcc.closing_fee),
        GNUNET_JSON_spec_absolute_time_nbo ("timestamp",
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
      GNUNET_CRYPTO_hash (
        rh->details.close_details.receiver_account_details,
        strlen (rh->details.close_details.receiver_account_details) + 1,
        &rcc.h_wire);
      rcc.wtid = rh->details.close_details.wtid;
      rcc.purpose.size = htonl (sizeof (rcc));
      rcc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_RESERVE_CLOSED);
      rcc.reserve_pub = *reserve_pub;
      timestamp = GNUNET_TIME_absolute_ntoh (rcc.timestamp);
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


/**
 * Free memory (potentially) allocated by #TALER_EXCHANGE_parse_reserve_history().
 *
 * @param rhistory result to free
 * @param len number of entries in @a rhistory
 */
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
      GNUNET_free (rhistory[i].details.in_details.wire_reference);
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


/**
 * Verify a coins transaction history as returned by the exchange.
 *
 * @param dk fee structure for the coin, NULL to skip verifying fees
 * @param currency expected currency for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
int
TALER_EXCHANGE_verify_coin_history (
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  const char *currency,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  json_t *history,
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
                 TALER_amount_get_zero (currency,
                                        total));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &rtotal));
  for (size_t off = 0; off<len; off++)
  {
    int add;
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification spec_glob[] = {
      TALER_JSON_spec_amount ("amount",
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
      struct TALER_DepositRequestPS dr;
      struct TALER_CoinSpendSignatureP sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &dr.h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("h_wire",
                                     &dr.h_wire),
        GNUNET_JSON_spec_absolute_time_nbo ("timestamp",
                                            &dr.timestamp),
        GNUNET_JSON_spec_absolute_time_nbo ("refund_deadline",
                                            &dr.refund_deadline),
        TALER_JSON_spec_amount_nbo ("deposit_fee",
                                    &dr.deposit_fee),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &dr.merchant),
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
      dr.purpose.size = htonl (sizeof (dr));
      dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
      TALER_amount_hton (&dr.amount_with_fee,
                         &amount);
      dr.coin_pub = *coin_pub;
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                      &dr,
                                      &sig.eddsa_signature,
                                      &coin_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (NULL != dk)
      {
        /* check that deposit fee matches our expectations from /keys! */
        TALER_amount_ntoh (&fee,
                           &dr.deposit_fee);
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dk->fee_deposit)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dk->fee_deposit)) )
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
      struct TALER_RefreshMeltCoinAffirmationPS rm;
      struct TALER_CoinSpendSignatureP sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("rc",
                                     &rm.rc),
        TALER_JSON_spec_amount_nbo ("melt_fee",
                                    &rm.melt_fee),
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
      rm.purpose.size = htonl (sizeof (rm));
      rm.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
      TALER_amount_hton (&rm.amount_with_fee,
                         &amount);
      rm.coin_pub = *coin_pub;
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                      &rm,
                                      &sig.eddsa_signature,
                                      &coin_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      if (NULL != dk)
      {
        /* check that melt fee matches our expectations from /keys! */
        TALER_amount_ntoh (&fee,
                           &rm.melt_fee);
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dk->fee_refresh)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dk->fee_refresh)) )
        {
          GNUNET_break_op (0);
          return GNUNET_SYSERR;
        }
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "REFUND"))
    {
      struct TALER_RefundRequestPS rr;
      struct TALER_MerchantSignatureP sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &rr.h_contract_terms),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &rr.merchant),
        GNUNET_JSON_spec_uint64 ("rtransaction_id",
                                 &rr.rtransaction_id),
        TALER_JSON_spec_amount_nbo ("refund_fee",
                                    &rr.refund_fee),
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
      rr.purpose.size = htonl (sizeof (rr));
      rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
      rr.coin_pub = *coin_pub;
      TALER_amount_hton (&rr.refund_amount,
                         &amount);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                      &rr,
                                      &sig.eddsa_sig,
                                      &rr.merchant.eddsa_pub))
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
         well-formendess check). *///

      /* check that refund fee matches our expectations from /keys! */
      if (NULL != dk)
      {
        TALER_amount_ntoh (&fee,
                           &rr.refund_fee);
        if ( (GNUNET_YES !=
              TALER_amount_cmp_currency (&fee,
                                         &dk->fee_refund)) ||
             (0 !=
              TALER_amount_cmp (&fee,
                                &dk->fee_refund)) )
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
      struct TALER_RecoupConfirmationPS pc;
      struct TALER_ExchangePublicKeyP exchange_pub;
      struct TALER_ExchangeSignatureP exchange_sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("exchange_sig",
                                     &exchange_sig),
        GNUNET_JSON_spec_fixed_auto ("exchange_pub",
                                     &exchange_pub),
        GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                     &pc.reserve_pub),
        GNUNET_JSON_spec_absolute_time_nbo ("timestamp",
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
      pc.purpose.size = htonl (sizeof (pc));
      pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_RECOUP);
      pc.coin_pub = *coin_pub;
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
      add = GNUNET_YES;
    }
    else
    {
      /* signature not supported, new version on server? */
      GNUNET_break_op (0);
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
         the subtraction by calculating "total = total - rtotal" */GNUNET_assert (GNUNET_NO == add);
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


/**
 * Obtain meta data about an exchange (online) signing
 * key.
 *
 * @param keys from where to obtain the meta data
 * @param exchange_pub public key to lookup
 * @return NULL on error (@a exchange_pub not known)
 */
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
