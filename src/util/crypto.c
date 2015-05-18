/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file util/crypto.c
 * @brief Cryptographic utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_util_lib.h>
#include <gcrypt.h>


/**
 * Function called by libgcrypt on serious errors.
 * Prints an error message and aborts the process.
 *
 * @param cls NULL
 * @param wtf unknown
 * @param msg error message
 */
static void
fatal_error_handler (void *cls,
                     int wtf,
                     const char *msg)
{
  fprintf (stderr,
           "Fatal error in libgcrypt: %s\n",
           msg);
  abort();
}


/**
 * Initialize libgcrypt.
 */
void
TALER_gcrypt_init ()
{
  gcry_set_fatalerror_handler (&fatal_error_handler,
                               NULL);
  if (! gcry_check_version (NEED_LIBGCRYPT_VERSION))
  {
    fprintf (stderr,
             "libgcrypt version mismatch\n");
    abort ();
  }
  /* Disable secure memory.  */
  gcry_control (GCRYCTL_DISABLE_SECMEM, 0);
  gcry_control (GCRYCTL_INITIALIZATION_FINISHED, 0);
}


/**
 * Derive symmetric key material for refresh operations from
 * a given shared secret for link decryption.
 *
 * @param secret the shared secret
 * @param[out] iv set to initialization vector
 * @param[out] skey set to session key
 */
static void
derive_refresh_key (const struct TALER_LinkSecretP *secret,
                    struct GNUNET_CRYPTO_SymmetricInitializationVector *iv,
                    struct GNUNET_CRYPTO_SymmetricSessionKey *skey)
{
  static const char ctx_key[] = "taler-link-skey";
  static const char ctx_iv[] = "taler-link-iv";

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (skey, sizeof (struct GNUNET_CRYPTO_SymmetricSessionKey),
                                    ctx_key, strlen (ctx_key),
                                    secret, sizeof (struct TALER_LinkSecretP),
                                    NULL, 0));
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (iv, sizeof (struct GNUNET_CRYPTO_SymmetricInitializationVector),
                                    ctx_iv, strlen (ctx_iv),
                                    secret, sizeof (struct TALER_LinkSecretP),
                                    NULL, 0));
}


/**
 * Derive symmetric key material for refresh operations from
 * a given shared secret for key decryption.
 *
 * @param secret the shared secret
 * @param[out] iv set to initialization vector
 * @param[out] skey set to session key
 */
static void
derive_transfer_key (const struct TALER_TransferSecretP *secret,
                     struct GNUNET_CRYPTO_SymmetricInitializationVector *iv,
                     struct GNUNET_CRYPTO_SymmetricSessionKey *skey)
{
  static const char ctx_key[] = "taler-transfer-skey";
  static const char ctx_iv[] = "taler-transfer-iv";

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (skey, sizeof (struct GNUNET_CRYPTO_SymmetricSessionKey),
                                    ctx_key, strlen (ctx_key),
                                    secret, sizeof (struct TALER_TransferSecretP),
                                    NULL, 0));
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (iv, sizeof (struct GNUNET_CRYPTO_SymmetricInitializationVector),
                                    ctx_iv, strlen (ctx_iv),
                                    secret, sizeof (struct TALER_TransferSecretP),
                                    NULL, 0));
}


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
                        struct TALER_LinkSecretP *secret)
{
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  ssize_t s;

  GNUNET_assert (sizeof (struct TALER_EncryptedLinkSecretP) ==
                 sizeof (struct TALER_LinkSecretP));
  derive_transfer_key (trans_sec, &iv, &skey);
  s = GNUNET_CRYPTO_symmetric_decrypt (secret_enc,
				       sizeof (struct TALER_LinkSecretP),
				       &skey,
				       &iv,
				       secret);
  if (sizeof (struct TALER_LinkSecretP) != s)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


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
                        struct TALER_EncryptedLinkSecretP *secret_enc)
{
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  ssize_t s;

