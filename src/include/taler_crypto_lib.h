/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file include/taler_crypto_lib.h
 * @brief taler-specific crypto functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef TALER_CRYPTO_LIB_H
#define TALER_CRYPTO_LIB_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_error_codes.h"
#include <gcrypt.h>
#include <jansson.h>


/**
 * Maximum number of coins we allow per operation.
 */
#define TALER_MAX_FRESH_COINS 256

/**
 * Cut-and-choose size for refreshing.  Client looses the gamble (of
 * unaccountable transfers) with probability 1/TALER_CNC_KAPPA.  Refresh cost
 * increases linearly with TALER_CNC_KAPPA, and 3 is sufficient up to a
 * income/sales tax of 66% of total transaction value.  As there is
 * no good reason to change this security parameter, we declare it
 * fixed and part of the protocol.
 */
#define TALER_CNC_KAPPA 3


/* ****************** Coin crypto primitives ************* */

GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Type of public keys for Taler security modules (software or hardware).
 * Note that there are usually at least two security modules (RSA and EdDSA),
 * each with its own private key.
 */
struct TALER_SecurityModulePublicKeyP
{
  /**
   * Taler uses EdDSA for security modules.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};

/**
 * @brief Set of the public keys of the security modules
 */
struct TALER_SecurityModulePublicKeySetP
{
  /**
   * Public key of the RSA security module
   */
  struct TALER_SecurityModulePublicKeyP rsa;

  /**
   * Public key of the CS security module
   */
  struct TALER_SecurityModulePublicKeyP cs;

  /**
   * Public key of the eddsa security module
   */
  struct TALER_SecurityModulePublicKeyP eddsa;
};

/**
 * @brief Type of private keys for Taler security modules (software or hardware).
 */
struct TALER_SecurityModulePrivateKeyP
{
  /**
   * Taler uses EdDSA for security modules.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures used for Taler security modules (software or hardware).
 */
struct TALER_SecurityModuleSignatureP
{
  /**
   * Taler uses EdDSA for security modules.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of public keys for Taler reserves.
 */
struct TALER_ReservePublicKeyP
{
  /**
   * Taler uses EdDSA for reserves.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of private keys for Taler reserves.
 */
struct TALER_ReservePrivateKeyP
{
  /**
   * Taler uses EdDSA for reserves.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures used with Taler reserves.
 */
struct TALER_ReserveSignatureP
{
  /**
   * Taler uses EdDSA for reserves.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of public keys to for merchant authorizations.
 * Merchants can issue refunds using the corresponding
 * private key.
 */
struct TALER_MerchantPublicKeyP
{
  /**
   * Taler uses EdDSA for merchants.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of private keys for merchant authorizations.
 * Merchants can issue refunds using the corresponding
 * private key.
 */
struct TALER_MerchantPrivateKeyP
{
  /**
   * Taler uses EdDSA for merchants.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures made by merchants.
 */
struct TALER_MerchantSignatureP
{
  /**
   * Taler uses EdDSA for merchants.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_sig;
};


/**
 * @brief Type of transfer public keys used during refresh
 * operations.
 */
struct TALER_TransferPublicKeyP
{
  /**
   * Taler uses ECDHE for transfer keys.
   */
  struct GNUNET_CRYPTO_EcdhePublicKey ecdhe_pub;
};


/**
 * @brief Type of transfer private keys used during refresh
 * operations.
 */
struct TALER_TransferPrivateKeyP
{
  /**
   * Taler uses ECDHE for melting session keys.
   */
  struct GNUNET_CRYPTO_EcdhePrivateKey ecdhe_priv;
};


/**
 * @brief Type of public keys used for contract
 * encryption.
 */
struct TALER_ContractDiffiePublicP
{
  /**
   * Taler uses ECDHE for contract encryption.
   */
  struct GNUNET_CRYPTO_EcdhePublicKey ecdhe_pub;
};


/**
 * @brief Type of private keys used for contract
 * encryption.
 */
struct TALER_ContractDiffiePrivateP
{
  /**
   * Taler uses ECDHE for contract encryption.
   */
  struct GNUNET_CRYPTO_EcdhePrivateKey ecdhe_priv;
};


/**
 * @brief Type of online public keys used by the exchange to sign
 * messages.
 */
struct TALER_ExchangePublicKeyP
{
  /**
   * Taler uses EdDSA for online exchange message signing.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of online public keys used by the exchange to
 * sign messages.
 */
struct TALER_ExchangePrivateKeyP
{
  /**
   * Taler uses EdDSA for online signatures sessions.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures used by the exchange to sign messages online.
 */
struct TALER_ExchangeSignatureP
{
  /**
   * Taler uses EdDSA for online signatures sessions.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of the offline master public key used by the exchange.
 */
struct TALER_MasterPublicKeyP
{
  /**
   * Taler uses EdDSA for the long-term offline master key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of the offline master public keys used by the exchange.
 */
struct TALER_MasterPrivateKeyP
{
  /**
   * Taler uses EdDSA for the long-term offline master key.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures by the offline master public key used by the exchange.
 */
struct TALER_MasterSignatureP
{
  /**
   * Taler uses EdDSA for the long-term offline master key.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of the private key used by the auditor.
 */
struct TALER_AuditorPrivateKeyP
{
  /**
   * Taler uses EdDSA for the auditor's signing key.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of the public key used by the auditor.
 */
struct TALER_AuditorPublicKeyP
{
  /**
   * Taler uses EdDSA for the auditor's signing key.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of signatures used by the auditor.
 */
struct TALER_AuditorSignatureP
{
  /**
   * Taler uses EdDSA signatures for auditors.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_sig;
};


/**
 * @brief Type of public keys for Taler coins.  The same key material is used
 * for EdDSA and ECDHE operations.
 */
struct TALER_CoinSpendPublicKeyP
{
  /**
   * Taler uses EdDSA for coins when signing deposit requests.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;

};


/**
 * @brief Type of private keys for Taler coins.  The same key material is used
 * for EdDSA and ECDHE operations.
 */
struct TALER_CoinSpendPrivateKeyP
{
  /**
   * Taler uses EdDSA for coins when signing deposit requests.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};

/**
 * @brief Type of signatures made with Taler coins.
 */
struct TALER_CoinSpendSignatureP
{
  /**
   * Taler uses EdDSA for coins.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of private keys for age commitment in coins.
 */
struct TALER_AgeCommitmentPrivateKeyP
{
#ifdef AGE_RESTRICTION_WITH_ECDSA
  /**
   * Taler uses EcDSA for coins when signing age verification attestation.
   */
  struct GNUNET_CRYPTO_EcdsaPrivateKey priv;
#else
  /**
   * Taler uses Edx25519 for coins when signing age verification attestation.
   */
  struct GNUNET_CRYPTO_Edx25519PrivateKey priv;
#endif
};


/**
 * @brief Type of public keys for age commitment in coins.
 */
struct TALER_AgeCommitmentPublicKeyP
{
#ifdef AGE_RESTRICTION_WITH_ECDSA
  /**
   * Taler uses EcDSA for coins when signing age verification attestation.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey pub;
#else
  /**
   * Taler uses Edx25519 for coins when signing age verification attestation.
   */
  struct GNUNET_CRYPTO_Edx25519PublicKey pub;
#endif
};


/**
 * @brief Type of online public keys used by the wallet to establish a purse and the associated contract meta data.
 */
struct TALER_PurseContractPublicKeyP
{
  /**
   * Taler uses EdDSA for purse message signing.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of online private keys used by the wallet to
 * bind a purse to a particular contract (and other meta data).
 */
struct TALER_PurseContractPrivateKeyP
{
  /**
   * Taler uses EdDSA for online signatures sessions.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures used by the wallet to sign purse creation messages online.
 */
struct TALER_PurseContractSignatureP
{
  /**
   * Taler uses EdDSA for online signatures sessions.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of online public keys used by the wallet to
 * sign a merge of a purse into an account.
 */
struct TALER_PurseMergePublicKeyP
{
  /**
   * Taler uses EdDSA for purse message signing.
   */
  struct GNUNET_CRYPTO_EddsaPublicKey eddsa_pub;
};


/**
 * @brief Type of online private keys used by the wallet to
 * sign a merge of a purse into an account.
 */
struct TALER_PurseMergePrivateKeyP
{
  /**
   * Taler uses EdDSA for online signatures sessions.
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey eddsa_priv;
};


/**
 * @brief Type of signatures used by the wallet to sign purse merge requests online.
 */
struct TALER_PurseMergeSignatureP
{
  /**
   * Taler uses EdDSA for online signatures sessions.
   */
  struct GNUNET_CRYPTO_EddsaSignature eddsa_signature;
};


/**
 * @brief Type of blinding keys for Taler.
 * must be 32 bytes (DB)
 */
union TALER_DenominationBlindingKeyP
{
  /**
   * Clause Schnorr Signatures have 2 blinding secrets, each containing two unpredictable values. (must be 32 bytes)
   */
  struct GNUNET_CRYPTO_CsNonce nonce;

  /**
   * Taler uses RSA for blind signatures.
   */
  struct GNUNET_CRYPTO_RsaBlindingKeySecret rsa_bks;
};


/**
 * Commitment value for the refresh protocol.
 * See #TALER_refresh_get_commitment().
 */
struct TALER_RefreshCommitmentP
{
  /**
   * The commitment is a hash code.
   */
  struct GNUNET_HashCode session_hash;
};


/**
 * Token used for access control to the merchant's unclaimed
 * orders.
 */
struct TALER_ClaimTokenP
{
  /**
   * The token is a 128-bit UUID.
   */
  struct GNUNET_Uuid token;
};


/**
 * Salt used to hash a merchant's payto:// URI to
 * compute the "h_wire" (say for deposit requests).
 */
struct TALER_WireSaltP
{
  /**
   * Actual 128-bit salt value.
   */
  uint32_t salt[4];
};


/**
 * Hash used to represent an CS public key.  Does not include age
 * restrictions and is ONLY for CS.  Used ONLY for interactions with the CS
 * security module.
 */
struct TALER_CsPubHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent an RSA public key.  Does not include age
 * restrictions and is ONLY for RSA.  Used ONLY for interactions with the RSA
 * security module.
 */
struct TALER_RsaPubHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Master key material for the deriviation of
 * private coins and blinding factors during
 * withdraw or refresh.
 */
struct TALER_PlanchetMasterSecretP
{

  /**
   * Key material.
   */
  uint32_t key_data[8];

};


/**
 * Master key material for the deriviation of
 * private coins and blinding factors.
 */
struct TALER_RefreshMasterSecretP
{

  /**
   * Key material.
   */
  uint32_t key_data[8];

};


/**
 * Hash used to represent a denomination public key
 * and associated age restrictions (if any).
 */
struct TALER_DenominationHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent the private part
 * of a contract between merchant and consumer.
 */
struct TALER_PrivateContractHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent the "public" extensions to
 * a contract that is shared with the exchange.
 */
struct TALER_ExtensionContractHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent the salted hash of a
 * merchant's bank account.
 */
struct TALER_MerchantWireHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent the unsalted hash of a
 * payto:// URI representing a bank account.
 */
struct TALER_PaytoHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_ShortHashCode hash;
};


/**
 * Hash used to represent a commitment to a blinded
 * coin, i.e. the hash of the envelope.
 */
struct TALER_BlindedCoinHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent the hash of the public
 * key of a coin (without blinding).
 */
struct TALER_CoinPubHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * @brief Value that uniquely identifies a tip.
 */
struct TALER_TipIdentifierP
{
  /**
   * The tip identifier is a SHA-512 hash code.
   */
  struct GNUNET_HashCode hash;
};


/**
 * @brief Value that uniquely identifies a tip pick up operation.
 */
struct TALER_PickupIdentifierP
{
  /**
   * The pickup identifier is a SHA-512 hash code.
   */
  struct GNUNET_HashCode hash;
};


/**
 * @brief Salted hash over the JSON object representing the configuration of an
 * extension.
 */
struct TALER_ExtensionConfigHashP
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Set of the fees applying to a denomination.
 */
struct TALER_DenomFeeSetNBOP
{

  /**
   * The fee the exchange charges when a coin of this type is withdrawn.
   * (can be zero).
   */
  struct TALER_AmountNBO withdraw;

  /**
   * The fee the exchange charges when a coin of this type is deposited.
   * (can be zero).
   */
  struct TALER_AmountNBO deposit;

  /**
   * The fee the exchange charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_AmountNBO refresh;

  /**
   * The fee the exchange charges when a coin of this type is refunded.
   * (can be zero).  Note that refund fees are charged to the customer;
   * if a refund is given, the deposit fee is also refunded.
   */
  struct TALER_AmountNBO refund;

};


/**
 * Set of the fees applying for a given
 * time-range and wire method.
 */
struct TALER_WireFeeSetNBOP
{

  /**
   * The fee the exchange charges for wiring funds
   * to a merchant.
   */
  struct TALER_AmountNBO wire;

  /**
   * The fee the exchange charges for closing a reserve
   * and wiring the funds back to the origin account.
   */
  struct TALER_AmountNBO closing;

  /**
   * The fee the exchange charges for cross-exchange
   * P2P payments.
   */
  struct TALER_AmountNBO wad;

};


/**
 * Set of the fees applying globally for a given
 * time-range.
 */
struct TALER_GlobalFeeSetNBOP
{

  /**
   * The fee the exchange charges for returning the
   * history of a reserve or account.
   */
  struct TALER_AmountNBO history;

  /**
   * The fee the exchange charges for performing a
   * KYC check on a reserve to turn it into an account
   * that can be used for P2P payments.
   */
  struct TALER_AmountNBO kyc;

  /**
   * The fee the exchange charges for keeping
   * an account or reserve open for a year.
   */
  struct TALER_AmountNBO account;

  /**
   * The fee the exchange charges if a purse
   * is abandoned and this was not covered by
   * the account limit.
   */
  struct TALER_AmountNBO purse;
};


GNUNET_NETWORK_STRUCT_END


/**
 * Set of the fees applying to a denomination.
 */
struct TALER_DenomFeeSet
{

  /**
   * The fee the exchange charges when a coin of this type is withdrawn.
   * (can be zero).
   */
  struct TALER_Amount withdraw;

  /**
   * The fee the exchange charges when a coin of this type is deposited.
   * (can be zero).
   */
  struct TALER_Amount deposit;

  /**
   * The fee the exchange charges when a coin of this type is refreshed.
   * (can be zero).
   */
  struct TALER_Amount refresh;

