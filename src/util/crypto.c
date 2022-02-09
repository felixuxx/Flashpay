/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
#include "taler_util.h"
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
  (void) cls;
  (void) wtf;
  fprintf (stderr,
           "Fatal error in libgcrypt: %s\n",
           msg);
  abort ();
}


/**
 * Initialize libgcrypt.
 */
void __attribute__ ((constructor))
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
  /* Disable secure memory (we should never run on a system that
     even uses swap space for memory). */
  gcry_control (GCRYCTL_DISABLE_SECMEM, 0);
  gcry_control (GCRYCTL_INITIALIZATION_FINISHED, 0);
}


enum GNUNET_GenericReturnValue
TALER_test_coin_valid (const struct TALER_CoinPublicInfo *coin_public_info,
                       const struct TALER_DenominationPublicKey *denom_pub)
{
  struct TALER_CoinPubHash c_hash;
#if ENABLE_SANITY_CHECKS
  struct TALER_DenominationHash d_hash;

  TALER_denom_pub_hash (denom_pub,
                        &d_hash);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&d_hash,
                                &coin_public_info->denom_pub_hash));
#endif
  // FIXME-Oec: replace with function that
  // also hashes the age vector if we have
  // one!
  GNUNET_CRYPTO_hash (&coin_public_info->coin_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &c_hash.hash);
  if (GNUNET_OK !=
      TALER_denom_pub_verify (denom_pub,
                              &coin_public_info->denom_sig,
                              &c_hash))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "coin signature is invalid\n");
    return GNUNET_NO;
  }
  return GNUNET_YES;
}


void
TALER_link_derive_transfer_secret (
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
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


void
TALER_link_reveal_transfer_secret (
  const struct TALER_TransferPrivateKeyP *trans_priv,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  struct TALER_TransferSecretP *transfer_secret)
{
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_ecdh_eddsa (&trans_priv->ecdhe_priv,
                                           &coin_pub->eddsa_pub,
                                           &transfer_secret->key));
}


void
TALER_link_recover_transfer_secret (
  const struct TALER_TransferPublicKeyP *trans_pub,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  struct TALER_TransferSecretP *transfer_secret)
{
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_ecdh (&coin_priv->eddsa_priv,
                                           &trans_pub->ecdhe_pub,
                                           &transfer_secret->key));
}


void
TALER_planchet_setup_random (
  struct TALER_PlanchetSecretsP *ps)
{
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              ps,
                              sizeof (*ps));
}


void
TALER_transfer_secret_to_planchet_secret (
  const struct TALER_TransferSecretP *secret_seed,
  uint32_t coin_num_salt,
  struct TALER_PlanchetSecretsP *ps)
{
  uint32_t be_salt = htonl (coin_num_salt);

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_kdf (ps,
                                    sizeof (*ps),
                                    &be_salt,
                                    sizeof (be_salt),
                                    secret_seed,
                                    sizeof (*secret_seed),
                                    "taler-coin-derivation",
                                    strlen ("taler-coin-derivation"),
                                    NULL, 0));
}


void
TALER_planchet_secret_to_transfer_priv (
  const struct TALER_PlanchetSecretsP *ps,
  uint32_t cnc_num,
  struct TALER_TransferPrivateKeyP *tpriv)
{
  uint32_t be_salt = htonl (cnc_num);

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_kdf (tpriv,
                                    sizeof (*tpriv),
                                    &be_salt,
                                    sizeof (be_salt),
                                    ps,
                                    sizeof (*ps),
                                    "taler-transfer-priv-derivation",
                                    strlen ("taler-transfer-priv-derivation"),
                                    NULL, 0));
}


void
TALER_cs_withdraw_nonce_derive (
  const struct TALER_PlanchetSecretsP *ps,
  struct TALER_CsNonce *nonce)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (nonce,
                                    sizeof (*nonce),
                                    "n",
                                    strlen ("n"),
                                    ps,
                                    sizeof(*ps),
                                    NULL,
                                    0));
}


void
TALER_cs_refresh_nonce_derive (
  const struct TALER_PlanchetSecretsP *ps,
  uint32_t coin_num_salt,
  struct TALER_CsNonce *nonce)
{
  uint32_t be_salt = htonl (coin_num_salt);

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (nonce,
                                    sizeof (*nonce),
                                    &be_salt,
                                    sizeof (be_salt),
                                    "refresh-n", // FIXME: value used in spec?
                                    strlen ("refresh-n"),
                                    ps,
                                    sizeof(*ps),
                                    NULL,
                                    0));
}


