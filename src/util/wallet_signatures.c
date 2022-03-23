/*
  This file is part of TALER
  Copyright (C) 2021, 2022 Taler Systems SA

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
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"


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
   * Hash over extension attributes shared with the exchange.
   */
  struct TALER_ExtensionContractHashP h_extensions GNUNET_PACKED;

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

};


void
TALER_wallet_deposit_sign (
  const struct TALER_Amount *amount,
  const struct TALER_Amount *deposit_fee,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_ExtensionContractHashP *h_extensions,
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

  if (NULL != h_extensions)
    dr.h_extensions = *h_extensions;

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
  const struct TALER_ExtensionContractHashP *h_extensions,
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
    .h_extensions = {{{0}}}
  };

  if (NULL != h_age_commitment)
    dr.h_age_commitment = *h_age_commitment;

  if (NULL != h_extensions)
    dr.h_extensions = *h_extensions;

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


void
TALER_wallet_account_setup_sign (
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_SETUP)
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&reserve_priv->eddsa_priv,
                                            &purpose,
                                            &reserve_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_account_setup_verify (
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_SETUP)
  };

  return GNUNET_CRYPTO_eddsa_verify_ (
    TALER_SIGNATURE_WALLET_ACCOUNT_SETUP,
    &purpose,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


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
   * When did the wallet make the requst.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

  /**
   * How much does the exchange charge for the history?
   */
  struct TALER_AmountNBO history_fee;

};


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
    TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
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
   * When did the wallet make the requst.
   */
  struct GNUNET_TIME_TimestampNBO request_timestamp;

};


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


void
TALER_wallet_purse_create_sign (
  struct GNUNET_TIME_Timestamp purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
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
  struct TALER_PrivateContractHashP *h_contract_terms,
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
   * Purse to deposit funds into.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

};


void
TALER_wallet_purse_deposit_sign (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_PurseDepositPS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_DEPOSIT),
    .purse_pub = *purse_pub,
  };

  TALER_amount_hton (&pm.coin_amount,
                     amount);
  GNUNET_CRYPTO_eddsa_sign (&coin_priv->eddsa_priv,
                            &pm,
                            &coin_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_deposit_verify (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TALER_PurseDepositPS pm = {
    .purpose.size = htonl (sizeof (pm)),
    .purpose.purpose = htonl (TALER_SIGNATURE_WALLET_PURSE_DEPOSIT),
    .purse_pub = *purse_pub,
  };

  TALER_amount_hton (&pm.coin_amount,
                     amount);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_PURSE_DEPOSIT,
    &pm,
    &coin_sig->eddsa_signature,
    &coin_pub->eddsa_pub);
}


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


void
TALER_wallet_purse_merge_sign (
  const char *reserve_url,
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

  TALER_payto_hash (reserve_url,
                    &pm.h_payto);
  GNUNET_CRYPTO_eddsa_sign (&merge_priv->eddsa_priv,
                            &pm,
                            &merge_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_purse_merge_verify (
  const char *reserve_url,
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

  TALER_payto_hash (reserve_url,
                    &pm.h_payto);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_ACCOUNT_MERGE,
    &pm,
    &merge_sig->eddsa_signature,
    &merge_pub->eddsa_pub);
}


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
   * Minimum age required for payments into this purse.
   */
  uint32_t min_age GNUNET_PACKED;
};


void
TALER_wallet_account_merge_sign (
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_Amount *amount,
  uint32_t min_age,
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
    .min_age = htonl (min_age)
  };

  TALER_amount_hton (&pm.purse_amount,
                     amount);
  GNUNET_CRYPTO_eddsa_sign (&reserve_priv->eddsa_priv,
                            &pm,
                            &reserve_sig->eddsa_signature);
}


enum GNUNET_GenericReturnValue
TALER_wallet_account_merge_verify (
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_Amount *amount,
  uint32_t min_age,
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
    .min_age = htonl (min_age)
  };

  TALER_amount_hton (&pm.purse_amount,
                     amount);
  return GNUNET_CRYPTO_eddsa_verify (
    TALER_SIGNATURE_WALLET_ACCOUNT_MERGE,
    &pm,
    &reserve_sig->eddsa_signature,
    &reserve_pub->eddsa_pub);
}


void
TALER_wallet_account_close_sign (
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_CLOSE)
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign_ (&reserve_priv->eddsa_priv,
                                            &purpose,
                                            &reserve_sig->eddsa_signature));
}


enum GNUNET_GenericReturnValue
TALER_wallet_account_close_verify (
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_CLOSE)
  };

  return GNUNET_CRYPTO_eddsa_verify_ (TALER_SIGNATURE_WALLET_RESERVE_CLOSE,
                                      &purpose,
                                      &reserve_sig->eddsa_signature,
                                      &reserve_pub->eddsa_pub);
}


/* end of wallet_signatures.c */
