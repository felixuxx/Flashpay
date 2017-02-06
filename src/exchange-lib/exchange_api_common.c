/*
  This file is part of TALER
  Copyright (C) 2015, 2016 Inria & GNUnet e.V.

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
    struct TALER_CoinSpendSignatureP sig;
    void *details;
    size_t details_size;
    const char *type;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_amount ("amount",
                       &amount),
      GNUNET_JSON_spec_string ("type",
                       &type),
      GNUNET_JSON_spec_fixed_auto ("signature",
                           &sig),
      GNUNET_JSON_spec_varsize ("details",
                        &details,
                        &details_size),
      GNUNET_JSON_spec_end()
    };

    transaction = json_array_get (history,
                                  off);
    if (GNUNET_OK !=
        GNUNET_JSON_parse (transaction,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }
    add = GNUNET_SYSERR;
    if (0 == strcasecmp (type,
                         "DEPOSIT"))
    {
      const struct TALER_DepositRequestPS *dr;
      struct TALER_Amount dr_amount;

      if (details_size != sizeof (struct TALER_DepositRequestPS))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      dr = (const struct TALER_DepositRequestPS *) details;
      if (details_size != ntohl (dr->purpose.size))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                      &dr->purpose,
                                      &sig.eddsa_signature,
                                      &coin_pub->eddsa_pub))
        {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }

      TALER_amount_ntoh (&dr_amount,
                         &dr->amount_with_fee);
      if (0 != TALER_amount_cmp (&dr_amount,
                                 &amount))
      {
        GNUNET_break (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "MELT"))
    {
      const struct TALER_RefreshMeltCoinAffirmationPS *rm;
      struct TALER_Amount rm_amount;

      if (details_size != sizeof (struct TALER_RefreshMeltCoinAffirmationPS))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      rm = (const struct TALER_RefreshMeltCoinAffirmationPS *) details;
      if (details_size != ntohl (rm->purpose.size))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                      &rm->purpose,
                                      &sig.eddsa_signature,
                                      &coin_pub->eddsa_pub))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      TALER_amount_ntoh (&rm_amount,
                         &rm->amount_with_fee);
      if (0 != TALER_amount_cmp (&rm_amount,
                                 &amount))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      add = GNUNET_YES;
    }
    else if (0 == strcasecmp (type,
                              "REFUND"))
    {
      const struct TALER_RefundRequestPS *rr;
      struct TALER_Amount rr_amount;
      struct TALER_Amount rr_fee;
      struct TALER_Amount rr_delta;

      if (details_size != sizeof (struct TALER_RefundRequestPS))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      rr = (const struct TALER_RefundRequestPS *) details;
      if (details_size != ntohl (rr->purpose.size))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                      &rr->purpose,
                                      &sig.eddsa_signature,
                                      &rr->merchant.eddsa_pub))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      TALER_amount_ntoh (&rr_amount,
                         &rr->refund_amount);
      TALER_amount_ntoh (&rr_fee,
                         &rr->refund_fee);
      if (GNUNET_OK !=
          TALER_amount_subtract (&rr_delta,
                                 &rr_amount,
                                 &rr_fee))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      if (0 != TALER_amount_cmp (&rr_delta,
                                 &amount))
      {
        GNUNET_break_op (0);
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
      /* NOTE/FIXME: theoretically, we could also check that the given
         transaction_id and merchant_pub and h_proposal_data appear in the
         history under deposits.  However, there is really no benefit
         for the exchange to lie here, so not checking is probably OK
         (an auditor ought to check, though). Then again, we similarly
         had no reason to check the merchant's signature (other than a
         well-formendess check). */
      add = GNUNET_NO;
    }
    else
    {
      /* signature not supported, new version on server? */
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
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
        GNUNET_JSON_parse_free (spec);
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
        GNUNET_JSON_parse_free (spec);
        return GNUNET_SYSERR;
      }
    }
    GNUNET_JSON_parse_free (spec);
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
