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
  struct MHD_Response *response;
  int ret;
  size_t dlen;

  (void) args;
  dlen = (0 == rh->data_size)
         ? strlen ((const char *) rh->data)
         : rh->data_size;
  response = MHD_create_response_from_buffer (dlen,
                                              (void *) rh->data,
                                              MHD_RESPMEM_PERSISTENT);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  TALER_MHD_add_global_headers (response);
  if (NULL != rh->mime_type)
    (void) MHD_add_response_header (response,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    rh->mime_type);
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
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


/**
 * Function to call to handle the request by building a JSON
 * reply with an error message from @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
int
TEH_handler_send_json_pack_error (const struct TEH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  const char *const args[])
{
  (void) args;
  return TALER_MHD_reply_with_error (connection,
                                     rh->response_code,
                                     TALER_EC_METHOD_INVALID,
                                     rh->data);
}


/* end of taler-exchange-httpd_mhd.c */
