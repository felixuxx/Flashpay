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
 * @author Özgür Kesim
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
  struct TALER_CoinPubHashP c_hash;
#if ENABLE_SANITY_CHECKS
  struct TALER_DenominationHashP d_hash;

  TALER_denom_pub_hash (denom_pub,
                        &d_hash);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&d_hash,
                                &coin_public_info->denom_pub_hash));
#endif

  TALER_coin_pub_hash (&coin_public_info->coin_pub,
                       &coin_public_info->h_age_commitment,
                       &c_hash);

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
TALER_planchet_master_setup_random (
  struct TALER_PlanchetMasterSecretP *ps)
{
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              ps,
                              sizeof (*ps));
}


void
TALER_refresh_master_setup_random (
  struct TALER_RefreshMasterSecretP *rms)
{
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              rms,
                              sizeof (*rms));
}


void
TALER_transfer_secret_to_planchet_secret (
  const struct TALER_TransferSecretP *secret_seed,
  uint32_t coin_num_salt,
  struct TALER_PlanchetMasterSecretP *ps)
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
  const struct TALER_RefreshMasterSecretP *rms,
  const struct TALER_CoinSpendPrivateKeyP *old_coin_priv,
  uint32_t cnc_num,
  struct TALER_TransferPrivateKeyP *tpriv)
{
  uint32_t be_salt = htonl (cnc_num);

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_kdf (tpriv,
                                    sizeof (*tpriv),
                                    &be_salt,
                                    sizeof (be_salt),
                                    old_coin_priv,
                                    sizeof (*old_coin_priv),
                                    rms,
                                    sizeof (*rms),
                                    "taler-transfer-priv-derivation",
                                    strlen ("taler-transfer-priv-derivation"),
                                    NULL, 0));
}


void
TALER_cs_withdraw_nonce_derive (
  const struct TALER_PlanchetMasterSecretP *ps,
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
  const struct TALER_RefreshMasterSecretP *rms,
  uint32_t coin_num_salt,
  struct TALER_CsNonce *nonce)
{
  uint32_t be_salt = htonl (coin_num_salt);

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (nonce,
                                    sizeof (*nonce),
                                    &be_salt,
                                    sizeof (be_salt),
                                    "refresh-n",
                                    strlen ("refresh-n"),
                                    rms,
                                    sizeof(*rms),
                                    NULL,
                                    0));
}


enum GNUNET_GenericReturnValue
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_ExchangeWithdrawValues *alg_values,
                        const union TALER_DenominationBlindingKeyP *bks,
                        const struct TALER_CoinSpendPrivateKeyP *coin_priv,
                        const struct TALER_AgeCommitmentHash *ach,
                        struct TALER_CoinPubHashP *c_hash,
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
                         ach,
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


enum GNUNET_GenericReturnValue
TALER_planchet_to_coin (
  const struct TALER_DenominationPublicKey *dk,
  const struct TALER_BlindedDenominationSignature *blind_sig,
  const union TALER_DenominationBlindingKeyP *bks,
  const struct TALER_CoinSpendPrivateKeyP *coin_priv,
  const struct TALER_AgeCommitmentHash *ach,
  const struct TALER_CoinPubHashP *c_hash,
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
  coin->h_age_commitment = ach;
  return GNUNET_OK;
}


void
TALER_refresh_get_commitment (struct TALER_RefreshCommitmentP *rc,
                              uint32_t kappa,
                              const struct TALER_RefreshMasterSecretP *rms,
                              uint32_t num_new_coins,
                              const struct TALER_RefreshCommitmentEntry *rcs,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct TALER_Amount *amount_with_fee)
{
  struct GNUNET_HashContext *hash_context;

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  if (NULL != rms)
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     rms,
                                     sizeof (*rms));
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
    struct TALER_DenominationHashP denom_hash;

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

      TALER_blinded_planchet_hash_ (&rcd->blinded_planchet,
                                    hash_context);
    }
  }

  /* Conclude */
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &rc->session_hash);
}


void
TALER_coin_pub_hash (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const struct TALER_AgeCommitmentHash *ach,
                     struct TALER_CoinPubHashP *coin_h)
{
  if (TALER_AgeCommitmentHash_isNullOrZero (ach))
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
    struct GNUNET_HashContext *hash_context;

    hash_context = GNUNET_CRYPTO_hash_context_start ();

    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      &coin_pub->eddsa_pub,
      sizeof(struct GNUNET_CRYPTO_EcdsaPublicKey));

    GNUNET_CRYPTO_hash_context_read (
      hash_context,
      ach,
      sizeof(struct TALER_AgeCommitmentHash));

    GNUNET_CRYPTO_hash_context_finish (
      hash_context,
      &coin_h->hash);
  }
}


enum GNUNET_GenericReturnValue
TALER_coin_ev_hash (const struct TALER_BlindedPlanchet *blinded_planchet,
                    const struct TALER_DenominationHashP *denom_hash,
                    struct TALER_BlindedCoinHashP *bch)
{
  struct GNUNET_HashContext *hash_context;

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  GNUNET_CRYPTO_hash_context_read (hash_context,
                                   denom_hash,
                                   sizeof(*denom_hash));
  TALER_blinded_planchet_hash_ (blinded_planchet,
                                hash_context);
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &bch->hash);
  return GNUNET_OK;
}


GNUNET_NETWORK_STRUCT_BEGIN
/**
 * Structure we hash to compute the group key for
 * a denomination group.
 */
struct DenominationGroupP
{
  /**
   * Value of coins in this denomination group.
   */
  struct TALER_AmountNBO value;

  /**
   * Fee structure for all coins in the group.
   */
  struct TALER_DenomFeeSetNBOP fees;

  /**
   * Age mask for the denomiation, in NBO.
   */
  uint32_t age_mask GNUNET_PACKED;

  /**
   * Cipher used for the denomination, in NBO.
   */
  uint32_t cipher GNUNET_PACKED;
};
GNUNET_NETWORK_STRUCT_END


void
TALER_denomination_group_get_key (
  const struct TALER_DenominationGroup *dg,
  struct GNUNET_HashCode *key)
{
  struct DenominationGroupP dgp = {
    .age_mask = htonl (dg->age_mask.bits),
    .cipher = htonl (dg->cipher)
  };

  TALER_amount_hton (&dgp.value,
                     &dg->value);
  TALER_denom_fee_set_hton (&dgp.fees,
                            &dg->fees);
  GNUNET_CRYPTO_hash (&dgp,
                      sizeof (dgp),
                      key);
}


/* end of crypto.c */
