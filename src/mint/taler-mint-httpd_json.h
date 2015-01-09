

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
 * Send JSON object as response.  Decreases
 * the reference count of the JSON object.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param status_code the http status code
 * @return MHD result code (MHD_YES on success)
 */
int
send_response_json (struct MHD_Connection *connection,
                    json_t *json,
                    unsigned int status_code);


/**
 * Send a JSON object via an MHD connection,
 * specified with the JANSSON pack syntax (see json_pack).
 *
 * @param connection connection to send the JSON over
 * @param http_code HTTP status for the response
 * @param fmt format string for pack
 * @param ... varargs
 * @return MHD_YES on success or MHD_NO on error
 */
int
request_send_json_pack (struct MHD_Connection *connection,
                        unsigned int http_code,
                        const char *fmt, ...);


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

#endif /* TALER_MICROHTTPD_LIB_H_ */
