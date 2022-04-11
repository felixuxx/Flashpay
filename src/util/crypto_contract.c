/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file util/crypto_contract.c
 * @brief functions for encrypting and decrypting contracts for P2P payments
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_util.h"
#include <zlib.h>
#include "taler_exchange_service.h"


/**
 * Different types of contracts supported.
 */
enum ContractFormats
{
  /**
   * The encrypted contract represents a payment offer. The receiver
   * can merge it into a reserve/account to accept the contract and
   * obtain the payment.
   */
  TALER_EXCHANGE_CONTRACT_PAYMENT_OFFER = 0
};


/**
 * Nonce used for encryption, 24 bytes.
 */
struct NonceP
{
  uint8_t nonce[crypto_secretbox_NONCEBYTES];
};

/**
 * Specifies a key used for symmetric encryption, 32 bytes.
 */
struct SymKeyP
{
  uint32_t key[8];
};


/**
 * Compute @a key.
 *
 * @param key_material key for calculation
 * @param key_m_len length of key
 * @param nonce nonce for calculation
 * @param salt salt value for calculation
 * @param[out] key where to write the en-/description key
 */
static void
derive_key (const void *key_material,
            size_t key_m_len,
            const struct NonceP *nonce,
            const char *salt,
            struct SymKeyP *key)
{
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (key,
                                    sizeof (*key),
                                    /* salt / XTS */
                                    nonce,
                                    sizeof (*nonce),
                                    /* ikm */
                                    key_material,
                                    key_m_len,
                                    /* info chunks */
                                    /* The "salt" passed here is actually not something random,
                                       but a protocol-specific identifier string.  Thus
                                       we pass it as a context info to the HKDF */
                                    salt,
                                    strlen (salt),
                                    NULL,
                                    0));
}


/**
 * Encryption of data.
 *
 * @param nonce value to use for the nonce
 * @param key key which is used to derive a key/iv pair from
 * @param key_len length of key
 * @param data data to encrypt
 * @param data_size size of the data
 * @param salt salt value which is used for key derivation
 * @param[out] res ciphertext output
 * @param[out] res_size size of the ciphertext
 */
static void
contract_encrypt (const struct NonceP *nonce,
                  const void *key,
                  size_t key_len,
                  const void *data,
                  size_t data_size,
                  const char *salt,
                  void **res,
                  size_t *res_size)
{
  size_t ciphertext_size;
  struct SymKeyP skey;

  derive_key (key,
              key_len,
              nonce,
              salt,
              &skey);
  ciphertext_size = crypto_secretbox_NONCEBYTES
                    + crypto_secretbox_MACBYTES + data_size;
  *res_size = ciphertext_size;
  *res = GNUNET_malloc (ciphertext_size);
  memcpy (*res, nonce, crypto_secretbox_NONCEBYTES);
  GNUNET_assert (0 ==
                 crypto_secretbox_easy (*res + crypto_secretbox_NONCEBYTES,
                                        data,
                                        data_size,
                                        (void *) nonce,
                                        (void *) &skey));
}


/**
 * Decryption of data like encrypted recovery document etc.
 *
 * @param key key which is used to derive a key/iv pair from
 * @param key_len length of key
 * @param data data to decrypt
 * @param data_size size of the data
 * @param salt salt value which is used for key derivation
 * @param[out] res plaintext output
 * @param[out] res_size size of the plaintext
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
contract_decrypt (const void *key,
                  size_t key_len,
                  const void *data,
                  size_t data_size,
                  const char *salt,
                  void **res,
                  size_t *res_size)
{
  const struct NonceP *nonce;
  struct SymKeyP skey;
  size_t plaintext_size;

  if (data_size < crypto_secretbox_NONCEBYTES + crypto_secretbox_MACBYTES)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  nonce = data;
  derive_key (key,
              key_len,
              nonce,
              salt,
              &skey);
  plaintext_size = data_size - (crypto_secretbox_NONCEBYTES
                                + crypto_secretbox_MACBYTES);
  *res = GNUNET_malloc (plaintext_size);
  *res_size = plaintext_size;
  if (0 != crypto_secretbox_open_easy (*res,
                                       data + crypto_secretbox_NONCEBYTES,
                                       data_size - crypto_secretbox_NONCEBYTES,
                                       (void *) nonce,
                                       (void *) &skey))
  {
    GNUNET_break (0);
    GNUNET_free (*res);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Header for encrypted contracts.
 */
