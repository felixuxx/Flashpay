/* NOTE: this is obsolete logic, we should migrate to the
   GNUNET_CRYPTO_rsa-API as soon as possible */

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
 * @file util/rsa.c
 * @brief RSA key management utilities.  Most of the code here is taken from
 *          gnunet-0.9.5a
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 *
 * Authors of the gnunet code:
 *   Christian Grothoff
 *   Krista Bennett
 *   Gerd Knorr <kraxel@bytesex.org>
 *   Ioana Patrascu
 *   Tzvetan Horozov
 */

#include "platform.h"
#include "gcrypt.h"
#include "gnunet/gnunet_util_lib.h"
#include "taler_rsa.h"



#define LOG(kind,...) GNUNET_log_from (kind, "util", __VA_ARGS__)

#define LOG_STRERROR(kind,syscall) GNUNET_log_from_strerror (kind, "util", syscall)

#define LOG_STRERROR_FILE(kind,syscall,filename) GNUNET_log_from_strerror_file (kind, "util", syscall, filename)

/**
 * Log an error message at log-level 'level' that indicates
 * a failure of the command 'cmd' with the message given
 * by gcry_strerror(rc).
 */
#define LOG_GCRY(level, cmd, rc) do { LOG(level, _("`%s' failed at %s:%d with error: %s\n"), cmd, __FILE__, __LINE__, gcry_strerror(rc)); } while(0)

/**
 * Shorthand to cleanup non null mpi data types
 */
#define mpi_release_non_null(mpi)               \
  if (NULL != mpi) gcry_mpi_release (mpi);

/**
 * The private information of an RSA key pair.
 * NOTE: this must match the definition in crypto_ksk.c and gnunet-rsa.c!
 */
