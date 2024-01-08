/*
  This file is part of TALER
  Copyright (C) 2014-2018, 2021 Taler Systems SA

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
 * @file lib/exchange_api_curl_defaults.c
 * @brief curl easy handle defaults
 * @author Florian Dold
 */
#include "taler_curl_lib.h"
#include "exchange_api_curl_defaults.h"


CURL *
TALER_EXCHANGE_curl_easy_get_ (const char *url)
{
  CURL *eh;

  eh = curl_easy_init ();
  if (NULL == eh)
  {
    GNUNET_break (0);
    return NULL;
  }
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   url));
  TALER_curl_set_secure_redirect_policy (eh,
                                         url);
  /* Enable compression (using whatever curl likes), see
     https://curl.se/libcurl/c/CURLOPT_ACCEPT_ENCODING.html  */
  GNUNET_break (CURLE_OK ==
                curl_easy_setopt (eh,
                                  CURLOPT_ACCEPT_ENCODING,
                                  ""));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_TCP_FASTOPEN,
                                   1L));
  return eh;
}
