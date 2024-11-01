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
 * Maximum number of records we return in one request.
 */
#define MAX_RECORDS 1024

/**
 * Return AML status.
 *
 * @param cls closure
 * @param row_id current row in AML status table
 * @param justification human-readable reason for the decision
 * @param h_payto account for which the attribute data is stored
 * @param decision_time when was the decision taken
 * @param expiration_time when will the rules expire
 * @param jproperties properties set for the account,
 *    NULL if no properties were set
 * @param to_investigate true if AML staff should look at the account
 * @param is_active true if this is the currently active decision about the account
 * @param account_rules current active rules for the account
 */
static void
record_cb (
  void *cls,
  uint64_t row_id,
  const char *justification,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  struct GNUNET_TIME_Absolute expiration_time,
  const json_t *jproperties,
  bool to_investigate,
  bool is_active,
  const json_t *account_rules)
{
  json_t *records = cls;

  GNUNET_assert (
    0 ==
    json_array_append_new (
      records,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("h_payto",
                                    h_payto),
        GNUNET_JSON_pack_int64 ("rowid",
                                row_id),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_string ("justification",
                                   justification)),
        GNUNET_JSON_pack_timestamp ("decision_time",
                                    decision_time),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_incref ("properties",
                                          (json_t *) jproperties)),
        GNUNET_JSON_pack_object_incref ("limits",
                                        (json_t *) account_rules),
        GNUNET_JSON_pack_bool ("to_investigate",
                               to_investigate),
        GNUNET_JSON_pack_bool ("is_active",
                               is_active)
        )));
}


MHD_RESULT
TEH_handler_aml_decisions_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  int64_t limit = -20;
  uint64_t offset;
  struct TALER_NormalizedPaytoHashP h_payto;
  bool have_payto = false;
  enum TALER_EXCHANGE_YesNoAll active_filter;
  enum TALER_EXCHANGE_YesNoAll investigation_filter;

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
  TALER_MHD_parse_request_yna (rc->connection,
                               "investigation",
                               TALER_EXCHANGE_YNA_ALL,
                               &investigation_filter);
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
    json_t *records;
    enum GNUNET_DB_QueryStatus qs;

    records = json_array ();
    GNUNET_assert (NULL != records);
    if (limit > MAX_RECORDS)
      limit = MAX_RECORDS;
    if (limit < -MAX_RECORDS)
      limit = -MAX_RECORDS;
    qs = TEH_plugin->select_aml_decisions (
      TEH_plugin->cls,
      have_payto
      ? &h_payto
      : NULL,
      investigation_filter,
      active_filter,
      offset,
      limit,
      &record_cb,
      records);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      json_decref (records);
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "select_aml_decisions");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      json_decref (records);
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
