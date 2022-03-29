/*
  This file is part of TALER
  Copyright (C) 2020, 2021 Taler Systems SA

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


/**
 * @brief format used by the signing crypto helper when affirming
 *        that it created an exchange signing key.
 */
struct TALER_SigningKeyAnnouncementPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_SM_SIGNING_KEY.
   * Used with an EdDSA signature of a `struct TALER_SecurityModulePublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Public signing key of the exchange this is about.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

  /**
   * When does the key become available?
   */
  struct GNUNET_TIME_TimestampNBO anchor_time;

  /**
   * How long is the key available after @e anchor_time?
   */
  struct GNUNET_TIME_RelativeNBO duration;

};


void
TALER_exchange_secmod_eddsa_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_SigningKeyAnnouncementPS ska = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_SIGNING_KEY),
    .purpose.size = htonl (sizeof (ska)),
    .exchange_pub = *exchange_pub,
    .anchor_time = GNUNET_TIME_timestamp_hton (start_sign),
    .duration = GNUNET_TIME_relative_hton (duration)
  };

  GNUNET_CRYPTO_eddsa_sign (&secm_priv->eddsa_priv,
                            &ska,
                            &secm_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_secmod_eddsa_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_SigningKeyAnnouncementPS ska = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_SIGNING_KEY),
    .purpose.size = htonl (sizeof (ska)),
    .exchange_pub = *exchange_pub,
    .anchor_time = GNUNET_TIME_timestamp_hton (start_sign),
    .duration = GNUNET_TIME_relative_hton (duration)
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_SM_SIGNING_KEY,
                                &ska,
                                &secm_sig->eddsa_signature,
                                &secm_pub->eddsa_pub);
}


/**
 * @brief format used by the denomination crypto helper when affirming
 *        that it created a denomination key.
 */
struct TALER_DenominationKeyAnnouncementPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_SM_RSA_DENOMINATION_KEY.
   * Used with an EdDSA signature of a `struct TALER_SecurityModulePublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the denomination public key.
   */
  struct TALER_DenominationHashP h_denom;

  /**
   * Hash of the section name in the configuration of this denomination.
   */
  struct GNUNET_HashCode h_section_name;

  /**
   * When does the key become available?
   */
  struct GNUNET_TIME_TimestampNBO anchor_time;

  /**
   * How long is the key available after @e anchor_time?
   */
  struct GNUNET_TIME_RelativeNBO duration_withdraw;

};

void
TALER_exchange_secmod_rsa_sign (
  const struct TALER_RsaPubHashP *h_rsa,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_DenominationKeyAnnouncementPS dka = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_RSA_DENOMINATION_KEY),
    .purpose.size = htonl (sizeof (dka)),
    .h_denom.hash = h_rsa->hash,
    .anchor_time = GNUNET_TIME_timestamp_hton (start_sign),
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
  const struct TALER_RsaPubHashP *h_rsa,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_DenominationKeyAnnouncementPS dka = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_RSA_DENOMINATION_KEY),
    .purpose.size = htonl (sizeof (dka)),
    .h_denom.hash = h_rsa->hash,
    .anchor_time = GNUNET_TIME_timestamp_hton (start_sign),
    .duration_withdraw = GNUNET_TIME_relative_hton (duration)
  };

  GNUNET_CRYPTO_hash (section_name,
                      strlen (section_name) + 1,
                      &dka.h_section_name);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_SM_RSA_DENOMINATION_KEY,
                                &dka,
                                &secm_sig->eddsa_signature,
                                &secm_pub->eddsa_pub);
}


void
TALER_exchange_secmod_cs_sign (
  const struct TALER_CsPubHashP *h_cs,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_DenominationKeyAnnouncementPS dka = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_CS_DENOMINATION_KEY),
    .purpose.size = htonl (sizeof (dka)),
    .h_denom.hash = h_cs->hash,
    .anchor_time = GNUNET_TIME_timestamp_hton (start_sign),
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
TALER_exchange_secmod_cs_verify (
  const struct TALER_CsPubHashP *h_cs,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig)
{
  struct TALER_DenominationKeyAnnouncementPS dka = {
    .purpose.purpose = htonl (TALER_SIGNATURE_SM_CS_DENOMINATION_KEY),
    .purpose.size = htonl (sizeof (dka)),
    .h_denom.hash = h_cs->hash,
    .anchor_time = GNUNET_TIME_timestamp_hton (start_sign),
    .duration_withdraw = GNUNET_TIME_relative_hton (duration)
  };

  GNUNET_CRYPTO_hash (section_name,
                      strlen (section_name) + 1,
                      &dka.h_section_name);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_SM_CS_DENOMINATION_KEY,
                                &dka,
                                &secm_sig->eddsa_signature,
                                &secm_pub->eddsa_pub);
}


/* end of secmod_signatures.c */
