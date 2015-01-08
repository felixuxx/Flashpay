#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_microhttpd_lib.h"



/**
 * Initial size for POST
 * request buffer.
 */
#define REQUEST_BUFFER_INITIAL 1024

/**
 * Maximum POST request size
 */
#define REQUEST_BUFFER_MAX (1024*1024)


/**
 * Buffer for POST requests.
 */
struct Buffer
{
  /**
   * Allocated memory
   */
  char *data;

  /**
   * Number of valid bytes in buffer.
   */
  size_t fill;

  /**
   * Number of allocated bytes in buffer.
   */
  size_t alloc;
};


/**
 * Initialize a buffer.
 *
 * @param buf the buffer to initialize
 * @param data the initial data
 * @param data_size size of the initial data
 * @param alloc_size size of the buffer
 * @param max_size maximum size that the buffer can grow to
 * @return a GNUnet result code
 */
static int
buffer_init (struct Buffer *buf, const void *data, size_t data_size, size_t alloc_size, size_t max_size)
{
  if (data_size > max_size || alloc_size > max_size)
    return GNUNET_SYSERR;
  if (data_size > alloc_size)
    alloc_size = data_size;
  buf->data = GNUNET_malloc (alloc_size);
  memcpy (buf->data, data, data_size);
  return GNUNET_OK;
}


/**
 * Free the data in a buffer.  Does *not* free
 * the buffer object itself.
 *
 * @param buf buffer to de-initialize
 */
static void
buffer_deinit (struct Buffer *buf)
{
  GNUNET_free (buf->data);
  buf->data = NULL;
}


/**
 * Append data to a buffer, growing the buffer if necessary.
 *
 * @param buf the buffer to append to
 * @param data the data to append
 * @param size the size of @a data
 * @param max_size maximum size that the buffer can grow to
 * @return GNUNET_OK on success,
 *         GNUNET_NO if the buffer can't accomodate for the new data
 *         GNUNET_SYSERR on fatal error (out of memory?)
 */
static int
buffer_append (struct Buffer *buf, const void *data, size_t data_size, size_t max_size)
{
  if (buf->fill + data_size > max_size)
    return GNUNET_NO;
  if (data_size + buf->fill > buf->alloc)
  {
    char *new_buf;
    size_t new_size = buf->alloc;
    while (new_size < buf->fill + data_size)
      new_size += 2;
    if (new_size > max_size)
      return GNUNET_NO;
    new_buf = GNUNET_malloc (new_size);
    memcpy (new_buf, buf->data, buf->fill);
    buf->data = new_buf;
    buf->alloc = new_size;
  }
  memcpy (buf->data + buf->fill, data, data_size);
  buf->fill += data_size;
  return GNUNET_OK;
}


/**
 * Send JSON object as response.  Decreases the reference count of the
 * JSON object.
 *
 * @param connection the MHD connection
 * @param json the json object
 * @param status_code the http status code
 * @return MHD result code
 */
