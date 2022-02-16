/*
  This file is part of TALER
  (C) 2015, 2020-2022 Taler Systems SA

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
  union TALER_DenominationBlindingKeyP bks1;
  union TALER_DenominationBlindingKeyP bks2;
  struct TALER_CoinSpendPrivateKeyP coin_priv1;
  struct TALER_CoinSpendPrivateKeyP coin_priv2;
  struct TALER_PlanchetMasterSecretP ps1;
  struct TALER_PlanchetMasterSecretP ps2;
  struct TALER_ExchangeWithdrawValues alg1;
  struct TALER_ExchangeWithdrawValues alg2;

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
  TALER_transfer_secret_to_planchet_secret (&secret,
                                            0,
                                            &ps1);
  alg1.cipher = TALER_DENOMINATION_RSA;
  TALER_planchet_setup_coin_priv (&ps1,
                                  &alg1,
                                  &coin_priv1);
  TALER_planchet_blinding_secret_create (&ps1,
                                         &alg1,
                                         &bks1);
  alg2.cipher = TALER_DENOMINATION_RSA;
  TALER_transfer_secret_to_planchet_secret (&secret,
                                            1,
                                            &ps2);
  TALER_planchet_setup_coin_priv (&ps2,
                                  &alg2,
                                  &coin_priv2);
  TALER_planchet_blinding_secret_create (&ps2,
                                         &alg2,
                                         &bks2);
  GNUNET_assert (0 !=
                 GNUNET_memcmp (&ps1,
                                &ps2));
  GNUNET_assert (0 !=
                 GNUNET_memcmp (&coin_priv1,
                                &coin_priv2));
  GNUNET_assert (0 !=
                 GNUNET_memcmp (&bks1,
                                &bks2));
  return 0;
}


/**
 * Test the basic planchet functionality of creating a fresh planchet
 * and extracting the respective signature.
 *
 * @return 0 on success
 */
static int
test_planchets_rsa (void)
{
  struct TALER_PlanchetMasterSecretP ps;
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  union TALER_DenominationBlindingKeyP bks;
  struct TALER_DenominationPrivateKey dk_priv;
  struct TALER_DenominationPublicKey dk_pub;
  struct TALER_ExchangeWithdrawValues alg_values;
  struct TALER_PlanchetDetail pd;
  struct TALER_BlindedDenominationSignature blind_sig;
  struct TALER_FreshCoin coin;
  struct TALER_CoinPubHash c_hash;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              &ps,
                              sizeof (ps));

  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          TALER_DENOMINATION_INVALID));

  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          42));

  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          TALER_DENOMINATION_RSA,
                                          1024));
  alg_values.cipher = TALER_DENOMINATION_RSA;
  TALER_planchet_setup_coin_priv (&ps,
                                  &alg_values,
                                  &coin_priv);
  TALER_planchet_blinding_secret_create (&ps,
                                         &alg_values,
                                         &bks);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_prepare (&dk_pub,
                                         &alg_values,
                                         &bks,
                                         &coin_priv,
                                         NULL, /* no age commitment */
                                         &c_hash,
                                         &pd));
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sign_blinded (&blind_sig,
                                           &dk_priv,
                                           &pd.blinded_planchet));
  TALER_planchet_detail_free (&pd);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_to_coin (&dk_pub,
                                         &blind_sig,
                                         &bks,
                                         &coin_priv,
                                         NULL, /* no age commitment */
                                         &c_hash,
                                         &alg_values,
                                         &coin));
  TALER_blinded_denom_sig_free (&blind_sig);
  TALER_denom_sig_free (&coin.sig);
  TALER_denom_priv_free (&dk_priv);
  TALER_denom_pub_free (&dk_pub);
  return 0;
}


/** FIXME-oec: Add test for planchets with age commitment hash */

/**
 * @brief Function for CS signatures to derive public R_0 and R_1
 *
 * @param nonce withdraw nonce from a client
 * @param denom_priv denomination privkey as long-term secret
 * @param r_pub the resulting R_0 and R_1
 * @return enum GNUNET_GenericReturnValue
 */
static enum GNUNET_GenericReturnValue
derive_r_public (
  const struct TALER_CsNonce *nonce,
  const struct TALER_DenominationPrivateKey *denom_priv,
  struct TALER_DenominationCSPublicRPairP *r_pub)
{
  struct GNUNET_CRYPTO_CsRSecret r[2];

  if (denom_priv->cipher != TALER_DENOMINATION_CS)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_cs_r_derive (&nonce->nonce,
                             &denom_priv->details.cs_private_key,
                             r);
  GNUNET_CRYPTO_cs_r_get_public (&r[0],
                                 &r_pub->r_pub[0]);
  GNUNET_CRYPTO_cs_r_get_public (&r[1],
                                 &r_pub->r_pub[1]);
  return GNUNET_OK;
}


