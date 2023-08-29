/*
  This file is part of TALER
  Copyright (C) 2021-2023 Taler Systems SA

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
 * @file wallet_signatures.c
 * @brief Utility functions for Taler wallet signatures
 * @author Christian Grothoff
 * @author Özgür Kesim
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include <gnunet/gnunet_common.h>


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used to generate the signature on a request to deposit
 * a coin into the account of a merchant.
 */
struct TALER_DepositRequestPS
{
  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_COIN_DEPOSIT.
   * Used for an EdDSA signature with the `struct TALER_CoinSpendPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the contract for which this deposit is made.
   */
  struct TALER_PrivateContractHashP h_contract_terms GNUNET_PACKED;

  /**
   * Hash over the age commitment that went into the coin. Maybe all zero, if
   * age commitment isn't applicable to the denomination.
   */
  struct TALER_AgeCommitmentHash h_age_commitment GNUNET_PACKED;

  /**
   * Hash over optional policy extension attributes shared with the exchange.
   */
  struct TALER_ExtensionPolicyHashP h_policy GNUNET_PACKED;

  /**
   * Hash over the wiring information of the merchant.
   */
  struct TALER_MerchantWireHashP h_wire GNUNET_PACKED;

  /**
   * Hash over the denomination public key used to sign the coin.
   */
  struct TALER_DenominationHashP h_denom_pub GNUNET_PACKED;

  /**
   * Time when this request was generated.  Used, for example, to
   * assess when (roughly) the income was achieved for tax purposes.
   * Note that the Exchange will only check that the timestamp is not "too
   * far" into the future (i.e. several days).  The fact that the
   * timestamp falls within the validity period of the coin's
   * denomination key is irrelevant for the validity of the deposit
   * request, as obviously the customer and merchant could conspire to
   * set any timestamp.  Also, the Exchange must accept very old deposit
   * requests, as the merchant might have been unable to transmit the
   * deposit request in a timely fashion (so back-dating is not
   * prevented).
   */
  struct GNUNET_TIME_TimestampNBO wallet_timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_TimestampNBO refund_deadline;

  /**
   * Amount to be deposited, including deposit fee charged by the
   * exchange.  This is the total amount that the coin's value at the exchange
   * will be reduced by.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Depositing fee charged by the exchange.  This must match the Exchange's
   * denomination key's depositing fee.  If the client puts in an
   * invalid deposit fee (too high or too low) that does not match the
   * Exchange's denomination key, the deposit operation is invalid and
   * will be rejected by the exchange.  The @e amount_with_fee minus the
   * @e deposit_fee is the amount that will be transferred to the
   * account identified by @e h_wire.
   */
  struct TALER_AmountNBO deposit_fee;

  /**
   * The Merchant's public key.  Allows the merchant to later refund
   * the transaction or to inquire about the wire transfer identifier.
   */
  struct TALER_MerchantPublicKeyP merchant;

  /**
   * Hash over a JSON containing data provided by the
   * wallet to complete the contract upon payment.
   */
  struct GNUNET_HashCode wallet_data_hash;

};

GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_deposit_sign (
  const struct TALER_Amount *amount,
  const struct TALER_Amount *deposit_fee,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_ExtensionPolicyHashP *h_policy,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct GNUNET_TIME_Timestamp wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_DepositRequestPS dr = {
    .purpose.size = htonl (sizeof (dr)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .h_denom_pub = *h_denom_pub,
    .wallet_timestamp = GNUNET_TIME_timestamp_hton (wallet_timestamp),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .merchant = *merchant_pub
  };

  if (NULL != h_age_commitment)
    dr.h_age_commitment = *h_age_commitment;
  if (NULL != h_policy)
    dr.h_policy = *h_policy;
  TALER_amount_hton (&dr.amount_with_fee,
                     amount);
  TALER_amount_hton (&dr.deposit_fee,
                     deposit_fee);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &dr,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_deposit_verify (
  const struct TALER_Amount *amount,
  const struct TALER_Amount *deposit_fee,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_ExtensionPolicyHashP *h_policy,
  const struct TALER_DenominationHashP *h_denom_pub,
  struct GNUNET_TIME_Timestamp wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_DepositRequestPS dr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT),
    .purpose.size = htonl (sizeof (dr)),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .h_denom_pub = *h_denom_pub,
    .wallet_timestamp = GNUNET_TIME_timestamp_hton (wallet_timestamp),
    .refund_deadline = GNUNET_TIME_timestamp_hton (refund_deadline),
    .merchant = *merchant_pub,
    .h_age_commitment = {{{0}}},
    .h_policy = {{{0}}}
  };

  if (NULL != h_age_commitment)
    dr.h_age_commitment = *h_age_commitment;
  if (NULL != h_policy)
    dr.h_policy = *h_policy;
  TALER_amount_hton (&dr.amount_with_fee,
                     amount);
  TALER_amount_hton (&dr.deposit_fee,
                     deposit_fee);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used for to allow the wallet to authenticate
 * link data provided by the exchange.
 */
struct TALER_LinkDataPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_COIN_LINK.
   * Used with an EdDSA signature of a `struct TALER_CoinPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the denomination public key of the new coin.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Transfer public key (for which the private key was not revealed)
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Hash of the age commitment, if applicable.  Can be all zero
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Hash of the blinded new coin.
   */
  struct TALER_BlindedCoinHashP coin_envelope_hash;
};

GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_link_sign (const struct TALER_DenominationHashP *h_denom_pub,
                        const struct TALER_TransferPublicKeyP *transfer_pub,
                        const struct TALER_BlindedCoinHashP *bch,
                        const struct TALER_CoinSpendPrivateKeyP *old_coin_priv,
                        struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_LinkDataPS ldp = {
    .purpose.size = htonl (sizeof (ldp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_LINK),
    .h_denom_pub = *h_denom_pub,
    .transfer_pub = *transfer_pub,
    .coin_envelope_hash = *bch
  };

  GNUNET_CRYPTO_eddsa_sign (&old_coin_priv->eddsa_priv,
                            &ldp,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_link_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  const struct TALER_BlindedCoinHashP *h_coin_ev,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_LinkDataPS ldp = {
    .purpose.size = htonl (sizeof (ldp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_LINK),
    .h_denom_pub = *h_denom_pub,
    .transfer_pub = *transfer_pub,
    .coin_envelope_hash = *h_coin_ev,
  };

  return
    GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_LINK,
                                &ldp,
                                &coin_sig->eddsa_signature,
                                &old_coin_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Signed data to request that a coin should be refunded as part of
 * the "emergency" /recoup protocol.  The refund will go back to the bank
 * account that created the reserve.
 */
struct TALER_RecoupRequestPS
{
  /**
   * Purpose is #TALER_SIGNATURE_WALLET_COIN_RECOUP
   * or #TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash of the (revoked) denomination public key of the coin.
   */
  struct TALER_DenominationHashP h_denom_pub;

  /**
   * Blinding factor that was used to withdraw the coin.
   */
  union TALER_DenominationBlindingKeyP coin_blind;

};

GNUNET_NETWORK_STRUCT_END


enum GNUNET_GenericReturnValue
TALER_wallet_recoup_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP),
    .purpose.size = htonl (sizeof (pr)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_RECOUP,
                                     &pr,
                                     &coin_sig->eddsa_signature,
                                     &coin_pub->eddsa_pub);
}


void
TALER_wallet_recoup_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP),
    .purpose.size = htonl (sizeof (pr)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &pr,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_recoup_refresh_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH),
    .purpose.size = htonl (sizeof (pr)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  return GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH,
                                     &pr,
                                     &coin_sig->eddsa_signature,
                                     &coin_pub->eddsa_pub);
}


void
TALER_wallet_recoup_refresh_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RecoupRequestPS pr = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_RECOUP_REFRESH),
    .purpose.size = htonl (sizeof (struct TALER_RecoupRequestPS)),
    .h_denom_pub = *h_denom_pub,
    .coin_blind = *coin_bks
  };

  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &pr,
                            &coin_sig->eddsa_signature);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Message signed by a coin to indicate that the coin should be
 * melted.
 */
struct TALER_RefreshMeltCoinAffirmationPS
{
  /**
   * Purpose is #TALER_SIGNATURE_WALLET_COIN_MELT.
   * Used for an EdDSA signature with the `struct TALER_CoinSpendPublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Which melt commitment is made by the wallet.
   */
  struct TALER_RefreshCommitmentP rc GNUNET_PACKED;