void
TALER_planchet_blinding_secret_create (
  const struct TALER_PlanchetSecretsP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  union TALER_DenominationBlindingKeyP *bks)
{
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return;
  case TALER_DENOMINATION_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->rsa_bks,
                                      sizeof (bks->rsa_bks),
                                      "bks",
                                      strlen ("bks"),
                                      ps,
                                      sizeof(*ps),
                                      NULL,
                                      0));
    return;
  case TALER_DENOMINATION_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (&bks->nonce,
                                      sizeof (bks->nonce),
                                      "bseed",
                                      strlen ("bseed"),
                                      ps,
                                      sizeof(*ps),
                                      &alg_values->details.cs_values,
                                      sizeof(alg_values->details.cs_values),
                                      NULL,
                                      0));
    return;
  default:
    GNUNET_break (0);
  }
}


void
TALER_planchet_setup_coin_priv (
  const struct TALER_PlanchetSecretsP *ps,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_CoinSpendPrivateKeyP *coin_priv)
{
  switch (alg_values->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (coin_priv,
                                      sizeof (*coin_priv),
                                      "coin",
                                      strlen ("coin"),
                                      ps,
                                      sizeof(*ps),
                                      NULL,
                                      0));
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_assert (GNUNET_YES ==
                   GNUNET_CRYPTO_kdf (coin_priv,
                                      sizeof (*coin_priv),
                                      "coin",
                                      strlen ("coin"),
                                      ps,
                                      sizeof(*ps),
                                      &alg_values->details,    /* Could be null on RSA case*/
                                      sizeof(alg_values->details),
                                      NULL,
                                      0));
    break;
  default:
    GNUNET_break (0);
    return;
  }
  coin_priv->eddsa_priv.d[0] &= 248;
  coin_priv->eddsa_priv.d[31] &= 127;
  coin_priv->eddsa_priv.d[31] |= 64;
}


enum GNUNET_GenericReturnValue
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_ExchangeWithdrawValues *alg_values,
                        const union TALER_DenominationBlindingKeyP *bks,
                        const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                        struct TALER_CoinPubHash *c_hash,
                        struct TALER_PlanchetDetail *pd
                        )
{
  struct TALER_CoinSpendPublicKeyP coin_pub;

  GNUNET_assert (alg_values->cipher == dk->cipher);
  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  if (GNUNET_OK !=
      TALER_denom_blind (dk,
                         bks,
                         NULL, /* FIXME-Oec */
                         &coin_pub,
                         alg_values,
                         c_hash,
                         &pd->blinded_planchet))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_denom_pub_hash (dk,
                        &pd->denom_pub_hash);
  return GNUNET_OK;
}


void
TALER_planchet_detail_free (struct TALER_PlanchetDetail *pd)
{
  TALER_blinded_planchet_free (&pd->blinded_planchet);
}


void
TALER_blinded_planchet_free (struct TALER_BlindedPlanchet *blinded_planchet)
{
  switch (blinded_planchet->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_free (blinded_planchet->details.rsa_blinded_planchet.blinded_msg);
    break;
  case TALER_DENOMINATION_CS:
    memset (blinded_planchet,
            0,
            sizeof (*blinded_planchet));
    /* nothing to do for CS */
    break;
  default:
    GNUNET_break (0);
  }
}


enum GNUNET_GenericReturnValue
TALER_planchet_to_coin (
  const struct TALER_DenominationPublicKey *dk,
  const struct TALER_BlindedDenominationSignature *blind_sig,
  const union TALER_DenominationBlindingKeyP *bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  const struct TALER_CoinPubHash *c_hash,
  const struct TALER_ExchangeWithdrawValues *alg_values,
  struct TALER_FreshCoin *coin)
{
  if ( (dk->cipher != blind_sig->cipher) ||
       (dk->cipher != alg_values->cipher) )
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_denom_sig_unblind (&coin->sig,
                               blind_sig,
                               bks,
                               c_hash,
                               alg_values,
                               dk))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_denom_pub_verify (dk,
                              &coin->sig,
                              c_hash))
  {
    GNUNET_break_op (0);
    TALER_denom_sig_free (&coin->sig);
    return GNUNET_SYSERR;
  }
  coin->coin_priv = *coin_priv;
  return GNUNET_OK;
}


