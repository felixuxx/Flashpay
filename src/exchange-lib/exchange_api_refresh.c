/*
  This file is part of TALER
  Copyright (C) 2015 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/exchange_api_refresh.c
 * @brief Implementation of the /refresh/melt+reveal requests of the exchange's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"
#include "taler_exchange_service.h"
#include "exchange_api_common.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"


/* ********************* /refresh/ common ***************************** */

/* structures for committing refresh data to disk before doing the
   network interaction(s) */

GNUNET_NETWORK_STRUCT_BEGIN

/**
 * Header of serialized information about a coin we are melting.
 */
struct MeltedCoinP
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Amount this coin contributes to the melt, including fee.
   */
  struct TALER_AmountNBO melt_amount_with_fee;

  /**
   * The applicable fee for withdrawing a coin of this denomination
   */
  struct TALER_AmountNBO fee_melt;

  /**
   * The original value of the coin.
   */
  struct TALER_AmountNBO original_value;

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_AbsoluteNBO expire_deposit;

  /**
   * Size of the encoded public key that follows.
   */
  uint16_t pbuf_size;

  /**
   * Size of the encoded signature that follows.
   */
  uint16_t sbuf_size;

  /* Followed by serializations of:
     1) struct TALER_DenominationPublicKey pub_key;
     2) struct TALER_DenominationSignature sig;
  */
};


/**
 * Header for serializations of coin-specific information about the
 * fresh coins we generate during a melt.
 */
struct FreshCoinP
{

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Size of the encoded blinding key that follows.
   */
  uint32_t bbuf_size;

  /* Followed by serialization of:
     - struct TALER_DenominationBlindingKey blinding_key;
  */

};


/**
 * Header of serialized data about a melt operation, suitable for
 * persisting it on disk.
 */
struct MeltDataP
{

  /**
   * Hash over the melting session.
   */
  struct GNUNET_HashCode melt_session_hash;

  /**
   * Link secret used to encrypt the @a coin_priv and the blinding
   * key in the linkage data for the respective cut-and-choose dimension.
   */
  struct TALER_LinkSecretP link_secrets[TALER_CNC_KAPPA];

  /**
   * Number of coins we are melting, in NBO
   */
  uint16_t num_melted_coins GNUNET_PACKED;

  /**
   * Number of coins we are creating, in NBO
   */
  uint16_t num_fresh_coins GNUNET_PACKED;

  /* Followed by serializations of:
     1) struct MeltedCoinP melted_coins[num_melted_coins];
     2) struct TALER_EXCHANGE_DenomPublicKey fresh_pks[num_fresh_coins];
     3) TALER_CNC_KAPPA times:
        3a) struct FreshCoinP fresh_coins[num_fresh_coins];
  */
};


GNUNET_NETWORK_STRUCT_END


/**
 * Information about a coin we are melting.
 */
struct MeltedCoin
{
  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Amount this coin contributes to the melt, including fee.
   */
  struct TALER_Amount melt_amount_with_fee;

  /**
   * The applicable fee for melting a coin of this denomination
   */
  struct TALER_Amount fee_melt;

  /**
   * The original value of the coin.
   */
  struct TALER_Amount original_value;

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Absolute expire_deposit;

  /**
   * Denomination key of the original coin.
   */
  struct TALER_DenominationPublicKey pub_key;

  /**
   * Exchange's signature over the coin.
   */
  struct TALER_DenominationSignature sig;

};


/**
 * Coin-specific information about the fresh coins we generate during
 * a melt.
 */
struct FreshCoin
{

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Blinding key used for blinding during blind signing.
   */
  struct TALER_DenominationBlindingKey blinding_key;

};


/**
 * Melt data in non-serialized format for convenient processing.
 */
struct MeltData
{

  /**
   * Hash over the melting session.
   */
  struct GNUNET_HashCode melt_session_hash;

  /**
   * Link secrets for each cut-and-choose dimension.
   */
  struct TALER_LinkSecretP link_secrets[TALER_CNC_KAPPA];

  /**
   * Number of coins we are creating
   */
  uint16_t num_fresh_coins;

  /**
   * Information about the melted coin.
   */
  struct MeltedCoin melted_coin;

  /**
   * Array of @e num_fresh_coins denomination keys for the coins to be
   * freshly exchangeed.
   */
  struct TALER_DenominationPublicKey *fresh_pks;

  /**
   * Arrays of @e num_fresh_coins with information about the fresh
   * coins to be created, for each cut-and-choose dimension.
   */
  struct FreshCoin *fresh_coins[TALER_CNC_KAPPA];
};


/**
 * Free all information associated with a melted coin session.
 *
 * @param mc melted coin to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
static void
free_melted_coin (struct MeltedCoin *mc)
{
  if (NULL != mc->pub_key.rsa_public_key)
    GNUNET_CRYPTO_rsa_public_key_free (mc->pub_key.rsa_public_key);
  if (NULL != mc->sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (mc->sig.rsa_signature);
}


/**
 * Free all information associated with a fresh coin.
 *
 * @param fc fresh coin to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
static void
free_fresh_coin (struct FreshCoin *fc)
{
  if (NULL == fc)
    return;
  if (NULL != fc->blinding_key.rsa_blinding_key)
    GNUNET_CRYPTO_rsa_blinding_key_free (fc->blinding_key.rsa_blinding_key);
}


/**
 * Free all information associated with a melting session.  Note
 * that we allow the melting session to be only partially initialized,
 * as we use this function also when freeing melt data that was not
 * fully initialized (i.e. due to failures in #deserialize_melt_data()).
 *
 * @param md melting data to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
static void
free_melt_data (struct MeltData *md)
{
  unsigned int i;
  unsigned int j;

  free_melted_coin (&md->melted_coin);
  if (NULL != md->fresh_pks)
  {
    for (i=0;i<md->num_fresh_coins;i++)
      if (NULL != md->fresh_pks[i].rsa_public_key)
        GNUNET_CRYPTO_rsa_public_key_free (md->fresh_pks[i].rsa_public_key);
    GNUNET_free (md->fresh_pks);
  }

  for (i=0;i<TALER_CNC_KAPPA;i++)
  {
    for (j=0;j<md->num_fresh_coins;j++)
      free_fresh_coin (&md->fresh_coins[i][j]);
    GNUNET_free (md->fresh_coins[i]);
  }
  /* Finally, clean up a bit...
     (NOTE: compilers might optimize this away, so this is
     not providing any strong assurances that the key material
     is purged.) */
  memset (md,
          0,
          sizeof (struct MeltData));
}


