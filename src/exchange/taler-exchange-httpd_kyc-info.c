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
   * #MHD_HTTP_HEADER_IF_NONE_MATCH Etag value sent by the client.  0 for none
   * (or malformed).
   */
  uint64_t etag_in;

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
 * Generate a reply with the KycProcessClientInformation from
 * the LegitimizationMeasures.
 *
 * @param[in,out] kyp request to reply on
 * @param legitimization_measure_row_id etag to set for the response
 * @param jmeasures measures to encode
 * @return MHD status code
 */
static MHD_RESULT
generate_reply (struct KycPoller *kyp,
                uint64_t legitimization_measure_row_id,
                const json_t *jmeasures)
{
  const json_t *measures;
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
  enum GNUNET_GenericReturnValue res;
  const char *ename;
  unsigned int eline;
  json_t *kris;
  size_t i;
  json_t *mi;

  res = GNUNET_JSON_parse (jmeasures,
                           spec,
                           &ename,
                           &eline);
  if (GNUNET_OK != res)
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
    struct GNUNET_JSON_Specification ispec[] = {
      GNUNET_JSON_spec_string ("check_name",
                               &check_name),
      GNUNET_JSON_spec_string ("prog_name",
                               &prog_name),
      GNUNET_JSON_spec_end ()
    };
    json_t *kri;

    res = GNUNET_JSON_parse (mi,
                             ispec,
                             &ename,
                             &eline);
    if (GNUNET_OK != res)
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
    char etags[64];
    struct MHD_Response *resp;
    MHD_RESULT res;

    GNUNET_snprintf (etags,
                     sizeof (etags),
                     "%llu",
                     (unsigned long long) legitimization_measure_row_id);
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_array_steal ("requirements",
                                    kris),
      GNUNET_JSON_pack_bool ("is_and_combinator",
                             is_and_combinator),
      GNUNET_JSON_pack_allow_null (
        /* TODO: support vATTEST */
        GNUNET_JSON_pack_object_steal ("voluntary_checks",
                                       NULL)));
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           MHD_HTTP_HEADER_ETAG,
                                           etags));
    res = MHD_queue_response (kyp->connection,
                              MHD_HTTP_OK,
                              resp);
    GNUNET_break (MHD_YES == res);
    MHD_destroy_response (resp);
    return res;
  }
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
  json_t *jmeasures;

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
        unsigned long long ev;

        if (1 != sscanf (etags,
                         "\"%llu\"%c",
                         &ev,
                         &dummy))
        {
          GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                      "Client send malformed `%s' header `%s'\n",
                      MHD_HTTP_HEADER_IF_NONE_MATCH,
                      etags);
        }
        else
        {
          kyp->etag_in = (uint64_t) ev;
        }
      }
    } /* etag */
  } /* one-time initialization */

  if ( (NULL == kyp->eh) &&
       GNUNET_TIME_absolute_is_future (kyp->timeout) )
  {
    struct TALER_KycCompletedEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_KYC_COMPLETED)
    };

    qs = TEH_plugin->lookup_h_payto_by_access_token (
      TEH_plugin->cls,
      &kyp->access_token,
      &rep.h_payto);
    if (qs < 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_ec (
        rc->connection,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "lookup_h_payto_by_access_token");
    }

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Starting DB event listening\n");
    kyp->eh = TEH_plugin->event_listen (
      TEH_plugin->cls,
      GNUNET_TIME_absolute_get_remaining (kyp->timeout),
      &rep.header,
      &db_event_cb,
      rc);
  }

  qs = TEH_plugin->lookup_kyc_status_by_token (
    TEH_plugin->cls,
    &kyp->access_token,
    &legitimization_measure_last_row,
    &jmeasures);
  if (qs < 0)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (
      rc->connection,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      "lookup_kyc_status_by_token");
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "No KYC requirement open\n");
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_allow_null (
        /* TODO: support vATTEST */
        GNUNET_JSON_pack_object_steal ("voluntary_checks",
                                       NULL)));
  }
  if ( (legitimization_measure_last_row == kyp->etag_in) &&
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
    return MHD_YES;
  }

  res = generate_reply (kyp,
                        legitimization_measure_last_row,
                        jmeasures);
  json_decref (jmeasures);
  return res;
}


/* end of taler-exchange-httpd_kyc-info.c */
