/*
  This file is part of TALER
  Copyright (C) 2014-2017 Inria & GNUnet e.V.

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
 * @file taler-exchange-httpd_responses.c
 * @brief API for generating genric replies of the exchange; these
 *        functions are called TAH_RESPONSE_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <zlib.h>
#include "taler-auditor-httpd_responses.h"
#include "taler_util.h"
#include "taler_json_lib.h"


/**
 * Add headers we want to return in every response.
 * Useful for testing, like if we want to always close
 * connections.
 *
 * @param response response to modify
 */
void
TAH_RESPONSE_add_global_headers (struct MHD_Response *response)
{
  if (TAH_auditor_connection_close)
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (response,
                                           MHD_HTTP_HEADER_CONNECTION,
                                           "close"));
}


/**
 * Is HTTP body deflate compression supported by the client?
 *
 * @param connection connection to check
 * @return #MHD_YES if 'deflate' compression is allowed
 *
 * Note that right now we're ignoring q-values, which is technically
 * not correct, and also do not support "*" anywhere but in a line by
 * itself.  This should eventually be fixed, see also
 * https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
 */
int
TAH_RESPONSE_can_compress (struct MHD_Connection *connection)
{
  const char *ae;
  const char *de;

  ae = MHD_lookup_connection_value (connection,
				    MHD_HEADER_KIND,
				    MHD_HTTP_HEADER_ACCEPT_ENCODING);
  if (NULL == ae)
    return MHD_NO;
  if (0 == strcmp (ae,
                   "*"))
    return MHD_YES;
  de = strstr (ae,
	       "deflate");
  if (NULL == de)
    return MHD_NO;
  if ( ( (de == ae) ||
	 (de[-1] == ',') ||
	 (de[-1] == ' ') ) &&
       ( (de[strlen ("deflate")] == '\0') ||
	 (de[strlen ("deflate")] == ',') ||
         (de[strlen ("deflate")] == ';') ) )
    return MHD_YES;
  return MHD_NO;
}


/**
 * Try to compress a response body.  Updates @a buf and @a buf_size.
 *
 * @param[in,out] buf pointer to body to compress
 * @param[in,out] buf_size pointer to initial size of @a buf
 * @return #MHD_YES if @a buf was compressed
 */
int
TAH_RESPONSE_body_compress (void **buf,
			    size_t *buf_size)
{
  Bytef *cbuf;
  uLongf cbuf_size;
  int ret;

  cbuf_size = compressBound (*buf_size);
  cbuf = malloc (cbuf_size);
  if (NULL == cbuf)
    return MHD_NO;
  ret = compress (cbuf,
		  &cbuf_size,
		  (const Bytef *) *buf,
		  *buf_size);
  if ( (Z_OK != ret) ||
       (cbuf_size >= *buf_size) )
  {
    /* compression failed */
    free (cbuf);
    return MHD_NO;
  }
  free (*buf);
  *buf = (void *) cbuf;
  *buf_size = (size_t) cbuf_size;
  return MHD_YES;
}


/**
 * Send JSON object as response.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param response_code the http response code
 * @return MHD result code
 */
