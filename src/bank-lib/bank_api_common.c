/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2017 GNUnet e.V.

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
 * Append HTTP key-value pair to curl header list.
 *
 * @param hdr list to append to, can be NULL
 * @param key key to append
 * @param value value to append
 * @return new list, NULL on error
 */
static struct curl_slist *
append (struct curl_slist *hdr,
        const char *key,
        const char *value)
{
  char *str;
  struct curl_slist *ret;

  GNUNET_asprintf (&str,
                   "%s: %s",
                   key,
                   value);
  ret = curl_slist_append (hdr,
                           str);
  GNUNET_free (str);
  if (NULL == ret)
  {
    GNUNET_break (0);
    curl_slist_free_all (hdr);
    return NULL;
  }
  return ret;
}


/**
 * Build authentication header from @a auth.
 *
 * @param auth authentication data to use
 * @return NULL on error, otherwise curl headers to use
 */
struct curl_slist *
TALER_BANK_make_auth_header_ (const struct TALER_BANK_AuthenticationData *auth)
{
  struct curl_slist *authh;

  switch (auth->method)
  {
  case TALER_BANK_AUTH_NONE:
    return NULL;
  case TALER_BANK_AUTH_BASIC:
    authh = append (NULL,
                    "X-Taler-Bank-Username",
                    auth->details.basic.username);
    if (NULL == authh)
      return NULL;
    authh = append (authh,
                    "X-Taler-Bank-Password",
                    auth->details.basic.password);
    return authh;
  }
  return NULL;
}


/**
 * Obtain the URL to use for an API request.
 *
 * @param u base URL of the bank
 * @param path Taler API path (i.e. "/history")
 * @return the full URI to use with cURL
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
 * @param json the json to parse
 * @return error code, or #TALER_EC_INVALID if not found
 */
enum TALER_ErrorCode
TALER_BANK_parse_ec_ (const json_t *json)
{
  uint32_t ec;

  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_uint32 ("ec",
                             &ec),
    GNUNET_JSON_spec_end()
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
