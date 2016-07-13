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
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
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

#if HAVE_GNUNET_GNUNET_UTIL_TALER_WALLET_LIB_H
#include "taler_util_wallet.h"
#endif
#if HAVE_GNUNET_GNUNET_UTIL_LIB_H
#include "taler_util.h"
#endif
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
void  __attribute__ ((constructor))
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
                                   struct TALER_TransferSecretP *ts)
{
  struct TALER_CoinSpendPublicKeyP coin_pub;

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_ecdh_eddsa (&trans_priv->ecdhe_priv,
                                           &coin_pub.eddsa_pub,
                                           &ts->key));

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
 * @param[out] output where to write decrypted data
 */
void
TALER_refresh_decrypt (const struct TALER_RefreshLinkEncryptedP *input,
                       const struct TALER_LinkSecretP *secret,
		       struct TALER_RefreshLinkDecryptedP *output)
{
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;

  derive_refresh_key (secret, &iv, &skey);
  GNUNET_assert (sizeof (struct TALER_RefreshLinkEncryptedP) ==
		 sizeof (struct TALER_RefreshLinkDecryptedP));
  GNUNET_assert (sizeof (struct TALER_RefreshLinkEncryptedP) ==
		 GNUNET_CRYPTO_symmetric_decrypt (input,
						  sizeof (struct TALER_RefreshLinkEncryptedP),
						  &skey,
						  &iv,
						  output));
}


/**
 * Encrypt refresh link information.
 *
 * @param input plaintext refresh link data
 * @param secret shared secret to use for encryption
 * @param[out] output where to write encrypted link data
 */
void
TALER_refresh_encrypt (const struct TALER_RefreshLinkDecryptedP *input,
                       const struct TALER_LinkSecretP *secret,
		       struct TALER_RefreshLinkEncryptedP *output)
{
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;

  derive_refresh_key (secret, &iv, &skey);
  GNUNET_assert (sizeof (struct TALER_RefreshLinkEncryptedP) ==
		 sizeof (struct TALER_RefreshLinkDecryptedP));
  GNUNET_assert (sizeof (struct TALER_RefreshLinkEncryptedP) ==
		 GNUNET_CRYPTO_symmetric_encrypt (input,
						  sizeof (struct TALER_RefreshLinkDecryptedP),
						  &skey,
						  &iv,
						  output));
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
 * @param trans_priv transfer private key
 * @param coin_pub coin public key
 * @param[out] secret set to the shared secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_decrypt_secret (const struct TALER_EncryptedLinkSecretP *secret_enc,
			   const struct TALER_TransferPrivateKeyP *trans_priv,
			   const struct TALER_CoinSpendPublicKeyP *coin_pub,
			   struct TALER_LinkSecretP *secret)
{
  struct TALER_TransferSecretP transfer_secret;

  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdh_eddsa (&trans_priv->ecdhe_priv,
				&coin_pub->eddsa_pub,
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
 * @param trans_pub transfer public key
 * @param coin_priv coin private key
 * @param[out] secret set to the shared secret
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
int
TALER_link_decrypt_secret2 (const struct TALER_EncryptedLinkSecretP *secret_enc,
			    const struct TALER_TransferPublicKeyP *trans_pub,
			    const struct TALER_CoinSpendPrivateKeyP *coin_priv,
			    struct TALER_LinkSecretP *secret)
{
  struct TALER_TransferSecretP transfer_secret;

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_ecdh (&coin_priv->eddsa_priv,
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
			   struct TALER_EncryptedLinkSecretP *secret_enc)
{
  struct TALER_TransferSecretP transfer_secret;
  struct GNUNET_CRYPTO_EcdhePrivateKey *pk;

  pk = GNUNET_CRYPTO_ecdhe_key_create ();
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdh_eddsa (pk,
				&coin_pub->eddsa_pub,
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
