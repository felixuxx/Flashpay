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


/**
 * Set authentication data in @a easy from @a auth.
 * The API currently specifies the use of HTTP basic
 * authentication.
 *
 * @param easy curl handle to setup for authentication
 * @param auth authentication data to use
 * @return #GNUNET_OK in success
 */
int
TALER_BANK_setup_auth_ (CURL *easy,
                        const struct TALER_BANK_AuthenticationData *auth)
{
  int ret;

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
  }
  return ret;
}


/**
 * Obtain the URL to use for an API request.
 * FIXME: duplicates MAH_path_to_url2, and likely also logic in util!
 * FIXME: duplicates TEAH_path_to_url2, and likely also logic in util!
 *
 * @param u base URL of the bank.
 * @param path Taler API path (i.e. "/history").
 *
 * @return the full URL to use with cURL, must be
 *         freed by the caller.
 */
char *
TALER_BANK_path_to_url_ (const char *u,
                         const char *path)
{
  char *url;

  if ( ('/' == path[0]) &&
       (0 < strlen (u)) &&
       ('/' == u[strlen (u) - 1]) )
    path++; /* avoid generating URL with "//" from concat */
  GNUNET_asprintf (&url,
                   "%s%s",
                   u,
                   path);
  return url;
}


/**
 * Parse error code given in @a json.
 *
 * @param json the json to parse.
 *
 * @return error code, or #TALER_EC_INVALID if not found.
 */
enum TALER_ErrorCode
TALER_BANK_parse_ec_ (const json_t *json)
{
  uint32_t ec;

  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint32 ("ec",
                             &ec),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (json,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return TALER_EC_INVALID;
  }
  return (enum TALER_ErrorCode) ec;
}


/* end of bank_api_common.c */
