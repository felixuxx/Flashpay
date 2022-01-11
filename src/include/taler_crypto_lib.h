/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @brief Type of transfer public keys used during refresh
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

/*
 * @brief Type of a list of age groups, represented as bit mask.
 *
 * The bits set in the mask mark the edges at the beginning of a next age
 * group.  F.e. for the age groups
 *     0-7, 8-9, 10-11, 12-14, 14-15, 16-17, 18-21, 21-*
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
  uint32_t mask;
};

/**
 * @brief Age restriction commitment of a coin.
 */
struct TALER_AgeHash
{
  /**
   * The commitment is a SHA-256 hash code.
   */
  struct GNUNET_ShortHashCode shash;
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
 * @brief Type of blinding keys for Taler.
 */
union TALER_DenominationBlindingKeyP
{
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
struct TALER_WireSalt
{
  /**
   * Actual 128-bit salt value.
   */
  uint32_t salt[4];
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
 * Hash @a rsa.
 *
 * @param rsa key to hash
 * @param[out] h_rsa where to write the result
 */
void
TALER_rsa_pub_hash (const struct GNUNET_CRYPTO_RsaPublicKey *rsa,
                    struct TALER_RsaPubHashP *h_rsa);


/**
 * Hash used to represent a denomination public key
 * and associated age restrictions (if any).
 */
struct TALER_DenominationHash
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
struct TALER_PrivateContractHash
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
struct TALER_ExtensionContractHash
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
struct TALER_MerchantWireHash
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
struct TALER_PaytoHash
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


/**
 * Hash used to represent a commitment to a blinded
 * coin, i.e. the hash of the envelope.
 */
struct TALER_BlindedCoinHash
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
struct TALER_CoinPubHash
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
struct TALER_ExtensionConfigHash
{
  /**
   * Actual hash value.
   */
  struct GNUNET_HashCode hash;
};


GNUNET_NETWORK_STRUCT_END


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
   * Clause-Schnorr blind signature.
   */
  // TALER_DENOMINATION_CS = 2
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
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaSignature *rsa_signature;

  } details;

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
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaSignature *blinded_rsa_signature;

  } details;

};


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
     * If we use #TALER_DENOMINATION_RSA in @a cipher.
     */
    struct GNUNET_CRYPTO_RsaPrivateKey *rsa_private_key;

  } details;
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
  struct TALER_DenominationHash denom_pub_hash;

  /**
   * Hash of the age commitment.
   */
  struct TALER_AgeHash age_commitment_hash;

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
  struct TALER_PrivateContractHash h_contract_terms;

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
 * Free internals of @a denom_pub, but not @a denom_pub itself.
 *
 * @param[in] denom_pub key to free
 */
void
TALER_denom_pub_free (struct TALER_DenominationPublicKey *denom_pub);


/**
 * Create a blinding secret @a bs for @a cipher.
 *
 * @param[out] bs blinding secret to initialize
 */
void
TALER_blinding_secret_create (union TALER_DenominationBlindingKeyP *bs);


