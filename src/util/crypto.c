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
 * Should we use the RSA blind signing implementation from libgnunetutil?  The
 * blinding only works correctly with a current version of libgnunetutil.
 *
 * Only applies to blinding and unblinding, but
 * not to blind signing.
 *
 * FIXME: Can we define some macro for this in configure.ac
 * to detect the version?
 */
#define USE_GNUNET_RSA_BLINDING 0


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
  struct GNUNET_HashCode c_hash;
#if ENABLE_SANITY_CHECKS
  struct GNUNET_HashCode d_hash;

  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     &d_hash);
  GNUNET_assert (0 ==
                 GNUNET_memcmp (&d_hash,
                                &coin_public_info->denom_pub_hash));
#endif
  GNUNET_CRYPTO_hash (&coin_public_info->coin_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &c_hash);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_rsa_verify (&c_hash,
                                coin_public_info->denom_sig.rsa_signature,
                                denom_pub->rsa_public_key))
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
TALER_planchet_setup_random (struct TALER_PlanchetSecretsP *ps)
{
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                              ps,
                              sizeof (*ps));
}


enum GNUNET_GenericReturnValue
TALER_planchet_prepare (const struct TALER_DenominationPublicKey *dk,
                        const struct TALER_PlanchetSecretsP *ps,
                        struct GNUNET_HashCode *c_hash,
                        struct TALER_PlanchetDetail *pd)
{
  struct TALER_CoinSpendPublicKeyP coin_pub;

  GNUNET_CRYPTO_eddsa_key_get_public (&ps->coin_priv.eddsa_priv,
                                      &coin_pub.eddsa_pub);
  GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      c_hash);
  if (GNUNET_YES !=
      TALER_rsa_blind (c_hash,
                       &ps->blinding_key.bks,
                       dk->rsa_public_key,
                       &pd->coin_ev,
                       &pd->coin_ev_size))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_rsa_public_key_hash (dk->rsa_public_key,
                                     &pd->denom_pub_hash);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_planchet_to_coin (const struct TALER_DenominationPublicKey *dk,
                        const struct GNUNET_CRYPTO_RsaSignature *blind_sig,
                        const struct TALER_PlanchetSecretsP *ps,
                        const struct GNUNET_HashCode *c_hash,
                        struct TALER_FreshCoin *coin)
{
  struct GNUNET_CRYPTO_RsaSignature *sig;

  sig = TALER_rsa_unblind (blind_sig,
                           &ps->blinding_key.bks,
                           dk->rsa_public_key);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_rsa_verify (c_hash,
                                sig,
                                dk->rsa_public_key))
  {
    GNUNET_break_op (0);
    GNUNET_CRYPTO_rsa_signature_free (sig);
    return GNUNET_SYSERR;
  }
  coin->sig.rsa_signature = sig;
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
    void *buf;
    size_t buf_size;

    /* The denomination keys should / must all be identical regardless
       of what offset we use, so we use [0]. */
    GNUNET_assert (kappa > 0); /* sanity check */
    buf_size = GNUNET_CRYPTO_rsa_public_key_encode (
      rcs[0].new_coins[i].dk->rsa_public_key,
      &buf);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     buf,
                                     buf_size);
    GNUNET_free (buf);
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


#if ! USE_GNUNET_RSA_BLINDING


/**
 * The private information of an RSA key pair.
 *
 * FIXME: This declaration is evil, as it defines
 * an opaque struct that is "owned" by GNUnet.
 */
struct GNUNET_CRYPTO_RsaPrivateKey
{
  /**
   * Libgcrypt S-expression for the RSA private key.
   */
  gcry_sexp_t sexp;
};


/**
 * The public information of an RSA key pair.
 *
 * FIXME: This declaration is evil, as it defines
 * an opaque struct that is "owned" by GNUnet.
 */
struct GNUNET_CRYPTO_RsaPublicKey
{
  /**
   * Libgcrypt S-expression for the RSA public key.
   */
  gcry_sexp_t sexp;
};

/**
 * @brief an RSA signature
 *
 * FIXME: This declaration is evil, as it defines
 * an opaque struct that is "owned" by GNUnet.
 */
