/*
  This file is part of TALER
  Copyright (C) 2021-2023 Taler Systems SA

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
   * Logic for @e ih
   */
  struct TALER_KYCLOGIC_Plugin *ih_logic;

  /**
   * Handle to asynchronously running KYC initiation
   * request.
   */
  struct TALER_KYCLOGIC_InitiateHandle *ih;

  /**
   * Subscription for the database event we are
   * waiting for.
   */
  struct GNUNET_DB_EventHandler *eh;

  /**
   * Row of the requirement being checked.
   */
  uint64_t requirement_row;

  /**
   * Row of KYC process being initiated.
   */
  uint64_t process_row;

  /**
   * Hash of the payto:// URI we are confirming to
   * have finished the KYC for.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * If the KYC complete, what kind of data was collected?
   */
  json_t *kyc_details;

  /**
   * Set to starting URL of KYC process if KYC is required.
   */
  char *kyc_url;

  /**
   * Set to error details, on error (@ec not TALER_EC_NONE).
   */
  char *hint;

  /**
   * Name of the section of the provider in the configuration.
   */
  const char *section_name;

  /**
   * Set to error encountered with KYC logic, if any.
   */
  enum TALER_ErrorCode ec;

  /**
   * What kind of entity is doing the KYC check?
   */
  enum TALER_KYCLOGIC_KycUserType ut;

  /**
   * True if we are still suspended.
   */
  bool suspended;

  /**
   * False if KYC is not required.
   */
  bool kyc_required;

  /**
   * True if we once tried the KYC initiation.
   */
  bool ih_done;

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
    if (NULL != kyp->ih)
    {
      kyp->ih_logic->initiate_cancel (kyp->ih);
      kyp->ih = NULL;
    }
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
  if (NULL != kyp->ih)
  {
    kyp->ih_logic->initiate_cancel (kyp->ih);
    kyp->ih = NULL;
  }
  json_decref (kyp->kyc_details);
  GNUNET_free (kyp->kyc_url);
  GNUNET_free (kyp->hint);
  GNUNET_free (kyp);
}


/**
 * Function called with the result of a KYC initiation
 * operation.
 *
 * @param cls closure with our `struct KycPoller *`
 * @param ec #TALER_EC_NONE on success
 * @param redirect_url set to where to redirect the user on success, NULL on failure
 * @param provider_user_id set to user ID at the provider, or NULL if not supported or unknown
 * @param provider_legitimization_id set to legitimization process ID at the provider, or NULL if not supported or unknown
 * @param error_msg_hint set to additional details to return to user, NULL on success
 */