struct TALER_RSA_PrivateKey
{
  /**
   * Libgcrypt S-expression for the ECC key.
   */
  gcry_sexp_t sexp;
};


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
key_from_sexp (gcry_mpi_t * array, gcry_sexp_t sexp, const char *topname,
               const char *elems)
{
  gcry_sexp_t list;
  gcry_sexp_t l2;
  const char *s;
  unsigned int i;
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
      for (i = 0; i < idx; i++)
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
      for (i = 0; i < idx; i++)
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
 * If target != size, move target bytes to the
 * end of the size-sized buffer and zero out the
 * first target-size bytes.
 *
 * @param buf original buffer
 * @param size number of bytes in the buffer
 * @param target target size of the buffer
 */
static void
adjust (unsigned char *buf, size_t size, size_t target)
{
  if (size < target)
  {
    memmove (&buf[target - size], buf, size);
    memset (buf, 0, target - size);
  }
}


/**
 * Create a new private key. Caller must free return value.
 *
 * @return fresh private key
 */
struct TALER_RSA_PrivateKey *
TALER_RSA_key_create ()
{
  struct TALER_RSA_PrivateKey *ret;
  gcry_sexp_t s_key;
  gcry_sexp_t s_keyparam;

  GNUNET_assert (0 ==
                 gcry_sexp_build (&s_keyparam, NULL,
                                  "(genkey(rsa(nbits %d)(rsa-use-e 3:257)))",
                                  2048));
  GNUNET_assert (0 == gcry_pk_genkey (&s_key, s_keyparam));
  gcry_sexp_release (s_keyparam);
#if EXTRA_CHECKS
  GNUNET_assert (0 == gcry_pk_testkey (s_key));
#endif
  ret = GNUNET_malloc (sizeof (struct TALER_RSA_PrivateKey));
  ret->sexp = s_key;
  return ret;
}


/**
 * Free memory occupied by the private key.
 *
 * @param key pointer to the memory to free
 */
void
TALER_RSA_key_free (struct TALER_RSA_PrivateKey *key)
{
  gcry_sexp_release (key->sexp);
  GNUNET_free (key);
}


/**
 * Encode the private key in a format suitable for
 * storing it into a file.
 * @return encoding of the private key
 */
struct TALER_RSA_PrivateKeyBinaryEncoded *
TALER_RSA_encode_key (const struct TALER_RSA_PrivateKey *hostkey)
{
  struct TALER_RSA_PrivateKeyBinaryEncoded *retval;
  gcry_mpi_t pkv[6];
  void *pbu[6];
  size_t sizes[6];
  int rc;
  int i;
  int size;

#if EXTRA_CHECKS
  if (gcry_pk_testkey (hostkey->sexp))
  {
    GNUNET_break (0);
    return NULL;
  }
#endif

  memset (pkv, 0, sizeof (gcry_mpi_t) * 6);
  rc = key_from_sexp (pkv, hostkey->sexp, "private-key", "nedpqu");
  if (rc)
    rc = key_from_sexp (pkv, hostkey->sexp, "rsa", "nedpqu");
  if (rc)
    rc = key_from_sexp (pkv, hostkey->sexp, "private-key", "nedpq");
  if (rc)
    rc = key_from_sexp (pkv, hostkey->sexp, "rsa", "nedpq");
  if (rc)
    rc = key_from_sexp (pkv, hostkey->sexp, "private-key", "ned");
  if (rc)
    rc = key_from_sexp (pkv, hostkey->sexp, "rsa", "ned");
  GNUNET_assert (0 == rc);
  size = sizeof (struct TALER_RSA_PrivateKeyBinaryEncoded);
  for (i = 0; i < 6; i++)
  {
    if (NULL != pkv[i])
    {
      GNUNET_assert (0 ==
                     gcry_mpi_aprint (GCRYMPI_FMT_USG,
                                      (unsigned char **) &pbu[i], &sizes[i],
                                      pkv[i]));
      size += sizes[i];
    }
    else
    {
      pbu[i] = NULL;
      sizes[i] = 0;
    }
  }
  GNUNET_assert (size < 65536);
  retval = GNUNET_malloc (size);
  retval->len = htons (size);
  i = 0;
  retval->sizen = htons (sizes[0]);
  memcpy (&((char *) (&retval[1]))[i], pbu[0], sizes[0]);
  i += sizes[0];
  retval->sizee = htons (sizes[1]);
  memcpy (&((char *) (&retval[1]))[i], pbu[1], sizes[1]);
  i += sizes[1];
  retval->sized = htons (sizes[2]);
  memcpy (&((char *) (&retval[1]))[i], pbu[2], sizes[2]);
  i += sizes[2];
  /* swap p and q! */
  retval->sizep = htons (sizes[4]);
  memcpy (&((char *) (&retval[1]))[i], pbu[4], sizes[4]);
  i += sizes[4];
  retval->sizeq = htons (sizes[3]);
  memcpy (&((char *) (&retval[1]))[i], pbu[3], sizes[3]);
  i += sizes[3];
  retval->sizedmp1 = htons (0);
  retval->sizedmq1 = htons (0);
  memcpy (&((char *) (&retval[1]))[i], pbu[5], sizes[5]);
  for (i = 0; i < 6; i++)
  {
    if (pkv[i] != NULL)
      gcry_mpi_release (pkv[i]);
    if (pbu[i] != NULL)
      free (pbu[i]);
  }
  return retval;
}


/**
 * Extract the public key of the given private key.
 *
 * @param priv the private key
 * @param pub where to write the public key
 */
void
TALER_RSA_key_get_public (const struct TALER_RSA_PrivateKey *priv,
                          struct TALER_RSA_PublicKeyBinaryEncoded *pub)
{
  gcry_mpi_t skey[2];
  size_t size;
  int rc;

  rc = key_from_sexp (skey, priv->sexp, "public-key", "ne");
  if (0 != rc)
    rc = key_from_sexp (skey, priv->sexp, "private-key", "ne");
  if (0 != rc)
    rc = key_from_sexp (skey, priv->sexp, "rsa", "ne");
  GNUNET_assert (0 == rc);
  pub->len =
      htons (sizeof (struct TALER_RSA_PublicKeyBinaryEncoded) -
             sizeof (pub->padding));
  pub->sizen = htons (TALER_RSA_DATA_ENCODING_LENGTH);
  pub->padding = 0;
  size = TALER_RSA_DATA_ENCODING_LENGTH;
  GNUNET_assert (0 ==
                 gcry_mpi_print (GCRYMPI_FMT_USG, &pub->key[0], size, &size,
                                 skey[0]));
  adjust (&pub->key[0], size, TALER_RSA_DATA_ENCODING_LENGTH);
  size = TALER_RSA_KEY_LENGTH - TALER_RSA_DATA_ENCODING_LENGTH;
  GNUNET_assert (0 ==
                 gcry_mpi_print (GCRYMPI_FMT_USG,
                                 &pub->key
                                 [TALER_RSA_DATA_ENCODING_LENGTH], size,
                                 &size, skey[1]));
  adjust (&pub->key[TALER_RSA_DATA_ENCODING_LENGTH], size,
          TALER_RSA_KEY_LENGTH -
          TALER_RSA_DATA_ENCODING_LENGTH);
  gcry_mpi_release (skey[0]);
  gcry_mpi_release (skey[1]);
}


/**
 * Decode the private key from the data-format back
 * to the "normal", internal format.
 *
 * @param buf the buffer where the private key data is stored
 * @param len the length of the data in 'buffer'
 * @return NULL on error
 */
struct TALER_RSA_PrivateKey *
TALER_RSA_decode_key (const char *buf, uint16_t len)
{
  struct TALER_RSA_PrivateKey *ret;
  const struct TALER_RSA_PrivateKeyBinaryEncoded *encoding =
      (const struct TALER_RSA_PrivateKeyBinaryEncoded *) buf;
  gcry_sexp_t res;
  gcry_mpi_t n;
  gcry_mpi_t e;
  gcry_mpi_t d;
  gcry_mpi_t p;
  gcry_mpi_t q;
  gcry_mpi_t u;
  int rc;
  size_t size;
  size_t pos;
  uint16_t enc_len;
  size_t erroff;

  enc_len = ntohs (encoding->len);
  if (len != enc_len)
    return NULL;

  pos = 0;
  size = ntohs (encoding->sizen);
  rc = gcry_mpi_scan (&n, GCRYMPI_FMT_USG,
                      &((const unsigned char *) (&encoding[1]))[pos], size,
                      &size);
  pos += ntohs (encoding->sizen);
  if (0 != rc)
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
    return NULL;
  }
  size = ntohs (encoding->sizee);
  rc = gcry_mpi_scan (&e, GCRYMPI_FMT_USG,
                      &((const unsigned char *) (&encoding[1]))[pos], size,
                      &size);
  pos += ntohs (encoding->sizee);
  if (0 != rc)
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
    gcry_mpi_release (n);
    return NULL;
  }
  size = ntohs (encoding->sized);
  rc = gcry_mpi_scan (&d, GCRYMPI_FMT_USG,
                      &((const unsigned char *) (&encoding[1]))[pos], size,
                      &size);
  pos += ntohs (encoding->sized);
  if (0 != rc)
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
    gcry_mpi_release (n);
    gcry_mpi_release (e);
    return NULL;
  }
  /* swap p and q! */
  size = ntohs (encoding->sizep);
  if (size > 0)
  {
    rc = gcry_mpi_scan (&q, GCRYMPI_FMT_USG,
                        &((const unsigned char *) (&encoding[1]))[pos], size,
                        &size);
    pos += ntohs (encoding->sizep);
    if (0 != rc)
    {
      LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
      gcry_mpi_release (n);
      gcry_mpi_release (e);
      gcry_mpi_release (d);
      return NULL;
    }
  }
  else
    q = NULL;
  size = ntohs (encoding->sizeq);
  if (size > 0)
  {
    rc = gcry_mpi_scan (&p, GCRYMPI_FMT_USG,
                        &((const unsigned char *) (&encoding[1]))[pos], size,
                        &size);
    pos += ntohs (encoding->sizeq);
    if (0 != rc)
    {
      LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
      gcry_mpi_release (n);
      gcry_mpi_release (e);
      gcry_mpi_release (d);
      if (NULL != q)
        gcry_mpi_release (q);
      return NULL;
    }
  }
  else
    p = NULL;
  pos += ntohs (encoding->sizedmp1);
  pos += ntohs (encoding->sizedmq1);
  size =
      ntohs (encoding->len) - sizeof (struct TALER_RSA_PrivateKeyBinaryEncoded) - pos;
  if (size > 0)
  {
    rc = gcry_mpi_scan (&u, GCRYMPI_FMT_USG,
                        &((const unsigned char *) (&encoding[1]))[pos], size,
                        &size);
    if (0 != rc)
    {
      LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
      gcry_mpi_release (n);
      gcry_mpi_release (e);
      gcry_mpi_release (d);
      if (NULL != p)
        gcry_mpi_release (p);
      if (NULL != q)
        gcry_mpi_release (q);
      return NULL;
    }
  }
  else
    u = NULL;

  if ((NULL != p) && (NULL != q) && (NULL != u))
  {
    rc = gcry_sexp_build (&res, &erroff,
                          "(private-key(rsa(n %m)(e %m)(d %m)(p %m)(q %m)(u %m)))",
                          n, e, d, p, q, u);
  }
  else
  {
    if ((NULL != p) && (NULL != q))
    {
      rc = gcry_sexp_build (&res, &erroff,
                            "(private-key(rsa(n %m)(e %m)(d %m)(p %m)(q %m)))",
                            n, e, d, p, q);
    }
    else
    {
      rc = gcry_sexp_build (&res, &erroff,
                            "(private-key(rsa(n %m)(e %m)(d %m)))", n, e, d);
    }
  }
  gcry_mpi_release (n);
  gcry_mpi_release (e);
  gcry_mpi_release (d);
  if (NULL != p)
    gcry_mpi_release (p);
  if (NULL != q)
    gcry_mpi_release (q);
  if (NULL != u)
    gcry_mpi_release (u);

  if (0 != rc)
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_sexp_build", rc);
  if (0 != (rc = gcry_pk_testkey (res)))
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_pk_testkey", rc);
    return NULL;
  }
  ret = GNUNET_malloc (sizeof (struct TALER_RSA_PrivateKey));
  ret->sexp = res;
  return ret;
}