/**
 * Serialize information about a coin we are melting.
 *
 * @param mc information to serialize
 * @param buf buffer to write data in, NULL to just compute
 *            required size
 * @param off offeset at @a buf to use
 * @return number of bytes written to @a buf at @a off, or if
 *        @a buf is NULL, number of bytes required; 0 on error
 */
static size_t
serialize_melted_coin (const struct MeltedCoin *mc,
                       char *buf,
                       size_t off)
{
  struct MeltedCoinP mcp;
  unsigned int i;
  char *pbuf;
  size_t pbuf_size;
  char *sbuf;
  size_t sbuf_size;

  sbuf_size = GNUNET_CRYPTO_rsa_signature_encode (mc->sig.rsa_signature,
                                                  &sbuf);
  pbuf_size = GNUNET_CRYPTO_rsa_public_key_encode (mc->pub_key.rsa_public_key,
                                                   &pbuf);
  if (NULL == buf)
  {
    GNUNET_free (sbuf);
    GNUNET_free (pbuf);
    return sizeof (struct MeltedCoinP) + sbuf_size + pbuf_size;
  }
  if ( (sbuf_size > UINT16_MAX) ||
       (pbuf_size > UINT16_MAX) )
  {
    GNUNET_break (0);
    return 0;
  }
  mcp.coin_priv = mc->coin_priv;
  TALER_amount_hton (&mcp.melt_amount_with_fee,
                     &mc->melt_amount_with_fee);
  TALER_amount_hton (&mcp.fee_melt,
                     &mc->fee_melt);
  TALER_amount_hton (&mcp.original_value,
                     &mc->original_value);
  for (i=0;i<TALER_CNC_KAPPA;i++)
    mcp.transfer_priv[i] = mc->transfer_priv[i];
  mcp.expire_deposit = GNUNET_TIME_absolute_hton (mc->expire_deposit);
  mcp.pbuf_size = htons ((uint16_t) pbuf_size);
  mcp.sbuf_size = htons ((uint16_t) sbuf_size);
  memcpy (&buf[off],
          &mcp,
          sizeof (struct MeltedCoinP));
  memcpy (&buf[off + sizeof (struct MeltedCoinP)],
          pbuf,
          pbuf_size);
  memcpy (&buf[off + sizeof (struct MeltedCoinP) + pbuf_size],
          sbuf,
          sbuf_size);
  GNUNET_free (sbuf);
  GNUNET_free (pbuf);
  return sizeof (struct MeltedCoinP) + sbuf_size + pbuf_size;
}


/**
 * Deserialize information about a coin we are melting.
 *
 * @param[out] mc information to deserialize
 * @param buf buffer to read data from
 * @param size number of bytes available at @a buf to use
 * @param[out] ok set to #GNUNET_NO to report errors
 * @return number of bytes read from @a buf, 0 on error
 */
static size_t
deserialize_melted_coin (struct MeltedCoin *mc,
                         const char *buf,
                         size_t size,
                         int *ok)
{
  struct MeltedCoinP mcp;
  unsigned int i;
  size_t pbuf_size;
  size_t sbuf_size;
  size_t off;

  if (size < sizeof (struct MeltedCoinP))
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  memcpy (&mcp,
          buf,
          sizeof (struct MeltedCoinP));
  pbuf_size = ntohs (mcp.pbuf_size);
  sbuf_size = ntohs (mcp.sbuf_size);
  if (size < sizeof (struct MeltedCoinP) + pbuf_size + sbuf_size)
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  off = sizeof (struct MeltedCoinP);
  mc->pub_key.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_decode (&buf[off],
                                           pbuf_size);
  off += pbuf_size;
  mc->sig.rsa_signature
    = GNUNET_CRYPTO_rsa_signature_decode (&buf[off],
                                          sbuf_size);
  off += sbuf_size;
  if ( (NULL == mc->pub_key.rsa_public_key) ||
       (NULL == mc->sig.rsa_signature) )
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }

  mc->coin_priv = mcp.coin_priv;
  TALER_amount_ntoh (&mc->melt_amount_with_fee,
                     &mcp.melt_amount_with_fee);
  TALER_amount_ntoh (&mc->fee_melt,
                     &mcp.fee_melt);
  TALER_amount_ntoh (&mc->original_value,
                     &mcp.original_value);
  for (i=0;i<TALER_CNC_KAPPA;i++)
    mc->transfer_priv[i] = mcp.transfer_priv[i];
  mc->expire_deposit = GNUNET_TIME_absolute_ntoh (mcp.expire_deposit);
  return off;
}


/**
 * Serialize information about a denomination key.
 *
 * @param dk information to serialize
 * @param buf buffer to write data in, NULL to just compute
 *            required size
 * @param off offeset at @a buf to use
 * @return number of bytes written to @a buf at @a off, or if
 *        @a buf is NULL, number of bytes required
 */
static size_t
serialize_denomination_key (const struct TALER_DenominationPublicKey *dk,
                            char *buf,
                            size_t off)
{
  char *pbuf;
  size_t pbuf_size;
  uint32_t be;

  pbuf_size = GNUNET_CRYPTO_rsa_public_key_encode (dk->rsa_public_key,
                                                   &pbuf);
  if (NULL == buf)
  {
    GNUNET_free (pbuf);
    return pbuf_size + sizeof (uint32_t);
  }
  be = htonl ((uint32_t) pbuf_size);
  memcpy (&buf[off],
          &be,
          sizeof (uint32_t));
  memcpy (&buf[off + sizeof (uint32_t)],
          pbuf,
          pbuf_size);
  GNUNET_free (pbuf);
  return pbuf_size + sizeof (uint32_t);
}


/**
 * Deserialize information about a denomination key.
 *
 * @param[out] dk information to deserialize
 * @param buf buffer to read data from
 * @param size number of bytes available at @a buf to use
 * @param[out] ok set to #GNUNET_NO to report errors
 * @return number of bytes read from @a buf, 0 on error
 */
static size_t
deserialize_denomination_key (struct TALER_DenominationPublicKey *dk,
                              const char *buf,
                              size_t size,
                              int *ok)
{
  size_t pbuf_size;
  uint32_t be;

  if (size < sizeof (uint32_t))
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  memcpy (&be,
          buf,
          sizeof (uint32_t));
  pbuf_size = ntohl (be);
  if (size < sizeof (uint32_t) + pbuf_size)
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  dk->rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_decode (&buf[sizeof (uint32_t)],
                                           pbuf_size);

  if (NULL == dk->rsa_public_key)
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  return sizeof (uint32_t) + pbuf_size;
}


