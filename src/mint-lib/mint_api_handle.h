/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file mint-lib/mint_api_handle.h
 * @brief Internal interface to the handle part of the mint's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <curl/curl.h>
#include "taler_mint_service.h"


/**
 * Get the context of a mint.
 *
 * @param h the mint handle to query
 * @return ctx context to execute jobs in
 */
struct TALER_MINT_Context *
MAH_handle_to_context (struct TALER_MINT_Handle *h);


/**
 * Check if the handle is ready to process requests.
 *
 * @param h the mint handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
int
MAH_handle_is_ready (struct TALER_MINT_Handle *h);


/**
 * Obtain the URL to use for an API request.
 *
 * @param h the mint handle to query
 * @param path Taler API path (i.e. "/reserve/withdraw")
 * @return the full URI to use with cURL
 */
char *
MAH_path_to_url (struct TALER_MINT_Handle *h,
                 const char *path);


/* end of mint_api_handle.h */
