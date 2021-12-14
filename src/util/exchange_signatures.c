/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange_signatures.c
 * @brief Utility functions for Taler security module signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


enum GNUNET_GenericReturnValue
TALER_exchange_deposit_confirm_verify (
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_ExtensionContractHash *h_extensions,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig)
{
  struct TALER_DepositConfirmationPS dcs = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT),
    .purpose.size = htonl (sizeof (struct TALER_DepositConfirmationPS)),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .exchange_timestamp = GNUNET_TIME_timestamp_hton (exchange_timestamp),
    .wire_deadline = GNUNET_TIME_timestamp_hton (wire_deadline),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .coin_pub = *coin_pub,
    .merchant_pub = *merchant_pub
  };

  if (NULL != h_extensions)
    dcs.h_extensions = *h_extensions;
  TALER_amount_hton (&dcs.amount_without_fee,
                     amount_without_fee);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT,
                                  &dcs,
                                  &exchange_sig->eddsa_signature,
                                  &exchange_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/* end of exchange_signatures.c */
