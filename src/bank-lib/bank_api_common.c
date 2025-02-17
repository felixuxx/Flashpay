/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/bank_api_common.c
 * @brief Common functions for the bank API
 * @author Christian Grothoff
 */
#include "platform.h"
#include "bank_api_common.h"


enum GNUNET_GenericReturnValue
TALER_BANK_setup_auth_ (CURL *easy,
                        const struct TALER_BANK_AuthenticationData *auth)
{
  enum GNUNET_GenericReturnValue ret;

  ret = GNUNET_OK;
  switch (auth->method)
  {
  case TALER_BANK_AUTH_NONE:
    return GNUNET_OK;
  case TALER_BANK_AUTH_BASIC:
    {
      char *up;

      GNUNET_asprintf (&up,
                       "%s:%s",
                       auth->details.basic.username,
                       auth->details.basic.password);
      if ( (CURLE_OK !=
            curl_easy_setopt (easy,
                              CURLOPT_HTTPAUTH,
                              CURLAUTH_BASIC)) ||
           (CURLE_OK !=
            curl_easy_setopt (easy,
                              CURLOPT_USERPWD,
                              up)) )
        ret = GNUNET_SYSERR;
      GNUNET_free (up);
      break;
    }
  case TALER_BANK_AUTH_BEARER:
    {
      if ( (CURLE_OK !=
            curl_easy_setopt (easy,
                              CURLOPT_HTTPAUTH,
                              CURLAUTH_BEARER)) ||
           (CURLE_OK !=
            curl_easy_setopt (easy,
                              CURLOPT_XOAUTH2_BEARER,
                              auth->details.bearer.token)) )
        ret = GNUNET_SYSERR;
      break;
    }
  }
  return ret;
}


/* end of bank_api_common.c */
