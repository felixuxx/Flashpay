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
 * Return AML status.
 *
 * @param cls closure
 * @param row_id current row in AML status table
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
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute decision_time,
  struct GNUNET_TIME_Absolute expiration_time,
  const json_t *jproperties,
  bool to_investigate,
  bool is_active,
  const json_t *account_rules)
{
  json_t *records = cls;

  GNUNET_assert (
    0 ==
    json_array_append (
      records,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("h_payto",
                                    h_payto),
        // FIXME: pack other data!
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
  long long limit = -20;
  unsigned long long offset;

  if (NULL != args[0])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       args[0]);
  }

  {
    const char *p;

    p = MHD_lookup_connection_value (rc->connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "limit");
    if (NULL != p)
    {
      char dummy;

      if (1 != sscanf (p,
                       "%lld%c",
                       &limit,
                       &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "limit");
      }
    }
    if (limit > 0)
      offset = 0;
    else
      offset = INT64_MAX;
    p = MHD_lookup_connection_value (rc->connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "offset");
    if (NULL != p)
    {
      char dummy;

      if (1 != sscanf (p,
                       "%llu%c",
                       &offset,
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
    qs = TEH_plugin->select_aml_decisions (
      TEH_plugin->cls,
      NULL /* FIXME! */,
      0, /* FIXME */
      0, /* FIXME */
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
