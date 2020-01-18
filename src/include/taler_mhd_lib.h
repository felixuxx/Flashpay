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
 * @file taler_mhd_lib.h
 * @brief API for generating MHD replies
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_MHD_LIB_H
#define TALER_MHD_LIB_H
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
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
 * Make JSON response object.
 *
 * @param json the json object
 * @return MHD response object
 */
struct MHD_Response *
TALER_MHD_make_json (const json_t *json);


/**
 * Make JSON response object.
 *
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD response object
 */
struct MHD_Response *
TALER_MHD_make_json_pack (const char *fmt,
                          ...);


/**
 * Create a response indicating an internal error.
 *
 * @param ec error code to return
 * @param hint hint about the internal error's nature
 * @return a MHD response object
 */
struct MHD_Response *
TALER_MHD_make_error (enum TALER_ErrorCode ec,
                      const char *hint);


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TALER_MHD_reply_request_too_large (struct MHD_Connection *connection);


/**
 * Function to call to handle the request by sending
 * back a redirect to the AGPL source code.
 *
 * @param connection the MHD connection to handle
 * @param url where to redirect for the sources
 * @return MHD result code
 */
int
TALER_MHD_reply_agpl (struct MHD_Connection *connection,
                      const char *url);


/**
 * Function to call to handle the request by sending
 * back static data.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param http_status status code to return
 * @param mime_type content-type to use
 * @param body response payload
 * @param body_size number of bytes in @a body
 * @return MHD result code
 */
int
TALER_MHD_reply_static (struct MHD_Connection *connection,
                        unsigned int http_status,
                        const char *mime_type,
                        const char *body,
                        size_t body_size);


/**
 * Process a POST request containing a JSON object.  This
 * function realizes an MHD POST processor that will
 * (incrementally) process JSON data uploaded to the HTTP
 * server.  It will store the required state in the
 * "connection_cls", which must be cleaned up using
 * #TALER_MHD_post_cleanup_callback().
 *
 * @param connection the MHD connection
 * @param con_cls the closure (points to a `struct Buffer *`)
 * @param upload_data the POST data
 * @param upload_data_size number of bytes in @a upload_data
 * @param json the JSON object for a completed request
 * @return
 *    #GNUNET_YES if json object was parsed or at least
 *               may be parsed in the future (call again);
 *               `*json` will be NULL if we need to be called again,
 *                and non-NULL if we are done.
 *    #GNUNET_NO is request incomplete or invalid
 *               (error message was generated)
 *    #GNUNET_SYSERR on internal error
 *               (we could not even queue an error message,
 *                close HTTP session with MHD_NO)
 */
int
TALER_MHD_parse_post_json (struct MHD_Connection *connection,
                           void **con_cls,
                           const char *upload_data,
                           size_t *upload_data_size,
                           json_t **json);


/**
 * Function called whenever we are done with a request
 * to clean up our state.
 *
 * @param con_cls value as it was left by
 *        #TALER_MHD_parse_post_json(), to be cleaned up
 */
void
TALER_MHD_parse_post_cleanup_callback (void *con_cls);


/**
 * Parse JSON object into components based on the given field
 * specification.
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param spec field specification for the parser
 * @return
 *    #GNUNET_YES if navigation was successful (caller is responsible
 *                for freeing allocated variable-size data using
 *                GNUNET_JSON_parse_free() when done)
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
int
TALER_MHD_parse_json_data (struct MHD_Connection *connection,
                           const json_t *root,
                           struct GNUNET_JSON_Specification *spec);


/**
 * Parse JSON array into components based on the given field
 * specification.  Generates error response on parse errors.
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param[in,out] spec field specification for the parser
 * @param ... -1-terminated list of array offsets of type 'int'
 * @return
 *    #GNUNET_YES if navigation was successful (caller is responsible
 *                for freeing allocated variable-size data using
 *                GNUNET_JSON_parse_free() when done)
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
int
TALER_MHD_parse_json_array (struct MHD_Connection *connection,
                            const json_t *root,
                            struct GNUNET_JSON_Specification *spec,
                            ...);


/**
 * Extraxt fixed-size base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of @a out_data
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
int
TALER_MHD_parse_request_arg_data (struct MHD_Connection *connection,
                                  const char *param_name,
                                  void *out_data,
                                  size_t out_size);


/**
 * Parse the configuration to determine on which port
 * or UNIX domain path we should run an HTTP service.
 *
 * @param cfg configuration to parse
 * @param section section of the configuration to parse (usually "exchange")
 * @param[out] rport set to the port number, or 0 for none
 * @param[out] unix_path set to the UNIX path, or NULL for none
 * @param[out] unix_mode set to the mode to be used for @a unix_path
 * @return #GNUNET_OK on success
 */
int
TALER_MHD_parse_config (const struct GNUNET_CONFIGURATION_Handle *cfg,
                        const char *section,
                        uint16_t *rport,
                        char **unix_path,
                        mode_t *unix_mode);


/**
 * Function called for logging by MHD.
 *
 * @param cls closure, NULL
 * @param fm format string (`printf()`-style)
 * @param ap arguments to @a fm
 */
void
TALER_MHD_handle_logs (void *cls,
                       const char *fm,
                       va_list ap);


/**
 * Open UNIX domain socket for listining at @a unix_path with
 * permissions @a unix_mode.
 *
 * @param unix_path where to listen
 * @param unix_mode access permissions to set
 * @return -1 on error, otherwise the listen socket
 */
int
TALER_MHD_open_unix_path (const char *unix_path,
                          mode_t unix_mode);


/**
 * Bind a listen socket to the UNIX domain path
 * or the TCP port and IP address as specified
 * in @a cfg in section @a section.  IF only a
 * port was specified, set @a port and return -1.
 * Otherwise, return the bound file descriptor.
 *
 * @param cfg configuration to parse
 * @param section configuration section to use
 * @param[out] port port to set, if TCP without BINDTO
 * @return -1 and a port of zero on error, otherwise
 *    either -1 and a port, or a bound stream socket
 */
int
TALER_MHD_bind (const struct GNUNET_CONFIGURATION_Handle *cfg,
                const char *section,
                uint16_t *port);


/**
 * Prepared responses for legal documents
 * (terms of service, privacy policy).
 */
struct TALER_MHD_Legal;


/**
 * Load set of legal documents as specified in
 * @a cfg in section @a section where the Etag
 * is given under the @param tagoption and the
 * directory under the @a diroption.
 *
 * @param cfg configuration to use
 * @param section section to load values from
 * @param diroption name of the option with the
 *        path to the legal documents
 * @param tagoption name of the files to use
 *        for the legal documents and the Etag
 * @return NULL on error
 */
struct TALER_MHD_Legal *
TALER_MHD_legal_load (const struct GNUNET_CONFIGURATION_Handle *cfg,
                      const char *section,
                      const char *diroption,
                      const char *tagoption);


/**
 * Free set of legal documents
 *
 * @param leg legal documents to free
 */
void
TALER_MHD_legal_free (struct TALER_MHD_Legal *legal);


/**
 * Generate a response with a legal document in
 * the format and language of the user's choosing.
 *
 * @param conn HTTP connection to handle
 * @param legal legal document to serve
 * @return MHD result code
 */
int
TALER_MHD_reply_legal (struct MHD_Connection *conn,
                       struct TALER_MHD_Legal *legal);


/**
 * Send back a "204 No Content" response with headers
 * for the CORS pre-flight request.
 *
 * @param connection the MHD connection
 * @return MHD result code
 */
int
TALER_MHD_reply_cors_preflight (struct MHD_Connection *connection);

#endif
