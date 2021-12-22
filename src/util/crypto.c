/*
  This file is part of TALER
  Copyright (C) 2014-2017 Taler Systems SA

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
TALER_planchet_setup_refresh (const struct TALER_TransferSecretP *secret_seed,
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
cs_blinding_seed_derive (const struct
                         TALER_CoinSpendPrivateKeyP *coin_priv,
                         const struct GNUNET_CRYPTO_CsRPublic r_pub[2],
                         struct GNUNET_CRYPTO_CsNonce *blind_seed)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_hkdf (blind_seed,
                                     sizeof (*blind_seed),
                                     GCRY_MD_SHA512,
                                     GCRY_MD_SHA256,
                                     "bseed",
                                     strlen ("bseed"),
                                     coin_priv,
                                     sizeof(*coin_priv),
                                     r_pub,
                                     sizeof(struct GNUNET_CRYPTO_CsRPublic) * 2,
                                     NULL,
                                     0));
}


void
TALER_cs_withdraw_nonce_derive (const struct
                                TALER_CoinSpendPrivateKeyP *coin_priv,
                                struct TALER_WithdrawNonce *nonce)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_hkdf (nonce,
                                     sizeof (*nonce),
                                     GCRY_MD_SHA512,
                                     GCRY_MD_SHA256,
                                     "n",
                                     strlen ("n"),
                                     coin_priv,
                                     sizeof(*coin_priv),
                                     NULL,
                                     0));
}


void
TALER_blinding_secret_create (union TALER_DenominationBlindingKeyP *bs,
                              enum TALER_DenominationCipher cipher,
                              ...)
{
  va_list ap;
  va_start (ap, cipher);
  switch (cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return;
  case TALER_DENOMINATION_RSA:
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                                &bs->rsa_bks,
                                sizeof (struct
                                        GNUNET_CRYPTO_RsaBlindingKeySecret));
    return;
  case TALER_DENOMINATION_CS:
    {
      struct TALER_CoinSpendPrivateKeyP *coin_priv;
      struct TALER_DenominationCsPublicR *r_pub;
      coin_priv = va_arg (ap, struct TALER_CoinSpendPrivateKeyP *);
      r_pub = va_arg (ap, struct TALER_DenominationCsPublicR *);

      cs_blinding_seed_derive (coin_priv,
                               r_pub->r_pub,
                               &bs->nonce);
      return;
    }
  default:
    GNUNET_break (0);
  }
  va_end (ap);
}


/**
 * @brief setup a random planchet
 * In Case of RSA planchet, the bks gets set
 * In Case of Schnorr this will be set in future
 */
void
TALER_planchet_setup_random (struct TALER_PlanchetSecretsP *ps,
                             enum TALER_DenominationCipher cipher)
{
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              &ps->coin_priv,
                              sizeof (struct TALER_CoinSpendPrivateKeyP));
  switch (cipher)
  {
  case TALER_DENOMINATION_INVALID:
    GNUNET_break (0);
    return;
  case TALER_DENOMINATION_RSA:
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                                &ps->blinding_key.rsa_bks,
                                sizeof (struct
                                        GNUNET_CRYPTO_RsaBlindingKeySecret));
    return;
  case TALER_DENOMINATION_CS:
    // Will be set in a later stage for Clause Blind Schnorr Scheme
    return;
  default:
    GNUNET_break (0);
  }
}


enum GNUNET_GenericReturnValue
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_PlanchetSecretsP *ps,
                        struct TALER_CoinPubHash *c_hash,
                        struct TALER_PlanchetDetail *pd)
{
  struct TALER_CoinSpendPublicKeyP coin_pub;

  GNUNET_CRYPTO_eddsa_key_get_public (&ps->coin_priv.eddsa_priv,
                                      &coin_pub.eddsa_pub);
  if (GNUNET_OK !=
      TALER_denom_blind (dk,
                         &ps->blinding_key,
                         NULL, /* FIXME-Oec */
                         &coin_pub,
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


enum GNUNET_GenericReturnValue
TALER_planchet_to_coin (
  const struct TALER_DenominationPublicKey *dk,
  const struct TALER_BlindedDenominationSignature *blind_sig,
  const struct TALER_PlanchetSecretsP *ps,
  const struct TALER_CoinPubHash *c_hash,
  struct TALER_FreshCoin *coin)
{
  struct TALER_DenominationSignature sig;

  if (GNUNET_OK !=
      TALER_denom_sig_unblind (&sig,
                               blind_sig,
                               &ps->blinding_key,
                               dk))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_denom_pub_verify (dk,
                              &sig,
                              c_hash))
  {
    GNUNET_break_op (0);
    TALER_denom_sig_free (&sig);
    return GNUNET_SYSERR;
  }
  coin->sig = sig;
  coin->coin_priv = ps->coin_priv;
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

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       rcd->coin_ev,
                                       rcd->coin_ev_size);
    }
  }

  /* Conclude */
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &rc->session_hash);
}


void
TALER_coin_ev_hash (const void *coin_ev,
                    size_t coin_ev_size,
                    struct TALER_BlindedCoinHash *bch)
{
  GNUNET_CRYPTO_hash (coin_ev,
                      coin_ev_size,
                      &bch->hash);
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
