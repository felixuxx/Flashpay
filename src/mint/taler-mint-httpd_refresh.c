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


static int
check_confirm_signature (struct MHD_Connection *connection,
                         json_t *coin_info,
                         const struct GNUNET_CRYPTO_EcdsaPublicKey *coin_pub,
                         const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub)
{
  struct RefreshMeltConfirmSignRequestBody body;
  struct GNUNET_CRYPTO_EcdsaSignature sig;
  int res;

  body.purpose.size = htonl (sizeof (struct RefreshMeltConfirmSignRequestBody));
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_MELT_CONFIRM);
  body.session_pub = *session_pub;

  res = GNUNET_MINT_parse_navigate_json (connection, coin_info,
                                  JNAV_FIELD, "confirm_sig",
                                  JNAV_RET_DATA,
                                  &sig,
                                  sizeof (struct GNUNET_CRYPTO_EcdsaSignature));

  if (GNUNET_OK != res)
  {
    GNUNET_break (GNUNET_SYSERR != res);
    return res;
  }

  if (GNUNET_OK !=
      GNUNET_CRYPTO_ecdsa_verify (TALER_SIGNATURE_REFRESH_MELT_CONFIRM,
                                  &body.purpose,
                                  &sig,
                                  coin_pub))
  {
    if (MHD_YES !=
        TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_UNAUTHORIZED,
                                    "{s:s}",
                                    "error", "signature invalid"))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }

  return GNUNET_OK;
}


/**
 * Extract public coin information from a JSON object.
 *
 * @param connection the connection to send error responses to
 * @param root the JSON object to extract the coin info from
 * @return #GNUNET_YES if coin public info in JSON was valid
 *         #GNUNET_NO JSON was invalid, response was generated
 *         #GNUNET_SYSERR on internal error
 */
static int
request_json_require_coin_public_info (struct MHD_Connection *connection,
                                       json_t *root,
                                       struct TALER_CoinPublicInfo *r_public_info)
{
  int ret;
  struct GNUNET_CRYPTO_rsa_Signature *sig;
  struct GNUNET_CRYPTO_rsa_PublicKey *pk;
  struct GNUNET_MINT_ParseFieldSpec spec[] =
    {
      TALER_MINT_PARSE_FIXED ("coin_pub", &r_public_info->coin_pub),
      TALER_MINT_PARSE_RSA_SIGNATURE ("denom_sig", &sig),
      TALER_MINT_PARSE_RSA_PUBLIC_KEY ("denom_pub", &pk),
      TALER_MINT_PARSE_END
    };

  ret = TALER_MINT_parse_json_data (connection,
                                    root,
                                    spec);
  if (GNUNET_OK != ret)
    return ret;
  // TALER_MINT_release_parsed_data (spec);
  r_public_info->denom_sig = sig;
  r_public_info->denom_pub = pk;
  return GNUNET_OK;
}


/**
 * Verify a signature that is encoded in a JSON object
 *
 * @param connection the connection to send errors to
 * @param root the JSON object with the signature
 * @param the public key that the signature was created with
 * @param purpose the signed message
 * @return #GNUNET_YES if the signature was valid
 *         #GNUNET_NO if the signature was invalid
 *         #GNUNET_SYSERR on internal error
 */
static int
request_json_check_signature (struct MHD_Connection *connection,
                              const json_t *root,
                              const struct GNUNET_CRYPTO_EddsaPublicKey *pub,
                              struct GNUNET_CRYPTO_EccSignaturePurpose *purpose)
{
  struct GNUNET_CRYPTO_EddsaSignature signature;
  int size;
  uint32_t purpose_num;
  int res;
  json_t *el;

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "sig",
                                  JNAV_RET_DATA,
                                  &signature,
                                  sizeof (struct GNUNET_CRYPTO_EddsaSignature));

  if (GNUNET_OK != res)
    return res;

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "purpose",
                                  JNAV_RET_TYPED_JSON,
                                  JSON_INTEGER,
                                  &el);

  if (GNUNET_OK != res)
    return res;

  purpose_num = json_integer_value (el);

  if (purpose_num != ntohl (purpose->purpose))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING, "signature invalid (purpose wrong)\n");
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error", "signature invalid (purpose)");
  }

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "size",
                                  JNAV_RET_TYPED_JSON,
                                  JSON_INTEGER,
                                  &el);

  if (GNUNET_OK != res)
    return res;

  size = json_integer_value (el);

  if (size != ntohl (purpose->size))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING, "signature invalid (size wrong)\n");
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       GNUNET_NO, GNUNET_SYSERR,
                                       "{s:s}",
                                       "error", "signature invalid (size)");
  }

  if (GNUNET_OK != GNUNET_CRYPTO_eddsa_verify (purpose_num,
                                               purpose,
                                               &signature,
                                               pub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING, "signature invalid (did not verify)\n");
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       "{s:s}",
                                       "error",
                                       "invalid signature (verification)");
  }

  return GNUNET_OK;
}


