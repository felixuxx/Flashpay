/*
  This file is part of TALER
  (C) 2016-2024 Taler Systems SA

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
 * @file bank-lib/fakebank_twg.c
 * @brief main entry point for the Taler Wire Gateway API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_twg.h"
#include "fakebank_twg_admin_add_incoming.h"
#include "fakebank_twg_admin_add_kycauth.h"
#include "fakebank_twg_get_root.h"
#include "fakebank_twg_history.h"
#include "fakebank_twg_transfer.h"


MHD_RESULT
TALER_FAKEBANK_twg_main_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *url,
  const char *method,
  const char *upload_data,
  size_t *upload_data_size,
  void **con_cls)
{
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Fakebank TWG, serving URL `%s' for account `%s'\n",
              url,
              account);
  if ( (0 == strcmp (url,
                     "/config")) &&
       (0 == strcasecmp (method,
                         MHD_HTTP_METHOD_GET)) )
  {
    /* GET /config */
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_string ("version",
                               "0:0:0"),
      GNUNET_JSON_pack_string ("currency",
                               h->currency),
      GNUNET_JSON_pack_string ("implementation",
                               "urn:net:taler:specs:bank:fakebank"),
      GNUNET_JSON_pack_string ("name",
                               "taler-wire-gateway"));
  }
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_GET))
  {
    if ( (0 == strcmp (url,
                       "/history/incoming")) &&
         (NULL != account) )
      return TALER_FAKEBANK_twg_get_credit_history_ (h,
                                                     connection,
                                                     account,
                                                     con_cls);
    if ( (0 == strcmp (url,
                       "/history/outgoing")) &&
         (NULL != account) )
      return TALER_FAKEBANK_twg_get_debit_history_ (h,
                                                    connection,
                                                    account,
                                                    con_cls);
    if (0 == strcmp (url,
                     "/"))
      return TALER_FAKEBANK_twg_get_root_ (h,
                                           connection);
  }
  else if (0 == strcasecmp (method,
                            MHD_HTTP_METHOD_POST))
  {
    if ( (0 == strcmp (url,
                       "/admin/add-incoming")) &&
         (NULL != account) )
      return TALER_FAKEBANK_twg_admin_add_incoming_ (h,
                                                     connection,
                                                     account,
                                                     upload_data,
                                                     upload_data_size,
                                                     con_cls);
    if ( (0 == strcmp (url,
                       "/admin/add-kycauth")) &&
         (NULL != account) )
      return TALER_FAKEBANK_twg_admin_add_kycauth_ (h,
                                                    connection,
                                                    account,
                                                    upload_data,
                                                    upload_data_size,
                                                    con_cls);
    if ( (0 == strcmp (url,
                       "/transfer")) &&
         (NULL != account) )
      return TALER_FAKEBANK_handle_transfer_ (h,
                                              connection,
                                              account,
                                              upload_data,
                                              upload_data_size,
                                              con_cls);
  }
  /* Unexpected URL path, just close the connection. */
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
