/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file include/taler_crypto_lib.h
 * @brief taler-specific crypto functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef TALER_CRYPTO_LIB_H
#define TALER_CRYPTO_LIB_H

#if HAVE_GNUNET_GNUNET_UTIL_LIB_H
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#elif HAVE_GNUNET_GNUNET_UTIL_TALER_WALLET_LIB_H
#include <gnunet/gnunet_util_taler_wallet_lib.h>
#include "taler_util_wallet.h"
#endif

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


GNUNET_NETWORK_STRUCT_END

/**
 * @brief Type of blinding keys for Taler.
 */
struct TALER_DenominationBlindingKey
{
  /**
   * Taler uses RSA for blinding.
   */
  struct GNUNET_CRYPTO_rsa_BlindingKey *rsa_blinding_key;
};


/**
 * @brief Type of (unblinded) coin signatures for Taler.
 */
struct TALER_DenominationSignature
{
  /**
   * Taler uses RSA for blinding.
   */
  struct GNUNET_CRYPTO_rsa_Signature *rsa_signature;
};


/**
 * @brief Type of public signing keys for verifying blindly signed coins.
 */
struct TALER_DenominationPublicKey
{
  /**
   * Taler uses RSA for signing coins.
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *rsa_public_key;
};


/**
 * @brief Type of private signing keys for blind signing of coins.
 */
struct TALER_DenominationPrivateKey
{
  /**
   * Taler uses RSA for signing coins.
   */
  struct GNUNET_CRYPTO_rsa_PrivateKey *rsa_private_key;
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
   * Public key representing the denomination of the coin
   * that is being deposited.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * (Unblinded) signature over @e coin_pub with @e denom_pub,
   * which demonstrates that the coin is valid.
   */
  struct TALER_DenominationSignature denom_sig;
};


/**
 * Check if a coin is valid; that is, whether the denomination key exists,
 * is not expired, and the signature is correct.
 *
 * @param coin_public_info the coin public info to check for validity
 * @return #GNUNET_YES if the coin is valid,
 *         #GNUNET_NO if it is invalid
 *         #GNUNET_SYSERROR if an internal error occured
 */
int
TALER_test_coin_valid (const struct TALER_CoinPublicInfo *coin_public_info);


/* ****************** Refresh crypto primitives ************* */


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * @brief Secret used to decrypt the key to decrypt link secrets.
 */
struct TALER_TransferSecretP
{
  /**
   * Secret used to encrypt/decrypt the `struct TALER_LinkSecretP`.
   * Must be (currently) a hash as this is what
   * #GNUNET_CRYPTO_ecc_ecdh() returns to us.
   */
  struct GNUNET_HashCode key;
};


/**
 * @brief Secret used to decrypt refresh links.
 */
struct TALER_LinkSecretP
{
  /**
   * Secret used to decrypt the refresh link data.
   */
  char key[sizeof (struct GNUNET_HashCode)];
};


/**
 * @brief Encrypted secret used to decrypt refresh links.
 */
struct TALER_EncryptedLinkSecretP
{
  /**
   * Encrypted secret, must be the given size!
   */
  char enc[sizeof (struct TALER_LinkSecretP)];
};


/**
 * @brief Representation of an refresh link in cleartext.
 */
struct TALER_RefreshLinkDecrypted
{

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Blinding key.
   */
  struct TALER_DenominationBlindingKey blinding_key;

};


/**
 * Length of the raw value in the Taler wire transfer identifier
 * (in binary representation).
 */
#define TALER_WIRE_TRANSFER_IDENTIFIER_LEN 32

/**
 * #TALER_WIRE_TRANSFER_IDENTIFIER_LEN as a string.
 */
#define TALER_WIRE_TRANSFER_IDENTIFIER_LEN_STR "32"

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
  uint8_t raw[TALER_WIRE_TRANSFER_IDENTIFIER_LEN];
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
 * @brief Representation of an encrypted refresh link.
 */
struct TALER_RefreshLinkEncrypted
{

  /**
   * Encrypted blinding key with @e blinding_key_enc_size bytes,
   * must be allocated at the end of this struct.
   */
  const char *blinding_key_enc;

  /**
   * Number of bytes in @e blinding_key_enc.
   */
  size_t blinding_key_enc_size;

