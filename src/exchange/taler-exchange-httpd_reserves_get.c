/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file taler-exchange-httpd_reserves_get.c
 * @brief Handle /reserves/$RESERVE_PUB GET requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_reserves_get.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Reserve GET request that is long-polling.
 */
struct ReservePoller
{
  /**
   * Kept in a DLL.
   */
  struct ReservePoller *next;

  /**
   * Kept in a DLL.
   */
  struct ReservePoller *prev;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * Subscription for the database event we are
   * waiting for.
   */
  struct TALER_EXCHANGEDB_EventHandler *eh;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * True if we are still suspended.
   */
  bool suspended;

};


/**
 * Head of list of requests in long polling.
 */
static struct ReservePoller *rp_head;

/**
 * Tail of list of requests in long polling.
 */
static struct ReservePoller *rp_tail;


void
TEH_reserves_get_cleanup ()
{
  struct ReservePoller *rp;

  while (NULL != (rp = rp_head))
  {
    GNUNET_CONTAINER_DLL_remove (rp_head,
                                 rp_tail,
                                 rp);
    if (rp->suspended)
    {
      rp->suspended = false;
      MHD_resume_connection (rp->connection);
    }
  }
}


/**
 * Function called once a connection is done to
 * clean up the `struct ReservePoller` state.
 *
 * @param rc context to clean up for
 */
static void
rp_cleanup (struct TEH_RequestContext *rc)
{
  struct ReservePoller *rp = rc->rh_ctx;

  if (NULL != rp->eh)
  {
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     rp->eh);
    rp->eh = NULL;
  }
  GNUNET_free (rp);
}


/**
 * Function called on events received from Postgres.
 * Wakes up long pollers.
 *
 * @param cls the `struct TEH_RequestContext *`
 * @param extra additional event data provided
 * @param extra_size number of bytes in @a extra
 */
static void
db_event_cb (void *cls,
             const void *extra,
             size_t extra_size)
{
  struct TEH_RequestContext *rc = cls;
  struct ReservePoller *rp = rc->rh_ctx;
  struct GNUNET_AsyncScopeSave old_scope;

  (void) extra;
  (void) extra_size;
  if (NULL == rp)
    return; /* event triggered while main transaction
               was still running */
  if (! rp->suspended)
    return; /* might get multiple wake-up events */
  rp->suspended = false;
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Resuming from long-polling on reserve\n");
  GNUNET_CONTAINER_DLL_remove (rp_head,
                               rp_tail,
                               rp);
  MHD_resume_connection (rp->connection);
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Send reserve history to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_history_success (struct MHD_Connection *connection,
                               const struct TALER_EXCHANGEDB_ReserveHistory *rh)
{
  json_t *json_history;
  struct TALER_Amount balance;

  json_history = TEH_RESPONSE_compile_reserve_history (rh,
                                                       &balance);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("balance",
                            &balance),
    GNUNET_JSON_pack_array_steal ("history",
                                  json_history));
}


/**
 * Closure for #reserve_history_transaction.
 */
struct ReserveHistoryContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * History of the reserve, set in the callback.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

};


/**
 * Function implementing /reserves/ GET transaction.
 * Execute a /reserves/ GET.  Given the public key of a reserve,
 * return the associated transaction history.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveHistoryContext *`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_history_transaction (void *cls,
                             struct MHD_Connection *connection,
                             struct TALER_EXCHANGEDB_Session *session,
                             MHD_RESULT *mhd_ret)
{
  struct ReserveHistoryContext *rsc = cls;

  (void) connection;
  (void) mhd_ret;
  return TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                          session,
                                          &rsc->reserve_pub,
                                          &rsc->rh);
}


MHD_RESULT
TEH_handler_reserves_get (struct TEH_RequestContext *rc,
                          const char *const args[1])
{
  struct ReserveHistoryContext rsc;
  MHD_RESULT mhd_ret;
  struct GNUNET_TIME_Relative timeout = GNUNET_TIME_UNIT_ZERO;
  struct TALER_EXCHANGEDB_EventHandler *eh = NULL;

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &rsc.reserve_pub,
                                     sizeof (rsc.reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_MERCHANT_GENERIC_RESERVE_PUB_MALFORMED,
                                       args[0]);
  }
  {
    const char *long_poll_timeout_ms;

    long_poll_timeout_ms
      = MHD_lookup_connection_value (rc->connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "timeout_ms");
    if (NULL != long_poll_timeout_ms)
    {
      unsigned int timeout_ms;
      char dummy;

      if (1 != sscanf (long_poll_timeout_ms,
                       "%u%c",
                       &timeout_ms,
                       &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "timeout_ms (must be non-negative number)");
      }
      timeout = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                               timeout_ms);
    }
  }
  if (! GNUNET_TIME_relative_is_zero (timeout))
  {
    struct TALER_ReserveEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_RESERVE_INCOMING),
      .reserve_pub = rsc.reserve_pub
    };

    eh = TEH_plugin->event_listen (TEH_plugin->cls,
                                   timeout,
                                   &rep.header,
                                   &db_event_cb,
                                   rc);
  }
  rsc.rh = NULL;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "get reserve history",
                              &mhd_ret,
                              &reserve_history_transaction,
                              &rsc))
    return mhd_ret;
  /* generate proper response */
  if (NULL == rsc.rh)
  {
    struct ReservePoller *rp = rc->rh_ctx;

    if ( (NULL != rp) ||
         (GNUNET_TIME_relative_is_zero (timeout)) )
    {
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_RESERVES_GET_STATUS_UNKNOWN,
                                         args[0]);
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Long-polling on reserve for %s\n",
                GNUNET_STRINGS_relative_time_to_string (timeout,
                                                        GNUNET_YES));
    rp = GNUNET_new (struct ReservePoller);
    rp->connection = rc->connection;
    rp->timeout = GNUNET_TIME_relative_to_absolute (timeout);
    rp->eh = eh;
    rc->rh_ctx = rp;
    rc->rh_cleaner = &rp_cleanup;
    rp->suspended = true;
    GNUNET_CONTAINER_DLL_insert (rp_head,
                                 rp_tail,
                                 rp);
    MHD_suspend_connection (rc->connection);
    return MHD_YES;
  }
  mhd_ret = reply_reserve_history_success (rc->connection,
                                           rsc.rh);
  TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                    rsc.rh);
  return mhd_ret;
}


/* end of taler-exchange-httpd_reserves_get.c */