/**
 * Convert a public key to a string.
 *
 * @param pub key to convert
 * @return string representing  'pub'
 */
char *
TALER_RSA_public_key_to_string (const struct TALER_RSA_PublicKeyBinaryEncoded *pub)
{
  char *pubkeybuf;
  size_t keylen = (sizeof (struct TALER_RSA_PublicKeyBinaryEncoded)) * 8;
  char *end;

  if (keylen % 5 > 0)
    keylen += 5 - keylen % 5;
  keylen /= 5;
  pubkeybuf = GNUNET_malloc (keylen + 1);
  end = GNUNET_STRINGS_data_to_string ((unsigned char *) pub,
                                       sizeof (struct TALER_RSA_PublicKeyBinaryEncoded),
                                       pubkeybuf,
                                       keylen);
  if (NULL == end)
  {
    GNUNET_free (pubkeybuf);
    return NULL;
  }
  *end = '\0';
  return pubkeybuf;
}


/**
 * Convert a string representing a public key to a public key.
 *
 * @param enc encoded public key
 * @param enclen number of bytes in enc (without 0-terminator)
 * @param pub where to store the public key
 * @return GNUNET_OK on success
 */
int
TALER_RSA_public_key_from_string (const char *enc,
                                  size_t enclen,
                                  struct TALER_RSA_PublicKeyBinaryEncoded *pub)
{
  size_t keylen = (sizeof (struct TALER_RSA_PublicKeyBinaryEncoded)) * 8;