  /**
   * The fee the exchange charges when a coin of this type is refunded.
   * (can be zero).  Note that refund fees are charged to the customer;
   * if a refund is given, the deposit fee is also refunded.
   */
  struct TALER_Amount refund;

};


/**
 * Set of the fees applying for a given
 * time-range and wire method.
 */
struct TALER_WireFeeSet
{

  /**
   * The fee the exchange charges for wiring funds
   * to a merchant.
   */
  struct TALER_Amount wire;

  /**
   * The fee the exchange charges for closing a reserve
   * and wiring the funds back to the origin account.
   */
  struct TALER_Amount closing;

  /**
   * The fee the exchange charges for cross-exchange
   * P2P payments.
   */
  struct TALER_Amount wad;

};


/**
 * Set of the fees applying globally for a given
 * time-range.
 */
struct TALER_GlobalFeeSet
{

  /**
   * The fee the exchange charges for returning the
   * history of a reserve or account.
   */
  struct TALER_Amount history;

  /**
   * The fee the exchange charges for performing a
   * KYC check on a reserve to turn it into an account
   * that can be used for P2P payments.
   */
  struct TALER_Amount kyc;

  /**
   * The fee the exchange charges for keeping
   * an account or reserve open for a year.
   */
  struct TALER_Amount account;

  /**
   * The fee the exchange charges if a purse
   * is abandoned and this was not covered by
   * the account limit.
   */
  struct TALER_Amount purse;
};


/**
 * Convert fee set from host to network byte order.
 *
 * @param[out] nbo where to write the result
 * @param fees fee set to convert
 */
void
TALER_denom_fee_set_hton (struct TALER_DenomFeeSetNBOP *nbo,
                          const struct TALER_DenomFeeSet *fees);


/**
 * Convert fee set from network to host network byte order.
 *
 * @param[out] fees where to write the result
 * @param nbo fee set to convert
 */
void
TALER_denom_fee_set_ntoh (struct TALER_DenomFeeSet *fees,
                          const struct TALER_DenomFeeSetNBOP *nbo);


/**
 * Convert global fee set from host to network byte order.
 *
 * @param[out] nbo where to write the result
 * @param fees fee set to convert
 */
void
TALER_global_fee_set_hton (struct TALER_GlobalFeeSetNBOP *nbo,
                           const struct TALER_GlobalFeeSet *fees);


/**
 * Convert global fee set from network to host network byte order.
 *
 * @param[out] fees where to write the result
 * @param nbo fee set to convert
 */
void
TALER_global_fee_set_ntoh (struct TALER_GlobalFeeSet *fees,
                           const struct TALER_GlobalFeeSetNBOP *nbo);


/**
 * Compare global fee sets.
 *
 * @param f1 first set to compare
 * @param f2 second set to compare
 * @return 0 if sets are equal
 */
int
TALER_global_fee_set_cmp (const struct TALER_GlobalFeeSet *f1,
                          const struct TALER_GlobalFeeSet *f2);


/**
 * Convert wire fee set from host to network byte order.
 *
 * @param[out] nbo where to write the result
 * @param fees fee set to convert
 */
void
TALER_wire_fee_set_hton (struct TALER_WireFeeSetNBOP *nbo,
                         const struct TALER_WireFeeSet *fees);


/**
 * Convert wire fee set from network to host network byte order.
 *
 * @param[out] fees where to write the result
 * @param nbo fee set to convert
 */
void
TALER_wire_fee_set_ntoh (struct TALER_WireFeeSet *fees,
                         const struct TALER_WireFeeSetNBOP *nbo);


/**
 * Compare wire fee sets.
 *
 * @param f1 first set to compare
 * @param f2 second set to compare
 * @return 0 if sets are equal
 */
int
TALER_wire_fee_set_cmp (const struct TALER_WireFeeSet *f1,
                        const struct TALER_WireFeeSet *f2);


/**
 * Hash @a rsa.
 *
 * @param rsa key to hash
 * @param[out] h_rsa where to write the result
 */
void
TALER_rsa_pub_hash (const struct GNUNET_CRYPTO_RsaPublicKey *rsa,
                    struct TALER_RsaPubHashP *h_rsa);

/**
 * Hash @a cs.
 *
 * @param cs key to hash
 * @param[out] h_cs where to write the result
 */
void
TALER_cs_pub_hash (const struct GNUNET_CRYPTO_CsPublicKey *cs,
                   struct TALER_CsPubHashP *h_cs);


/**
 * Types of public keys used for denominations in Taler.
 */
enum TALER_DenominationCipher
{

  /**
   * Invalid type of signature.
   */
  TALER_DENOMINATION_INVALID = 0,

  /**
   * RSA blind signature.
   */
  TALER_DENOMINATION_RSA = 1,

  /**
   * Clause Blind Schnorr signature.
   */
  TALER_DENOMINATION_CS = 2
};


/**
 * @brief Type of (unblinded) coin signatures for Taler.
 */
struct TALER_DenominationSignature
{

  /**
   * Type of the signature.
   */
  enum TALER_DenominationCipher cipher;

  /**
   * Details, depending on @e cipher.
   */
  union
  {
    /**
     * If we use #TALER_DENOMINATION_CS in @a cipher.
     */
    struct GNUNET_CRYPTO_CsSignature cs_signature;

    /**
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaSignature *rsa_signature;

  } details;

};

/**
 * The Sign Answer for Clause Blind Schnorr signature.
 * The sign operation returns a parameter @param b and the signature
 * scalar @param s_scalar.
 */
struct TALER_BlindedDenominationCsSignAnswer
{
  /**
   * To make ROS problem harder, the signer chooses an unpredictable b and only calculates signature of c_b
   */
  unsigned int b;

  /**
   * The blinded s scalar calculated from c_b
   */
  struct GNUNET_CRYPTO_CsBlindS s_scalar;
};

/**
 * @brief Type for *blinded* denomination signatures for Taler.
 * Must be unblinded before it becomes valid.
 */
struct TALER_BlindedDenominationSignature
{

  /**
   * Type of the signature.
   */
  enum TALER_DenominationCipher cipher;

  /**
   * Details, depending on @e cipher.
   */
  union
  {
    /**
     * If we use #TALER_DENOMINATION_CS in @a cipher.
     * At this point only the blinded s scalar is used.
     * The final signature consisting of r,s is built after unblinding.
     */
    struct TALER_BlindedDenominationCsSignAnswer blinded_cs_answer;

    /**
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaSignature *blinded_rsa_signature;

  } details;

};

/* *************** Age Restriction *********************************** */

/*
 * @brief Type of a list of age groups, represented as bit mask.
 *
 * The bits set in the mask mark the edges at the beginning of a next age
 * group.  F.e. for the age groups
 *     0-7, 8-9, 10-11, 12-13, 14-15, 16-17, 18-21, 21-*
 * the following bits are set:
 *
 *   31     24        16        8         0
 *   |      |         |         |         |
 *   oooooooo  oo1oo1o1  o1o1o1o1  ooooooo1
 *
 * A value of 0 means that the exchange does not support the extension for
 * age-restriction.
 */
struct TALER_AgeMask
{
  uint32_t bits;
};

/**
 * @brief Age commitment of a coin.
 */
struct TALER_AgeCommitmentHash
{
  /**
   * The commitment is a SHA-256 hash code.
   */
  struct GNUNET_ShortHashCode shash;
};

/**
 * @brief Signature of an age with the private key for the corresponding age group of an age commitment.
 */
struct TALER_AgeAttestation
{
#ifdef AGE_RESTRICTION_WITH_ECDSA
  struct GNUNET_CRYPTO_EcdsaSignature signature;
#else
  struct GNUNET_CRYPTO_Edx25519Signature signature;
#endif
};

extern const struct TALER_AgeCommitmentHash TALER_ZeroAgeCommitmentHash;
#define TALER_AgeCommitmentHash_isNullOrZero(ph) ((NULL == ph) || \
                                                  (0 == memcmp (ph, \
                                                                & \
                                                                TALER_ZeroAgeCommitmentHash, \
                                                                sizeof(struct \
                                                                       TALER_AgeCommitmentHash))))

/**
 * @brief Type of public signing keys for verifying blindly signed coins.
 */
struct TALER_DenominationPublicKey
{

  /**
   * Type of the public key.
   */
  enum TALER_DenominationCipher cipher;

  /**
   * Age restriction mask used for the key.
   */
  struct TALER_AgeMask age_mask;

  /**
   * Details, depending on @e cipher.
   */
  union
  {
    /**
     * If we use #TALER_DENOMINATION_CS in @a cipher.
     */
    struct GNUNET_CRYPTO_CsPublicKey cs_public_key;

    /**
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaPublicKey *rsa_public_key;

  } details;
};


/**
 * @brief Type of private signing keys for blind signing of coins.
 */
struct TALER_DenominationPrivateKey
{

  /**
   * Type of the public key.
   */
  enum TALER_DenominationCipher cipher;

  /**
   * Details, depending on @e cipher.
   */
  union
  {
    /**
     * If we use #TALER_DENOMINATION_CS in @a cipher.
     */
    struct GNUNET_CRYPTO_CsPrivateKey cs_private_key;

    /**
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaPrivateKey *rsa_private_key;

  } details;
};

/**
 * @brief RSA Parameters to create blinded signature
 *
 */
struct TALER_BlindedRsaPlanchet
{
  /**
   * Blinded message to be signed
   * Note: is malloc()'ed!
   */
  void *blinded_msg;

  /**
   * Size of the @e blinded_msg to be signed.
   */
  size_t blinded_msg_size;
};


/**
 * Withdraw nonce for CS denominations
 */
struct TALER_CsNonce
{
  /**
   * 32 bit nonce to include in withdrawals when using CS.
   */
  struct GNUNET_CRYPTO_CsNonce nonce;
};


/**
 * @brief CS Parameters to create blinded signature
 */
struct TALER_BlindedCsPlanchet
{
  /**
   * The Clause Schnorr c_0 and c_1 containing the blinded message
   */
  struct GNUNET_CRYPTO_CsC c[2];

  /**
   * Public nonce.
   */
  struct TALER_CsNonce nonce;
};


/**
 * @brief Type including Parameters to create blinded signature
 */
struct TALER_BlindedPlanchet
{
  /**
   * Type of the sign blinded message
   */
  enum TALER_DenominationCipher cipher;

  /**
   * Details, depending on @e cipher.
   */
  union
  {
    /**
     * If we use #TALER_DENOMINATION_CS in @a cipher.
     */
    struct TALER_BlindedCsPlanchet cs_blinded_planchet;

    /**
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct TALER_BlindedRsaPlanchet rsa_blinded_planchet;

  } details;
};


/**
 * Pair of Public R values for Cs denominations
 */
struct TALER_DenominationCSPublicRPairP
{
  struct GNUNET_CRYPTO_CsRPublic r_pub[2];
};


/**
 * Secret r for Cs denominations
 */
struct TALER_DenominationCSPrivateRPairP
{
  struct GNUNET_CRYPTO_CsRSecret r[2];
};


/**
 * @brief Public information about a coin (including the public key
 * of the coin, the denomination key and the signature with
 * the denomination key).
 */
struct TALER_CoinPublicInfo
{
  /**
   * The coin's public key.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Hash of the public key representing the denomination of the coin that is
   * being deposited.
   */
  struct TALER_DenominationHashP denom_pub_hash;

  /**
   * Hash of the age commitment.  If no age commitment was provided, it must be
   * set to all zeroes.
   */
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * True, if age commitment is not applicable.
   */
  bool no_age_commitment;

  /**
   * (Unblinded) signature over @e coin_pub with @e denom_pub,
   * which demonstrates that the coin is valid.
   */
  struct TALER_DenominationSignature denom_sig;
};


/**
 * Details for one of the /deposit operations that the
 * exchange combined into a single wire transfer.
 */
struct TALER_TrackTransferDetails
{
  /**
   * Hash of the proposal data.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Which coin was deposited?
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Value of the deposit (including fee).
   */
  struct TALER_Amount coin_value;

  /**
   * Fee charged by the exchange for the deposit.
   */
  struct TALER_Amount coin_fee;

};


/**
 * @brief Type of algorithm specific Values for withdrawal
 */
struct TALER_ExchangeWithdrawValues
{

  /**
   * Type of the signature.
   */
  enum TALER_DenominationCipher cipher;

