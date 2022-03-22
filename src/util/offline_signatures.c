/*
  This file is part of TALER
  Copyright (C) 2020-2022 Taler Systems SA

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


/**
 * @brief Signature made by the exchange offline key over the information of
 * an auditor to be added to the exchange's set of auditors.
 */
struct TALER_MasterAddAuditorPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_ADD_AUDITOR.   Signed
   * by a `struct TALER_MasterPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time of the change.
   */
  struct GNUNET_TIME_TimestampNBO start_date;

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

  /**
   * Hash over the auditor's URL.
   */
  struct GNUNET_HashCode h_auditor_url GNUNET_PACKED;
};


void
TALER_exchange_offline_auditor_add_sign (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  struct GNUNET_TIME_Timestamp start_date,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddAuditorPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_ADD_AUDITOR),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_timestamp_hton (start_date),
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
  struct GNUNET_TIME_Timestamp start_date,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddAuditorPS aa = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_ADD_AUDITOR),
    .purpose.size = htonl (sizeof (aa)),
    .start_date = GNUNET_TIME_timestamp_hton (start_date),
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


/**
 * @brief Signature made by the exchange offline key over the information of
 * an auditor to be removed from the exchange's set of auditors.
 */
struct TALER_MasterDelAuditorPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_DEL_AUDITOR.   Signed
   * by a `struct TALER_MasterPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time of the change.
   */
  struct GNUNET_TIME_TimestampNBO end_date;

  /**
   * Public key of the auditor.
   */
  struct TALER_AuditorPublicKeyP auditor_pub;

};


void
TALER_exchange_offline_auditor_del_sign (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp end_date,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelAuditorPS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DEL_AUDITOR),
    .purpose.size = htonl (sizeof (kv)),
    .end_date = GNUNET_TIME_timestamp_hton (end_date),
    .auditor_pub = *auditor_pub,
  };

  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_auditor_del_verify (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp end_date,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelAuditorPS da = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DEL_AUDITOR),
    .purpose.size = htonl (sizeof (da)),
    .end_date = GNUNET_TIME_timestamp_hton (end_date),
    .auditor_pub = *auditor_pub
  };

  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DEL_AUDITOR,
                                     &da,
                                     &master_sig->eddsa_signature,
                                     &master_pub->eddsa_pub);
}


/**
 * @brief Message confirming that a denomination key was revoked.
 */
struct TALER_MasterDenominationKeyRevocationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the denomination key.
   */
  struct TALER_DenominationHashP h_denom_pub;

};


void
TALER_exchange_offline_denomination_revoke_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
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
  const struct TALER_DenominationHashP *h_denom_pub,
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


/**
 * @brief Message confirming that an exchange online signing key was revoked.
 */
struct TALER_MasterSigningKeyRevocationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_MASTER_SIGNING_KEY_REVOKED.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * The exchange's public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

};


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
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Timestamp end_sign,
  struct GNUNET_TIME_Timestamp end_legal,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_ExchangeSigningKeyValidityPS skv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (skv)),
    .start = GNUNET_TIME_timestamp_hton (start_sign),
    .expire = GNUNET_TIME_timestamp_hton (end_sign),
    .end = GNUNET_TIME_timestamp_hton (end_legal),
    .signkey_pub = *exchange_pub
  };

  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &skv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_signkey_validity_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Timestamp end_sign,
  struct GNUNET_TIME_Timestamp end_legal,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_ExchangeSigningKeyValidityPS skv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (skv)),
    .start = GNUNET_TIME_timestamp_hton (start_sign),
    .expire = GNUNET_TIME_timestamp_hton (end_sign),
    .end = GNUNET_TIME_timestamp_hton (end_legal),
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
  const struct TALER_DenominationHashP *h_denom_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_DenomFeeSet *fees,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_DenominationKeyValidityPS issue = {
    .purpose.purpose
      = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY),
    .purpose.size
      = htonl (sizeof (issue)),
    .start = GNUNET_TIME_timestamp_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_timestamp_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_timestamp_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_timestamp_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub
  };

  GNUNET_CRYPTO_eddsa_key_get_public (&master_priv->eddsa_priv,
                                      &issue.master.eddsa_pub);
  TALER_amount_hton (&issue.value,
                     coin_value);
  TALER_denom_fee_set_hton (&issue.fees,
                            fees);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &issue,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_denom_validity_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_DenomFeeSet *fees,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_DenominationKeyValidityPS dkv = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY),
    .purpose.size = htonl (sizeof (dkv)),
    .master = *master_pub,
    .start = GNUNET_TIME_timestamp_hton (stamp_start),
    .expire_withdraw = GNUNET_TIME_timestamp_hton (stamp_expire_withdraw),
    .expire_deposit = GNUNET_TIME_timestamp_hton (stamp_expire_deposit),
    .expire_legal = GNUNET_TIME_timestamp_hton (stamp_expire_legal),
    .denom_hash = *h_denom_pub
  };

  TALER_amount_hton (&dkv.value,
                     coin_value);
  TALER_denom_fee_set_hton (&dkv.fees,
                            fees);
  return
    GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
    &dkv,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


