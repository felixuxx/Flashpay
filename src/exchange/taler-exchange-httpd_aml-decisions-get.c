/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_aml-decisions-get.c
 * @brief Return summary information about AML decisions
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd.h"
#include "taler_exchangedb_plugin.h"
#include "taler-exchange-httpd_aml-decision.h"
#include "taler-exchange-httpd_metrics.h"


/**
 * Maximum number of records we return per request.
 */
#define MAX_RECORDS 1024

/**
 * Return AML status.
 *
 * @param cls closure
 * @param row_id current row in AML status table
 * @param h_payto account for which the attribute data is stored
 * @param threshold currently monthly threshold that would trigger an AML check
 * @param status what is the current AML decision
 */
static void
record_cb (
  void *cls,
  uint64_t row_id,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_Amount *threshold,
  enum TALER_AmlDecisionState status)
{
  json_t *records = cls;

  GNUNET_assert (
    0 ==
    json_array_append (
      records,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("h_payto",
                                    h_payto),
        GNUNET_JSON_pack_int64 ("current_state",
                                status),
        TALER_JSON_pack_amount ("threshold",
                                threshold),
        GNUNET_JSON_pack_int64 ("rowid",
                                row_id)
        )));
}


MHD_RESULT
TEH_handler_aml_decisions_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  enum TALER_AmlDecisionState decision;
  int delta = -20;
  unsigned long long start;
  const char *state_str = args[0];

  if (NULL == state_str)
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       args[0]);
  }
  if (0 == strcmp (state_str,
                   "pending"))
    decision = TALER_AML_PENDING;
  else if (0 == strcmp (state_str,
                        "frozen"))
    decision = TALER_AML_FROZEN;
  else if (0 == strcmp (state_str,
                        "normal"))
    decision = TALER_AML_NORMAL;
  else
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       state_str);
  }
  if (NULL != args[1])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       args[1]);
  }

  {
    const char *p;

    p = MHD_lookup_connection_value (rc->connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "delta");
    if (NULL != p)
    {
      char dummy;

      if (1 != sscanf (p,
                       "%d%c",
                       &delta,
                       &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "delta");
      }
    }
    if (delta > 0)
      start = 0;
    else
      start = INT64_MAX;
    p = MHD_lookup_connection_value (rc->connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "start");
    if (NULL != p)
    {
      char dummy;

      if (1 != sscanf (p,
                       "%llu%c",
                       &start,
                       &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "start");
      }
    }
  }

  {
    json_t *records;
    enum GNUNET_DB_QueryStatus qs;

    records = json_array ();
    GNUNET_assert (NULL != records);
    if (INT_MIN == delta)
      delta = INT_MIN + 1;
    qs = TEH_plugin->select_aml_process (TEH_plugin->cls,
                                         decision,
                                         start,
                                         GNUNET_MIN (MAX_RECORDS,
                                                     delta > 0
                                                     ? delta
                                                     : -delta),
                                         delta > 0,
                                         &record_cb,
                                         records);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      json_decref (records);
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      return TALER_MHD_reply_static (
        rc->connection,
        MHD_HTTP_NO_CONTENT,
        NULL,
        NULL,
        0);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_array_steal ("records",
                                    records));
  }
}


/* end of taler-exchange-httpd_aml-decisions_get.c */
