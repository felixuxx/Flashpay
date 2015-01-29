/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_refresh.c
 * @brief Handle /refresh/ requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <libpq-fe.h>
#include <pthread.h>
#include "mint.h"
#include "mint_db.h"
#include "taler_signatures.h"
#include "taler_util.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_mhd.h"
#include "taler-mint-httpd_refresh.h"
#include "taler-mint-httpd_responses.h"
#include "taler-mint-httpd_keystate.h"


/**
 * Verify a signature that is encoded in a JSON object.  Extracts
 * the signature and its associated purpose and checks that it
 * matches the specified @a purpose and @a pub public key.  Any
 * errors are reported via appropriate response messages.
 *
 * @param connection the connection to send errors to
 * @param json_sig the JSON object with the signature
 * @param the public key that the signature was created with
 * @param purpose the signed message
 * @return #GNUNET_YES if the signature was valid
 *         #GNUNET_NO if the signature was invalid
 *         #GNUNET_SYSERR on internal error
 */
static int
request_json_check_signature (struct MHD_Connection *connection,
                              const json_t *json_sig,
                              const struct GNUNET_CRYPTO_EddsaPublicKey *pub,
                              const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose)
{
  struct GNUNET_CRYPTO_EddsaSignature signature;
  int size;
  uint32_t purpose_num;
  int res;
  json_t *el;

  /* TODO: use specification array to simplify the parsing! */
  res = GNUNET_MINT_parse_navigate_json (connection,
                                         json_sig,
                                         JNAV_FIELD,
                                         "sig",
                                         JNAV_RET_DATA,
                                         &signature,
                                         sizeof (struct GNUNET_CRYPTO_EddsaSignature));

  if (GNUNET_OK != res)
    return res;

  res = GNUNET_MINT_parse_navigate_json (connection,
                                         json_sig,
                                         JNAV_FIELD,
                                         "purpose",
                                         JNAV_RET_TYPED_JSON,
                                         JSON_INTEGER,
                                         &el);

  if (GNUNET_OK != res)
    return res;

  purpose_num = json_integer_value (el);

  if (purpose_num != ntohl (purpose->purpose))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "signature invalid (purpose wrong)\n");
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error", "signature invalid (purpose)");
  }

  res = GNUNET_MINT_parse_navigate_json (connection,
                                         json_sig,
                                         JNAV_FIELD, "size",
                                         JNAV_RET_TYPED_JSON,
                                         JSON_INTEGER,
                                         &el);

  if (GNUNET_OK != res)
    return res;

  size = json_integer_value (el);

  if (size != ntohl (purpose->size))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "signature invalid (size wrong)\n");
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       GNUNET_NO, GNUNET_SYSERR,
                                       "{s:s}",
                                       "error",
                                       "signature invalid (size)");
  }

  if (GNUNET_OK != GNUNET_CRYPTO_eddsa_verify (purpose_num,
                                               purpose,
                                               &signature,
                                               pub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "signature invalid (did not verify)\n");
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       "{s:s}",
                                       "error",
                                       "invalid signature (verification)");
  }

  return GNUNET_OK;
}


/**
 * Handle a "/refresh/melt" request after the main JSON parsing has happened.
 * We now need to validate the coins being melted and the session signature
 * and then hand things of to execute the melt operation.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the melt operation
 * @param new_denoms array of denomination keys
 * @param melt_coins array of coins to melt
 * @param melt_sig_json signature affirming the melt operation
 * @return MHD result code
 */