  GNUNET_assert (sizeof (struct TALER_EncryptedLinkSecretP) ==
                 sizeof (struct TALER_LinkSecretP));
  derive_transfer_key (trans_sec, &iv, &skey);
  s = GNUNET_CRYPTO_symmetric_encrypt (secret,
				       sizeof (struct TALER_LinkSecretP),
				       &skey,
				       &iv,
				       secret_enc);
  if (sizeof (struct TALER_LinkSecretP) != s)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Decrypt refresh link information.
 *
 * @param input encrypted refresh link data
 * @param secret shared secret to use for decryption
 * @return NULL on error
 */
struct TALER_RefreshLinkDecrypted *
TALER_refresh_decrypt (const struct TALER_RefreshLinkEncrypted *input,
                       const struct TALER_LinkSecretP *secret)
{
  struct TALER_RefreshLinkDecrypted *ret;
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  size_t buf_size = input->blinding_key_enc_size
    + sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey);
  char buf[buf_size];

  GNUNET_assert (input->blinding_key_enc == (const char *) &input[1]);
  derive_refresh_key (secret, &iv, &skey);
  if (buf_size !=
      GNUNET_CRYPTO_symmetric_decrypt (input->coin_priv_enc,
                                       buf_size,
                                       &skey,
                                       &iv,
                                       buf))
    return NULL;
  ret = GNUNET_new (struct TALER_RefreshLinkDecrypted);
  memcpy (&ret->coin_priv,
          buf,
          sizeof (union TALER_CoinSpendPrivateKeyP));
  ret->blinding_key.rsa_blinding_key
    = GNUNET_CRYPTO_rsa_blinding_key_decode (&buf[sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)],
                                             input->blinding_key_enc_size);
  if (NULL == ret->blinding_key.rsa_blinding_key)
  {
    GNUNET_free (ret);
    return NULL;
  }
  return ret;
}


/**
 * Encrypt refresh link information.
 *
 * @param input plaintext refresh link data
 * @param secret shared secret to use for encryption
 * @return NULL on error (should never happen)
 */
struct TALER_RefreshLinkEncrypted *
TALER_refresh_encrypt (const struct TALER_RefreshLinkDecrypted *input,
                       const struct TALER_LinkSecretP *secret)
{
  char *b_buf;
  size_t b_buf_size;
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  struct TALER_RefreshLinkEncrypted *ret;

  derive_refresh_key (secret, &iv, &skey);
  b_buf_size = GNUNET_CRYPTO_rsa_blinding_key_encode (input->blinding_key.rsa_blinding_key,
                                                      &b_buf);
  ret = GNUNET_malloc (sizeof (struct TALER_RefreshLinkEncrypted) +
                       b_buf_size);
  ret->blinding_key_enc = (const char *) &ret[1];
  ret->blinding_key_enc_size = b_buf_size;
  {
    size_t buf_size = b_buf_size + sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey);
    char buf[buf_size];

    memcpy (buf,
            &input->coin_priv,
            sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey));
    memcpy (&buf[sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)],
            b_buf,
            b_buf_size);

    if (buf_size !=
        GNUNET_CRYPTO_symmetric_encrypt (buf,
                                         buf_size,
                                         &skey,
                                         &iv,
                                         ret->coin_priv_enc))
    {
      GNUNET_free (ret);
      return NULL;
    }
  }
  return ret;
}


/**
 * Decode encrypted refresh link information from buffer.
 *
 * @param buf buffer with refresh link data
 * @param buf_len number of bytes in @a buf
 * @return NULL on error (@a buf_len too small)
 */
struct TALER_RefreshLinkEncrypted *
TALER_refresh_link_encrypted_decode (const char *buf,
                                     size_t buf_len)
{
  struct TALER_RefreshLinkEncrypted *rle;

  if (buf_len < sizeof (union TALER_CoinSpendPrivateKeyP))
    return NULL;
  if (buf_len >= GNUNET_MAX_MALLOC_CHECKED)
  {
    GNUNET_break (0);
    return NULL;
  }
  rle = GNUNET_malloc (sizeof (struct TALER_RefreshLinkEncrypted) +
                       buf_len - sizeof (union TALER_CoinSpendPrivateKeyP));
  rle->blinding_key_enc = (const char *) &rle[1];
  rle->blinding_key_enc_size = buf_len - sizeof (union TALER_CoinSpendPrivateKeyP);
  memcpy (rle->coin_priv_enc,
          buf,
          buf_len);
  return rle;
}


/**
 * Encode encrypted refresh link information to buffer.
 *
 * @param rle refresh link to encode
 * @param[out] buf_len set number of bytes returned
 * @return NULL on error, otherwise buffer with encoded @a rle
 */
