/*
  This file is part of TALER
  Copyright (C) 2014 GNUnet e.V.

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
 * @file taler_mhd_lib.h
 * @brief API for generating MHD replies
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_MHD_LIB_H
#define TALER_MHD_LIB_H
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_error_codes.h"

/**
 * Global options for response generation.
 */
enum TALER_MHD_GlobalOptions
{

  /**
   * Use defaults.
   */
  TALER_MHD_GO_NONE = 0,

  /**
   * Add "Connection: Close" header.
   */
  TALER_MHD_GO_FORCE_CONNECTION_CLOSE = 1,

  /**
   * Disable use of compression, even if the client
   * supports it.
   */
  TALER_MHD_GO_DISABLE_COMPRESSION = 2

};


/**
 * Set global options for response generation
 * within libtalermhd.
 *
 * @param go global options to use
 */
void
TALER_MHD_setup (enum TALER_MHD_GlobalOptions go);


/**
 * Add headers we want to return in every response.
 * Useful for testing, like if we want to always close
 * connections.
 *
 * @param response response to modify
 */
void
TALER_MHD_add_global_headers (struct MHD_Response *response);


/**
 * Try to compress a response body.  Updates @a buf and @a buf_size.
 *
 * @param[in,out] buf pointer to body to compress
 * @param[in,out] buf_size pointer to initial size of @a buf
 * @return #MHD_YES if @a buf was compressed
 */
int
TALER_MHD_body_compress (void **buf,
                         size_t *buf_size);


/**
 * Is HTTP body deflate compression supported by the client?
 *
 * @param connection connection to check
 * @return #MHD_YES if 'deflate' compression is allowed
 */
int
TALER_MHD_can_compress (struct MHD_Connection *connection);


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TALER_MHD_reply_json (struct MHD_Connection *connection,
                      const json_t *json,
                      unsigned int response_code);


/**
 * Function to call to handle the request by building a JSON
 * reply from a format string and varargs.
 *
 * @param connection the MHD connection to handle
 * @param response_code HTTP response code to use
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD result code
 */
int
TALER_MHD_reply_json_pack (struct MHD_Connection *connection,
                           unsigned int response_code,
                           const char *fmt,
                           ...);


/**
 * Send a response indicating an error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param http_status HTTP status code to use
 * @param hint human readable hint about the error
 * @return a MHD result code
 */
int
TALER_MHD_reply_with_error (struct MHD_Connection *connection,
                            unsigned int http_status,
                            enum TALER_ErrorCode ec,
                            const char *hint);


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MHD_reply_request_too_large (struct MHD_Connection *connection);


#endif