/**
 * Initialize denomination public-private key pair.
 *
 * For #TALER_DENOMINATION_RSA, an additional "unsigned int"
 * argument with the number of bits for 'n' (e.g. 2048) must
 * be passed.
 *
 * @param[out] denom_priv where to write the private key
 * @param[out] deonm_pub where to write the public key
 * @param cipher which type of cipher to use
 * @param ... cipher-specific parameters
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
 * @param dk denomination public key to blind for
 * @param coin_bks blinding secret to use
 * @param age_commitment_hash hash of the age commitment to be used for the coin. NULL if no commitment is made.
 * @param coin_pub public key of the coin to blind
 * @param[out] c_hash resulting hashed coin
 * @param[out] coin_ev blinded coin to submit
 * @param[out] coin_ev_size number of bytes in @a coin_ev
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_blind (const struct TALER_DenominationPublicKey *dk,
                   const union TALER_DenominationBlindingKeyP *coin_bks,
                   const struct TALER_AgeHash *age_commitment_hash,
                   const struct TALER_CoinSpendPublicKeyP *coin_pub,
                   struct TALER_CoinPubHash *c_hash,
                   void **coin_ev,
                   size_t *coin_ev_size);


/**
 * Create blinded signature.
 *
 * @param[out] denom_sig where to write the signature
 * @param denom_priv private key to use for signing
 * @param blinded_msg message to sign
 * @param blinded_msg_size number of bytes in @a blinded_msg
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_sign_blinded (struct TALER_BlindedDenominationSignature *denom_sig,
                          const struct TALER_DenominationPrivateKey *denom_priv,
                          void *blinded_msg,
                          size_t blinded_msg_size);


/**
 * Unblind blinded signature.
 *
 * @param[out] denom_sig where to write the unblinded signature
 * @param bdenom_sig the blinded signature
 * @param bks blinding secret to use
 * @param denom_pub public key used for signing
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_denom_sig_unblind (
  struct TALER_DenominationSignature *denom_sig,
  const struct TALER_BlindedDenominationSignature *bdenom_sig,
  const union TALER_DenominationBlindingKeyP *bks,
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
                      struct TALER_DenominationHash *denom_hash);


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_str public key to copy
 */
void
TALER_denom_pub_deep_copy (struct TALER_DenominationPublicKey *denom_dst,
                           const struct TALER_DenominationPublicKey *denom_src);


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_str public key to copy
 */
void
TALER_denom_sig_deep_copy (struct TALER_DenominationSignature *denom_dst,
                           const struct TALER_DenominationSignature *denom_src);


/**
 * Make a (deep) copy of the given @a denom_src to
 * @a denom_dst.
 *
 * @param[out] denom_dst target to copy to
 * @param denom_str public key to copy
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
                        const struct TALER_CoinPubHash *c_hash);


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
 * @param coin_ev blinded coin
 * @param coin_ev_size number of bytes in @a coin_ev
 * @param[out] bch where to write the hash
 */
void
TALER_coin_ev_hash (const void *coin_ev,
                    size_t coin_ev_size,
                    struct TALER_BlindedCoinHash *bch);


/**
 * Compute the hash of a coin.
 *
 * @param coin_pub public key of the coin
 * @param age_commitment_hash hash of the age commitment vector. NULL, if no age commitment was set
 * @param[out] coin_h where to write the hash
 */
void
TALER_coin_pub_hash (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const struct TALER_AgeHash *age_commitment_hash,
                     struct TALER_CoinPubHash *coin_h);


/**
 * Compute the hash of a payto URI.
 *
 * @param payto URI to hash
 * @param[out] h_payto where to write the hash
 */
void
TALER_payto_hash (const char *payto,
                  struct TALER_PaytoHash *h_payto);


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Header for serializations of coin-specific information about the
 * fresh coins we generate.  These are the secrets that arise during
 * planchet generation, which is the first stage of creating a new
 * coin.
 */
struct TALER_PlanchetSecretsP
{

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * The blinding key.
   */
  union TALER_DenominationBlindingKeyP blinding_key;

};


GNUNET_NETWORK_STRUCT_END


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
  struct TALER_DenominationHash denom_pub_hash;

  /**
   * Blinded coin (see GNUNET_CRYPTO_rsa_blind()).  Note: is malloc()'ed!
   */
  void *coin_ev;

  /**
   * Number of bytes in @a coin_ev.
   */
  size_t coin_ev_size;
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
   * FIXME-Oec: Age-verification vector, as pointer: Dyn alloc!
   */
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
 * Setup information for a fresh coin, deriving the coin private key
 * and the blinding factor from the @a secret_seed with a KDF salted
 * by the @a coin_num_salt.
 *
 * @param secret_seed seed to use for KDF to derive coin keys
 * @param coin_num_salt number of the coin to include in KDF
 * @param[out] ps value to initialize
 */
void
TALER_planchet_setup_refresh (const struct TALER_TransferSecretP *secret_seed,
                              uint32_t coin_num_salt,
                              struct TALER_PlanchetSecretsP *ps);