/**
 * Serialize information about a fresh coin we are generating.
 *
 * @param fc information to serialize
 * @param buf buffer to write data in, NULL to just compute
 *            required size
 * @param off offeset at @a buf to use
 * @return number of bytes written to @a buf at @a off, or if
 *        @a buf is NULL, number of bytes required
 */
static size_t
serialize_fresh_coin (const struct FreshCoin *fc,
                      char *buf,
                      size_t off)
{
  struct FreshCoinP fcp;
  char *bbuf;
  size_t bbuf_size;

  bbuf_size = GNUNET_CRYPTO_rsa_blinding_key_encode (fc->blinding_key.rsa_blinding_key,
                                                     &bbuf);
  if (NULL == buf)
  {
    GNUNET_free (bbuf);
    return sizeof (struct FreshCoinP) + bbuf_size;
  }
  fcp.coin_priv = fc->coin_priv;
  fcp.bbuf_size = htonl ((uint32_t) bbuf_size);
  memcpy (&buf[off],
          &fcp,
          sizeof (struct FreshCoinP));
  memcpy (&buf[off + sizeof (struct FreshCoinP)],
          bbuf,
          bbuf_size);
  GNUNET_free (bbuf);
  return sizeof (struct FreshCoinP) + bbuf_size;
}


/**
 * Deserialize information about a fresh coin we are generating.
 *
 * @param[out] fc information to deserialize
 * @param buf buffer to read data from
 * @param size number of bytes available at @a buf to use
 * @param[out] ok set to #GNUNET_NO to report errors
 * @return number of bytes read from @a buf, 0 on error
 */
static size_t
deserialize_fresh_coin (struct FreshCoin *fc,
                        const char *buf,
                        size_t size,
                        int *ok)
{
  struct FreshCoinP fcp;
  size_t bbuf_size;

  if (size < sizeof (struct FreshCoinP))
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  memcpy (&fcp,
          buf,
          sizeof (struct FreshCoinP));
  bbuf_size = ntohl (fcp.bbuf_size);
  if (size < sizeof (struct FreshCoinP) + bbuf_size)
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  fc->blinding_key.rsa_blinding_key
    = GNUNET_CRYPTO_rsa_blinding_key_decode (&buf[sizeof (struct FreshCoinP)],
                                             bbuf_size);
  if (NULL == fc->blinding_key.rsa_blinding_key)
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  fc->coin_priv = fcp.coin_priv;
  return sizeof (struct FreshCoinP) + bbuf_size;
}


/**
 * Serialize melt data.
 *
 * @param md data to serialize
 * @param[out] res_size size of buffer returned
 * @return serialized melt data
 */
static char *
serialize_melt_data (const struct MeltData *md,
                     size_t *res_size)
{
  size_t size;
  size_t asize;
  char *buf;
  unsigned int i;
  unsigned int j;

  size = 0;
  asize = (size_t) -1; /* make the compiler happy */
  buf = NULL;
  /* we do 2 iterations, #1 to determine total size, #2 to
     actually construct the buffer */
  do {
    if (0 == size)
    {
      size = sizeof (struct MeltDataP);
    }
    else
    {
      struct MeltDataP *mdp;

      buf = GNUNET_malloc (size);
      asize = size; /* just for invariant check later */
      size = sizeof (struct MeltDataP);
      mdp = (struct MeltDataP *) buf;
      mdp->melt_session_hash = md->melt_session_hash;
      for (i=0;i<TALER_CNC_KAPPA;i++)
        mdp->link_secrets[i] = md->link_secrets[i];
      mdp->num_fresh_coins = htons (md->num_fresh_coins);
    }
    size += serialize_melted_coin (&md->melted_coin,
                                   buf,
                                   size);
    for (i=0;i<md->num_fresh_coins;i++)
      size += serialize_denomination_key (&md->fresh_pks[i],
                                          buf,
                                          size);
    for (i=0;i<TALER_CNC_KAPPA;i++)
      for(j=0;j<md->num_fresh_coins;j++)
        size += serialize_fresh_coin (&md->fresh_coins[i][j],
                                      buf,
                                      size);
  } while (NULL == buf);
  GNUNET_assert (size == asize);
  *res_size = size;
  return buf;
}


/**
 * Deserialize melt data.
 *
 * @param buf serialized data
 * @param buf_size size of @a buf
 * @return deserialized melt data, NULL on error
 */
static struct MeltData *
deserialize_melt_data (const char *buf,
                       size_t buf_size)
{
  struct MeltData *md;
  struct MeltDataP mdp;
  unsigned int i;
  unsigned int j;
  size_t off;
  int ok;

  if (buf_size < sizeof (struct MeltDataP))
    return NULL;
  memcpy (&mdp,
          buf,
          sizeof (struct MeltDataP));
  md = GNUNET_new (struct MeltData);
  md->melt_session_hash = mdp.melt_session_hash;
  for (i=0;i<TALER_CNC_KAPPA;i++)
    md->link_secrets[i] = mdp.link_secrets[i];
  md->num_fresh_coins = ntohs (mdp.num_fresh_coins);
  md->fresh_pks = GNUNET_new_array (md->num_fresh_coins,
                                    struct TALER_DenominationPublicKey);
  for (i=0;i<TALER_CNC_KAPPA;i++)
    md->fresh_coins[i] = GNUNET_new_array (md->num_fresh_coins,
                                           struct FreshCoin);
  off = sizeof (struct MeltDataP);
  ok = GNUNET_YES;
  off += deserialize_melted_coin (&md->melted_coin,
                                  &buf[off],
                                  buf_size - off,
                                  &ok);
  for (i=0;(i<md->num_fresh_coins)&&(GNUNET_YES == ok);i++)
    off += deserialize_denomination_key (&md->fresh_pks[i],
                                         &buf[off],
                                         buf_size - off,
                                         &ok);

  for (i=0;i<TALER_CNC_KAPPA;i++)
    for(j=0;(j<md->num_fresh_coins)&&(GNUNET_YES == ok);j++)
      off += deserialize_fresh_coin (&md->fresh_coins[i][j],
                                     &buf[off],
                                     buf_size - off,
                                     &ok);
  if (off != buf_size)
  {
    GNUNET_break (0);
    ok = GNUNET_NO;
  }
  if (GNUNET_YES != ok)
  {
    free_melt_data (md);
    GNUNET_free (md);
    return NULL;
  }
  return md;
}