  /**
   * Details, depending on @e cipher.
   */
  union
  {
    /**
     * If we use #TALER_DENOMINATION_CS in @a cipher.
     */
    struct TALER_DenominationCSPublicRPairP cs_values;

  } details;

};


/**
 * Free internals of @a denom_pub, but not @a denom_pub itself.
 *
 * @param[in] denom_pub key to free
 */
void
TALER_denom_pub_free (struct TALER_DenominationPublicKey *denom_pub);


/**
 * Create private key for a Taler coin.
 * @param ps planchet secret to derive coin priv key
 * @param alg_values includes algorithm specific values
 * @param[out] coin_priv private key to initialize
 */
void
TALER_planchet_setup_coin_priv (
  const struct TALER_PlanchetMasterSecretP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_CoinSpendPrivateKeyP *coin_priv);


/**
 * @brief Method to derive withdraw /csr nonce
 *
 * @param ps planchet secrets of the coin
 * @param[out] nonce withdraw nonce included in the request to generate R_0 and R_1
 */
void
TALER_cs_withdraw_nonce_derive (
  const struct TALER_PlanchetMasterSecretP *ps,
  struct TALER_CsNonce *nonce);


/**
 * @brief Method to derive /csr nonce
 * to be used during refresh/melt operation.
 *
 * @param rms secret input for the refresh operation
 * @param idx index of the fresh coin
 * @param[out] nonce set to nonce included in the request to generate R_0 and R_1
 */
void
TALER_cs_refresh_nonce_derive (
  const struct TALER_RefreshMasterSecretP *rms,
  uint32_t idx,
  struct TALER_CsNonce *nonce);


/**
 * Initialize denomination public-private key pair.
 *
 * For #TALER_DENOMINATION_RSA, an additional "unsigned int"
 * argument with the number of bits for 'n' (e.g. 2048) must
 * be passed.
 *
 * @param[out] denom_priv where to write the private key
 * @param[out] denom_pub where to write the public key
 * @param cipher which type of cipher to use
 * @param ... RSA key size (eg. 2048/3072/4096)
 * @return #GNUNET_OK on success, #GNUNET_NO if parameters were invalid
 */
enum GNUNET_GenericReturnValue
TALER_denom_priv_create (struct TALER_DenominationPrivateKey *denom_priv,
                         struct TALER_DenominationPublicKey *denom_pub,
                         enum TALER_DenominationCipher cipher,
                         ...);


/**
 * Free internals of @a denom_priv, but not @a denom_priv itself.
 *
 * @param[in] denom_priv key to free
 */
void
TALER_denom_priv_free (struct TALER_DenominationPrivateKey *denom_priv);


/**
 * Free internals of @a denom_sig, but not @a denom_sig itself.
 *
 * @param[in] denom_sig signature to free
 */
void
TALER_denom_sig_free (struct TALER_DenominationSignature *denom_sig);


/**
 * Blind coin for blind signing with @a dk using blinding secret @a coin_bks.
 *
 * NOTE: As a particular oddity, the @a blinded_planchet is only partially
 * initialized by this function in the case of CS-denominations. Here, the
 * 'nonce' must be initialized separately!
 *
 * @param dk denomination public key to blind for
 * @param coin_bks blinding secret to use
 * @param age_commitment_hash hash of the age commitment to be used for the coin. NULL if no commitment is made.
 * @param coin_pub public key of the coin to blind
 * @param alg_values algorithm specific values to blind the planchet
 * @param[out] c_hash resulting hashed coin
 * @param[out] blinded_planchet planchet data to initialize
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_blind (const struct TALER_DenominationPublicKey *dk,
                   const union TALER_DenominationBlindingKeyP *coin_bks,
                   const struct TALER_AgeCommitmentHash *age_commitment_hash,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   const struct TALER_ExchangeWithdrawValues *alg_values,
                   struct TALER_CoinPubHashP *c_hash,
                   struct TALER_BlindedPlanchet *blinded_planchet);


/**
 * Create blinded signature.
 *
 * @param[out] denom_sig where to write the signature
 * @param denom_priv private key to use for signing
 * @param for_melt true to use the HKDF for melt
 * @param blinded_planchet the planchet already blinded
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_sign_blinded (struct TALER_BlindedDenominationSignature *denom_sig,
                          const struct TALER_DenominationPrivateKey *denom_priv,
                          bool for_melt,
                          const struct TALER_BlindedPlanchet *blinded_planchet);


/**
 * Unblind blinded signature.
 *
 * @param[out] denom_sig where to write the unblinded signature
 * @param bdenom_sig the blinded signature
 * @param bks blinding secret to use
 * @param c_hash hash of the coin's public key for verification of the signature
 * @param alg_values algorithm specific values
 * @param denom_pub public key used for signing
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_sig_unblind (
  struct TALER_DenominationSignature *denom_sig,
  const struct TALER_BlindedDenominationSignature *bdenom_sig,
  const union TALER_DenominationBlindingKeyP *bks,
  const struct TALER_CoinPubHashP *c_hash,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  const struct TALER_DenominationPublicKey *denom_pub);


/**
 * Free internals of @a denom_sig, but not @a denom_sig itself.
 *
 * @param[in] denom_sig signature to free
 */
void
TALER_blinded_denom_sig_free (
  struct TALER_BlindedDenominationSignature *denom_sig);


/**
 * Compute the hash of the given @a denom_pub.
 *
 * @param denom_pub public key to hash
 * @param[out] denom_hash resulting hash value
 */
void
TALER_denom_pub_hash (const struct TALER_DenominationPublicKey *denom_pub,
                      struct TALER_DenominationHashP *denom_hash);


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_src public key to copy
 */
void
TALER_denom_pub_deep_copy (struct TALER_DenominationPublicKey *denom_dst,
                           const struct TALER_DenominationPublicKey *denom_src);


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_src public key to copy
 */
void
TALER_denom_sig_deep_copy (struct TALER_DenominationSignature *denom_dst,
                           const struct TALER_DenominationSignature *denom_src);


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_src public key to copy
 */
void
TALER_blinded_denom_sig_deep_copy (
  struct TALER_BlindedDenominationSignature *denom_dst,
  const struct TALER_BlindedDenominationSignature *denom_src);


/**
 * Compare two denomination public keys.
 *
 * @param denom1 first key
 * @param denom2 second key
 * @return 0 if the keys are equal, otherwise -1 or 1
 */
int
TALER_denom_pub_cmp (const struct TALER_DenominationPublicKey *denom1,
                     const struct TALER_DenominationPublicKey *denom2);


/**
 * Compare two denomination signatures.
 *
 * @param sig1 first signature
 * @param sig2 second signature
 * @return 0 if the keys are equal, otherwise -1 or 1
 */
int
TALER_denom_sig_cmp (const struct TALER_DenominationSignature *sig1,
                     const struct TALER_DenominationSignature *sig2);


/**
 * Compare two blinded denomination signatures.
 *
 * @param sig1 first signature
 * @param sig2 second signature
 * @return 0 if the keys are equal, otherwise -1 or 1
 */
int
TALER_blinded_denom_sig_cmp (
  const struct TALER_BlindedDenominationSignature *sig1,
  const struct TALER_BlindedDenominationSignature *sig2);


/**
 * Compare two blinded planchets.
 *
 * @param bp1 first blinded planchet
 * @param bp2 second blinded planchet
 * @return 0 if the keys are equal, otherwise -1 or 1
 */
int
TALER_blinded_planchet_cmp (
  const struct TALER_BlindedPlanchet *bp1,
  const struct TALER_BlindedPlanchet *bp2);


/**
 * Obtain denomination public key from a denomination private key.
 *
 * @param denom_priv private key to convert
 * @param age_mask age mask to be applied
 * @param[out] denom_pub where to return the public key
 */
void
TALER_denom_priv_to_pub (const struct TALER_DenominationPrivateKey *denom_priv,
                         const struct TALER_AgeMask age_mask,
                         struct TALER_DenominationPublicKey *denom_pub);


/**
 * Verify signature made with a denomination public key
 * over a coin.
 *
 * @param denom_pub public denomination key
 * @param denom_sig signature made with the private key
 * @param c_hash hash over the coin
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_denom_pub_verify (const struct TALER_DenominationPublicKey *denom_pub,
                        const struct TALER_DenominationSignature *denom_sig,
                        const struct TALER_CoinPubHashP *c_hash);


/**
 * Check if a coin is valid; that is, whether the denomination key exists,
 * is not expired, and the signature is correct.
 *
 * @param coin_public_info the coin public info to check for validity
 * @param denom_pub denomination key, must match @a coin_public_info's `denom_pub_hash`
 * @return #GNUNET_YES if the coin is valid,
 *         #GNUNET_NO if it is invalid
 *         #GNUNET_SYSERR if an internal error occurred
 */
enum GNUNET_GenericReturnValue
TALER_test_coin_valid (const struct TALER_CoinPublicInfo *coin_public_info,
                       const struct TALER_DenominationPublicKey *denom_pub);


/**
 * Compute the hash of a blinded coin.
 *
 * @param blinded_planchet blinded planchet
 * @param denom_hash hash of the denomination publick key
 * @param[out] bch where to write the hash
 * @return #GNUNET_OK when successful, #GNUNET_SYSERR if an internal error occurred
 */
enum GNUNET_GenericReturnValue
TALER_coin_ev_hash (const struct TALER_BlindedPlanchet *blinded_planchet,
                    const struct TALER_DenominationHashP *denom_hash,
                    struct TALER_BlindedCoinHashP *bch);


/**
 * Compute the hash of a coin.
 *
 * @param coin_pub public key of the coin
 * @param age_commitment_hash hash of the age commitment vector. NULL, if no age commitment was set
 * @param[out] coin_h where to write the hash
 */
void
TALER_coin_pub_hash (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const struct TALER_AgeCommitmentHash *age_commitment_hash,
                     struct TALER_CoinPubHashP *coin_h);


/**
 * Compute the hash of a payto URI.
 *
 * @param payto URI to hash
 * @param[out] h_payto where to write the hash
 */
void
TALER_payto_hash (const char *payto,
                  struct TALER_PaytoHashP *h_payto);

/**
 * Details about a planchet that the customer wants to obtain
 * a withdrawal authorization.  This is the information that
 * will need to be sent to the exchange to obtain the blind
 * signature required to turn a planchet into a coin.
 */
struct TALER_PlanchetDetail
{
  /**
   * Hash of the denomination public key.
   */
  struct TALER_DenominationHashP denom_pub_hash;

  /**
   * The blinded planchet
   */
  struct TALER_BlindedPlanchet blinded_planchet;
};


/**
 * Information about a (fresh) coin, returned from the API when we
 * finished creating a coin.  Note that @e sig needs to be freed
 * using the appropriate code.
 */
struct TALER_FreshCoin
{

  /**
   * The exchange's signature over the coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * The coin's private key.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Optional hash of an age commitment bound to this coin, maybe NULL.
   */
  const struct TALER_AgeCommitmentHash *h_age_commitment;
};


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Secret used to decrypt the key to decrypt link secrets.
 */
struct TALER_TransferSecretP
{
  /**
   * Secret used to derive private inputs for refreshed coins.
   * Must be (currently) a hash as this is what
   * GNUNET_CRYPTO_ecc_ecdh() returns to us.
   */
  struct GNUNET_HashCode key;
};


/**
 * Length of the raw value in the Taler wire transfer identifier
 * (in binary representation).
 */
#define TALER_BANK_TRANSFER_IDENTIFIER_LEN 32

/**
 * #TALER_BANK_TRANSFER_IDENTIFIER_LEN as a string.
 */
#define TALER_BANK_TRANSFER_IDENTIFIER_LEN_STR "32"


/**
 * Raw value of a wire transfer subjects, without the checksum.
 */
struct TALER_WireTransferIdentifierRawP
{

  /**
   * Raw value.  Note that typical payment systems (SEPA, ACH) support
   * at least two lines of 27 ASCII characters to encode a transaction
   * subject or "details", for a total of 54 characters.  (The payment
   * system protocols often support more lines, but the forms presented
   * to customers are usually limited to 54 characters.)
   *
   * With a Base32-encoding of 5 bit per character, this gives us 270
   * bits or (rounded down) 33 bytes.  So we use the first 32 bytes to
   * encode the actual value (i.e. a 256-bit / 32-byte public key or
   * a hash code), and the last byte for a minimalistic checksum.
   */
  uint8_t raw[TALER_BANK_TRANSFER_IDENTIFIER_LEN];
};


/**
 * Raw value of a wire transfer subject for a wad.
 */
struct TALER_WadIdentifierP
{

  /**
   * Wad identifier, in binary encoding.
   */
  uint8_t raw[24];
};


/**
 * Binary information encoded in Crockford's Base32 in wire transfer
 * subjects of transfers from Taler to a merchant.  The actual value
 * is chosen by the exchange and has no particular semantics, other than
 * being unique so that the exchange can lookup details about the wire
 * transfer when needed.
 */
struct TALER_WireTransferIdentifierP
{

  /**
   * Raw value.
   */
  struct TALER_WireTransferIdentifierRawP raw;

  /**
   * Checksum using CRC8 over the @e raw data.
   */
  uint8_t crc8;
};


GNUNET_NETWORK_STRUCT_END


/**
 * Setup information for a fresh coin, deriving the coin planchet secrets from
 * which we will later derive the private key and the blinding factor.  The
 * planchet secrets derivation is based on the @a secret_seed with a KDF
 * salted by the @a coin_num_salt.
 *
 * @param secret_seed seed to use for KDF to derive coin keys
 * @param coin_num_salt number of the coin to include in KDF
 * @param[out] ps value to initialize
 */
void
TALER_transfer_secret_to_planchet_secret (
  const struct TALER_TransferSecretP *secret_seed,
  uint32_t coin_num_salt,
  struct TALER_PlanchetMasterSecretP *ps);


/**
 * Derive the @a coin_num transfer private key @a tpriv from a refresh from
 * the @a rms seed and the @a old_coin_pub of the refresh operation.  The
 * transfer private key derivation is based on the @a ps with a KDF salted by
 * the @a coin_num.
 *
 * @param rms seed to use for KDF to derive transfer keys
 * @param old_coin_priv private key of the old coin
 * @param cnc_num cut and choose number to include in KDF
 * @param[out] tpriv value to initialize
 */
void
TALER_planchet_secret_to_transfer_priv (
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_CoinSpendPrivateKeyP *old_coin_priv,
  uint32_t cnc_num,
  struct TALER_TransferPrivateKeyP *tpriv);


/**
 * Setup secret seed information for fresh coins to be
 * withdrawn.
 *
 * @param[out] ps value to initialize
 */
void
TALER_planchet_master_setup_random (
  struct TALER_PlanchetMasterSecretP *ps);


/**
 * Setup secret seed for fresh coins to be refreshed.
 *
 * @param[out] rms value to initialize
 */
void
TALER_refresh_master_setup_random (
  struct TALER_RefreshMasterSecretP *rms);


/**
 * Create a blinding secret @a bks given the client's @a ps and the alg_values
 * from the exchange.
 *
 * @param ps secret to derive blindings from
 * @param alg_values withdraw values containing cipher and additional CS values
 * @param[out] bks blinding secrets
 */
void
TALER_planchet_blinding_secret_create (
  const struct TALER_PlanchetMasterSecretP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  union TALER_DenominationBlindingKeyP *bks);


/**
 * Prepare a planchet for withdrawal.  Creates and blinds a coin.
 *
 * @param dk denomination key for the coin to be created
 * @param alg_values algorithm specific values
 * @param bks blinding secrets
 * @param coin_priv coin private key
 * @param ach hash of age commitment to bind to this coin, maybe NULL
 * @param[out] c_hash set to the hash of the public key of the coin (needed later)
 * @param[out] pd set to the planchet detail for TALER_MERCHANT_tip_pickup() and
 *               other withdraw operations, `pd->blinded_planchet.cipher` will be set
 *               to cipher from @a dk
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_ExchangeWithdrawValues *alg_values,
                        const union TALER_DenominationBlindingKeyP *bks,
                        const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                        const struct TALER_AgeCommitmentHash *ach,
                        struct TALER_CoinPubHashP *c_hash,
                        struct TALER_PlanchetDetail *pd);


/**
 * Frees blinded message inside blinded planchet depending on `blinded_planchet->cipher`.
 * Does not free the @a blinded_planchet itself!
 *
 * @param[in] blinded_planchet blinded planchet
 */
void
TALER_blinded_planchet_free (struct TALER_BlindedPlanchet *blinded_planchet);


/**
 * Frees blinded message inside planchet detail @a pd.
 *
 * @param[in] pd planchet detail to free
 */
void
TALER_planchet_detail_free (struct TALER_PlanchetDetail *pd);


/**
 * Obtain a coin from the planchet's secrets and the blind signature
 * of the exchange.
 *
 * @param dk denomination key, must match what was given to #TALER_planchet_prepare()
 * @param blind_sig blind signature from the exchange
 * @param bks blinding key secret
 * @param coin_priv private key of the coin
 * @param ach hash of age commitment that is bound to this coin, maybe NULL
 * @param c_hash hash of the coin's public key for verification of the signature
 * @param alg_values values obtained from the exchange for the withdrawal
 * @param[out] coin set to the details of the fresh coin
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_planchet_to_coin (
  const struct TALER_DenominationPublicKey *dk,
  const struct TALER_BlindedDenominationSignature *blind_sig,
  const union TALER_DenominationBlindingKeyP *bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  const struct TALER_AgeCommitmentHash *ach,
  const struct TALER_CoinPubHashP *c_hash,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_FreshCoin *coin);


/**
 * Add the hash of the @a bp (in some canonicalized form)
 * to the @a hash_context.
 *
 * @param bp blinded planchet to hash
 * @param[in,out] hash_context hash context to use
 */
void
TALER_blinded_planchet_hash_ (const struct TALER_BlindedPlanchet *bp,
                              struct GNUNET_HashContext *hash_context);


/**
 * Given the coin and the transfer private keys, compute the
 * transfer secret.  (Technically, we only need one of the two
 * private keys, but the caller currently trivially only has
 * the two private keys, so we derive one of the public keys
 * internally to this function.)
 *
 * @param coin_priv coin key
 * @param trans_priv transfer private key
 * @param[out] ts computed transfer secret
 */
void
TALER_link_derive_transfer_secret (
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  const struct TALER_TransferPrivateKeyP *trans_priv,
  struct TALER_TransferSecretP *ts);


/**
 * Decrypt the shared @a secret from the information in the
 * @a trans_priv and @a coin_pub.
 *
 * @param trans_priv transfer private key
 * @param coin_pub coin public key
 * @param[out] transfer_secret set to the shared secret
 */
void
TALER_link_reveal_transfer_secret (
  const struct TALER_TransferPrivateKeyP *trans_priv,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_TransferSecretP *transfer_secret);


/**
 * Decrypt the shared @a secret from the information in the
 * @a trans_priv and @a coin_pub.
 *
 * @param trans_pub transfer private key
 * @param coin_priv coin public key
 * @param[out] transfer_secret set to the shared secret
 */
void
TALER_link_recover_transfer_secret (
  const struct TALER_TransferPublicKeyP *trans_pub,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_TransferSecretP *transfer_secret);


/**
 * Information about a coin to be created during a refresh operation.
 */
struct TALER_RefreshCoinData
{