  /**
   * Hash over the denomination public key used to sign the coin.
   */
  struct TALER_DenominationHashP h_denom_pub GNUNET_PACKED;

  /**
   * If age commitment was provided during the withdrawal of the coin, this is
   * the hash of the age commitment vector.  It must be all zeroes if no age
   * commitment was provided.
   */
  struct TALER_AgeCommitmentHash h_age_commitment GNUNET_PACKED;

  /**
   * How much of the value of the coin should be melted?  This amount
   * includes the fees, so the final amount contributed to the melt is
   * this value minus the fee for melting the coin.  We include the
   * fee in what is being signed so that we can verify a reserve's
   * remaining total balance without needing to access the respective
   * denomination key information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Melting fee charged by the exchange.  This must match the Exchange's
   * denomination key's melting fee.  If the client puts in an invalid
   * melting fee (too high or too low) that does not match the Exchange's
   * denomination key, the melting operation is invalid and will be
   * rejected by the exchange.  The @e amount_with_fee minus the @e
   * melt_fee is the amount that will be credited to the melting
   * session.
   */
  struct TALER_AmountNBO melt_fee;
};

GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_melt_sign (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RefreshMeltCoinAffirmationPS melt = {
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT),
    .purpose.size = htonl (sizeof (melt)),
    .rc = *rc,
    .h_denom_pub = *h_denom_pub,
    .h_age_commitment = {{{0}}},
  };

  if (NULL != h_age_commitment)
    melt.h_age_commitment = *h_age_commitment;


  TALER_amount_hton (&melt.amount_with_fee,
                     amount_with_fee);
  TALER_amount_hton (&melt.melt_fee,
                     melt_fee);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &melt,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_melt_verify (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_RefreshMeltCoinAffirmationPS melt = {
    .purpose.size = htonl (sizeof (melt)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT),
    .rc = *rc,
    .h_denom_pub = *h_denom_pub,
    .h_age_commitment = {{{0}}},
  };

  if (NULL != h_age_commitment)
    melt.h_age_commitment = *h_age_commitment;

  TALER_amount_hton (&melt.amount_with_fee,
                     amount_with_fee);
  TALER_amount_hton (&melt.melt_fee,
                     melt_fee);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_COIN_MELT,
    &melt,
    &coin_sig->eddsa_signature,
    &coin_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN


/**
 * @brief Format used for to generate the signature on a request to withdraw
 * coins from a reserve.
 */
struct TALER_WithdrawRequestPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW.
   * Used with an EdDSA signature of a `struct TALER_ReservePublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Value of the coin being exchanged (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Hash of the denomination public key for the coin that is withdrawn.
   */
  struct TALER_DenominationHashP h_denomination_pub GNUNET_PACKED;

  /**
   * Hash of the (blinded) message to be signed by the Exchange.
   */
  struct TALER_BlindedCoinHashP h_coin_envelope GNUNET_PACKED;
};


GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_withdraw_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_BlindedCoinHashP *bch,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_WithdrawRequestPS req = {
    .purpose.size = htonl (sizeof (req)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW),
    .h_denomination_pub = *h_denom_pub,
    .h_coin_envelope = *bch
  };

  TALER_amount_hton (&req.amount_with_fee,
                     amount_with_fee);
  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &req,
                            &reserve_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_withdraw_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_BlindedCoinHashP *bch,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_WithdrawRequestPS wsrd = {
    .purpose.size = htonl (sizeof (wsrd)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW),
    .h_denomination_pub = *h_denom_pub,
    .h_coin_envelope = *bch
  };

  TALER_amount_hton (&wsrd.amount_with_fee,
                     amount_with_fee);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
    &wsrd,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Format used for to generate the signature on a request to
 * age-withdraw from a reserve.
 */
struct TALER_AgeWithdrawRequestPS
{

  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW.
   * Used with an EdDSA signature of a `struct TALER_ReservePublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * The reserve's public key
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Value of the coin being exchanged (matching the denomination key)
   * plus the transaction fee.  We include this in what is being
   * signed so that we can verify a reserve's remaining total balance
   * without needing to access the respective denomination key
   * information each time.
   */
  struct TALER_AmountNBO amount_with_fee;

  /**
   * Running SHA512 hash of the commitment of n*kappa coins
   */
  struct TALER_AgeWithdrawCommitmentHashP h_commitment;

  /**
   * The mask that defines the age groups.  MUST be the same for all denominations.
   */
  struct TALER_AgeMask mask;

  /**
   * Maximum age group that the coins are going to be restricted to.
   */
  uint8_t max_age_group;
};


GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_age_withdraw_sign (
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_AgeMask *mask,
  uint8_t max_age,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_AgeWithdrawRequestPS req = {
    .purpose.size = htonl (sizeof (req)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_AGE_WITHDRAW),
    .h_commitment = *h_commitment,
    .mask = *mask,
    .max_age_group = TALER_get_age_group (mask, max_age)
  };

  GNUNET_CRYPTO_eddsa_key_get_public (&reserve_priv->eddsa_priv,
                                      &req.reserve_pub.eddsa_pub);
  TALER_amount_hton (&req.amount_with_fee,
                     amount_with_fee);
  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &req,
                            &reserve_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_age_withdraw_verify (
  const struct TALER_AgeWithdrawCommitmentHashP *h_commitment,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_AgeMask *mask,
  uint8_t max_age,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_AgeWithdrawRequestPS awsrd = {
    .purpose.size = htonl (sizeof (awsrd)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_AGE_WITHDRAW),
    .reserve_pub = *reserve_pub,
    .h_commitment = *h_commitment,
    .mask = *mask,
    .max_age_group = TALER_get_age_group (mask, max_age)
  };

  TALER_amount_hton (&awsrd.amount_with_fee,
                     amount_with_fee);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_RESERVE_AGE_WITHDRAW,
    &awsrd,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN


/**
 * @brief Format used for to generate the signature on a request to withdraw
 * coins from a reserve.
 */
struct TALER_AccountSetupRequestSignaturePS
{

  /**
   * Purpose must be #TALER_SIGNATURE_WALLET_ACCOUNT_SETUP.
   * Used with an EdDSA signature of a `struct TALER_ReservePublicKeyP`.
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Balance threshold the wallet is about to cross.
   */
  struct TALER_AmountNBO threshold;

};


GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_account_setup_sign (
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_Amount *balance_threshold,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_AccountSetupRequestSignaturePS asap = {
    .purpose.size = htonl (sizeof (asap)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_SETUP)
  };

  TALER_amount_hton (&asap.threshold,
                     balance_threshold);
  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &asap,
                            &reserve_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_account_setup_verify (
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *balance_threshold,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_AccountSetupRequestSignaturePS asap = {
    .purpose.size = htonl (sizeof (asap)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_SETUP)
  };

  TALER_amount_hton (&asap.threshold,
                     balance_threshold);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_ACCOUNT_SETUP,
    &asap,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN


/**
 * Response by which a wallet requests a full
 * reserve history and indicates it is willing
 * to pay for it.
 */
struct TALER_ReserveHistoryRequestPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_RESERVE_HISTORY
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the wallet make the request.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

  /**
   * How much does the exchange charge for the history?
   */
  struct TALER_AmountNBO history_fee;

};


GNUNET_NETWORK_STRUCT_END


enum GNUNET_GenericReturnValue
TALER_wallet_reserve_history_verify (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_Amount *history_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveHistoryRequestPS rhr = {
    .purpose.size = htonl (sizeof (rhr)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_HISTORY),
    .request_timestamp = GNUNET_TIME_timestamp_hton (ts)
  };

  TALER_amount_hton (&rhr.history_fee,
                     history_fee);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_RESERVE_HISTORY,
    &rhr,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


void
TALER_wallet_reserve_history_sign (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_Amount *history_fee,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveHistoryRequestPS rhr = {
    .purpose.size = htonl (sizeof (rhr)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_HISTORY),
    .request_timestamp = GNUNET_TIME_timestamp_hton (ts)
  };

  TALER_amount_hton (&rhr.history_fee,
                     history_fee);
  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &rhr,
                            &reserve_sig->eddsa_signature);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Response by which a wallet requests an account status.
 */
struct TALER_ReserveStatusRequestPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_RESERVE_STATUS
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When did the wallet make the request.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

};

GNUNET_NETWORK_STRUCT_END

enum GNUNET_GenericReturnValue
TALER_wallet_reserve_status_verify (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveStatusRequestPS rsr = {
    .purpose.size = htonl (sizeof (rsr)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_STATUS),
    .request_timestamp = GNUNET_TIME_timestamp_hton (ts)
  };

  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_RESERVE_STATUS,
    &rsr,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


void
TALER_wallet_reserve_status_sign (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveStatusRequestPS rsr = {
    .purpose.size = htonl (sizeof (rsr)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_STATUS),
    .request_timestamp = GNUNET_TIME_timestamp_hton (ts)
  };

  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &rsr,
                            &reserve_sig->eddsa_signature);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed to create a purse (without reserve).
 */
struct TALER_PurseCreatePS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_PURSE_CREATE
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time when the purse will expire if still unmerged or unpaid.
   */
  struct GNUNET_TIME_TimestampNBO purse_expiration;

  /**
   * Total amount (with fees) to be put into the purse.
   */
  struct TALER_AmountNBO purse_amount;

  /**
   * Contract this purse pays for.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Public key identifying the merge capability.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Minimum age required for payments into this purse.
   */
  uint32_t min_age GNUNET_PACKED;

};


GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_purse_create_sign (
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  uint32_t min_age,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct TALER_PurseCreatePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_CREATE),
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .h_contract_terms = *h_contract_terms,
    .merge_pub = *merge_pub,
    .min_age = htonl (min_age)
  };

  TALER_amount_hton (&pm.purse_amount,
                     amount);
  GNUNET_CRYPTO_eddsa_sign (&purse_priv->eddsa_priv,
                            &pm,
                            &purse_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_create_verify (
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  uint32_t min_age,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  struct TALER_PurseCreatePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_CREATE),
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .h_contract_terms = *h_contract_terms,
    .merge_pub = *merge_pub,
    .min_age = htonl (min_age)
  };

  TALER_amount_hton (&pm.purse_amount,
                     amount);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_PURSE_CREATE,
    &pm,
    &purse_sig->eddsa_signature,
    &purse_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed to delete a purse.
 */
struct TALER_PurseDeletePS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_PURSE_DELETE
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

};


GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_purse_delete_sign (
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct TALER_PurseDeletePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_DELETE)
  };

  GNUNET_CRYPTO_eddsa_sign (&purse_priv->eddsa_priv,
                            &pm,
                            &purse_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_delete_verify (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  struct TALER_PurseDeletePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_DELETE)
  };

  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_PURSE_DELETE,
    &pm,
    &purse_sig->eddsa_signature,
    &purse_pub->eddsa_pub);
}


