/*
  This file is part of TALER
  (C) 2015, 2020-2023 Taler Systems SA

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
  union GNUNET_CRYPTO_BlindingSecretP bks1;
  union GNUNET_CRYPTO_BlindingSecretP bks2;
  struct TALER_CoinSpendPrivateKeyP coin_priv1;
  struct TALER_CoinSpendPrivateKeyP coin_priv2;
  struct TALER_PlanchetMasterSecretP ps1;
  struct TALER_PlanchetMasterSecretP ps2;
  struct GNUNET_CRYPTO_BlindingInputValues bi = {
    .cipher = GNUNET_CRYPTO_BSA_RSA
  };
  struct TALER_ExchangeWithdrawValues alg1 = {
    .blinding_inputs = &bi
  };
  struct TALER_ExchangeWithdrawValues alg2 = {
    .blinding_inputs = &bi
  };

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
  TALER_planchet_setup_coin_priv (&ps1,
                                  &alg1,
                                  &coin_priv1);
  TALER_planchet_blinding_secret_create (&ps1,
                                         &alg1,
                                         &bks1);
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


static struct TALER_AgeMask age_mask = {
  .bits = 1 | 1 << 8 | 1 << 10 | 1 << 12
          | 1 << 14 | 1 << 16 | 1 << 18 | 1 << 21
};

/**
 * Test the basic planchet functionality of creating a fresh planchet
 * and extracting the respective signature.
 *
 * @return 0 on success
 */
static int
test_planchets_rsa (uint8_t age)
{
  struct TALER_PlanchetMasterSecretP ps;
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  union GNUNET_CRYPTO_BlindingSecretP bks;
  struct TALER_DenominationPrivateKey dk_priv;
  struct TALER_DenominationPublicKey dk_pub;
  const struct TALER_ExchangeWithdrawValues *alg_values;
  struct TALER_PlanchetDetail pd;
  struct TALER_BlindedDenominationSignature blind_sig;
  struct TALER_FreshCoin coin;
  struct TALER_CoinPubHashP c_hash;
  struct TALER_AgeCommitmentHash *ach = NULL;
  struct TALER_AgeCommitmentHash ah = {0};

  alg_values = TALER_denom_ewv_rsa_singleton ();
  if (0 < age)
  {
    struct TALER_AgeCommitmentProof acp;
    struct GNUNET_HashCode seed;

    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));
    TALER_age_restriction_commit (&age_mask,
                                  age,
                                  &seed,
                                  &acp);
    TALER_age_commitment_hash (&acp.commitment,
                               &ah);
    ach = &ah;
    TALER_age_commitment_proof_free (&acp);
  }

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              &ps,
                              sizeof (ps));
  GNUNET_log_skip (1, GNUNET_YES);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          GNUNET_CRYPTO_BSA_INVALID));
  GNUNET_log_skip (1, GNUNET_YES);
  GNUNET_assert (GNUNET_SYSERR ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          42));

  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          GNUNET_CRYPTO_BSA_RSA,
                                          1024));
  TALER_planchet_setup_coin_priv (&ps,
                                  alg_values,
                                  &coin_priv);
  TALER_planchet_blinding_secret_create (&ps,
                                         alg_values,
                                         &bks);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_prepare (&dk_pub,
                                         alg_values,
                                         &bks,
                                         NULL,
                                         &coin_priv,
                                         ach,
                                         &c_hash,
                                         &pd));
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sign_blinded (&blind_sig,
                                           &dk_priv,
                                           false,
                                           &pd.blinded_planchet));
  TALER_planchet_detail_free (&pd);
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_to_coin (&dk_pub,
                                         &blind_sig,
                                         &bks,
                                         &coin_priv,
                                         ach,
                                         &c_hash,
                                         alg_values,
                                         &coin));
  TALER_blinded_denom_sig_free (&blind_sig);
  TALER_denom_sig_free (&coin.sig);
  TALER_denom_priv_free (&dk_priv);
  TALER_denom_pub_free (&dk_pub);
  return 0;
}


/**
 * Test the basic planchet functionality of creating a fresh planchet with CS denomination
 * and extracting the respective signature.
 *
 * @return 0 on success
 */
