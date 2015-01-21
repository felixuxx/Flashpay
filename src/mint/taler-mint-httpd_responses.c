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
 * @file taler-mint-httpd_responses.c
 * @brief API for generating the various replies of the mint; these
 *        functions are called TALER_MINT_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 *
 * TODO:
 * - when generating /deposit reply, do include signature of mint
 *   to say that we accepted it (check reply format)
 * - when generating /withdraw/status reply, which signature do
 *   we use there? Might want to instead return *all* signatures on the
 *   existig withdraw operations, instead of Mint's signature
 *   (check reply format, adjust `struct Reserve` if needed)
 */
#include "platform.h"
#include "taler-mint-httpd_responses.h"
#include "taler_json_lib.h"


/**
 * Send JSON object as response.  Decreases the reference count of the
 * JSON object.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TALER_MINT_reply_json (struct MHD_Connection *connection,
                       json_t *json,
                       unsigned int response_code)
{
  struct MHD_Response *resp;
  char *json_str;
  int ret;

  json_str = json_dumps (json, JSON_INDENT(2));
  json_decref (json);
  resp = MHD_create_response_from_buffer (strlen (json_str), json_str,
                                          MHD_RESPMEM_MUST_FREE);
  if (NULL == resp)
    return MHD_NO;
  (void) MHD_add_response_header (resp,
                                  MHD_HTTP_HEADER_CONTENT_TYPE,
                                  "application/json");
  ret = MHD_queue_response (connection, response_code, resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Function to call to handle the request by building a JSON
 * reply from a format string and varargs.
 *
 * @param connection the MHD connection to handle
 * @param response_code HTTP response code to use
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD result code
 */
int
TALER_MINT_reply_json_pack (struct MHD_Connection *connection,
                            unsigned int response_code,
                            const char *fmt,
                            ...)
{
  json_t *json;
  va_list argp;

  va_start (argp, fmt);
  json = json_vpack_ex (NULL, 0, fmt, argp);
  va_end (argp);
  if (NULL == json)
    return MHD_NO;
  return TALER_MINT_reply_json (connection,
                                json,
                                response_code);
}


/**
 * Send a response indicating an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TALER_MINT_reply_arg_invalid (struct MHD_Connection *connection,
                              const char *param_name)
{
  json_t *json;

  json = json_pack ("{ s:s, s:s }",
                    "error",
                    "invalid parameter",
                    "parameter",
                    param_name);
  return TALER_MINT_reply_json (connection,
                                json,
                                MHD_HTTP_BAD_REQUEST);
}


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TALER_MINT_reply_arg_missing (struct MHD_Connection *connection,
                              const char *param_name)
{
  json_t *json;

  json = json_pack ("{ s:s, s:s }",
                    "error",
                    "missing parameter",
                    "parameter",
                    param_name);
  return TALER_MINT_reply_json (connection,
                                json,
                                MHD_HTTP_BAD_REQUEST);
}


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TALER_MINT_reply_internal_error (struct MHD_Connection *connection,
                                 const char *hint)
{
  json_t *json;

  json = json_pack ("{ s:s, s:s }",
                    "error",
                    "internal error",
                    "hint",
                    hint);
  return TALER_MINT_reply_json (connection,
                                json,
                                MHD_HTTP_BAD_REQUEST);
}


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_request_too_large (struct MHD_Connection *connection)
{
  struct MHD_Response *resp;
  int ret;

  resp = MHD_create_response_from_buffer (0,
                                          NULL,
                                          MHD_RESPMEM_PERSISTENT);
  if (NULL == resp)
    return MHD_NO;
  ret = MHD_queue_response (connection,
                            MHD_HTTP_REQUEST_ENTITY_TOO_LARGE,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Send a response indicating that the JSON was malformed.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MINT_reply_invalid_json (struct MHD_Connection *connection)
{
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_BAD_REQUEST,
                                     "{s:s}",
                                     "error",
                                     "invalid json");
}


/**
 * Send confirmation of deposit success to client.
 *
 * @param connection connection to the client
 * @param deposit deposit request to confirm
 * @return MHD result code
 */
int
TALER_MINT_reply_deposit_success (struct MHD_Connection *connection,
                                  const struct Deposit *deposit)
{
  // FIXME: return more information here,
  // including in particular a signature over
  // the deposit data from the mint!
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_OK,
                                     "{s:s}",
                                     "status",
                                     "DEPOSIT_OK");
}


