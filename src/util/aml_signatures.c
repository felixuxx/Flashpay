/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file aml_signatures.c
 * @brief Utility functions for AML officers
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used to generate the signature on an AML decision.
 */
struct TALER_AmlDecisionPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_AML_DECISION.
   * Used for an EdDSA signature with the `struct TALER_AmlOfficerPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the justification text.
   */
  struct GNUNET_HashCode h_justification GNUNET_PACKED;

  /**
   * Time when this decision was made.
   */
  struct GNUNET_TIME_TimestampNBO decision_time;

  /**
   * New threshold for triggering possibly a new AML process.
   */
  struct TALER_AmountNBO new_threshold;

  /**
   * Hash of the account identifier to which the decision applies.
   */
  struct TALER_PaytoHashP h_payto GNUNET_PACKED;

  /**
   * Hash over JSON array with KYC requirements that were imposed. All zeros
   * for none.
   */
  struct GNUNET_HashCode h_kyc_requirements;

  /**
   * What is the new AML status?
   */
  uint32_t new_state GNUNET_PACKED;

};

GNUNET_NETWORK_STRUCT_END

void
TALER_officer_aml_decision_sign (
  const char *justification,
  struct GNUNET_TIME_Timestamp decision_time,
  const struct TALER_Amount *new_threshold,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_AmlDecisionState new_state,
  const json_t *kyc_requirements,
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  struct TALER_AmlOfficerSignatureP *officer_sig)
{
  struct TALER_AmlDecisionPS ad = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AML_DECISION),
    .purpose.size = htonl (sizeof (ad)),
    .h_payto = *h_payto,
    .new_state = htonl ((uint32_t) new_state)
  };

  GNUNET_CRYPTO_hash (justification,
                      strlen (justification),
                      &ad.h_justification);
  TALER_amount_hton (&ad.new_threshold,
                     new_threshold);
  if (NULL != kyc_requirements)
    TALER_json_hash (kyc_requirements,
                     &ad.h_kyc_requirements);
  GNUNET_CRYPTO_eddsa_sign (&officer_priv->eddsa_priv,
                            &ad,
                            &officer_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_officer_aml_decision_verify (
  const char *justification,
  struct GNUNET_TIME_Timestamp decision_time,
  const struct TALER_Amount *new_threshold,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_AmlDecisionState new_state,
  const json_t *kyc_requirements,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const struct TALER_AmlOfficerSignatureP *officer_sig)
{
  struct TALER_AmlDecisionPS ad = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AML_DECISION),
    .purpose.size = htonl (sizeof (ad)),
    .h_payto = *h_payto,
    .new_state = htonl ((uint32_t) new_state)
  };

  GNUNET_CRYPTO_hash (justification,
                      strlen (justification),
                      &ad.h_justification);
  TALER_amount_hton (&ad.new_threshold,
                     new_threshold);
  if (NULL != kyc_requirements)
    TALER_json_hash (kyc_requirements,
                     &ad.h_kyc_requirements);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_AML_DECISION,
    &ad,
    &officer_sig->eddsa_signature,
    &officer_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used to generate the signature on any AML query.
 */
struct TALER_AmlQueryPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_AML_QUERY.
   * Used for an EdDSA signature with the `struct TALER_AmlOfficerPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

};

GNUNET_NETWORK_STRUCT_END


void
TALER_officer_aml_query_sign (
  const struct TALER_AmlOfficerPrivateKeyP *officer_priv,
  struct TALER_AmlOfficerSignatureP *officer_sig)
{
  struct TALER_AmlQueryPS aq = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AML_QUERY),
    .purpose.size = htonl (sizeof (aq))
  };

  GNUNET_CRYPTO_eddsa_sign (&officer_priv->eddsa_priv,
                            &aq,
                            &officer_sig->eddsa_signature);
}


/**
 * Verify AML query authorization.
 *
 * @param officer_pub public key of AML officer
 * @param officer_sig signature to verify
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_officer_aml_query_verify (
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const struct TALER_AmlOfficerSignatureP *officer_sig)
{
  struct TALER_AmlQueryPS aq = {
    .purpose.purpose = htonl (TALER_SIGNATURE_AML_QUERY),
    .purpose.size = htonl (sizeof (aq))
  };

  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_AML_QUERY,
    &aq,
    &officer_sig->eddsa_signature,
    &officer_pub->eddsa_pub);
}


/* end of aml_signatures.c */
