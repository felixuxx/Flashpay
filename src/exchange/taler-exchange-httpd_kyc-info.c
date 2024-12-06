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
 * @file taler-exchange-httpd_kyc-info.c
 * @brief Handle request for generic KYC info.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_exchangedb_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_kyc-info.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_common_kyc.h"


/**
 * Context for the GET /kyc-info request.
 *
 * Used for long-polling and other asynchronous waiting.
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
   * Handle to async activity to get the latest legitimization
   * rule set.
   */
  struct TALER_EXCHANGEDB_RuleUpdater *ru;

  /**
   * #MHD_HTTP_HEADER_IF_NONE_MATCH Etag value sent by the client.  0 for none
   * (or malformed).
   */
  uint64_t etag_outcome_in;

  /**
   * #MHD_HTTP_HEADER_IF_NONE_MATCH Etag value sent by the client.  0 for none
   * (or malformed).
   */
  uint64_t etag_measure_in;

  /**
   * When will this request time out?
   */
  struct GNUNET_TIME_Absolute timeout;

  /**
   * Set to access token for a KYC process by the account,
   * if @e have_token is true.
   */
  struct TALER_AccountAccessTokenP access_token;

  /**
   * Payto hash of the account matching @a access_token.
   */
  struct TALER_NormalizedPaytoHashP h_payto;


  /**
   * Current legitimization rule set, owned by callee.  Will be NULL on error
   * or for default rules. Will not contain skip rules and not be expired.
   */
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs;

  /**
   *
   */
  uint64_t legitimization_measure_last_row;

  /**
   * Row in the legitimization outcomes table that @e lrs matches.
   */
  uint64_t legitimization_outcome_last_row;

  /**
   * True if we are still suspended.
   */
  bool suspended;

  /**
   * Handle for async KYC processing.
   */
  struct TEH_KycMeasureRunContext *kat;

  /**
   * HTTP status code to use with @e response.
   */
  unsigned int response_code;

  /**
   * Response to return, NULL if none yet.
   */
  struct MHD_Response *response;

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
TEH_kyc_info_cleanup ()
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
  if (NULL != kyp->ru)
  {
    TALER_EXCHANGEDB_update_rules_cancel (kyp->ru);
    kyp->ru = NULL;
  }
  if (NULL != kyp->response)
  {
    MHD_destroy_response (kyp->response);
    kyp->response = NULL;
  }
  if (NULL != kyp->lrs)
  {
    TALER_KYCLOGIC_rules_free (kyp->lrs);
    kyp->lrs = NULL;
  }
  if (NULL != kyp->kat)
  {
    TEH_kyc_run_measure_cancel (kyp->kat);
    kyp->kat = NULL;
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
  GNUNET_async_scope_enter (&rc->async_scope_id,
                            &old_scope);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Resuming from long-polling on KYC status\n");
  GNUNET_CONTAINER_DLL_remove (kyp_head,
                               kyp_tail,
                               kyp);
  kyp->suspended = false;
  MHD_resume_connection (kyp->connection);
  TALER_MHD_daemon_trigger ();
  GNUNET_async_scope_restore (&old_scope);
}


/**
 * Add the headers we want to set for every response.
 *
 * @param[in,out] response the response to modify
 */
static void
add_nocache_header (struct MHD_Response *response)
{
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CACHE_CONTROL,
                                         "no-cache"));
}


/**
 * Resume processing the @a kyp request with the @a response.
 *
 * @param kyp request to resume and respond to
 * @param http_status HTTP status for @a response
 * @param response HTTP response to return
 */
static void
resume_with_response (struct KycPoller *kyp,
                      unsigned int http_status,
                      struct MHD_Response *response)
{
  kyp->response_code = http_status;
  kyp->response = response;
  GNUNET_CONTAINER_DLL_remove (kyp_head,
                               kyp_tail,
                               kyp);
  kyp->suspended = false;
  MHD_resume_connection (kyp->connection);
  TALER_MHD_daemon_trigger ();
}