  /**
   * The denomination's public key.
   */
  const struct TALER_DenominationPublicKey *dk;

  /**
   * The blinded planchet (details depend on cipher).
   */
  struct TALER_BlindedPlanchet blinded_planchet;

};


/**
 * One of the #TALER_CNC_KAPPA commitments.
 */
struct TALER_RefreshCommitmentEntry
{
  /**
   * Transfer public key of this commitment.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Array of @e num_new_coins new coins to be created.
   */
  struct TALER_RefreshCoinData *new_coins;
};


/**
 * Compute the commitment for a /refresh/melt operation from
 * the respective public inputs.
 *
 * @param[out] rc set to the value the wallet must commit to
 * @param kappa number of transfer public keys involved (must be #TALER_CNC_KAPPA)
 * @param rms refresh master secret to include, can be NULL!
 * @param num_new_coins number of new coins to be created
 * @param rcs array of @a kappa commitments
 * @param coin_pub public key of the coin to be melted
 * @param amount_with_fee amount to be melted, including fee
 */
void
TALER_refresh_get_commitment (struct TALER_RefreshCommitmentP *rc,
                              uint32_t kappa,
                              const struct TALER_RefreshMasterSecretP *rms,
                              uint32_t num_new_coins,
                              const struct TALER_RefreshCommitmentEntry *rcs,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct TALER_Amount *amount_with_fee);


/**
 * Encrypt contract for transmission to a party that will
 * merge it into a reserve.
 *
 * @param purse_pub public key of the purse
 * @param contract_priv private key of the contract
 * @param merge_priv merge capability to include
 * @param contract_terms contract terms to encrypt
 * @param[out] econtract set to encrypted contract
 * @param[out] econtract_size set to number of bytes in @a econtract
 */
void
TALER_CRYPTO_contract_encrypt_for_merge (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const json_t *contract_terms,
  void **econtract,
  size_t *econtract_size);


/**
 * Decrypt contract for the party that will
 * merge it into a reserve.
 *
 * @param purse_pub public key of the purse
 * @param contract_priv private key of the contract
 * @param econtract encrypted contract
 * @param econtract_size  number of bytes in @a econtract
 * @param[out] merge_priv set to merge capability
 * @return decrypted contract terms, or NULL on failure
 */
json_t *
TALER_CRYPTO_contract_decrypt_for_merge (
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const void *econtract,
  size_t econtract_size,
  struct TALER_PurseMergePrivateKeyP *merge_priv);


/**
 * Encrypt contract for transmission to a party that will
 * pay for it.
 *
 * @param purse_pub public key of the purse
 * @param contract_priv private key of the contract
 * @param contract_terms contract terms to encrypt
 * @param[out] econtract set to encrypted contract
 * @param[out] econtract_size set to number of bytes in @a econtract
 */
void
TALER_CRYPTO_contract_encrypt_for_deposit (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const json_t *contract_terms,
  void **econtract,
  size_t *econtract_size);


/**
 * Decrypt contract for the party that will pay for it.
 *
 * @param contract_priv private key of the contract
 * @param econtract encrypted contract
 * @param econtract_size  number of bytes in @a econtract
 * @return decrypted contract terms, or NULL on failure
 */
json_t *
TALER_CRYPTO_contract_decrypt_for_deposit (
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const void *econtract,
  size_t econtract_size);


/* **************** Helper-based RSA operations **************** */

/**
 * Handle for talking to an Denomination key signing helper.
 */
struct TALER_CRYPTO_RsaDenominationHelper;

/**
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.
 *
 * @param cls closure
 * @param section_name name of the denomination type in the configuration;
 *                 NULL if the key has been revoked or purged
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param h_rsa hash of the RSA @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
typedef void
(*TALER_CRYPTO_RsaDenominationKeyStatusCallback)(
  void *cls,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct TALER_RsaPubHashP *h_rsa,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig);


/**
 * Initiate connection to an denomination key helper.
 *
 * @param cfg configuration to use
 * @param dkc function to call with key information
 * @param dkc_cls closure for @a dkc
 * @return NULL on error (such as bad @a cfg).
 */
struct TALER_CRYPTO_RsaDenominationHelper *
TALER_CRYPTO_helper_rsa_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  TALER_CRYPTO_RsaDenominationKeyStatusCallback dkc,
  void *dkc_cls);


/**
 * Function to call to 'poll' for updates to the available key material.
 * Should be called whenever it is important that the key material status is
 * current, like when handling a "/keys" request.  This function basically
 * briefly checks if there are messages from the helper announcing changes to
 * denomination keys.
 *
 * @param dh helper process connection
 */
void
TALER_CRYPTO_helper_rsa_poll (struct TALER_CRYPTO_RsaDenominationHelper *dh);


/**
 * Information needed for an RSA signature request.
 */
struct TALER_CRYPTO_RsaSignRequest
{
  /**
   * Hash of the RSA public key.
   */
  const struct TALER_RsaPubHashP *h_rsa;

  /**
   * Message to be (blindly) signed.
   */
  const void *msg;

