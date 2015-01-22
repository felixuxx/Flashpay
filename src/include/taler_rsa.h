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
 * @file include/taler_rsa.h
 * @brief RSA key management utilities.  Some code is taken from gnunet-0.9.5a
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 *
 * Authors of the gnunet code:
 *   Christian Grothoff
 *   Krista Bennett
 *   Gerd Knorr <kraxel@bytesex.org>
 *   Ioana Patrascu
 *   Tzvetan Horozov
 */

#ifndef TALER_RSA_H
#define TALER_RSA_H

#include <gnunet/gnunet_common.h>
#include <gnunet/gnunet_crypto_lib.h>

/**
 * Length of an RSA KEY (n,e,len), 2048 bit (=256 octests) key n, 2 byte e
 */
#define TALER_RSA_KEY_LENGTH 258

/**
 * @brief Length of RSA encrypted data (2048 bit)
 *
 * We currently do not handle encryption of data
 * that can not be done in a single call to the
 * RSA methods (read: large chunks of data).
 * We should never need that, as we can use
 * the GNUNET_CRYPTO_hash for larger pieces of data for signing,
 * and for encryption, we only need to encode sessionkeys!
 */
#define TALER_RSA_DATA_ENCODING_LENGTH 256

/**
 * The private information of an RSA key pair.
 */
struct TALER_RSA_PrivateKey;


GNUNET_NETWORK_STRUCT_BEGIN

/**
 * GNUnet mandates a certain format for the encoding
 * of private RSA key information that is provided
 * by the RSA implementations.  This format is used
 * to serialize a private RSA key (typically when
 * writing it to disk).
 */
struct TALER_RSA_PrivateKeyBinaryEncoded
{
  /**
   * Total size of the structure, in bytes, in big-endian!
   */
  uint16_t len GNUNET_PACKED;
  uint16_t sizen GNUNET_PACKED; /*  in big-endian! */
  uint16_t sizee GNUNET_PACKED; /*  in big-endian! */
  uint16_t sized GNUNET_PACKED; /*  in big-endian! */
  uint16_t sizep GNUNET_PACKED; /*  in big-endian! */
  uint16_t sizeq GNUNET_PACKED; /*  in big-endian! */
  uint16_t sizedmp1 GNUNET_PACKED;      /*  in big-endian! */
  uint16_t sizedmq1 GNUNET_PACKED;      /*  in big-endian! */
  /* followed by the actual values */
};
GNUNET_NETWORK_STRUCT_END


/**
 * @brief an RSA signature
 */
struct TALER_RSA_Signature
{
  unsigned char sig[TALER_RSA_DATA_ENCODING_LENGTH];
};

GNUNET_NETWORK_STRUCT_BEGIN
/**
 * @brief header of what an RSA signature signs
 *        this must be followed by "size - 8" bytes of
 *        the actual signed data
 */
struct TALER_RSA_SignaturePurpose
{
  /**
   * How many bytes does this signature sign?
   * (including this purpose header); in network
   * byte order (!).
   */
  uint32_t size GNUNET_PACKED;

  /**
   * What does this signature vouch for?  This
   * must contain a GNUNET_SIGNATURE_PURPOSE_XXX
   * constant (from gnunet_signatures.h).  In
   * network byte order!
   */
  uint32_t purpose GNUNET_PACKED;

};


struct TALER_RSA_BlindedSignaturePurpose
{
  unsigned char data[TALER_RSA_DATA_ENCODING_LENGTH];
};


/**
 * @brief A public key.
 */
struct TALER_RSA_PublicKeyBinaryEncoded
{
  /**
   * In big-endian, must be GNUNET_CRYPTO_RSA_KEY_LENGTH+4
   */
  uint16_t len GNUNET_PACKED;

  /**
   * Size of n in key; in big-endian!
   */
  uint16_t sizen GNUNET_PACKED;

  /**
   * The key itself, contains n followed by e.
   */
  unsigned char key[TALER_RSA_KEY_LENGTH];

  /**
   * Padding (must be 0)
   */
  uint16_t padding GNUNET_PACKED;
};

GNUNET_NETWORK_STRUCT_END

/**
 * Create a new private key. Caller must free return value.
 *
 * @return fresh private key
 */
struct TALER_RSA_PrivateKey *
TALER_RSA_key_create ();


/**
 * Free memory occupied by the private key.
 *
 * @param key pointer to the memory to free
 */
void
TALER_RSA_key_free (struct TALER_RSA_PrivateKey *key);


/**
 * Encode the private key in a format suitable for
 * storing it into a file.
 * @return encoding of the private key
 */
