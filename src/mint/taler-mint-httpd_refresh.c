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
 * - split properly into parsing, DB-ops and response generation
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
#include "taler_rsa.h"
#include "taler_json_lib.h"
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_mhd.h"
#include "taler-mint-httpd_refresh.h"
#include "taler-mint-httpd_responses.h"


/**
 * FIXME: document!
 */
static int
link_iter (void *cls,
           const struct LinkDataEnc *link_data_enc,
           const struct TALER_RSA_PublicKeyBinaryEncoded *denom_pub,
           const struct TALER_RSA_Signature *ev_sig)
{
  json_t *list = cls;
  json_t *obj = json_object ();

  json_array_append_new (list, obj);

  json_object_set_new (obj, "link_enc",
                         TALER_JSON_from_data (link_data_enc,
                                       sizeof (struct LinkDataEnc)));

  json_object_set_new (obj, "denom_pub",
                         TALER_JSON_from_data (denom_pub,
                                       sizeof (struct TALER_RSA_PublicKeyBinaryEncoded)));

  json_object_set_new (obj, "ev_sig",
                         TALER_JSON_from_data (ev_sig,
                                       sizeof (struct TALER_RSA_Signature)));

  return GNUNET_OK;
}


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
 *         #GNUNET_NO otherwise
 *         #GNUNET_SYSERR on internal error
 */
static int
request_json_require_coin_public_info (struct MHD_Connection *connection,
                                       json_t *root,
                                       struct TALER_CoinPublicInfo *r_public_info)
{
  int ret;

  GNUNET_assert (NULL != root);