static void
initiate_cb (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *redirect_url,
  const char *provider_user_id,
  const char *provider_legitimization_id,
  const char *error_msg_hint)
{
  struct KycPoller *kyp = cls;
  enum GNUNET_DB_QueryStatus qs;

  kyp->ih = NULL;
  kyp->ih_done = true;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "KYC initiation completed with ec=%d (%s)\n",
              ec,
              (TALER_EC_NONE == ec)
              ? redirect_url
              : error_msg_hint);
  kyp->ec = ec;
  if (TALER_EC_NONE == ec)
  {
    kyp->kyc_url = GNUNET_strdup (redirect_url);
  }
  else
  {
    kyp->hint = GNUNET_strdup (error_msg_hint);
  }
  qs = TEH_plugin->update_kyc_process_by_row (
    TEH_plugin->cls,
    kyp->process_row,
    kyp->section_name,
    &kyp->h_payto,
    provider_user_id,
    provider_legitimization_id,
    GNUNET_TIME_UNIT_ZERO_ABS);
  if (qs < 0)
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYC requirement update failed for %s with status %d at %s:%u\n",
                TALER_B2S (&kyp->h_payto),
                qs,
                __FILE__,
                __LINE__);
  GNUNET_assert (kyp->suspended);
  kyp->suspended = false;
  GNUNET_CONTAINER_DLL_remove (kyp_head,
                               kyp_tail,
                               kyp);
  MHD_resume_connection (kyp->connection);
  TALER_MHD_daemon_trigger ();
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
  struct TALER_KYCLOGIC_ProviderDetails *pd;
  enum GNUNET_GenericReturnValue ret;
  struct TALER_PaytoHashP h_payto;
  char *requirements;
  bool satisfied;

  qs = TEH_plugin->lookup_kyc_requirement_by_row (
    TEH_plugin->cls,
    kyp->requirement_row,
    &requirements,
    &h_payto);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No KYC requirements open for %llu\n",
                (unsigned long long) kyp->requirement_row);
    return qs;
  }
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR != qs);
    return qs;
  }
  if (0 !=
      GNUNET_memcmp (&kyp->h_payto,
                     &h_payto))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Requirement %llu provided, but h_payto does not match\n",
                (unsigned long long) kyp->requirement_row);
    GNUNET_break_op (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_FORBIDDEN,
                                           TALER_EC_EXCHANGE_KYC_CHECK_AUTHORIZATION_FAILED,
                                           "h_payto");
    GNUNET_free (requirements);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  qs = TALER_KYCLOGIC_check_satisfied (
    &requirements,
    &h_payto,
    &kyp->kyc_details,
    TEH_plugin->select_satisfied_kyc_processes,
    TEH_plugin->cls,
    &satisfied);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "kyc_test_required");
    GNUNET_free (requirements);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (satisfied)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC requirements `%s' already satisfied\n",
                requirements);
    GNUNET_free (requirements);
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }

  kyp->kyc_required = true;
  ret = TALER_KYCLOGIC_requirements_to_logic (requirements,
                                              kyp->ut,
                                              &kyp->ih_logic,
                                              &pd,
                                              &kyp->section_name);
  if (GNUNET_OK != ret)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "KYC requirements `%s' cannot be checked, but are set as required in database!\n",
                requirements);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_EXCHANGE_KYC_GENERIC_LOGIC_GONE,
                                           requirements);
    GNUNET_free (requirements);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_free (requirements);

  if (kyp->ih_done)
    return qs;

  qs = TEH_plugin->insert_kyc_requirement_process (
    TEH_plugin->cls,
    &h_payto,
    kyp->section_name,
    NULL,
    NULL,
    &kyp->process_row);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "insert_kyc_requirement_process");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Initiating KYC check with logic %s\n",
              kyp->ih_logic->name);
  kyp->ih = kyp->ih_logic->initiate (kyp->ih_logic->cls,
                                     pd,
                                     &h_payto,
                                     kyp->process_row,
                                     &initiate_cb,
                                     kyp);
  GNUNET_break (NULL != kyp->ih);
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
  const char *const args[3])
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
      unsigned long long requirement_row;
      char dummy;

      if (1 !=
          sscanf (args[0],
                  "%llu%c",
                  &requirement_row,
                  &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "requirement_row");
      }
      kyp->requirement_row = (uint64_t) requirement_row;
    }

    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[1],
                                       strlen (args[1]),
                                       &kyp->h_payto,
                                       sizeof (kyp->h_payto)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         "h_payto");
    }

    if (GNUNET_OK !=
        TALER_KYCLOGIC_kyc_user_type_from_string (args[2],
                                                  &kyp->ut))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         "usertype");
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
  }

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
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Transaction failed.\n");
    return res;
  }

  if ( (NULL == kyp->ih) &&
       (! kyp->kyc_required) )
  {
    /* KYC not required */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "KYC not required %llu\n",
                (unsigned long long) kyp->requirement_row);
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);
  }

  if (NULL != kyp->ih)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Suspending HTTP request on KYC logic...\n");
    kyp->suspended = true;
    GNUNET_CONTAINER_DLL_insert (kyp_head,
                                 kyp_tail,
                                 kyp);
    MHD_suspend_connection (kyp->connection);
    return MHD_YES;
  }

  /* long polling? */
  if ( (NULL != kyp->section_name) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Suspending HTTP request on timeout (%s) now...\n",
                GNUNET_TIME_relative2s (GNUNET_TIME_absolute_get_duration (
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

  /* KYC plugin generated reply? */
  if (NULL != kyp->kyc_url)
  {
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_ACCEPTED,
      GNUNET_JSON_pack_string ("kyc_url",
                               kyp->kyc_url));
  }

  if (TALER_EC_NONE != kyp->ec)
  {
    return TALER_MHD_reply_with_ec (rc->connection,
                                    kyp->ec,
                                    kyp->hint);
  }

  /* KYC must have succeeded! */
  {
    struct TALER_ExchangePublicKeyP pub;
    struct TALER_ExchangeSignatureP sig;
    enum TALER_ErrorCode ec;

    if (TALER_EC_NONE !=
        (ec = TALER_exchange_online_account_setup_success_sign (
           &TEH_keys_exchange_sign_,
           &kyp->h_payto,
           kyp->kyc_details,
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
      GNUNET_JSON_pack_object_incref ("kyc_details",
                                      kyp->kyc_details),
      GNUNET_JSON_pack_timestamp ("now",
                                  now));
  }
}


/* end of taler-exchange-httpd_kyc-check.c */