static int
handle_refresh_melt_binary (struct MHD_Connection *connection,
                            const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                            unsigned int num_new_denoms,
                            struct GNUNET_CRYPTO_rsa_PublicKey *const*denom_pubs,
                            unsigned int coin_count,
                            struct TALER_CoinPublicInfo *coin_public_infos,
                            const json_t *melt_sig_json)
{
  int res;
  unsigned int i;
  struct GNUNET_HashContext *hash_context;
  struct GNUNET_HashCode melt_hash;
  struct RefreshMeltSignatureBody body;
  char *buf;
  size_t buf_size;

  /* check that signature from the session public key is ok */
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  for (i = 0; i < num_new_denoms; i++)
  {
    buf_size = GNUNET_CRYPTO_rsa_public_key_encode (denom_pubs[i],
                                                    &buf);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     buf,
                                     buf_size);
    GNUNET_free (buf);
  }
  for (i = 0; i < coin_count; i++)
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &coin_public_infos[i].coin_pub,
                                     sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &melt_hash);

  body.melt_hash = melt_hash;
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_MELT);
  body.purpose.size = htonl (sizeof (struct RefreshMeltSignatureBody));

  if (GNUNET_OK !=
      (res = request_json_check_signature (connection,
                                           melt_sig_json,
                                           refresh_session_pub,
                                           &body.purpose)))
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

  return TALER_MINT_db_execute_refresh_melt (connection,
                                             refresh_session_pub,
                                             num_new_denoms,
                                             denom_pubs,
                                             coin_count,
                                             coin_public_infos);
}


/**
 * Extract public coin information from a JSON object and verify
 * that the signature shows that this coin is to be melted into
 * the given @a session_pub melting session, and that this is
 * a valid coin (we know the denomination key and the signature
 * on it is valid).  Essentially, this does all of the per-coin
 * checks that can be done before the transaction starts.
 *
 * @param connection the connection to send error responses to
 * @param session_pub public key of the session the coin is melted into
 * @param coin_info the JSON object to extract the coin info from
 * @param r_public_info[OUT] set to the coin's public information
 * @return #GNUNET_YES if coin public info in JSON was valid
 *         #GNUNET_NO JSON was invalid, response was generated
 *         #GNUNET_SYSERR on internal error
 */
static int
get_and_verify_coin_public_info (struct MHD_Connection *connection,
                                 const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub,
                                 json_t *coin_info,
                                 struct TALER_CoinPublicInfo *r_public_info)
{
  int ret;
  struct GNUNET_CRYPTO_EcdsaSignature melt_sig;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct GNUNET_CRYPTO_rsa_PublicKey *pk;
  struct RefreshMeltConfirmSignRequestBody body;
  struct MintKeyState *key_state;
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct GNUNET_MINT_ParseFieldSpec spec[] = {
    TALER_MINT_PARSE_FIXED ("coin_pub", &r_public_info->coin_pub),
    TALER_MINT_PARSE_RSA_SIGNATURE ("denom_sig", &sig),
    TALER_MINT_PARSE_RSA_PUBLIC_KEY ("denom_pub", &pk),
    TALER_MINT_PARSE_FIXED ("confirm_sig", &melt_sig),
    TALER_MINT_PARSE_END
  };