/**
 * Function called after a measure has been run.
 *
 * @param kyp request to fail with the error code
 * @param ec error code or 0 on success
 * @param hint detail error message or NULL on success / no info
 */
static void
fail_with_ec (
  struct KycPoller *kyp,
  enum TALER_ErrorCode ec,
  const char *hint)
{
  resume_with_response (kyp,
                        TALER_ErrorCode_get_http_status (ec),
                        TALER_MHD_make_error (ec,
                                              hint));
}


/**
 * Generate a reply with the KycProcessClientInformation from
 * the LegitimizationMeasures.
 *
 * @param[in,out] kyp request to reply on
 * @param legitimization_measure_row_id part of etag to set for the response
 * @param legitimization_outcome_row_id part of etag to set for the response
 * @param jmeasures a `LegitimizationMeasures` object to encode
 * @param jvoluntary array of voluntary measures to encode, can be NULL
 */
static void
resume_with_reply (struct KycPoller *kyp,
                   uint64_t legitimization_measure_row_id,
                   uint64_t legitimization_outcome_row_id,
                   const json_t *jmeasures,
                   const json_t *jvoluntary)
{
  const json_t *measures; /* array of MeasureInformation */
  bool is_and_combinator = false;
  bool verboten;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_bool ("is_and_combinator",
                             &is_and_combinator),
      NULL),
    GNUNET_JSON_spec_bool ("verboten",
                           &verboten),
    GNUNET_JSON_spec_array_const ("measures",
                                  &measures),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_GenericReturnValue ret;
  const char *ename;
  unsigned int eline;
  json_t *kris;
  size_t i;
  json_t *mi; /* a MeasureInformation object */

  ret = GNUNET_JSON_parse (jmeasures,
                           spec,
                           &ename,
                           &eline);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    fail_with_ec (kyp,
                  TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
                  ename);
    return;
  }
  kris = json_array ();
  GNUNET_assert (NULL != kris);
  json_array_foreach ((json_t *) measures, i, mi)
  {
    const char *check_name;
    const char *prog_name;
    const json_t *context = NULL;
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_string ("check_name",
                               &check_name),
      GNUNET_JSON_spec_string ("prog_name",
                               &prog_name),
      GNUNET_JSON_spec_mark_optional (
        GNUNET_JSON_spec_object_const ("context",
                                       &context),
        NULL),
      GNUNET_JSON_spec_end ()
    };
    json_t *kri;

    ret = GNUNET_JSON_parse (mi,
                             ispec,
                             &ename,
                             &eline);
    if (GNUNET_OK != ret)
    {
      GNUNET_break (0);
      json_decref (kris);
      fail_with_ec (
        kyp,
        TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
        ename);
      return;
    }
    kri = TALER_KYCLOGIC_measure_to_requirement (
      check_name,
      prog_name,
      context,
      &kyp->access_token,
      i,
      legitimization_measure_row_id);
    if (NULL == kri)
    {
      GNUNET_break (0);
      json_decref (kris);
      fail_with_ec (
        kyp,
        TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
        "could not convert measure to requirement");
      return;
    }
    GNUNET_assert (0 ==
                   json_array_append_new (kris,
                                          kri));
  }

  {
    char etags[128];
    struct MHD_Response *resp;

    GNUNET_snprintf (etags,
                     sizeof (etags),
                     "\"%llu-%llu\"",
                     (unsigned long long) legitimization_measure_row_id,
                     (unsigned long long) legitimization_outcome_row_id);
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_array_steal ("requirements",
                                    kris),
      GNUNET_JSON_pack_bool ("is_and_combinator",
                             is_and_combinator),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_array_incref (
          "voluntary_measures",
          (json_t *) jvoluntary)));
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           MHD_HTTP_HEADER_ETAG,
                                           etags));
    add_nocache_header (resp);
    resume_with_response (kyp,
                          MHD_HTTP_OK,
                          resp);
  }
}


