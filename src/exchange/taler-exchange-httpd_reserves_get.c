/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
#include "taler-exchange-httpd_keys.h"
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
   * Our request context.
   */
  struct TEH_RequestContext *rc;

  /**
   * Subscription for the database event we are waiting for.
   */
  struct GNUNET_DB_EventHandler *eh;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * Public key of the reserve the inquiry is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Balance of the reserve, set in the callback.
   */
  struct TALER_Amount balance;

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
  for (struct ReservePoller *rp = rp_head;
       NULL != rp;
       rp = rp->next)
  {
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

  GNUNET_assert (! rp->suspended);
  if (NULL != rp->eh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Cancelling DB event listening on cleanup (odd unless during shutdown)\n");
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     rp->eh);
    rp->eh = NULL;
  }
  GNUNET_CONTAINER_DLL_remove (rp_head,
                               rp_tail,
                               rp);
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
  struct ReservePoller *rp = cls;
  struct GNUNET_AsyncScopeSave old_scope;

  (void) extra;
  (void) extra_size;
  if (! rp->suspended)
    return; /* might get multiple wake-up events */
  GNUNET_async_scope_enter (&rp->rc->async_scope_id,
                            &old_scope);
  TEH_check_invariants ();
  rp->suspended = false;
  MHD_resume_connection (rp->connection);
  TALER_MHD_daemon_trigger ();
  TEH_check_invariants ();
  GNUNET_async_scope_restore (&old_scope);
}


MHD_RESULT
TEH_handler_reserves_get (struct TEH_RequestContext *rc,
                          const char *const args[1])
{
  struct ReservePoller *rp = rc->rh_ctx;

  if (NULL == rp)
  {
    rp = GNUNET_new (struct ReservePoller);
    rp->connection = rc->connection;
    rp->rc = rc;
    rc->rh_ctx = rp;
    rc->rh_cleaner = &rp_cleanup;
    GNUNET_CONTAINER_DLL_insert (rp_head,
                                 rp_tail,
                                 rp);
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &rp->reserve_pub,
                                       sizeof (rp->reserve_pub)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_RESERVE_PUB_MALFORMED,
                                         args[0]);
    }
    TALER_MHD_parse_request_timeout (rc->connection,
                                     &rp->timeout);
  }

  if ( (GNUNET_TIME_absolute_is_future (rp->timeout)) &&
       (NULL == rp->eh) )
  {
    struct TALER_ReserveEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_RESERVE_INCOMING),
      .reserve_pub = rp->reserve_pub
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Starting DB event listening until %s\n",
                GNUNET_TIME_absolute2s (rp->timeout));
    rp->eh = TEH_plugin->event_listen (
      TEH_plugin->cls,
      GNUNET_TIME_absolute_get_remaining (rp->timeout),
      &rep.header,
      &db_event_cb,
      rp);
  }
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_reserve_balance (TEH_plugin->cls,
                                          &rp->reserve_pub,
                                          &rp->balance);
    switch (qs)
    {
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0); /* single-shot query should never have soft-errors */
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                         "get_reserve_balance");
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "get_reserve_balance");
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Got reserve balance of %s\n",
                  TALER_amount2s (&rp->balance));
      return TALER_MHD_REPLY_JSON_PACK (rc->connection,
                                        MHD_HTTP_OK,
                                        TALER_JSON_pack_amount ("balance",
                                                                &rp->balance));
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      if (! GNUNET_TIME_absolute_is_future (rp->timeout))
      {
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                           args[0]);
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Long-polling on reserve for %s\n",
                  GNUNET_STRINGS_relative_time_to_string (
                    GNUNET_TIME_absolute_get_remaining (rp->timeout),
                    true));
      rp->suspended = true;
      MHD_suspend_connection (rc->connection);
      return MHD_YES;
    }
  }
  GNUNET_break (0);
  return MHD_NO;
}


/* end of taler-exchange-httpd_reserves_get.c */