/**
 * Setup information for a fresh coin.
 *
 * @param[out] ps value to initialize
 */
void
TALER_planchet_setup_random (struct TALER_PlanchetSecretsP *ps);


/**
 * Prepare a planchet for tipping.  Creates and blinds a coin.
 *
 * @param dk denomination key for the coin to be created
 * @param ps secret planchet internals (for #TALER_planchet_to_coin)
 * @param[out] c_hash set to the hash of the public key of the coin (needed later)
 * @param[out] pd set to the planchet detail for TALER_MERCHANT_tip_pickup() and
 *               other withdraw operations
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_PlanchetSecretsP *ps,
                        struct TALER_CoinPubHash *c_hash,
                        struct TALER_PlanchetDetail *pd);


/**
 * Obtain a coin from the planchet's secrets and the blind signature
 * of the exchange.
 *
 * @param dk denomination key, must match what was given to #TALER_planchet_prepare()
 * @param blind_sig blind signature from the exchange
 * @param ps secrets from #TALER_planchet_prepare()
 * @param c_hash hash of the coin's public key for verification of the signature
 * @param[out] coin set to the details of the fresh coin
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_planchet_to_coin (
  const struct TALER_DenominationPublicKey *dk,
  const struct TALER_BlindedDenominationSignature *blind_sig,
  const struct TALER_PlanchetSecretsP *ps,
  const struct TALER_CoinPubHash *c_hash,
  struct TALER_FreshCoin *coin);


/* ****************** Refresh crypto primitives ************* */


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
   * The envelope with the blinded coin.
   */
  void *coin_ev;

  /**
   * Number of bytes in @a coin_ev
   */
  size_t coin_ev_size;

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
 * @param num_new_coins number of new coins to be created
 * @param rcs array of @a kappa commitments
 * @param coin_pub public key of the coin to be melted
 * @param amount_with_fee amount to be melted, including fee
 */
