/*
  This file is part of TALER
  (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 */
#ifndef TALER_CRYPTO_LIB_H
#define TALER_CRYPTO_LIB_H

#include <gnunet/gnunet_util_lib.h>
#include <gcrypt.h>


/* ****************** Coin crypto primitives ************* */

/**
 * Public information about a coin (including the public key
 * of the coin, the denomination key and the signature with
 * the denomination key).
 */
struct TALER_CoinPublicInfo
{
  /**
   * The coin's public key.
   */
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;

  /**
   * Public key representing the denomination of the coin
   * that is being deposited.
   */
  struct GNUNET_CRYPTO_rsa_PublicKey *denom_pub;

  /**
   * (Unblinded) signature over @e coin_pub with @e denom_pub,
   * which demonstrates that the coin is valid.
   */
  struct GNUNET_CRYPTO_rsa_Signature *denom_sig;
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

/**
 * Secret used to decrypt the key to decrypt link secrets.
 */
struct TALER_TransferSecret
{
  /**
   * Secret used to encrypt/decrypt the `struct TALER_LinkSecret`.
   * Must be (currently) a hash as this is what
   * #GNUNET_CRYPTO_ecc_ecdh() returns to us.
   */
  struct GNUNET_HashCode key;
};


/**
 * Secret used to decrypt refresh links.
 */
struct TALER_LinkSecret
{
  /**
   * Secret used to decrypt the refresh link data.
   */
  char key[sizeof (struct GNUNET_HashCode)];
};


/**
 * Encrypted secret used to decrypt refresh links.
 */
struct TALER_EncryptedLinkSecret
{
  /**
   * Encrypted secret, must be the given size!
   */
  char enc[sizeof (struct TALER_LinkSecret)];
};


/**
 * Representation of an encrypted refresh link.
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
  char coin_priv_enc[sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)];

};


/**
 * Representation of an refresh link in cleartext.
 */
struct TALER_RefreshLinkDecrypted
{

  /**
   * Private key of the coin.
   */
  struct GNUNET_CRYPTO_EcdsaPrivateKey coin_priv;

  /**
   * Blinding key with @e blinding_key_enc_size bytes.
   */
  struct GNUNET_CRYPTO_rsa_BlindingKey *blinding_key;

};


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
TALER_transfer_decrypt (const struct TALER_EncryptedLinkSecret *secret_enc,
                        const struct TALER_TransferSecret *trans_sec,
                        struct TALER_LinkSecret *secret);


/**
 * Use the @a trans_sec (from ECDHE) to encrypt the @a secret
 * to obtain the @a secret_enc.
 *
 * @param secret shared secret for refresh link decryption
 * @param trans_sec transfer secret
 * @param secret_enc[out] encrypted secret
 * @return #GNUNET_OK on success
 */
int
TALER_transfer_encrypt (const struct TALER_LinkSecret *secret,
                        const struct TALER_TransferSecret *trans_sec,
                        struct TALER_EncryptedLinkSecret *secret_enc);


/**
 * Decrypt refresh link information.
 *
 * @param input encrypted refresh link data
 * @param secret shared secret to use for decryption
 * @return NULL on error
 */
struct TALER_RefreshLinkDecrypted *
TALER_refresh_decrypt (const struct TALER_RefreshLinkEncrypted *input,
                       const struct TALER_LinkSecret *secret);


/**
 * Encrypt refresh link information.
 *
 * @param input plaintext refresh link data
 * @param secret shared secret to use for encryption
 * @return NULL on error (should never happen)
 */
struct TALER_RefreshLinkEncrypted *
TALER_refresh_encrypt (const struct TALER_RefreshLinkDecrypted *input,
                       const struct TALER_LinkSecret *secret);


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



#endif
