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


/**
 * @brief Format used to generate the signature on a request to refund
 * a coin into the account of the customer.
 */
struct TALER_RefundRequestPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_MERCHANT_REFUND.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the proposal data to identify the contract
   * which is being refunded.
   */
  struct TALER_PrivateContractHashP h_contract_terms GNUNET_PACKED;

  /**
   * The coin's public key.  This is the value that must have been
   * signed (blindly) by the Exchange.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Merchant-generated transaction ID for the refund.
   */
  uint64_t rtransaction_id GNUNET_PACKED;

  /**
   * Amount to be refunded, including refund fee charged by the
   * exchange to the customer.
   */
  struct TALER_AmountNBO refund_amount;
};


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


/**
 * @brief Information signed by the exchange's master
 * key affirming the IBAN details for the exchange.
 */
struct TALER_MerchantWireDetailsPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MERCHANT_WIRE_DETAILS.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Salted hash over the account holder's payto:// URL and
   * the salt, as done by #TALER_merchant_wire_signature_hash().
   */
  struct TALER_MerchantWireHashP h_wire_details GNUNET_PACKED;

};


enum GNUNET_GenericReturnValue
TALER_merchant_wire_signature_check (
  const char *payto_uri,
  const struct TALER_WireSaltP *salt,
  const struct TALER_MerchantPublicKeyP *merch_pub,
  const struct TALER_MerchantSignatureP *merch_sig)
{
  struct TALER_MerchantWireDetailsPS wd = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_WIRE_DETAILS),
    .purpose.size = htonl (sizeof (wd))
  };

  TALER_merchant_wire_signature_hash (payto_uri,
                                      salt,
                                      &wd.h_wire_details);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_WIRE_DETAILS,
                                     &wd,
                                     &merch_sig->eddsa_sig,
                                     &merch_pub->eddsa_pub);
}


void
TALER_merchant_wire_signature_make (
  const char *payto_uri,
  const struct TALER_WireSaltP *salt,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct TALER_MerchantSignatureP *merch_sig)
{
  struct TALER_MerchantWireDetailsPS wd = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_WIRE_DETAILS),
    .purpose.size = htonl (sizeof (wd))
  };

  TALER_merchant_wire_signature_hash (payto_uri,
                                      salt,
                                      &wd.h_wire_details);
  GNUNET_CRYPTO_eddsa_sign (&merch_priv->eddsa_priv,
                            &wd,
                            &merch_sig->eddsa_sig);
}


/* end of merchant_signatures.c */