  ret = TALER_MINT_parse_json_data (connection,
                                    coin_info,
                                    spec);
  if (GNUNET_OK != ret)
    return ret;
  /* TODO: include amount of coin value to be melted here!? */
  body.purpose.size = htonl (sizeof (struct RefreshMeltConfirmSignRequestBody));
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_MELT_CONFIRM);
  body.session_pub = *session_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdsa_verify (TALER_SIGNATURE_REFRESH_MELT_CONFIRM,
                                  &body.purpose,
                                  &melt_sig,
                                  &r_public_info->coin_pub))
  {
    TALER_MINT_release_parsed_data (spec);
    if (MHD_YES !=
        TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_UNAUTHORIZED,
                                    "{s:s}",
                                    "error", "signature invalid"))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  key_state = TALER_MINT_key_state_acquire ();
  dki = TALER_MINT_get_denom_key (key_state,
                                  pk);
  /* FIXME: need to check if denomination key is still
     valid for issuing! (#3634) */
  if (NULL == dki)
  {
    TALER_MINT_key_state_release (key_state);
    LOG_WARNING ("Unknown denomination key in /refresh/melt request\n");
    return TALER_MINT_reply_arg_invalid (connection,
                                         "denom_pub");
  }
  TALER_MINT_key_state_release (key_state);

  /* check mint signature on the coin */
  r_public_info->denom_sig = sig;
  r_public_info->denom_pub = pk;
  if (GNUNET_OK !=
      TALER_test_coin_valid (r_public_info))
  {
    TALER_MINT_release_parsed_data (spec);
    r_public_info->denom_sig = NULL;
    r_public_info->denom_pub = NULL;
    return (MHD_YES ==
            TALER_MINT_reply_json_pack (connection,
                                        MHD_HTTP_NOT_FOUND,
                                        "{s:s}",
                                        "error", "coin invalid"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Handle a "/refresh/melt" request after the first parsing has happened.
 * We now need to validate the coins being melted and the session signature
 * and then hand things of to execute the melt operation.  This function
 * parses the JSON arrays and then passes processing on to
 * #handle_refresh_melt_binary().
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the melt operation
 * @param new_denoms array of denomination keys
 * @param melt_coins array of coins to melt
 * @param melt_sig_json signature affirming the melt operation
 * @return MHD result code
 */
static int
handle_refresh_melt_json (struct MHD_Connection *connection,
                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                          const json_t *new_denoms,
                          const json_t *melt_coins,
                          const json_t *melt_sig_json)
{
  int res;
  unsigned int i;
  unsigned int j;
  struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs;
  unsigned int num_new_denoms;
  struct TALER_CoinPublicInfo *coin_public_infos;
  unsigned int coin_count;

  num_new_denoms = json_array_size (new_denoms);
  denom_pubs = GNUNET_malloc (num_new_denoms *
                              sizeof (struct GNUNET_CRYPTO_rsa_PublicKey *));
  for (i=0;i<num_new_denoms;i++)
  {
    res = GNUNET_MINT_parse_navigate_json (connection, new_denoms,
                                           JNAV_INDEX, (int) i,
                                           JNAV_RET_RSA_PUBLIC_KEY, &denom_pubs[i]);
    if (GNUNET_OK != res)
    {
      for (j=0;j<i;j++)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
      GNUNET_free (denom_pubs);
      return res;
    }
  }

  coin_count = json_array_size (melt_coins);
  coin_public_infos = GNUNET_malloc (coin_count *
                                     sizeof (struct TALER_CoinPublicInfo));
  for (i=0;i<coin_count;i++)
  {
    /* decode JSON data on coin to melt */
    res = get_and_verify_coin_public_info (connection,
                                           refresh_session_pub,
                                           json_array_get (melt_coins, i),
                                           &coin_public_infos[i]);
    if (GNUNET_OK != res)
    {
      for (j=0;j<i;j++)
      {
        GNUNET_CRYPTO_rsa_public_key_free (coin_public_infos[j].denom_pub);
        GNUNET_CRYPTO_rsa_signature_free (coin_public_infos[j].denom_sig);
      }
      GNUNET_free (coin_public_infos);
      for (j=0;j<num_new_denoms;j++)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
      GNUNET_free (denom_pubs);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
  }

  res = handle_refresh_melt_binary (connection,
                                    refresh_session_pub,
                                    num_new_denoms,
                                    denom_pubs,
                                    coin_count,
                                    coin_public_infos,
                                    melt_sig_json);
  for (j=0;j<coin_count;j++)
  {
    GNUNET_CRYPTO_rsa_public_key_free (coin_public_infos[j].denom_pub);
    GNUNET_CRYPTO_rsa_signature_free (coin_public_infos[j].denom_sig);
  }
  GNUNET_free (coin_public_infos);
  for (j=0;j<num_new_denoms;j++)
  {
    GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j]);
  }
  GNUNET_free (denom_pubs);
  return res;
}


/**
 * Handle a "/refresh/melt" request.  Parses the request into the JSON
 * components and then hands things of to #handle_referesh_melt_json()
 * to validate the melted coins, the signature and execute the melt
 * using TALER_MINT_db_execute_refresh_melt().
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_refresh_melt (struct RequestHandler *rh,
                                 struct MHD_Connection *connection,
                                 void **connection_cls,
                                 const char *upload_data,
                                 size_t *upload_data_size)
{
  json_t *root;
  json_t *new_denoms;
  json_t *melt_coins;
  json_t *melt_sig_json;
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;
  int res;
  struct GNUNET_MINT_ParseFieldSpec spec[] = {
    TALER_MINT_PARSE_FIXED ("session_pub", &refresh_session_pub),
    TALER_MINT_PARSE_ARRAY ("new_denoms", &new_denoms),
    TALER_MINT_PARSE_ARRAY ("melt_coins", &melt_coins),
    TALER_MINT_PARSE_ARRAY ("melt_signature", &melt_sig_json),
    TALER_MINT_PARSE_END
  };

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;

  res = TALER_MINT_parse_json_data (connection,
                                    root,
                                    spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  res = handle_refresh_melt_json (connection,
                                  &refresh_session_pub,
                                  new_denoms,
                                  melt_coins,
                                  melt_sig_json);
  TALER_MINT_release_parsed_data (spec);
  return res;
}


/**
 * Release memory from the @a commit_coin array.
 *
 * @param commit_coin array to release
 * @param kappa size of 1st dimension
 * @param num_new_coins size of 2nd dimension
 */
static void
free_commit_coins (struct RefreshCommitCoin **commit_coin,
                   unsigned int kappa,
                   unsigned int num_new_coins)
{
  unsigned int i;
  unsigned int j;

  for (i=0;i<kappa;i++)
  {
    if (NULL == commit_coin[i])
      break;
    for (j=0;j<num_new_coins;j++)
    {
      GNUNET_free_non_null (commit_coin[i][j].coin_ev);
      GNUNET_free_non_null (commit_coin[i][j].refresh_link);
    }
    GNUNET_free (commit_coin[i]);
  }
}


/**
 * Release memory from the @a commit_link array.
 *
 * @param commit_coin array to release
 * @param kappa size of 1st dimension
 * @param num_old_coins size of 2nd dimension
 */
static void
free_commit_links (struct RefreshCommitLink **commit_link,
                   unsigned int kappa,
                   unsigned int num_old_coins)
{
  unsigned int i;

  for (i=0;i<kappa;i++)
  {
    if (NULL == commit_link[i])
      break;
    GNUNET_free (commit_link[i]);
  }
}



/**
 * Handle a "/refresh/commit" request.  We have the individual JSON
 * arrays, now we need to parse their contents and verify the
 * commit signature.  Then we can commit the data to the database.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the refresh session
 * @param commit_signature signature over the commit
 * @param kappa security parameter for cut and choose
 * @param num_oldcoins number of coins that are being melted
 * @param transfer_pubs @a kappa-dimensional array of @a num_oldcoins transfer keys
 * @param secret_encs @a kappa-dimensional array of @a num_oldcoins secrets
 * @param num_newcoins number of coins that the refresh will generate
 * @param coin_envs @a kappa-dimensional array of @a num_newcoins envelopes to sign
 * @param link_encs @a kappa-dimensional array of @a num_newcoins encrypted links
 * @return MHD result code
 */
static int
handle_refresh_commit_json (struct MHD_Connection *connection,
                            const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                            const json_t *commit_signature,
                            unsigned int kappa,
                            unsigned int num_oldcoins,
                            const json_t *transfer_pubs,
                            const json_t *secret_encs,
                            unsigned int num_newcoins,
                            const json_t *coin_evs,
                            const json_t *link_encs)
{
  struct GNUNET_HashCode commit_hash;
  struct GNUNET_HashContext *hash_context;
  struct RefreshCommitSignatureBody body;
  struct RefreshCommitCoin *commit_coin[kappa];
  struct RefreshCommitLink *commit_link[kappa];
  unsigned int i;
  unsigned int j;
  int res;

  /* parse JSON arrays into 2d binary arrays and hash everything
     together for the signature check */
  memset (commit_coin, 0, sizeof (commit_coin));
  memset (commit_link, 0, sizeof (commit_link));
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  for (i = 0; i < kappa; i++)
  {
    commit_coin[i] = GNUNET_malloc (num_newcoins *
                                    sizeof (struct RefreshCommitCoin));
    for (j = 0; j < num_newcoins; j++)
    {
      char *link_enc;
      size_t link_enc_size;

      res = GNUNET_MINT_parse_navigate_json (connection,
                                             coin_evs,
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA_VAR,
                                             &commit_coin[i][j].coin_ev,
                                             &commit_coin[i][j].coin_ev_size);

      if (GNUNET_OK != res)
      {
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        free_commit_coins (commit_coin, kappa, num_newcoins);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       commit_coin[i][j].coin_ev,
                                       commit_coin[i][j].coin_ev_size);
      res = GNUNET_MINT_parse_navigate_json (connection,
                                             link_encs,
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA_VAR,
                                             &link_enc,
                                             &link_enc_size);
      if (GNUNET_OK != res)
      {
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        free_commit_coins (commit_coin, kappa, num_newcoins);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }
      commit_coin[i][j].refresh_link = TALER_refresh_link_encrypted_decode (link_enc,
                                                                            link_enc_size);

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       link_enc,
                                       link_enc_size);
    }
  }

  for (i = 0; i < kappa; i++)
  {
    commit_link[i] = GNUNET_malloc (num_oldcoins *
                                    sizeof (struct RefreshCommitLink));
    for (j = 0; j < num_oldcoins; j++)
    {
      res = GNUNET_MINT_parse_navigate_json (connection,
                                             transfer_pubs,
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             &commit_link[i][j].transfer_pub,
                                             sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));

      if (GNUNET_OK != res)
      {
        GNUNET_break (GNUNET_SYSERR != res);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        free_commit_coins (commit_coin, kappa, num_newcoins);
        free_commit_links (commit_link, kappa, num_oldcoins);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &commit_link[i][j].transfer_pub,
                                       sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));

      res = GNUNET_MINT_parse_navigate_json (connection,
                                             secret_encs,
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             &commit_link[i][j].shared_secret_enc,
                                             sizeof (struct GNUNET_HashCode));

      if (GNUNET_OK != res)
      {
        GNUNET_break (GNUNET_SYSERR != res);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        free_commit_coins (commit_coin, kappa, num_newcoins);
        free_commit_links (commit_link, kappa, num_oldcoins);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &commit_link[i][j].shared_secret_enc,
                                       sizeof (struct GNUNET_HashCode));
    }
  }
  GNUNET_CRYPTO_hash_context_finish (hash_context, &commit_hash);

  /* verify commit signature */
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_COMMIT);
  body.purpose.size = htonl (sizeof (struct RefreshCommitSignatureBody));
  body.commit_hash = commit_hash;

  if (GNUNET_OK !=
      (res = request_json_check_signature (connection,
                                           commit_signature,
                                           refresh_session_pub,
                                           &body.purpose)))
  {
    free_commit_coins (commit_coin, kappa, num_newcoins);
    free_commit_links (commit_link, kappa, num_oldcoins);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  /* execute commit */
  /* FIXME: we must also store the signature! (#3635) */
  res = TALER_MINT_db_execute_refresh_commit (connection,
                                              refresh_session_pub,
                                              kappa,
                                              num_oldcoins,
                                              num_newcoins,
                                              commit_coin,
                                              commit_link);
  free_commit_coins (commit_coin, kappa, num_newcoins);
  free_commit_links (commit_link, kappa, num_oldcoins);

  return res;
}


