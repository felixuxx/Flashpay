/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint-lib/mint_api_refresh.c
 * @brief Implementation of the /refresh/melt+reveal requests of the mint's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"
#include "mint_api_json.h"
#include "mint_api_context.h"
#include "mint_api_handle.h"
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
  struct TALER_AmountNBO fee_withdraw;

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_AbsoluteNBO deposit_valid_until;

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
   * Link secret used to encrypt the @a coin_priv and the blinding
   * key in the linkage data.
   */
  struct TALER_LinkSecretP link_secret;

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
   * Transfer secrets for each cut-and-choose dimension.
   */
  struct TALER_TransferSecretP transfer_secrets[TALER_CNC_KAPPA];

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
     2) struct TALER_MINT_DenomPublicKey fresh_pks[num_fresh_coins];
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
   * The applicable fee for withdrawing a coin of this denomination
   */
  struct TALER_Amount fee_withdraw;

  /**
   * Transfer private keys for each cut-and-choose dimension.
   */
  struct TALER_TransferPrivateKeyP transfer_priv[TALER_CNC_KAPPA];

  /**
   * Timestamp indicating when coins of this denomination become invalid.
   */
  struct GNUNET_TIME_Absolute deposit_valid_until;

  /**
   * Denomination key of the original coin.
   */
  struct TALER_DenominationPublicKey pub_key;

  /**
   * Mint's signature over the coin.
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
   * Link secret used to encrypt the @a coin_priv and the blinding
   * key in the linkage data.
   */
  struct TALER_LinkSecretP link_secret;

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
   * Transfer secrets for each cut-and-choose dimension.
   */
  struct TALER_TransferSecretP transfer_secrets[TALER_CNC_KAPPA];

  /**
   * Number of coins we are melting
   */
  uint16_t num_melted_coins;

  /**
   * Number of coins we are creating
   */
  uint16_t num_fresh_coins;

  /**
   * Information about the melted coins in an array of length @e
   * num_melted_coins.
   */
  struct MeltedCoin *melted_coins;

  /**
   * Array of @e num_fresh_coins denomination keys for the coins to be
   * freshly minted.
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
  GNUNET_CRYPTO_rsa_public_key_free (mc->pub_key.rsa_public_key);
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
  GNUNET_CRYPTO_rsa_blinding_key_free (fc->blinding_key.rsa_blinding_key);
}


/**
 * Free all information associated with a melting session.
 *
 * @param md melting data to release, the pointer itself is NOT
 *           freed (as it is typically not allocated by itself)
 */
