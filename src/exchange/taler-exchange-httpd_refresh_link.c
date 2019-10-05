/*
  This file is part of TALER
  Copyright (C) 2014-2019 Taler Systems SA

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
 * Closure for #handle_transfer_data().
 */
struct HTD_Context
{

  /**
   * Public key of the coin for which we are running /refresh/link.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Json array with transfer data we collect.
   */
  json_t *mlist;

  /**
   * Taler error code.
   */
  enum TALER_ErrorCode ec;
};


/**
 * Function called with the session hashes and transfer secret
 * information for a given coin.  Gets the linkage data and
 * builds the reply for the client.
 *
 *
 * @param cls closure, a `struct HTD_Context`
 * @param transfer_pub public transfer key for the session
 * @param ldl link data related to @a transfer_pub
 */
static void
handle_link_data (void *cls,
                  const struct TALER_TransferPublicKeyP *transfer_pub,
                  const struct TALER_EXCHANGEDB_LinkDataList *ldl)
{
  struct HTD_Context *ctx = cls;
  json_t *list;
  json_t *root;

  if (NULL == ctx->mlist)
    return;
  if (NULL == (list = json_array ()))
    goto fail;

  for (const struct TALER_EXCHANGEDB_LinkDataList *pos = ldl;
       NULL != pos;
       pos = pos->next)
  {
    json_t *obj;

    if (NULL == (obj = json_object ()))
      goto fail;
    json_object_set_new (obj,
                         "denom_pub",
                         GNUNET_JSON_from_rsa_public_key (
                           pos->denom_pub.rsa_public_key));
    json_object_set_new (obj,
                         "ev_sig",
                         GNUNET_JSON_from_rsa_signature (
                           pos->ev_sig.rsa_signature));
    json_object_set_new (obj,
                         "link_sig",
                         GNUNET_JSON_from_data_auto (&pos->orig_coin_link_sig));
    if (0 !=
        json_array_append_new (list,
                               obj))
      goto fail;
  }
  if (NULL == (root = json_object ()))
    goto fail;
  json_object_set_new (root,
                       "new_coins",
                       list);
  json_object_set_new (root,
                       "transfer_pub",
                       GNUNET_JSON_from_data_auto (transfer_pub));
  if (0 !=
      json_array_append_new (ctx->mlist,
                             root))
    goto fail;
  return;
fail:
  ctx->ec = TALER_EC_JSON_ALLOCATION_FAILURE;
  json_decref (ctx->mlist);
  ctx->mlist = NULL;
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

  qs = TEH_plugin->get_link_data (TEH_plugin->cls,
                                  session,
                                  &ctx->coin_pub,
                                  &handle_link_data,
                                  ctx);
  if (NULL == ctx->mlist)
  {
    *mhd_ret = TEH_RESPONSE_reply_internal_error (connection,
                                                  ctx->ec,
                                                  "coin_pub");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TEH_RESPONSE_reply_arg_unknown (connection,
                                               TALER_EC_REFRESH_LINK_COIN_UNKNOWN,
                                               "coin_pub");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
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
                                        sizeof (struct
                                                TALER_CoinSpendPublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if (GNUNET_OK != res)
    return MHD_YES;
  ctx.mlist = json_array ();
  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "run link",
                              &mhd_ret,
                              &refresh_link_transaction,
                              &ctx))
  {
    if (NULL != ctx.mlist)
      json_decref (ctx.mlist);
    return mhd_ret;
  }
  mhd_ret = TEH_RESPONSE_reply_json (connection,
                                     ctx.mlist,
                                     MHD_HTTP_OK);
  json_decref (ctx.mlist);
  return mhd_ret;
}


/* end of taler-exchange-httpd_refresh_link.c */
