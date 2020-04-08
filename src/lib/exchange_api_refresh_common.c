/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_refresh_common.c
 * @brief Serialization logic shared between melt and reveal steps during refreshing
 * @author Christian Grothoff
 */
#include "platform.h"
#include "exchange_api_refresh_common.h"


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
 * Free all information associated with a melting session.  Note
 * that we allow the melting session to be only partially initialized,
 * as we use this function also when freeing melt data that was not
 * fully initialized (i.e. due to failures in #TALER_EXCHANGE_deserialize_melt_data_()).
 *
 * @param md melting data to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
void
TALER_EXCHANGE_free_melt_data_ (struct MeltData *md)
{
  free_melted_coin (&md->melted_coin);
  if (NULL != md->fresh_pks)
  {
    for (unsigned int i = 0; i<md->num_fresh_coins; i++)
      if (NULL != md->fresh_pks[i].rsa_public_key)
        GNUNET_CRYPTO_rsa_public_key_free (md->fresh_pks[i].rsa_public_key);
    GNUNET_free (md->fresh_pks);
  }

  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    GNUNET_free_non_null (md->fresh_coins[i]);
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
  void *pbuf;
  size_t pbuf_size;
  void *sbuf;
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
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
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
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
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
  void *pbuf;
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
serialize_fresh_coin (const struct TALER_PlanchetSecretsP *fc,
                      char *buf,
                      size_t off)
{
  if (NULL != buf)
    memcpy (&buf[off],
            fc,
            sizeof (struct TALER_PlanchetSecretsP));
  return sizeof (struct TALER_PlanchetSecretsP);
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
deserialize_fresh_coin (struct TALER_PlanchetSecretsP *fc,
                        const char *buf,
                        size_t size,
                        int *ok)
{
  if (size < sizeof (struct TALER_PlanchetSecretsP))
  {
    GNUNET_break (0);
    *ok = GNUNET_NO;
    return 0;
  }
  memcpy (fc,
          buf,
          sizeof (struct TALER_PlanchetSecretsP));
  return sizeof (struct TALER_PlanchetSecretsP);
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
      mdp->rc = md->rc;
      mdp->num_fresh_coins = htons (md->num_fresh_coins);
    }
    size += serialize_melted_coin (&md->melted_coin,
                                   buf,
                                   size);
    for (unsigned int i = 0; i<md->num_fresh_coins; i++)
      size += serialize_denomination_key (&md->fresh_pks[i],
                                          buf,
                                          size);
    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
      for (unsigned int j = 0; j<md->num_fresh_coins; j++)
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
struct MeltData *
TALER_EXCHANGE_deserialize_melt_data_ (const char *buf,
                                       size_t buf_size)
{
  struct MeltData *md;
  struct MeltDataP mdp;
  size_t off;
  int ok;

  if (buf_size < sizeof (struct MeltDataP))
    return NULL;
  memcpy (&mdp,
          buf,
          sizeof (struct MeltDataP));
  md = GNUNET_new (struct MeltData);
  md->rc = mdp.rc;
  md->num_fresh_coins = ntohs (mdp.num_fresh_coins);
  md->fresh_pks = GNUNET_new_array (md->num_fresh_coins,
                                    struct TALER_DenominationPublicKey);
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    md->fresh_coins[i] = GNUNET_new_array (md->num_fresh_coins,
                                           struct TALER_PlanchetSecretsP);
  off = sizeof (struct MeltDataP);
  ok = GNUNET_YES;
  off += deserialize_melted_coin (&md->melted_coin,
                                  &buf[off],
                                  buf_size - off,
                                  &ok);
  for (unsigned int i = 0; (i<md->num_fresh_coins) && (GNUNET_YES == ok); i++)
    off += deserialize_denomination_key (&md->fresh_pks[i],
                                         &buf[off],
                                         buf_size - off,
                                         &ok);

  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    for (unsigned int j = 0; (j<md->num_fresh_coins) && (GNUNET_YES == ok); j++)
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
    TALER_EXCHANGE_free_melt_data_ (md);
    GNUNET_free (md);
    return NULL;
  }
  return md;
}


/**
 * Melt (partially spent) coins to obtain fresh coins that are
 * unlinkable to the original coin(s).  Note that melting more
 * than one coin in a single request will make those coins linkable,
 * so the safest operation only melts one coin at a time.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, this operation does
 * not actually initiate the request. Instead, it generates a buffer
 * which the caller must store before proceeding with the actual call
 * to #TALER_EXCHANGE_melt() that will generate the request.
 *
 * This function does verify that the given request data is internally
 * consistent.  However, the @a melts_sigs are NOT verified.
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
 * @param fresh_pks_len length of the @a pks array
 * @param fresh_pks array of @a pks_len denominations of fresh coins to create
 * @param[out] res_size set to the size of the return value, or 0 on error
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         Otherwise, pointer to a buffer of @a res_size to store persistently
 *         before proceeding to #TALER_EXCHANGE_melt().
 *         Non-null results should be freed using GNUNET_free().
 */
char *
TALER_EXCHANGE_refresh_prepare (
  const struct TALER_CoinSpendPrivateKeyP *melt_priv,
  const struct TALER_Amount *melt_amount,
  const struct TALER_DenominationSignature *melt_sig,
  const struct TALER_EXCHANGE_DenomPublicKey *melt_pk,
  unsigned int fresh_pks_len,
  const struct TALER_EXCHANGE_DenomPublicKey *fresh_pks,
  size_t *res_size)
{
  struct MeltData md;
  char *buf;
  struct TALER_Amount total;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  struct TALER_TransferSecretP trans_sec[TALER_CNC_KAPPA];
  struct TALER_RefreshCommitmentEntry rce[TALER_CNC_KAPPA];

  GNUNET_CRYPTO_eddsa_key_get_public (&melt_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);
  /* build up melt data structure */
  memset (&md, 0, sizeof (md));
  md.num_fresh_coins = fresh_pks_len;
  md.melted_coin.coin_priv = *melt_priv;
  md.melted_coin.melt_amount_with_fee = *melt_amount;
  md.melted_coin.fee_melt = melt_pk->fee_refresh;
  md.melted_coin.original_value = melt_pk->value;
  md.melted_coin.expire_deposit
    = melt_pk->expire_deposit;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (melt_amount->currency,
                                        &total));
  md.melted_coin.pub_key.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (melt_pk->key.rsa_public_key);
  md.melted_coin.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_signature_dup (melt_sig->rsa_signature);
  md.fresh_pks = GNUNET_new_array (fresh_pks_len,
                                   struct TALER_DenominationPublicKey);
  for (unsigned int i = 0; i<fresh_pks_len; i++)
  {
    md.fresh_pks[i].rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_dup (fresh_pks[i].key.rsa_public_key);
    if ( (0 >
          TALER_amount_add (&total,
                            &total,
                            &fresh_pks[i].value)) ||
         (0 >
          TALER_amount_add (&total,
                            &total,
                            &fresh_pks[i].fee_withdraw)) )
    {
      GNUNET_break (0);
      TALER_EXCHANGE_free_melt_data_ (&md);
      return NULL;
    }
  }
  /* verify that melt_amount is above total cost */
  if (1 ==
      TALER_amount_cmp (&total,
                        melt_amount) )
  {
    /* Eh, this operation is more expensive than the
       @a melt_amount. This is not OK. */
    GNUNET_break (0);
    TALER_EXCHANGE_free_melt_data_ (&md);
    return NULL;
  }

  /* build up coins */
  for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
  {
    struct GNUNET_CRYPTO_EcdhePrivateKey *tpk;

    tpk = GNUNET_CRYPTO_ecdhe_key_create ();
    md.melted_coin.transfer_priv[i].ecdhe_priv = *tpk;
    GNUNET_free (tpk);

    GNUNET_CRYPTO_ecdhe_key_get_public (
      &md.melted_coin.transfer_priv[i].ecdhe_priv,
      &rce[i].transfer_pub.ecdhe_pub);
    TALER_link_derive_transfer_secret  (melt_priv,
                                        &md.melted_coin.transfer_priv[i],
                                        &trans_sec[i]);
    md.fresh_coins[i] = GNUNET_new_array (fresh_pks_len,
                                          struct TALER_PlanchetSecretsP);
    rce[i].new_coins = GNUNET_new_array (fresh_pks_len,
                                         struct TALER_RefreshCoinData);
    for (unsigned int j = 0; j<fresh_pks_len; j++)
    {
      struct TALER_PlanchetSecretsP *fc = &md.fresh_coins[i][j];
      struct TALER_RefreshCoinData *rcd = &rce[i].new_coins[j];
      struct TALER_PlanchetDetail pd;

      TALER_planchet_setup_refresh (&trans_sec[i],
                                    j,
                                    fc);
      if (GNUNET_OK !=
          TALER_planchet_prepare (&md.fresh_pks[j],
                                  fc,
                                  &pd))
      {
        GNUNET_break_op (0);
        TALER_EXCHANGE_free_melt_data_ (&md);
        return NULL;
      }
      rcd->dk = &md.fresh_pks[j];
      rcd->coin_ev = pd.coin_ev;
      rcd->coin_ev_size = pd.coin_ev_size;
    }
  }

  /* Compute refresh commitment */
  TALER_refresh_get_commitment (&md.rc,
                                TALER_CNC_KAPPA,
                                fresh_pks_len,
                                rce,
                                &coin_pub,
                                melt_amount);
  /* finally, serialize everything */
  buf = serialize_melt_data (&md,
                             res_size);
  for (unsigned int i = 0; i < TALER_CNC_KAPPA; i++)
  {
    for (unsigned int j = 0; j < fresh_pks_len; j++)
      GNUNET_free_non_null (rce[i].new_coins[j].coin_ev);
    GNUNET_free_non_null (rce[i].new_coins);
  }
  TALER_EXCHANGE_free_melt_data_ (&md);
  return buf;
}