  if (keylen % 5 > 0)
    keylen += 5 - keylen % 5;
  keylen /= 5;
  if (enclen != keylen)
    return GNUNET_SYSERR;

  if (GNUNET_OK != GNUNET_STRINGS_string_to_data (enc, enclen,
                                                  (unsigned char*) pub,
                                                  sizeof (struct TALER_RSA_PublicKeyBinaryEncoded)))
    return GNUNET_SYSERR;
  if ( (ntohs (pub->len) != sizeof (struct TALER_RSA_PublicKeyBinaryEncoded)) ||
       (ntohs (pub->padding) != 0) ||
       (ntohs (pub->sizen) != TALER_RSA_DATA_ENCODING_LENGTH) )
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Convert the data specified in the given purpose argument to an
 * S-expression suitable for signature operations.
 *
 * @param ptr pointer to the data to convert
 * @param size the size of the data
 * @return converted s-expression
 */
static gcry_sexp_t
data_to_sexp (const void *ptr, size_t size)
{
  gcry_mpi_t value;
  gcry_sexp_t data;

  value = NULL;
  data = NULL;
  GNUNET_assert (0 == gcry_mpi_scan (&value, GCRYMPI_FMT_USG, ptr, size, NULL));
  GNUNET_assert (0 == gcry_sexp_build (&data, NULL, "(data (flags raw) (value %M))", value));
  gcry_mpi_release (value);
  return data;
}


/**
 * Sign the given hash block.
 *
 * @param key private key to use for the signing
 * @param hash the block containing the hash of the message to sign
 * @param hash_size the size of the hash block
 * @param sig where to write the signature
 * @return GNUNET_SYSERR on error, GNUNET_OK on success
 */
int
TALER_RSA_sign (const struct TALER_RSA_PrivateKey *key,
                const void *hash,
                size_t hash_size,
                struct TALER_RSA_Signature *sig)
{
  gcry_sexp_t result;
  gcry_sexp_t data;
  size_t ssize;
  gcry_mpi_t rval;