  ret = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "coin_pub",
                                  JNAV_RET_DATA,
                                  &r_public_info->coin_pub,
                                  sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey));
  if (GNUNET_OK != ret)
    return ret;

  ret = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "denom_sig",
                                  JNAV_RET_DATA,
                                  &r_public_info->denom_sig,
                                  sizeof (struct TALER_RSA_Signature));
  if (GNUNET_OK != ret)
    return ret;

  ret = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "denom_pub",
                                  JNAV_RET_DATA,
                                  &r_public_info->denom_pub,
                                  sizeof (struct TALER_RSA_PublicKeyBinaryEncoded));
  if (GNUNET_OK != ret)
    return ret;

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
                              json_t *root,
                              struct GNUNET_CRYPTO_EddsaPublicKey *pub,
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
 * Handle a "/refresh/melt" request
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
  struct GNUNET_CRYPTO_EddsaPublicKey refresh_session_pub;
  int res;
  json_t *new_denoms;
  unsigned int num_new_denoms;
  unsigned int i;
  struct TALER_RSA_PublicKeyBinaryEncoded *denom_pubs;
  json_t *melt_coins;
  struct TALER_CoinPublicInfo *coin_public_infos;
  unsigned int coin_count;
  struct GNUNET_HashContext *hash_context;
  struct GNUNET_HashCode melt_hash;
  struct MintKeyState *key_state;
  struct RefreshMeltSignatureBody body;
  json_t *melt_sig_json;

  res = TALER_MINT_parse_post_json (connection,
                                    connection_cls,
                                    upload_data,
                                    upload_data_size,
                                    &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;

  /* session_pub field must always be present */
  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                  JNAV_FIELD, "session_pub",
                                  JNAV_RET_DATA,
                                  &refresh_session_pub,
                                  sizeof (struct GNUNET_CRYPTO_EddsaPublicKey));
  if (GNUNET_OK != res)
  {
    // FIXME: return 'internal error'?
    GNUNET_break (0);
    return MHD_NO;
  }
  if (GNUNET_NO == res)
    return MHD_YES;

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "new_denoms",
                                         JNAV_RET_TYPED_JSON,
                                         JSON_ARRAY,
                                         &new_denoms);
  if (GNUNET_OK != res)
    return res;
  num_new_denoms = json_array_size (new_denoms);
  denom_pubs = GNUNET_malloc (num_new_denoms *
                              sizeof (struct TALER_RSA_PublicKeyBinaryEncoded));

  for (i=0;i<num_new_denoms;i++)
  {
    res = GNUNET_MINT_parse_navigate_json (connection, root,
                                           JNAV_FIELD, "new_denoms",
                                           JNAV_INDEX, (int) i,
                                           JNAV_RET_DATA,
                                           &denom_pubs[i],
                                           sizeof (struct TALER_RSA_PublicKeyBinaryEncoded));

    if (GNUNET_OK != res)
    {
      GNUNET_free (denom_pubs);
      /* FIXME: proper cleanup! */
      return res;
    }
  }

  res = GNUNET_MINT_parse_navigate_json (connection, root,
                                         JNAV_FIELD, "melt_coins",
                                         JNAV_RET_TYPED_JSON,
                                         JSON_ARRAY,
                                         &melt_coins);
  if (GNUNET_OK != res)
    {
      // FIXME: leaks!
      return res;
    }

  melt_sig_json = json_object_get (root,
                                   "melt_signature");
  if (NULL == melt_sig_json)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s}",
                                       "error",
                                       "melt_signature missing");
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
          return res;
        }
      /* check that this coin's private key was used to sign that
         we should melt it */
      if (GNUNET_OK != (res = check_confirm_signature (connection,
                                                       json_array_get (melt_coins, i),
                                                       &coin_public_infos[i].coin_pub,
                                                       &refresh_session_pub)))
        {
          GNUNET_break (GNUNET_SYSERR != res);
          // FIXME: leaks!
          return res;
        }
      /* check mint signature on the coin */
      if (GNUNET_OK != TALER_MINT_test_coin_valid (key_state,
                                                   &coin_public_infos[i]))
        {
          // FIXME: leaks!
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
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &denom_pubs[i],
                                     sizeof (struct TALER_RSA_PublicKeyBinaryEncoded));
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
                                           &refresh_session_pub,
                                           &body.purpose)))
  {
    // FIXME: generate proper error reply
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }


  res = TALER_MINT_db_execute_refresh_melt (connection,
                                            &refresh_session_pub,
                                            num_new_denoms,
                                            denom_pubs,
                                            coin_count,
                                            coin_public_infos);
  // FIXME: free memory
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
      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                             JNAV_FIELD, "coin_evs",
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             commit_coin[i][j].coin_ev,
                                             sizeof (struct TALER_RSA_BlindedSignaturePurpose));

      if (GNUNET_OK != res)
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &commit_coin[i][j].coin_ev,
                                       sizeof (struct TALER_RSA_BlindedSignaturePurpose));

      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                             JNAV_FIELD, "link_encs",
                                             JNAV_INDEX, (int) i,
                                             JNAV_INDEX, (int) j,
                                             JNAV_RET_DATA,
                                             commit_coin[i][j].link_enc,
                                             TALER_REFRESH_LINK_LENGTH);
      if (GNUNET_OK != res)
      {
        // FIXME: return 'internal error'?
        GNUNET_break (0);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       commit_coin[i][j].link_enc,
                                       TALER_REFRESH_LINK_LENGTH);
      commit_coin[i][j].cnc_index = i;
      commit_coin[i][j].newcoin_index = j;
      commit_coin[i][j].session_pub = refresh_session_pub;
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
                                             commit_link[i][j].shared_secret_enc,
                                             TALER_REFRESH_SHARED_SECRET_LENGTH);

      if (GNUNET_OK != res)
      {
        GNUNET_break (GNUNET_SYSERR != res);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       commit_link[i][j].shared_secret_enc,
                                       TALER_REFRESH_SHARED_SECRET_LENGTH);

      commit_link[i][j].cnc_index = i;
      commit_link[i][j].oldcoin_index = j;
      commit_link[i][j].session_pub = refresh_session_pub;

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
 * Send response for "/refresh/reveal".
 *
 * @param connection the MHD connection
 * @param db_conn the connection to the mint's db
 * @param refresh_session_pub the refresh session's public key
 * @return a MHD result code
 */
