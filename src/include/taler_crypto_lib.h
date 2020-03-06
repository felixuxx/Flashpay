/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
#include "taler_util.h"

#include <gcrypt.h>


/* ****************** Coin crypto primitives ************* */

GNUNET_NETWORK_STRUCT_BEGIN

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
struct TALER_DenominationBlindingKeyP
{
  /**
   * Taler uses RSA for blind signatures.
   */
  struct GNUNET_CRYPTO_RsaBlindingKeySecret bks;
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


GNUNET_NETWORK_STRUCT_END


/**
 * @brief Type of (unblinded) coin signatures for Taler.
 */
struct TALER_DenominationSignature
{
  /**
   * Taler uses RSA for blinding.
   */
  struct GNUNET_CRYPTO_RsaSignature *rsa_signature;
};


/**
 * @brief Type of public signing keys for verifying blindly signed coins.
 */
struct TALER_DenominationPublicKey
{
  /**
   * Taler uses RSA for signing coins.
   */
  struct GNUNET_CRYPTO_RsaPublicKey *rsa_public_key;
};


/**
 * @brief Type of private signing keys for blind signing of coins.
 */
struct TALER_DenominationPrivateKey
{
  /**
   * Taler uses RSA for signing coins.
   */
  struct GNUNET_CRYPTO_RsaPrivateKey *rsa_private_key;
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
  struct GNUNET_HashCode denom_pub_hash;

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
  struct GNUNET_HashCode h_contract_terms;

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
 * Check if a coin is valid; that is, whether the denomination key exists,
 * is not expired, and the signature is correct.
 *
 * @param coin_public_info the coin public info to check for validity
 * @param denom_pub denomination key, must match @a coin_public_info's `denom_pub_hash`
 * @return #GNUNET_YES if the coin is valid,
 *         #GNUNET_NO if it is invalid
 *         #GNUNET_SYSERR if an internal error occured
 */
int
TALER_test_coin_valid (const struct TALER_CoinPublicInfo *coin_public_info,
                       const struct TALER_DenominationPublicKey *denom_pub);


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
  struct TALER_DenominationBlindingKeyP blinding_key;

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
  struct GNUNET_HashCode denom_pub_hash;

  /**
   * Hash of the coin's public key.  Kept around so we do not need to
   * compute it again.  Can be recomputed by hashing the public key
   * of @a coin_priv if storage is at a premium.
   */
  struct GNUNET_HashCode c_hash;

  /**
   * Blinded coin (see GNUNET_CRYPTO_rsa_blind()).  Note: is malloc()'ed!
   */
  char *coin_ev;

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
 * @param[out] pd set to the planchet detail for TALER_MERCHANT_tip_pickup() and
 *               other withdraw operations
 * @return #GNUNET_OK on success
 */
int
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_PlanchetSecretsP *ps,
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
int
TALER_planchet_to_coin (const struct TALER_DenominationPublicKey *dk,
                        const struct GNUNET_CRYPTO_RsaSignature *blind_sig,
                        const struct TALER_PlanchetSecretsP *ps,
                        const struct GNUNET_HashCode *c_hash,
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
  char *coin_ev;

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


/* **************** /wire account offline signing **************** */


/**
 * Compute the hash of the given wire details.   The resulting
 * hash is what is signed by the master key.
 *
 * @param payto_uri bank account
 * @param[out] hc set to the hash
 */
void
TALER_exchange_wire_signature_hash (const char *payto_uri,
                                    struct GNUNET_HashCode *hc);


/**
 * Check the signature in @a master_sig.
 *
 * @param payto_uri URL that is signed
 * @param master_pub master public key of the exchange
 * @param master_sig signature of the exchange
 * @return #GNUNET_OK if signature is valid
 */
int
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
                                    const char *salt,
                                    struct GNUNET_HashCode *hc);


/**
 * Check the signature in @a wire_s.
 *
 * @param payto_uri URL that is signed
 * @param salt the salt used to salt the @a payto_uri when hashing
 * @param merch_pub public key of the merchant
 * @param merch_sig signature of the merchant
 * @return #GNUNET_OK if signature is valid
 */
int
TALER_merchant_wire_signature_check (
  const char *payto_uri,
  const char *salt,
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
  const char *salt,
  const struct TALER_MerchantPrivateKeyP *merch_priv,
  struct TALER_MerchantSignatureP *merch_sig);


#endif