  data = data_to_sexp (hash, hash_size);
  GNUNET_assert (0 == gcry_pk_sign (&result, data, key->sexp));
  gcry_sexp_release (data);
  GNUNET_assert (0 == key_from_sexp (&rval, result, "rsa", "s"));
  gcry_sexp_release (result);
  ssize = sizeof (struct TALER_RSA_Signature);
  GNUNET_assert (0 ==
                 gcry_mpi_print (GCRYMPI_FMT_USG, (unsigned char *) sig, ssize,
                                 &ssize, rval));
  gcry_mpi_release (rval);
  adjust (sig->sig, ssize, sizeof (struct TALER_RSA_Signature));
  return GNUNET_OK;
}


/**
 * Convert the given public key from the network format to the
 * S-expression that can be used by libgcrypt.
 *
 * @param publicKey public key to decode
 * @return NULL on error
 */
static gcry_sexp_t
decode_public_key (const struct TALER_RSA_PublicKeyBinaryEncoded *publicKey)
{
  gcry_sexp_t result;
  gcry_mpi_t n;
  gcry_mpi_t e;
  size_t size;
  size_t erroff;
  int rc;

  if ((ntohs (publicKey->sizen) != TALER_RSA_DATA_ENCODING_LENGTH) ||
      (ntohs (publicKey->len) !=
       sizeof (struct TALER_RSA_PublicKeyBinaryEncoded) -
       sizeof (publicKey->padding)))
  {
    GNUNET_break (0);
    return NULL;
  }
  size = TALER_RSA_DATA_ENCODING_LENGTH;
  if (0 != (rc = gcry_mpi_scan (&n, GCRYMPI_FMT_USG, &publicKey->key[0], size, &size)))
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
    return NULL;
  }
  size = TALER_RSA_KEY_LENGTH - TALER_RSA_DATA_ENCODING_LENGTH;
  if (0 != (rc = gcry_mpi_scan (&e, GCRYMPI_FMT_USG,
                                &publicKey->key[TALER_RSA_DATA_ENCODING_LENGTH],
                                size, &size)))
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
    gcry_mpi_release (n);
    return NULL;
  }
  rc = gcry_sexp_build (&result, &erroff, "(public-key(rsa(n %m)(e %m)))", n,
                        e);
  gcry_mpi_release (n);
  gcry_mpi_release (e);
  if (0 != rc)
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_sexp_build", rc);  /* erroff gives more info */
    return NULL;
  }
  return result;
}


/**
 * Verify signature with the given hash.
 *
 * @param hash the hash code to verify against the signature
 * @param sig signature that is being validated
 * @param publicKey public key of the signer
 * @returns GNUNET_OK if ok, GNUNET_SYSERR if invalid
 */
