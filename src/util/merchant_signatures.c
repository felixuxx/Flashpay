/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file merchant_signatures.c
 * @brief Utility functions for Taler merchant signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_merchant_refund_sign (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint64_t rtransaction_id,
  const struct TALER_Amount *amount,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  struct TALER_MerchantSignatureP *merchant_sig)
{
  struct TALER_RefundRequestPS rr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND),
    .purpose.size = htonl (sizeof (rr)),
    .h_contract_terms = *h_contract_terms,
    .coin_pub = *coin_pub,
    .rtransaction_id = GNUNET_htonll (rtransaction_id)
  };

  TALER_amount_hton (&rr.refund_amount,
                     amount);
  GNUNET_CRYPTO_eddsa_sign (&merchant_priv->eddsa_priv,
                            &rr,
                            &merchant_sig->eddsa_sig);
}


enum GNUNET_GenericReturnValue
TALER_merchant_refund_verify (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint64_t rtransaction_id,
  const struct TALER_Amount *amount,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_MerchantSignatureP *merchant_sig)
{
  struct TALER_RefundRequestPS rr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND),
    .purpose.size = htonl (sizeof (rr)),
    .h_contract_terms = *h_contract_terms,
    .coin_pub = *coin_pub,
    .rtransaction_id = GNUNET_htonll (rtransaction_id)
  };

  TALER_amount_hton (&rr.refund_amount,
                     amount);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                &rr,
                                &merchant_sig->eddsa_sig,
                                &merchant_pub->eddsa_pub);
}


/* end of merchant_signatures.c */
