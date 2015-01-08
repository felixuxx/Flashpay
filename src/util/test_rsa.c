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
 * @file util/test_rsa.c
 * @brief testcase for utility functions for RSA cryptography
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_rsa.h"
#include <gnunet/gnunet_util_lib.h>

#define TEST_PURPOSE UINT32_MAX


#define EXITIF(cond)                                              \
  do {                                                            \
    if (cond) { GNUNET_break (0); goto EXITIF_exit; }             \
  } while (0)

int
main (int argc, char *argv[])
{
#define RND_BLK_SIZE 4096
  unsigned char rnd_blk[RND_BLK_SIZE];
  struct TALER_RSA_PrivateKey *priv;
  struct TALER_RSA_PrivateKeyBinaryEncoded *priv_enc;
  struct TALER_RSA_PublicKeyBinaryEncoded pubkey;
  struct TALER_RSA_BlindingKey *bkey;
  struct TALER_RSA_BlindedSignaturePurpose *bsp;
  struct TALER_RSA_Signature sig;
  struct GNUNET_HashCode hash;
  int ret;

  priv = NULL;
  bsp = NULL;
  bkey = NULL;
  ret = 1;
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, rnd_blk,
                              RND_BLK_SIZE);
  GNUNET_CRYPTO_hash (rnd_blk, RND_BLK_SIZE, &hash);
  priv = TALER_RSA_key_create ();
  GNUNET_assert (NULL != priv);
  EXITIF (GNUNET_OK != TALER_RSA_sign (priv,
                                       &hash, sizeof (hash),
                                       &sig));
  TALER_RSA_key_get_public (priv, &pubkey);
  EXITIF (NULL == (priv_enc = TALER_RSA_encode_key (priv)));
  TALER_RSA_key_free (priv);
  priv = NULL;
  EXITIF (NULL == (priv = TALER_RSA_decode_key ((const char *) priv_enc,
                                                ntohs (priv_enc->len))));
  GNUNET_free (priv_enc);
  priv_enc = NULL;
  EXITIF (GNUNET_OK != TALER_RSA_hash_verify (&hash,
                                              &sig,
                                              &pubkey));
  EXITIF (GNUNET_OK != TALER_RSA_verify (rnd_blk,
                                         RND_BLK_SIZE,
                                         &sig,
                                         &pubkey));

  /* test blind signing */
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, rnd_blk,
                              RND_BLK_SIZE);
  GNUNET_CRYPTO_hash (rnd_blk, RND_BLK_SIZE, &hash);
  (void) memset (&sig, 0, sizeof (struct TALER_RSA_Signature));
  EXITIF (NULL == (bkey = TALER_RSA_blinding_key_create ()));
  EXITIF (NULL == (bsp =
                   TALER_RSA_message_blind (&hash, sizeof (hash),
                                              bkey, &pubkey)));
  EXITIF (GNUNET_OK != TALER_RSA_sign (priv,
                                       bsp,
                                       sizeof (struct TALER_RSA_BlindedSignaturePurpose),
                                       &sig));
  EXITIF (GNUNET_OK != TALER_RSA_unblind (&sig,
                                          bkey,
                                          &pubkey));
  EXITIF (GNUNET_OK != TALER_RSA_hash_verify (&hash,
                                              &sig,
                                              &pubkey));
  ret = 0;                      /* all OK */

 EXITIF_exit:
  if (NULL != priv)
  {
    TALER_RSA_key_free (priv);
    priv = NULL;
  }
  if (NULL != priv_enc)
  {
    GNUNET_free (priv_enc);
    priv_enc = NULL;
  }
  if (NULL != bkey)
    TALER_RSA_blinding_key_destroy (bkey);
  GNUNET_free_non_null (bsp);
  return ret;
}