struct TALER_RSA_PrivateKeyBinaryEncoded *
TALER_RSA_encode_key (const struct TALER_RSA_PrivateKey *hostkey);


/**
 * Extract the public key of the given private key.
 *
 * @param priv the private key
 * @param pub where to write the public key
 */
void
TALER_RSA_key_get_public (const struct TALER_RSA_PrivateKey *priv,
                          struct TALER_RSA_PublicKeyBinaryEncoded *pub);


/**
 * Decode the private key from the data-format back
 * to the "normal", internal format.
 *
 * @param buf the buffer where the private key data is stored
 * @param len the length of the data in 'buffer'
 * @return NULL on error
 */
struct TALER_RSA_PrivateKey *
TALER_RSA_decode_key (const char *buf, uint16_t len);


/**
 * Convert a public key to a string.
 *
 * @param pub key to convert
 * @return string representing  'pub'
 */
char *
TALER_RSA_public_key_to_string (const struct TALER_RSA_PublicKeyBinaryEncoded *pub);


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
                                  struct TALER_RSA_PublicKeyBinaryEncoded *pub);


/**
 * Sign a given data block.  The size of the message should be less than
 * TALER_RSA_DATA_ENCODING_LENGTH (256) bytes.
 *
 * @param key private key to use for the signing
 * @param msg the message
 * @param size the size of the message
 * @param sig where to write the signature
 * @return GNUNET_SYSERR on error, GNUNET_OK on success
 */
int
TALER_RSA_sign (const struct TALER_RSA_PrivateKey *key,
                const void *msg,
                size_t size,
                struct TALER_RSA_Signature *sig);


/**
 * Verify signature on the given message.  The size of the message should be
 * less than TALER_RSA_DATA_ENCODING_LENGTH (256) bytes.
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
                  const struct TALER_RSA_PublicKeyBinaryEncoded *publicKey);

/**
 * Key used to blind a message
 */
struct TALER_RSA_BlindingKey;

/**
 * Create a blinding key
 *
 * @return the newly created blinding key
 */
struct TALER_RSA_BlindingKey *
TALER_RSA_blinding_key_create ();


/**
 * Destroy a blinding key
 *
 * @param bkey the blinding key to destroy
 */
void
TALER_RSA_blinding_key_destroy (struct TALER_RSA_BlindingKey *bkey);


/**
 * Binary encoding for TALER_RSA_BlindingKey
 */
struct TALER_RSA_BlindingKeyBinaryEncoded
{
  unsigned char data[TALER_RSA_DATA_ENCODING_LENGTH];
};


/**
 * Encode a blinding key
 *
 * @param bkey the blinding key to encode
 * @param bkey_enc where to store the encoded binary key
 * @return #GNUNET_OK upon successful encoding; #GNUNET_SYSERR upon failure
 */
int
TALER_RSA_blinding_key_encode (struct TALER_RSA_BlindingKey *bkey,
                               struct TALER_RSA_BlindingKeyBinaryEncoded *bkey_enc);


/**
 * Decode a blinding key from its encoded form
 *
 * @param bkey_enc the encoded blinding key
 * @return the decoded blinding key; NULL upon error
 */
struct TALER_RSA_BlindingKey *
TALER_RSA_blinding_key_decode (struct TALER_RSA_BlindingKeyBinaryEncoded *bkey_enc);


/**
 * Blinds the given message with the given blinding key
 *
 * @param msg the message
 * @param size the size of the message
 * @param bkey the blinding key
 * @param pkey the public key of the signer
 * @return the blinding signature purpose; NULL upon any error
 */
struct TALER_RSA_BlindedSignaturePurpose *
TALER_RSA_message_blind (const void *msg, size_t size,
                         struct TALER_RSA_BlindingKey *bkey,
                         struct TALER_RSA_PublicKeyBinaryEncoded *pkey);


/**
 * Unblind a signature made on blinding signature purpose.  The signature
 * purpose should have been generated with TALER_RSA_message_blind() function.
 *
 * @param sig the signature made on the blinded signature purpose
 * @param bkey the blinding key used to blind the signature purpose
 * @param pkey the public key of the signer
 * @return GNUNET_SYSERR upon error; GNUNET_OK upon success.
 */
int
TALER_RSA_unblind (struct TALER_RSA_Signature *sig,
                   struct TALER_RSA_BlindingKey *bkey,
                   struct TALER_RSA_PublicKeyBinaryEncoded *pkey);

#endif  /* TALER_RSA_H */

/* end of include/taler_rsa.h */
