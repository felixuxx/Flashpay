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
 * @file offline_signatures.c
 * @brief Utility functions for Taler exchange offline signatures
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


void
TALER_exchange_offline_auditor_add_sign (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  struct GNUNET_TIME_Absolute start_date,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddAuditorPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_ADD_AUDITOR),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_absolute_hton (start_date),
    .auditor_pub = *auditor_pub,
  };

  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &kv.h_auditor_url);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_auditor_add_verify (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  struct GNUNET_TIME_Absolute start_date,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddAuditorPS aa = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_ADD_AUDITOR),
    .purpose.size = htonl (sizeof (aa)),
    .start_date = GNUNET_TIME_absolute_hton (start_date),
    .auditor_pub = *auditor_pub
  };

  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &aa.h_auditor_url);
  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_ADD_AUDITOR,
                                     &aa,
                                     &master_sig->eddsa_signature,
                                     &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_auditor_del_sign (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Absolute end_date,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelAuditorPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DEL_AUDITOR),
    .purpose.size = htonl (sizeof (kv)),
    .end_date = GNUNET_TIME_absolute_hton (end_date),
    .auditor_pub = *auditor_pub,
  };

  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_auditor_del_verify (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Absolute end_date,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelAuditorPS da = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DEL_AUDITOR),
    .purpose.size = htonl (sizeof (da)),
    .end_date = GNUNET_TIME_absolute_hton (end_date),
    .auditor_pub = *auditor_pub
  };

  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DEL_AUDITOR,
                                     &da,
                                     &master_sig->eddsa_signature,
                                     &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_denomination_revoke_sign (
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDenominationKeyRevocationPS rm = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED),
    .purpose.size = htonl (sizeof (rm)),
    .h_denom_pub = *h_denom_pub
  };

  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &rm,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_denomination_revoke_verify (
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDenominationKeyRevocationPS kr = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED),
    .purpose.size = htonl (sizeof (kr)),
    .h_denom_pub = *h_denom_pub
  };

  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED,
    &kr,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_signkey_revoke_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterSigningKeyRevocationPS kv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_SIGNING_KEY_REVOKED),
    .purpose.size = htonl (sizeof (kv)),
    .exchange_pub = *exchange_pub
  };

  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_signkey_revoke_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterSigningKeyRevocationPS rm = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_SIGNING_KEY_REVOKED),
    .purpose.size = htonl (sizeof (rm)),
    .exchange_pub = *exchange_pub
  };

  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_SIGNING_KEY_REVOKED,
    &rm,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_signkey_validity_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Absolute start_sign,
  struct GNUNET_TIME_Absolute end_sign,
  struct GNUNET_TIME_Absolute end_legal,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_ExchangeSigningKeyValidityPS skv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (skv)),
    .start = GNUNET_TIME_absolute_hton (start_sign),
    .expire = GNUNET_TIME_absolute_hton (end_sign),
    .end = GNUNET_TIME_absolute_hton (end_legal),
    .signkey_pub = *exchange_pub
  };

  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv->eddsa_priv,
                                      &skv.master_public_key.eddsa_pub);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &skv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_signkey_validity_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Absolute start_sign,
  struct GNUNET_TIME_Absolute end_sign,
  struct GNUNET_TIME_Absolute end_legal,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_ExchangeSigningKeyValidityPS skv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (skv)),
    .master_public_key = *master_pub,
    .start = GNUNET_TIME_absolute_hton (start_sign),
    .expire = GNUNET_TIME_absolute_hton (end_sign),
    .end = GNUNET_TIME_absolute_hton (end_legal),
    .signkey_pub = *exchange_pub
  };

  return
    GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
    &skv,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_denom_validity_sign (
  const struct GNUNET_HashCode *h_denom_pub,
  struct GNUNET_TIME_Absolute stamp_start,
  struct GNUNET_TIME_Absolute stamp_expire_withdraw,
  struct GNUNET_TIME_Absolute stamp_expire_deposit,
  struct GNUNET_TIME_Absolute stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_DenominationKeyValidityPS issue = {
    .purpose.purpose
      = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY),
    .purpose.size
      = htonl (sizeof (issue)),
    .start = GNUNET_TIME_absolute_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_absolute_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_absolute_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_absolute_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub
  };

  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv->eddsa_priv,
                                      &issue.master.eddsa_pub);
  TALER_amount_hton (&issue.value,
                     coin_value);
  TALER_amount_hton (&issue.fee_withdraw,
                     fee_withdraw);
  TALER_amount_hton (&issue.fee_deposit,
                     fee_deposit);
  TALER_amount_hton (&issue.fee_refresh,
                     fee_refresh);
  TALER_amount_hton (&issue.fee_refund,
                     fee_refund);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &issue,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_denom_validity_verify (
  const struct GNUNET_HashCode *h_denom_pub,
  struct GNUNET_TIME_Absolute stamp_start,
  struct GNUNET_TIME_Absolute stamp_expire_withdraw,
  struct GNUNET_TIME_Absolute stamp_expire_deposit,
  struct GNUNET_TIME_Absolute stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_DenominationKeyValidityPS dkv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (dkv)),
    .master = *master_pub,
    .start = GNUNET_TIME_absolute_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_absolute_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_absolute_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_absolute_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub
  };

  TALER_amount_hton (&dkv.value,
                     coin_value);
  TALER_amount_hton (&dkv.fee_withdraw,
                     fee_withdraw);
  TALER_amount_hton (&dkv.fee_deposit,
                     fee_deposit);
  TALER_amount_hton (&dkv.fee_refresh,
                     fee_refresh);
  TALER_amount_hton (&dkv.fee_refund,
                     fee_refund);
  return
    GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
    &dkv,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_wire_add_sign (
  const char *payto_uri,
  struct GNUNET_TIME_Absolute now,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddWirePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_ADD_WIRE),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_absolute_hton (now),
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_abs (&now));
  TALER_exchange_wire_signature_hash (payto_uri,
                                      &kv.h_wire);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_add_verify (
  const char *payto_uri,
  struct GNUNET_TIME_Absolute sign_time,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddWirePS aw = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_ADD_WIRE),
    .purpose.size = htonl (sizeof (aw)),
    .start_date = GNUNET_TIME_absolute_hton (sign_time),
  };

  TALER_exchange_wire_signature_hash (payto_uri,
                                      &aw.h_wire);
  return
    GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_ADD_WIRE,
    &aw,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_wire_del_sign (
  const char *payto_uri,
  struct GNUNET_TIME_Absolute now,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelWirePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DEL_WIRE),
    .purpose.size = htonl (sizeof (kv)),
    .end_date = GNUNET_TIME_absolute_hton (now),
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_abs (&now));
  TALER_exchange_wire_signature_hash (payto_uri,
                                      &kv.h_wire);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_del_verify (
  const char *payto_uri,
  struct GNUNET_TIME_Absolute sign_time,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelWirePS aw = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DEL_WIRE),
    .purpose.size = htonl (sizeof (aw)),
    .end_date = GNUNET_TIME_absolute_hton (sign_time),
  };

  TALER_exchange_wire_signature_hash (payto_uri,
                                      &aw.h_wire);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_DEL_WIRE,
    &aw,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