void
TALER_refresh_get_commitment (struct TALER_RefreshCommitmentP *rc,
                              uint32_t kappa,
                              uint32_t num_new_coins,
                              const struct TALER_RefreshCommitmentEntry *rcs,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct TALER_Amount *amount_with_fee)
{
  struct GNUNET_HashContext *hash_context;

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  /* first, iterate over transfer public keys for hash_context */
  for (unsigned int i = 0; i<kappa; i++)
  {
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &rcs[i].transfer_pub,
                                     sizeof (struct TALER_TransferPublicKeyP));
  }
  /* next, add all of the hashes from the denomination keys to the
     hash_context */
  for (unsigned int i = 0; i<num_new_coins; i++)
  {
    struct TALER_DenominationHash denom_hash;

    /* The denomination keys should / must all be identical regardless
       of what offset we use, so we use [0]. */
    GNUNET_assert (kappa > 0); /* sanity check */
    TALER_denom_pub_hash (rcs[0].new_coins[i].dk,
                          &denom_hash);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &denom_hash,
                                     sizeof (denom_hash));
  }

  /* next, add public key of coin and amount being refreshed */
  {
    struct TALER_AmountNBO melt_amountn;

    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     coin_pub,
                                     sizeof (struct TALER_CoinSpendPublicKeyP));
    TALER_amount_hton (&melt_amountn,
                       amount_with_fee);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &melt_amountn,
                                     sizeof (struct TALER_AmountNBO));
  }

  /* finally, add all the envelopes */
  for (unsigned int i = 0; i<kappa; i++)
  {
    const struct TALER_RefreshCommitmentEntry *rce = &rcs[i];

    for (unsigned int j = 0; j<num_new_coins; j++)
    {
      const struct TALER_RefreshCoinData *rcd = &rce->new_coins[j];

      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "BCH %u/%u %s\n",
                  i, j,
                  TALER_B2S (
                    &rcd->blinded_planchet.details.cs_blinded_planchet));
      TALER_blinded_planchet_hash (&rcd->blinded_planchet,
                                   hash_context);
    }
  }

  /* Conclude */
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &rc->session_hash);
}


enum GNUNET_GenericReturnValue
TALER_coin_ev_hash (const struct TALER_BlindedPlanchet *blinded_planchet,
                    const struct TALER_DenominationHash *denom_hash,
                    struct TALER_BlindedCoinHash *bch)
{
  struct GNUNET_HashContext *hash_context;

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   denom_hash,
                                   sizeof(*denom_hash));
  switch (blinded_planchet->cipher)
  {
  case TALER_DENOMINATION_RSA:
    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      blinded_planchet->details.rsa_blinded_planchet.blinded_msg,
      blinded_planchet->details.rsa_blinded_planchet.blinded_msg_size);
    break;
  case TALER_DENOMINATION_CS:
    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      &blinded_planchet->details.cs_blinded_planchet.nonce,
      sizeof (blinded_planchet->details.cs_blinded_planchet.nonce));
    break;
  default:
    GNUNET_break (0);
    GNUNET_CRYPTO_hash_context_abort (hash_context);
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &bch->hash);
  return GNUNET_OK;
}


void
TALER_coin_pub_hash (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const struct TALER_AgeHash *age_commitment_hash,
                     struct TALER_CoinPubHash *coin_h)
{
  if (NULL == age_commitment_hash)
  {
    /* No age commitment was set */
    GNUNET_CRYPTO_hash (&coin_pub->eddsa_pub,
                        sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                        &coin_h->hash);
  }
  else
  {
    /* Coin comes with age commitment.  Take the hash of the age commitment
     * into account */
    const size_t key_s = sizeof(struct GNUNET_CRYPTO_EcdsaPublicKey);
    const size_t age_s = sizeof(struct TALER_AgeHash);
    char data[key_s + age_s];

    GNUNET_memcpy (&data[0],
                   &coin_pub->eddsa_pub,
                   key_s);
    GNUNET_memcpy (&data[key_s],
                   age_commitment_hash,
                   age_s);
    GNUNET_CRYPTO_hash (&data,
                        key_s + age_s,
                        &coin_h->hash);
  }
}


/* end of crypto.c */