int
TALER_RSA_hash_verify (const struct GNUNET_HashCode *hash,
                       const struct TALER_RSA_Signature *sig,
                       const struct TALER_RSA_PublicKeyBinaryEncoded *publicKey)
{
  gcry_sexp_t data;
  gcry_sexp_t sigdata;
  size_t size;
  gcry_mpi_t val;
  gcry_sexp_t psexp;
  size_t erroff;
  int rc;

  size = sizeof (struct TALER_RSA_Signature);
  GNUNET_assert (0 ==
                 gcry_mpi_scan (&val, GCRYMPI_FMT_USG,
                                (const unsigned char *) sig, size, &size));
  GNUNET_assert (0 ==
                 gcry_sexp_build (&sigdata, &erroff, "(sig-val(rsa(s %m)))",
                                  val));
  gcry_mpi_release (val);
  data = data_to_sexp (hash, sizeof (struct GNUNET_HashCode));
  if (! (psexp = decode_public_key (publicKey)))
  {
    gcry_sexp_release (data);
    gcry_sexp_release (sigdata);
    return GNUNET_SYSERR;
  }
  rc = gcry_pk_verify (sigdata, data, psexp);
  gcry_sexp_release (psexp);
  gcry_sexp_release (data);
  gcry_sexp_release (sigdata);
  if (rc)
  {
    LOG (GNUNET_ERROR_TYPE_WARNING,
         _("RSA signature verification failed at %s:%d: %s\n"), __FILE__,
         __LINE__, gcry_strerror (rc));
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify signature on the given message
 *
 * @param msg the message
 * @param size the size of the message
 * @param sig signature that is being validated
 * @param publicKey public key of the signer
 * @returns GNUNET_OK if ok, GNUNET_SYSERR if invalid
 */
int
TALER_RSA_verify (const void *msg, size_t size,
                  const struct TALER_RSA_Signature *sig,
                  const struct TALER_RSA_PublicKeyBinaryEncoded *publicKey)
{
  struct GNUNET_HashCode hash;

  GNUNET_CRYPTO_hash (msg, size, &hash);
  return TALER_RSA_hash_verify (&hash, sig, publicKey);
}

/**
 * The blinding key is equal in length to the RSA modulus
 */
#define TALER_RSA_BLINDING_KEY_LEN TALER_RSA_DATA_ENCODING_LENGTH

struct TALER_RSA_BlindingKey
{
  /**
   * The blinding factor
   */
  gcry_mpi_t r;
};

struct TALER_RSA_BlindingKey *
TALER_RSA_blinding_key_create ()
{
  struct TALER_RSA_BlindingKey *blind;

  blind = GNUNET_new (struct TALER_RSA_BlindingKey);
  blind->r = gcry_mpi_new (TALER_RSA_BLINDING_KEY_LEN * 8);
  gcry_mpi_randomize (blind->r, TALER_RSA_BLINDING_KEY_LEN * 8, GCRY_STRONG_RANDOM);
  return blind;
}


void
TALER_RSA_blinding_key_destroy (struct TALER_RSA_BlindingKey *bkey)
{
  gcry_mpi_release (bkey->r);
  GNUNET_free (bkey);
}


struct TALER_RSA_BlindedSignaturePurpose *
TALER_RSA_message_blind (const void *msg, size_t size,
                         struct TALER_RSA_BlindingKey *bkey,
                         struct TALER_RSA_PublicKeyBinaryEncoded *pkey)
{
  struct TALER_RSA_BlindedSignaturePurpose *bsp;
  struct GNUNET_HashCode hash;
  gcry_sexp_t psexp;
  gcry_mpi_t data;
  gcry_mpi_t skey[2];
  gcry_mpi_t r_e;
  gcry_mpi_t data_r_e;
  size_t rsize;
  gcry_error_t rc;
  int ret;

  bsp = NULL;
  psexp = NULL;
  data = NULL;
  skey[0] = skey[1] = NULL;
  r_e = NULL;
  data_r_e = NULL;
  rsize = 0;
  rc = 0;
  ret = 0;
  if (! (psexp = decode_public_key (pkey)))
    return NULL;
  ret = key_from_sexp (skey, psexp, "public-key", "ne");
  if (0 != ret)
    ret = key_from_sexp (skey, psexp, "rsa", "ne");
  gcry_sexp_release (psexp);
  psexp = NULL;
  GNUNET_assert (0 == ret);
  GNUNET_CRYPTO_hash (msg, size, &hash);
  if (0 != (rc=gcry_mpi_scan (&data, GCRYMPI_FMT_USG,
                              (const unsigned char *) msg, size, &rsize)))
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_WARNING, "gcry_mpi_scan", rc);
    goto cleanup;
  }
  r_e = gcry_mpi_new (0);
  gcry_mpi_powm (r_e, bkey->r,
                 skey[1],       /* e */
                 skey[0]);      /* n */

  data_r_e = gcry_mpi_new (0);
  gcry_mpi_mulm (data_r_e, data, r_e, skey[0]);

  bsp = GNUNET_new (struct TALER_RSA_BlindedSignaturePurpose);
  rc = gcry_mpi_print (GCRYMPI_FMT_USG,
                       (unsigned char *) bsp,
                       sizeof (struct TALER_RSA_BlindedSignaturePurpose),
                       &rsize,
                       data_r_e);
  GNUNET_assert (0 == rc);
  adjust ((unsigned char *) bsp, rsize,
          sizeof (struct TALER_RSA_BlindedSignaturePurpose));

 cleanup:
  if (NULL != psexp) gcry_sexp_release (psexp);
  mpi_release_non_null (skey[0]);
  mpi_release_non_null (skey[1]);
  mpi_release_non_null (data);
  mpi_release_non_null (r_e);
  mpi_release_non_null (data_r_e);
  return bsp;
}