/**
 * @brief Signature made by the exchange offline key over the information of
 * a payto:// URI to be added to the exchange's set of active wire accounts.
 */
struct TALER_MasterAddWirePS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_ADD_WIRE.   Signed
   * by a `struct TALER_MasterPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time of the change.
   */
  struct GNUNET_TIME_TimestampNBO start_date;

  /**
   * Hash over the exchange's payto URI.
   */
  struct TALER_PaytoHashP h_payto GNUNET_PACKED;
};


void
TALER_exchange_offline_wire_add_sign (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddWirePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_ADD_WIRE),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_timestamp_hton (now),
  };

  TALER_payto_hash (payto_uri,
                    &kv.h_payto);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_add_verify (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp sign_time,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterAddWirePS aw = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_ADD_WIRE),
    .purpose.size = htonl (sizeof (aw)),
    .start_date = GNUNET_TIME_timestamp_hton (sign_time),
  };

  TALER_payto_hash (payto_uri,
                    &aw.h_payto);
  return
    GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_ADD_WIRE,
    &aw,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


/**
 * @brief Signature made by the exchange offline key over the information of
 * a  wire method to be removed to the exchange's set of active accounts.
 */
struct TALER_MasterDelWirePS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_DEL_WIRE.   Signed
   * by a `struct TALER_MasterPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time of the change.
   */
  struct GNUNET_TIME_TimestampNBO end_date;

  /**
   * Hash over the exchange's payto URI.
   */
  struct TALER_PaytoHashP h_payto GNUNET_PACKED;

};


void
TALER_exchange_offline_wire_del_sign (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelWirePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DEL_WIRE),
    .purpose.size = htonl (sizeof (kv)),
    .end_date = GNUNET_TIME_timestamp_hton (now),
  };

  TALER_payto_hash (payto_uri,
                    &kv.h_payto);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_del_verify (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp sign_time,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterDelWirePS aw = {
    .purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DEL_WIRE),
    .purpose.size = htonl (sizeof (aw)),
    .end_date = GNUNET_TIME_timestamp_hton (sign_time),
  };

  TALER_payto_hash (payto_uri,
                    &aw.h_payto);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_MASTER_DEL_WIRE,
    &aw,
    &master_sig->eddsa_signature,
    &master_pub->eddsa_pub);
}


/**
 * @brief Information signed by the exchange's master
 * key stating the wire fee to be paid per wire transfer.
 */
struct TALER_MasterWireFeePS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_WIRE_FEES.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the wire method (yes, H("x-taler-bank") or H("iban")), in lower
   * case, including 0-terminator.  Used to uniquely identify which
   * wire method these fees apply to.
   */
  struct GNUNET_HashCode h_wire_method;

  /**
   * Start date when the fee goes into effect.
   */
  struct GNUNET_TIME_TimestampNBO start_date;

  /**
   * End date when the fee stops being in effect (exclusive)
   */
  struct GNUNET_TIME_TimestampNBO end_date;

  /**
   * Fees charged for wire transfers using the
   * given wire method.
   */
  struct TALER_WireFeeSetNBOP fees;

};


void
TALER_exchange_offline_wire_fee_sign (
  const char *payment_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_WireFeeSet *fees,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterWireFeePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_timestamp_hton (start_time),
    .end_date = GNUNET_TIME_timestamp_hton (end_time),
  };

  GNUNET_CRYPTO_hash (payment_method,
                      strlen (payment_method) + 1,
                      &kv.h_wire_method);
  TALER_wire_fee_set_hton (&kv.fees,
                           fees);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_fee_verify (
  const char *payment_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_WireFeeSet *fees,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterWireFeePS wf = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES),
    .purpose.size = htonl (sizeof (wf)),
    .start_date = GNUNET_TIME_timestamp_hton (start_time),
    .end_date = GNUNET_TIME_timestamp_hton (end_time)
  };

  GNUNET_CRYPTO_hash (payment_method,
                      strlen (payment_method) + 1,
                      &wf.h_wire_method);
  TALER_wire_fee_set_hton (&wf.fees,
                           fees);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_FEES,
                                &wf,
                                &master_sig->eddsa_signature,
                                &master_pub->eddsa_pub);
}


/**
 * Global fees charged by the exchange independent of
 * denomination or wire method.
 */
