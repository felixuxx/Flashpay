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
 * @file include/taler_util.h
 * @brief Interface for common utility functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */

#ifndef UTIL_H_
#define UTIL_H_

#include <gnunet/gnunet_util_lib.h>
#include <gcrypt.h>

/* Define logging functions */
#define LOG_DEBUG(...)                                  \
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG, __VA_ARGS__)

#define LOG_WARNING(...)                                \
  GNUNET_log (GNUNET_ERROR_TYPE_WARNING, __VA_ARGS__)

#define LOG_ERROR(...)                                  \
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR, __VA_ARGS__)


/**
 * Tests a given as assertion and if failed prints it as a warning with the
 * given reason
 *
 * @param EXP the expression to test as assertion
 * @param reason string to print as warning
 */
#define TALER_assert_as(EXP, reason)                           \
  do {                                                          \
    if (EXP) break;                                             \
    LOG_ERROR("%s at %s:%d\n", reason, __FILE__, __LINE__);       \
    abort();                                                    \
  } while(0)



/**
 * Log an error message at log-level 'level' that indicates
 * a failure of the command 'cmd' with the message given
 * by gcry_strerror(rc).
 */
#define LOG_GCRY_ERROR(cmd, rc) do { LOG_ERROR("`%s' failed at %s:%d with error: %s\n", cmd, __FILE__, __LINE__, gcry_strerror(rc)); } while(0)


#define TALER_gcry_ok(cmd) \
  do {int rc; rc = cmd; if (!rc) break; LOG_ERROR("A Gcrypt call failed at %s:%d with error: %s\n", __FILE__, __LINE__, gcry_strerror(rc)); abort(); } while (0)



/**
 * Initialize Gcrypt library.
 */
void
TALER_gcrypt_init (void);


/* *********************** Amount management ****************** */


/**
 * Number of characters (plus 1 for 0-termination) we use to
 * represent currency names (i.e. EUR, USD, etc.).
 */
#define TALER_CURRENCY_LEN 4


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Amount, encoded for network transmission.
 */
struct TALER_AmountNBO
{
  /**
   * Value in the main currency, in NBO.
   */
  uint32_t value;

  /**
   * Additinal fractional value, in NBO.
   */
  uint32_t fraction;

  /**
   * Type of the currency being represented.
   */
  char currency[TALER_CURRENCY_LEN];
};

GNUNET_NETWORK_STRUCT_END


/**
 * Representation of monetary value in a given currency.
 */
struct TALER_Amount
{
  /**
   * Value (numerator of fraction)
   */
  uint32_t value;

  /**
   * Fraction (denominator of fraction)
   */
  uint32_t fraction;

  /**
   * Currency string, left adjusted and padded with zeros.
   */
  char currency[4];
};


/**
 * Parse denomination description, in the format "T : V : F".
 *
 * @param str denomination description
 * @param denom denomination to write the result to
 * @return #GNUNET_OK if the string is a valid denomination specification,
 *         #GNUNET_SYSERR if it is invalid.
 */
int
TALER_string_to_amount (const char *str,
                        struct TALER_Amount *denom);


/**
 * Convert amount from host to network representation.
 *
 * @param d amount in host representation
 * @return amount in network representation
 */
struct TALER_AmountNBO
TALER_amount_hton (struct TALER_Amount d);


/**
 * Convert amount from network to host representation.
 *
 * @param d amount in network representation
 * @return amount in host representation
 */
struct TALER_Amount
TALER_amount_ntoh (struct TALER_AmountNBO dn);


/**
 * Compare the value/fraction of two amounts.  Does not compare the currency,
 * i.e. comparing amounts with the same value and fraction but different
 * currency would return 0.
 *
 * @param a1 first amount
 * @param a2 second amount
 * @return result of the comparison
 */
int
TALER_amount_cmp (struct TALER_Amount a1,
                  struct TALER_Amount a2);


/**
 * Perform saturating subtraction of amounts.
 *
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @return (a1-a2) or 0 if a2>=a1
 */
struct TALER_Amount
TALER_amount_subtract (struct TALER_Amount a1,
                       struct TALER_Amount a2);


/**
 * Perform saturating addition of amounts
 *
 * @param a1 first amount to add
 * @param a2 second amount to add
 * @return sum of a1 and a2
 */
struct TALER_Amount
TALER_amount_add (struct TALER_Amount a1,
                  struct TALER_Amount a2);


