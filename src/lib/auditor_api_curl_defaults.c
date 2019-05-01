/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
 * @file auditor-lib/curl_defaults.c
 * @brief curl easy handle defaults
 * @author Florian Dold
 */

#include "auditor_api_curl_defaults.h"


/**
 * Get a curl handle with the right defaults
 * for the exchange lib.  In the future, we might manage a pool of connections here.
 *
 * @param url URL to query
 */
CURL *
TAL_curl_easy_get (const char *url)
{
  CURL *eh;

  eh = curl_easy_init ();

  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_URL,
                                   url));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_ENCODING,
                                   "deflate"));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_TCP_FASTOPEN,
                                   1L));
  {
    /* Unfortunately libcurl needs chunk to be alive until after
    curl_easy_perform.  To avoid manual cleanup, we keep
    one static list here.  */
    static struct curl_slist *chunk = NULL;
    if (NULL == chunk)
    {
      /* With POST requests, we do not want to wait for the
      "100 Continue" response, as our request bodies are usually
      small and directy sending them saves us a round trip.

      Clearing the expect header like this disables libcurl's
      default processing of the header.

      Disabling this header is safe for other HTTP methods, thus
      we don't distinguish further before setting it.  */
      chunk = curl_slist_append (chunk, "Expect:");
    }
    GNUNET_assert (CURLE_OK == curl_easy_setopt (eh, CURLOPT_HTTPHEADER, chunk));
  }

  return eh;
}
