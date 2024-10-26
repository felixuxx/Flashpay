/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file taler-exchange-httpd_purses_get.c
 * @brief Handle GET /purses/$PID/$TARGET requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_purses_get.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Information about an ongoing /purses GET operation.
 */
struct GetContext
{
  /**
   * Kept in a DLL.
   */
  struct GetContext *next;

  /**
   * Kept in a DLL.
   */
  struct GetContext *prev;

  /**
   * Connection we are handling.
   */
  struct MHD_Connection *connection;

  /**
   * Subscription for the database event we are
   * waiting for.
   */
  struct GNUNET_DB_EventHandler *eh;

  /**
   * Subscription for refund event we are
   * waiting for.
   */
  struct GNUNET_DB_EventHandler *ehr;

  /**
   * Public key of our purse.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * When does this purse expire?
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * When was this purse merged?
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * How much is the purse (supposed) to be worth?
   */
  struct TALER_Amount amount;

  /**
   * How much was deposited into the purse so far?
   */
  struct TALER_Amount deposited;

  /**
   * Hash over the contract of the purse.
   */
  struct TALER_PrivateContractHashP h_contract;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * true to wait for merge, false to wait for deposit.
   */
  bool wait_for_merge;

  /**
   * True if we are still suspended.
   */
  bool suspended;
};


/**
 * Head of DLL of suspended GET requests.
 */
static struct GetContext *gc_head;

/**
 * Tail of DLL of suspended GET requests.
 */
static struct GetContext *gc_tail;


void
TEH_purses_get_cleanup ()
{
  struct GetContext *gc;

  while (NULL != (gc = gc_head))
  {
    GNUNET_CONTAINER_DLL_remove (gc_head,
                                 gc_tail,
                                 gc);
    if (gc->suspended)
    {
      gc->suspended = false;
      MHD_resume_connection (gc->connection);
    }
  }
}


/**
 * Function called once a connection is done to
 * clean up the `struct GetContext` state.
 *
 * @param rc context to clean up for
 */
static void
gc_cleanup (struct TEH_RequestContext *rc)
{
  struct GetContext *gc = rc->rh_ctx;

  GNUNET_assert (! gc->suspended);
  if (NULL != gc->eh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Cancelling DB event listening\n");
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     gc->eh);
    gc->eh = NULL;
  }
  if (NULL != gc->ehr)
  {
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     gc->ehr);
    gc->ehr = NULL;
  }
  GNUNET_free (gc);
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
  struct GetContext *gc = rc->rh_ctx;
  struct GNUNET_AsyncScopeSave old_scope;

  (void) extra;
  (void) extra_size;
  if (NULL == gc)
    return; /* event triggered while main transaction
               was still running */
  if (! gc->suspended)
    return; /* might get multiple wake-up events */
  gc->suspended = false;
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Waking up on %p - %p - %s\n",
              rc,
              gc,
              gc->suspended ? "suspended" : "active");
  TEH_check_invariants ();
  GNUNET_CONTAINER_DLL_remove (gc_head,
                               gc_tail,
                               gc);
  MHD_resume_connection (gc->connection);
  TALER_MHD_daemon_trigger ();
  TEH_check_invariants ();
  GNUNET_async_scope_restore (&old_scope);
}