struct TALER_MasterGlobalFeePS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_GLOBAL_FEES.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Start date when the fee goes into effect.
   */
  struct GNUNET_TIME_TimestampNBO start_date;

  /**
   * End date when the fee stops being in effect (exclusive)
   */
  struct GNUNET_TIME_TimestampNBO end_date;

  /**
   * How long does an exchange keep a purse around after a purse
   * has expired (or been successfully merged)?  A 'GET' request
   * for a purse will succeed until the purse expiration time
   * plus this value.
   */
  struct GNUNET_TIME_RelativeNBO purse_timeout;

  /**
   * How long does the exchange promise to keep funds
   * an account for which the KYC has never happened
   * after a purse was merged into an account? Basically,
   * after this time funds in an account without KYC are
   * forfeit.
   */
  struct GNUNET_TIME_RelativeNBO kyc_timeout;

  /**
   * How long will the exchange preserve the account history?  After an
   * account was deleted/closed, the exchange will retain the account history
   * for legal reasons until this time.
   */
  struct GNUNET_TIME_RelativeNBO history_expiration;

  /**
   * Fee charged to the merchant per wire transfer.
   */
  struct TALER_GlobalFeeSetNBOP fees;

  /**
   * Number of concurrent purses that any
   * account holder is allowed to create without having
   * to pay the @e purse_fee. Here given in NBO.
   */
  uint32_t purse_account_limit;


};


void
TALER_exchange_offline_global_fee_sign (
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative kyc_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  uint32_t purse_account_limit,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterGlobalFeePS kv = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_GLOBAL_FEES),
    .purpose.size = htonl (sizeof (kv)),
    .start_date = GNUNET_TIME_timestamp_hton (start_time),
    .end_date = GNUNET_TIME_timestamp_hton (end_time),
    .purse_timeout = GNUNET_TIME_relative_hton (purse_timeout),
    .kyc_timeout = GNUNET_TIME_relative_hton (kyc_timeout),
    .history_expiration = GNUNET_TIME_relative_hton (history_expiration),
    .purse_account_limit = htonl (purse_account_limit)
  };

  TALER_global_fee_set_hton (&kv.fees,
                             fees);
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &kv,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_global_fee_verify (
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_GlobalFeeSet *fees,
  struct GNUNET_TIME_Relative purse_timeout,
  struct GNUNET_TIME_Relative kyc_timeout,
  struct GNUNET_TIME_Relative history_expiration,
  uint32_t purse_account_limit,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterGlobalFeePS wf = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_GLOBAL_FEES),
    .purpose.size = htonl (sizeof (wf)),
    .start_date = GNUNET_TIME_timestamp_hton (start_time),
    .end_date = GNUNET_TIME_timestamp_hton (end_time),
    .purse_timeout = GNUNET_TIME_relative_hton (purse_timeout),
    .kyc_timeout = GNUNET_TIME_relative_hton (kyc_timeout),
    .history_expiration = GNUNET_TIME_relative_hton (history_expiration),
    .purse_account_limit = htonl (purse_account_limit)
  };

  TALER_global_fee_set_hton (&wf.fees,
                             fees);
  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_GLOBAL_FEES,
                                &wf,
                                &master_sig->eddsa_signature,
                                &master_pub->eddsa_pub);
}


/**
 * @brief Signature made by the exchange offline key over the
 * configuration of an extension.
 */
struct TALER_MasterExtensionConfigurationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_MASTER_EXTENSION.   Signed
   * by a `struct TALER_MasterPublicKeyP` using EdDSA.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the JSON object that represents the configuration of an extension.
   */
  struct TALER_ExtensionConfigHashP h_config GNUNET_PACKED;
};


void
TALER_exchange_offline_extension_config_hash_sign (
  const struct TALER_ExtensionConfigHashP *h_config,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig)
{
  struct TALER_MasterExtensionConfigurationPS ec = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_EXTENSION),
    .purpose.size = htonl (sizeof(ec)),
    .h_config = *h_config
  };
  GNUNET_CRYPTO_eddsa_sign (&master_priv->eddsa_priv,
                            &ec,
                            &master_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_exchange_offline_extension_config_hash_verify (
  const struct TALER_ExtensionConfigHashP *h_config,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig
  )
{
  struct TALER_MasterExtensionConfigurationPS ec = {
    .purpose.purpose = htonl (TALER_SIGNATURE_MASTER_EXTENSION),
    .purpose.size = htonl (sizeof(ec)),
    .h_config = *h_config
  };

  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_EXTENSION,
                                     &ec,
                                     &master_sig->eddsa_signature,
                                     &master_pub->eddsa_pub);
}


/**
 * @brief Information signed by the exchange's master
 * key affirming the IBAN details for the exchange.
 */
struct TALER_MasterWireDetailsPS
{

  /**
   * Purpose is #TALER_SIGNATURE_MASTER_WIRE_DETAILS.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the account holder's payto:// URL.
   */
  struct TALER_PaytoHashP h_wire_details GNUNET_PACKED;

};


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


/* end of offline_signatures.c */
