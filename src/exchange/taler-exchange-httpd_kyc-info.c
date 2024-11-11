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
  if (NULL != kyp->response)
  {
    MHD_destroy_response (kyp->response);
    kyp->response = NULL;
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
 * @param cls the key state to use
 * @param[in,out] response the response to modify
 */
static void
add_response_headers (void *cls,
                      struct MHD_Response *response)
{
  (void) cls;
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (response,
                                         MHD_HTTP_HEADER_CACHE_CONTROL,
                                         "no-cache"));
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
 * @return MHD status code
 */
static MHD_RESULT
generate_reply (struct KycPoller *kyp,
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
    return TALER_MHD_reply_with_ec (
      kyp->connection,
      TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
      ename);
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
      return TALER_MHD_reply_with_ec (
        kyp->connection,
        TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
        ename);
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
      return TALER_MHD_reply_with_ec (
        kyp->connection,
        TALER_EC_GENERIC_DB_INVARIANT_FAILURE,
        "could not convert measure to requirement");
    }
    GNUNET_assert (0 ==
                   json_array_append_new (kris,
                                          kri));
  }

  {
    char etags[128];
    struct MHD_Response *resp;
    MHD_RESULT res;

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
    add_response_headers (NULL,
                          resp);
    res = MHD_queue_response (kyp->connection,
                              MHD_HTTP_OK,
                              resp);
    GNUNET_break (MHD_YES == res);
    MHD_destroy_response (resp);
    return res;
  }
}


/**
 * Check if measures contain an instant
 * measure.
 *
 * @param jmeasures measures JSON object
 * @returns true if @a jmeasures contains an instant measure
 */
static bool
contains_instant_measure (const json_t *jmeasures)
{
  size_t i;
  json_t *mi; /* a MeasureInformation object */
  const char *ename;
  unsigned int eline;
  enum GNUNET_GenericReturnValue ret;
  const json_t *measures;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_array_const ("measures",
                                  &measures),
    GNUNET_JSON_spec_end ()
  };

  ret = GNUNET_JSON_parse (jmeasures,
                           spec,
                           &ename,
                           &eline);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return false;
  }

  json_array_foreach ((json_t *) measures, i, mi)
  {
    const char *check_name;

    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_string ("check_name",
                               &check_name),
      GNUNET_JSON_spec_end ()
    };

    ret = GNUNET_JSON_parse (mi,
                             ispec,
                             &ename,
                             &eline);
    if (GNUNET_OK != ret)
    {
      GNUNET_break (0);
      continue;
    }
    if (0 == strcasecmp (check_name, "SKIP"))
    {
      return true;
    }
  }

  return false;
}


/**
 * Function called after a measure has been run.
 *
 * @param cls closure
 * @param ec error code or 0 on success
 * @param detail error message or NULL on success / no info
 */
static void
measure_run_cb (
  void *cls,
  enum TALER_ErrorCode ec,
  const char *detail)
{
  struct KycPoller *kyp = cls;

  GNUNET_assert (kyp->suspended);
  GNUNET_assert (NULL == kyp->response);
  GNUNET_assert (NULL != kyp->kat);

  kyp->kat = NULL;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Resuming after running successor measure, ec=%u\n",
              (unsigned int) ec);

  if (TALER_EC_NONE != ec)
  {
    kyp->response_code = MHD_HTTP_INTERNAL_SERVER_ERROR;
    kyp->response = TALER_MHD_make_error (
      ec,
      detail);
  }

  GNUNET_CONTAINER_DLL_remove (kyp_head,
                               kyp_tail,
                               kyp);
  kyp->suspended = false;
  MHD_resume_connection (kyp->connection);
  TALER_MHD_daemon_trigger ();
}


