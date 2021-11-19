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
#include "taler_util.h"
#include "taler_signatures.h"


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

  TALER_payto_hash (payto_uri,
                    &wd.h_wire_details);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_DETAILS,
                                     &wd,
                                     &master_sig->eddsa_signature,
                                     &master_pub->eddsa_pub);
}


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

  TALER_payto_hash (payto_uri,
                    &wd.h_wire_details);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &wd,
                            &master_sig->eddsa_signature);
}


void
TALER_merchant_wire_signature_hash (const char *payto_uri,
                                    const struct TALER_WireSalt *salt,
                                    struct TALER_MerchantWireHash *hc)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (hc,
                                    sizeof (*hc),
                                    salt,
                                    sizeof (*salt),
                                    payto_uri,
                                    strlen (payto_uri) + 1,
                                    "merchant-wire-signature",
                                    strlen ("merchant-wire-signature"),
                                    NULL, 0));
}


enum GNUNET_GenericReturnValue
TALER_merchant_wire_signature_check (
  const char *payto_uri,
  const struct TALER_WireSalt *salt,
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
  const struct TALER_WireSalt *salt,
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


/* end of crypto_wire.c */
