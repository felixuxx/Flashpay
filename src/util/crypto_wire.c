/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file util/crypto_wire.c
 * @brief functions for making and verifying /wire account signatures
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_crypto_lib.h"
#include "taler_signatures.h"


/**
 * Compute the hash of the given wire details. The resulting
 * hash is what is signed by the master key.
 *
 * @param payto_uri bank account
 * @param[out] hc set to the hash
 */
void
TALER_exchange_wire_signature_hash (const char *payto_uri,
                                    struct GNUNET_HashCode *hc)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (hc,
                                    sizeof (*hc),
                                    payto_uri,
                                    strlen (payto_uri) + 1,
                                    "exchange-wire-signature",
                                    strlen ("exchange-wire-signature"),
                                    NULL, 0));
}


/**
 * Check the signature in @a master_sig.
 *
 * @param payto_uri URL that is signed
 * @param master_pub master public key of the exchange
 * @param master_sig signature of the exchange
 * @return #GNUNET_OK if signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_wire_signature_check (
  const char *payto_uri,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterWireDetailsPS wd = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_DETAILS),
    .purpose.size = htonl (sizeof (wd))
  };

  TALER_exchange_wire_signature_hash (payto_uri,
                                      &wd.h_wire_details);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_DETAILS,
                                     &wd,
                                     &master_sig->eddsa_signature,
                                     &master_pub->eddsa_pub);
}


/**
 * Create a signed wire statement for the given account.
 *
 * @param payto_uri account specification
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_wire_signature_make (
  const char *payto_uri,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterWireDetailsPS wd = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_DETAILS),
    .purpose.size = htonl (sizeof (wd))
  };

  TALER_exchange_wire_signature_hash (payto_uri,
                                      &wd.h_wire_details);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &wd,
                            &master_sig->eddsa_signature);
}


/**
 * Compute the hash of the given wire details.   The resulting
 * @a hc is what will be put into the contract between customer
 * and merchant for signing by both parties.
 *
 * @param payto_uri bank account
 * @param salt salt used to eliminate brute-force inversion
 * @param[out] hc set to the hash
 */
void
TALER_merchant_wire_signature_hash (const char *payto_uri,
                                    const char *salt,
                                    struct GNUNET_HashCode *hc)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (hc,
                                    sizeof (*hc),
                                    salt,
                                    strlen (salt) + 1,
                                    payto_uri,
                                    strlen (payto_uri) + 1,
                                    "merchant-wire-signature",
                                    strlen ("merchant-wire-signature"),
                                    NULL, 0));
}


/**
 * Check the signature in @a merch_sig.
 * (Not yet used anywhere.)
 *
 * Expected to be used if/when we get @a merch_pub signed via
 * X.509 *and* have a way for the WebEx wallet to check that the
 * @a merch_pub provided matches that of the X.509 certificate
 * from the Web site. Until then, @a merch_pub cannto be
 * validated (no PKI), and hence there is no point in checking
 * these signatures. (See #5129 and #3946).
 *
 * @param payto_uri URL that is signed
 * @param salt the salt used to salt the @a payto_uri when hashing
 * @param merch_pub master public key of the merchant
 * @param merch_sig signature of the merchant
 * @return #GNUNET_OK if signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_merchant_wire_signature_check (
  const char *payto_uri,
  const char *salt,
  const struct TALER_MerchantPublicKeyP *merch_pub,
  const struct TALER_MerchantSignatureP *merch_sig)
{
  struct TALER_MasterWireDetailsPS wd = {
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


/**
 * Create a signed wire statement for the given account. (Not yet used anywhere.)
 *
 * @param payto_uri account specification
 * @param salt the salt used to salt the @a payto_uri when hashing
 * @param merch_priv private key to sign with
 * @param[out] merch_sig where to write the signature
 */
void
TALER_merchant_wire_signature_make (
  const char *payto_uri,
  const char *salt,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct TALER_MerchantSignatureP *merch_sig)
{
  struct TALER_MasterWireDetailsPS wd = {
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


/* end of crypto_wire.c */