/**
 * Function called with the current rule set.
 *
 * @param cls closure with a `struct KycPoller *`
 * @param rur includes legitimziation rule set that applies to the account
 *   (owned by callee, callee must free the lrs!)
 */
static void
current_rules_cb (
  void *cls,
  struct TALER_EXCHANGEDB_RuleUpdaterResult *rur)
{
  struct KycPoller *kyp = cls;
  enum GNUNET_DB_QueryStatus qs;
  uint64_t legitimization_measure_last_row;
  json_t *jmeasures;

  kyp->ru = NULL;
  if (TALER_EC_NONE != rur->ec)
  {
    /* Rollback should not be needed, just to be sure */
    TEH_plugin->rollback (TEH_plugin->cls);
    fail_with_ec (kyp,
                  rur->ec,
                  rur->hint);
    return;
  }
  GNUNET_assert (NULL == kyp->lrs);
  kyp->lrs
    = rur->lrs;
  kyp->legitimization_outcome_last_row
    = rur->legitimization_outcome_last_row;

  qs = TEH_plugin->lookup_kyc_status_by_token (
    TEH_plugin->cls,
    &kyp->access_token,
    &legitimization_measure_last_row,
    &jmeasures);
  if (qs < 0)
  {
    GNUNET_break (0);
    TEH_plugin->rollback (TEH_plugin->cls);
    fail_with_ec (
      kyp,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      "lookup_kyc_status_by_token");
    return;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    jmeasures
      = TALER_KYCLOGIC_zero_measures (kyp->lrs);
    if (NULL == jmeasures)
    {
      qs = TEH_plugin->commit (TEH_plugin->cls);
      if (qs < 0)
      {
        TEH_plugin->rollback (TEH_plugin->cls);
        fail_with_ec (
          kyp,
          TALER_EC_GENERIC_DB_COMMIT_FAILED,
          "kyc-info");
        return;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "No KYC requirement open\n");
      resume_with_response (kyp,
                            MHD_HTTP_OK,
                            TALER_MHD_MAKE_JSON_PACK (
                              GNUNET_JSON_pack_allow_null (
                                GNUNET_JSON_pack_array_steal (
                                  "voluntary_measures",
                                  TALER_KYCLOGIC_voluntary_measures
                                    (kyp->lrs))
                                )));
      return;
    }

    qs = TEH_plugin->insert_active_legitimization_measure (
      TEH_plugin->cls,
      &kyp->access_token,
      jmeasures,
      &legitimization_measure_last_row);
    if (qs < 0)
    {
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls);
      fail_with_ec (kyp,
                    TALER_EC_GENERIC_DB_STORE_FAILED,
                    "insert_active_legitimization_measure");
      return;
    }
  }
  if ( (legitimization_measure_last_row == kyp->etag_measure_in) &&
       (kyp->legitimization_outcome_last_row == kyp->etag_outcome_in) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout) )
  {
    /* Note: in practice this commit should do nothing, but we cannot
       trust that the client provided correct etags, and so we must
       commit anyway just in case the client lied about the etags. */
    qs = TEH_plugin->commit (TEH_plugin->cls);
    if (qs < 0)
    {
      TEH_plugin->rollback (TEH_plugin->cls);
      fail_with_ec (
        kyp,
        TALER_EC_GENERIC_DB_COMMIT_FAILED,
        "kyc-info");
      return;
    }
    if (NULL != kyp->lrs)
    {
      TALER_KYCLOGIC_rules_free (kyp->lrs);
      kyp->lrs = NULL;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Suspending HTTP request on timeout (%s)\n",
                GNUNET_TIME_relative2s (
                  GNUNET_TIME_absolute_get_remaining (
                    kyp->timeout),
                  true));
    GNUNET_assert (NULL != kyp->eh);
    GNUNET_break (kyp->suspended);
    return;
  }
  if ( (legitimization_measure_last_row ==
        kyp->etag_measure_in) &&
       (kyp->legitimization_outcome_last_row ==
        kyp->etag_outcome_in) )
  {
    char etags[128];
    struct MHD_Response *resp;

    GNUNET_snprintf (etags,
                     sizeof (etags),
                     "\"%llu-%llu\"",
                     (unsigned long long) legitimization_measure_last_row,
                     (unsigned long long) kyp->legitimization_outcome_last_row);
    resp = MHD_create_response_from_buffer (0,
                                            NULL,
                                            MHD_RESPMEM_PERSISTENT);
    add_nocache_header (resp);
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           MHD_HTTP_HEADER_ETAG,
                                           etags));
    resume_with_response (kyp,
                          MHD_HTTP_NOT_MODIFIED,
                          resp);
    json_decref (jmeasures);
    return;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Generating success reply to kyc-info query\n");
  resume_with_reply (kyp,
                     legitimization_measure_last_row,
                     kyp->legitimization_outcome_last_row,
                     jmeasures,
                     TALER_KYCLOGIC_voluntary_measures (kyp->lrs));
  json_decref (jmeasures);
}


