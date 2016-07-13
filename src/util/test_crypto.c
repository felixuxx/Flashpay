/*
  This file is part of TALER
  (C) 2015 GNUnet e.V.

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
 * @file util/test_crypto.c
 * @brief Tests for Taler-specific crypto logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_crypto_lib.h"


/**
 * Test low-level link encryption/decryption APIs.
 *
 * @return 0 on success
 */
static int
test_basics ()
{
  struct TALER_EncryptedLinkSecretP secret_enc;
  struct TALER_TransferSecretP trans_sec;
  struct TALER_LinkSecretP secret;
  struct TALER_LinkSecretP secret2;
  struct TALER_RefreshLinkEncryptedP rl_enc;
  struct TALER_RefreshLinkDecryptedP rl;
  struct TALER_RefreshLinkDecryptedP rld;
                       
  GNUNET_log_setup ("test-crypto",
		    "WARNING",
		    NULL);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &secret,
			      sizeof (secret));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &rl,
			      sizeof (rl));
  TALER_refresh_encrypt (&rl,
			 &secret,
			 &rl_enc);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &trans_sec,
			      sizeof (trans_sec));
  GNUNET_assert (GNUNET_OK ==
		 TALER_transfer_encrypt (&secret,
					 &trans_sec,
					 &secret_enc));
  GNUNET_assert (GNUNET_OK ==
		 TALER_transfer_decrypt (&secret_enc,
					 &trans_sec,
					 &secret2));
  GNUNET_assert (0 == memcmp (&secret,
			      &secret2,
			      sizeof (secret)));
  TALER_refresh_decrypt (&rl_enc,
			 &secret2,
			 &rld);
  GNUNET_assert (0 == memcmp (&rld,
			      &rl,
			      sizeof (struct TALER_RefreshLinkDecryptedP)));
  return 0;
}


/**
 * Test high-level link encryption/decryption API.
 *
 * @return 0 on success
 */
static int
test_high_level ()
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *pk;
  struct TALER_LinkSecretP secret;
  struct TALER_LinkSecretP secret2;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  struct TALER_TransferPrivateKeyP trans_priv;
  struct TALER_TransferPublicKeyP trans_pub;
  struct TALER_EncryptedLinkSecretP secret_enc;

  pk = GNUNET_CRYPTO_eddsa_key_create ();
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &secret,
			      sizeof (secret));
  GNUNET_CRYPTO_eddsa_key_get_public (pk,
				      &coin_pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK == 
		 TALER_link_encrypt_secret (&secret,
					    &coin_pub,
					    &trans_priv,
					    &trans_pub,
					    &secret_enc));
  GNUNET_assert (GNUNET_OK == 
		 TALER_link_decrypt_secret (&secret_enc,
					    &trans_priv,
					    &coin_pub,
					    &secret2));
  GNUNET_assert (0 ==
		 memcmp (&secret,
			 &secret2,
			 sizeof (secret)));
  coin_priv.eddsa_priv = *pk;
  GNUNET_assert (GNUNET_OK == 
		 TALER_link_decrypt_secret2 (&secret_enc,
					     &trans_pub,
					     &coin_priv,
					     &secret2));
  GNUNET_assert (0 ==
		 memcmp (&secret,
			 &secret2,
			 sizeof (secret)));
  GNUNET_free (pk);
  return 0;
}


int
main(int argc,
     const char *const argv[])
{
  if (0 != test_basics ())
    return 1;
  if (0 != test_high_level ())
    return 1;
  return 0;  
}

/* end of test_crypto.c */