int
TALER_RSA_unblind (struct TALER_RSA_Signature *sig,
                   struct TALER_RSA_BlindingKey *bkey,
                   struct TALER_RSA_PublicKeyBinaryEncoded *pkey)
{
  gcry_sexp_t psexp;
  gcry_mpi_t skey;
  gcry_mpi_t sigval;
  gcry_mpi_t r_inv;
  gcry_mpi_t ubsig;
  size_t rsize;
  gcry_error_t rc;
  int ret;

  psexp = NULL;
  skey = NULL;
  sigval = NULL;
  r_inv = NULL;
  ubsig = NULL;
  rsize = 0;
  rc = 0;
  ret = GNUNET_SYSERR;
  if (! (psexp = decode_public_key (pkey)))
    return GNUNET_SYSERR;
  ret = key_from_sexp (&skey, psexp, "public-key", "n");
  if (0 != ret)
    ret = key_from_sexp (&skey, psexp, "rsa", "n");
  gcry_sexp_release (psexp);
  psexp = NULL;
  if (0 != (rc = gcry_mpi_scan (&sigval, GCRYMPI_FMT_USG,
                                (const unsigned char *) sig,
                                sizeof (struct TALER_RSA_Signature),
                                &rsize)))
  {
    LOG_GCRY (GNUNET_ERROR_TYPE_ERROR, "gcry_mpi_scan", rc);
    goto cleanup;
  }
  r_inv = gcry_mpi_new (0);
  GNUNET_assert (1 == gcry_mpi_invm (r_inv, bkey->r, skey)); /* n: skey */
  ubsig = gcry_mpi_new (0);
  gcry_mpi_mulm (ubsig, sigval, r_inv, skey);
  rc = gcry_mpi_print (GCRYMPI_FMT_USG,
                       (unsigned char *) sig,
                       sizeof (struct TALER_RSA_Signature),
                       &rsize,
                       ubsig);
  GNUNET_assert (0 == rc);
  adjust ((unsigned char *) sig, rsize, sizeof (struct TALER_RSA_Signature));
  ret = GNUNET_OK;

 cleanup:
  if (NULL != psexp) gcry_sexp_release (psexp);
  mpi_release_non_null (skey);
  mpi_release_non_null (sigval);
  mpi_release_non_null (r_inv);
  mpi_release_non_null (ubsig);
  return ret;
}


/**
 * Encode a blinding key
 *
 * @param bkey the blinding key to encode
 * @param bkey_enc where to store the encoded binary key
 * @return #GNUNET_OK upon successful encoding; #GNUNET_SYSERR upon failure
 */
int
TALER_RSA_blinding_key_encode (struct TALER_RSA_BlindingKey *bkey,
                               struct TALER_RSA_BlindingKeyBinaryEncoded *bkey_enc)
{
  GNUNET_abort ();              /* FIXME: not implemented */
}


/**
 * Decode a blinding key from its encoded form
 *
 * @param bkey_enc the encoded blinding key
 * @return the decoded blinding key; NULL upon error
 */
struct TALER_RSA_BlindingKey *
TALER_RSA_blinding_key_decode (struct TALER_RSA_BlindingKeyBinaryEncoded *bkey_enc)
{
  GNUNET_abort ();              /* FIXME: not implemented */
}

/* end of util/rsa.c */
