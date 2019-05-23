/*
  This file is part of TALER
  Copyright (C) 2019 GNUnet e.V.

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
 * @file lib/teah_common.h
 * @brief Helper routines shared by libtalerexchange and libtalerauditor
 * @author Christian Grothoff
 */
#ifndef TEAH_COMMON_H
#define TEAH_COMMON_H

#include <gnunet/gnunet_curl_lib.h>
#include "taler_json_lib.h"

/**
 * Should we compress PUT/POST bodies with 'deflate' encoding?
 */
#define COMPRESS_BODIES 1

/**
 * State used for #TEAL_curl_easy_post() and
 * #TEAL_curl_easy_post_finished().
 */
struct TEAH_PostContext
{
  /**
   * JSON encoding of the request to POST.
   */
  char *json_enc;

  /**
   * Custom headers.
   */
  struct curl_slist *headers;
};


/**
 * Add the @a body as POST data to the easy handle in
 * @a ctx.
 *
 * @param ctx[in,out] a request context (updated)
 * @param eh easy handle to use
 * @param body JSON body to add to @e ctx
 * @return #GNUNET_OK on success #GNUNET_SYSERR on failure
 */
int
TALER_curl_easy_post (struct TEAH_PostContext *ctx,
                     CURL *eh,
                     const json_t *body);


/**
 * Free the data in @a ctx.
 *
 * @param ctx[in] a request context (updated)
 */
void
TALER_curl_easy_post_finished (struct TEAH_PostContext *ctx);



#endif