void
TALER_refresh_get_commitment (struct TALER_RefreshCommitmentP *rc,
                              uint32_t kappa,
                              uint32_t num_new_coins,
                              const struct TALER_RefreshCommitmentEntry *rcs,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct TALER_Amount *amount_with_fee);

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
 * @param h_rsa hash of the RSA public key to use to sign
 * @param msg message to sign
 * @param msg_size number of bytes in @a msg
 * @param[out] ec set to the error code (or #TALER_EC_NONE on success)
 * @return signature, the value inside the structure will be NULL on failure,
 *         see @a ec for details about the failure
 */
struct TALER_BlindedDenominationSignature
TALER_CRYPTO_helper_rsa_sign (
  struct TALER_CRYPTO_RsaDenominationHelper *dh,
  const struct TALER_RsaPubHashP *h_rsa,
  const void *msg,
  size_t msg_size,
  enum TALER_ErrorCode *ec);


/**
 * Ask the helper to revoke the public key associated with @param h_denom_pub .
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
 * Ask the helper to revoke the public key @param exchange_pub .
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


/* ********************* exchange signing ************************** */


/**
 * Verify a deposit confirmation.
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
 * @param exchange_pub exchange's online signing public key
 * @param exchange_sig the signature made with purpose #TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_deposit_confirm_verify (
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_ExtensionContractHash *h_extensions,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp wire_deadline,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_Amount *amount_without_fee,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig);


/* ********************* wallet signing ************************** */


/**
 * Sign a deposit permission.  Function for wallets.
 *
 * @param amount the amount to be deposited
 * @param deposit_fee the deposit fee we expect to pay
 * @param h_wire hash of the merchant’s account details
 * @param h_contract_terms hash of the contact of the merchant with the customer (further details are never disclosed to the exchange)
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
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_ExtensionContractHash *h_extensions,
  const struct TALER_DenominationHash *h_denom_pub,
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
  const struct TALER_MerchantWireHash *h_wire,
  const struct TALER_PrivateContractHash *h_contract_terms,
  const struct TALER_ExtensionContractHash *h_extensions,
  const struct TALER_DenominationHash *h_denom_pub,
  struct GNUNET_TIME_Timestamp wallet_timestamp,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  struct GNUNET_TIME_Timestamp refund_deadline,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign a melt request.
 *
 * @param amount the amount to be melted (with fee)
 * @param melt_fee the melt fee we expect to pay
 * @param rc refresh session we are committed to
 * @param h_denom_pub hash of the coin denomination's public key
 * @param coin_priv coin’s private key
 * @param[out] coin_sig set to the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_MELT
 */
void
TALER_wallet_melt_sign (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Verify a melt request.
 *
 * @param amount the amount to be melted (with fee)
 * @param melt_fee the melt fee we expect to pay
 * @param rc refresh session we are committed to
 * @param h_denom_pub hash of the coin denomination's public key
 * @param coin_pub coin’s public key
 * @param coin_sig the signature made with purpose #TALER_SIGNATURE_WALLET_COIN_MELT
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_wallet_melt_verify (
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *melt_fee,
  const struct TALER_RefreshCommitmentP *rc,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign link data.
 *
 * @param h_denom_pub hash of the denomiantion public key of the new coin
 * @param transfer_pub transfer public key
 * @param coin_ev coin envelope
 * @param coin_ev_size number of bytes in @a coin_ev
 * @param old_coin_priv private key to sign with
 * @param[out] coin_sig resulting signature
 */
void
TALER_wallet_link_sign (const struct TALER_DenominationHash *h_denom_pub,
                        const struct TALER_TransferPublicKeyP *transfer_pub,
                        const void *coin_ev,
                        size_t coin_ev_size,
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
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_TransferPublicKeyP *transfer_pub,
  const struct TALER_BlindedCoinHash *h_coin_ev,
  const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Sign link data.
 *
 * @param h_denom_pub hash of the denomiantion public key of the new coin
 * @param transfer_pub transfer public key
 * @param coin_ev coin envelope
 * @param coin_ev_size number of bytes in @a coin_ev
 * @param old_coin_priv private key to sign with
 * @param[out] coin_sig resulting signature
 */
void
TALER_wallet_link_sign (const struct TALER_DenominationHash *h_denom_pub,
                        const struct TALER_TransferPublicKeyP *transfer_pub,
                        const void *coin_ev,
                        size_t coin_ev_size,
                        const struct TALER_CoinSpendPrivateKeyP *old_coin_priv,
                        struct TALER_CoinSpendSignatureP *coin_sig);


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
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Create recoup signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin
 * @param coin_bks blinding factor used when withdrawing the coin
 * @param requested_amount amount that is left to be recouped
 * @param coin_priv coin key of the coin to be recouped
 * @param coin_sig resulting signature
 */
void
TALER_wallet_recoup_sign (
  const struct TALER_DenominationHash *h_denom_pub,
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
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_CoinSpendSignatureP *coin_sig);


/**
 * Create recoup-refresh signature.
 *
 * @param h_denom_pub hash of the denomiantion public key of the coin
 * @param coin_bks blinding factor used when withdrawing the coin
 * @param requested_amount amount that is left to be recouped
 * @param coin_priv coin key of the coin to be recouped
 * @param coin_sig resulting signature
 */
void
TALER_wallet_recoup_refresh_sign (
  const struct TALER_DenominationHash *h_denom_pub,
  const union TALER_DenominationBlindingKeyP *coin_bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_CoinSpendSignatureP *coin_sig);


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
  const struct TALER_PrivateContractHash *h_contract_terms,
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
  const struct TALER_PrivateContractHash *h_contract_terms,
  uint64_t rtransaction_id,
  const struct TALER_Amount *amount,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_MerchantSignatureP *merchant_sig);


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
  const struct TALER_DenominationHash *h_denom_pub,
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
  const struct TALER_DenominationHash *h_denom_pub,
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
 * @param fee_withdraw what withdraw fee does the exchange charge for this denomination
 * @param fee_deposit what deposit fee does the exchange charge for this denomination
 * @param fee_refresh what refresh fee does the exchange charge for this denomination
 * @param fee_refund what refund fee does the exchange charge for this denomination
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_denom_validity_sign (
  const struct TALER_DenominationHash *h_denom_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
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
 * @param fee_withdraw what withdraw fee does the exchange charge for this denomination
 * @param fee_deposit what deposit fee does the exchange charge for this denomination
 * @param fee_refresh what refresh fee does the exchange charge for this denomination
 * @param fee_refund what refund fee does the exchange charge for this denomination
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_denom_validity_verify (
  const struct TALER_DenominationHash *h_denom_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
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
 * @param fee_withdraw what withdraw fee does the exchange charge for this denomination
 * @param fee_deposit what deposit fee does the exchange charge for this denomination
 * @param fee_refresh what refresh fee does the exchange charge for this denomination
 * @param fee_refund what refund fee does the exchange charge for this denomination
 * @param auditor_priv private key to sign with
 * @param[out] auditor_sig where to write the signature
 */
void
TALER_auditor_denom_validity_sign (
  const char *auditor_url,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
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
 * @param fee_withdraw what withdraw fee does the exchange charge for this denomination
 * @param fee_deposit what deposit fee does the exchange charge for this denomination
 * @param fee_refresh what refresh fee does the exchange charge for this denomination
 * @param fee_refund what refund fee does the exchange charge for this denomination
 * @param auditor_pub public key to verify against
 * @param auditor_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_auditor_denom_validity_verify (
  const char *auditor_url,
  const struct TALER_DenominationHash *h_denom_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct GNUNET_TIME_Timestamp stamp_start,
  struct GNUNET_TIME_Timestamp stamp_expire_withdraw,
  struct GNUNET_TIME_Timestamp stamp_expire_deposit,
  struct GNUNET_TIME_Timestamp stamp_expire_legal,
  const struct TALER_Amount *coin_value,
  const struct TALER_Amount *fee_withdraw,
  const struct TALER_Amount *fee_deposit,
  const struct TALER_Amount *fee_refresh,
  const struct TALER_Amount *fee_refund,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig);


/* **************** /wire account offline signing **************** */


/**
 * Create wire fee signature.
 *
 * @param payment_method the payment method
 * @param start_time when do the fees start to apply
 * @param end_time when do the fees start to apply
 * @param wire_fee the wire fee
 * @param closing_fee the closing fee
 * @param master_priv private key to sign with
 * @param[out] master_sig where to write the signature
 */
void
TALER_exchange_offline_wire_fee_sign (
  const char *payment_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_Amount *wire_fee,
  const struct TALER_Amount *closing_fee,
  const struct TALER_MasterPrivateKeyP *master_priv,
  struct TALER_MasterSignatureP *master_sig);


/**
 * Verify wire fee signature.
 *
 * @param payment_method the payment method
 * @param start_time when do the fees start to apply
 * @param end_time when do the fees start to apply
 * @param wire_fee the wire fee
 * @param closing_fee the closing fee
 * @param master_pub public key to verify against
 * @param master_sig the signature the signature
 * @return #GNUNET_OK if the signature is valid
 */
enum GNUNET_GenericReturnValue
TALER_exchange_offline_wire_fee_verify (
  const char *payment_method,
  struct GNUNET_TIME_Timestamp start_time,
  struct GNUNET_TIME_Timestamp end_time,
  const struct TALER_Amount *wire_fee,
  const struct TALER_Amount *closing_fee,
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
                                    const struct TALER_WireSalt *salt,
                                    struct TALER_MerchantWireHash *hc);


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
  const struct TALER_WireSalt *salt,
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
  const struct TALER_WireSalt *salt,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct TALER_MerchantSignatureP *merch_sig);


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
  const struct TALER_ExtensionConfigHash h_config,
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
  const struct TALER_ExtensionConfigHash h_config,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig
  );


#endif
