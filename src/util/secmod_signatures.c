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
 * @file secmod_signatures.c
 * @brief Utility functions for Taler security module signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_exchange_secmod_eddsa_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Absolute start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_SigningKeyAnnouncementPS ska = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_SIGNING_KEY),
    .purpose.size = htonl (sizeof (ska)),
    .exchange_pub = *exchange_pub,
    .anchor_time = GNUNET_TIME_absolute_hton (start_sign),
    .duration = GNUNET_TIME_relative_hton (duration)
  };

  GNUNET_CRYPTO_eddsa_sign (&secm_priv->eddsa_priv,
                            &ska,
                            &secm_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_secmod_eddsa_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Absolute start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_SigningKeyAnnouncementPS ska = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_SIGNING_KEY),
    .purpose.size = htonl (sizeof (ska)),
    .exchange_pub = *exchange_pub,
    .anchor_time = GNUNET_TIME_absolute_hton (start_sign),
    .duration = GNUNET_TIME_relative_hton (duration)
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_SM_SIGNING_KEY,
                                &ska,
                                &secm_sig->eddsa_signature,
                                &secm_pub->eddsa_pub);
}


void
TALER_exchange_secmod_rsa_sign (
  const struct GNUNET_HashCode *h_denom_pub,
  const char *section_name,
  struct GNUNET_TIME_Absolute start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_DenominationKeyAnnouncementPS dka = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_DENOMINATION_KEY),
    .purpose.size = htonl (sizeof (dka)),
    .h_denom_pub = *h_denom_pub,
    .anchor_time = GNUNET_TIME_absolute_hton (start_sign),
    .duration_withdraw = GNUNET_TIME_relative_hton (duration)
  };

  GNUNET_CRYPTO_hash (section_name,
                      strlen (section_name) + 1,
                      &dka.h_section_name);
  GNUNET_CRYPTO_eddsa_sign (&secm_priv->eddsa_priv,
                            &dka,
                            &secm_sig->eddsa_signature);

}


enum GNUNET_GenericReturnValue
TALER_exchange_secmod_rsa_verify (
  const struct GNUNET_HashCode *h_denom_pub,
  const char *section_name,
  struct GNUNET_TIME_Absolute start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_DenominationKeyAnnouncementPS dka = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_DENOMINATION_KEY),
    .purpose.size = htonl (sizeof (dka)),
    .h_denom_pub = *h_denom_pub,
    .anchor_time = GNUNET_TIME_absolute_hton (start_sign),
    .duration_withdraw = GNUNET_TIME_relative_hton (duration)
  };

  GNUNET_CRYPTO_hash (section_name,
                      strlen (section_name) + 1,
                      &dka.h_section_name);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_SM_DENOMINATION_KEY,
                                &dka,
                                &secm_sig->eddsa_signature,
                                &secm_pub->eddsa_pub);
}


/* end of secmod_signatures.c */
