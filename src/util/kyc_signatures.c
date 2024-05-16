/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file kyc_signatures.c
 * @brief Utility functions for KYC account holders
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used to generate the signature on a
 * KYC authorization.
 */
struct TALER_KycQueryPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_KYC_AUTH.
   * Used for an EdDSA signature with the `union TALER_AccountPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

};

GNUNET_NETWORK_STRUCT_END


void
TALER_account_kyc_auth_sign (
  const union TALER_AccountPrivateKeyP *account_priv,
  union TALER_AccountSignatureP *account_sig)
{
  struct TALER_KycQueryPS aq = {
    .purpose.purpose = htonl (TALER_SIGNATURE_KYC_AUTH),
    .purpose.size = htonl (sizeof (aq))
  };

  GNUNET_CRYPTO_eddsa_sign (
    &account_priv->reserve_priv.eddsa_priv,
    &aq,
    &account_sig->reserve_sig.eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_account_kyc_auth_verify (
  const union TALER_AccountPublicKeyP *account_pub,
  const union TALER_AccountSignatureP *account_sig)
{
  struct TALER_KycQueryPS aq = {
    .purpose.purpose = htonl (TALER_SIGNATURE_KYC_AUTH),
    .purpose.size = htonl (sizeof (aq))
  };

  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_KYC_AUTH,
    &aq,
    &account_sig->reserve_sig.eddsa_signature,
    &account_pub->reserve_pub.eddsa_pub);
}


/* end of kyc_signatures.c */
