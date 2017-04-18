/*
  This file is part of TALER
  Copyright (C) 2015-2017 Inria & GNUnet e.V.

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
 * @file exchange-lib/exchange_api_common.c
 * @brief common functions for the exchange API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"


/**
 * Verify a coins transaction history as returned by the exchange.
 *
 * @param currency expected currency for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
int
TALER_EXCHANGE_verify_coin_history (const char *currency,
				    const struct TALER_CoinSpendPublicKeyP *coin_pub,
				    json_t *history,
                                    struct TALER_Amount *total)
{
  size_t len;
  size_t off;
  int add;
  struct TALER_Amount rtotal;

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
  TALER_amount_get_zero (currency,
                         total);
  TALER_amount_get_zero (currency,
                         &rtotal);
  for (off=0;off<len;off++)
  {
    json_t *transaction;
    struct TALER_Amount amount;
    const char *type;
    struct GNUNET_JSON_Specification spec_glob[] = {
      TALER_JSON_spec_amount ("amount",
                              &amount),
      GNUNET_JSON_spec_string ("type",
                               &type),
      GNUNET_JSON_spec_end()
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
    add = GNUNET_SYSERR;
    if (0 == strcasecmp (type,
                         "DEPOSIT"))
    {
      struct TALER_DepositRequestPS dr;
      struct TALER_CoinSpendSignatureP sig;
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                     &sig),
        GNUNET_JSON_spec_fixed_auto ("h_proposal_data",
                                     &dr.h_proposal_data),
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
        GNUNET_JSON_spec_end()
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
                                      &dr.purpose,
                                      &sig.eddsa_signature,
                                      &coin_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* TODO: check that deposit fee and coin value match
	 our expectations from /keys! */
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
        GNUNET_JSON_spec_fixed_auto ("session_hash",
                                     &rm.session_hash),
        TALER_JSON_spec_amount_nbo ("melt_fee",
				    &rm.melt_fee),
        GNUNET_JSON_spec_end()
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
                                      &rm.purpose,
                                      &sig.eddsa_signature,
                                      &coin_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* TODO: check that deposit fee and coin value match
	 our expectations from /keys! */
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
        GNUNET_JSON_spec_fixed_auto ("h_proposal_data",
                                     &rr.h_proposal_data),
        GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                     &rr.merchant),
        GNUNET_JSON_spec_uint64 ("rtransaction_id",
				 &rr.rtransaction_id),
        TALER_JSON_spec_amount_nbo ("refund_fee",
				    &rr.refund_fee),
        GNUNET_JSON_spec_end()
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
                                      &rr.purpose,
                                      &sig.eddsa_sig,
                                      &rr.merchant.eddsa_pub))
      {
        GNUNET_break_op (0);
        return GNUNET_SYSERR;
      }
      /* NOTE: theoretically, we could also check that the given
         merchant_pub and h_proposal_data appear in the
         history under deposits.  However, there is really no benefit
         for the exchange to lie here, so not checking is probably OK
         (an auditor ought to check, though). Then again, we similarly
         had no reason to check the merchant's signature (other than a
         well-formendess check). */
      /* TODO: check that deposit fee and coin value match
	 our expectations from /keys! */
      add = GNUNET_NO;
    }
    else if (0 == strcasecmp (type,
                              "PAYBACK"))
    {
      struct TALER_PaybackConfirmationPS pc;
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
        GNUNET_JSON_spec_end()
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
      pc.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK);
      pc.coin_pub = *coin_pub;
      TALER_amount_hton (&pc.payback_amount,
			 &amount);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_PAYBACK,
                                      &pc.purpose,
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
      return GNUNET_SYSERR;
    }
    if (GNUNET_YES == add)
    {
      /* This amount should be added to the total */
      if (GNUNET_OK !=
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
      if (GNUNET_OK !=
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
  if (GNUNET_OK !=
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


/* end of exchange_api_common.c */