MHD_RESULT
TEH_handler_purses_get (struct TEH_RequestContext *rc,
                        const char *const args[2])
{
  struct GetContext *gc = rc->rh_ctx;
  bool purse_deleted;
  bool purse_refunded;
  MHD_RESULT res;

  if (NULL == gc)
  {
    gc = GNUNET_new (struct GetContext);
    rc->rh_ctx = gc;
    rc->rh_cleaner = &gc_cleanup;
    gc->connection = rc->connection;
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &gc->purse_pub,
                                       sizeof (gc->purse_pub)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_PURSE_PUB_MALFORMED,
                                         args[0]);
    }
    if (0 == strcmp (args[1],
                     "merge"))
      gc->wait_for_merge = true;
    else if (0 == strcmp (args[1],
                          "deposit"))
      gc->wait_for_merge = false;
    else
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_PURSES_INVALID_WAIT_TARGET,
                                         args[1]);
    }

    TALER_MHD_parse_request_timeout (rc->connection,
                                     &gc->timeout);
    if ( (GNUNET_TIME_absolute_is_future (gc->timeout)) &&
         (NULL == gc->eh) )
    {
      struct TALER_PurseEventP rep = {
        .header.size = htons (sizeof (rep)),
        .header.type = htons (
          gc->wait_for_merge
          ? TALER_DBEVENT_EXCHANGE_PURSE_MERGED
          : TALER_DBEVENT_EXCHANGE_PURSE_DEPOSITED),
        .purse_pub = gc->purse_pub
      };

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Starting DB event listening on purse %s (%s)\n",
                  TALER_B2S (&gc->purse_pub),
                  gc->wait_for_merge
                  ? "waiting for merge"
                  : "waiting for deposit");
      gc->eh = TEH_plugin->event_listen (
        TEH_plugin->cls,
        GNUNET_TIME_absolute_get_remaining (gc->timeout),
        &rep.header,
        &db_event_cb,
        rc);
      if (NULL == gc->eh)
      {
        GNUNET_break (0);
        gc->timeout = GNUNET_TIME_UNIT_ZERO_ABS;
      }
      else
      {
        struct GNUNET_DB_EventHeaderP repr = {
          .size = htons (sizeof (repr)),
          .type = htons (TALER_DBEVENT_EXCHANGE_PURSE_REFUNDED),
        };

        gc->ehr = TEH_plugin->event_listen (
          TEH_plugin->cls,
          GNUNET_TIME_absolute_get_remaining (gc->timeout),
          &repr,
          &db_event_cb,
          rc);
      }
    }
  } /* end first-time initialization */

  {
    enum GNUNET_DB_QueryStatus qs;
    struct GNUNET_TIME_Timestamp create_timestamp;

    qs = TEH_plugin->select_purse (TEH_plugin->cls,
                                   &gc->purse_pub,
                                   &create_timestamp,
                                   &gc->purse_expiration,
                                   &gc->amount,
                                   &gc->deposited,
                                   &gc->h_contract,
                                   &gc->merge_timestamp,
                                   &purse_deleted,
                                   &purse_refunded);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "select_purse %s returned %d (%s)\n",
                args[0],
                (int) qs,
                GNUNET_TIME_timestamp2s (gc->merge_timestamp));
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "select_purse");
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "select_purse");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_PURSE_UNKNOWN,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break; /* handled below */
    }
  }
  if (purse_refunded ||
      purse_deleted)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Purse refunded or deleted\n");
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_GONE,
                                       purse_deleted
                                       ? TALER_EC_EXCHANGE_GENERIC_PURSE_DELETED
                                       : TALER_EC_EXCHANGE_GENERIC_PURSE_EXPIRED
                                       ,
                                       GNUNET_TIME_timestamp2s (
                                         gc->purse_expiration));
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Deposited amount is %s (%d/%d/%d)\n",
              TALER_amount2s (&gc->deposited),
              GNUNET_TIME_absolute_is_future (gc->timeout),
              GNUNET_TIME_absolute_is_never (gc->merge_timestamp.abs_time),
              (0 <
               TALER_amount_cmp (&gc->amount,
                                 &gc->deposited)));
  if (GNUNET_TIME_absolute_is_future (gc->timeout) &&
      ( ((gc->wait_for_merge) &&
         GNUNET_TIME_absolute_is_never (gc->merge_timestamp.abs_time)) ||
        ((! gc->wait_for_merge) &&
         (0 <
          TALER_amount_cmp (&gc->amount,
                            &gc->deposited))) ) )
  {
    gc->suspended = true;
    GNUNET_CONTAINER_DLL_insert (gc_head,
                                 gc_tail,
                                 gc);
    MHD_suspend_connection (gc->connection);
    return MHD_YES;
  }

  {
    struct GNUNET_TIME_Timestamp dt = GNUNET_TIME_timestamp_get ();
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_ExchangeSignatureP exchange_sig;
    enum TALER_ErrorCode ec;

    if (GNUNET_TIME_timestamp_cmp (dt,
                                   >,
                                   gc->purse_expiration))
      dt = gc->purse_expiration;
    if (0 <
        TALER_amount_cmp (&gc->amount,
                          &gc->deposited))
    {
      /* amount > deposited: not yet fully paid */
      dt = GNUNET_TIME_UNIT_ZERO_TS;
    }
    if (TALER_EC_NONE !=
        (ec = TALER_exchange_online_purse_status_sign (
           &TEH_keys_exchange_sign_,
           gc->merge_timestamp,
           dt,
           &gc->deposited,
           &exchange_pub,
           &exchange_sig)))
    {
      res = TALER_MHD_reply_with_ec (rc->connection,
                                     ec,
                                     NULL);
    }
    else
    {
      /* Make sure merge_timestamp is omitted if not yet merged */
      if (GNUNET_TIME_absolute_is_never (gc->merge_timestamp.abs_time))
        gc->merge_timestamp = GNUNET_TIME_UNIT_ZERO_TS;
      res = TALER_MHD_REPLY_JSON_PACK (
        rc->connection,
        MHD_HTTP_OK,
        TALER_JSON_pack_amount ("balance",
                                &gc->deposited),
        GNUNET_JSON_pack_data_auto ("exchange_sig",
                                    &exchange_sig),
        GNUNET_JSON_pack_data_auto ("exchange_pub",
                                    &exchange_pub),
        GNUNET_JSON_pack_timestamp ("purse_expiration",
                                    gc->purse_expiration),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                      gc->merge_timestamp)),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_timestamp ("deposit_timestamp",
                                      dt))
        );
    }
  }
  return res;
}


/* end of taler-exchange-httpd_purses_get.c */