/**
 * Handle a "/refresh/commit" request.  Parses the top-level JSON to
 * determine the dimensions of the problem and then handles handing
 * off to #handle_refresh_commit_json() to parse the details of the
 * JSON arguments.  Once the signature has been verified, the
 * commit data is written to the database via
 * #TALER_MINT_db_execute_refresh_commit() and the reveal parameter
 * is then returned to the client.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TALER_MINT_handler_refresh_commit (struct RequestHandler *rh,
                                   struct MHD_Connection *connection,
                                   void **connection_cls,
                                   const char *upload_data,
                                   size_t *upload_data_size)
{
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;
  int res;
  unsigned int kappa;
  unsigned int num_oldcoins;
  unsigned int num_newcoins;
  json_t *root;
  json_t *coin_evs;
  json_t *link_encs;
  json_t *transfer_pubs;
  json_t *secret_encs;
  json_t *coin_detail;
  json_t *commit_sig_json;
  struct GNUNET_MINT_ParseFieldSpec spec[] = {
    TALER_MINT_PARSE_FIXED ("session_pub", &refresh_session_pub),
    TALER_MINT_PARSE_ARRAY ("coin_evs", &coin_evs),
    TALER_MINT_PARSE_ARRAY ("link_encs", &link_encs),
    TALER_MINT_PARSE_ARRAY ("transfer_pubs", &transfer_pubs),
    TALER_MINT_PARSE_ARRAY ("secret_encs", &secret_encs),
    TALER_MINT_PARSE_OBJECT ("commit_signature", &commit_sig_json),
    TALER_MINT_PARSE_END
  };

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;

  res = TALER_MINT_parse_json_data (connection,
                                    root,
                                    spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

  /* Determine dimensionality of the request (kappa, #old and #new coins) */
  kappa = json_array_size (coin_evs);
  if ( (3 > kappa) || (kappa > 32) )
  {
    GNUNET_break_op (0);
    TALER_MINT_release_parsed_data (spec);
    return TALER_MINT_reply_arg_invalid (connection,
                                         "coin_evs");
  }
  if (json_array_size (transfer_pubs) != kappa)
  {
    GNUNET_break_op (0);
    TALER_MINT_release_parsed_data (spec);
    return TALER_MINT_reply_arg_invalid (connection,
                                         "transfer_pubs");
  }
  res = GNUNET_MINT_parse_navigate_json (connection, coin_evs,
                                         JNAV_INDEX, (int) 0,
                                         JNAV_RET_DATA,
                                         JSON_ARRAY, &coin_detail);
  if (GNUNET_OK != res)
  {
    TALER_MINT_release_parsed_data (spec);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  num_newcoins = json_array_size (coin_detail);
  res = GNUNET_MINT_parse_navigate_json (connection,
                                         transfer_pubs,
                                         JNAV_INDEX, (int) 0,
                                         JNAV_RET_DATA,
                                         JSON_ARRAY, &coin_detail);
  if (GNUNET_OK != res)
  {
    TALER_MINT_release_parsed_data (spec);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  num_oldcoins = json_array_size (coin_detail);
  res = handle_refresh_commit_json (connection,
                                    &refresh_session_pub,
                                    commit_sig_json,
                                    kappa,
                                    num_oldcoins,
                                    transfer_pubs,
                                    secret_encs,
                                    num_newcoins,
                                    coin_evs,
                                    link_encs);
  TALER_MINT_release_parsed_data (spec);
  return res;
}


/**
 * Handle a "/refresh/reveal" request.   Parses the given JSON
 * transfer private keys and if successful, passes everything to
 * #TALER_MINT_db_execute_refresh_reveal() which will verify that the
 * revealed information is valid then returns the signed refreshed
 * coins.
 *
 * @param connection the MHD connection to handle
 * @param refresh_session_pub public key of the session
 * @param kappa length of the 1st dimension of @a transfer_privs array PLUS ONE
 * @param num_oldcoins length of the 2nd dimension of @a transfer_privs array
 * @param tp_json private transfer keys in JSON format
 * @return MHD result code
  */
static int
handle_refresh_reveal_json (struct MHD_Connection *connection,
                            const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                            unsigned int kappa,
                            unsigned int num_oldcoins,
                            const json_t *tp_json)
{
  struct GNUNET_CRYPTO_EcdsaPrivateKey *transfer_privs[kappa - 1];
  unsigned int i;
  unsigned int j;
  int res;

  for (i = 0; i < kappa - 1; i++)
    transfer_privs[i] = GNUNET_malloc (num_oldcoins *
                                       sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey));
  res = GNUNET_OK;
  for (i = 0; i < kappa - 1; i++)
  {
    if (GNUNET_OK != res)
      break;
    for (j = 0; j < num_oldcoins; j++)
    {
      if (GNUNET_OK != res)
        break;
      res = GNUNET_MINT_parse_navigate_json (connection,
                                             tp_json,
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             &transfer_privs[i][j],
                                             sizeof (struct GNUNET_CRYPTO_EddsaPrivateKey));
    }
  }
  if (GNUNET_OK != res)
    res = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  else
    res = TALER_MINT_db_execute_refresh_reveal (connection,
                                                refresh_session_pub,
                                                kappa,
                                                num_oldcoins,
                                                transfer_privs);
  for (i = 0; i < kappa - 1; i++)
    GNUNET_free (transfer_privs[i]);
  return res;
}


