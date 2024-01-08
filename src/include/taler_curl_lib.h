/*
  This file is part of TALER
  Copyright (C) 2019 Taler Systems SA

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
 * @file taler_curl_lib.h
 * @brief Helper routines shared by libtalerexchange and libtalerauditor
 * @author Christian Grothoff
 */
#ifndef TALER_CURL_LIB_H
#define TALER_CURL_LIB_H

#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"

/**
 * Should we compress PUT/POST bodies with 'deflate' encoding?
 */
#define TALER_CURL_COMPRESS_BODIES 1

/**
 * State used for #TALER_curl_easy_post() and
 * #TALER_curl_easy_post_finished().
 */
struct TALER_CURL_PostContext
{
  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Custom headers.
   */
  struct curl_slist *headers;

  /**
   * Set to true to disable compression of the body.
   */
  bool disable_compression;
};


/**
 * Add the @a body as POST data to the easy handle in
 * @a ctx.
 *
 * @param[in,out] ctx a request context (updated)
 * @param eh easy handle to use
 * @param body JSON body to add to @e ctx
 * @return #GNUNET_OK on success #GNUNET_SYSERR on failure
 */
enum GNUNET_GenericReturnValue
TALER_curl_easy_post (struct TALER_CURL_PostContext *ctx,
                      CURL *eh,
                      const json_t *body);


/**
 * Free the data in @a ctx.
 *
 * @param[in] ctx a request context (updated)
 */
void
TALER_curl_easy_post_finished (struct TALER_CURL_PostContext *ctx);


/**
 * Set a secure redirection policy, allowing a limited
 * number of redirects and only going from HTTP to HTTPS
 * but not from HTTPS to HTTP.
 *
 * @param[in,out] eh easy handle to modify
 * @param url URL to base the redirect policy on;
 *        must start with "http://" or "https://"
 */
void
TALER_curl_set_secure_redirect_policy (CURL *eh,
                                       const char *url);

#endif