struct GNUNET_CRYPTO_RsaSignature
{
  /**
   * Libgcrypt S-expression for the RSA signature.
   */
  gcry_sexp_t sexp;
};

/**
 * @brief RSA blinding key
 */
struct RsaBlindingKey
{
  /**
   * Random value used for blinding.
   */
  gcry_mpi_t r;
};


/**
 * Destroy a blinding key
 *
 * @param bkey the blinding key to destroy
 */
static void
rsa_blinding_key_free (struct RsaBlindingKey *bkey)
{
  gcry_mpi_release (bkey->r);
  GNUNET_free (bkey);
}


/**
 * Extract values from an S-expression.
 *
 * @param array where to store the result(s)
 * @param sexp S-expression to parse
 * @param topname top-level name in the S-expression that is of interest
 * @param elems names of the elements to extract
 * @return 0 on success
 */
static int
key_from_sexp (gcry_mpi_t *array,
               gcry_sexp_t sexp,
               const char *topname,
               const char *elems)
{
  gcry_sexp_t list;
  gcry_sexp_t l2;
  const char *s;
  unsigned int idx;

  if (! (list = gcry_sexp_find_token (sexp, topname, 0)))
    return 1;
  l2 = gcry_sexp_cadr (list);
  gcry_sexp_release (list);
  list = l2;
  if (! list)
    return 2;
  idx = 0;
  for (s = elems; *s; s++, idx++)
  {
    if (! (l2 = gcry_sexp_find_token (list, s, 1)))
    {
      for (unsigned int i = 0; i < idx; i++)
      {
        gcry_free (array[i]);
        array[i] = NULL;
      }
      gcry_sexp_release (list);
      return 3;                 /* required parameter not found */
    }
    array[idx] = gcry_sexp_nth_mpi (l2, 1, GCRYMPI_FMT_USG);
    gcry_sexp_release (l2);
    if (! array[idx])
    {
      for (unsigned int i = 0; i < idx; i++)
      {
        gcry_free (array[i]);
        array[i] = NULL;
      }
      gcry_sexp_release (list);
      return 4;                 /* required parameter is invalid */
    }
  }
  gcry_sexp_release (list);
  return 0;
}


/**
 * Test for malicious RSA key.
 *
 * Assuming n is an RSA modulous and r is generated using a call to
 * GNUNET_CRYPTO_kdf_mod_mpi, if gcd(r,n) != 1 then n must be a
 * malicious RSA key designed to deanomize the user.
 *
 * @param r KDF result
 * @param n RSA modulus
 * @return True if gcd(r,n) = 1, False means RSA key is malicious
 */
static int
rsa_gcd_validate (gcry_mpi_t r, gcry_mpi_t n)
{
  gcry_mpi_t g;
  int t;

  g = gcry_mpi_new (0);
  t = gcry_mpi_gcd (g, r, n);
  gcry_mpi_release (g);
  return t;
}


/**
 * Computes a full domain hash seeded by the given public key.
 * This gives a measure of provable security to the Taler exchange
 * against one-more forgery attacks.  See:
 *   https://eprint.iacr.org/2001/002.pdf
 *   http://www.di.ens.fr/~pointche/Documents/Papers/2001_fcA.pdf
 *
 * @param hash initial hash of the message to sign
 * @param pkey the public key of the signer
 * @return MPI value set to the FDH, NULL if RSA key is malicious
 */
static gcry_mpi_t
rsa_full_domain_hash (const struct GNUNET_CRYPTO_RsaPublicKey *pkey,
                      const struct GNUNET_HashCode *hash)
{
  gcry_mpi_t r, n;
  void *xts;
  size_t xts_len;
  int ok;

  /* Extract the composite n from the RSA public key */
  GNUNET_assert (0 == key_from_sexp (&n, pkey->sexp, "rsa", "n"));
  /* Assert that it at least looks like an RSA key */
  GNUNET_assert (0 == gcry_mpi_get_flag (n, GCRYMPI_FLAG_OPAQUE));

  /* We key with the public denomination key as a homage to RSA-PSS by  *
  * Mihir Bellare and Phillip Rogaway.  Doing this lowers the degree   *
  * of the hypothetical polyomial-time attack on RSA-KTI created by a  *
  * polynomial-time one-more forgary attack.  Yey seeding!             */
  xts_len = GNUNET_CRYPTO_rsa_public_key_encode (pkey, &xts);

  GNUNET_CRYPTO_kdf_mod_mpi (&r,
                             n,
                             xts, xts_len,
                             hash, sizeof(*hash),
                             "RSA-FDA FTpsW!");
  GNUNET_free (xts);

  ok = rsa_gcd_validate (r, n);
  gcry_mpi_release (n);
  if (ok)
    return r;
  gcry_mpi_release (r);
  return NULL;
}


