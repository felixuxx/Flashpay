/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-exchange-httpd_mhd.c
 * @brief helpers for MHD interaction; these are TALER_EXCHANGE_handler_ functions
 *        that generate simple MHD replies that do not require any real operations
 *        to be performed (error handling, static pages, etc.)
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_mhd.h"


/**
 * Function to call to handle the request by sending
 * back static data from the @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
int
TEH_handler_static_response (const struct TEH_RequestHandler *rh,
                             struct MHD_Connection *connection,
                             const char *const args[])
{
  size_t dlen;

  (void) args;
  dlen = (0 == rh->data_size)
         ? strlen ((const char *) rh->data)
         : rh->data_size;
  return TALER_MHD_reply_static (connection,
                                 rh->response_code,
                                 rh->mime_type,
                                 rh->data,
                                 dlen);
}


/**
 * Function to call to handle the request by sending
 * back a redirect to the AGPL source code.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
int
TEH_handler_agpl_redirect (const struct TEH_RequestHandler *rh,
                           struct MHD_Connection *connection,
                           const char *const args[])
{
  (void) rh;
  (void) args;
  return TALER_MHD_reply_agpl (connection,
                               "http://www.git.taler.net/?p=exchange.git");
}


/* end of taler-exchange-httpd_mhd.c */