/**
 * Normalize the given amount.
 *
 * @param amout amount to normalize
 * @return normalized amount
 */
struct TALER_Amount
TALER_amount_normalize (struct TALER_Amount amount);


/**
 * Convert amount to string.
 *
 * @param amount amount to convert to string
 * @return freshly allocated string representation
 */
char *
TALER_amount_to_string (struct TALER_Amount amount);

/* ****************** FIXME: move to GNUnet? ************** */

/**
 * Return the base32crockford encoding of the given buffer.
 *
 * The returned string will be freshly allocated, and must be free'd
 * with #GNUNET_free().
 *
 * @param buffer with data
 * @param size size of the buffer
 * @return freshly allocated, null-terminated string
 */
char *
TALER_data_to_string_alloc (const void *buf,
                            size_t size);


/* ****************** Refresh crypto primitives ************* */

/**
 * Secret used to decrypt the key to decrypt link secrets.
 */
struct TALER_TransferSecret
{
  /**
   * Secret used to encrypt/decrypt the `struct TALER_LinkSecret`.
   * Must be (currently) a hash as this is what
   * #GNUNET_CRYPTO_ecc_ecdh() returns to us.
   */
  struct GNUNET_HashCode key;
};


/**
 * Secret used to decrypt refresh links.
 */
struct TALER_LinkSecret
{
  /**
   * Secret used to decrypt the refresh link data.
   */
  char key[sizeof (struct GNUNET_HashCode)];
};


/**
 * Encrypted secret used to decrypt refresh links.
 */
struct TALER_EncryptedLinkSecret
{
  /**
   * Encrypted secret, must be the given size!
   */
  char enc[sizeof (struct TALER_LinkSecret)];
};


/**
 * Representation of an encrypted refresh link.
 */
struct TALER_RefreshLinkEncrypted
{

  /**
   * Encrypted blinding key with @e blinding_key_enc_size bytes,
   * must be allocated at the end of this struct.
   */
  const char *blinding_key_enc;

  /**
   * Number of bytes in @e blinding_key_enc.
   */
  size_t blinding_key_enc_size;

  /**
   * Encrypted private key of the coin.
   */
  char coin_priv_enc[sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey)];

};


/**
 * Representation of an refresh link in cleartext.
 */
struct TALER_RefreshLinkDecrypted
{

  /**
   * Private key of the coin.
   */
  struct GNUNET_CRYPTO_EcdsaPrivateKey coin_priv;

  /**
   * Blinding key with @e blinding_key_enc_size bytes.
   */
  struct GNUNET_CRYPTO_rsa_BlindingKey *blinding_key;

};


/**
 * Use the @a trans_sec (from ECDHE) to decrypt the @a secret_enc
 * to obtain the @a secret to decrypt the linkage data.
 *
 * @param secret_enc encrypted secret
 * @param trans_sec transfer secret
 * @param secret shared secret for refresh link decryption
 * @return #GNUNET_OK on success
 */
int
TALER_transfer_decrypt (const struct TALER_EncryptedLinkSecret *secret_enc,
                        const struct TALER_TransferSecret *trans_sec,
                        struct TALER_LinkSecret *secret);


/**
 * Use the @a trans_sec (from ECDHE) to encrypt the @a secret
 * to obtain the @a secret_enc.
 *
 * @param secret shared secret for refresh link decryption
 * @param trans_sec transfer secret
 * @param secret_enc[out] encrypted secret
 * @return #GNUNET_OK on success
 */
int
TALER_transfer_encrypt (const struct TALER_LinkSecret *secret,
                        const struct TALER_TransferSecret *trans_sec,
                        struct TALER_EncryptedLinkSecret *secret_enc);


/**
 * Decrypt refresh link information.
 *
 * @param input encrypted refresh link data
 * @param secret shared secret to use for decryption
 * @return NULL on error
 */
struct TALER_RefreshLinkDecrypted *
TALER_refresh_decrypt (const struct TALER_RefreshLinkEncrypted *input,
                       const struct TALER_LinkSecret *secret);


/**
 * Encrypt refresh link information.
 *
 * @param input plaintext refresh link data
 * @param secret shared secret to use for encryption
 * @return NULL on error (should never happen)
 */
struct TALER_RefreshLinkEncrypted *
TALER_refresh_encrypt (const struct TALER_RefreshLinkDecrypted *input,
                       const struct TALER_LinkSecret *secret);


#endif
