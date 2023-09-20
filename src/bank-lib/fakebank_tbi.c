/*
  This file is part of TALER
  (C) 2016-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/fakebank_tbi.c
 * @brief main entry point to the Taler Bank Integration (TBI) API implementation
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_tbi.h"
#include "fakebank_tbi_get_withdrawal_operation.h"
#include "fakebank_tbi_post_withdrawal_operation.h"


MHD_RESULT
TALER_FAKEBANK_tbi_main_ (struct TALER_FAKEBANK_Handle *h,
                          struct MHD_Connection *connection,
                          const char *url,
                          const char *method,
                          const char *upload_data,
                          size_t *upload_data_size,
                          void **con_cls)
{
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_HEAD))
    method = MHD_HTTP_METHOD_GET;
  if ( (0 == strcmp (url,
                     "/config")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string ("version",
                               "0:0:0"),
      GNUNET_JSON_pack_string ("currency",
                               h->currency),
      GNUNET_JSON_pack_string ("name",
                               "taler-bank-integration"));
  }
  if ( (0 == strncmp (url,
                      "/withdrawal-operation/",
                      strlen ("/withdrawal-operation/"))) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    const char *wopid = &url[strlen ("/withdrawal-operation/")];
    const char *lp_s
      = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     "long_poll_ms");
    struct GNUNET_TIME_Relative lp = GNUNET_TIME_UNIT_ZERO;

    if (NULL != lp_s)
    {
      unsigned long long d;
      char dummy;

      if (1 != sscanf (lp_s,
                       "%llu%c",
                       &d,
                       &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "long_poll_ms");
      }
      lp = GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                          d);
    }
    return TALER_FAKEBANK_tbi_get_withdrawal_operation_ (h,
                                                         connection,
                                                         wopid,
                                                         lp,
                                                         con_cls);

  }
  if ( (0 == strncmp (url,
                      "/withdrawal-operation/",
                      strlen ("/withdrawal-operation/"))) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_POST)) )
  {
    const char *wopid = &url[strlen ("/withdrawal-operation/")];

    return TALER_FAKEBANK_tbi_post_withdrawal (h,
                                               connection,
                                               wopid,
                                               upload_data,
                                               upload_data_size,
                                               con_cls);
  }

  TALER_LOG_ERROR ("Breaking URL: %s %s\n",
                   method,
                   url);
  GNUNET_break_op (0);
  return TALER_MHD_reply_with_error (
    connection,
    MHD_HTTP_NOT_FOUND,
    TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
    url);
}
