/*
  This file is part of TALER
  Copyright (C) 2014, 2015 GNUnet e.V.

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
 * @file lib/auditor_api_handle.h
 * @brief Internal interface to the handle part of the auditor's HTTP API
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_auditor_service.h"
#include "taler_curl_lib.h"

/**
 * Get the context of a auditor.
 *
 * @param h the auditor handle to query
 * @return ctx context to execute jobs in
 */
struct GNUNET_CURL_Context *
MAH_handle_to_context (struct TALER_AUDITOR_Handle *h);


/**
 * Check if the handle is ready to process requests.
 *
 * @param h the auditor handle to query
 * @return #GNUNET_YES if we are ready, #GNUNET_NO if not
 */
int
MAH_handle_is_ready (struct TALER_AUDITOR_Handle *h);


/**
 * Obtain the URL to use for an API request.
 *
 * @param h the auditor handle to query
 * @param path Taler API path (i.e. "/deposit-confirmation")
 * @return the full URL to use with cURL
 */
char *
MAH_path_to_url (struct TALER_AUDITOR_Handle *h,
                 const char *path);


/* end of auditor_api_handle.h */