/**
 * Setup information for a fresh coin.
 *
 * @param[out] fc value to initialize
 * @param pk denomination information for the fresh coin
 */
static void
setup_fresh_coin (struct FreshCoin *fc,
                  const struct TALER_EXCHANGE_DenomPublicKey *pk)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *epk;
  unsigned int len;

  epk = GNUNET_CRYPTO_eddsa_key_create ();
  fc->coin_priv.eddsa_priv = *epk;
  GNUNET_free (epk);
  len = GNUNET_CRYPTO_rsa_public_key_len (pk->key.rsa_public_key);
  fc->blinding_key.rsa_blinding_key
    = GNUNET_CRYPTO_rsa_blinding_key_create (len);
}


/**
 * Melt (partially spent) coins to obtain fresh coins that are
 * unlinkable to the original coin(s).  Note that melting more
 * than one coin in a single request will make those coins linkable,
 * so the safest operation only melts one coin at a time.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, is operation does
 * not actually initiate the request. Instead, it generates a buffer
 * which the caller must store before proceeding with the actual call
 * to #TALER_EXCHANGE_refresh_melt() that will generate the request.
 *
 * This function does verify that the given request data is internally
 * consistent.  However, the @a melts_sigs are only verified if
 * @a check_sigs is set to #GNUNET_YES, as this may be relatively
 * expensive and should be redundant.
 *
 * Aside from some non-trivial cryptographic operations that might
 * take a bit of CPU time to complete, this function returns
 * its result immediately and does not start any asynchronous
 * processing.  This function is also thread-safe.
 *
 * @param melt_priv private key of the coin to melt
 * @param melt_amount amount specifying how much
 *                     the coin will contribute to the melt (including fee)
 * @param melt_sig signature affirming the
 *                   validity of the public keys corresponding to the
 *                   @a melt_priv private key
 * @param melt_pk denomination key information
 *                   record corresponding to the @a melt_sig
 *                   validity of the keys
 * @param check_sig verify the validity of the @a melt_sig signature
 * @param fresh_pks_len length of the @a pks array
 * @param fresh_pks array of @a pks_len denominations of fresh coins to create
 * @param[out] res_size set to the size of the return value, or 0 on error
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         Otherwise, pointer to a buffer of @a res_size to store persistently
 *         before proceeding to #TALER_EXCHANGE_refresh_melt().
 *         Non-null results should be freed using #GNUNET_free().
 */
char *
TALER_EXCHANGE_refresh_prepare (const struct TALER_CoinSpendPrivateKeyP *melt_priv,
                                const struct TALER_Amount *melt_amount,
                                const struct TALER_DenominationSignature *melt_sig,
                                const struct TALER_EXCHANGE_DenomPublicKey *melt_pk,
                                int check_sig,
                                unsigned int fresh_pks_len,
                                const struct TALER_EXCHANGE_DenomPublicKey *fresh_pks,
                                size_t *res_size)
{
  struct MeltData md;
  char *buf;
  unsigned int i;
  unsigned int j;
  struct GNUNET_HashContext *hash_context;

  /* build up melt data structure */
  for (i=0;i<TALER_CNC_KAPPA;i++)
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_STRONG,
                                &md.link_secrets[i],
                                sizeof (struct TALER_LinkSecretP));
  md.num_fresh_coins = fresh_pks_len;
  md.melted_coin.coin_priv = *melt_priv;
  md.melted_coin.melt_amount_with_fee = *melt_amount;
  md.melted_coin.fee_melt = melt_pk->fee_refresh;
  md.melted_coin.original_value = melt_pk->value;
  for (j=0;j<TALER_CNC_KAPPA;j++)
  {
    struct GNUNET_CRYPTO_EcdhePrivateKey *tpk;

    tpk = GNUNET_CRYPTO_ecdhe_key_create ();
    md.melted_coin.transfer_priv[j].ecdhe_priv = *tpk;
    GNUNET_free (tpk);
  }
  md.melted_coin.expire_deposit
    = melt_pk->expire_deposit;
  md.melted_coin.pub_key.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (melt_pk->key.rsa_public_key);
  md.melted_coin.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_signature_dup (melt_sig->rsa_signature);
  md.fresh_pks = GNUNET_new_array (fresh_pks_len,
                                   struct TALER_DenominationPublicKey);
  for (i=0;i<fresh_pks_len;i++)
    md.fresh_pks[i].rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_dup (fresh_pks[i].key.rsa_public_key);
  for (i=0;i<TALER_CNC_KAPPA;i++)
  {
    md.fresh_coins[i] = GNUNET_new_array (fresh_pks_len,
                                          struct FreshCoin);
    for (j=0;j<fresh_pks_len;j++)
      setup_fresh_coin (&md.fresh_coins[i][j],
                        &fresh_pks[j]);
  }

  /* now compute melt session hash */
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  for (i=0;i<fresh_pks_len;i++)
  {
    char *buf;
    size_t buf_size;

    buf_size = GNUNET_CRYPTO_rsa_public_key_encode (fresh_pks[i].key.rsa_public_key,
                                                    &buf);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     buf,
                                     buf_size);
    GNUNET_free (buf);
  }
  {
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_AmountNBO melt_amountn;

    GNUNET_CRYPTO_eddsa_key_get_public (&melt_priv->eddsa_priv,
                                        &coin_pub.eddsa_pub);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &coin_pub,
                                     sizeof (struct TALER_CoinSpendPublicKeyP));
    TALER_amount_hton (&melt_amountn,
                       melt_amount);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &melt_amountn,
                                     sizeof (struct TALER_AmountNBO));

  }
  for (i = 0; i < TALER_CNC_KAPPA; i++)
  {
    for (j = 0; j < fresh_pks_len; j++)
    {
      const struct FreshCoin *fc; /* coin this is about */
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct GNUNET_HashCode coin_hash;
      char *coin_ev; /* blinded message to be signed (in envelope) for each coin */
      size_t coin_ev_size;
      struct TALER_RefreshLinkDecrypted rld;
      struct TALER_RefreshLinkEncrypted *rle;
      char *link_enc; /* encrypted link data */
      size_t link_enc_size;

      fc = &md.fresh_coins[i][j];
      GNUNET_CRYPTO_eddsa_key_get_public (&fc->coin_priv.eddsa_priv,
                                          &coin_pub.eddsa_pub);
      GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                          sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                          &coin_hash);
      coin_ev_size = GNUNET_CRYPTO_rsa_blind (&coin_hash,
                                              fc->blinding_key.rsa_blinding_key,
                                              md.fresh_pks[j].rsa_public_key,
                                              &coin_ev);
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       coin_ev,
                                       coin_ev_size);
      GNUNET_free (coin_ev);

      rld.coin_priv = fc->coin_priv;
      rld.blinding_key = fc->blinding_key;
      rle = TALER_refresh_encrypt (&rld,
                                   &md.link_secrets[i]);
      link_enc = TALER_refresh_link_encrypted_encode (rle,
                                                      &link_enc_size);

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       link_enc,
                                       link_enc_size);
      GNUNET_free (link_enc);
    }
  }
  for (i = 0; i < TALER_CNC_KAPPA; i++)
  {
    struct TALER_RefreshCommitLinkP rcl;
    struct TALER_TransferSecretP trans_sec;

    GNUNET_CRYPTO_ecdhe_key_get_public (&md.melted_coin.transfer_priv[i].ecdhe_priv,
                                        &rcl.transfer_pub.ecdhe_pub);
    TALER_link_derive_transfer_secret  (melt_priv,
                                        &md.melted_coin.transfer_priv[i],
                                        &trans_sec);
    TALER_transfer_encrypt (&md.link_secrets[i],
                            &trans_sec,
                            &rcl.shared_secret_enc);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &rcl,
                                     sizeof (struct TALER_RefreshCommitLinkP));
  }

  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &md.melt_session_hash);

  /* finally, serialize everything */
  buf = serialize_melt_data (&md,
                             res_size);
  free_melt_data (&md);
  return buf;
}