void
TALER_wallet_purse_status_sign (
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_STATUS)
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&purse_priv->eddsa_priv,
                                            &purpose,
                                            &purse_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_status_verify (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_STATUS)
  };

  return GNUNET_CRYPTO_eddsa_verify_ (TALER_SIGNATURE_WALLET_PURSE_STATUS,
                                      &purpose,
                                      &purse_sig->eddsa_signature,
                                      &purse_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed to deposit a coin into a purse.
 */
struct TALER_PurseDepositPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_PURSE_DEPOSIT
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Amount (with deposit fee) to be deposited into the purse.
   */
  struct TALER_AmountNBO coin_amount;

  /**
   * Hash over the denomination public key used to sign the coin.
   */
  struct TALER_DenominationHashP h_denom_pub GNUNET_PACKED;

  /**
   * Hash over the age commitment that went into the coin. Maybe all zero, if
   * age commitment isn't applicable to the denomination.
   */
  struct TALER_AgeCommitmentHash h_age_commitment GNUNET_PACKED;

  /**
   * Purse to deposit funds into.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Hash of the base URL of the exchange hosting the
   * @e purse_pub.
   */
  struct GNUNET_HashCode h_exchange_base_url GNUNET_PACKED;
};

GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_purse_deposit_sign (
  const char *exchange_base_url,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *amount,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_PurseDepositPS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_DEPOSIT),
    .purse_pub = *purse_pub,
    .h_denom_pub = *h_denom_pub,
    .h_age_commitment = *h_age_commitment
  };

  GNUNET_CRYPTO_hash (exchange_base_url,
                      strlen (exchange_base_url) + 1,
                      &pm.h_exchange_base_url);
  TALER_amount_hton (&pm.coin_amount,
                     amount);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &pm,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_deposit_verify (
  const char *exchange_base_url,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *amount,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_PurseDepositPS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_DEPOSIT),
    .purse_pub = *purse_pub,
    .h_denom_pub = *h_denom_pub,
    .h_age_commitment = *h_age_commitment
  };

  GNUNET_CRYPTO_hash (exchange_base_url,
                      strlen (exchange_base_url) + 1,
                      &pm.h_exchange_base_url);
  TALER_amount_hton (&pm.coin_amount,
                     amount);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_PURSE_DEPOSIT,
    &pm,
    &coin_sig->eddsa_signature,
    &coin_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed to merge a purse into a reserve.
 */
