/*
  This file is part of TALER
  Copyright (C) 2019-2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file curl/curl.c
 * @brief Helper routines for interactions with libcurl
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_curl_lib.h"


#if TALER_CURL_COMPRESS_BODIES
#include <zlib.h>
#endif


void
TALER_curl_set_secure_redirect_policy (CURL *eh,
                                       const char *url)
{
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_FOLLOWLOCATION,
                                   1L));
  GNUNET_assert ( (0 == strncasecmp (url,
                                     "https://",
                                     strlen ("https://"))) ||
                  (0 == strncasecmp (url,
                                     "http://",
                                     strlen ("http://"))) );
#ifdef CURLOPT_REDIR_PROTOCOLS_STR
  if (0 == strncasecmp (url,
                        "https://",
                        strlen ("https://")))
    GNUNET_assert (CURLE_OK ==
                   curl_easy_setopt (eh,
                                     CURLOPT_REDIR_PROTOCOLS_STR,
                                     "https"));
  else
    GNUNET_assert (CURLE_OK ==
                   curl_easy_setopt (eh,
                                     CURLOPT_REDIR_PROTOCOLS_STR,
                                     "http,https"));
#else
#ifdef CURLOPT_REDIR_PROTOCOLS
  if (0 == strncasecmp (url,
                        "https://",
                        strlen ("https://")))
    GNUNET_assert (CURLE_OK ==
                   curl_easy_setopt (eh,
                                     CURLOPT_REDIR_PROTOCOLS,
                                     CURLPROTO_HTTPS));
  else
    GNUNET_assert (CURLE_OK ==
                   curl_easy_setopt (eh,
                                     CURLOPT_REDIR_PROTOCOLS,
                                     CURLPROTO_HTTP | CURLPROTO_HTTPS));
#endif
#endif
  /* limit MAXREDIRS to 5 as a simple security measure against
     a potential infinite loop caused by a malicious target */
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_MAXREDIRS,
                                   5L));
}


enum GNUNET_GenericReturnValue
TALER_curl_easy_post (struct TALER_CURL_PostContext *ctx,
                      CURL *eh,
                      const json_t *body)
{
  char *str;
  size_t slen;

  str = json_dumps (body,
                    JSON_COMPACT);
  if (NULL == str)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  slen = strlen (str);
  if (TALER_CURL_COMPRESS_BODIES &&
      (! ctx->disable_compression) )
  {
    Bytef *cbuf;
    uLongf cbuf_size;
    int ret;

    cbuf_size = compressBound (slen);
    cbuf = GNUNET_malloc (cbuf_size);
    ret = compress (cbuf,
                    &cbuf_size,
                    (const Bytef *) str,
                    slen);
    if (Z_OK != ret)
    {
      /* compression failed!? */
      GNUNET_break (0);
      GNUNET_free (cbuf);
      return GNUNET_SYSERR;
    }
    free (str);
    slen = (size_t) cbuf_size;
    ctx->json_enc = (char *) cbuf;
    GNUNET_assert (
      NULL !=
      (ctx->headers = curl_slist_append (
         ctx->headers,
         "Content-Encoding: deflate")));
  }
  else
  {
    ctx->json_enc = str;
  }
  GNUNET_assert (
    NULL !=
    (ctx->headers = curl_slist_append (
       ctx->headers,
       "Content-Type: application/json")));

  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDS,
                                   ctx->json_enc));
  GNUNET_assert (CURLE_OK ==
                 curl_easy_setopt (eh,
                                   CURLOPT_POSTFIELDSIZE,
                                   slen));
  return GNUNET_OK;
}


void
TALER_curl_easy_post_finished (struct TALER_CURL_PostContext *ctx)
{
  curl_slist_free_all (ctx->headers);
  ctx->headers = NULL;
  GNUNET_free (ctx->json_enc);
  ctx->json_enc = NULL;
}
