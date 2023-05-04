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
#include <gnunet/gnunet_mhd_compat.h>


/**
 * Maximum POST request size.
 */
#define TALER_MHD_REQUEST_BUFFER_MAX (1024 * 1024 * 16)


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
 * Set global options for response generation within libtalermhd.
 *
 * @param go global options to use
 */
void
TALER_MHD_setup (enum TALER_MHD_GlobalOptions go);


/**
 * Add headers we want to return in every response.  Useful for testing, like
 * if we want to always close connections.
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
MHD_RESULT
TALER_MHD_body_compress (void **buf,
                         size_t *buf_size);


/**
 * Is HTTP body deflate compression supported by the client?
 *
 * @param connection connection to check
 * @return #MHD_YES if 'deflate' compression is allowed
 */
MHD_RESULT
TALER_MHD_can_compress (struct MHD_Connection *connection);


/**
 * Check if @a mime matches the @a accept_pattern.  For this function, the @a
 * accept_pattern may include multiple values separated by ";".
 *
 * @param accept_pattern a mime pattern like "text/plain"
 *        or "image/STAR" or "text/plain; text/xml"
 * @param mime the mime type to match
 * @return true if @a mime matches the @a accept_pattern
 */
bool
TALER_MHD_xmime_matches (const char *accept_pattern,
                         const char *mime);


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
MHD_RESULT
TALER_MHD_reply_json (struct MHD_Connection *connection,
                      const json_t *json,
                      unsigned int response_code);


/**
 * Send JSON object as response, and free the @a json
 * object.
 *
 * @param connection the MHD connection
 * @param json the json object (freed!)
 * @param response_code the http response code
 * @return MHD result code
 */
