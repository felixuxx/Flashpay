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
 * @file bank-lib/fakebank_tbr.c
 * @brief main entry point for the Taler Bank Revenue API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#include "platform.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"
#include "fakebank_tbr_get_history.h"
#include "fakebank_tbr_get_root.h"


MHD_RESULT
TALER_FAKEBANK_tbr_main_ (
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
              "Fakebank - Anastasis API: serving URL `%s' for account `%s'\n",
              url,
              account);
  if (0 == strcasecmp (method,
                       MHD_HTTP_METHOD_GET))
  {
    if ( (0 == strcmp (url,
                       "/history")) &&
         (NULL != account) )
      return TALER_FAKEBANK_tbr_get_history (h,
                                             connection,
                                             account,
                                             con_cls);
    if (0 == strcmp (url,
                     "/"))
      return TALER_FAKEBANK_tbr_get_root (h,
                                          connection);
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