void
TALER_exchange_offline_wire_fee_sign (
  const char *payment_method,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Absolute end_time,
  const struct TALER_Amount *wire_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterWireFeePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_absolute_hton (start_time),
    .end_date = GNUNET_TIME_absolute_hton (end_time),
  };

  GNUNET_CRYPTO_hash (payment_method,
                      strlen (payment_method) + 1,
                      &kv.h_wire_method);
  TALER_amount_hton (&kv.wire_fee,
                     wire_fee);
  TALER_amount_hton (&kv.closing_fee,
                     closing_fee);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_fee_verify (
  const char *payment_method,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Absolute end_time,
  const struct TALER_Amount *wire_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterWireFeePS wf = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES),
    .purpose.size = htonl (sizeof (wf)),
    .start_date = GNUNET_TIME_absolute_hton (start_time),
    .end_date = GNUNET_TIME_absolute_hton (end_time)
  };

  GNUNET_CRYPTO_hash (payment_method,
                      strlen (payment_method) + 1,
                      &wf.h_wire_method);
  TALER_amount_hton (&wf.wire_fee,
                     wire_fee);
  TALER_amount_hton (&wf.closing_fee,
                     closing_fee);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_FEES,
                                &wf,
                                &master_sig->eddsa_signature,
                                &master_pub->eddsa_pub);
}


/* end of offline_signatures.c */
