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
 * @file taler-exchange-httpd_aml-statistics-get.c
 * @brief Return summary information about KYC statistics
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
#include "taler-exchange-httpd_aml-statistics-get.h"
#include "taler-exchange-httpd_metrics.h"


MHD_RESULT
TEH_handler_aml_kyc_statistics_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  const char *name = args[0];
  uint64_t cnt;

  if ( (NULL == args[0]) ||
       (NULL != args[1]) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
      rc->url);
  }
  start_date = GNUNET_TIME_UNIT_ZERO_TS;
  end_date = GNUNET_TIME_timestamp_get ();

  TALER_MHD_parse_request_timestamp (rc->connection,
                                     "start_date",
                                     &start_date);
  TALER_MHD_parse_request_timestamp (rc->connection,
                                     "end_date",
                                     &end_date);
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->select_aml_statistics (
      TEH_plugin->cls,
      name,
      start_date,
      end_date,
      &cnt);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "select_aml_statistics");
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
      GNUNET_JSON_pack_uint64 ("counter",
                               cnt));
  }
}


/* end of taler-exchange-httpd_aml-statistics_get.c */
