/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @file crypto.c
 * @brief Cryptographic utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_util_lib.h>
#include <gcrypt.h>

#define CURVE "Ed25519"


static void
fatal_error_handler (void *cls, int wtf, const char *msg)
{
  LOG_ERROR("Fatal error in Gcrypt: %s\n", msg);
  abort();
}


/**
 * Initialize Gcrypt library.
 */
void
TALER_gcrypt_init()
{
  gcry_set_fatalerror_handler (&fatal_error_handler, NULL);
  TALER_assert_as(gcry_check_version(NEED_LIBGCRYPT_VERSION),
                  "libgcrypt version mismatch");
  /* Disable secure memory.  */
  gcry_control (GCRYCTL_DISABLE_SECMEM, 0);
  gcry_control (GCRYCTL_INITIALIZATION_FINISHED, 0);
}


/**
 * Derive symmetric key material for refresh operations from
 * a given shared secret.
 *
 * @param secret the shared secret
 * @param[out] iv set to initialization vector
 * @param[out] skey set to session key
 */
static void
derive_refresh_key (const struct GNUNET_HashCode *secret,
                    struct GNUNET_CRYPTO_SymmetricInitializationVector *iv,
                    struct GNUNET_CRYPTO_SymmetricSessionKey *skey)
{
  static const char ctx_key[] = "taler-key-skey";
  static const char ctx_iv[] = "taler-key-iv";

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (skey, sizeof (struct GNUNET_CRYPTO_SymmetricSessionKey),
                                    ctx_key, strlen (ctx_key),
                                    secret, sizeof (struct GNUNET_HashCode),
                                    NULL, 0));
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (iv, sizeof (struct GNUNET_CRYPTO_SymmetricInitializationVector),
                                    ctx_iv, strlen (ctx_iv),
                                    secret, sizeof (struct GNUNET_HashCode),
                                    NULL, 0));
}


/**
 * Use the @a trans_sec (from ECDHE) to decrypt the @a secret_enc
 * to obtain the @a secret to decrypt the linkage data.
 *
 * @param secret_enc encrypted secret (FIXME: use different type!)
 * @param trans_sec transfer secret (FIXME: use different type?)
 * @param secret shared secret for refresh link decryption
 *               (FIXME: use different type?)
 * @return #GNUNET_OK on success
 */
int
TALER_transfer_decrypt (const struct GNUNET_HashCode *secret_enc,
                        const struct GNUNET_HashCode *trans_sec,
                        struct GNUNET_HashCode *secret)
{
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;

  derive_refresh_key (trans_sec, &iv, &skey);
  return GNUNET_CRYPTO_symmetric_decrypt (secret_enc,
                                          sizeof (struct GNUNET_HashCode),
                                          &skey,
                                          &iv,
                                          secret);
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
                       const struct GNUNET_HashCode *secret)
{
  struct TALER_RefreshLinkDecrypted *ret;
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  size_t buf_size = input->blinding_key_enc_size
    + sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey);
  char buf[buf_size];

  GNUNET_assert (input->blinding_key_enc == (const char *) &input[1]);
  derive_refresh_key (secret, &iv, &skey);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_symmetric_decrypt (input->coin_priv_enc,
                                       buf_size,
                                       &skey,
                                       &iv,
                                       buf))
    return NULL;
  ret = GNUNET_new (struct TALER_RefreshLinkDecrypted);
  memcpy (&ret->coin_priv,
          buf,
          sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey));
  ret->blinding_key
    = GNUNET_CRYPTO_rsa_blinding_key_decode (&buf[sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)],
                                             input->blinding_key_enc_size);
  if (NULL == ret->blinding_key)
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
                       const struct GNUNET_HashCode *secret)
{
  char *b_buf;
  size_t b_buf_size;
  struct GNUNET_CRYPTO_SymmetricInitializationVector iv;
  struct GNUNET_CRYPTO_SymmetricSessionKey skey;
  struct TALER_RefreshLinkEncrypted *ret;

  derive_refresh_key (secret, &iv, &skey);
  b_buf_size = GNUNET_CRYPTO_rsa_blinding_key_encode (input->blinding_key,
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

    if (GNUNET_OK !=
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


/* end of crypto.c */
