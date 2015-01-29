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
 *
 * TODO:
 * - split /refresh/reveal properly into parsing, DB-ops and response generation
 * - error handling
 * - document functions properly
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
  struct GNUNET_MINT_ParseFieldSpec spec[] =
    {
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
 * to validate the melted coins, the signature and execute the melt.
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
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if (GNUNET_NO == res)
    return MHD_YES;
  res = handle_refresh_melt_json (connection,
                                  &refresh_session_pub,
                                  new_denoms,
                                  melt_coins,
                                  melt_sig_json);
  TALER_MINT_release_parsed_data (spec);
  return res;
}


/**
 * Handle a "/refresh/commit" request
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
  unsigned int i;
  unsigned int j;
  unsigned int kappa;
  unsigned int num_oldcoins;
  unsigned int num_newcoins;
  struct GNUNET_HashCode commit_hash;
  struct GNUNET_HashContext *hash_context;
  json_t *root;
  struct RefreshCommitSignatureBody body;
  json_t *commit_sig_json;
  struct RefreshCommitCoin **commit_coin;
  struct RefreshCommitLink **commit_link;
  json_t *coin_evs;
  json_t *transfer_pubs;
  json_t *coin_detail;

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "session_pub",
                                         JNAV_RET_DATA,
                                         &refresh_session_pub,
                                         sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_OK != res)
  {
    GNUNET_break (GNUNET_SYSERR != res);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  /* Determine dimensionality of the request (kappa, #old and #new coins) */
  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "coin_evs",
                                         JNAV_RET_TYPED_JSON, JSON_ARRAY, &coin_evs);
  if (GNUNET_OK != res)
    return res;
  kappa = json_array_size (coin_evs);
  if (3 > kappa)
  {
    GNUNET_break_op (0);
    // FIXME: generate error message
    return MHD_NO;
  }
  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "coin_evs",
                                         JNAV_INDEX, (int) 0,
                                         JNAV_RET_DATA,
                                         JSON_ARRAY, &coin_detail);
  if (GNUNET_OK != res)
    return res;
  num_newcoins = json_array_size (coin_detail);

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "transfer_pubs",
                                         JNAV_RET_TYPED_JSON, JSON_ARRAY, &transfer_pubs);
  if (GNUNET_OK != res)
    return res;
  if (json_array_size (transfer_pubs) != kappa)
  {
    GNUNET_break_op (0);
    // FIXME: generate error message
    return MHD_NO;
  }
  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "transfer_pubs",
                                         JNAV_INDEX, (int) 0,
                                         JNAV_RET_DATA,
                                         JSON_ARRAY, &coin_detail);
  if (GNUNET_OK != res)
    return res;
  num_oldcoins = json_array_size (coin_detail);



  hash_context = GNUNET_CRYPTO_hash_context_start ();
  commit_coin = GNUNET_malloc (kappa *
                               sizeof (struct RefreshCommitCoin *));
  for (i = 0; i < kappa; i++)
  {
    commit_coin[i] = GNUNET_malloc (num_newcoins *
                                    sizeof (struct RefreshCommitCoin));
    for (j = 0; j < num_newcoins; j++)
    {
      char *link_enc;
      size_t link_enc_size;

      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                             JNAV_FIELD, "coin_evs",
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA_VAR,
                                             &commit_coin[i][j].coin_ev,
                                             &commit_coin[i][j].coin_ev_size);

      if (GNUNET_OK != res)
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       commit_coin[i][j].coin_ev,
                                       commit_coin[i][j].coin_ev_size);

      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                             JNAV_FIELD, "link_encs",
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA_VAR,
                                             &link_enc,
                                             &link_enc_size);
      if (GNUNET_OK != res)
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }
      // FIXME: convert link_enc / link_enc_size to
      // commit_coin[i][j].refresh_link!


      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       link_enc,
                                       link_enc_size);
    }
  }

  commit_link = GNUNET_malloc (kappa *
                               sizeof (struct RefreshCommitLink *));
  for (i = 0; i < kappa; i++)
  {
    commit_link[i] = GNUNET_malloc (num_oldcoins *
                                    sizeof (struct RefreshCommitLink));
    for (j = 0; j < num_oldcoins; j++)
    {
      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                             JNAV_FIELD, "transfer_pubs",
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             &commit_link[i][j].transfer_pub,
                                             sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));

      if (GNUNET_OK != res)
      {
        GNUNET_break (GNUNET_SYSERR != res);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &commit_link[i][j].transfer_pub,
                                       sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));

      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                             JNAV_FIELD, "secret_encs",
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             &commit_link[i][j].shared_secret_enc,
                                             sizeof (struct GNUNET_HashCode));

      if (GNUNET_OK != res)
      {
        GNUNET_break (GNUNET_SYSERR != res);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &commit_link[i][j].shared_secret_enc,
                                       sizeof (struct GNUNET_HashCode));
    }
  }
  GNUNET_CRYPTO_hash_context_finish (hash_context, &commit_hash);

  commit_sig_json = json_object_get (root, "commit_signature");
  if (NULL == commit_sig_json)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error",
                                       "commit_signature missing");
  }

  body.commit_hash = commit_hash;
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_COMMIT);
  body.purpose.size = htonl (sizeof (struct RefreshCommitSignatureBody));

  if (GNUNET_OK !=
      (res = request_json_check_signature (connection,
                                           commit_sig_json,
                                           &refresh_session_pub,
                                           &body.purpose)))
  {
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  res = TALER_MINT_db_execute_refresh_commit (connection,
                                              &refresh_session_pub,
                                              kappa,
                                              num_oldcoins,
                                              num_newcoins,
                                              commit_coin,
                                              commit_link);
  // FIXME: free memory
  return res;
}


