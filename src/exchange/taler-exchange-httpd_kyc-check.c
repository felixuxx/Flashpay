/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-check.c
 * @brief Handle request for generic KYC check.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Reserve GET request that is long-polling.
 */
struct KycPoller
{
  /**
   * Kept in a DLL.
   */
  struct KycPoller *next;

  /**
   * Kept in a DLL.
   */
  struct KycPoller *prev;

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
   * UUID being checked.
   */
  uint64_t auth_payment_target_uuid;

  /**
   * Current KYC status.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash of the payto:// URI we are confirming to
   * have finished the KYC for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Payto URL as a string, as given to us by t
   */
  const char *hps;

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
static struct KycPoller *kyp_head;

/**
 * Tail of list of requests in long polling.
 */
static struct KycPoller *kyp_tail;


void
TEH_kyc_check_cleanup ()
{
  struct KycPoller *kyp;

  while (NULL != (kyp = kyp_head))
  {
    GNUNET_CONTAINER_DLL_remove (kyp_head,
                                 kyp_tail,
                                 kyp);
    if (kyp->suspended)
    {
      kyp->suspended = false;
      MHD_resume_connection (kyp->connection);
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
kyp_cleanup (struct TEH_RequestContext *rc)
{
  struct KycPoller *kyp = rc->rh_ctx;

  GNUNET_assert (! kyp->suspended);
  if (NULL != kyp->eh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Cancelling DB event listening\n");
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     kyp->eh);
    kyp->eh = NULL;
  }
  GNUNET_free (kyp);
}


/**
 * Function implementing database transaction to check wallet's KYC status.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct KycPoller *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
kyc_check (void *cls,
           struct MHD_Connection *connection,
           MHD_RESULT *mhd_ret)
{
  struct KycPoller *kyp = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->select_kyc_status (TEH_plugin->cls,
                                      &kyp->h_payto,
                                      &kyp->kyc);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "inselect_wallet_status");
    return qs;
  }
  return qs;
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
  struct KycPoller *kyp = rc->rh_ctx;
  struct GNUNET_AsyncScopeSave old_scope;

  (void) extra;
  (void) extra_size;
  if (! kyp->suspended)
    return; /* event triggered while main transaction
               was still running, or got multiple wake-up events */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received KYC update event\n");
  kyp->suspended = false;
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  TEH_check_invariants ();
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Resuming from long-polling on KYC status\n");
  GNUNET_CONTAINER_DLL_remove (kyp_head,
                               kyp_tail,
                               kyp);
  MHD_resume_connection (kyp->connection);
  TALER_MHD_daemon_trigger ();
  TEH_check_invariants ();
  GNUNET_async_scope_restore (&old_scope);
}


MHD_RESULT
TEH_handler_kyc_check (
  struct TEH_RequestContext *rc,
  const char *const args[])
{
  struct KycPoller *kyp = rc->rh_ctx;
  MHD_RESULT res;
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_TIME_Timestamp now;

  if (NULL == kyp)
  {
    kyp = GNUNET_new (struct KycPoller);
    kyp->connection = rc->connection;
    rc->rh_ctx = kyp;
    rc->rh_cleaner = &kyp_cleanup;

    {
      unsigned long long payment_target_uuid;
      char dummy;

      if (1 !=
          sscanf (args[0],
                  "%llu%c",
                  &payment_target_uuid,
                  &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "payment_target_uuid");
      }
      kyp->auth_payment_target_uuid = (uint64_t) payment_target_uuid;
    }
    {
      const char *ts;

      ts = MHD_lookup_connection_value (rc->connection,
                                        MHD_GET_ARGUMENT_KIND,
                                        "timeout_ms");
      if (NULL != ts)
      {
        char dummy;
        unsigned long long tms;

        if (1 !=
            sscanf (ts,
                    "%llu%c",
                    &tms,
                    &dummy))
        {
          GNUNET_break_op (0);
          return TALER_MHD_reply_with_error (rc->connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                             "timeout_ms");
        }
        kyp->timeout = GNUNET_TIME_relative_to_absolute (
          GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                         tms));
      }
    }
    kyp->hps = MHD_lookup_connection_value (rc->connection,
                                            MHD_GET_ARGUMENT_KIND,
                                            "h_payto");
    if (NULL == kyp->hps)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MISSING,
                                         "h_payto");
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (kyp->hps,
                                       strlen (kyp->hps),
                                       &kyp->h_payto,
                                       sizeof (kyp->h_payto)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         "h_payto");
    }
  }

  if (TEH_KYC_NONE == TEH_kyc_config.mode)
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);

  if ( (NULL == kyp->eh) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout) )
  {
    struct TALER_KycCompletedEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED),
      .h_payto = kyp->h_payto
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Starting DB event listening\n");
    kyp->eh = TEH_plugin->event_listen (
      TEH_plugin->cls,
      GNUNET_TIME_absolute_get_remaining (kyp->timeout),
      &rep.header,
      &db_event_cb,
      rc);
  }

  now = GNUNET_TIME_timestamp_get ();
  ret = TEH_DB_run_transaction (rc->connection,
                                "kyc check",
                                TEH_MT_REQUEST_OTHER,
                                &res,
                                &kyc_check,
                                kyp);
  if (GNUNET_SYSERR == ret)
    return res;

  if (kyp->auth_payment_target_uuid !=
      kyp->kyc.payment_target_uuid)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Account %llu provided, but payto %s is for %llu\n",
                (unsigned long long) kyp->auth_payment_target_uuid,
                kyp->hps,
                (unsigned long long) kyp->kyc.payment_target_uuid);
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       TALER_EC_EXCHANGE_KYC_CHECK_AUTHORIZATION_FAILED,
                                       "h_payto");
  }

  /* long polling? */
  if ( (! kyp->kyc.ok) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout))
  {
    GNUNET_assert (NULL != kyp->eh);
    kyp->suspended = true;
    GNUNET_CONTAINER_DLL_insert (kyp_head,
                                 kyp_tail,
                                 kyp);
    MHD_suspend_connection (kyp->connection);
    return MHD_YES;
  }

  /* KYC failed? */
  if (! kyp->kyc.ok)
  {
    char *url;
    char *redirect_uri;
    char *redirect_uri_encoded;

    GNUNET_assert (TEH_KYC_OAUTH2 == TEH_kyc_config.mode);
    GNUNET_asprintf (&redirect_uri,
                     "%s/kyc-proof/%s",
                     TEH_base_url,
                     kyp->hps);
    redirect_uri_encoded = TALER_urlencode (redirect_uri);
    GNUNET_free (redirect_uri);
    GNUNET_asprintf (&url,
                     "%s?client_id=%s&redirect_uri=%s",
                     TEH_kyc_config.details.oauth2.login_url,
                     TEH_kyc_config.details.oauth2.client_id,
                     redirect_uri_encoded);
    GNUNET_free (redirect_uri_encoded);

    res = TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_ACCEPTED,
      GNUNET_JSON_pack_string ("kyc_url",
                               url));
    GNUNET_free (url);
    return res;
  }

  /* KYC succeeded! */
  {
    struct TALER_ExchangePublicKeyP pub;
    struct TALER_ExchangeSignatureP sig;
    enum TALER_ErrorCode ec;

    if (TALER_EC_NONE !=
        (ec = TALER_exchange_online_account_setup_success_sign (
           &TEH_keys_exchange_sign_,
           &kyp->h_payto,
           now,
           &pub,
           &sig)))
    {
      return TALER_MHD_reply_with_ec (rc->connection,
                                      ec,
                                      NULL);
    }
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_data_auto ("exchange_sig",
                                  &sig),
      GNUNET_JSON_pack_data_auto ("exchange_pub",
                                  &pub),
      GNUNET_JSON_pack_timestamp ("now",
                                  now));
  }
}


/* end of taler-exchange-httpd_kyc-check.c */