static int
helper_refresh_reveal_send_response (struct MHD_Connection *connection,
                                     PGconn *db_conn,
                                     struct GNUNET_CRYPTO_EddsaPublicKey *refresh_session_pub)
{
  int res;
  int newcoin_index;
  struct RefreshSession refresh_session;
  struct TALER_RSA_Signature *sigs;

  res = TALER_MINT_DB_get_refresh_session (db_conn,
                                           refresh_session_pub,
                                           &refresh_session);
  if (GNUNET_OK != res)
  {
    // FIXME: return 'internal error'
    GNUNET_break (0);
    return MHD_NO;
  }

  GNUNET_assert (0 != refresh_session.reveal_ok);
  sigs = GNUNET_malloc (refresh_session.num_newcoins *
                        sizeof (struct TALER_RSA_Signature));
  for (newcoin_index = 0; newcoin_index < refresh_session.num_newcoins; newcoin_index++)
  {
    res = TALER_MINT_DB_get_refresh_collectable (db_conn,
                                                 newcoin_index,
                                                 refresh_session_pub,
                                                 &sigs[newcoin_index]);
    if (GNUNET_OK != res)
    {
      // FIXME: return 'internal error'
      GNUNET_break (0);
      GNUNET_free (sigs);
      return MHD_NO;
    }
  }
  res = TALER_MINT_reply_refresh_reveal_success (connection,
                                                 refresh_session.num_newcoins,
                                                 sigs);
  GNUNET_free (sigs);
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
  PGconn *db_conn;
  struct RefreshSession refresh_session;
  struct MintKeyState *key_state;
  int i;
  int j;
  json_t *root;

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

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    // FIXME: return 'internal error'?
    return MHD_NO;
  }

  /* Send response immediately if we already know the session,
   * and the session commited already.
   * Do _not_ care about fields other than session_pub in this case. */

  res = TALER_MINT_DB_get_refresh_session (db_conn, &refresh_session_pub, &refresh_session);
  if (GNUNET_YES == res && 0 != refresh_session.reveal_ok)
    return helper_refresh_reveal_send_response (connection, db_conn, &refresh_session_pub);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    // FIXME: return 'internal error'?
    return MHD_NO;
  }

  /* Check that the transfer private keys match their commitments.
   * Then derive the shared secret for each kappa, and check that they match. */

  for (i = 0; i < refresh_session.kappa; i++)
  {
    struct GNUNET_HashCode last_shared_secret;
    int secret_initialized = GNUNET_NO;

    if (i == (refresh_session.noreveal_index % refresh_session.kappa))
      continue;

    for (j = 0; j < refresh_session.num_oldcoins; j++)
    {
      struct GNUNET_CRYPTO_EcdsaPrivateKey transfer_priv;
      struct RefreshCommitLink commit_link;
      struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
      struct GNUNET_HashCode transfer_secret;
      struct GNUNET_HashCode shared_secret;

      res = GNUNET_MINT_parse_navigate_json (connection, root,
                                      JNAV_FIELD, "transfer_privs",
                                      JNAV_INDEX, (int) i,
                                      JNAV_INDEX, (int) j,
                                      JNAV_RET_DATA,
                                      &transfer_priv,
                                      sizeof (struct GNUNET_CRYPTO_EddsaPrivateKey));

      if (GNUNET_OK != res)
      {
        GNUNET_break (GNUNET_SYSERR != res);
        return res;
      }

      res = TALER_MINT_DB_get_refresh_commit_link (db_conn,
                                                   &refresh_session_pub,
                                                   i, j,
                                                   &commit_link);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
            // FIXME: return 'internal error'?
        return MHD_NO;
      }

      res = TALER_MINT_DB_get_refresh_melt (db_conn, &refresh_session_pub, j, &coin_pub);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
        // FIXME: return 'internal error'?
        return MHD_NO;
      }

      /* We're converting key types here, which is not very nice
       * but necessary and harmless (keys will be thrown away later). */
      if (GNUNET_OK != GNUNET_CRYPTO_ecc_ecdh ((struct GNUNET_CRYPTO_EcdhePrivateKey *) &transfer_priv,
                                               (struct GNUNET_CRYPTO_EcdhePublicKey *) &coin_pub,
                                               &transfer_secret))
      {
        GNUNET_break (0);
        // FIXME: return 'internal error'?
        return MHD_NO;
      }

      if (0 >= TALER_refresh_decrypt (commit_link.shared_secret_enc, TALER_REFRESH_SHARED_SECRET_LENGTH,
                                      &transfer_secret, &shared_secret))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "decryption failed\n");
        // FIXME: return 'internal error'?
        return MHD_NO;
      }

      if (GNUNET_NO == secret_initialized)
      {
        secret_initialized = GNUNET_YES;
        last_shared_secret = shared_secret;
      }
      else if (0 != memcmp (&shared_secret, &last_shared_secret, sizeof (struct GNUNET_HashCode)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "shared secrets do not match\n");
        // FIXME: return error code!
        return MHD_NO;
      }

      {
        struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub_check;
        GNUNET_CRYPTO_ecdsa_key_get_public (&transfer_priv, &transfer_pub_check);
        if (0 != memcmp (&transfer_pub_check, &commit_link.transfer_pub, sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey)))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "transfer keys do not match\n");
        // FIXME: return error code!
          return MHD_NO;
        }
      }
    }

    /* Check that the commitments for all new coins were correct */

    for (j = 0; j < refresh_session.num_newcoins; j++)
    {
      struct RefreshCommitCoin commit_coin;
      struct LinkData link_data;
      struct TALER_RSA_BlindedSignaturePurpose *coin_ev_check;
      struct GNUNET_CRYPTO_EcdsaPublicKey coin_pub;
      struct TALER_RSA_BlindingKey *bkey;
      struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;

      bkey = NULL;
      res = TALER_MINT_DB_get_refresh_commit_coin (db_conn,
                                                   &refresh_session_pub,
                                                   i, j,
                                                   &commit_coin);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
                // FIXME: return error code!
        return MHD_NO;
      }


      if (0 >= TALER_refresh_decrypt (commit_coin.link_enc, sizeof (struct LinkData),
                                      &last_shared_secret, &link_data))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "decryption failed\n");
                // FIXME: return error code!
        return MHD_NO;
      }

      GNUNET_CRYPTO_ecdsa_key_get_public (&link_data.coin_priv, &coin_pub);
      if (NULL == (bkey = TALER_RSA_blinding_key_decode (&link_data.bkey_enc)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Invalid blinding key\n");
                        // FIXME: return error code!
        return MHD_NO;
      }
      res = TALER_MINT_DB_get_refresh_order (db_conn, j, &refresh_session_pub, &denom_pub);
      if (GNUNET_OK != res)
      {
        GNUNET_break (0);
          // FIXME: return error code!
        return MHD_NO;
      }
      if (NULL == (coin_ev_check =
                   TALER_RSA_message_blind (&coin_pub,
                                            sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                                            bkey,
                                            &denom_pub)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "blind failed\n");
          // FIXME: return error code!
        return MHD_NO;
      }

      if (0 != memcmp (&coin_ev_check,
                       &commit_coin.coin_ev,
                       sizeof (struct TALER_RSA_BlindedSignaturePurpose)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "blind envelope does not match for kappa=%d, old=%d\n",
                    (int) i, (int) j);
        // FIXME: return error code!
        return MHD_NO;
      }
    }
  }


  if (GNUNET_OK != TALER_MINT_DB_transaction (db_conn))
  {
    GNUNET_break (0);
            // FIXME: return error code!
    return MHD_NO;
  }

  for (j = 0; j < refresh_session.num_newcoins; j++)
  {
    struct RefreshCommitCoin commit_coin;
    struct TALER_RSA_PublicKeyBinaryEncoded denom_pub;
    struct TALER_MINT_DenomKeyIssuePriv *dki;
    struct TALER_RSA_Signature ev_sig;

    res = TALER_MINT_DB_get_refresh_commit_coin (db_conn,
                                                 &refresh_session_pub,
                                                 refresh_session.noreveal_index % refresh_session.kappa,
                                                 j,
                                                 &commit_coin);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
              // FIXME: return error code!
      return MHD_NO;
    }
    res = TALER_MINT_DB_get_refresh_order (db_conn, j, &refresh_session_pub, &denom_pub);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
                    // FIXME: return error code!
      return MHD_NO;
    }


    key_state = TALER_MINT_key_state_acquire ();
    dki = TALER_MINT_get_denom_key (key_state, &denom_pub);
    TALER_MINT_key_state_release (key_state);
    if (NULL == dki)
    {
      GNUNET_break (0);
                    // FIXME: return error code!
      return MHD_NO;
    }
    if (GNUNET_OK !=
        TALER_RSA_sign (dki->denom_priv,
                        &commit_coin.coin_ev,
                        sizeof (struct TALER_RSA_BlindedSignaturePurpose),
                        &ev_sig))
    {
      GNUNET_break (0);
                    // FIXME: return error code!
      return MHD_NO;
    }

    res = TALER_MINT_DB_insert_refresh_collectable (db_conn,
                                                    j,
                                                    &refresh_session_pub,
                                                    &ev_sig);
    if (GNUNET_OK != res)
    {
      GNUNET_break (0);
                          // FIXME: return error code!
      return MHD_NO;
    }
  }
  /* mark that reveal was successful */

  res = TALER_MINT_DB_set_reveal_ok (db_conn, &refresh_session_pub);
  if (GNUNET_OK != res)
  {
    GNUNET_break (0);
    // FIXME: return error code!
    return MHD_NO;
  }

  if (GNUNET_OK != TALER_MINT_DB_commit (db_conn))
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  return helper_refresh_reveal_send_response (connection, db_conn, &refresh_session_pub);
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
  json_t *root;
  json_t *list;
  PGconn *db_conn;
  struct GNUNET_CRYPTO_EcdsaPublicKey transfer_pub;
  struct SharedSecretEnc shared_secret_enc;

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

  if (NULL == (db_conn = TALER_MINT_DB_get_connection ()))
  {
    GNUNET_break (0);
    // FIXME: return error code!
    return MHD_NO;
  }

  list = json_array ();
  root = json_object ();
  json_object_set_new (root, "new_coins", list);

  res = TALER_db_get_transfer (db_conn,
                               &coin_pub,
                               &transfer_pub,
                               &shared_secret_enc);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
        // FIXME: return error code!
    return MHD_NO;
  }
  if (GNUNET_NO == res)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "link data not found (transfer)");
  }
  GNUNET_assert (GNUNET_OK == res);

  res = TALER_db_get_link (db_conn, &coin_pub, link_iter, list);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
        // FIXME: return error code!
    return MHD_NO;
  }
  if (GNUNET_NO == res)
  {
    return TALER_MINT_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s}",
                                       "error",
                                       "link data not found (link)");
  }
  GNUNET_assert (GNUNET_OK == res);
  json_object_set_new (root, "transfer_pub",
                       TALER_JSON_from_data (&transfer_pub,
                                             sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)));
  json_object_set_new (root, "secret_enc",
                       TALER_JSON_from_data (&shared_secret_enc,
                                             sizeof (struct SharedSecretEnc)));
  return TALER_MINT_reply_json (connection,
                                root,
                                MHD_HTTP_OK);
}


/* end of taler-mint-httpd_refresh.c */