/**
 * Send reserve status information to client.
 *
 * @param connection connection to the client
 * @param reserve reserve status information to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_status_success (struct MHD_Connection *connection,
                                          const struct Reserve *reserve)
{
  json_t *json;

  /* Convert the public information of a reserve (i.e.
     excluding private key) to a JSON object. */
  json = json_object ();
  json_object_set_new (json,
                       "balance",
                       TALER_JSON_from_amount (TALER_amount_ntoh (reserve->balance)));
  json_object_set_new (json,
                       "expiration",
                       TALER_JSON_from_abs (GNUNET_TIME_absolute_ntoh (reserve->expiration)));
  json_object_set_new (json,
                       "signature",
                       TALER_JSON_from_sig (&reserve->status_sig_purpose,
                                            &reserve->status_sig));

  return TALER_MINT_reply_json (connection,
                                json,
                                MHD_HTTP_OK);
}


/**
 * Send blinded coin information to client.
 *
 * @param connection connection to the client
 * @param collectable blinded coin to return
 * @return MHD result code
 */
int
TALER_MINT_reply_withdraw_sign_success (struct MHD_Connection *connection,
                                        const struct CollectableBlindcoin *collectable)
{
  json_t *root = json_object ();

  json_object_set_new (root, "ev_sig",
                       TALER_JSON_from_data (&collectable->ev_sig,
                                             sizeof (struct TALER_RSA_Signature)));
  return TALER_MINT_reply_json (connection,
                                root,
                                MHD_HTTP_OK);
}


/**
 * Send a response for "/refresh/melt".
 *
 * @param connection the connection to send the response to
 * @param db_conn the database connection to fetch values from
 * @param session_pub the refresh session public key.
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_melt_success (struct MHD_Connection *connection,
                                       const struct RefreshSession *session,
                                       const struct GNUNET_CRYPTO_EddsaPublicKey *session_pub)
{
  json_t *root;
  json_t *list;
  struct GNUNET_HashContext *hash_context;
  struct RefreshMeltResponseSignatureBody body;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  json_t *sig_json;

  root = json_object ();
  list = json_array ();
  json_object_set_new (root, "blind_session_pubs", list);
  hash_context = GNUNET_CRYPTO_hash_context_start ();
  body.purpose.size = htonl (sizeof (struct RefreshMeltResponseSignatureBody));
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_MELT_RESPONSE);
  /* FIXME: should we not add something to the hash_context in the meantime? */
  GNUNET_CRYPTO_hash_context_finish (hash_context, &body.melt_response_hash);
  TALER_MINT_keys_sign (&body.purpose,
                        &sig);
  sig_json = TALER_JSON_from_sig (&body.purpose, &sig);
  GNUNET_assert (NULL != sig_json);
  json_object_set (root, "signature", sig_json);

  return TALER_MINT_reply_json (connection,
                                root,
                                MHD_HTTP_OK);
}


/**
 * Send a response to a "/refresh/commit" request.
 *
 * FIXME: maybe not the ideal argument type for @a refresh_session here.
 *
 * @param connection the connection to send the response to
 * @param refresh_session the refresh session
 * @return a MHD status code
 */
int
TALER_MINT_reply_refresh_commit_success (struct MHD_Connection *connection,
                                         struct RefreshSession *refresh_session)
{
  struct RefreshCommitResponseSignatureBody body;
  struct GNUNET_CRYPTO_EddsaSignature sig;
  json_t *sig_json;

  body.purpose.size = htonl (sizeof (struct RefreshCommitResponseSignatureBody));
  body.purpose.purpose = htonl (TALER_SIGNATURE_REFRESH_COMMIT_RESPONSE);
  body.noreveal_index = htons (refresh_session->noreveal_index);
  TALER_MINT_keys_sign (&body.purpose,
                        &sig);
  sig_json = TALER_JSON_from_sig (&body.purpose, &sig);
  GNUNET_assert (NULL != sig_json);
  return TALER_MINT_reply_json_pack (connection,
                                     MHD_HTTP_OK,
                                     "{s:i, s:o}",
                                     "noreveal_index", (int) refresh_session->noreveal_index,
                                     "signature", sig_json);
}


/**
 * Send a response for "/refresh/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_newcoins number of new coins for which we reveal data
 * @param sigs array of @a num_newcoins signatures revealed
 * @return a MHD result code
 */
int
TALER_MINT_reply_refresh_reveal_success (struct MHD_Connection *connection,
                                         unsigned int num_newcoins,
                                         const struct TALER_RSA_Signature *sigs)
{
  int newcoin_index;
  json_t *root;
  json_t *list;

  root = json_object ();
  list = json_array ();
  json_object_set_new (root, "ev_sigs", list);
  for (newcoin_index = 0; newcoin_index < num_newcoins; newcoin_index++)
    json_array_append_new (list,
                           TALER_JSON_from_data (&sigs[newcoin_index],
                                                 sizeof (struct TALER_RSA_Signature)));
  return TALER_MINT_reply_json (connection,
                                root,
                                MHD_HTTP_OK);

}



/* end of taler-mint-httpd_responses.c */