struct ContractHeader
{
  /**
   * Type of the contract, in NBO.
   */
  uint32_t ctype;

  /**
   * Length of the encrypted contract, in NBO.
   */
  uint32_t clen;

  /**
   * Included key material, depending on @e ctype.
   */
  union
  {
    struct TALER_PurseMergePrivateKeyP merge_priv;
  } keys;

};


/**
 * Salt we use when encrypting contracts for merge.
 */
#define MERGE_SALT "p2p-merge-contract"


void
TALER_CRYPTO_contract_encrypt_for_merge (
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const struct TALER_PurseMergePrivateKeyP *merge_priv,
  const json_t *contract_terms,
  void **econtract,
  size_t *econtract_size)
{
  struct GNUNET_HashCode key;
  char *cstr;
  size_t clen;
  void *xbuf;
  struct ContractHeader *hdr;
  struct NonceP nonce;
  uLongf cbuf_size;
  int ret;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_ecdh_eddsa (&contract_priv->ecdhe_priv,
                                           &purse_pub->eddsa_pub,
                                           &key));
  cstr = json_dumps (contract_terms,
                     JSON_COMPACT | JSON_SORT_KEYS);
  clen = strlen (cstr);
  cbuf_size = compressBound (clen);
  xbuf = GNUNET_malloc (cbuf_size);
  ret = compress (xbuf,
                  &cbuf_size,
                  (const Bytef *) cstr,
                  clen);
  GNUNET_assert (Z_OK == ret);
  free (cstr);
  hdr = GNUNET_malloc (sizeof (*hdr) + cbuf_size);
  hdr->ctype = htonl (TALER_EXCHANGE_CONTRACT_PAYMENT_OFFER);
  hdr->clen = htonl ((uint32_t) clen);
  hdr->keys.merge_priv = *merge_priv;
  memcpy (&hdr[1],
          xbuf,
          cbuf_size);
  GNUNET_free (xbuf);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &nonce,
                              sizeof (nonce));
  contract_encrypt (&nonce,
                    &key,
                    sizeof (key),
                    hdr,
                    sizeof (*hdr) + cbuf_size,
                    MERGE_SALT,
                    econtract,
                    econtract_size);
  GNUNET_free (hdr);
}


json_t *
TALER_CRYPTO_contract_decrypt_for_merge (
  const struct TALER_ContractDiffiePrivateP *contract_priv,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const void *econtract,
  size_t econtract_size,
  struct TALER_PurseMergePrivateKeyP *merge_priv)
{
  struct GNUNET_HashCode key;
  void *xhdr;
  size_t hdr_size;
  const struct ContractHeader *hdr;
  char *cstr;
  uLongf clen;
  json_error_t json_error;
  json_t *ret;

  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdh_eddsa (&contract_priv->ecdhe_priv,
                                &purse_pub->eddsa_pub,
                                &key))
  {
    GNUNET_break (0);
    return NULL;
  }
  if (GNUNET_OK !=
      contract_decrypt (&key,
                        sizeof (key),
                        econtract,
                        econtract_size,
                        MERGE_SALT,
                        &xhdr,
                        &hdr_size))
  {
    GNUNET_break_op (0);
    return NULL;
  }
  if (hdr_size < sizeof (*hdr))
  {
    GNUNET_break_op (0);
    GNUNET_free (xhdr);
    return NULL;
  }
  hdr = xhdr;
  clen = ntohl (hdr->clen);
  if (clen >= GNUNET_MAX_MALLOC_CHECKED)
  {
    GNUNET_break_op (0);
    GNUNET_free (xhdr);
    return NULL;
  }
  cstr = GNUNET_malloc (clen + 1);
  if (Z_OK !=
      uncompress ((Bytef *) cstr,
                  &clen,
                  (const Bytef *) &hdr[1],
                  hdr_size - sizeof (*hdr)))
  {
    GNUNET_break_op (0);
    GNUNET_free (cstr);
    GNUNET_free (xhdr);
    return NULL;
  }
  *merge_priv = hdr->keys.merge_priv;
  GNUNET_free (xhdr);
  ret = json_loadb ((char *) cstr,
                    clen,
                    JSON_DECODE_ANY,
                    &json_error);
  if (NULL == ret)
  {
    GNUNET_break_op (0);
    GNUNET_free (cstr);
    return NULL;
  }
  GNUNET_free (cstr);
  return ret;
}
