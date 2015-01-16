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
 * @file taler-mint-httpd_parsing.h
 * @brief functions to parse incoming requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */

#ifndef TALER_MICROHTTPD_LIB_H_
#define TALER_MICROHTTPD_LIB_H_


#include <microhttpd.h>
#include <jansson.h>


/**
 * Constants for JSON navigation description.
 */
enum
{
  /**
   * Access a field.
   * Param: const char *
   */
  JNAV_FIELD,
  /**
   * Access an array index.
   * Param: int
   */
  JNAV_INDEX,
  /**
   * Return base32crockford encoded data of
   * constant size.
   * Params: (void *, size_t)
   */
  JNAV_RET_DATA,
  /**
   * Return base32crockford encoded data of
   * variable size.
   * Params: (void **, size_t *)
   */
  JNAV_RET_DATA_VAR,
  /**
   * Return a json object, which must be
   * of the given type (JSON_* type constants,
   * or -1 for any type).
   * Params: (int, json_t **)
   */
  JNAV_RET_TYPED_JSON
};


/**
 * Process a POST request containing a JSON object.
 *
 * @param connection the MHD connection
 * @param con_cs the closure (contains a 'struct Buffer *')
 * @param upload_data the POST data
 * @param upload_data_size the POST data size
 * @param json the JSON object for a completed request
 *
 * @returns
 *    GNUNET_YES if json object was parsed
 *    GNUNET_NO is request incomplete or invalid
 *    GNUNET_SYSERR on internal error
 */
int
process_post_json (struct MHD_Connection *connection,
                   void **con_cls,
                   const char *upload_data,
                   size_t *upload_data_size,
                   json_t **json);


/**
 * Navigate through a JSON tree.
 *
 * Sends an error response if navigation is impossible (i.e.
 * the JSON object is invalid)
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param ... navigation specification (see JNAV_*)
 * @return GNUNET_YES if navigation was successful
 *         GNUNET_NO if json is malformed, error response was generated
 *         GNUNET_SYSERR on internal error
 */
int
request_json_require_nav (struct MHD_Connection *connection,
                          const json_t *root, ...);




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
                          size_t out_size);




#endif /* TALER_MICROHTTPD_LIB_H_ */
