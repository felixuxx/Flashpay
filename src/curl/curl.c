/*
  This file is part of TALER
  Copyright (C) 2019-2020 Taler Systems SA

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

#if COMPRESS_BODIES
#include <zlib.h>
#endif


/**
 * Add the @a body as POST data to the easy handle in @a ctx.
 *
 * @param ctx[in,out] a request context (updated)
 * @param eh easy handle to use
 * @param body JSON body to add to @e ctx
 * @return #GNUNET_OK on success #GNUNET_SYSERR on failure
 */
int
TALER_curl_easy_post (struct TEAH_PostContext *ctx,
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
#if COMPRESS_BODIES
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
  }
  GNUNET_assert
    (NULL != (ctx->headers = curl_slist_append
                               (ctx->headers,
                               "Content-Encoding: deflate")));
#else
  ctx->json_enc = str;
#endif

  GNUNET_assert
    (NULL != (ctx->headers = curl_slist_append
                               (ctx->headers,
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


/**
 * Free the data in @a ctx.
 *
 * @param ctx[in] a request context (updated)
 */
void
TALER_curl_easy_post_finished (struct TEAH_PostContext *ctx)
{
  curl_slist_free_all (ctx->headers);
  ctx->headers = NULL;
  GNUNET_free_non_null (ctx->json_enc);
}