int
send_response_json (struct MHD_Connection *connection,
                    json_t *json,
                    unsigned int status_code)
{
  struct MHD_Response *resp;
  char *json_str;

  json_str = json_dumps (json, JSON_INDENT(2));
  json_decref (json);
  resp = MHD_create_response_from_buffer (strlen (json_str), json_str,
                                          MHD_RESPMEM_MUST_FREE);
  if (NULL == resp)
    return MHD_NO;
  return MHD_queue_response (connection, status_code, resp);
}


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
                        const char *fmt, ...)
{
  json_t *msg;
  va_list argp;
  int ret;

  va_start(argp, fmt);
  msg = json_vpack_ex (NULL, 0, fmt, argp);
  va_end(argp);
  if (NULL == msg)
    return MHD_NO;
  ret = send_response_json (connection, msg, http_code);
  json_decref (msg);
  return ret;
}


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
                   json_t **json)
{
  struct Buffer *r = *con_cls;

  if (NULL == *con_cls)
  {
    /* We are seeing a fresh POST request. */

    r = GNUNET_new (struct Buffer);
    if (GNUNET_OK != buffer_init (r, upload_data, *upload_data_size,
                 REQUEST_BUFFER_INITIAL, REQUEST_BUFFER_MAX))
    {
      *con_cls = NULL;
      buffer_deinit (r);
      GNUNET_free (r);
      return GNUNET_SYSERR;
    }
    *upload_data_size = 0;
    *con_cls = r;
    return GNUNET_NO;
  }
  if (0 != *upload_data_size)
  {
    /* We are seeing an old request with more data available. */

    if (GNUNET_OK != buffer_append (r, upload_data, *upload_data_size,
                                    REQUEST_BUFFER_MAX))
    {
      /* Request too long or we're out of memory. */

      *con_cls = NULL;
      buffer_deinit (r);
      GNUNET_free (r);
      return GNUNET_SYSERR;
    }
    *upload_data_size = 0;
    return GNUNET_NO;
  }

  /* We have seen the whole request. */

  *json = json_loadb (r->data, r->fill, 0, NULL);
  buffer_deinit (r);
  GNUNET_free (r);
  if (NULL == *json)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING, "Can't parse JSON request body\n");
    return request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                   GNUNET_NO, GNUNET_SYSERR,
                                   "{s:s}",
                                   "error", "invalid json");
  }
  *con_cls = NULL;

  return GNUNET_YES;
}


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
                          const json_t *root, ...)
{
  va_list argp;
  int ignore = GNUNET_NO;
  // what's our current path from 'root'?
  json_t *path;

  path = json_array ();

  va_start(argp, root);

  while (1)
  {
    int command = va_arg(argp, int);
    switch (command)
    {
      case JNAV_FIELD:
        {
          const char *fname = va_arg(argp, const char *);
          if (GNUNET_YES == ignore)
            break;
          json_array_append_new (path, json_string (fname));
          root = json_object_get (root, fname);
          if (NULL == root)
          {

            (void) request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                           0, 0,
                                           "{s:s,s:o}",
                                           "error", "missing field in JSON",
                                           "path", path);
            ignore = GNUNET_YES;
            break;
          }
        }
        break;
      case JNAV_INDEX:
        {
          int fnum = va_arg(argp, int);
          if (GNUNET_YES == ignore)
            break;
          json_array_append_new (path, json_integer (fnum));
          root = json_array_get (root, fnum);
          if (NULL == root)
          {
            (void) request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                           0, 0,
                                           "{s:s, s:o}",
                                           "error", "missing index in JSON",
                                           "path", path);
            ignore = GNUNET_YES;
            break;
          }
        }
        break;
      case JNAV_RET_DATA:
        {
          void *where = va_arg (argp, void *);
          size_t len = va_arg (argp, size_t);
          const char *str;
          int res;

          va_end(argp);
          if (GNUNET_YES == ignore)
            return GNUNET_NO;
          str = json_string_value (root);
          if (NULL == str)
          {
            (void) request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                           0, 0,
                                           "{s:s, s:o}",
                                           "error", "string expected",
                                           "path", path);
            return GNUNET_NO;
          }
          res = GNUNET_STRINGS_string_to_data (str, strlen (str),
                                                where, len);
          if (GNUNET_OK != res)
          {
            (void) request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                           0, 0,
                                           "{s:s,s:o}",
                                           "error", "malformed binary data in JSON",
                                           "path", path);
            return GNUNET_NO;
          }
          return GNUNET_YES;
        }
        break;
      case JNAV_RET_DATA_VAR:
        {
          void **where = va_arg (argp, void **);
          size_t *len = va_arg (argp, size_t *);
          const char *str;

          va_end(argp);
          if (GNUNET_YES == ignore)
            return GNUNET_NO;
          str = json_string_value (root);
          if (NULL == str)
          {
            GNUNET_break (0);
            return GNUNET_SYSERR;
          }
          *len = (strlen (str) * 5) / 8;
          if (where != NULL)
          {
            int res;
            *where = GNUNET_malloc (*len);
            res = GNUNET_STRINGS_string_to_data (str, strlen (str),
                                                  *where, *len);
            if (GNUNET_OK != res)
            {
              (void) request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                             0, 0,
                                             "{s:s, s:o}",
                                             "error", "malformed binary data in JSON",
                                             "path", path);
              return GNUNET_NO;
            }
          }
          return GNUNET_OK;
        }
        break;
      case JNAV_RET_TYPED_JSON:
        {
          int typ = va_arg (argp, int);
          const json_t **r_json = va_arg (argp, const json_t **);

          va_end(argp);
          if (GNUNET_YES == ignore)
            return GNUNET_NO;
          if (typ != -1 && json_typeof (root) != typ)
          {
              (void) request_send_json_pack (connection, MHD_HTTP_BAD_REQUEST,
                                             0, 0,
                                             "{s:s, s:i, s:i s:o}",
                                             "error", "wrong JSON field type",
                                             "type_expected", typ,
                                             "type_actual", json_typeof (root),
                                             "path", path);
            return GNUNET_NO;
          }
          *r_json = root;
          return GNUNET_OK;
        }
        break;
      default:
        GNUNET_assert (0);
    }
  }
  GNUNET_assert (0);
}



