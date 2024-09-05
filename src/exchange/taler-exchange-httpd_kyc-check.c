/*
  This file is part of TALER
  Copyright (C) 2021-2024 Taler Systems SA

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
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_kyc-check.h"
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
   * Account for which we perform the KYC check.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * Signature by the account owner authorizing this
   * operation.
   */
  union TALER_AccountSignatureP account_sig;

  /**
   * True if we are still suspended.
   */
  bool suspended;

  /**
   * True if we are long polling for a KYC authorization
   * wire transfer.
   */
  bool await_auth;

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
  const char *const args[1])
{
  struct KycPoller *kyp = rc->rh_ctx;
  json_t *jrules = NULL;
  json_t *jlimits = NULL;
  union TALER_AccountPublicKeyP account_pub;
  union TALER_AccountPublicKeyP reserve_pub;
  struct TALER_AccountAccessTokenP access_token;
  bool aml_review;
  bool kyc_required;

  if (NULL == kyp)
  {
    bool sig_required = true;

    kyp = GNUNET_new (struct KycPoller);
    kyp->connection = rc->connection;
    rc->rh_ctx = kyp;
    rc->rh_cleaner = &kyp_cleanup;

    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &kyp->h_payto,
                                       sizeof (kyp->h_payto)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PATH_SEGMENT_MALFORMED,
        "h_payto");
    }

    TALER_MHD_parse_request_header_auto (
      rc->connection,
      TALER_HTTP_HEADER_ACCOUNT_OWNER_SIGNATURE,
      &kyp->account_sig,
      sig_required);
    TALER_MHD_parse_request_timeout (rc->connection,
                                     &kyp->timeout);
    {
      enum TALER_EXCHANGE_YesNoAll yna;

      TALER_MHD_parse_request_yna (rc->connection,
                                   "await_auth",
                                   TALER_EXCHANGE_YNA_NO,
                                   &yna);
      kyp->await_auth = (TALER_EXCHANGE_YNA_YES == yna);
    }
    /* long polling needed? */
    if (GNUNET_TIME_absolute_is_future (kyp->timeout))
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
  } /* end initialization */

  if (! TEH_enable_kyc)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC not enabled\n");
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Looking up KYC requirements for account %s\n",
                TALER_B2S (&kyp->h_payto));
    qs = TEH_plugin->lookup_kyc_requirement_by_row (
      TEH_plugin->cls,
      &kyp->h_payto,
      &account_pub,
      &reserve_pub.reserve_pub,
      &access_token,
      &jrules,
      &aml_review,
      &kyc_required);
    if (qs < 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "lookup_kyc_requirement_by_row");
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      /* account unknown */
      if ( (kyp->await_auth) &&
           (GNUNET_TIME_absolute_is_future (kyp->timeout)) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Suspending HTTP request on timeout (%s) now...\n",
                    GNUNET_TIME_relative2s (GNUNET_TIME_absolute_get_remaining (
                                              kyp->timeout),
                                            true));
        GNUNET_assert (NULL != kyp->eh);
        kyp->suspended = true;
        GNUNET_CONTAINER_DLL_insert (kyp_head,
                                     kyp_tail,
                                     kyp);
        MHD_suspend_connection (kyp->connection);
        return MHD_YES;
      }
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_KYC_CHECK_REQUEST_UNKNOWN,
        NULL);
    }
  }

  if ( (GNUNET_is_zero (&account_pub) ||
        (GNUNET_OK !=
         TALER_account_kyc_auth_verify (&account_pub,
                                        &kyp->account_sig)) ) &&
       (GNUNET_is_zero (&reserve_pub) ||
        (GNUNET_OK !=
         TALER_account_kyc_auth_verify (&reserve_pub,
                                        &kyp->account_sig)) ) )
  {
    json_decref (jrules);
    jrules = NULL;
    if (GNUNET_is_zero (&account_pub))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_CONFLICT,
        TALER_EC_EXCHANGE_KYC_CHECK_AUTHORIZATION_KEY_UNKNOWN,
        NULL);
    }
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_FORBIDDEN,
      TALER_JSON_pack_ec (
        TALER_EC_EXCHANGE_KYC_CHECK_AUTHORIZATION_FAILED),
      GNUNET_JSON_pack_data_auto ("expected_account_pub",
                                  &account_pub));
  }

  jlimits = TALER_KYCLOGIC_rules_to_limits (jrules);
  if (NULL == jlimits)
  {
    GNUNET_break_op (0);
    json_decref (jrules);
    jrules = NULL;
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
      "/kyc-check: rules_to_limits failed");
  }
  json_decref (jrules);
  jrules = NULL;

  if ( (kyc_required) &&
       (! kyp->await_auth) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Suspending HTTP request on timeout (%s) now...\n",
                GNUNET_TIME_relative2s (GNUNET_TIME_absolute_get_remaining (
                                          kyp->timeout),
                                        true));
    GNUNET_assert (NULL != kyp->eh);
    kyp->suspended = true;
    GNUNET_CONTAINER_DLL_insert (kyp_head,
                                 kyp_tail,
                                 kyp);
    MHD_suspend_connection (kyp->connection);
    return MHD_YES;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Returning KYC %s\n",
              kyc_required ? "required" : "optional");
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    kyc_required
      ? MHD_HTTP_ACCEPTED
      : MHD_HTTP_OK,
    GNUNET_JSON_pack_bool ("aml_review",
                           aml_review),
    GNUNET_JSON_pack_data_auto ("access_token",
                                &access_token),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_array_steal ("limits",
                                    jlimits)));
}


/* end of taler-exchange-httpd_kyc-check.c */