/**
 * Test the basic planchet functionality of creating a fresh planchet with CS denomination
 * and extracting the respective signature.
 *
 * @return 0 on success
 */
static int
test_planchets_cs (void)
{
  struct TALER_PlanchetMasterSecretP ps;
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  union TALER_DenominationBlindingKeyP bks;
  struct TALER_DenominationPrivateKey dk_priv;
  struct TALER_DenominationPublicKey dk_pub;
  struct TALER_PlanchetDetail pd;
  struct TALER_CoinPubHash c_hash;
  struct TALER_BlindedDenominationSignature blind_sig;
  struct TALER_FreshCoin coin;
  struct TALER_ExchangeWithdrawValues alg_values;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              &ps,
                              sizeof (ps));
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          TALER_DENOMINATION_CS));
  alg_values.cipher = TALER_DENOMINATION_CS;
  TALER_cs_withdraw_nonce_derive (
    &ps,
    &pd.blinded_planchet.details.cs_blinded_planchet.nonce);
  GNUNET_assert (GNUNET_OK ==
                 derive_r_public (
                   &pd.blinded_planchet.details.cs_blinded_planchet.nonce,
                   &dk_priv,
                   &alg_values.details.cs_values));
  TALER_planchet_setup_coin_priv (&ps,
                                  &alg_values,
                                  &coin_priv);
  TALER_planchet_blinding_secret_create (&ps,
                                         &alg_values,
                                         &bks);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_prepare (&dk_pub,
                                         &alg_values,
                                         &bks,
                                         &coin_priv,
                                         &c_hash,
                                         &pd));
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sign_blinded (&blind_sig,
                                           &dk_priv,
                                           &pd.blinded_planchet));
  TALER_planchet_detail_free (&pd);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_to_coin (&dk_pub,
                                         &blind_sig,
                                         &bks,
                                         &coin_priv,
                                         &c_hash,
                                         &alg_values,
                                         &coin));
  TALER_blinded_denom_sig_free (&blind_sig);
  TALER_denom_sig_free (&coin.sig);
  TALER_denom_priv_free (&dk_priv);
  TALER_denom_pub_free (&dk_pub);
  return 0;
}


/**
 * Test the basic planchet functionality of creating a fresh planchet
 * and extracting the respective signature.
 * Calls test_planchets_rsa and test_planchets_cs
 *
 * @return 0 on success
 */
static int
test_planchets (void)
{
  if (0 != test_planchets_rsa ())
    return -1;
  return test_planchets_cs ();
}


static int
test_exchange_sigs (void)
{
  const char *pt = "payto://x-taler-bank/localhost/Account";
  struct TALER_MasterPrivateKeyP priv;
  struct TALER_MasterPublicKeyP pub;
  struct TALER_MasterSignatureP sig;

  GNUNET_CRYPTO_eddsa_key_create (&priv.eddsa_priv);
  TALER_exchange_wire_signature_make (pt,
                                      &priv,
                                      &sig);
  GNUNET_CRYPTO_eddsa_key_get_public (&priv.eddsa_priv,
                                      &pub.eddsa_pub);
  if (GNUNET_OK !=
      TALER_exchange_wire_signature_check (pt,
                                           &pub,
                                           &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  if (GNUNET_OK ==
      TALER_exchange_wire_signature_check (
        "payto://x-taler-bank/localhost/Other",
        &pub,
        &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  return 0;
}


static int
test_merchant_sigs (void)
{
  const char *pt = "payto://x-taler-bank/localhost/Account";
  struct TALER_WireSaltP salt;
  struct TALER_MerchantPrivateKeyP priv;
  struct TALER_MerchantPublicKeyP pub;
  struct TALER_MerchantSignatureP sig;

  GNUNET_CRYPTO_eddsa_key_create (&priv.eddsa_priv);
  memset (&salt,
          42,
          sizeof (salt));
  TALER_merchant_wire_signature_make (pt,
                                      &salt,
                                      &priv,
                                      &sig);
  GNUNET_CRYPTO_eddsa_key_get_public (&priv.eddsa_priv,
                                      &pub.eddsa_pub);
  if (GNUNET_OK !=
      TALER_merchant_wire_signature_check (pt,
                                           &salt,
                                           &pub,
                                           &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  if (GNUNET_OK ==
      TALER_merchant_wire_signature_check (
        "payto://x-taler-bank/localhost/Other",
        &salt,
        &pub,
        &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  memset (&salt,
          43,
          sizeof (salt));
  if (GNUNET_OK ==
      TALER_merchant_wire_signature_check (pt,
                                           &salt,
                                           &pub,
                                           &sig))
  {
    GNUNET_break (0);
    return 1;
  }
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
    return 2;
  if (0 != test_planchets_with_age_commitment ())
    return 3;
  if (0 != test_exchange_sigs ())
    return 4;
  if (0 != test_merchant_sigs ())
    return 5;
  return 0;
}


/* end of test_crypto.c */