struct TALER_PurseMergePS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_PURSE_MERGE
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time when the purse is merged into the reserve.
   */
  struct GNUNET_TIME_TimestampNBO merge_timestamp;

  /**
   * Which purse is being merged?
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Which reserve should the purse be merged with.
   * Hash of the reserve's payto:// URI.
   */
  struct TALER_PaytoHashP h_payto;

};

GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_purse_merge_sign (
  const char *reserve_uri,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  struct TALER_PurseMergeSignatureP *merge_sig)
{
  struct TALER_PurseMergePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_MERGE),
    .merge_timestamp = GNUNET_TIME_timestamp_hton (merge_timestamp),
    .purse_pub = *purse_pub
  };

  GNUNET_assert (0 ==
                 strncasecmp (reserve_uri,
                              "payto://taler-reserve",
                              strlen ("payto://taler-reserve")));
  TALER_payto_hash (reserve_uri,
                    &pm.h_payto);
  GNUNET_CRYPTO_eddsa_sign (&merge_priv->eddsa_priv,
                            &pm,
                            &merge_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_merge_verify (
  const char *reserve_uri,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig)
{
  struct TALER_PurseMergePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_MERGE),
    .merge_timestamp = GNUNET_TIME_timestamp_hton (merge_timestamp),
    .purse_pub = *purse_pub
  };

  if (0 !=
      strncasecmp (reserve_uri,
                   "payto://taler-reserve",
                   strlen ("payto://taler-reserve")))
  {
    GNUNET_break (0);
    return GNUNET_NO;
  }
  TALER_payto_hash (reserve_uri,
                    &pm.h_payto);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_PURSE_MERGE,
    &pm,
    &merge_sig->eddsa_signature,
    &merge_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed by account to merge a purse into a reserve.
 */
struct TALER_AccountMergePS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_ACCOUNT_MERGE
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Time when the purse will expire if still unmerged or unpaid.
   */
  struct GNUNET_TIME_TimestampNBO purse_expiration;

  /**
   * Total amount (with fees) to be put into the purse.
   */
  struct TALER_AmountNBO purse_amount;

  /**
   * Purse creation fee to be paid by the reserve for
   * this operation.
   */
  struct TALER_AmountNBO purse_fee;

  /**
   * Contract this purse pays for.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Purse to merge.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Time when the purse is merged into the reserve.
   */
  struct GNUNET_TIME_TimestampNBO merge_timestamp;

  /**
   * Minimum age required for payments into this purse,
   * in NBO.
   */
  uint32_t min_age GNUNET_PACKED;

  /**
   * Flags for the operation, in NBO. See
   * `enum TALER_WalletAccountMergeFlags`.
   */
  uint32_t flags GNUNET_PACKED;
};

GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_account_merge_sign (
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_Amount *amount,
  const struct TALER_Amount *purse_fee,
  uint32_t min_age,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_AccountMergePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_MERGE),
    .merge_timestamp = GNUNET_TIME_timestamp_hton (merge_timestamp),
    .purse_pub = *purse_pub,
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .h_contract_terms = *h_contract_terms,
    .min_age = htonl (min_age),
    .flags = htonl ((uint32_t) flags)
  };

  TALER_amount_hton (&pm.purse_amount,
                     amount);
  TALER_amount_hton (&pm.purse_fee,
                     purse_fee);
  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &pm,
                            &reserve_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_account_merge_verify (
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_Amount *amount,
  const struct TALER_Amount *purse_fee,
  uint32_t min_age,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_AccountMergePS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_MERGE),
    .merge_timestamp = GNUNET_TIME_timestamp_hton (merge_timestamp),
    .purse_pub = *purse_pub,
    .purse_expiration = GNUNET_TIME_timestamp_hton (purse_expiration),
    .h_contract_terms = *h_contract_terms,
    .min_age = htonl (min_age),
    .flags = htonl ((uint32_t) flags)
  };

  TALER_amount_hton (&pm.purse_amount,
                     amount);
  TALER_amount_hton (&pm.purse_fee,
                     purse_fee);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_ACCOUNT_MERGE,
    &pm,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed by reserve key.
 */