/**
 * Handle a "/refresh/melt" request after the first parsing has happened.
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
handle_refresh_melt_json (struct MHD_Connection *connection,
                          const struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub,
                          const json_t *new_denoms,
                          const json_t *melt_coins,
                          const json_t *melt_sig_json)
{
  int res;
  unsigned int num_new_denoms;
  unsigned int i;
  struct GNUNET_CRYPTO_rsa_PublicKey **denom_pubs;
  struct TALER_CoinPublicInfo *coin_public_infos;
  unsigned int coin_count;
  struct GNUNET_HashContext *hash_context;
  struct GNUNET_HashCode melt_hash;
  struct MintKeyState *key_state;
  struct RefreshMeltSignatureBody body;
  char *buf;
  size_t buf_size;
  struct TALER_MINT_DenomKeyIssuePriv *dki;

  num_new_denoms = json_array_size (new_denoms);

  denom_pubs = GNUNET_malloc (num_new_denoms *
                              sizeof (struct GNUNET_CRYPTO_rsa_PublicKey *));

  for (i=0;i<num_new_denoms;i++)
  {
    res = GNUNET_MINT_parse_navigate_json (connection, new_denoms,
                                           JNAV_INDEX, (int) i,
                                           JNAV_RET_DATA_VAR,
                                           &buf,
                                           &buf_size);
    if (GNUNET_OK != res)
    {
      GNUNET_free (denom_pubs);
      /* FIXME: proper cleanup! */
      return res;
    }
    denom_pubs[i] = GNUNET_CRYPTO_rsa_public_key_decode (buf, buf_size);
    GNUNET_free (buf);
    if (NULL == denom_pubs[i])
    {
      GNUNET_free (denom_pubs);
      /* FIXME: proper cleanup! */
      /* FIXME: generate error reply */
      return GNUNET_SYSERR;
    }
  }




  coin_count = json_array_size (melt_coins);
  coin_public_infos = GNUNET_malloc (coin_count *
                                     sizeof (struct TALER_CoinPublicInfo));
  key_state = TALER_MINT_key_state_acquire ();
  for (i = 0; i < coin_count; i++)
    {
      /* decode JSON data on coin to melt */
      res = request_json_require_coin_public_info (connection,
                                                   json_array_get (melt_coins, i),
                                                   &coin_public_infos[i]);
      if (GNUNET_OK != res)
        {
          GNUNET_break (GNUNET_SYSERR != res);
          // FIXME: leaks!
          TALER_MINT_key_state_release (key_state);
          return res;
        }
      /* check that this coin's private key was used to sign that
         we should melt it */
      if (GNUNET_OK !=
          (res = check_confirm_signature (connection,
                                          json_array_get (melt_coins, i),
                                          &coin_public_infos[i].coin_pub,
                                          refresh_session_pub)))
      {
        GNUNET_break (GNUNET_SYSERR != res);
        // FIXME: leaks!
        TALER_MINT_key_state_release (key_state);
        return res;
      }
      /* check coin denomination is valid */
      dki = TALER_MINT_get_denom_key (key_state,
                                      coin_public_infos[i].denom_pub);
      if (NULL == dki)
      {
        TALER_MINT_key_state_release (key_state);
        LOG_WARNING ("Unknown denomination key in /refresh/melt request\n");
        TALER_MINT_key_state_release (key_state);
        return TALER_MINT_reply_arg_invalid (connection,
                                             "melt_coins");
      }
      /* check mint signature on the coin */
      if (GNUNET_OK !=
          TALER_test_coin_valid (&coin_public_infos[i]))
        {
          // FIXME: leaks!
          TALER_MINT_key_state_release (key_state);
          return (MHD_YES ==
                TALER_MINT_reply_json_pack (connection,
                                            MHD_HTTP_NOT_FOUND,
                                            "{s:s}",
                                            "error", "coin invalid"))
          ? GNUNET_NO : GNUNET_SYSERR;
        }
    }
  TALER_MINT_key_state_release (key_state);

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
  {
    // FIXME: generate proper error reply
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }


  res = TALER_MINT_db_execute_refresh_melt (connection,
                                            refresh_session_pub,
                                            num_new_denoms,
                                            denom_pubs,
                                            coin_count,
                                            coin_public_infos);
  // FIXME: free memory
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

  if (GNUNET_OK != (res = request_json_check_signature (connection,
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