/* ********************* /refresh/melt ***************************** */


/**
 * @brief A /refresh/melt Handle
 */
struct TALER_EXCHANGE_RefreshMeltHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with refresh melt failure results.
   */
  TALER_EXCHANGE_RefreshMeltCallback melt_cb;

  /**
   * Closure for @e result_cb and @e melt_failure_cb.
   */
  void *melt_cb_cls;

  /**
   * Actual information about the melt operation.
   */
  struct MeltData *md;
};


/**
 * Verify that the signature on the "200 OK" response
 * from the exchange is valid.
 *
 * @param rmh melt handle
 * @param json json reply with the signature
 * @param[out] noreveal_index set to the noreveal index selected by the exchange
 * @return #GNUNET_OK if the signature is valid, #GNUNET_SYSERR if not
 */
static int
verify_refresh_melt_signature_ok (struct TALER_EXCHANGE_RefreshMeltHandle *rmh,
                                  const json_t *json,
                                  uint16_t *noreveal_index)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_ExchangePublicKeyP exchange_pub;
  const struct TALER_EXCHANGE_Keys *key_state;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("exchange_sig", &exchange_sig),
    GNUNET_JSON_spec_fixed_auto ("exchange_pub", &exchange_pub),
    GNUNET_JSON_spec_uint16 ("noreveal_index", noreveal_index),
    GNUNET_JSON_spec_end()
  };
  struct TALER_RefreshMeltConfirmationPS confirm;

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that exchange signing key is permitted */
  key_state = TALER_EXCHANGE_get_keys (rmh->exchange);
  if (GNUNET_OK !=
      TALER_EXCHANGE_test_signing_key (key_state,
                                   &exchange_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* check that noreveal index is in permitted range */
  if (TALER_CNC_KAPPA <= *noreveal_index)
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* verify signature by exchange */
  confirm.purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT);
  confirm.purpose.size = htonl (sizeof (struct TALER_RefreshMeltConfirmationPS));
  confirm.session_hash = rmh->md->melt_session_hash;
  confirm.noreveal_index = htons (*noreveal_index);
  confirm.reserved = htons (0);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_EXCHANGE_CONFIRM_MELT,
                                  &confirm.purpose,
                                  &exchange_sig.eddsa_signature,
                                  &exchange_pub.eddsa_pub))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Verify that the signatures on the "403 FORBIDDEN" response from the
 * exchange demonstrating customer double-spending are valid.
 *
 * @param rmh melt handle
 * @param json json reply with the signature(s) and transaction history
 * @return #GNUNET_OK if the signature(s) is valid, #GNUNET_SYSERR if not
 */