/**
 * Create a blinding key
 *
 * @param pkey the public key to blind for
 * @param bks pre-secret to use to derive the blinding key
 * @return the newly created blinding key, NULL if RSA key is malicious
 */
static struct RsaBlindingKey *
rsa_blinding_key_derive (const struct GNUNET_CRYPTO_RsaPublicKey *pkey,
                         const struct GNUNET_CRYPTO_RsaBlindingKeySecret *bks)
{
  char *xts = "Blinding KDF extractor HMAC key";  /* Trusts bks' randomness more */
  struct RsaBlindingKey *blind;
  gcry_mpi_t n;

  blind = GNUNET_new (struct RsaBlindingKey);
  GNUNET_assert (NULL != blind);

  /* Extract the composite n from the RSA public key */
  GNUNET_assert (0 == key_from_sexp (&n, pkey->sexp, "rsa", "n"));
  /* Assert that it at least looks like an RSA key */
  GNUNET_assert (0 == gcry_mpi_get_flag (n, GCRYMPI_FLAG_OPAQUE));

  GNUNET_CRYPTO_kdf_mod_mpi (&blind->r,
                             n,
                             xts, strlen (xts),
                             bks, sizeof(*bks),
                             "Blinding KDF");
  if (0 == rsa_gcd_validate (blind->r, n))
  {
    GNUNET_free (blind);
    blind = NULL;
  }

  gcry_mpi_release (n);
  return blind;
}


/**
 * Print an MPI to a newly created buffer
 *
 * @param v MPI to print.
 * @param[out] buffer newly allocated buffer containing the result
 * @return number of bytes stored in @a buffer
 */
static size_t
numeric_mpi_alloc_n_print (gcry_mpi_t v,
                           char **buffer)
{
  size_t n;
  char *b;
  size_t rsize;

  gcry_mpi_print (GCRYMPI_FMT_USG,
                  NULL,
                  0,
                  &n,
                  v);
  b = GNUNET_malloc (n);
  GNUNET_assert (0 ==
                 gcry_mpi_print (GCRYMPI_FMT_USG,
                                 (unsigned char *) b,
                                 n,
                                 &rsize,
                                 v));
  *buffer = b;
  return n;
}


#endif /* ! USE_GNUNET_RSA_BLINDING */


enum GNUNET_GenericReturnValue
TALER_rsa_blind (const struct GNUNET_HashCode *hash,
                 const struct GNUNET_CRYPTO_RsaBlindingKeySecret *bks,
                 struct GNUNET_CRYPTO_RsaPublicKey *pkey,
                 void **buf,
                 size_t *buf_size)
{
#if USE_GNUNET_RSA_BLINDING
  return GNUNET_CRYPTO_rsa_blind (hash,
                                  bks,
                                  pkey,
                                  buf,
                                  buf_size);
#else
  struct RsaBlindingKey *bkey;
  gcry_mpi_t data;
  gcry_mpi_t ne[2];
  gcry_mpi_t r_e;
  gcry_mpi_t data_r_e;
  int ret;

  GNUNET_assert (buf != NULL);
  GNUNET_assert (buf_size != NULL);
  ret = key_from_sexp (ne, pkey->sexp, "public-key", "ne");
  if (0 != ret)
    ret = key_from_sexp (ne, pkey->sexp, "rsa", "ne");
  if (0 != ret)
  {
    GNUNET_break (0);
    *buf = NULL;
    *buf_size = 0;
    return GNUNET_NO;
  }

  data = rsa_full_domain_hash (pkey, hash);
  if (NULL == data)
    goto rsa_gcd_validate_failure;

  bkey = rsa_blinding_key_derive (pkey, bks);
  if (NULL == bkey)
  {
    gcry_mpi_release (data);
    goto rsa_gcd_validate_failure;
  }

  r_e = gcry_mpi_new (0);
  gcry_mpi_powm (r_e,
                 bkey->r,
                 ne[1],
                 ne[0]);
  data_r_e = gcry_mpi_new (0);
  gcry_mpi_mulm (data_r_e,
                 data,
                 r_e,
                 ne[0]);
  gcry_mpi_release (data);
  gcry_mpi_release (ne[0]);
  gcry_mpi_release (ne[1]);
  gcry_mpi_release (r_e);
  rsa_blinding_key_free (bkey);

  *buf_size = numeric_mpi_alloc_n_print (data_r_e,
                                         (char **) buf);
  gcry_mpi_release (data_r_e);

  return GNUNET_YES;

rsa_gcd_validate_failure:
  /* We know the RSA key is malicious here, so warn the wallet. */
  /* GNUNET_break_op (0); */
  gcry_mpi_release (ne[0]);
  gcry_mpi_release (ne[1]);
  *buf = NULL;
  *buf_size = 0;
  return GNUNET_NO;
#endif
}