MHD_RESULT
TALER_MHD_reply_json_steal (struct MHD_Connection *connection,
                            json_t *json,
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
MHD_RESULT
TALER_MHD_reply_json_pack (struct MHD_Connection *connection,
                           unsigned int response_code,
                           const char *fmt,
                           ...);


/**
 * Function to call to handle the request by building a JSON
 * reply from varargs.
 *
 * @param connection the MHD connection to handle
 * @param response_code HTTP response code to use
 * @param ... varargs of JSON pack specification
 * @return MHD result code
 */
#define TALER_MHD_REPLY_JSON_PACK(connection,response_code,...) \
  TALER_MHD_reply_json_steal (connection, GNUNET_JSON_PACK (__VA_ARGS__), \
                              response_code)


/**
 * Send a response indicating an error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param http_status HTTP status code to use
 * @param detail additional optional detail about the error
 * @return a MHD result code
 */
MHD_RESULT
TALER_MHD_reply_with_error (struct MHD_Connection *connection,
                            unsigned int http_status,
                            enum TALER_ErrorCode ec,
                            const char *detail);


/**
 * Send a response indicating an error. The HTTP status code is
 * to be derived from the @a ec.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param detail additional optional detail about the error
 * @return a MHD result code
 */
MHD_RESULT
TALER_MHD_reply_with_ec (struct MHD_Connection *connection,
                         enum TALER_ErrorCode ec,
                         const char *detail);


/**
 * Produce HTTP "Date:" header.
 *
 * @param at time to write to @a date
 * @param[out] date where to write the header, with
 *        at least 128 bytes available space.
 */
void
TALER_MHD_get_date_string (struct GNUNET_TIME_Absolute at,
                           char date[128]);


/**
 * Make JSON response object.
 *
 * @param json the json object
 * @return MHD response object
 */
struct MHD_Response *
TALER_MHD_make_json (const json_t *json);


/**
 * Make JSON response object and free @a json.
 *
 * @param json the json object, freed.
 * @return MHD response object
 */
struct MHD_Response *
TALER_MHD_make_json_steal (json_t *json);


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
 * Make JSON response object.
 *
 * @param ... varargs
 * @return MHD response object
 */
#define TALER_MHD_MAKE_JSON_PACK(...) \
  TALER_MHD_make_json_steal (GNUNET_JSON_PACK (__VA_ARGS__))


/**
 * Pack Taler error code @a ec and associated hint into a
 * JSON object.
 *
 * @param ec error code to pack
 * @return packer array entries (two!)
 */
#define TALER_MHD_PACK_EC(ec) \
  GNUNET_JSON_pack_uint64 ("code", ec), \
  GNUNET_JSON_pack_string ("hint", TALER_ErrorCode_get_hint (ec))

/**
 * Create a response indicating an internal error.
 *
 * @param ec error code to return
 * @param detail additional optional detail about the error, can be NULL
 * @return a MHD response object
 */
struct MHD_Response *
TALER_MHD_make_error (enum TALER_ErrorCode ec,
                      const char *detail);


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
MHD_RESULT
TALER_MHD_reply_request_too_large (struct MHD_Connection *connection);


/**
 * Function to call to handle the request by sending
 * back a redirect to the AGPL source code.
 *
 * @param connection the MHD connection to handle
 * @param url where to redirect for the sources
 * @return MHD result code
 */
MHD_RESULT
TALER_MHD_reply_agpl (struct MHD_Connection *connection,
                      const char *url);


/**
 * Function to call to handle the request by sending
 * back static data.
 *
 * @param connection the MHD connection to handle
 * @param http_status status code to return
 * @param mime_type content-type to use
 * @param body response payload
 * @param body_size number of bytes in @a body
 * @return MHD result code
 */
MHD_RESULT
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
 * #TALER_MHD_parse_post_cleanup_callback().
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
enum GNUNET_GenericReturnValue
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
 * specification.  If parsing fails, we return an HTTP
 * status code of 400 (#MHD_HTTP_BAD_REQUEST).
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
enum GNUNET_GenericReturnValue
TALER_MHD_parse_json_data (struct MHD_Connection *connection,
                           const json_t *root,
                           struct GNUNET_JSON_Specification *spec);


/**
 * Parse JSON object that we (the server!) generated into components based on
 * the given field specification.  The difference to
 * #TALER_MHD_parse_json_data() is that this function will fail
 * with an HTTP failure of 500 (internal server error) in case
 * parsing fails, instead of blaming it on the client with a
 * 400 (#MHD_HTTP_BAD_REQUEST).
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
enum GNUNET_GenericReturnValue
TALER_MHD_parse_internal_json_data (struct MHD_Connection *connection,
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
enum GNUNET_GenericReturnValue
TALER_MHD_parse_json_array (struct MHD_Connection *connection,
                            const json_t *root,
                            struct GNUNET_JSON_Specification *spec,
                            ...);


/**
 * Extract optional "timeout_ms" argument from request.
 *
 * @param connection the MHD connection
 * @param[out] expiration set to #GNUNET_TIME_UNIT_ZERO_ABS if there was no timeout,
 *         the current time plus the value given under "timeout_ms" otherwise
 * @return #GNUNET_OK on success, #GNUNET_NO if an
 *     error was returned on @a connection (caller should return #MHD_YES) and
 *     #GNUNET_SYSERR if we failed to return an error (caller should return #MHD_NO)
 */
enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_timeout (struct MHD_Connection *connection,
                                     struct GNUNET_TIME_Absolute *expiration);


/**
 * Extract optional "timeout_ms" argument from request.
 * Macro that *returns* #MHD_YES/#MHD_NO if the "timeout_ms"
 * argument existed but failed to parse.
 *
 * @param connection the MHD connection
 * @param[out] expiration set to #GNUNET_TIME_UNIT_ZERO_ABS if there was no timeout,
 *         the current time plus the value given under "timeout_ms" otherwise
 */
#define TALER_MHD_parse_request_timeout(connection,expiration) \
  do {                                                         \
    switch (TALER_MHD_parse_request_arg_timeout (connection,   \
                                                 expiration))  \
    {                      \
    case GNUNET_SYSERR:    \
      GNUNET_break (0);    \
      return MHD_NO;       \
    case GNUNET_NO:        \
      GNUNET_break_op (0); \
    case GNUNET_OK:        \
      break;               \
    }                      \
  } while (0)


/**
 * Extract fixed-size base32crockford encoded data from request argument.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of @a out_data
 * @param[out] present set to true if argument was found
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_data (struct MHD_Connection *connection,
                                  const char *param_name,
                                  void *out_data,
                                  size_t out_size,
                                  bool *present);


/**
 * Extract fixed-size base32crockford encoded data from request header.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param header_name the name of the HTTP header with the value
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of @a out_data
 * @param[out] present set to true if argument was found
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_header_data (struct MHD_Connection *connection,
                                     const char *header_name,
                                     void *out_data,
                                     size_t out_size,
                                     bool *present);

/**
 * Extract fixed-size base32crockford encoded data from request.
 *
 * @param connection the MHD connection
 * @param name the name of the parameter with the key
 * @param[out] out_data pointer to store the result, type must determine size
 * @param[in,out] required pass true to require presence of this argument; if 'false'
 *                         set to true if the argument was found
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
#define TALER_MHD_parse_request_arg_auto(connection,name,val,required) \
  do {                                                                 \
    bool p;                                                            \
    switch (TALER_MHD_parse_request_arg_data (connection, name,        \
                                              val, sizeof (*val), &p)) \
    {                      \
    case GNUNET_SYSERR:    \
      GNUNET_break (0);    \
      return MHD_NO;       \
    case GNUNET_NO:        \
      GNUNET_break_op (0); \
      return MHD_YES;      \
    case GNUNET_OK:        \
      if (required & (! p)) \
      return TALER_MHD_reply_with_error (   \
        connection,                         \
        MHD_HTTP_BAD_REQUEST,               \
        TALER_EC_GENERIC_PARAMETER_MISSING, \
        name);                              \
      required = p;                         \
      break;               \
    }                      \
  } while (0)


/**
 * Extract required fixed-size base32crockford encoded data from request.
 *
 * @param connection the MHD connection
 * @param name the name of the parameter with the key
 * @param[out] out_data pointer to store the result, type must determine size
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
#define TALER_MHD_parse_request_arg_auto_t(connection,name,val) \
  do {                                                          \
    bool b = true;                                              \
    TALER_MHD_parse_request_arg_auto (connection,name,val,b);   \
  } while (0)

/**
 * Extract fixed-size base32crockford encoded data from request.
 *
 * @param connection the MHD connection
 * @param name the name of the header with the key
 * @param[out] out_data pointer to store the result, type must determine size
 * @param[in,out] required pass true to require presence of this argument; if 'false'
 *                         set to true if the argument was found
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
#define TALER_MHD_parse_request_header_auto(connection,name,val,required) \
  do {                                                                    \
    bool p;                                                               \
    switch (TALER_MHD_parse_request_header_data (connection, name,        \
                                                 val, sizeof (*val), &p)) \
    {                      \
    case GNUNET_SYSERR:    \
      GNUNET_break (0);    \
      return MHD_NO;       \
    case GNUNET_NO:        \
      GNUNET_break_op (0); \
      return MHD_YES;      \
    case GNUNET_OK:        \
      if (required & (! p)) \
      return TALER_MHD_reply_with_error (   \
        connection,                         \
        MHD_HTTP_BAD_REQUEST,               \
        TALER_EC_GENERIC_PARAMETER_MISSING, \
        name);                              \
      required = p;                         \
      break;               \
    }                      \
  } while (0)


/**
 * Extract required fixed-size base32crockford encoded data from request.
 *
 * @param connection the MHD connection
 * @param name the name of the header with the key
 * @param[out] out_data pointer to store the result, type must determine size
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
#define TALER_MHD_parse_request_header_auto_t(connection,name,val) \
  do {                                                             \
    bool b = true;                                                 \
    TALER_MHD_parse_request_header_auto (connection,name,val,b);   \
  } while (0)


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
enum GNUNET_GenericReturnValue
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
 * Bind a listen socket to the UNIX domain path or the TCP port and IP address
 * as specified in @a cfg in section @a section.  IF only a port was
 * specified, set @a port and return -1.  Otherwise, return the bound file
 * descriptor.
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
 * Start to run an event loop for @a daemon.
 * Only one daemon can be running per process
 * using this API.
 *
 * @param daemon the MHD service to run
 */
void
TALER_MHD_daemon_start (struct MHD_Daemon *daemon);


/**
 * Stop running the event loop for MHD.
 *
 * @return the daemon that we were previously running,
 *       or NULL if none was active
 */
struct MHD_Daemon *
TALER_MHD_daemon_stop (void);


/**
 * Trigger MHD daemon that is running. Needed when
 * a connection was resumed.
 */
void
TALER_MHD_daemon_trigger (void);


/**
 * Prepared responses for legal documents
 * (terms of service, privacy policy).
 */
struct TALER_MHD_Legal;


/**
 * Load set of legal documents as specified in @a cfg in section @a section
 * where the Etag is given under the @a tagoption and the directory under
 * the @a diroption.
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
 * @param legal legal documents to free
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
MHD_RESULT
TALER_MHD_reply_legal (struct MHD_Connection *conn,
                       struct TALER_MHD_Legal *legal);


/**
 * Send back a "204 No Content" response with headers
 * for the CORS pre-flight request.
 *
 * @param connection the MHD connection
 * @return MHD result code
 */
MHD_RESULT
TALER_MHD_reply_cors_preflight (struct MHD_Connection *connection);

#endif
