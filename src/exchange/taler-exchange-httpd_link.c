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
 * @file taler-exchange-httpd_link.c
 * @brief Handle /coins/$COIN_PUB/link requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_link.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for #handle_link_data().
 */
struct HTD_Context
{

  /**
   * Public key of the coin for which we are running link.
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
 * @param cls closure, a `struct HTD_Context`
 * @param transfer_pub public transfer key for the session
 * @param ldl link data related to @a transfer_pub
 */
static void
handle_link_data (void *cls,
                  const struct TALER_TransferPublicKeyP *transfer_pub,
                  const struct TALER_EXCHANGEDB_LinkList *ldl)
{
  struct HTD_Context *ctx = cls;
  json_t *list;

  if (NULL == ctx->mlist)
    return; /* we failed earlier */
  if (NULL == (list = json_array ()))
    goto fail;

  for (const struct TALER_EXCHANGEDB_LinkList *pos = ldl;
       NULL != pos;
       pos = pos->next)
  {
    json_t *obj;

    obj = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_rsa_public_key ("denom_pub",
                                       pos->denom_pub.rsa_public_key),
      GNUNET_JSON_pack_rsa_signature ("ev_sig",
                                      pos->ev_sig.rsa_signature),
      GNUNET_JSON_pack_data_auto ("link_sig",
                                  &pos->orig_coin_link_sig));
    if ( (NULL == obj) ||
         (0 !=
          json_array_append_new (list,
                                 obj)) )
    {
      json_decref (list);
      goto fail;
    }
  }
  {
    json_t *root;

    root = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_array_steal ("new_coins",
                                    list),
      GNUNET_JSON_pack_data_auto ("transfer_pub",
                                  transfer_pub));
    if ( (NULL == root) ||
         (0 !=
          json_array_append_new (ctx->mlist,
                                 root)) )
      goto fail;
  }
  return;
fail:
  ctx->ec = TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE;
  json_decref (ctx->mlist);
  ctx->mlist = NULL;
}


/**
 * Execute a link operation.  Returns the linkage information that will allow
 * the owner of a coin to follow the trail to the refreshed coin.
 *
 * If it returns a non-error code, the transaction logic MUST NOT queue a MHD
 * response.  IF it returns an hard error, the transaction logic MUST queue a
 * MHD response and set @a mhd_ret.  IF it returns the soft error code, the
 * function MAY be called again to retry and MUST not queue a MHD response.
 *
 * @param cls closure
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
link_transaction (void *cls,
                  struct MHD_Connection *connection,
                  struct TALER_EXCHANGEDB_Session *session,
                  MHD_RESULT *mhd_ret)
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
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           ctx->ec,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_LINK_COIN_UNKNOWN,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * Handle a "/coins/$COIN_PUB/link" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (length: 2, first is the coin_pub, second must be "link")
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_link (const struct TEH_RequestHandler *rh,
                  struct MHD_Connection *connection,
                  const char *const args[2])
{
  struct HTD_Context ctx;
  MHD_RESULT mhd_ret;

  (void) rh;
  memset (&ctx,
          0,
          sizeof (ctx));
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &ctx.coin_pub,
                                     sizeof (ctx.coin_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_COINS_INVALID_COIN_PUB,
                                       args[0]);
  }
  ctx.mlist = json_array ();
  if (NULL == ctx.mlist)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       "json_array() call failed");
  }
  if (GNUNET_OK !=
      TEH_DB_run_transaction (connection,
                              "run link",
                              &mhd_ret,
                              &link_transaction,
                              &ctx))
  {
    if (NULL != ctx.mlist)
      json_decref (ctx.mlist);
    return mhd_ret;
  }
  mhd_ret = TALER_MHD_reply_json (connection,
                                  ctx.mlist,
                                  MHD_HTTP_OK);
  json_decref (ctx.mlist);
  return mhd_ret;
}


/* end of taler-exchange-httpd_link.c */