/**
 * Handle a "/refresh/reveal" request. This time, the client reveals
 * the private transfer keys except for the cut-and-choose value
 * returned from "/refresh/commit".  This function parses the revealed
 * keys and secrets and ultimately passes everything to
 * #TALER_MINT_db_execute_refresh_reveal() which will verify that the
 * revealed information is valid then returns the signed refreshed
 * coins.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TALER_MINT_handler_refresh_reveal (struct RequestHandler *rh,
                                   struct MHD_Connection *connection,
                                   void **connection_cls,
                                   const char *upload_data,
                                   size_t *upload_data_size)
{
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;
  int res;
  unsigned int kappa;
  unsigned int num_oldcoins;
  json_t *reveal_detail;
  json_t *root;
  json_t *transfer_privs;
  struct GNUNET_MINT_ParseFieldSpec spec[] = {
    TALER_MINT_PARSE_FIXED ("session_pub", &refresh_session_pub),
    TALER_MINT_PARSE_ARRAY ("transfer_privs", &transfer_privs),
    TALER_MINT_PARSE_END
  };

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;

  res = TALER_MINT_parse_json_data (connection,
                                    root,
                                    spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;

  /* Determine dimensionality of the request (kappa and #old coins) */
  kappa = json_array_size (transfer_privs) + 1;
  if ( (2 > kappa) || (kappa > 31) )
  {
    TALER_MINT_release_parsed_data (spec);
    return TALER_MINT_reply_arg_invalid (connection,
                                         "transfer_privs");
  }
  /* Note we do +1 as 1 row (cut-and-choose!) is missing! */
  kappa++;
  res = GNUNET_MINT_parse_navigate_json (connection,
                                         transfer_privs,
                                         JNAV_INDEX, 0,
                                         JNAV_RET_TYPED_JSON,
                                         JSON_ARRAY,
                                         &reveal_detail);
  if (GNUNET_OK != res)
  {
    TALER_MINT_release_parsed_data (spec);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  num_oldcoins = json_array_size (reveal_detail);
  res = handle_refresh_reveal_json (connection,
                                    &refresh_session_pub,
                                    kappa,
                                    num_oldcoins,
                                    transfer_privs);
  TALER_MINT_release_parsed_data (spec);
  return res;
}


/**
 * Handle a "/refresh/link" request
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TALER_MINT_handler_refresh_link (struct RequestHandler *rh,
                                 struct MHD_Connection *connection,
                                 void **connection_cls,
                                 const char *upload_data,
                                 size_t *upload_data_size)
{
  struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
  int res;

  res = TALER_MINT_mhd_request_arg_data (connection,
                                         "coin_pub",
                                         &coin_pub,
                                         sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if (GNUNET_OK != res)
    return MHD_YES;

  return TALER_MINT_db_execute_refresh_link (connection,
                                             &coin_pub);
}


/* end of taler-mint-httpd_refresh.c */