static int
test_planchets_cs (uint8_t age)
{
  struct TALER_PlanchetMasterSecretP ps;
  struct TALER_CoinSpendPrivateKeyP coin_priv;
  union GNUNET_CRYPTO_BlindingSecretP bks;
  struct TALER_DenominationPrivateKey dk_priv;
  struct TALER_DenominationPublicKey dk_pub;
  struct TALER_PlanchetDetail pd;
  struct TALER_CoinPubHashP c_hash;
  union GNUNET_CRYPTO_BlindSessionNonce nonce;
  struct TALER_BlindedDenominationSignature blind_sig;
  struct TALER_FreshCoin coin;
  struct TALER_ExchangeWithdrawValues alg_values;
  struct TALER_AgeCommitmentHash *ach = NULL;

  if (0 < age)
  {
    struct TALER_AgeCommitmentHash ah = {0};
    struct TALER_AgeCommitmentProof acp;
    struct GNUNET_HashCode seed;

    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));
    TALER_age_restriction_commit (&age_mask,
                                  age,
                                  &seed,
                                  &acp);
    TALER_age_commitment_hash (&acp.commitment,
                               &ah);
    ach = &ah;
    TALER_age_commitment_proof_free (&acp);
  }

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              &ps,
                              sizeof (ps));
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&dk_priv,
                                          &dk_pub,
                                          GNUNET_CRYPTO_BSA_CS));
  TALER_cs_withdraw_nonce_derive (
    &ps,
    &nonce.cs_nonce);
  // FIXME: define Taler abstraction for this:
  alg_values.blinding_inputs
    = GNUNET_CRYPTO_get_blinding_input_values (dk_priv.bsign_priv_key,
                                               &nonce,
                                               "rw");
  TALER_denom_pub_hash (&dk_pub,
                        &pd.denom_pub_hash);
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
                                         &nonce,
                                         &coin_priv,
                                         ach,
                                         &c_hash,
                                         &pd));
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sign_blinded (&blind_sig,
                                           &dk_priv,
                                           false,
                                           &pd.blinded_planchet));
  GNUNET_assert (GNUNET_OK ==
                 TALER_planchet_to_coin (&dk_pub,
                                         &blind_sig,
                                         &bks,
                                         &coin_priv,
                                         ach,
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
test_planchets (uint8_t age)
{
  if (0 != test_planchets_rsa (age))
    return -1;
  return test_planchets_cs (age);
}


static int
test_exchange_sigs (void)
{
  const char *pt = "payto://x-taler-bank/localhost/Account";
  struct TALER_MasterPrivateKeyP priv;
  struct TALER_MasterPublicKeyP pub;
  struct TALER_MasterSignatureP sig;
  json_t *rest;

  GNUNET_CRYPTO_eddsa_key_create (&priv.eddsa_priv);
  rest = json_array ();
  GNUNET_assert (NULL != rest);
  TALER_exchange_wire_signature_make (pt,
                                      NULL,
                                      rest,
                                      rest,
                                      &priv,
                                      &sig);
  GNUNET_CRYPTO_eddsa_key_get_public (&priv.eddsa_priv,
                                      &pub.eddsa_pub);
  if (GNUNET_OK !=
      TALER_exchange_wire_signature_check (pt,
                                           NULL,
                                           rest,
                                           rest,
                                           &pub,
                                           &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  if (GNUNET_OK ==
      TALER_exchange_wire_signature_check (
        "payto://x-taler-bank/localhost/Other",
        NULL,
        rest,
        rest,
        &pub,
        &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  if (GNUNET_OK ==
      TALER_exchange_wire_signature_check (
        pt,
        "http://example.com/",
        rest,
        rest,
        &pub,
        &sig))
  {
    GNUNET_break (0);
    return 1;
  }
  json_decref (rest);
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


static int
test_contracts (void)
{
  struct TALER_ContractDiffiePrivateP cpriv;
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_PurseContractPrivateKeyP purse_priv;
  void *econtract;
  size_t econtract_size;
  struct TALER_PurseMergePrivateKeyP mpriv_in;
  struct TALER_PurseMergePrivateKeyP mpriv_out;
  json_t *c;

  GNUNET_CRYPTO_ecdhe_key_create (&cpriv.ecdhe_priv);
  GNUNET_CRYPTO_eddsa_key_create (&purse_priv.eddsa_priv);
  GNUNET_CRYPTO_eddsa_key_get_public (&purse_priv.eddsa_priv,
                                      &purse_pub.eddsa_pub);
  memset (&mpriv_in,
          42,
          sizeof (mpriv_in));
  c = json_pack ("{s:s}", "test", "value");
  GNUNET_assert (NULL != c);
  TALER_CRYPTO_contract_encrypt_for_merge (&purse_pub,
                                           &cpriv,
                                           &mpriv_in,
                                           c,
                                           &econtract,
                                           &econtract_size);
  json_decref (c);
  c = TALER_CRYPTO_contract_decrypt_for_merge (&cpriv,
                                               &purse_pub,
                                               econtract,
                                               econtract_size,
                                               &mpriv_out);
  GNUNET_free (econtract);
  if (NULL == c)
    return 1;
  json_decref (c);
  if (0 != GNUNET_memcmp (&mpriv_in,
                          &mpriv_out))
    return 1;
  return 0;
}


static int
test_attributes (void)
{
  struct TALER_AttributeEncryptionKeyP key;
  void *eattr;
  size_t eattr_size;
  json_t *c;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &key,
                              sizeof (key));
  c = json_pack ("{s:s}", "test", "value");
  GNUNET_assert (NULL != c);
  TALER_CRYPTO_kyc_attributes_encrypt (&key,
                                       c,
                                       &eattr,
                                       &eattr_size);
  json_decref (c);
  c = TALER_CRYPTO_kyc_attributes_decrypt (&key,
                                           eattr,
                                           eattr_size);
  GNUNET_free (eattr);
  if (NULL == c)
  {
    GNUNET_break (0);
    return 1;
  }
  GNUNET_assert (0 ==
                 strcmp ("value",
                         json_string_value (json_object_get (c,
                                                             "test"))));
  json_decref (c);
  return 0;
}


int
main (int argc,
      const char *const argv[])
{
  (void) argc;
  (void) argv;
  GNUNET_log_setup ("test-crypto",
                    "WARNING",
                    NULL);
  if (0 != test_high_level ())
    return 1;
  if (0 != test_planchets (0))
    return 2;
  if (0 != test_planchets (13))
    return 3;
  if (0 != test_exchange_sigs ())
    return 4;
  if (0 != test_merchant_sigs ())
    return 5;
  if (0 != test_contracts ())
    return 6;
  if (0 != test_attributes ())
    return 7;
  return 0;
}


/* end of test_crypto.c */
