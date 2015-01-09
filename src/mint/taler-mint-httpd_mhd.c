/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-mint-httpd_mhd.c
 * @brief helpers for MHD interaction
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <libpq-fe.h>
#include <pthread.h>
#include "taler-mint-httpd_json.h"
#include "taler-mint-httpd.h"
#include "taler-mint-httpd_mhd.h"


/**
 * Function to call to handle the request by sending
 * back static data from the @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_static_response (struct RequestHandler *rh,
                                    struct MHD_Connection *connection,
                                    void **connection_cls,
                                    const char *upload_data,
                                    size_t *upload_data_size)
{
  struct MHD_Response *response;
  int ret;

  if (0 == rh->data_size)
    rh->data_size = strlen ((const char *) rh->data);
  response = MHD_create_response_from_buffer (rh->data_size,
                                              (void *) rh->data,
                                              MHD_RESPMEM_PERSISTENT);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
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
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_agpl_redirect (struct RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  const char *agpl =
    "This server is licensed under the Affero GPL. You will now be redirected to the source code.";
  struct MHD_Response *response;
  int ret;

  response = MHD_create_response_from_buffer (strlen (agpl),
                                              (void *) agpl,
                                              MHD_RESPMEM_PERSISTENT);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  if (NULL != rh->mime_type)
    (void) MHD_add_response_header (response,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    rh->mime_type);
  MHD_add_response_header (response,
                           MHD_HTTP_HEADER_LOCATION,
                           "http://www.git.taler.net/?p=mint.git");
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}


/**
 * Function to call to handle the request by building a JSON
 * reply from varargs.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param response_code HTTP response code to use
 * @param do_cache can the response be cached? (0: no, 1: yes)
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD result code
 */
int
TALER_MINT_helper_send_json_pack (struct RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void *connection_cls,
                                  int response_code,
                                  int do_cache,
                                  const char *fmt,
                                  ...)
{
  int ret;
  json_t *json;
  va_list argp;
  char *json_str;
  struct MHD_Response *response;

  va_start (argp, fmt);
  json = json_vpack_ex (NULL, 0, fmt, argp);
  va_end (argp);
  if (NULL == json)
    return MHD_NO;
  json_str = json_dumps (json, JSON_INDENT(2));
  json_decref (json);
  if (NULL == json_str)
    return MHD_NO;
  response = MHD_create_response_from_buffer (strlen (json_str),
                                              json_str,
                                              MHD_RESPMEM_MUST_FREE);
  if (NULL == response)
  {
    free (json_str);
    return MHD_NO;
  }
  if (NULL != rh->mime_type)
    (void) MHD_add_response_header (response,
                                    MHD_HTTP_HEADER_CONTENT_TYPE,
                                    rh->mime_type);
  ret = MHD_queue_response (connection,
                            response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}


/**
 * Function to call to handle the request by building a JSON
 * reply with an error message from @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_send_json_pack_error (struct RequestHandler *rh,
                                         struct MHD_Connection *connection,
                                         void **connection_cls,
                                         const char *upload_data,
                                         size_t *upload_data_size)
{
  return TALER_MINT_helper_send_json_pack (rh,
                                           connection,
                                           connection_cls,
                                           1, /* caching enabled */
                                           rh->response_code,
                                           "{s:s}",
                                           "error",
                                           rh->data);
}


/**
 * Send a response for an invalid argument.
 *
 * @param connection the MHD connection to use
 * @param param_name the parameter that is missing
 * @return a GNUnet result code
 */
static int
request_arg_invalid (struct MHD_Connection *connection,
                     const char *param_name)
{
  json_t *json;
  json = json_pack ("{ s:s, s:s }",
                    "error", "invalid parameter",
                    "parameter", param_name);
  if (MHD_YES != send_response_json (connection, json, MHD_HTTP_BAD_REQUEST))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_NO;
}


/**
 * Get a GET paramater that is a string,
 * or send an error response if the parameter is missing.
 *
 * @param connection the connection to get the parameter from /
 *                   send the error response to
 * @param param_name the parameter name
 * @param str pointer to store the parameter string,
 *            must be freed by the caller
 * @return GNUNET_YES if the parameter is present and valid,
 *         GNUNET_NO if the parameter is missing
 *         GNUNET_SYSERR on internal error
 */
static int
request_arg_require_string (struct MHD_Connection *connection,
                            const char *param_name,
                            const char **str)
{
  *str = MHD_lookup_connection_value (connection, MHD_GET_ARGUMENT_KIND, param_name);
  if (NULL == *str)
  {
    if (MHD_NO ==
        request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                "{ s:s, s:s }",
                                "error", "missing parameter",
                                "parameter", param_name))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Extraxt base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of data
 * @return
 *   GNUNET_YES if the the argument is present
 *   GNUNET_NO if the argument is absent or malformed
 *   GNUNET_SYSERR on internal error (error response could not be sent)
 */
int
TALER_MINT_mhd_request_arg_data (struct MHD_Connection *connection,
                                 const char *param_name,
                                 void *out_data,
                                 size_t out_size)
{
  const char *str;
  int ret;

  if (GNUNET_OK != (ret = request_arg_require_string (connection, param_name, &str)))
    return ret;
  if (GNUNET_OK != GNUNET_STRINGS_string_to_data (str, strlen (str), out_data, out_size))
    return request_arg_invalid (connection, param_name);
  return GNUNET_OK;
}



/* end of taler-mint-httpd_mhd.c */