struct GNUNET_CRYPTO_RsaSignature *
TALER_rsa_unblind (const struct GNUNET_CRYPTO_RsaSignature *sig,
                   const struct GNUNET_CRYPTO_RsaBlindingKeySecret *bks,
                   struct GNUNET_CRYPTO_RsaPublicKey *pkey)
{
#if USE_GNUNET_RSA_BLINDING
  return GNUNET_CRYPTO_rsa_unblind (sig,
                                    bks,
                                    pkey);
#else
  struct RsaBlindingKey *bkey;
  gcry_mpi_t n;
  gcry_mpi_t s;
  gcry_mpi_t r_inv;
  gcry_mpi_t ubsig;
  int ret;
  struct GNUNET_CRYPTO_RsaSignature *sret;

  ret = key_from_sexp (&n, pkey->sexp, "public-key", "n");
  if (0 != ret)
    ret = key_from_sexp (&n, pkey->sexp, "rsa", "n");
  if (0 != ret)
  {
    GNUNET_break_op (0);
    return NULL;
  }
  ret = key_from_sexp (&s, sig->sexp, "sig-val", "s");
  if (0 != ret)
    ret = key_from_sexp (&s, sig->sexp, "rsa", "s");
  if (0 != ret)
  {
    gcry_mpi_release (n);
    GNUNET_break_op (0);
    return NULL;
  }

  bkey = rsa_blinding_key_derive (pkey, bks);
  if (NULL == bkey)
  {
    /* RSA key is malicious since rsa_gcd_validate failed here.
     * It should have failed during GNUNET_CRYPTO_rsa_blind too though,
     * so the exchange is being malicious in an unfamilair way, maybe
     * just trying to crash us.  */
    GNUNET_break_op (0);
    gcry_mpi_release (n);
    gcry_mpi_release (s);
    return NULL;
  }

  r_inv = gcry_mpi_new (0);
  if (1 !=
      gcry_mpi_invm (r_inv,
                     bkey->r,
                     n))
  {
    /* We cannot find r mod n, so gcd(r,n) != 1, which should get *
    * caught above, but we handle it the same here.              */
    GNUNET_break_op (0);
    gcry_mpi_release (r_inv);
    rsa_blinding_key_free (bkey);
    gcry_mpi_release (n);
    gcry_mpi_release (s);
    return NULL;
  }

  ubsig = gcry_mpi_new (0);
  gcry_mpi_mulm (ubsig, s, r_inv, n);
  gcry_mpi_release (n);
  gcry_mpi_release (r_inv);
  gcry_mpi_release (s);
  rsa_blinding_key_free (bkey);

  sret = GNUNET_new (struct GNUNET_CRYPTO_RsaSignature);
  GNUNET_assert (0 ==
                 gcry_sexp_build (&sret->sexp,
                                  NULL,
                                  "(sig-val (rsa (s %M)))",
                                  ubsig));
  gcry_mpi_release (ubsig);
  return sret;
#endif
}


/* end of crypto.c */
