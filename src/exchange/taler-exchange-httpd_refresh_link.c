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
   * Public key of the coin that we are tracing.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

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
  json_t *mlist;
  int res;

  mlist = json_array ();
  for (unsigned int i=0;i<num_sessions;i++)
  {
    json_t *list = json_array ();
    json_t *root;

    for (const struct TALER_EXCHANGEDB_LinkDataList *pos = sessions[i].ldl;
	 NULL != pos;
	 pos = pos->next)
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
  enum GNUNET_DB_QueryStatus qs;

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != ctx->status)
    return;
  ldl = NULL;
  qs = TEH_plugin->get_link_data_list (TEH_plugin->cls,
				       ctx->session,
				       session_hash,
				       &ldl);
  if (qs <= 0) 
  {
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      ctx->status = GNUNET_DB_STATUS_HARD_ERROR;
    else
      ctx->status = qs;
    return;
  }
  GNUNET_assert (NULL != ldl);
  GNUNET_array_grow (ctx->sessions,
                     ctx->num_sessions,
                     ctx->num_sessions + 1);
  lsi = &ctx->sessions[ctx->num_sessions - 1];
  lsi->transfer_pub = *transfer_pub;
  lsi->ldl = ldl;
}


/**
 * Free session data kept in @a ctx
 *
 * @param ctx context to clean up
 */
static void
purge_context (struct HTD_Context *ctx)
{
  for (unsigned int i=0;i<ctx->num_sessions;i++)
    TEH_plugin->free_link_data_list (TEH_plugin->cls,
				     ctx->sessions[i].ldl);
  GNUNET_free_non_null (ctx->sessions);
  ctx->sessions = NULL;
  ctx->num_sessions = 0;
}


/**
 * Execute a "/refresh/link".  Returns the linkage information that
 * will allow the owner of a coin to follow the refresh trail to
 * the refreshed coin.
 *
 * If it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refresh_link_transaction (void *cls,
			  struct MHD_Connection *connection,
			  struct TALER_EXCHANGEDB_Session *session,
			  int *mhd_ret)
{
  struct HTD_Context *ctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  ctx->session = session;
  ctx->status = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qs = TEH_plugin->get_transfer (TEH_plugin->cls,
				 session,
				 &ctx->coin_pub,
				 &handle_transfer_data,
				 ctx);
  ctx->session = NULL;
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TEH_RESPONSE_reply_arg_unknown (connection,
					       TALER_EC_REFRESH_LINK_COIN_UNKNOWN,
					       "coin_pub");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (0 < qs)
  {
    qs = ctx->status;
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      *mhd_ret = TEH_RESPONSE_reply_json_pack (ctx->connection,
					       MHD_HTTP_NOT_FOUND,
					       "{s:s}",
					       "error",
					       "link data not found (link)");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    return qs;
  }
  purge_context (ctx);
  return qs;
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
  int mhd_ret;
  int res;
  struct HTD_Context ctx;

  memset (&ctx,
	  0,
	  sizeof (ctx));
  res = TEH_PARSE_mhd_request_arg_data (connection,
                                        "coin_pub",
                                        &ctx.coin_pub,
                                        sizeof (struct TALER_CoinSpendPublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if (GNUNET_OK != res)
    return MHD_YES;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
			      &mhd_ret,
			      &refresh_link_transaction,
			      &ctx))
  {
    purge_context (&ctx);
    return mhd_ret;
  }
  mhd_ret = reply_refresh_link_success (connection,
					ctx.num_sessions,
					ctx.sessions);
  purge_context (&ctx);
  return mhd_ret;
}


/* end of taler-exchange-httpd_refresh_link.c */