/**
 * Handle a "/refresh/reveal" request
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
  json_t *transfer_p;
  json_t *reveal_detail;
  unsigned int i;
  unsigned int j;
  json_t *root;
  struct GNUNET_CRYPTO_EcdsaPrivateKey **transfer_privs;

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "session_pub",
                                  JNAV_RET_DATA,
                                  &refresh_session_pub,
                                  sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_OK != res)
  {
    GNUNET_break (GNUNET_SYSERR != res);
    return res;
  }


  /* Determine dimensionality of the request (kappa and #old coins) */
  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "transfer_privs",
                                         JNAV_RET_TYPED_JSON, JSON_ARRAY, &transfer_p);
  if (GNUNET_OK != res)
    return res;
  kappa = json_array_size (transfer_p) + 1; /* 1 row is missing */
  if (3 > kappa)
  {
    GNUNET_break_op (0);
    // FIXME: generate error message
    return MHD_NO;
  }
  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "transfer_privs",
                                         JNAV_INDEX, 0,
                                         JNAV_RET_TYPED_JSON, JSON_ARRAY, &reveal_detail);
  if (GNUNET_OK != res)
    return res;
  num_oldcoins = json_array_size (reveal_detail);


  transfer_privs = GNUNET_malloc ((kappa - 1) *
                                  sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey *));
  for (i = 0; i < kappa - 1; i++)
  {
    transfer_privs[i] = GNUNET_malloc (num_oldcoins *
                                       sizeof (struct GNUNET_CRYPTO_EcdsaPrivateKey));
    for (j = 0; j < num_oldcoins; j++)
      {
        res = GNUNET_MINT_parse_navigate_json (connection, root,
                                               JNAV_FIELD, "transfer_privs",
                                               JNAV_INDEX, (int) i,
                                               JNAV_INDEX, (int) j,
                                               JNAV_RET_DATA,
                                               &transfer_privs[i][j],
                                               sizeof (struct GNUNET_CRYPTO_EddsaPrivateKey));
        if (GNUNET_OK != res)
          {
            GNUNET_break (0);
            // FIXME: return 'internal error'?
            return MHD_NO;
          }
      }
  }


  res = TALER_MINT_db_execute_refresh_reveal (connection,
                                              &refresh_session_pub,
                                              kappa,
                                              num_oldcoins,
                                              transfer_privs);
  // FIXME: free memory
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
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_OK != res)
    return MHD_YES;

  return TALER_MINT_db_execute_refresh_link (connection,
                                             &coin_pub);
}


/* end of taler-mint-httpd_refresh.c */
