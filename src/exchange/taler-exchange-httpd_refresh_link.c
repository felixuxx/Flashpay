/*
  This file is part of TALER
  Copyright (C) 2014-2017 Inria & GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_refresh_link.c
 * @brief Handle /refresh/link requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_refresh_link.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * @brief Information for each session a coin was melted into.
 */
struct TEH_RESPONSE_LinkSessionInfo
{
  /**
   * Transfer public key of the coin.
   */
  struct TALER_TransferPublicKeyP transfer_pub;

  /**
   * Linked data of coins being created in the session.
   */
  struct TALER_EXCHANGEDB_LinkDataList *ldl;

};


/**
 * Closure for #handle_transfer_data().
 */
struct HTD_Context
{

  /**
   * Session link data we collect.
   */
  struct TEH_RESPONSE_LinkSessionInfo *sessions;

  /**
   * Database session. Nothing to do with @a sessions.
   */
  struct TALER_EXCHANGEDB_Session *session;

  /**
   * MHD connection, for queueing replies.
   */
  struct MHD_Connection *connection;

  /**
   * Number of sessions the coin was melted into.
   */
  unsigned int num_sessions;

  /**
   * How are we expected to proceed. #GNUNET_SYSERR if we
   * failed to return an error (should return #MHD_NO).
   * #GNUNET_NO if we succeeded in queueing an MHD error
   * (should return #MHD_YES from #TEH_execute_refresh_link),
   * #GNUNET_OK if we should call #reply_refresh_link_success().
   */
  int status;
};


/**
 * Send a response for "/refresh/link".
 *
 * @param connection the connection to send the response to
 * @param num_sessions number of sessions the coin was used in
 * @param sessions array of @a num_session entries with
 *                  information for each session
 * @return a MHD result code
 */
static int
reply_refresh_link_success (struct MHD_Connection *connection,
			    unsigned int num_sessions,
			    const struct TEH_RESPONSE_LinkSessionInfo *sessions)
{
  json_t *root;
  json_t *mlist;
  int res;
  unsigned int i;

  mlist = json_array ();
  for (i=0;i<num_sessions;i++)
  {
    const struct TALER_EXCHANGEDB_LinkDataList *pos;
    json_t *list = json_array ();

    for (pos = sessions[i].ldl; NULL != pos; pos = pos->next)
    {
      json_t *obj;

      obj = json_object ();
      json_object_set_new (obj,
                           "denom_pub",
                           GNUNET_JSON_from_rsa_public_key (pos->denom_pub.rsa_public_key));
      json_object_set_new (obj,
                           "ev_sig",
                           GNUNET_JSON_from_rsa_signature (pos->ev_sig.rsa_signature));
      GNUNET_assert (0 ==
                     json_array_append_new (list,
                                            obj));
    }
    root = json_object ();
    json_object_set_new (root,
                         "new_coins",
                         list);
    json_object_set_new (root,
                         "transfer_pub",
                         GNUNET_JSON_from_data_auto (&sessions[i].transfer_pub));
    GNUNET_assert (0 ==
                   json_array_append_new (mlist,
                                          root));
  }
  res = TEH_RESPONSE_reply_json (connection,
                                 mlist,
                                 MHD_HTTP_OK);
  json_decref (mlist);
  return res;
}


/**
 * Function called with the session hashes and transfer secret
 * information for a given coin.  Gets the linkage data and
 * builds the reply for the client.
 *
 *
 * @param cls closure, a `struct HTD_Context`
 * @param session_hash a session the coin was melted in
 * @param transfer_pub public transfer key for the session
 */
static void
handle_transfer_data (void *cls,
                      const struct GNUNET_HashCode *session_hash,
                      const struct TALER_TransferPublicKeyP *transfer_pub)
{
  struct HTD_Context *ctx = cls;
  struct TALER_EXCHANGEDB_LinkDataList *ldl;
  struct TEH_RESPONSE_LinkSessionInfo *lsi;

  if (GNUNET_OK != ctx->status)
    return;
  ldl = TEH_plugin->get_link_data_list (TEH_plugin->cls,
                                        ctx->session,
                                        session_hash);
  if (NULL == ldl)
  {
    ctx->status = GNUNET_NO;
    if (MHD_NO ==
        TEH_RESPONSE_reply_json_pack (ctx->connection,
                                      MHD_HTTP_NOT_FOUND,
                                      "{s:s}",
                                      "error",
                                      "link data not found (link)"))
      ctx->status = GNUNET_SYSERR;
    return;
  }
  GNUNET_array_grow (ctx->sessions,
                     ctx->num_sessions,
                     ctx->num_sessions + 1);
  lsi = &ctx->sessions[ctx->num_sessions - 1];
  lsi->transfer_pub = *transfer_pub;
  lsi->ldl = ldl;
}


/**
 * Execute a "/refresh/link".  Returns the linkage information that
 * will allow the owner of a coin to follow the refresh trail to
 * the refreshed coin.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin to link
 * @return MHD result code
 */
static int
execute_refresh_link (struct MHD_Connection *connection,
		      const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  struct HTD_Context ctx;
  int res;
  unsigned int i;

  if (NULL == (ctx.session = TEH_plugin->get_session (TEH_plugin->cls)))
  {
    GNUNET_break (0);
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_DB_SETUP_FAILED);
  }
  ctx.connection = connection;
  ctx.num_sessions = 0;
  ctx.sessions = NULL;
  ctx.status = GNUNET_OK;
  res = TEH_plugin->get_transfer (TEH_plugin->cls,
                                  ctx.session,
                                  coin_pub,
                                  &handle_transfer_data,
                                  &ctx);
  if (GNUNET_SYSERR == ctx.status)
  {
    res = MHD_NO;
    goto cleanup;
  }
  if (GNUNET_NO == ctx.status)
  {
    res = MHD_YES;
    goto cleanup;
  }
  GNUNET_assert (GNUNET_OK == ctx.status);
  if (0 == ctx.num_sessions)
    return TEH_RESPONSE_reply_arg_unknown (connection,
					   TALER_EC_REFRESH_LINK_COIN_UNKNOWN,
                                           "coin_pub");
  res = reply_refresh_link_success (connection,
				    ctx.num_sessions,
				    ctx.sessions);
 cleanup:
  for (i=0;i<ctx.num_sessions;i++)
    TEH_plugin->free_link_data_list (TEH_plugin->cls,
                                     ctx.sessions[i].ldl);
  GNUNET_free_non_null (ctx.sessions);
  return res;
}


/**
 * Handle a "/refresh/link" request.  Note that for "/refresh/link"
 * we do use a simple HTTP GET, and a HTTP POST!
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_REFRESH_handler_refresh_link (struct TEH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  struct TALER_CoinSpendPublicKeyP coin_pub;
  int res;

  res = TEH_PARSE_mhd_request_arg_data (connection,
                                        "coin_pub",
                                        &coin_pub,
                                        sizeof (struct TALER_CoinSpendPublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if (GNUNET_OK != res)
    return MHD_YES;
  return execute_refresh_link (connection,
			       &coin_pub);
}


/* end of taler-exchange-httpd_refresh_link.c */
