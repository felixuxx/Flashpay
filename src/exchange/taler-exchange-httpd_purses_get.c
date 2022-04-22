/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file taler-exchange-httpd_purses_get.c
 * @brief Handle GET /purses/$PID requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_purses.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_responses.h"

// FIXME: add long-polling support!

MHD_RESULT
TEH_handler_pursess_get (struct TEH_RequestContext *rc,
                         const char *const args[1])
{
  struct TALER_PurseContractPublicKeyP purse_pub;
  enum GNUNET_DB_QueryStatus qs;
  MHD_RESULT res;
  struct GNUNET_TIME_Timestamp merge_timestamp = {0};

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &purse_pub,
                                     sizeof (purse_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_PURSES_INVALID_PURSE_PUB,
                                       args[0]);
  }
#if FIXME
  qs = TEH_plugin->select_purse (TEH_plugin->cls,
                                 &purse_pub,
                                 &merge_timestamp,
                                 ...);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "select_purses");
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "select_purses");
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_PURSESS_UNKNOWN,
                                       NULL);
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break; /* handled below */
  }
#endif
  res = TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                &merge_timestamp));
  GNUNET_free (epurses);
  return res;
}


/* end of taler-exchange-httpd_purses_get.c */