int
TAH_RESPONSE_reply_json (struct MHD_Connection *connection,
                         const json_t *json,
                         unsigned int response_code)
{
  struct MHD_Response *resp;
  void *json_str;
  size_t json_len;
  int ret;
  int comp;

  json_str = json_dumps (json,
			 JSON_INDENT(2));
  if (NULL == json_str)
  {
    /**
     * This log helps to figure out which
     * function called this one and assert-failed.
     */
    TALER_LOG_ERROR ("Aborting json-packing for HTTP code: %u\n",
                     response_code);

    GNUNET_assert (0);
    return MHD_NO;
  }
  json_len = strlen (json_str);
  /* try to compress the body */
  comp = MHD_NO;
  if (MHD_YES ==
      TAH_RESPONSE_can_compress (connection))
    comp = TAH_RESPONSE_body_compress (&json_str,
				       &json_len);
  resp = MHD_create_response_from_buffer (json_len,
                                          json_str,
                                          MHD_RESPMEM_MUST_FREE);
  if (NULL == resp)
  {
    free (json_str);
    GNUNET_break (0);
    return MHD_NO;
  }
  TAH_RESPONSE_add_global_headers (resp);
  (void) MHD_add_response_header (resp,
                                  MHD_HTTP_HEADER_CONTENT_TYPE,
                                  "application/json");
  if (MHD_YES == comp)
  {
    /* Need to indicate to client that body is compressed */
    if (MHD_NO ==
	MHD_add_response_header (resp,
				 MHD_HTTP_HEADER_CONTENT_ENCODING,
				 "deflate"))
    {
      GNUNET_break (0);
      MHD_destroy_response (resp);
      return MHD_NO;
    }
  }
  ret = MHD_queue_response (connection,
                            response_code,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


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
TAH_RESPONSE_reply_json_pack (struct MHD_Connection *connection,
                              unsigned int response_code,
                              const char *fmt,
                              ...)
{
  json_t *json;
  va_list argp;
  int ret;
  json_error_t jerror;

  va_start (argp, fmt);
  json = json_vpack_ex (&jerror, 0, fmt, argp);
  va_end (argp);
  if (NULL == json)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to pack JSON with format `%s': %s\n",
                fmt,
                jerror.text);
    GNUNET_break (0);
    return MHD_NO;
  }
  ret = TAH_RESPONSE_reply_json (connection,
                                 json,
                                 response_code);
  json_decref (json);
  return ret;
}


/**
 * Send a response indicating an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_arg_invalid (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I, s:s}",
                                       "error", "invalid parameter",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating an argument refering to a
 * resource unknown to the auditor (i.e. unknown reserve or
 * denomination key).
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_arg_unknown (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       "{s:s, s:I, s:s}",
                                       "error", "unknown entity referenced",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating an invalid signature.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is invalid
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_signature_invalid (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec,
                                      const char *param_name)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       "{s:s, s:I, s:s}",
                                       "error", "invalid signature",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating a missing argument.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param param_name the parameter that is missing
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_arg_missing (struct MHD_Connection *connection,
				enum TALER_ErrorCode ec,
                                const char *param_name)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I, s:s}",
                                       "error", "missing parameter",
				       "code", (json_int_t) ec,
                                       "parameter", param_name);
}


/**
 * Send a response indicating permission denied.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about why access was denied
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_permission_denied (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec,
                                      const char *hint)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       "{s:s, s:I, s:s}",
                                       "error", "permission denied",
				       "code", (json_int_t) ec,
                                       "hint", hint);
}


/**
 * Send a response indicating an internal error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about the internal error's nature
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_internal_error (struct MHD_Connection *connection,
				   enum TALER_ErrorCode ec,
                                   const char *hint)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       "{s:s, s:I, s:s}",
                                       "error", "internal error",
				       "code", (json_int_t) ec,
                                       "hint", hint);
}


/**
 * Send a response indicating an external error.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @param hint hint about the error's nature
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_external_error (struct MHD_Connection *connection,
				   enum TALER_ErrorCode ec,
                                   const char *hint)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I, s:s}",
                                       "error", "client error",
				       "code", (json_int_t) ec,
                                       "hint", hint);
}


/**
 * Send a response indicating an error committing a
 * transaction (concurrent interference).
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_commit_error (struct MHD_Connection *connection,
				 enum TALER_ErrorCode ec)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       "{s:s, s:I}",
                                       "error", "commit failure",
				       "code", (json_int_t) ec);
}


/**
 * Send a response indicating a failure to talk to the Auditor's
 * database.
 *
 * @param connection the MHD connection to use
 * @param ec error code uniquely identifying the error
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_internal_db_error (struct MHD_Connection *connection,
				      enum TALER_ErrorCode ec)
{
  return TAH_RESPONSE_reply_internal_error (connection,
					    ec,
                                            "Failure in database interaction");
}


/**
 * Send a response indicating that the request was too big.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_request_too_large (struct MHD_Connection *connection)
{
  struct MHD_Response *resp;
  int ret;

  resp = MHD_create_response_from_buffer (0,
                                          NULL,
                                          MHD_RESPMEM_PERSISTENT);
  if (NULL == resp)
    return MHD_NO;
  TAH_RESPONSE_add_global_headers (resp);
  ret = MHD_queue_response (connection,
                            MHD_HTTP_REQUEST_ENTITY_TOO_LARGE,
                            resp);
  MHD_destroy_response (resp);
  return ret;
}


/**
 * Send a response indicating that the JSON was malformed.
 *
 * @param connection the MHD connection to use
 * @return a MHD result code
 */
int
TAH_RESPONSE_reply_invalid_json (struct MHD_Connection *connection)
{
  return TAH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       "{s:s, s:I}",
                                       "error", "invalid json",
				       "code", (json_int_t) TALER_EC_JSON_INVALID);
}


/* end of taler-auditor-httpd_responses.c */