MHD_RESULT
TEH_handler_kyc_info (
  struct TEH_RequestContext *rc,
  const char *const args[1])
{
  struct KycPoller *kyp = rc->rh_ctx;
  MHD_RESULT res;
  enum GNUNET_DB_QueryStatus qs;
  uint64_t legitimization_measure_last_row;
  uint64_t legitimization_outcome_last_row;
  json_t *jmeasures = NULL;
  json_t *jvoluntary = NULL;
  struct TALER_KYCLOGIC_LegitimizationRuleSet *lrs = NULL;

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
      res = TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "access token");
      goto cleanup;
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
      res = TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "lookup_h_payto_by_access_token");
      goto cleanup;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      GNUNET_break_op (0);
      res = TALER_MHD_REPLY_JSON_PACK (
        rc->connection,
        MHD_HTTP_FORBIDDEN,
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_KYC_INFO_AUTHORIZATION_FAILED));
      goto cleanup;
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
    res = MHD_queue_response (rc->connection,
                              kyp->response_code,
                              kyp->response);
    goto cleanup;
  }

  /* Get rules. */
  {
    json_t *jnew_rules;
    qs = TEH_plugin->lookup_rules_by_access_token (
      TEH_plugin->cls,
      &kyp->h_payto,
      &jnew_rules,
      &legitimization_outcome_last_row);
    if (qs < 0)
    {
      GNUNET_break (0);
      res = TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "lookup_rules_by_access_token");
      goto cleanup;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      /* Nothing was triggered, return the measures
        that apply for any amount. */
      lrs = NULL;
    }
    else
    {
      lrs = TALER_KYCLOGIC_rules_parse (jnew_rules);
      GNUNET_break (NULL != lrs);
      json_decref (jnew_rules);
    }
  }

  /* Check if ruleset is expired and we need to run the successor measure */
  if (NULL != lrs)
  {
    struct GNUNET_TIME_Timestamp ts;

    ts = TALER_KYCLOGIC_rules_get_expiration (lrs);
    if (GNUNET_TIME_absolute_is_past (ts.abs_time))
    {
      const struct TALER_KYCLOGIC_Measure *successor_measure;

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Current KYC ruleset expired, running successor measure.\n");

      successor_measure = TALER_KYCLOGIC_rules_get_successor (lrs);
      if (NULL == successor_measure)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Successor measure `%s' unknown, falling back to default rules!\n",
                    successor_measure->measure_name);
        TALER_KYCLOGIC_rules_free (lrs);
        lrs = NULL;
      }
      else if (0 == strcmp (successor_measure->prog_name, "SKIP"))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Running successor measure %s.\n", successor_measure->
                    measure_name);
        /* FIXME(fdold, 2024-01-08): Consider limiting how
           often we try this, in case we run into expired rulesets
           repeatedly. */
        kyp->kat = TEH_kyc_run_measure_directly (
          &rc->async_scope_id,
          successor_measure,
          &kyp->h_payto,
          &measure_run_cb,
          kyp);
        if (NULL == kyp->kat)
        {
          GNUNET_break (0);
          res = TALER_MHD_reply_with_ec (
            rc->connection,
            TALER_EC_EXCHANGE_KYC_AML_PROGRAM_FAILURE,
            "successor measure");
        }
        kyp->suspended = true;
        GNUNET_CONTAINER_DLL_insert (kyp_head,
                                     kyp_tail,
                                     kyp);
        MHD_suspend_connection (rc->connection);
        res = MHD_YES;
        goto cleanup;
      }
      else
      {
        bool unknown_account;
        struct GNUNET_TIME_Timestamp decision_time
          = GNUNET_TIME_timestamp_get ();
        struct GNUNET_TIME_Timestamp last_date;
        json_t *succ_jmeasures = TALER_KYCLOGIC_get_jmeasures (
          lrs,
          successor_measure->measure_name);

        GNUNET_assert (NULL != succ_jmeasures);
        qs = TEH_plugin->insert_successor_measure (
          TEH_plugin->cls,
          &kyp->h_payto,
          decision_time,
          successor_measure->measure_name,
          succ_jmeasures,
          &unknown_account,
          &last_date);
        json_decref (succ_jmeasures);
        if (qs <= 0)
        {
          GNUNET_break (0);
          res = TALER_MHD_reply_with_ec (
            rc->connection,
            TALER_EC_GENERIC_DB_STORE_FAILED,
            "insert_successor_measure");
          goto cleanup;
        }
        if (unknown_account)
        {
          res = TALER_MHD_reply_with_ec (
            rc->connection,
            TALER_EC_EXCHANGE_GENERIC_BANK_ACCOUNT_UNKNOWN,
            NULL);
          goto cleanup;
        }
        /* We tolerate conflicting decision times for automatic decisions. */
        GNUNET_break (
          GNUNET_TIME_timestamp_cmp (last_date,
                                     >=,
                                     decision_time));
        /* Back to default rules. */
        TALER_KYCLOGIC_rules_free (lrs);
        lrs = NULL;
      }
    }
  }

  jvoluntary
    = TALER_KYCLOGIC_voluntary_measures (lrs);

  qs = TEH_plugin->lookup_kyc_status_by_token (
    TEH_plugin->cls,
    &kyp->access_token,
    &legitimization_measure_last_row,
    &jmeasures);
  if (qs < 0)
  {
    GNUNET_break (0);
    res = TALER_MHD_reply_with_ec (
      rc->connection,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      "lookup_kyc_status_by_token");
    goto cleanup;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    jmeasures
      = TALER_KYCLOGIC_zero_measures (lrs);
    if (NULL == jmeasures)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "No KYC requirement open\n");
      res = TALER_MHD_REPLY_JSON_PACK (
        rc->connection,
        MHD_HTTP_OK,
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_array_steal ("voluntary_measures",
                                        jvoluntary)));
      goto cleanup;
    }

    qs = TEH_plugin->insert_active_legitimization_measure (
      TEH_plugin->cls,
      &kyp->access_token,
      jmeasures,
      &legitimization_measure_last_row);
    if (qs < 0)
    {
      GNUNET_break (0);
      res = TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "insert_active_legitimization_measure");
      goto cleanup;
    }
  }
  if ( (legitimization_measure_last_row == kyp->etag_measure_in) &&
       (legitimization_outcome_last_row == kyp->etag_outcome_in) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Suspending HTTP request on timeout (%s)\n",
                GNUNET_TIME_relative2s (
                  GNUNET_TIME_absolute_get_remaining (
                    kyp->timeout),
                  true));
    GNUNET_assert (NULL != kyp->eh);
    kyp->suspended = true;
    GNUNET_CONTAINER_DLL_insert (kyp_head,
                                 kyp_tail,
                                 kyp);
    MHD_suspend_connection (rc->connection);
    res = MHD_YES;
    goto cleanup;
  }
  /* FIXME: We should instead long-poll on the running KYC program. */
  if (contains_instant_measure (jmeasures))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Still waiting for KYC program.\n");
    res = TALER_MHD_reply_with_ec (
      rc->connection,
      TALER_EC_EXCHANGE_KYC_INFO_BUSY,
      "waiting for KYC program");
    goto cleanup;
  }
  if ( (legitimization_measure_last_row ==
        kyp->etag_measure_in) &&
       (legitimization_outcome_last_row ==
        kyp->etag_outcome_in) )
  {
    char etags[128];

    GNUNET_snprintf (etags,
                     sizeof (etags),
                     "\"%llu-%llu\"",
                     (unsigned long long) legitimization_measure_last_row,
                     (unsigned long long) legitimization_outcome_last_row);
    res = TEH_RESPONSE_reply_not_modified (
      rc->connection,
      etags,
      &add_response_headers,
      NULL);
    goto cleanup;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Generating success reply to kyc-info query\n");
  res = generate_reply (kyp,
                        legitimization_measure_last_row,
                        legitimization_outcome_last_row,
                        jmeasures,
                        jvoluntary);
cleanup:
  TALER_KYCLOGIC_rules_free (lrs);
  json_decref (jmeasures);
  json_decref (jvoluntary);
  return res;
}


/* end of taler-exchange-httpd_kyc-info.c */