struct TALER_ReserveOpenPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_RESERVE_OPEN
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Amount to be paid from the reserve balance to open
   * the reserve.
   */
  struct TALER_AmountNBO reserve_payment;

  /**
   * When was the request created.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

  /**
   * For how long should the reserve be kept open.
   * (Determines amount to be paid.)
   */
  struct GNUNET_TIME_TimestampNBO reserve_expiration;

  /**
   * How many open purses should be included with the
   * open reserve?
   * (Determines amount to be paid.)
   */
  uint32_t purse_limit GNUNET_PACKED;

};

GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_reserve_open_sign (
  const struct TALER_Amount *reserve_payment,
  struct GNUNET_TIME_Timestamp request_timestamp,
  struct GNUNET_TIME_Timestamp reserve_expiration,
  uint32_t purse_limit,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveOpenPS rop = {
    .purpose.size = htonl (sizeof (rop)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_OPEN),
    .request_timestamp = GNUNET_TIME_timestamp_hton (request_timestamp),
    .reserve_expiration = GNUNET_TIME_timestamp_hton (reserve_expiration),
    .purse_limit = htonl (purse_limit)
  };

  TALER_amount_hton (&rop.reserve_payment,
                     reserve_payment);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&reserve_priv->eddsa_priv,
                                            &rop.purpose,
                                            &reserve_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_reserve_open_verify (
  const struct TALER_Amount *reserve_payment,
  struct GNUNET_TIME_Timestamp request_timestamp,
  struct GNUNET_TIME_Timestamp reserve_expiration,
  uint32_t purse_limit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveOpenPS rop = {
    .purpose.size = htonl (sizeof (rop)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_OPEN),
    .request_timestamp = GNUNET_TIME_timestamp_hton (request_timestamp),
    .reserve_expiration = GNUNET_TIME_timestamp_hton (reserve_expiration),
    .purse_limit = htonl (purse_limit)
  };

  TALER_amount_hton (&rop.reserve_payment,
                     reserve_payment);
  return GNUNET_CRYPTO_eddsa_verify_ (TALER_SIGNATURE_WALLET_RESERVE_OPEN,
                                      &rop.purpose,
                                      &reserve_sig->eddsa_signature,
                                      &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed by
 */
struct TALER_ReserveOpenDepositPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_RESERVE_OPEN_DEPOSIT
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Which reserve's opening signature should be paid for?
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Specifies how much of the coin's value should be spent on opening this
   * reserve.
   */
  struct TALER_AmountNBO coin_contribution;
};

GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_reserve_open_deposit_sign (
  const struct TALER_Amount *coin_contribution,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_ReserveOpenDepositPS rod = {
    .purpose.size = htonl (sizeof (rod)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_OPEN_DEPOSIT),
    .reserve_sig = *reserve_sig
  };

  TALER_amount_hton (&rod.coin_contribution,
                     coin_contribution);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&coin_priv->eddsa_priv,
                                            &rod.purpose,
                                            &coin_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_reserve_open_deposit_verify (
  const struct TALER_Amount *coin_contribution,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_ReserveOpenDepositPS rod = {
    .purpose.size = htonl (sizeof (rod)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_OPEN_DEPOSIT),
    .reserve_sig = *reserve_sig
  };

  TALER_amount_hton (&rod.coin_contribution,
                     coin_contribution);
  return GNUNET_CRYPTO_eddsa_verify_ (
    TALER_SIGNATURE_WALLET_RESERVE_OPEN_DEPOSIT,
    &rod.purpose,
    &coin_sig->eddsa_signature,
    &coin_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed by reserve key.
 */
struct TALER_ReserveClosePS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_RESERVE_CLOSE
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When was the request created.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

  /**
   * Hash of the payto://-URI of the target account
   * for the closure, or all zeros for the reserve
   * origin account.
   */
  struct TALER_PaytoHashP target_account_h_payto;

};

GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_reserve_close_sign (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveClosePS rcp = {
    .purpose.size = htonl (sizeof (rcp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_CLOSE),
    .request_timestamp = GNUNET_TIME_timestamp_hton (request_timestamp)
  };

  if (NULL != h_payto)
    rcp.target_account_h_payto = *h_payto;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&reserve_priv->eddsa_priv,
                                            &rcp.purpose,
                                            &reserve_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_reserve_close_verify (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveClosePS rcp = {
    .purpose.size = htonl (sizeof (rcp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_CLOSE),
    .request_timestamp = GNUNET_TIME_timestamp_hton (request_timestamp)
  };

  if (NULL != h_payto)
    rcp.target_account_h_payto = *h_payto;
  return GNUNET_CRYPTO_eddsa_verify_ (TALER_SIGNATURE_WALLET_RESERVE_CLOSE,
                                      &rcp.purpose,
                                      &reserve_sig->eddsa_signature,
                                      &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed by reserve private key.
 */
struct TALER_ReserveAttestRequestPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_ATTEST_REQUEST
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * When was the request created.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

  /**
   * Hash over the JSON array of requested attributes.
   */
  struct GNUNET_HashCode h_details;

};

GNUNET_NETWORK_STRUCT_END


void
TALER_wallet_reserve_attest_request_sign (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const json_t *details,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveAttestRequestPS rcp = {
    .purpose.size = htonl (sizeof (rcp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_ATTEST_DETAILS),
    .request_timestamp = GNUNET_TIME_timestamp_hton (request_timestamp)
  };

  TALER_json_hash (details,
                   &rcp.h_details);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&reserve_priv->eddsa_priv,
                                            &rcp.purpose,
                                            &reserve_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_reserve_attest_request_verify (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const json_t *details,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct TALER_ReserveAttestRequestPS rcp = {
    .purpose.size = htonl (sizeof (rcp)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_ATTEST_DETAILS),
    .request_timestamp = GNUNET_TIME_timestamp_hton (request_timestamp)
  };

  TALER_json_hash (details,
                   &rcp.h_details);
  return GNUNET_CRYPTO_eddsa_verify_ (
    TALER_SIGNATURE_WALLET_RESERVE_ATTEST_DETAILS,
    &rcp.purpose,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Message signed by purse to associate an encrypted contract.
 */
struct TALER_PurseContractPS
{

  /**
   * Purpose is #TALER_SIGNATURE_WALLET_PURSE_ECONTRACT
   */
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose;

  /**
   * Hash over the encrypted contract.
   */
  struct GNUNET_HashCode h_econtract;

  /**
   * Public key to decrypt the contract.
   */
  struct TALER_ContractDiffiePublicP contract_pub;
};

GNUNET_NETWORK_STRUCT_END

void
TALER_wallet_econtract_upload_sign (
  const void *econtract,
  size_t econtract_size,
  const struct TALER_ContractDiffiePublicP *contract_pub,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig)
{
  struct TALER_PurseContractPS pc = {
    .purpose.size = htonl (sizeof (pc)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_ECONTRACT),
    .contract_pub = *contract_pub
  };

  GNUNET_CRYPTO_hash (econtract,
                      econtract_size,
                      &pc.h_econtract);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&purse_priv->eddsa_priv,
                                            &pc.purpose,
                                            &purse_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_econtract_upload_verify2 (
  const struct GNUNET_HashCode *h_econtract,
  const struct TALER_ContractDiffiePublicP *contract_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  struct TALER_PurseContractPS pc = {
    .purpose.size = htonl (sizeof (pc)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_ECONTRACT),
    .contract_pub = *contract_pub,
    .h_econtract = *h_econtract
  };

  return GNUNET_CRYPTO_eddsa_verify_ (TALER_SIGNATURE_WALLET_PURSE_ECONTRACT,
                                      &pc.purpose,
                                      &purse_sig->eddsa_signature,
                                      &purse_pub->eddsa_pub);
}


enum GNUNET_GenericReturnValue
TALER_wallet_econtract_upload_verify (
  const void *econtract,
  size_t econtract_size,
  const struct TALER_ContractDiffiePublicP *contract_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig)
{
  struct GNUNET_HashCode h_econtract;

  GNUNET_CRYPTO_hash (econtract,
                      econtract_size,
                      &h_econtract);
  return TALER_wallet_econtract_upload_verify2 (&h_econtract,
                                                contract_pub,
                                                purse_pub,
                                                purse_sig);
}


/* end of wallet_signatures.c */
