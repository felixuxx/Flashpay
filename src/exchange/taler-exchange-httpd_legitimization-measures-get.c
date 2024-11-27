/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_legitimization-measures-get.c
 * @brief Return information about legitimization measures
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
#include "taler-exchange-httpd_legitimization-measures-get.h"
#include "taler-exchange-httpd_metrics.h"

/**
 * Maximum number of measures we return in one request.
 */
#define MAX_MEASURES 1024

/**
 * Return LEGITIMIZATION measure.
 *
 * @param cls closure
 * @param h_payto hash of account the measure applies to
 * @param start_time when was the process started
 * @param jmeasures array of measures that are active
 * @param is_finished true if the measure was finished
 * @param measure_serial_id row ID of the measure in the exchange table
 */
static void
record_cb (
  void *cls,
  struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp start_time,
  const json_t *jmeasures,
  bool is_finished,
  uint64_t measure_serial_id)
{
  json_t *measures = cls;

  GNUNET_assert (
    0 ==
    json_array_append_new (
      measures,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("h_payto",
                                    h_payto),
        GNUNET_JSON_pack_uint64 ("rowid",
                                 measure_serial_id),
        GNUNET_JSON_pack_timestamp ("start_time",
                                    start_time),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_array_incref ("measures",
                                         (json_t *) jmeasures)),
        GNUNET_JSON_pack_bool ("is_finished",
                               is_finished)
        )));
}


MHD_RESULT
TEH_handler_legitimization_measures_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  int64_t limit = -20;
  uint64_t offset;
  struct TALER_NormalizedPaytoHashP h_payto;
  bool have_payto = false;
  enum TALER_EXCHANGE_YesNoAll active_filter;

  if (NULL != args[0])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
      args[0]);
  }
  TALER_MHD_parse_request_snumber (rc->connection,
                                   "limit",
                                   &limit);
  if (limit > 0)
    offset = 0;
  else
    offset = INT64_MAX;
  TALER_MHD_parse_request_number (rc->connection,
                                  "offset",
                                  &offset);
  if (offset > INT64_MAX)
  {
    GNUNET_break_op (0); /* broken client */
    offset = INT64_MAX;
  }
  TALER_MHD_parse_request_arg_auto (rc->connection,
                                    "h_payto",
                                    &h_payto,
                                    have_payto);
  TALER_MHD_parse_request_yna (rc->connection,
                               "active",
                               TALER_EXCHANGE_YNA_ALL,
                               &active_filter);
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->test_aml_officer (TEH_plugin->cls,
                                       officer_pub);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "test_aml_officer");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      GNUNET_break_op (0);
      return TALER_MHD_reply_static (
        rc->connection,
        MHD_HTTP_FORBIDDEN,
        NULL,
        NULL,
        0);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
  }
  {
    json_t *measures;
    enum GNUNET_DB_QueryStatus qs;

    measures = json_array ();
    GNUNET_assert (NULL != measures);
    if (limit > MAX_MEASURES)
      limit = MAX_MEASURES;
    if (limit < -MAX_MEASURES)
      limit = -MAX_MEASURES;
    qs = TEH_plugin->select_aml_measures (
      TEH_plugin->cls,
      have_payto
      ? &h_payto
      : NULL,
      active_filter,
      offset,
      limit,
      &record_cb,
      measures);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      json_decref (measures);
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "select_aml_measures");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      json_decref (measures);
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
      GNUNET_JSON_pack_array_steal ("measures",
                                    measures));
  }
}


/* end of taler-exchange-httpd_legitimization-measures_get.c */