MHD_RESULT
TEH_handler_kyc_info (
  struct TEH_RequestContext *rc,
  const char *const args[1])
{
  struct KycPoller *kyp = rc->rh_ctx;
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == kyp)
  {
    kyp = GNUNET_new (struct KycPoller);
    kyp->connection = rc->connection;
    rc->rh_ctx = kyp;
    rc->rh_cleaner = &kyp_cleanup;

    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (
          args[0],
          strlen (args[0]),
          &kyp->access_token,
          sizeof (kyp->access_token)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "access token");
    }
    TALER_MHD_parse_request_timeout (rc->connection,
                                     &kyp->timeout);

    /* Get etag */
    {
      const char *etags;

      etags = MHD_lookup_connection_value (
        rc->connection,
        MHD_HEADER_KIND,
        MHD_HTTP_HEADER_IF_NONE_MATCH);
      if (NULL != etags)
      {
        char dummy;
        unsigned long long ev1;
        unsigned long long ev2;

        if (2 != sscanf (etags,
                         "\"%llu-%llu\"%c",
                         &ev1,
                         &ev2,
                         &dummy))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                      "Client send malformed `%s' header `%s'\n",
                      MHD_HTTP_HEADER_IF_NONE_MATCH,
                      etags);
        }
        else
        {
          kyp->etag_measure_in = (uint64_t) ev1;
          kyp->etag_outcome_in = (uint64_t) ev2;
        }
      }
    } /* etag */

    /* Check access token */
    qs = TEH_plugin->lookup_h_payto_by_access_token (
      TEH_plugin->cls,
      &kyp->access_token,
      &kyp->h_payto);
    if (qs < 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "lookup_h_payto_by_access_token");
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      GNUNET_break_op (0);
      return TALER_MHD_REPLY_JSON_PACK (
        rc->connection,
        MHD_HTTP_FORBIDDEN,
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_INFO_AUTHORIZATION_FAILED));
    }

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
  } /* end of one-time initialization */

  if (NULL != kyp->response)
  {
    return MHD_queue_response (rc->connection,
                               kyp->response_code,
                               kyp->response);
  }

  kyp->ru = TALER_EXCHANGEDB_update_rules (TEH_plugin,
                                           &TEH_attribute_key,
                                           &kyp->h_payto,
                                           &current_rules_cb,
                                           kyp);
  kyp->suspended = true;
  GNUNET_CONTAINER_DLL_insert (kyp_head,
                               kyp_tail,
                               kyp);
  MHD_suspend_connection (rc->connection);
  return MHD_YES;

}


/* end of taler-exchange-httpd_kyc-info.c */
