/*
  This file is part of TALER
  (C) 2015 Taler Systems SA

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
 * Test high-level link encryption/decryption API.
 *
 * @return 0 on success
 */
static int
test_high_level (void)
{
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_TransferPrivateKeyP trans_priv;
  struct TALER_TransferPublicKeyP trans_pub;
  struct TALER_TransferSecretP secret;
  struct TALER_TransferSecretP secret2;
  struct TALER_PlanchetSecretsP fc1;
  struct TALER_PlanchetSecretsP fc2;

  GNUNET_CRYPTO_eddsa_key_create (&coin_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv.eddsa_priv,
                                      &coin_pub.eddsa_pub);
  GNUNET_CRYPTO_ecdhe_key_create (&trans_priv.ecdhe_priv);
  GNUNET_CRYPTO_ecdhe_key_get_public (&trans_priv.ecdhe_priv,
                                      &trans_pub.ecdhe_pub);
  TALER_link_derive_transfer_secret (&coin_priv,
                                     &trans_priv,
                                     &secret);
  TALER_link_reveal_transfer_secret (&trans_priv,
                                     &coin_pub,
                                     &secret2);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&secret,
                                &secret2));
  TALER_link_recover_transfer_secret (&trans_pub,
                                      &coin_priv,
                                      &secret2);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&secret,
                                &secret2));
  TALER_planchet_setup_refresh (&secret,
                                0,
                                &fc1);
  TALER_planchet_setup_refresh (&secret,
                                1,
                                &fc2);
  GNUNET_assert (0 !=
                 GNUNET_memcmp (&fc1,
                                &fc2));
  return 0;
}


/**
 * Test the basic planchet functionality of creating a fresh planchet
 * and extracting the respective signature.
 *
 * @return 0 on success
 */
static int
test_planchets (void)
{
  struct TALER_PlanchetSecretsP ps;
  struct TALER_DenominationPrivateKey dk_priv;
  struct TALER_DenominationPublicKey dk_pub;
  struct TALER_PlanchetDetail pd;
  struct GNUNET_CRYPTO_RsaSignature *blind_sig;
  struct TALER_FreshCoin coin;
  struct GNUNET_HashCode c_hash;

  dk_priv.rsa_private_key = GNUNET_CRYPTO_rsa_private_key_create (1024);
  dk_pub.rsa_public_key = GNUNET_CRYPTO_rsa_private_key_get_public (
    dk_priv.rsa_private_key);
  TALER_planchet_setup_random (&ps);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_prepare (&dk_pub,
                                         &ps,
                                         &c_hash,
                                         &pd));
  blind_sig = GNUNET_CRYPTO_rsa_sign_blinded (dk_priv.rsa_private_key,
                                              pd.coin_ev,
                                              pd.coin_ev_size);
  GNUNET_assert (NULL != blind_sig);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_to_coin (&dk_pub,
                                         blind_sig,
                                         &ps,
                                         &c_hash,
                                         &coin));
  GNUNET_CRYPTO_rsa_signature_free (blind_sig);
  GNUNET_CRYPTO_rsa_signature_free (coin.sig.rsa_signature);
  GNUNET_CRYPTO_rsa_private_key_free (dk_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dk_pub.rsa_public_key);
  return 0;
}


int
main (int argc,
      const char *const argv[])
{
  (void) argc;
  (void) argv;
  if (0 != test_high_level ())
    return 1;
  if (0 != test_planchets ())
    return 1;
  return 0;
}


/* end of test_crypto.c */