  /**
   * Encrypted private key of the coin.
   */
  char coin_priv_enc[sizeof (struct TALER_CoinSpendPrivateKeyP)];

};


/**
 * Decrypt the shared @a secret from the information in the
 * encrypted link secret @e secret_enc using the transfer
 * private key and the coin's public key.
 *
 * @param secret_enc encrypted link secret
 * @param trans_priv transfer private key
 * @param coin_pub coin public key
 * @param[out] secret set to the shared secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_decrypt_secret (const struct TALER_EncryptedLinkSecretP *secret_enc,
			   const struct TALER_TransferPrivateKeyP *trans_priv,
			   const struct TALER_CoinSpendPublicKeyP *coin_pub,
			   struct TALER_LinkSecretP *secret);


/**
 * Decrypt the shared @a secret from the information in the
 * encrypted link secret @e secret_enc using the transfer
 * public key and the coin's private key.
 *
 * @param secret_enc encrypted link secret
 * @param trans_pub transfer public key
 * @param coin_priv coin private key
 * @param[out] secret set to the shared secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_decrypt_secret2 (const struct TALER_EncryptedLinkSecretP *secret_enc,
			    const struct TALER_TransferPublicKeyP *trans_pub,
			    const struct TALER_CoinSpendPrivateKeyP *coin_priv,
			    struct TALER_LinkSecretP *secret);


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
TALER_link_derive_transfer_secret (const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                                   const struct TALER_TransferPrivateKeyP *trans_priv,
                                   struct TALER_TransferSecretP *ts);


/**
 * Encrypt the shared @a secret to generate the encrypted link secret.
 * Also creates the transfer key.
 *
 * @param secret link secret to encrypt
 * @param coin_pub coin public key
 * @param[out] trans_priv set to transfer private key
 * @param[out] trans_pub set to transfer public key
 * @param[out] secret_enc set to the encryptd @a secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_encrypt_secret (const struct TALER_LinkSecretP *secret,
			   const struct TALER_CoinSpendPublicKeyP *coin_pub,
			   struct TALER_TransferPrivateKeyP *trans_priv,
			   struct TALER_TransferPublicKeyP *trans_pub,
			   struct TALER_EncryptedLinkSecretP *secret_enc);


/**
 * Use the @a trans_sec (from ECDHE) to decrypt the @a secret_enc
 * to obtain the @a secret to decrypt the linkage data.
 *
 * @param secret_enc encrypted secret
 * @param trans_sec transfer secret
 * @param secret shared secret for refresh link decryption
 * @return #GNUNET_OK on success
 */
int
TALER_transfer_decrypt (const struct TALER_EncryptedLinkSecretP *secret_enc,
                        const struct TALER_TransferSecretP *trans_sec,
                        struct TALER_LinkSecretP *secret);


/**
 * Use the @a trans_sec (from ECDHE) to encrypt the @a secret
 * to obtain the @a secret_enc.
 *
 * @param secret shared secret for refresh link decryption
 * @param trans_sec transfer secret
 * @param[out] secret_enc encrypted secret
 * @return #GNUNET_OK on success
 */
int
TALER_transfer_encrypt (const struct TALER_LinkSecretP *secret,
                        const struct TALER_TransferSecretP *trans_sec,
                        struct TALER_EncryptedLinkSecretP *secret_enc);


/**
 * Decrypt refresh link information.
 *
 * @param input encrypted refresh link data
 * @param secret shared secret to use for decryption
 * @return NULL on error
 */
struct TALER_RefreshLinkDecrypted *
TALER_refresh_decrypt (const struct TALER_RefreshLinkEncrypted *input,
                       const struct TALER_LinkSecretP *secret);


/**
 * Encrypt refresh link information.
 *
 * @param input plaintext refresh link data
 * @param secret shared secret to use for encryption
 * @return NULL on error (should never happen)
 */
struct TALER_RefreshLinkEncrypted *
TALER_refresh_encrypt (const struct TALER_RefreshLinkDecrypted *input,
                       const struct TALER_LinkSecretP *secret);


/**
 * Decode encrypted refresh link information from buffer.
 *
 * @param buf buffer with refresh link data
 * @param buf_len number of bytes in @a buf
 * @return NULL on error (@a buf_len too small)
 */
struct TALER_RefreshLinkEncrypted *
TALER_refresh_link_encrypted_decode (const char *buf,
                                     size_t buf_len);


/**
 * Encode encrypted refresh link information to buffer.
 *
 * @param rle refresh link to encode
 * @param[out] buf_len set number of bytes returned
 * @return NULL on error, otherwise buffer with encoded @a rle
 */
char *
TALER_refresh_link_encrypted_encode (const struct TALER_RefreshLinkEncrypted *rle,
                                     size_t *buf_len);



#endif