static void
free_melt_data (struct MeltData *md)
{
  unsigned int i;
  unsigned int j;

  for (i=0;i<md->num_melted_coins;i++)
    free_melted_coin (&md->melted_coins[i]);
  GNUNET_free (md->melted_coins);

  for (i=0;i<md->num_fresh_coins;i++)
    GNUNET_CRYPTO_rsa_public_key_free (md->fresh_pks[i].rsa_public_key);
  GNUNET_free (md->fresh_pks);

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
 *        @a buf is NULL, number of bytes required
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

  mcp.coin_priv = mc->coin_priv;
  TALER_amount_hton (&mcp.melt_amount_with_fee,
                     &mc->melt_amount_with_fee);

  TALER_amount_hton (&mcp.fee_withdraw,
                     &mc->fee_withdraw);
  for (i=0;i<TALER_CNC_KAPPA;i++)
    mcp.transfer_priv[i] = mc->transfer_priv[i];
  mcp.deposit_valid_until = GNUNET_TIME_absolute_hton (mc->deposit_valid_until);

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

  pbuf_size = GNUNET_CRYPTO_rsa_public_key_encode (dk->rsa_public_key,
                                                   &pbuf);
  if (NULL == buf)
  {
    GNUNET_free (pbuf);
    return pbuf_size;
  }

  memcpy (&buf[off],
          pbuf,
          pbuf_size);
  GNUNET_free (pbuf);
  return pbuf_size;
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
  fcp.link_secret = fc->link_secret;
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
        mdp->transfer_secrets[i] = md->transfer_secrets[i];
      mdp->num_melted_coins = htons (md->num_melted_coins);
      mdp->num_fresh_coins = htons (md->num_fresh_coins);
    }
    for (i=0;i<md->num_melted_coins;i++)
      size += serialize_melted_coin (&md->melted_coins[i],
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
  GNUNET_break (0); // FIXME: not implemented
  return NULL;
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
 * to #TALER_MINT_refresh_execute() that will generate the request.
 *
 * This function does verify that the given request data is internally
 * consistent.  However, the @a melts_sigs are only verified if @a
 * check_sigs is set to #GNUNET_YES, as this may be relatively
 * expensive and should be redundant.
 *
 * Aside from some non-trivial cryptographic operations that might
 * take a bit of CPU time to complete, this function returns
 * its result immediately and does not start any asynchronous
 * processing.  This function is also thread-safe.
 *
 * @param num_melts number of coins that are being melted (typically 1)
 * @param melt_privs array of @a num_melts private keys of the coins to melt
 * @param melt_amounts array of @a num_melts amounts specifying how much
 *                     each coin will contribute to the melt (including fee)
 * @param melt_sigs array of @a num_melts signatures affirming the
 *                   validity of the public keys corresponding to the
 *                   @a melt_privs private keys
 * @param melt_pks array of @a num_melts denomination key information
 *                   records corresponding to the @a melt_sigs
 *                   validity of the keys
 * @param check_sigs verify the validity of the signatures of @a melt_sigs
 * @param fresh_pks_len length of the @a pks array
 * @param fresh_pks array of @a pks_len denominations of fresh coins to create
 * @param[OUT] res_size set to the size of the return value, or 0 on error
 * @return NULL
 *         if the inputs are invalid (i.e. denomination key not with this mint).
 *         Otherwise, pointer to a buffer of @a res_size to store persistently
 *         before proceeding to #TALER_MINT_refresh_execute().
 *         Non-null results should be freed using #GNUNET_free().
 */
char *
TALER_MINT_refresh_prepare (unsigned int num_melts,
                            const struct TALER_CoinSpendPrivateKeyP *melt_privs,
                            const struct TALER_Amount *melt_amounts,
                            const struct TALER_DenominationSignature *melt_sigs,
                            const struct TALER_MINT_DenomPublicKey *melt_pks,
                            int check_sigs,
                            unsigned int fresh_pks_len,
                            const struct TALER_MINT_DenomPublicKey *fresh_pks,
                            size_t *res_size)
{
  struct MeltData md;
  char *buf;

  GNUNET_break (0); // FIXME: not implemented
  // FIXME: init 'md' here!

  buf = serialize_melt_data (&md,
                             res_size);
  free_melt_data (&md);
  return buf;
}


/* ********************* /refresh/melt ***************************** */


/**
 * @brief A /refresh/melt Handle
 */
struct TALER_MINT_RefreshMeltHandle
{

  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

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
  struct MAC_Job *job;

  /**
   * Function to call with refresh melt failure results.
   */
  TALER_MINT_RefreshMeltCallback melt_cb;

  /**
   * Closure for @e result_cb and @e melt_failure_cb.
   */
  void *melt_cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

  /**
   * Actual information about the melt operation.
   */
  struct MeltData *md;
};


/**
 * Function called when we're done processing the
 * HTTP /refresh/melt request.
 *
 * @param cls the `struct TALER_MINT_RefreshMeltHandle`
 * @param eh the curl request handle
 */
static void
handle_refresh_melt_finished (void *cls,
                              CURL *eh)
{
  struct TALER_MINT_RefreshMeltHandle *rmh = cls;
  long response_code;
  json_t *json;

  rmh->job = NULL;
  json = MAC_download_get_result (&rmh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME: NOT implemented! (parse, check sig!)

    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_FORBIDDEN:
    /* Double spending; check signatures on transaction history */
    GNUNET_break (0); // FIXME: NOT implemented!
    break;
  case MHD_HTTP_UNAUTHORIZED:
    /* Nothing really to verify, mint says one of the signatures is
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
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != rmh->melt_cb)
    rmh->melt_cb (rmh->melt_cb_cls,
                  response_code,
                  UINT16_MAX,
                  json);
  json_decref (json);
  TALER_MINT_refresh_melt_cancel (rmh);
}


/**
 * Submit a melt request to the mint and get the mint's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * argument should have been constructed using
 * #TALER_MINT_refresh_prepare and committed to persistent storage
 * prior to calling this function.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_MINT_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_MINT_refresh_prepare())
 * @param melt_cb the callback to call with the result
 * @param melt_cb_cls closure for @a melt_cb
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_MINT_RefreshMeltHandle *
TALER_MINT_refresh_melt (struct TALER_MINT_Handle *mint,
                         size_t refresh_data_length,
                         const char *refresh_data,
                         TALER_MINT_RefreshMeltCallback melt_cb,
                         void *melt_cb_cls)
{
  json_t *melt_obj;
  struct TALER_MINT_RefreshMeltHandle *rmh;
  CURL *eh;
  struct TALER_MINT_Context *ctx;
  struct MeltData *md;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
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

  /* FIXME: totally bogus request building here: */
  melt_obj = json_pack ("{s:o, s:O}", /* f/wire */
                        "4", 42,
                        "6", 62);


  rmh = GNUNET_new (struct TALER_MINT_RefreshMeltHandle);
  rmh->mint = mint;
  rmh->melt_cb = melt_cb;
  rmh->melt_cb_cls = melt_cb_cls;
  rmh->md = md;
  rmh->url = MAH_path_to_url (mint,
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
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &rmh->db));
  ctx = MAH_handle_to_context (mint);
  rmh->job = MAC_job_add (ctx,
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
TALER_MINT_refresh_melt_cancel (struct TALER_MINT_RefreshMeltHandle *rmh)
{
  if (NULL != rmh->job)
  {
    MAC_job_cancel (rmh->job);
    rmh->job = NULL;
  }
  GNUNET_free_non_null (rmh->db.buf);
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
struct TALER_MINT_RefreshRevealHandle
{

  /**
   * The connection to mint this request handle will use
   */
  struct TALER_MINT_Handle *mint;

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
  struct MAC_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_MINT_RefreshRevealCallback reveal_cb;

  /**
   * Closure for @e reveal_cb.
   */
  void *reveal_cb_cls;

  /**
   * Download buffer
   */
  struct MAC_DownloadBuffer db;

  /**
   * Actual information about the melt operation.
   */
  struct MeltData *md;

};


/**
 * Function called when we're done processing the
 * HTTP /refresh/reveal request.
 *
 * @param cls the `struct TALER_MINT_RefreshHandle`
 * @param eh the curl request handle
 */
static void
handle_refresh_reveal_finished (void *cls,
                                CURL *eh)
{
  struct TALER_MINT_RefreshRevealHandle *rrh = cls;
  long response_code;
  json_t *json;

  rrh->job = NULL;
  json = MAC_download_get_result (&rrh->db,
                                  eh,
                                  &response_code);
  switch (response_code)
  {
  case 0:
    break;
  case MHD_HTTP_OK:
    GNUNET_break (0); // FIXME: NOT implemented!
    // rrh->reveal_cb = NULL; (call with real result, do not call again below)
    break;
  case MHD_HTTP_BAD_REQUEST:
    /* This should never happen, either us or the mint is buggy
       (or API version conflict); just pass JSON reply to the application */
    break;
  case MHD_HTTP_CONFLICT:
    /* Nothing really to verify, mint says our reveal is inconsitent
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
                response_code);
    GNUNET_break (0);
    response_code = 0;
    break;
  }
  if (NULL != rrh->reveal_cb)
    rrh->reveal_cb (rrh->reveal_cb_cls,
                    response_code,
                    0, NULL, NULL,
                    json);
  json_decref (json);
  TALER_MINT_refresh_reveal_cancel (rrh);
}



/**
 * Submit a /refresh/reval request to the mint and get the mint's
 * response.
 *
 * This API is typically used by a wallet.  Note that to ensure that
 * no money is lost in case of hardware failures, the provided
 * arguments should have been committed to persistent storage
 * prior to calling this function.
 *
 * @param mint the mint handle; the mint must be ready to operate
 * @param refresh_data_length size of the @a refresh_data (returned
 *        in the `res_size` argument from #TALER_MINT_refresh_prepare())
 * @param refresh_data the refresh data as returned from
          #TALER_MINT_refresh_prepare())
 * @param noreveal_index response from the mint to the
 *        #TALER_MINT_refresh_melt() invocation
 * @param reveal_cb the callback to call with the final result of the
 *        refresh operation
 * @param reveal_cb_cls closure for the above callback
 * @return a handle for this request; NULL if the argument was invalid.
 *         In this case, neither callback will be called.
 */
struct TALER_MINT_RefreshRevealHandle *
TALER_MINT_refresh_reveal (struct TALER_MINT_Handle *mint,
                           size_t refresh_data_length,
                           const char *refresh_data,
                           uint16_t noreveal_index,
                           TALER_MINT_RefreshRevealCallback reveal_cb,
                           void *reveal_cb_cls)
{
  struct TALER_MINT_RefreshRevealHandle *rrh;
  json_t *reveal_obj;
  CURL *eh;
  struct TALER_MINT_Context *ctx;
  struct MeltData *md;

  if (GNUNET_YES !=
      MAH_handle_is_ready (mint))
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

  /* FIXME: totally bogus request building here: */
  reveal_obj = json_pack ("{s:o, s:O}", /* f/wire */
                          "4", 42,
                          "6", 62);

  rrh = GNUNET_new (struct TALER_MINT_RefreshRevealHandle);
  rrh->mint = mint;
  rrh->reveal_cb = reveal_cb;
  rrh->reveal_cb_cls = reveal_cb_cls;
  rrh->md = md;
  rrh->url = MAH_path_to_url (rrh->mint,
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
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEFUNCTION,
                                   &MAC_download_cb));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_WRITEDATA,
                                   &rrh->db));
  ctx = MAH_handle_to_context (rrh->mint);
  rrh->job = MAC_job_add (ctx,
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
TALER_MINT_refresh_reveal_cancel (struct TALER_MINT_RefreshRevealHandle *rrh)
{
  if (NULL != rrh->job)
  {
    MAC_job_cancel (rrh->job);
    rrh->job = NULL;
  }
  GNUNET_free_non_null (rrh->db.buf);
  GNUNET_free (rrh->url);
  GNUNET_free (rrh->json_enc);
  free_melt_data (rrh->md); /* does not free 'md' itself */
  GNUNET_free (rrh->md);
  GNUNET_free (rrh);
}


/* end of mint_api_refresh.c */