char *
TALER_refresh_link_encrypted_encode (const struct TALER_RefreshLinkEncrypted *rle,
                                     size_t *buf_len)
{
  char *buf;

  if (rle->blinding_key_enc_size >= GNUNET_MAX_MALLOC_CHECKED - sizeof (union TALER_CoinSpendPrivateKeyP))
  {
    GNUNET_break (0);
    return NULL;
  }
  *buf_len = sizeof (union TALER_CoinSpendPrivateKeyP) + rle->blinding_key_enc_size;
  buf = GNUNET_malloc (*buf_len);
  memcpy (buf,
	  rle->coin_priv_enc,
          *buf_len);
  return buf;
}


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
TALER_test_coin_valid (const struct TALER_CoinPublicInfo *coin_public_info)
{
  struct GNUNET_HashCode c_hash;

  GNUNET_CRYPTO_hash (&coin_public_info->coin_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &c_hash);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_rsa_verify (&c_hash,
                                coin_public_info->denom_sig.rsa_signature,
                                coin_public_info->denom_pub.rsa_public_key))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "coin signature is invalid\n");
    return GNUNET_NO;
  }
  return GNUNET_YES;
}


/**
 * Decrypt the shared @a secret from the information in the
 * encrypted link secret @e secret_enc using the transfer
 * private key and the coin's public key.
 *
 * @param secret_enc encrypted link secret
 * @param transfer_priv transfer private key
 * @param coin_pub coin public key
 * @param[out] secret set to the shared secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_decrypt_secret (const struct TALER_EncryptedLinkSecretP *secret_enc,
			   const struct TALER_TransferPrivateKeyP *trans_priv,
			   const union TALER_CoinSpendPublicKeyP *coin_pub,
			   struct TALER_LinkSecretP *secret)
{
  struct TALER_TransferSecretP transfer_secret;

  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecc_ecdh (&trans_priv->ecdhe_priv,
			      &coin_pub->ecdhe_pub,
			      &transfer_secret.key))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_transfer_decrypt (secret_enc,
			      &transfer_secret,
			      secret))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Decrypt the shared @a secret from the information in the
 * encrypted link secret @e secret_enc using the transfer
 * public key and the coin's private key.
 *
 * @param secret_enc encrypted link secret
 * @param transfer_pub transfer public key
 * @param coin_priv coin private key
 * @param[out] secret set to the shared secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_decrypt_secret2 (const struct TALER_EncryptedLinkSecretP *secret_enc,
			    const struct TALER_TransferPublicKeyP *trans_pub,
			    const union TALER_CoinSpendPrivateKeyP *coin_priv,
			    struct TALER_LinkSecretP *secret)
{
  struct TALER_TransferSecretP transfer_secret;

  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecc_ecdh (&coin_priv->ecdhe_priv,
			      &trans_pub->ecdhe_pub,
			      &transfer_secret.key))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_transfer_decrypt (secret_enc,
			      &transfer_secret,
			      secret))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Encrypt the shared @a secret to generate the encrypted link secret.
 * Also creates the transfer key.
 *
 * @param secret link secret to encrypt
 * @param coin_pub coin public key
 * @param transfer_priv[out] set to transfer private key
 * @param transfer_pub[out] set to transfer public key
 * @param[out] secret_enc set to the encryptd @a secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_encrypt_secret (const struct TALER_LinkSecretP *secret,
			   const union TALER_CoinSpendPublicKeyP *coin_pub,
			   struct TALER_TransferPrivateKeyP *trans_priv,
			   struct TALER_TransferPublicKeyP *trans_pub,
			   struct TALER_EncryptedLinkSecretP *secret_enc)
{
  struct TALER_TransferSecretP transfer_secret;
  struct GNUNET_CRYPTO_EcdhePrivateKey *pk;

  pk = GNUNET_CRYPTO_ecdhe_key_create ();
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecc_ecdh (pk,
			      &coin_pub->ecdhe_pub,
			      &transfer_secret.key))
  {
    GNUNET_break (0);
    GNUNET_free (pk);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_transfer_encrypt (secret,
			      &transfer_secret,
			      secret_enc))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  trans_priv->ecdhe_priv = *pk;
  GNUNET_CRYPTO_ecdhe_key_get_public (pk,
				      &trans_pub->ecdhe_pub);
  GNUNET_free (pk);
  return GNUNET_OK;
}


/* end of crypto.c */
