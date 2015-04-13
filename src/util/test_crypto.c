/*
  This file is part of TALER
  (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @file util/test_crypto.c
 * @brief Tests for Taler-specific crypto logic
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_crypto_lib.h"


int
main(int argc,
     const char *const argv[])
{
  struct TALER_EncryptedLinkSecretP secret_enc;
  struct TALER_TransferSecretP trans_sec;
  struct TALER_LinkSecretP secret;
  struct TALER_RefreshLinkEncrypted *rl_enc;
  struct TALER_RefreshLinkDecrypted rl;
  struct GNUNET_CRYPTO_EcdhePrivateKey *pk;
  
                       
  GNUNET_log_setup ("test-crypto",
		    "WARNING",
		    NULL);
  /* FIXME: implement test... */
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &secret,
			      sizeof (secret));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &trans_sec,
			      sizeof (trans_sec));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
			      &rl.coin_priv,
			      sizeof (rl.coin_priv));
  rl.blinding_key.rsa_blinding_key = GNUNET_CRYPTO_rsa_blinding_key_create ();
  rl_enc = TALER_refresh_link_encrypt (&rl,
				       &secret);
  GNUNET_assert (GNUNET_OK ==
		 TALER_transfer_encrypt (&secret,
					 &trans_sec,
					 &secret_enc));
  pk = GNUNET_CRYPTO_ecdhe_key_create ();
#if 0
  .../.ecdhe_private_key = *pk;
#endif
  
  GNUNET_CRYPTO_rsa_blinding_key_free (rl.blinding_key);
  GNUNET_free (pk);
  return 0;
}

/* end of test_crypto.c */