static int
verify_refresh_melt_signature_forbidden (struct TALER_EXCHANGE_RefreshMeltHandle *rmh,
                                         const json_t *json)
{
  json_t *history;
  struct TALER_Amount original_value;
  struct TALER_Amount melt_value_with_fee;
  struct TALER_Amount total;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("history", &history),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &coin_pub),
    TALER_JSON_spec_amount ("original_value", &original_value),
    TALER_JSON_spec_amount ("requested_value", &melt_value_with_fee),
    GNUNET_JSON_spec_end()
  };
  const struct MeltedCoin *mc;

  /* parse JSON reply */
  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }

  /* Find out which coin was deemed problematic by the exchange */
  mc = &rmh->md->melted_coin;

  /* check basic coin properties */
  if (0 != TALER_amount_cmp (&original_value,
                             &mc->original_value))
  {
    /* We disagree on the value of the coin */
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }
  if (0 != TALER_amount_cmp (&melt_value_with_fee,
                             &mc->melt_amount_with_fee))
  {
    /* We disagree on the value of the coin */
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }

  /* verify coin history */
  history = json_object_get (json,
                             "history");
  if (GNUNET_OK !=
      TALER_EXCHANGE_verify_coin_history (original_value.currency,
                                       &coin_pub,
                                       history,
                                       &total))
  {
    GNUNET_break_op (0);
    json_decref (history);
    return GNUNET_SYSERR;
  }
  json_decref (history);

  /* check if melt operation was really too expensive given history */
  if (GNUNET_OK !=
      TALER_amount_add (&total,
                        &total,
                        &melt_value_with_fee))
  {
    /* clearly not OK if our transaction would have caused
       the overflow... */
    return GNUNET_OK;
  }

  if (0 >= TALER_amount_cmp (&total,
                             &original_value))
  {
    /* transaction should have still fit */
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* everything OK, valid proof of double-spending was provided */
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /refresh/melt request.
 *
 * @param cls the `struct TALER_EXCHANGE_RefreshMeltHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_refresh_melt_finished (void *cls,
                              long response_code,
                              const json_t *json)
{
  struct TALER_EXCHANGE_RefreshMeltHandle *rmh = cls;
  uint16_t noreveal_index = TALER_CNC_KAPPA; /* invalid value */

  rmh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    if (GNUNET_OK !=
        verify_refresh_melt_signature_ok (rmh,
                                          json,
                                          &noreveal_index))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    if (NULL != rmh->melt_cb)
    {
      rmh->melt_cb (rmh->melt_cb_cls,
                    response_code,
                    noreveal_index,
                    json);
      rmh->melt_cb = NULL;
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Double spending; check signatures on transaction history */
    if (GNUNET_OK !=
        verify_refresh_melt_signature_forbidden (rmh,
                                                 json))
    {
      GNUNET_break_op (0);
      response_code = 0;
    }
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, exchange says one of the signatures is
       invalid; assuming we checked them, this should never happen, we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* Nothing really to verify, this should never
       happen, we should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != rmh->melt_cb)
    rmh->melt_cb (rmh->melt_cb_cls,
                  response_code,
                  UINT16_MAX,
                  json);
  TALER_EXCHANGE_refresh_melt_cancel (rmh);
}


/**
 * Convert a coin to be melted to the respective JSON encoding.
 *
 * @param melt_session_hash session hash to use
 * @param mc coin to be melted
 * @return JSON encoding of the melting request
 */
static json_t *
melted_coin_to_json (const struct GNUNET_HashCode *melt_session_hash,
                     const struct MeltedCoin *mc)
{
  struct TALER_CoinSpendSignatureP confirm_sig;
  struct TALER_RefreshMeltCoinAffirmationPS melt;

  melt.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
  melt.purpose.size = htonl (sizeof (struct TALER_RefreshMeltCoinAffirmationPS));
  melt.session_hash = *melt_session_hash;
  TALER_amount_hton (&melt.amount_with_fee,
                     &mc->melt_amount_with_fee);
  TALER_amount_hton (&melt.melt_fee,
                     &mc->fee_melt);
  GNUNET_CRYPTO_eddsa_key_get_public (&mc->coin_priv.eddsa_priv,
                                      &melt.coin_pub.eddsa_pub);
  GNUNET_CRYPTO_eddsa_sign (&mc->coin_priv.eddsa_priv,
                            &melt.purpose,
                            &confirm_sig.eddsa_signature);
  return json_pack ("{s:o, s:o, s:o, s:o, s:o}",
                    "coin_pub",
                    GNUNET_JSON_from_data (&melt.coin_pub,
                                          sizeof (melt.coin_pub)),
                    "denom_pub",
                    GNUNET_JSON_from_rsa_public_key (mc->pub_key.rsa_public_key),
                    "denom_sig",
                    GNUNET_JSON_from_rsa_signature (mc->sig.rsa_signature),
                    "confirm_sig",
                    GNUNET_JSON_from_data (&confirm_sig,
                                          sizeof (confirm_sig)),
                    "value_with_fee",
                    TALER_JSON_from_amount (&mc->melt_amount_with_fee));
}


/**
 * Submit a melt request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument should have been constructed using
 * #TALER_EXCHANGE_refresh_prepare and committed to persistent storage
 * prior to calling this function.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_EXCHANGE_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_EXCHANGE_refresh_prepare())
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_RefreshMeltHandle *
TALER_EXCHANGE_refresh_melt (struct TALER_EXCHANGE_Handle *exchange,
                             size_t refresh_data_length,
                             const char *refresh_data,
                             TALER_EXCHANGE_RefreshMeltCallback melt_cb,
                             void *melt_cb_cls)
{
  json_t *melt_obj;
  json_t *new_denoms;
  json_t *melt_coin;
  json_t *coin_evs;
  json_t *transfer_pubs;
  json_t *secret_encs;
  json_t *link_encs;
  json_t *tmp;
  struct TALER_EXCHANGE_RefreshMeltHandle *rmh;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  struct MeltData *md;
  unsigned int i;
  unsigned int j;

  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  md = deserialize_melt_data (refresh_data,
                              refresh_data_length);
  if (NULL == md)
  {
    GNUNET_break (0);
    return NULL;
  }

  /* build JSON request, each of the 6 arrays first */
  new_denoms = json_array ();
  melt_coin = melted_coin_to_json (&md->melt_session_hash,
                                   &md->melted_coin);
  coin_evs = json_array ();
  transfer_pubs = json_array ();
  secret_encs = json_array ();
  link_encs = json_array ();

  /* now transfer_pubs */
  for (j=0;j<TALER_CNC_KAPPA;j++)
  {
    const struct MeltedCoin *mc = &md->melted_coin;
    struct TALER_TransferPublicKeyP transfer_pub;

    GNUNET_CRYPTO_ecdhe_key_get_public (&mc->transfer_priv[j].ecdhe_priv,
                                        &transfer_pub.ecdhe_pub);
    json_array_append (transfer_pubs,
                       GNUNET_JSON_from_data (&transfer_pub,
                                              sizeof (transfer_pub)));
  }

  /* now secret_encs */
  for (j=0;j<TALER_CNC_KAPPA;j++)
  {
    const struct MeltedCoin *mc = &md->melted_coin;
    struct TALER_EncryptedLinkSecretP els;
    struct TALER_TransferSecretP trans_sec;

    TALER_link_derive_transfer_secret (&mc->coin_priv,
                                       &mc->transfer_priv[j],
                                       &trans_sec);
    GNUNET_assert (GNUNET_OK ==
                   TALER_transfer_encrypt (&md->link_secrets[j],
                                           &trans_sec,
                                           &els));
    json_array_append (secret_encs,
                       GNUNET_JSON_from_data (&els,
                                              sizeof (els)));
  }

  /* now new_denoms */
  for (i=0;i<md->num_fresh_coins;i++)
  {
    json_array_append (new_denoms,
                       GNUNET_JSON_from_rsa_public_key
                       (md->fresh_pks[i].rsa_public_key));
  }

  /* now link_encs */
  for (j=0;j<TALER_CNC_KAPPA;j++)
  {
    tmp = json_array ();
    for (i=0;i<md->num_fresh_coins;i++)
    {
      const struct FreshCoin *fc = &md->fresh_coins[j][i];
      struct TALER_RefreshLinkDecrypted rld;
      struct TALER_RefreshLinkEncrypted *rle;
      char *buf;
      size_t buf_len;

      rld.coin_priv = fc->coin_priv;
      rld.blinding_key = fc->blinding_key;
      rle = TALER_refresh_encrypt (&rld,
                                   &md->link_secrets[j]);
      GNUNET_assert (NULL != rle);
      buf = TALER_refresh_link_encrypted_encode (rle,
                                                 &buf_len);
      GNUNET_assert (NULL != buf);
      json_array_append (tmp,
                         GNUNET_JSON_from_data (buf,
                                               buf_len));
      GNUNET_free (buf);
      GNUNET_free (rle);
    }
    json_array_append (link_encs,
                       tmp);
  }

  /* now coin_evs */
  for (j=0;j<TALER_CNC_KAPPA;j++)
  {
    tmp = json_array ();
    for (i=0;i<md->num_fresh_coins;i++)
    {
      const struct FreshCoin *fc = &md->fresh_coins[j][i];
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct GNUNET_HashCode coin_hash;
      char *coin_ev; /* blinded message to be signed (in envelope) for each coin */
      size_t coin_ev_size;

      GNUNET_CRYPTO_eddsa_key_get_public (&fc->coin_priv.eddsa_priv,
                                          &coin_pub.eddsa_pub);
      GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                          sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                          &coin_hash);
      coin_ev_size = GNUNET_CRYPTO_rsa_blind (&coin_hash,
                                              fc->blinding_key.rsa_blinding_key,
                                              md->fresh_pks[i].rsa_public_key,
                                              &coin_ev);
      json_array_append (tmp,
                         GNUNET_JSON_from_data (coin_ev,
                                               coin_ev_size));
      GNUNET_free (coin_ev);
    }
    json_array_append (coin_evs,
                       tmp);
  }

  /* finally, assemble main JSON request from constitutent arrays */
  melt_obj = json_pack ("{s:o, s:o, s:o, s:o, s:o, s:o}",
                        "new_denoms", new_denoms,
                        "melt_coin", melt_coin,
                        "coin_evs", coin_evs,
                        "transfer_pubs", transfer_pubs,
                        "secret_encs", secret_encs,
                        "link_encs", link_encs);

  /* and now we can at last begin the actual request handling */
  rmh = GNUNET_new (struct TALER_EXCHANGE_RefreshMeltHandle);
  rmh->exchange = exchange;
  rmh->melt_cb = melt_cb;
  rmh->melt_cb_cls = melt_cb_cls;
  rmh->md = md;
  rmh->url = MAH_path_to_url (exchange,
                              "/refresh/melt");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (rmh->json_enc =
                          json_dumps (melt_obj,
                                      JSON_COMPACT)));
  json_decref (melt_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rmh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   rmh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (rmh->json_enc)));
  ctx = MAH_handle_to_context (exchange);
  rmh->job = GNUNET_CURL_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_refresh_melt_finished,
                          rmh);
  return rmh;
}


/**
 * Cancel a refresh execute request.  This function cannot be used
 * on a request handle if either callback was already invoked.
 *
 * @param rmh the refresh melt handle
 */
void
TALER_EXCHANGE_refresh_melt_cancel (struct TALER_EXCHANGE_RefreshMeltHandle *rmh)
{
  if (NULL != rmh->job)
  {
    GNUNET_CURL_job_cancel (rmh->job);
    rmh->job = NULL;
  }
  free_melt_data (rmh->md); /* does not free 'md' itself */
  GNUNET_free (rmh->md);
  GNUNET_free (rmh->url);
  GNUNET_free (rmh->json_enc);
  GNUNET_free (rmh);
}


/* ********************* /refresh/reveal ***************************** */


/**
 * @brief A /refresh/reveal Handle
 */
struct TALER_EXCHANGE_RefreshRevealHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * The url for this request.
   */
  char *url;

  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_RefreshRevealCallback reveal_cb;

  /**
   * Closure for @e reveal_cb.
   */
  void *reveal_cb_cls;

  /**
   * Actual information about the melt operation.
   */
  struct MeltData *md;

  /**
   * The index selected by the exchange in cut-and-choose to not be revealed.
   */
  uint16_t noreveal_index;

};


/**
 * We got a 200 OK response for the /refresh/reveal operation.
 * Extract the coin signatures and return them to the caller.
 * The signatures we get from the exchange is for the blinded value.
 * Thus, we first must unblind them and then should verify their
 * validity.
 *
 * If everything checks out, we return the unblinded signatures
 * to the application via the callback.
 *
 * @param rrh operation handle
 * @param json reply from the exchange
 * @param[out] coin_privs array of length `num_fresh_coins`, initialized to contain private keys
 * @param[out] sigs array of length `num_fresh_coins`, initialized to cointain RSA signatures
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on errors
 */
static int
refresh_reveal_ok (struct TALER_EXCHANGE_RefreshRevealHandle *rrh,
                   const json_t *json,
                   struct TALER_CoinSpendPrivateKeyP *coin_privs,
                   struct TALER_DenominationSignature *sigs)
{
  unsigned int i;
  json_t *jsona;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("ev_sigs", &jsona),
    GNUNET_JSON_spec_end()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (! json_is_array (jsona))
  {
    /* We expected an array of coins */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  if (rrh->md->num_fresh_coins != json_array_size (jsona))
  {
    /* Number of coins generated does not match our expectation */
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  for (i=0;i<rrh->md->num_fresh_coins;i++)
  {
    const struct FreshCoin *fc;
    struct TALER_DenominationPublicKey *pk;
    json_t *jsonai;
    struct GNUNET_CRYPTO_RsaSignature *blind_sig;
    struct GNUNET_CRYPTO_RsaSignature *sig;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct GNUNET_HashCode coin_hash;

    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_rsa_signature ("ev_sig", &blind_sig),
      GNUNET_JSON_spec_end()
    };

    fc = &rrh->md->fresh_coins[rrh->noreveal_index][i];
    pk = &rrh->md->fresh_pks[i];
    jsonai = json_array_get (jsona, i);
    GNUNET_assert (NULL != jsonai);

    if (GNUNET_OK !=
        GNUNET_JSON_parse (jsonai,
                           spec,
                           NULL, NULL))
    {
      GNUNET_break_op (0);
      return GNUNET_SYSERR;
    }

    /* unblind the signature */
    sig = GNUNET_CRYPTO_rsa_unblind (blind_sig,
                                     fc->blinding_key.rsa_blinding_key,
                                     pk->rsa_public_key);
    GNUNET_CRYPTO_rsa_signature_free (blind_sig);

    /* verify the signature */
    GNUNET_CRYPTO_eddsa_key_get_public (&fc->coin_priv.eddsa_priv,
                                        &coin_pub.eddsa_pub);
    GNUNET_CRYPTO_hash (&coin_pub.eddsa_pub,
                        sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                        &coin_hash);

    if (GNUNET_OK !=
        GNUNET_CRYPTO_rsa_verify (&coin_hash,
                                  sig,
                                  pk->rsa_public_key))
    {
      GNUNET_break_op (0);
      GNUNET_CRYPTO_rsa_signature_free (sig);
      return GNUNET_SYSERR;
    }
    coin_privs[i] = fc->coin_priv;
    sigs[i].rsa_signature = sig;
  }
  return GNUNET_OK;
}


/**
 * Function called when we're done processing the
 * HTTP /refresh/reveal request.
 *
 * @param cls the `struct TALER_EXCHANGE_RefreshHandle`
 * @param response_code HTTP response code, 0 on error
 * @param json parsed JSON result, NULL on error
 */
static void
handle_refresh_reveal_finished (void *cls,
                                long response_code,
                                const json_t *json)
{
  struct TALER_EXCHANGE_RefreshRevealHandle *rrh = cls;

  rrh->job = NULL;
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    {
      struct TALER_CoinSpendPrivateKeyP coin_privs[rrh->md->num_fresh_coins];
      struct TALER_DenominationSignature sigs[rrh->md->num_fresh_coins];
      unsigned int i;
      int ret;

      memset (sigs, 0, sizeof (sigs));
      ret = refresh_reveal_ok (rrh,
                               json,
                               coin_privs,
                               sigs);
      if (GNUNET_OK != ret)
      {
        response_code = 0;
      }
      else
      {
        rrh->reveal_cb (rrh->reveal_cb_cls,
                        MHD_HTTP_OK,
                        rrh->md->num_fresh_coins,
                        coin_privs,
                        sigs,
                        json);
        rrh->reveal_cb = NULL;
      }
      for (i=0;i<rrh->md->num_fresh_coins;i++)
        if (NULL != sigs[i].rsa_signature)
          GNUNET_CRYPTO_rsa_signature_free (sigs[i].rsa_signature);
    }
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the exchange is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify, exchange says our reveal is inconsitent
       with our commitment, so either side is buggy; we
       should pass the JSON reply to the application */
    break;
  case MHD_HTTP_INTERNAL_SERVER_ERROR:
    /* Server had an internal issue; we should retry, but this API
       leaves this to the application */
    break;
  default:
    /* unexpected response code */
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u\n",
                (unsigned int) response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != rrh->reveal_cb)
    rrh->reveal_cb (rrh->reveal_cb_cls,
                    response_code,
                    0, NULL, NULL,
                    json);
  TALER_EXCHANGE_refresh_reveal_cancel (rrh);
}


/**
 * Submit a /refresh/reval request to the exchange and get the exchange's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * arguments should have been committed to persistent storage
 * prior to calling this function.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_EXCHANGE_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_EXCHANGE_refresh_prepare())
 * @param noreveal_index response from the exchange to the
 *        #TALER_EXCHANGE_refresh_melt() invocation
 * @param reveal_cb the callback to call with the final result of the
 *        refresh operation
 * @param reveal_cb_cls closure for the above callback
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_EXCHANGE_RefreshRevealHandle *
TALER_EXCHANGE_refresh_reveal (struct TALER_EXCHANGE_Handle *exchange,
                           size_t refresh_data_length,
                           const char *refresh_data,
                           uint16_t noreveal_index,
                           TALER_EXCHANGE_RefreshRevealCallback reveal_cb,
                           void *reveal_cb_cls)
{
  struct TALER_EXCHANGE_RefreshRevealHandle *rrh;
  json_t *transfer_privs;
  json_t *reveal_obj;
  CURL *eh;
  struct GNUNET_CURL_Context *ctx;
  struct MeltData *md;
  unsigned int j;

  if (GNUNET_YES !=
      MAH_handle_is_ready (exchange))
  {
    GNUNET_break (0);
    return NULL;
  }
  md = deserialize_melt_data (refresh_data,
                              refresh_data_length);
  if (NULL == md)
  {
    GNUNET_break (0);
    return NULL;
  }
  if (noreveal_index >= TALER_CNC_KAPPA)
  {
    /* We check this here, as it would be really bad to below just
       disclose all the transfer keys. Note that this error should
       have been caught way earlier when the exchange replied, but maybe
       we had some internal corruption that changed the value... */
    GNUNET_break (0);
    return NULL;
  }

  /* build array of transfer private keys */
  transfer_privs = json_array ();
  for (j=0;j<TALER_CNC_KAPPA;j++)
  {
    if (j == noreveal_index)
    {
      /* This is crucial: exclude the transfer key for the
	 noreval index! */
      continue;
    }
    json_array_append (transfer_privs,
                       GNUNET_JSON_from_data (&md->melted_coin.transfer_priv[j],
                                              sizeof (struct TALER_TransferPrivateKeyP)));
  }

  /* build main JSON request */
  reveal_obj = json_pack ("{s:o, s:o}",
                          "session_hash",
                          GNUNET_JSON_from_data (&md->melt_session_hash,
                                                sizeof (struct GNUNET_HashCode)),
                          "transfer_privs",
                          transfer_privs);

  /* finally, we can actually issue the request */
  rrh = GNUNET_new (struct TALER_EXCHANGE_RefreshRevealHandle);
  rrh->exchange = exchange;
  rrh->noreveal_index = noreveal_index;
  rrh->reveal_cb = reveal_cb;
  rrh->reveal_cb_cls = reveal_cb_cls;
  rrh->md = md;
  rrh->url = MAH_path_to_url (rrh->exchange,
                              "/refresh/reveal");

  eh = curl_easy_init ();
  GNUNET_assert (NULL != (rrh->json_enc =
                          json_dumps (reveal_obj,
                                      JSON_COMPACT)));
  json_decref (reveal_obj);
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   rrh->url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   rrh->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   strlen (rrh->json_enc)));
  ctx = MAH_handle_to_context (rrh->exchange);
  rrh->job = GNUNET_CURL_job_add (ctx,
                          eh,
                          GNUNET_YES,
                          &handle_refresh_reveal_finished,
                          rrh);
  return rrh;
}


/**
 * Cancel a refresh reveal request.  This function cannot be used
 * on a request handle if the callback was already invoked.
 *
 * @param rrh the refresh reval handle
 */
void
TALER_EXCHANGE_refresh_reveal_cancel (struct TALER_EXCHANGE_RefreshRevealHandle *rrh)
{
  if (NULL != rrh->job)
  {
    GNUNET_CURL_job_cancel (rrh->job);
    rrh->job = NULL;
  }
  GNUNET_free (rrh->url);
  GNUNET_free (rrh->json_enc);
  free_melt_data (rrh->md); /* does not free 'md' itself */
  GNUNET_free (rrh->md);
  GNUNET_free (rrh);
}


/* end of exchange_api_refresh.c */