  /**
   * Number of bytes in @e msg.
   */
  size_t msg_size;
};


/**
 * Request helper @a dh to sign message in @a rsr using the public key
 * corresponding to the key in @a rsr.
 *
 * This operation will block until the signature has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param dh helper process connection
 * @param rsr details about the requested signature
 * @param[out] bs set to the blind signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_rsa_sign (
  struct TALER_CRYPTO_RsaDenominationHelper *dh,
  const struct TALER_CRYPTO_RsaSignRequest *rsr,
  struct TALER_BlindedDenominationSignature *bs);


/**
 * Request helper @a dh to batch sign messages in @a rsrs using the public key
 * corresponding to the keys in @a rsrs.
 *
 * This operation will block until all the signatures have been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param dh helper process connection
 * @param rsrs array with details about the requested signatures
 * @param rsrs_length length of the @a rsrs array
 * @param[out] bss array set to the blind signatures, must be of length @a rsrs_length!
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_rsa_batch_sign (
  struct TALER_CRYPTO_RsaDenominationHelper *dh,
  const struct TALER_CRYPTO_RsaSignRequest *rsrs,
  unsigned int rsrs_length,
  struct TALER_BlindedDenominationSignature *bss);


/**
 * Ask the helper to revoke the public key associated with @a h_denom_pub.
 * Will cause the helper to tell all clients that the key is now unavailable,
 * and to create a replacement key.
 *
 * This operation will block until the revocation request has been
 * transmitted.  Should this process receive a signal (that is not ignored)
 * while the operation is pending, the operation may fail. If the key is
 * unknown, this function will also appear to have succeeded. To be sure that
 * the revocation worked, clients must watch the denomination key status
 * callback.
 *
 * @param dh helper to process connection
 * @param h_rsa hash of the RSA public key to revoke
 */
void
TALER_CRYPTO_helper_rsa_revoke (
  struct TALER_CRYPTO_RsaDenominationHelper *dh,
  const struct TALER_RsaPubHashP *h_rsa);


/**
 * Close connection to @a dh.
 *
 * @param[in] dh connection to close
 */
void
TALER_CRYPTO_helper_rsa_disconnect (
  struct TALER_CRYPTO_RsaDenominationHelper *dh);

/* **************** Helper-based CS operations **************** */

/**
 * Handle for talking to an Denomination key signing helper.
 */
struct TALER_CRYPTO_CsDenominationHelper;

/**
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.
 *
 * @param cls closure
 * @param section_name name of the denomination type in the configuration;
 *                 NULL if the key has been revoked or purged
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param h_cs hash of the CS @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
typedef void
(*TALER_CRYPTO_CsDenominationKeyStatusCallback)(
  void *cls,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct TALER_CsPubHashP *h_cs,
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig);


/**
 * Initiate connection to an denomination key helper.
 *
 * @param cfg configuration to use
 * @param dkc function to call with key information
 * @param dkc_cls closure for @a dkc
 * @return NULL on error (such as bad @a cfg).
 */
struct TALER_CRYPTO_CsDenominationHelper *
TALER_CRYPTO_helper_cs_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  TALER_CRYPTO_CsDenominationKeyStatusCallback dkc,
  void *dkc_cls);


/**
 * Function to call to 'poll' for updates to the available key material.
 * Should be called whenever it is important that the key material status is
 * current, like when handling a "/keys" request.  This function basically
 * briefly checks if there are messages from the helper announcing changes to
 * denomination keys.
 *
 * @param dh helper process connection
 */
void
TALER_CRYPTO_helper_cs_poll (struct TALER_CRYPTO_CsDenominationHelper *dh);


/**
 * Request helper @a dh to sign @a msg using the public key corresponding to
 * @a h_denom_pub.
 *
 * This operation will block until the signature has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param dh helper process connection
 * @param h_cs hash of the CS public key to use to sign
 * @param blinded_planchet blinded planchet containing c and nonce
 * @param[out] bs set to the blind signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_sign_melt (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CsPubHashP *h_cs,
  const struct TALER_BlindedCsPlanchet *blinded_planchet,
  struct TALER_BlindedDenominationSignature *bs);


/**
 * Request helper @a dh to sign @a msg using the public key corresponding to
 * @a h_denom_pub.
 *
 * This operation will block until the signature has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param dh helper process connection
 * @param h_cs hash of the CS public key to use to sign
 * @param blinded_planchet blinded planchet containing c and nonce
 * @param[out] bs set to the blind signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_sign_withdraw (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CsPubHashP *h_cs,
  const struct TALER_BlindedCsPlanchet *blinded_planchet,
  struct TALER_BlindedDenominationSignature *bs);


/**
 * Ask the helper to revoke the public key associated with @a h_cs.
 * Will cause the helper to tell all clients that the key is now unavailable,
 * and to create a replacement key.
 *
 * This operation will block until the revocation request has been
 * transmitted.  Should this process receive a signal (that is not ignored)
 * while the operation is pending, the operation may fail. If the key is
 * unknown, this function will also appear to have succeeded. To be sure that
 * the revocation worked, clients must watch the denomination key status
 * callback.
 *
 * @param dh helper to process connection
 * @param h_cs hash of the CS public key to revoke
 */
void
TALER_CRYPTO_helper_cs_revoke (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CsPubHashP *h_cs);


/**
 * Ask the helper to derive R using the @a nonce and denomination key
 * associated with @a h_cs.
 *
 * This operation will block until the R has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param dh helper to process connection
 * @param h_cs hash of the CS public key to revoke
 * @param nonce witdhraw nonce
 * @param[out] crp set to the pair of R values
 * @return set to the error code (or #TALER_EC_NONE on success)
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_r_derive_withdraw (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CsPubHashP *h_cs,
  const struct TALER_CsNonce *nonce,
  struct TALER_DenominationCSPublicRPairP *crp);


/**
 * Ask the helper to derive R using the @a nonce and denomination key
 * associated with @a h_cs.
 *
 * This operation will block until the R has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param dh helper to process connection
 * @param h_cs hash of the CS public key to revoke
 * @param nonce witdhraw nonce
 * @param[out] crp set to the pair of R values
 * @return set to the error code (or #TALER_EC_NONE on success)
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_cs_r_derive_melt (
  struct TALER_CRYPTO_CsDenominationHelper *dh,
  const struct TALER_CsPubHashP *h_cs,
  const struct TALER_CsNonce *nonce,
  struct TALER_DenominationCSPublicRPairP *crp);


/**
 * Close connection to @a dh.
 *
 * @param[in] dh connection to close
 */
void
TALER_CRYPTO_helper_cs_disconnect (
  struct TALER_CRYPTO_CsDenominationHelper *dh);

/**
 * Handle for talking to an online key signing helper.
 */
struct TALER_CRYPTO_ExchangeSignHelper;

/**
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.
 *
 * @param cls closure
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param exchange_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
typedef void
(*TALER_CRYPTO_ExchangeKeyStatusCallback)(
  void *cls,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Relative validity_duration,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_SecurityModulePublicKeyP *sm_pub,
  const struct TALER_SecurityModuleSignatureP *sm_sig);


/**
 * Initiate connection to an online signing key helper.
 *
 * @param cfg configuration to use
 * @param ekc function to call with key information
 * @param ekc_cls closure for @a ekc
 * @return NULL on error (such as bad @a cfg).
 */
struct TALER_CRYPTO_ExchangeSignHelper *
TALER_CRYPTO_helper_esign_connect (
  const struct GNUNET_CONFIGURATION_Handle *cfg,
  TALER_CRYPTO_ExchangeKeyStatusCallback ekc,
  void *ekc_cls);


/**
 * Function to call to 'poll' for updates to the available key material.
 * Should be called whenever it is important that the key material status is
 * current, like when handling a "/keys" request.  This function basically
 * briefly checks if there are messages from the helper announcing changes to
 * exchange online signing keys.
 *
 * @param esh helper process connection
 */
void
TALER_CRYPTO_helper_esign_poll (struct TALER_CRYPTO_ExchangeSignHelper *esh);


/**
 * Request helper @a esh to sign @a msg using the current online
 * signing key.
 *
 * This operation will block until the signature has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param esh helper process connection
 * @param purpose message to sign (must extend beyond the purpose)
 * @param[out] exchange_pub set to the public key used for the signature upon success
 * @param[out] exchange_sig set to the signature upon success
 * @return the error code (or #TALER_EC_NONE on success)
 */
enum TALER_ErrorCode
TALER_CRYPTO_helper_esign_sign_ (
  struct TALER_CRYPTO_ExchangeSignHelper *esh,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_ExchangeSignatureP *exchange_sig);


/**
 * Request helper @a esh to sign @a msg using the current online
 * signing key.
 *
 * This operation will block until the signature has been obtained.  Should
 * this process receive a signal (that is not ignored) while the operation is
 * pending, the operation will fail.  Note that the helper may still believe
 * that it created the signature. Thus, signals may result in a small
 * differences in the signature counters.  Retrying in this case may work.
 *
 * @param esh helper process connection
 * @param ps message to sign (MUST begin with a purpose)
 * @param[out] epub set to the public key used for the signature upon success
 * @param[out] esig set to the signature upon success
 * @return the error code (or #TALER_EC_NONE on success)
 */
#define TALER_CRYPTO_helper_esign_sign(esh,ps,epub,esig) (         \
    /* check size is set correctly */                              \
    GNUNET_assert (ntohl ((ps)->purpose.size) == sizeof (*ps)),    \
    /* check 'ps' begins with the purpose */                       \
    GNUNET_static_assert (((void*) (ps)) ==                        \
                          ((void*) &(ps)->purpose)),               \
    TALER_CRYPTO_helper_esign_sign_ (esh,                          \
                                     &(ps)->purpose,               \
                                     epub,                         \
                                     esig) )


/**
 * Ask the helper to revoke the public key @a exchange_pub .
 * Will cause the helper to tell all clients that the key is now unavailable,
 * and to create a replacement key.
 *
 * This operation will block until the revocation request has been
 * transmitted.  Should this process receive a signal (that is not ignored)
 * while the operation is pending, the operation may fail. If the key is
 * unknown, this function will also appear to have succeeded. To be sure that
 * the revocation worked, clients must watch the signing key status callback.
 *
 * @param esh helper to process connection
 * @param exchange_pub the public key to revoke
 */
void
TALER_CRYPTO_helper_esign_revoke (
  struct TALER_CRYPTO_ExchangeSignHelper *esh,
  const struct TALER_ExchangePublicKeyP *exchange_pub);


/**
 * Close connection to @a esh.
 *
 * @param[in] esh connection to close
 */
void
TALER_CRYPTO_helper_esign_disconnect (
  struct TALER_CRYPTO_ExchangeSignHelper *esh);


/* ********************* wallet signing ************************** */


/**
 * Sign a request to create a purse.
 *
 * @param purse_expiration when should the purse expire
 * @param h_contract_terms contract the two parties agree on
 * @param merge_pub public key defining the merge capability
 * @param min_age age restriction to apply for deposits into the purse
 * @param amount total amount in the purse (including fees)
 * @param purse_priv key identifying the purse
 * @param[out] purse_sig resulting signature
 */
void
TALER_wallet_purse_create_sign (
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  uint32_t min_age,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Verify a purse creation request.
 *
 * @param purse_expiration when should the purse expire
 * @param h_contract_terms contract the two parties agree on
 * @param merge_pub public key defining the merge capability
 * @param min_age age restriction to apply for deposits into the purse
 * @param amount total amount in the purse (including fees)
 * @param purse_pub purse’s public key
 * @param purse_sig the signature made with purpose #TALER_SIGNATURE_WALLET_PURSE_CREATE
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_purse_create_verify (
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  uint32_t min_age,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Sign a request to upload an encrypted contract.
 *
 * @param econtract encrypted contract
 * @param econtract_size number of bytes in @a econtract
 * @param contract_pub public key for the DH-encryption
 * @param purse_priv key identifying the purse
 * @param[out] purse_sig resulting signature
 */
void
TALER_wallet_econtract_upload_sign (
  const void *econtract,
  size_t econtract_size,
  const struct TALER_ContractDiffiePublicP *contract_pub,
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Verify a signature over encrypted contract.
 *
 * @param econtract encrypted contract
 * @param econtract_size number of bytes in @a econtract
 * @param contract_pub public key for the DH-encryption
 * @param purse_pub purse’s public key
 * @param purse_sig the signature made with purpose #TALER_SIGNATURE_WALLET_PURSE_CREATE
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_econtract_upload_verify (
  const void *econtract,
  size_t econtract_size,
  const struct TALER_ContractDiffiePublicP *contract_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Verify a signature over encrypted contract.
 *
 * @param h_econtract hashed encrypted contract
 * @param contract_pub public key for the DH-encryption
 * @param purse_pub purse’s public key
 * @param purse_sig the signature made with purpose #TALER_SIGNATURE_WALLET_PURSE_CREATE
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_econtract_upload_verify2 (
  const struct GNUNET_HashCode *h_econtract,
  const struct TALER_ContractDiffiePublicP *contract_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Sign a request to inquire about a purse's status.
 *
 * @param purse_priv key identifying the purse
 * @param[out] purse_sig resulting signature
 */
void
TALER_wallet_purse_status_sign (
  const struct TALER_PurseContractPrivateKeyP *purse_priv,
  struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Verify a purse status request signature.
 *
 * @param purse_pub purse’s public key
 * @param purse_sig the signature made with purpose #TALER_SIGNATURE_WALLET_PURSE_STATUS
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_purse_status_verify (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig);


/**
 * Sign a request to deposit a coin into a purse.
 *
 * @param exchange_base_url URL of the exchange hosting the purse
 * @param purse_pub purse’s public key
 * @param amount amount of the coin's value to transfer to the purse
 * @param h_denom_pub hash of the coin's denomination
 * @param h_age_commitment hash of the coin's age commitment
 * @param coin_priv key identifying the coin to be deposited
 * @param[out] coin_sig resulting signature
 */
void
TALER_wallet_purse_deposit_sign (
  const char *exchange_base_url,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *amount,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify a purse deposit request.
 *
 * @param exchange_base_url URL of the exchange hosting the purse
 * @param purse_pub purse’s public key
 * @param amount amount of the coin's value to transfer to the purse
 * @param h_denom_pub hash of the coin's denomination
 * @param h_age_commitment hash of the coin's age commitment
 * @param coin_pub key identifying the coin that is being deposited
 * @param[out] coin_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_purse_deposit_verify (
  const char *exchange_base_url,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *amount,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign a request by a purse to merge it into an account.
 *
 * @param reserve_uri identifies the location of the reserve
 * @param merge_timestamp time when the merge happened
 * @param purse_pub key identifying the purse
 * @param merge_priv key identifying the merge capability
 * @param[out] merge_sig resulting signature
 */
void
TALER_wallet_purse_merge_sign (
  const char *reserve_uri,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  struct TALER_PurseMergeSignatureP *merge_sig);


/**
 * Verify a purse merge request.
 *
 * @param reserve_uri identifies the location of the reserve
 * @param merge_timestamp time when the merge happened
 * @param purse_pub public key of the purse to merge
 * @param merge_pub public key of the merge capability
 * @param merge_sig the signature made with purpose #TALER_SIGNATURE_WALLET_PURSE_MERGE
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_purse_merge_verify (
  const char *reserve_uri,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig);


/**
 * Flags for a merge signature.
 */
enum TALER_WalletAccountMergeFlags
{

  /**
   * A mode must be set. None is not a legal mode!
   */
  TALER_WAMF_MODE_NONE = 0,

  /**
   * We are merging a fully paid-up purse into a reserve.
   */
  TALER_WAMF_MODE_MERGE_FULLY_PAID_PURSE = 1,

  /**
   * We are creating a fresh purse, from the contingent
   * of free purses that our account brings.
   */
  TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA = 2,

  /**
   * The account owner is willing to pay the purse_fee for the purse to be
   * created from the account balance.
   */
  TALER_WAMF_MODE_CREATE_WITH_PURSE_FEE = 3,

  /**
   * Bitmask to AND the full flags with to get the mode.
   */
  TALER_WAMF_MERGE_MODE_MASK = 3

};


/**
 * Sign a request by an account to merge a purse.
 *
 * @param merge_timestamp time when the merge happened
 * @param purse_pub public key of the purse to merge
 * @param purse_expiration when should the purse expire
 * @param h_contract_terms contract the two parties agree on
 * @param amount total amount in the purse (including fees)
 * @param purse_fee purse fee the reserve will pay,
 *        only used if @a flags is #TALER_WAMF_MODE_CREATE_WITH_PURSE_FEE
 * @param min_age age restriction to apply for deposits into the purse
 * @param flags flags for the operation
 * @param reserve_priv key identifying the reserve
 * @param[out] reserve_sig resulting signature
 */
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
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify an account's request to merge a purse.
 *
 * @param merge_timestamp time when the merge happened
 * @param purse_pub public key of the purse to merge
 * @param purse_expiration when should the purse expire
 * @param h_contract_terms contract the two parties agree on
 * @param amount total amount in the purse (including fees)
 * @param purse_fee purse fee the reserve will pay,
 *        only used if @a flags is #TALER_WAMF_MODE_CREATE_WITH_PURSE_FEE
 * @param min_age age restriction to apply for deposits into the purse
 * @param flags flags for the operation
 * @param reserve_pub account’s public key
 * @param reserve_sig the signature made with purpose #TALER_SIGNATURE_WALLET_ACCOUNT_MERGE
 * @return #GNUNET_OK if the signature is valid
 */
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
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Sign a request to keep a reserve open.
 *
 * @param reserve_payment how much to pay from the
 *        reserve's own balance for opening the reserve
 * @param request_timestamp when was the request created
 * @param reserve_expiration desired expiration time for the reserve
 * @param purse_limit minimum number of purses the client
 *       wants to have concurrently open for this reserve
 * @param reserve_priv key identifying the reserve
 * @param[out] reserve_sig resulting signature
 */
void
TALER_wallet_reserve_open_sign (
  const struct TALER_Amount *reserve_payment,
  struct GNUNET_TIME_Timestamp request_timestamp,
  struct GNUNET_TIME_Timestamp reserve_expiration,
  uint32_t purse_limit,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify a request to keep a reserve open.
 *
 * @param reserve_payment how much to pay from the
 *        reserve's own balance for opening the reserve
 * @param request_timestamp when was the request created
 * @param reserve_expiration desired expiration time for the reserve
 * @param purse_limit minimum number of purses the client
 *       wants to have concurrently open for this reserve
 * @param reserve_pub key identifying the reserve
 * @param reserve_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_reserve_open_verify (
  const struct TALER_Amount *reserve_payment,
  struct GNUNET_TIME_Timestamp request_timestamp,
  struct GNUNET_TIME_Timestamp reserve_expiration,
  uint32_t purse_limit,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Sign to deposit coin to pay for keeping a reserve open.
 *
 * @param coin_contribution how much the coin should contribute
 * @param reserve_sig signature over the reserve open operation
 * @param coin_priv private key of the coin
 * @param[out] coin_sig signature by the coin
 */
void
TALER_wallet_reserve_open_deposit_sign (
  const struct TALER_Amount *coin_contribution,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify signature that deposits coin to pay for keeping a reserve open.
 *
 * @param coin_contribution how much the coin should contribute
 * @param reserve_sig signature over the reserve open operation
 * @param coin_pub public key of the coin
 * @param coin_sig signature by the coin
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_reserve_open_deposit_verify (
  const struct TALER_Amount *coin_contribution,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign a request to close a reserve.
 *
 * @param request_timestamp when was the request created
 * @param h_payto where to send the funds (NULL allowed to send
 *        to origin of the reserve)
 * @param reserve_priv key identifying the reserve
 * @param[out] reserve_sig resulting signature
 */
void
TALER_wallet_reserve_close_sign (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify wallet request to close an account.
 *
 * @param request_timestamp when was the request created
 * @param h_payto where to send the funds (NULL/all zeros
 *        allowed to send to origin of the reserve)
 * @param reserve_pub account’s public key
 * @param reserve_sig the signature made with purpose #TALER_SIGNATURE_WALLET_RESERVE_CLOSE
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_reserve_close_verify (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Sign a request by a wallet to perform a KYC check.
 *
 * @param reserve_priv key identifying the wallet/account
 * @param[out] reserve_sig resulting signature
 */
void
TALER_wallet_account_setup_sign (
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify account setup request.
 *
 * @param reserve_pub reserve the setup request was for
 * @param reserve_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_account_setup_verify (
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Sign request to the exchange to confirm certain
 * @a details about the owner of a reserve.
 *
 * @param request_timestamp when was the request created
 * @param details which attributes are requested
 * @param reserve_priv private key of the reserve
 * @param[out] reserve_sig where to store the signature
 */
void
TALER_wallet_reserve_attest_request_sign (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const json_t *details,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify request to the exchange to confirm certain
 * @a details about the owner of a reserve.
 *
 * @param request_timestamp when was the request created
 * @param details which attributes are requested
 * @param reserve_pub public key of the reserve
 * @param reserve_sig where to store the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_reserve_attest_request_verify (
  struct GNUNET_TIME_Timestamp request_timestamp,
  const json_t *details,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Sign a deposit permission.  Function for wallets.
 *
 * @param amount the amount to be deposited
 * @param deposit_fee the deposit fee we expect to pay
 * @param h_wire hash of the merchant’s account details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param h_age_commitment hash over the age commitment, if applicable to the denomination (maybe NULL)
 * @param h_extensions hash over the extensions
 * @param h_denom_pub hash of the coin denomination's public key
 * @param coin_priv coin’s private key
 * @param wallet_timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param[out] coin_sig set to the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT
 */
void
TALER_wallet_deposit_sign (
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
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify a deposit permission.
 *
 * @param amount the amount to be deposited
 * @param deposit_fee the deposit fee we expect to pay
 * @param h_wire hash of the merchant’s account details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param h_age_commitment hash over the age commitment (maybe all zeroes, if not applicable to the denomination)
 * @param h_extensions hash over the extensions
 * @param h_denom_pub hash of the coin denomination's public key
 * @param wallet_timestamp timestamp when the contract was finalized, must not be too far in the future
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param coin_pub coin’s public key
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_DEPOSIT
 * @return #GNUNET_OK if the signature is valid
 */
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
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign a melt request.
 *
 * @param amount_with_fee the amount to be melted (with fee)
 * @param melt_fee the melt fee we expect to pay
 * @param rc refresh session we are committed to
 * @param h_denom_pub hash of the coin denomination's public key
 * @param h_age_commitment hash of the age commitment (may be NULL)
 * @param coin_priv coin’s private key
 * @param[out] coin_sig set to the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_MELT
 */
void
TALER_wallet_melt_sign (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify a melt request.
 *
 * @param amount_with_fee the amount to be melted (with fee)
 * @param melt_fee the melt fee we expect to pay
 * @param rc refresh session we are committed to
 * @param h_denom_pub hash of the coin denomination's public key
 * @param h_age_commitment hash of the age commitment (may be NULL)
 * @param coin_pub coin’s public key
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_MELT
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_melt_verify (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign link data.
 *
 * @param h_denom_pub hash of the denomiantion public key of the new coin
 * @param transfer_pub transfer public key
 * @param bch blinded coin hash
 * @param old_coin_priv private key to sign with
 * @param[out] coin_sig resulting signature
 */
void
TALER_wallet_link_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  const struct TALER_BlindedCoinHashP *bch,
  const struct TALER_CoinSpendPrivateKeyP *old_coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify link signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the new coin
 * @param transfer_pub transfer public key
 * @param h_coin_ev hash of the coin envelope
 * @param old_coin_pub old coin key that the link signature is for
 * @param coin_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_link_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  const struct TALER_BlindedCoinHashP *h_coin_ev,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign withdraw request.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin to withdraw
 * @param amount_with_fee amount to debit the reserve for
 * @param bch blinded coin hash
 * @param reserve_priv private key to sign with
 * @param[out] reserve_sig resulting signature
 */
void
TALER_wallet_withdraw_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_BlindedCoinHashP *bch,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify withdraw request.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin to withdraw
 * @param amount_with_fee amount to debit the reserve for
 * @param bch blinded coin hash
 * @param reserve_pub public key of the reserve
 * @param reserve_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_withdraw_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_BlindedCoinHashP *bch,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify exchange melt confirmation.
 *
 * @param rc refresh session this is about
 * @param noreveal_index gamma value chosen by the exchange
 * @param exchange_pub public signing key used
 * @param exchange_sig signature to check
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_melt_confirmation_verify (
  const struct TALER_RefreshCommitmentP *rc,
  uint32_t noreveal_index,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig);


/**
 * Verify recoup signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin
 * @param coin_bks blinding factor used when withdrawing the coin
 * @param coin_pub coin key of the coin to be recouped
 * @param coin_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_recoup_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Create recoup signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin
 * @param coin_bks blinding factor used when withdrawing the coin
 * @param coin_priv coin key of the coin to be recouped
 * @param[out] coin_sig resulting signature
 */
void
TALER_wallet_recoup_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify recoup-refresh signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin
 * @param coin_bks blinding factor used when withdrawing the coin
 * @param coin_pub coin key of the coin to be recouped
 * @param coin_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_recoup_refresh_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Create recoup-refresh signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin
 * @param coin_bks blinding factor used when withdrawing the coin
 * @param coin_priv coin key of the coin to be recouped
 * @param[out] coin_sig resulting signature
 */
void
TALER_wallet_recoup_refresh_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify reserve history request signature.
 *
 * @param ts timestamp used
 * @param history_fee how much did the wallet say it would pay
 * @param reserve_pub reserve the history request was for
 * @param reserve_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_reserve_history_verify (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_Amount *history_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Create reserve history request signature.
 *
 * @param ts timestamp used
 * @param history_fee how much do we expect to pay
 * @param reserve_priv private key of the reserve the history request is for
 * @param[out] reserve_sig resulting signature
 */
void
TALER_wallet_reserve_history_sign (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_Amount *history_fee,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Verify reserve status request signature.
 *
 * @param ts timestamp used
 * @param reserve_pub reserve the status request was for
 * @param reserve_sig resulting signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_reserve_status_verify (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig);


/**
 * Create reserve status request signature.
 *
 * @param ts timestamp used
 * @param reserve_priv private key of the reserve the status request is for
 * @param[out] reserve_sig resulting signature
 */
void
TALER_wallet_reserve_status_sign (
  const struct GNUNET_TIME_Timestamp ts,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_ReserveSignatureP *reserve_sig);


/* ********************* merchant signing ************************** */


/**
 * Create merchant signature approving a refund.
 *
 * @param coin_pub coin to be refunded
 * @param h_contract_terms contract to be refunded
 * @param rtransaction_id unique ID for this (partial) refund
 * @param amount amount to be refunded
 * @param merchant_priv private key to sign with
 * @param[out] merchant_sig where to write the signature
 */
void
TALER_merchant_refund_sign (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint64_t rtransaction_id,
  const struct TALER_Amount *amount,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  struct TALER_MerchantSignatureP *merchant_sig);


/**
 * Verify merchant signature approving a refund.
 *
 * @param coin_pub coin to be refunded
 * @param h_contract_terms contract to be refunded
 * @param rtransaction_id unique ID for this (partial) refund
 * @param amount amount to be refunded
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature to verify
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_merchant_refund_verify (
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint64_t rtransaction_id,
  const struct TALER_Amount *amount,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_MerchantSignatureP *merchant_sig);


/* ********************* exchange deposit signing ************************* */

/**
 * Sign a deposit.
 *
 * @param h_contract_terms hash of contract terms
 * @param h_wire hash of the merchant account details
 * @param coin_pub coin to be deposited
 * @param merchant_priv private key to sign with
 * @param[out] merchant_sig where to write the signature
 */
void
TALER_merchant_deposit_sign (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPrivateKeyP *merchant_priv,
  struct TALER_MerchantSignatureP *merchant_sig);


/**
 * Verify a deposit.
 *
 * @param merchant merchant public key
 * @param coin_pub public key of the deposited coin
 * @param h_contract_terms hash of contract terms
 * @param h_wire hash of the merchant account details
 * @param merchant_sig signature of the merchant
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_merchant_deposit_verify (
  const struct TALER_MerchantPublicKeyP *merchant,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_MerchantSignatureP *merchant_sig);


/* ********************* exchange online signing ************************** */


/**
 * Signature of a function that signs the message in @a purpose with the
 * exchange's signing key.
 *
 * The @a purpose data is the beginning of the data of which the signature is
 * to be created. The `size` field in @a purpose must correctly indicate the
 * number of bytes of the data structure, including its header. *
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 * @return #TALER_EC_NONE on success
 */
typedef enum TALER_ErrorCode
(*TALER_ExchangeSignCallback)(
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Signature of a function that signs the message in @a purpose with the
 * exchange's signing key.
 *
 * The @a purpose data is the beginning of the data of which the signature is
 * to be created. The `size` field in @a purpose must correctly indicate the
 * number of bytes of the data structure, including its header. *
 * @param cls closure
 * @param purpose the message to sign
 * @param[out] pub set to the current public signing key of the exchange
 * @param[out] sig signature over purpose using current signing key
 * @return #TALER_EC_NONE on success
 */
typedef enum TALER_ErrorCode
(*TALER_ExchangeSignCallback2)(
  void *cls,
  const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Create deposit confirmation signature.
 *
 * @param scb function to call to create the signature
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param h_wire hash of the merchant’s account details
 * @param h_extensions hash over the extensions, can be NULL
 * @param exchange_timestamp timestamp when the contract was finalized, must not be too far off
 * @param wire_deadline date until which the exchange should wire the funds
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param amount_without_fee the amount to be deposited after fees
 * @param coin_pub public key of the deposited coin
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_deposit_confirmation_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionContractHashP *h_extensions,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify deposit confirmation signature.
 *
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
 * @param h_wire hash of the merchant’s account details
 * @param h_extensions hash over the extensions, can be NULL
 * @param exchange_timestamp timestamp when the contract was finalized, must not be too far off
 * @param wire_deadline date until which the exchange should wire the funds
 * @param refund_deadline date until which the merchant can issue a refund to the customer via the exchange (can be zero if refunds are not allowed); must not be after the @a wire_deadline
 * @param amount_without_fee the amount to be deposited after fees
 * @param coin_pub public key of the deposited coin
 * @param merchant_pub the public key of the merchant (used to identify the merchant for refund requests)
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_deposit_confirmation_verify (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionContractHashP *h_extensions,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create refund confirmation signature.
 *
 * @param scb function to call to create the signature
 * @param h_contract_terms hash of contract being refunded
 * @param coin_pub public key of the coin receiving the refund
 * @param merchant public key of the merchant that granted the refund
 * @param rtransaction_id refund transaction ID used by the merchant
 * @param refund_amount amount refunded
 * @param[out] pub where to write the exchange public key
 * @param[out] sig where to write the exchange signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_refund_confirmation_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  uint64_t rtransaction_id,
  const struct TALER_Amount *refund_amount,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify refund confirmation signature.
 *
 * @param h_contract_terms hash of contract being refunded
 * @param coin_pub public key of the coin receiving the refund
 * @param merchant public key of the merchant that granted the refund
 * @param rtransaction_id refund transaction ID used by the merchant
 * @param refund_amount amount refunded
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_refund_confirmation_verify (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant,
  uint64_t rtransaction_id,
  const struct TALER_Amount *refund_amount,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create refresh melt confirmation signature.
 *
 * @param scb function to call to create the signature
 * @param rc refresh commitment that identifies the melt operation
 * @param noreveal_index gamma cut-and-choose value chosen by the exchange
 * @param[out] pub where to write the exchange public key
 * @param[out] sig where to write the exchange signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_melt_confirmation_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_RefreshCommitmentP *rc,
  uint32_t noreveal_index,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify refresh melt confirmation signature.
 *
 * @param rc refresh commitment that identifies the melt operation
 * @param noreveal_index gamma cut-and-choose value chosen by the exchange
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_melt_confirmation_verify (
  const struct TALER_RefreshCommitmentP *rc,
  uint32_t noreveal_index,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create exchange purse refund confirmation signature.
 *
 * @param scb function to call to create the signature
 * @param amount_without_fee refunded amount
 * @param refund_fee refund fee charged
 * @param coin_pub coin that was refunded
 * @param purse_pub public key of the expired purse
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_purse_refund_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_Amount *refund_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify signature of exchange affirming purse refund
 * from purse expiration.
 *
 * @param amount_without_fee refunded amount
 * @param refund_fee refund fee charged
 * @param coin_pub coin that was refunded
 * @param purse_pub public key of the expired purse
 * @param pub public key to verify signature against
 * @param sig signature to verify
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_refund_verify (
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_Amount *refund_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create exchange key set signature.
 *
 * @param scb function to call to create the signature
 * @param cls closure for @a scb
 * @param timestamp time when the key set was issued
 * @param hc hash over all the keys
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_key_set_sign (
  TALER_ExchangeSignCallback2 scb,
  void *cls,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct GNUNET_HashCode *hc,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify key set signature.
 *
 * @param timestamp time when the key set was issued
 * @param hc hash over all the keys
 * @param pub public key to verify signature against
 * @param sig signature to verify
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_key_set_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct GNUNET_HashCode *hc,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create account setup success signature.
 *
 * @param scb function to call to create the signature
 * @param h_payto target of the KYC account
 * @param timestamp time when the KYC was confirmed
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_account_setup_success_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp timestamp,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify account setup success signature.
 *
 * @param h_payto target of the KYC account
 * @param timestamp time when the KYC was confirmed
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_account_setup_success_verify (
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Hash normalized @a j JSON object or array and
 * store the result in @a hc.
 *
 * @param j JSON to hash
 * @param[out] hc where to write the hash
 */
void
TALER_json_hash (const json_t *j,
                 struct GNUNET_HashCode *hc);


/**
 * Update the @a hash_context in the computation of the
 * h_details for a wire status signature.
 *
 * @param[in,out] hash_context context to update
 * @param h_contract_terms hash of the contract
 * @param execution_time when was the wire transfer initiated
 * @param coin_pub deposited coin
 * @param deposit_value contribution of the coin
 * @param deposit_fee how high was the deposit fee
 */
void
TALER_exchange_online_wire_deposit_append (
  struct GNUNET_HashContext *hash_context,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp execution_time,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_Amount *deposit_value,
  const struct TALER_Amount *deposit_fee);


/**
 * Create wire deposit signature.
 *
 * @param scb function to call to create the signature
 * @param total amount the merchant was credited
 * @param wire_fee fee charged by the exchange for the wire transfer
 * @param merchant_pub which merchant was credited
 * @param payto payto://-URI of the merchant account
 * @param h_details hash over the aggregation details
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_wire_deposit_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_Amount *total,
  const struct TALER_Amount *wire_fee,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const char *payto,
  const struct GNUNET_HashCode *h_details,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify wire deposit signature.
 *
 * @param total amount the merchant was credited
 * @param wire_fee fee charged by the exchange for the wire transfer
 * @param merchant_pub which merchant was credited
 * @param h_payto hash of the payto://-URI of the merchant account
 * @param h_details hash over the aggregation details
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_wire_deposit_verify (
  const struct TALER_Amount *total,
  const struct TALER_Amount *wire_fee,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_PaytoHashP *h_payto,
  const struct GNUNET_HashCode *h_details,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create wire confirmation signature.
 *
 * @param scb function to call to create the signature
 * @param h_wire hash of the merchant's account
 * @param h_contract_terms hash of the contract
 * @param wtid wire transfer this deposit was aggregated into
 * @param coin_pub public key of the deposited coin
 * @param execution_time when was wire transfer initiated
 * @param coin_contribution what was @a coin_pub's contribution to the wire transfer
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_confirm_wire_sign (
  TALER_ExchangeSignCallback scb,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct GNUNET_TIME_Timestamp execution_time,
  const struct TALER_Amount *coin_contribution,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify confirm wire signature.
 *
 * @param h_wire hash of the merchant's account
 * @param h_contract_terms hash of the contract
 * @param wtid wire transfer this deposit was aggregated into
 * @param coin_pub public key of the deposited coin
 * @param execution_time when was wire transfer initiated
 * @param coin_contribution what was @a coin_pub's contribution to the wire transfer
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_confirm_wire_verify (
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct GNUNET_TIME_Timestamp execution_time,
  const struct TALER_Amount *coin_contribution,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create confirm recoup signature.
 *
 * @param scb function to call to create the signature
 * @param timestamp when was the recoup done
 * @param recoup_amount how much was recouped
 * @param coin_pub coin that was recouped
 * @param reserve_pub reserve that was credited
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_confirm_recoup_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify confirm recoup signature.
 *
 * @param timestamp when was the recoup done
 * @param recoup_amount how much was recouped
 * @param coin_pub coin that was recouped
 * @param reserve_pub reserve that was credited
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_confirm_recoup_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create confirm recoup refresh signature.
 *
 * @param scb function to call to create the signature
 * @param timestamp when was the recoup done
 * @param recoup_amount how much was recouped
 * @param coin_pub coin that was recouped
 * @param old_coin_pub old coin that was credited
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_confirm_recoup_refresh_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify confirm recoup refresh signature.
 *
 * @param timestamp when was the recoup done
 * @param recoup_amount how much was recouped
 * @param coin_pub coin that was recouped
 * @param old_coin_pub old coin that was credited
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_confirm_recoup_refresh_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *recoup_amount,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create denomination unknown signature.
 *
 * @param scb function to call to create the signature
 * @param timestamp when was the error created
 * @param h_denom_pub hash of denomination that is unknown
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_denomination_unknown_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify denomination unknown signature.
 *
 * @param timestamp when was the error created
 * @param h_denom_pub hash of denomination that is unknown
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_denomination_unknown_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create denomination expired signature.
 *
 * @param scb function to call to create the signature
 * @param timestamp when was the error created
 * @param h_denom_pub hash of denomination that is expired
 * @param op character string describing the operation for which
 *           the denomination is expired
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_denomination_expired_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  const char *op,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify denomination expired signature.
 *
 * @param timestamp when was the error created
 * @param h_denom_pub hash of denomination that is expired
 * @param op character string describing the operation for which
 *           the denomination is expired
 * @param pub where to write the public key
 * @param sig where to write the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_denomination_expired_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_DenominationHashP *h_denom_pub,
  const char *op,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create reserve closure signature.
 *
 * @param scb function to call to create the signature
 * @param timestamp time when the reserve was closed
 * @param closing_amount amount left in the reserve
 * @param closing_fee closing fee charged
 * @param payto target of the wire transfer
 * @param wtid wire transfer subject used
 * @param reserve_pub public key of the closed reserve
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_reserve_closed_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *closing_amount,
  const struct TALER_Amount *closing_fee,
  const char *payto,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify reserve closure signature.
 *
 * @param timestamp time when the reserve was closed
 * @param closing_amount amount left in the reserve
 * @param closing_fee closing fee charged
 * @param payto target of the wire transfer
 * @param wtid wire transfer subject used
 * @param reserve_pub public key of the closed reserve
 * @param pub the public key of the exchange to check against
 * @param sig the signature to check
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_reserve_closed_verify (
  struct GNUNET_TIME_Timestamp timestamp,
  const struct TALER_Amount *closing_amount,
  const struct TALER_Amount *closing_fee,
  const char *payto,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Create signature by exchange affirming that a reserve
 * has had certain attributes verified via KYC.
 *
 * @param scb function to call to create the signature
 * @param attest_timestamp our time
 * @param expiration_time when does the KYC data expire
 * @param reserve_pub for which reserve are attributes attested
 * @param attributes JSON object with attributes being attested to
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_reserve_attest_details_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp attest_timestamp,
  struct GNUNET_TIME_Timestamp expiration_time,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *attributes,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify signature by exchange affirming that a reserve
 * has had certain attributes verified via KYC.
 *
 * @param attest_timestamp our time
 * @param expiration_time when does the KYC data expire
 * @param reserve_pub for which reserve are attributes attested
 * @param attributes JSON object with attributes being attested to
 * @param pub exchange public key
 * @param sig exchange signature to verify
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_reserve_attest_details_verify (
  struct GNUNET_TIME_Timestamp attest_timestamp,
  struct GNUNET_TIME_Timestamp expiration_time,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *attributes,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Create signature by exchange affirming that a purse was created.
 *
 * @param scb function to call to create the signature
 * @param exchange_time our time
 * @param purse_expiration when will the purse expire
 * @param amount_without_fee total amount to be put into the purse (without deposit fees)
 * @param total_deposited total currently in the purse
 * @param purse_pub public key of the purse
 * @param h_contract_terms hash of the contract for the purse
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_purse_created_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_Amount *total_deposited,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify exchange signature about a purse creation and balance.
 *
 * @param exchange_time our time
 * @param purse_expiration when will the purse expire
 * @param amount_without_fee total amount to be put into the purse (without deposit fees)
 * @param total_deposited total currently in the purse
 * @param purse_pub public key of the purse
 * @param h_contract_terms hash of the contract for the purse
 * @param pub the public key of the exchange to check against
 * @param sig the signature to check
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_created_verify (
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_Amount *total_deposited,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Sign affirmation that a purse was merged.
 *
 * @param scb function to call to create the signature
 * @param exchange_time our time
 * @param purse_expiration when does the purse expire
 * @param amount_without_fee total amount that should be in the purse without deposit fees
 * @param purse_pub public key of the purse
 * @param h_contract_terms hash of the contract of the purse
 * @param reserve_pub reserve the purse will be merged into
 * @param exchange_url exchange at which the @a reserve_pub lives
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_purse_merged_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *exchange_url,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify affirmation that a purse will be merged.
 *
 * @param exchange_time our time
 * @param purse_expiration when does the purse expire
 * @param amount_without_fee total amount that should be in the purse without deposit fees
 * @param purse_pub public key of the purse
 * @param h_contract_terms hash of the contract of the purse
 * @param reserve_pub reserve the purse will be merged into
 * @param exchange_url exchange at which the @a reserve_pub lives
 * @param pub the public key of the exchange to check against
 * @param sig the signature to check
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_merged_verify (
  struct GNUNET_TIME_Timestamp exchange_time,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *exchange_url,
  const struct TALER_ExchangePublicKeyP *pub,
  const struct TALER_ExchangeSignatureP *sig);


/**
 * Sign information about the status of a purse.
 *
 * @param scb function to call to create the signature
 * @param merge_timestamp when was the purse merged (can be never)
 * @param deposit_timestamp when was the purse fully paid up (can be never)
 * @param balance current balance of the purse
 * @param[out] pub where to write the public key
 * @param[out] sig where to write the signature
 * @return #TALER_EC_NONE on success
 */
enum TALER_ErrorCode
TALER_exchange_online_purse_status_sign (
  TALER_ExchangeSignCallback scb,
  struct GNUNET_TIME_Timestamp merge_timestamp,
  struct GNUNET_TIME_Timestamp deposit_timestamp,
  const struct TALER_Amount *balance,
  struct TALER_ExchangePublicKeyP *pub,
  struct TALER_ExchangeSignatureP *sig);


/**
 * Verify signature over information about the status of a purse.
 *
 * @param merge_timestamp when was the purse merged (can be never)
 * @param deposit_timestamp when was the purse fully paid up (can be never)
 * @param balance current balance of the purse
 * @param exchange_pub the public key of the exchange to check against
 * @param exchange_sig the signature to check
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_online_purse_status_verify (
  struct GNUNET_TIME_Timestamp merge_timestamp,
  struct GNUNET_TIME_Timestamp deposit_timestamp,
  const struct TALER_Amount *balance,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig);


/* ********************* offline signing ************************** */


/**
 * Create auditor addition signature.
 *
 * @param auditor_pub public key of the auditor
 * @param auditor_url URL of the auditor
 * @param start_date when to enable the auditor (for replay detection)
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_auditor_add_sign (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  struct GNUNET_TIME_Timestamp start_date,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify auditor add signature.
 *
 * @param auditor_pub public key of the auditor
 * @param auditor_url URL of the auditor
 * @param start_date when to enable the auditor (for replay detection)
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_auditor_add_verify (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const char *auditor_url,
  struct GNUNET_TIME_Timestamp start_date,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create auditor deletion signature.
 *
 * @param auditor_pub public key of the auditor
 * @param end_date when to disable the auditor (for replay detection)
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_auditor_del_sign (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp end_date,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify auditor del signature.
 *
 * @param auditor_pub public key of the auditor
 * @param end_date when to disable the auditor (for replay detection)
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_auditor_del_verify (
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp end_date,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create denomination revocation signature.
 *
 * @param h_denom_pub hash of public denomination key to revoke
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_denomination_revoke_sign (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify denomination revocation signature.
 *
 * @param h_denom_pub hash of public denomination key to revoke
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_denomination_revoke_verify (
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create signkey revocation signature.
 *
 * @param exchange_pub public signing key to revoke
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_signkey_revoke_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify signkey revocation signature.
 *
 * @param exchange_pub public signkey key to revoke
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_signkey_revoke_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create signkey validity signature.
 *
 * @param exchange_pub public signing key to validate
 * @param start_sign starting point of validity for signing
 * @param end_sign end point (exclusive) for validity for signing
 * @param end_legal legal end point of signature validity
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_signkey_validity_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Timestamp end_sign,
  struct GNUNET_TIME_Timestamp end_legal,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify signkey validitity signature.
 *
 * @param exchange_pub public signkey key to validate
 * @param start_sign starting point of validity for signing
 * @param end_sign end point (exclusive) for validity for signing
 * @param end_legal legal end point of signature validity
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_signkey_validity_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Timestamp end_sign,
  struct GNUNET_TIME_Timestamp end_legal,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create denomination key validity signature.
 *
 * @param h_denom_pub hash of the denomination's public key
 * @param stamp_start when does the exchange begin signing with this key
 * @param stamp_expire_withdraw when does the exchange end signing with this key
 * @param stamp_expire_deposit how long does the exchange accept the deposit of coins with this key
 * @param stamp_expire_legal how long does the exchange preserve information for legal disputes with this key
 * @param coin_value what is the value of coins signed with this key
 * @param fees fees for this denomination
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
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
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify denomination key validity signature.
 *
 * @param h_denom_pub hash of the denomination's public key
 * @param stamp_start when does the exchange begin signing with this key
 * @param stamp_expire_withdraw when does the exchange end signing with this key
 * @param stamp_expire_deposit how long does the exchange accept the deposit of coins with this key
 * @param stamp_expire_legal how long does the exchange preserve information for legal disputes with this key
 * @param coin_value what is the value of coins signed with this key
 * @param fees fees for this denomination
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
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
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create offline signature about an exchange's partners.
 *
 * @param partner_pub master public key of the partner
 * @param start_date validity period start
 * @param end_date validity period end
 * @param wad_frequency how often will we do wad transfers to this partner
 * @param wad_fee what is the wad fee to this partner
 * @param partner_base_url what is the base URL of the @a partner_pub exchange
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_partner_details_sign (
  const struct TALER_MasterPublicKeyP *partner_pub,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  struct GNUNET_TIME_Relative wad_frequency,
  const struct TALER_Amount *wad_fee,
  const char *partner_base_url,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify signature about an exchange's partners.
 *
 * @param partner_pub master public key of the partner
 * @param start_date validity period start
 * @param end_date validity period end
 * @param wad_frequency how often will we do wad transfers to this partner
 * @param wad_fee what is the wad fee to this partner
 * @param partner_base_url what is the base URL of the @a partner_pub exchange
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_partner_details_verify (
  const struct TALER_MasterPublicKeyP *partner_pub,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  struct GNUNET_TIME_Relative wad_frequency,
  const struct TALER_Amount *wad_fee,
  const char *partner_base_url,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create offline signature about wiring profits to a
 * regular non-escrowed account of the exchange.
 *
 * @param wtid (random) wire transfer ID to be used
 * @param date when was the profit drain approved (not exact time of execution)
 * @param amount how much should be wired
 * @param account_section configuration section of the
 *        exchange specifying the account to be debited
 * @param payto_uri target account to be credited
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_profit_drain_sign (
  const struct TALER_WireTransferIdentifierRawP *wtid,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_Amount *amount,
  const char *account_section,
  const char *payto_uri,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify offline signature about wiring profits to a
 * regular non-escrowed account of the exchange.
 *
 * @param wtid (random) wire transfer ID to be used
 * @param date when was the profit drain approved (not exact time of execution)
 * @param amount how much should be wired
 * @param account_section configuration section of the
 *        exchange specifying the account to be debited
 * @param payto_uri target account to be credited
 * @param master_pub public key to verify signature against
 * @param master_sig the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_profit_drain_verify (
  const struct TALER_WireTransferIdentifierRawP *wtid,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_Amount *amount,
  const char *account_section,
  const char *payto_uri,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create security module EdDSA signature.
 *
 * @param exchange_pub public signing key to validate
 * @param start_sign starting point of validity for signing
 * @param duration how long will the key be in use
 * @param secm_priv security module key to sign with
 * @param[out] secm_sig where to write the signature
 */
void
TALER_exchange_secmod_eddsa_sign (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig);


/**
 * Verify security module EdDSA signature.
 *
 * @param exchange_pub public signing key to validate
 * @param start_sign starting point of validity for signing
 * @param duration how long will the key be in use
 * @param secm_pub public key to verify against
 * @param secm_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_secmod_eddsa_verify (
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig);


/**
 * Create security module denomination signature.
 *
 * @param h_rsa hash of the RSA public key to sign
 * @param section_name name of the section in the configuration
 * @param start_sign starting point of validity for signing
 * @param duration how long will the key be in use
 * @param secm_priv security module key to sign with
 * @param[out] secm_sig where to write the signature
 */
void
TALER_exchange_secmod_rsa_sign (
  const struct TALER_RsaPubHashP *h_rsa,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig);


/**
 * Verify security module denomination signature.
 *
 * @param h_rsa hash of the public key to validate
 * @param section_name name of the section in the configuration
 * @param start_sign starting point of validity for signing
 * @param duration how long will the key be in use
 * @param secm_pub public key to verify against
 * @param secm_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_secmod_rsa_verify (
  const struct TALER_RsaPubHashP *h_rsa,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig);


/**
 * Create security module denomination signature.
 *
 * @param h_cs hash of the CS public key to sign
 * @param section_name name of the section in the configuration
 * @param start_sign starting point of validity for signing
 * @param duration how long will the key be in use
 * @param secm_priv security module key to sign with
 * @param[out] secm_sig where to write the signature
 */
void
TALER_exchange_secmod_cs_sign (
  const struct TALER_CsPubHashP *h_cs,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePrivateKeyP *secm_priv,
  struct TALER_SecurityModuleSignatureP *secm_sig);


/**
 * Verify security module denomination signature.
 *
 * @param h_cs hash of the public key to validate
 * @param section_name name of the section in the configuration
 * @param start_sign starting point of validity for signing
 * @param duration how long will the key be in use
 * @param secm_pub public key to verify against
 * @param secm_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_secmod_cs_verify (
  const struct TALER_CsPubHashP *h_cs,
  const char *section_name,
  struct GNUNET_TIME_Timestamp start_sign,
  struct GNUNET_TIME_Relative duration,
  const struct TALER_SecurityModulePublicKeyP *secm_pub,
  const struct TALER_SecurityModuleSignatureP *secm_sig);


/**
 * Create denomination key validity signature by the auditor.
 *
 * @param auditor_url BASE URL of the auditor's API
 * @param h_denom_pub hash of the denomination's public key
 * @param master_pub master public key of the exchange
 * @param stamp_start when does the exchange begin signing with this key
 * @param stamp_expire_withdraw when does the exchange end signing with this key
 * @param stamp_expire_deposit how long does the exchange accept the deposit of coins with this key
 * @param stamp_expire_legal how long does the exchange preserve information for legal disputes with this key
 * @param coin_value what is the value of coins signed with this key
 * @param fees fees the exchange charges for this denomination
 * @param auditor_priv private key to sign with
 * @param[out] auditor_sig where to write the signature
 */
void
TALER_auditor_denom_validity_sign (
  const char *auditor_url,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_DenomFeeSet *fees,
  const struct TALER_AuditorPrivateKeyP *auditor_priv,
  struct TALER_AuditorSignatureP *auditor_sig);


/**
 * Verify denomination key validity signature from auditor.
 *
 * @param auditor_url BASE URL of the auditor's API
 * @param h_denom_pub hash of the denomination's public key
 * @param master_pub master public key of the exchange
 * @param stamp_start when does the exchange begin signing with this key
 * @param stamp_expire_withdraw when does the exchange end signing with this key
 * @param stamp_expire_deposit how long does the exchange accept the deposit of coins with this key
 * @param stamp_expire_legal how long does the exchange preserve information for legal disputes with this key
 * @param coin_value what is the value of coins signed with this key
 * @param fees fees the exchange charges for this denomination
 * @param auditor_pub public key to verify against
 * @param auditor_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_auditor_denom_validity_verify (
  const char *auditor_url,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_DenomFeeSet *fees,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig);


/* **************** /wire account offline signing **************** */


/**
 * Create wire fee signature.
 *
 * @param payment_method the payment method
 * @param start_time when do the fees start to apply
 * @param end_time when do the fees start to apply
 * @param fees the wire fees
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_wire_fee_sign (
  const char *payment_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_WireFeeSet *fees,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify wire fee signature.
 *
 * @param payment_method the payment method
 * @param start_time when do the fees start to apply
 * @param end_time when do the fees start to apply
 * @param fees the wire fees
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_fee_verify (
  const char *payment_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_WireFeeSet *fees,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create global fees signature.
 *
 * @param start_time when do the fees start to apply
 * @param end_time when do the fees start to apply
 * @param fees the global fees
 * @param purse_timeout how long do unmerged purses stay around
 * @param kyc_timeout how long do we keep funds in a reserve without KYC?
 * @param history_expiration how long do we keep the history of an account
 * @param purse_account_limit how many concurrent purses are free per account holder
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
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
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify global fees signature.
 *
 * @param start_time when do the fees start to apply
 * @param end_time when do the fees start to apply
 * @param fees the global fees
 * @param purse_timeout how long do unmerged purses stay around
 * @param kyc_timeout how long do we keep funds in a reserve without KYC?
 * @param history_expiration how long do we keep the history of an account
 * @param purse_account_limit how many concurrent purses are free per account holder
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
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
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create wire account addition signature.
 *
 * @param payto_uri bank account
 * @param now timestamp to use for the signature (rounded)
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_wire_add_sign (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify wire account addition signature.
 *
 * @param payto_uri bank account
 * @param sign_time timestamp when signature was created
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_add_verify (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp sign_time,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Create wire account removal signature.
 *
 * @param payto_uri bank account
 * @param now timestamp to use for the signature (rounded)
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_wire_del_sign (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify wire account deletion signature.
 *
 * @param payto_uri bank account
 * @param sign_time timestamp when signature was created
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_del_verify (
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp sign_time,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


/**
 * Check the signature in @a master_sig.
 *
 * @param payto_uri URI that is signed
 * @param master_pub master public key of the exchange
 * @param master_sig signature of the exchange
 * @return #GNUNET_OK if signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_wire_signature_check (
  const char *payto_uri,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig);


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
  struct TALER_MasterSignatureP *master_sig);


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
                                    const struct TALER_WireSaltP *salt,
                                    struct TALER_MerchantWireHashP *hc);


/**
 * Check the signature in @a wire_s.
 *
 * @param payto_uri URL that is signed
 * @param salt the salt used to salt the @a payto_uri when hashing
 * @param merch_pub public key of the merchant
 * @param merch_sig signature of the merchant
 * @return #GNUNET_OK if signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_merchant_wire_signature_check (
  const char *payto_uri,
  const struct TALER_WireSaltP *salt,
  const struct TALER_MerchantPublicKeyP *merch_pub,
  const struct TALER_MerchantSignatureP *merch_sig);


/**
 * Create a signed wire statement for the given account.
 *
 * @param payto_uri account specification
 * @param salt the salt used to salt the @a payto_uri when hashing
 * @param merch_priv private key to sign with
 * @param[out] merch_sig where to write the signature
 */
void
TALER_merchant_wire_signature_make (
  const char *payto_uri,
  const struct TALER_WireSaltP *salt,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct TALER_MerchantSignatureP *merch_sig);


/**
 * Sign a payment confirmation.
 *
 * @param h_contract_terms hash of the contact of the merchant with the customer
 * @param merch_priv private key to sign with
 * @param[out] merch_sig where to write the signature
 */
void
TALER_merchant_pay_sign (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct GNUNET_CRYPTO_EddsaSignature *merch_sig);


/**
 * Verify payment confirmation signature.
 *
 * @param h_contract_terms hash of the contact of the merchant with the customer
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature to verify
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_merchant_pay_verify (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_MerchantSignatureP *merchant_sig);


/**
 * Sign contract sent by the merchant to the wallet.
 *
 * @param h_contract_terms hash of the contract terms
 * @param merch_priv private key to sign with
 * @param[out] merch_sig where to write the signature
 */
void
TALER_merchant_contract_sign (
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct GNUNET_CRYPTO_EddsaSignature *merch_sig);


/* **************** /management/extensions offline signing **************** */

/**
 * Create a signature for the hash of the configuration of an extension
 *
 * @param h_config hash of the JSON object representing the configuration
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_extension_config_hash_sign (
  const struct TALER_ExtensionConfigHashP *h_config,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify the signature in @a master_sig of the given hash, taken over the JSON
 * blob representing the configuration of an extension
 *
 * @param h_config hash of the JSON blob of a configuration of an extension
 * @param master_pub master public key of the exchange
 * @param master_sig signature of the exchange
 * @return #GNUNET_OK if signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_extension_config_hash_verify (
  const struct TALER_ExtensionConfigHashP *h_config,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig
  );


/**
 * @brief Representation of an age commitment:  one public key per age group.
 *
 * The number of keys must be be the same as the number of bits set in the
 * corresponding age mask.
 */
struct TALER_AgeCommitment
{

  /**
   * The age mask defines the age groups that were a parameter during the
   * generation of this age commitment
   */
  struct TALER_AgeMask mask;

  /**
   * The number of public keys, which must be the same as the number of
   * groups in the mask.
   */
  size_t num;

  /**
   * The list of @e num public keys.  In must have same size as the number of
   * age groups defined in the mask.
   *
   * A hash of this list is the hashed commitment that goes into FDC
   * calculation during the withdraw and refresh operations for new coins. That
   * way, the particular age commitment becomes mandatory and bound to a coin.
   *
   * The list has been allocated via GNUNET_malloc().
   */
  struct TALER_AgeCommitmentPublicKeyP *keys;
};


/**
 * @brief Proof for a particular age commitment, used in age attestation
 *
 * This struct is used in a call to TALER_age_commitment_attest to create an
 * attestation for a minimum age (if that minimum age is less or equal to the
 * committed age for this proof).  It consists of a list private keys, one per
 * age group, for which the committed age is either lager or within that
 * particular group.
 */
struct TALER_AgeProof
{
  /**
   * The number of private keys, which must be at most num_pub_keys.  One minus
   * this number corresponds to the largest age group that is supported with
   * this age commitment.
   * **Note**, that this and the next field are only relevant on the wallet
   * side for attestation and derive operations.
   */
  size_t num;

  /**
   * List of @e num private keys.
   *
   * Note that the list can be _smaller_ than the corresponding list of public
   * keys. In that case, the wallet can sign off only for a subset of the age
   * groups.
   *
   * The list has been allocated via GNUNET_malloc.
   */
  struct TALER_AgeCommitmentPrivateKeyP *keys;
};


/**
 * @brief Commitment and Proof for a maximum age
 *
 * Calling TALER_age_restriction_commit on an (maximum) age value returns this
 * data structure.  It consists of the proof, which is used to create
 * attestations for compatible minimum ages, and the commitment, which is used
 * to verify the attestations and derived commitments.
 *
 * The hash value of the commitment is bound to a particular coin with age
 * restriction.
 */
struct TALER_AgeCommitmentProof
{
  /**
   * The commitment is used to verify a particular attestation.  Its hash value
   * is bound to a particular coin with age restriction.  This structure is
   * sent to the merchant in order to verify a particular attestation for a
   * minimum age.
   * In itself, it does not convey any information about the maximum age that
   * went into the call to TALER_age_restriction_commit.
   */
  struct TALER_AgeCommitment commitment;

  /**
   * The proof is used to create an attestation for a (compatible) minimum age.
   */
  struct TALER_AgeProof proof;
};


/**
 * @brief Generates a hash of the public keys in the age commitment.
 *
 * @param commitment the age commitment - one public key per age group
 * @param[out] hash resulting hash
 */
void
TALER_age_commitment_hash (
  const struct TALER_AgeCommitment *commitment,
  struct TALER_AgeCommitmentHash *hash);


/**
 * @brief Generates an age commitent for the given age.
 *
 * @param mask The age mask the defines the age groups
 * @param age The actual age for which an age commitment is generated
 * @param seed The seed that goes into the key generation.  MUST be chosen uniformly random.
 * @param[out] comm_proof The generated age commitment, ->priv and ->pub allocated via GNUNET_malloc() on success
 * @return #GNUNET_OK on success, #GNUNET_SYSERR otherwise
 */
enum GNUNET_GenericReturnValue
TALER_age_restriction_commit (
  const struct TALER_AgeMask *mask,
  const uint8_t age,
  const struct GNUNET_HashCode *seed,
  struct TALER_AgeCommitmentProof *comm_proof);


/**
 * @brief Derives another, equivalent age commitment for a given one.
 *
 * @param orig Original age commitment
 * @param salt Salt to randomly move the points on the elliptic curve in order to generate another, equivalent commitment.
 * @param[out] derived The resulting age commitment, ->priv and ->pub allocated via GNUNET_malloc() on success.
 * @return #GNUNET_OK on success, #GNUNET_SYSERR otherwise
 */
enum GNUNET_GenericReturnValue
TALER_age_commitment_derive (
  const struct TALER_AgeCommitmentProof *orig,
  const struct GNUNET_HashCode *salt,
  struct TALER_AgeCommitmentProof *derived);


/**
 * @brief Provide attestation for a given age, from a given age commitment, if possible.
 *
 * @param comm_proof The age commitment to be used for attestation.  For successful attestation, it must contain the private key for the corresponding age group.
 * @param age Age (not age group) for which the an attestation should be done
 * @param[out] attest Signature of the age with the appropriate key from the age commitment for the corresponding age group, if applicaple.
 * @return #GNUNET_OK on success, #GNUNET_NO when no attestation can be made for that age with the given commitment, #GNUNET_SYSERR otherwise
 */
enum GNUNET_GenericReturnValue
TALER_age_commitment_attest (
  const struct TALER_AgeCommitmentProof *comm_proof,
  uint8_t age,
  struct TALER_AgeAttestation *attest);


/**
 * @brief Verify the attestation for an given age and age commitment
 *
 * @param commitment The age commitment that went into the attestation.  Only the public keys are needed.
 * @param age Age (not age group) for which the an attestation should be done
 * @param attest Signature of the age with the appropriate key from the age commitment for the corresponding age group, if applicaple.
 * @return #GNUNET_OK when the attestation was successful, #GNUNET_NO no attestation couldn't be verified, #GNUNET_SYSERR otherwise
 */
enum GNUNET_GenericReturnValue
TALER_age_commitment_verify (
  const struct TALER_AgeCommitment *commitment,
  uint8_t age,
  const struct TALER_AgeAttestation *attest);


/**
 * @brief helper function to free memory of a struct TALER_AgeCommitment
 *
 * @param p the commitment from which all memory should be freed.
 */
void
TALER_age_commitment_free (
  struct TALER_AgeCommitment *p);


/**
 * @brief helper function to free memory of a struct TALER_AgeProof
 *
 * @param p the proof of commitment from which all memory should be freed.
 */
void
TALER_age_proof_free (
  struct TALER_AgeProof *p);


/**
 * @brief helper function to free memory of a struct TALER_AgeCommitmentProof
 *
 * @param p the commitment and its proof from which all memory should be freed.
 */
void
TALER_age_commitment_proof_free (
  struct TALER_AgeCommitmentProof *p);

#endif
