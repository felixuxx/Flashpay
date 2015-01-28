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
 * @file taler-mint-httpd_parsing.c
 * @brief functions to parse incoming requests (MHD arguments and JSON snippets)
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */

#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler-mint-httpd_parsing.h"
#include "taler-mint-httpd_responses.h"


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
buffer_init (struct Buffer *buf,
             const void *data,
             size_t data_size,
             size_t alloc_size,
             size_t max_size)
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
 * @return #GNUNET_OK on success,
 *         #GNUNET_NO if the buffer can't accomodate for the new data
 */
static int
buffer_append (struct Buffer *buf,
               const void *data,
               size_t data_size,
               size_t max_size)
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
 * Process a POST request containing a JSON object.  This
 * function realizes an MHD POST processor that will
 * (incrementally) process JSON data uploaded to the HTTP
 * server.  It will store the required state in the
 * "connection_cls", which must be cleaned up using
 * #TALER_MINT_parse_post_cleanup_callback().
 *
 * @param connection the MHD connection
 * @param con_cs the closure (points to a `struct Buffer *`)
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
TALER_MINT_parse_post_json (struct MHD_Connection *connection,
                            void **con_cls,
                            const char *upload_data,
                            size_t *upload_data_size,
                            json_t **json)
{
  struct Buffer *r = *con_cls;

  *json = NULL;
  if (NULL == *con_cls)
  {
    /* We are seeing a fresh POST request. */
    r = GNUNET_new (struct Buffer);
    if (GNUNET_OK !=
        buffer_init (r,
                     upload_data,
                     *upload_data_size,
                     REQUEST_BUFFER_INITIAL,
                     REQUEST_BUFFER_MAX))
    {
      *con_cls = NULL;
      buffer_deinit (r);
      GNUNET_free (r);
      return (MHD_NO ==
              TALER_MINT_reply_internal_error (connection,
                                               "out of memory"))
        ? GNUNET_SYSERR : GNUNET_NO;
    }
    /* everything OK, wait for more POST data */
    *upload_data_size = 0;
    *con_cls = r;
    return GNUNET_YES;
  }
  if (0 != *upload_data_size)
  {
    /* We are seeing an old request with more data available. */

    if (GNUNET_OK !=
        buffer_append (r,
                       upload_data,
                       *upload_data_size,
                       REQUEST_BUFFER_MAX))
    {
      /* Request too long */
      *con_cls = NULL;
      buffer_deinit (r);
      GNUNET_free (r);
      return (MHD_NO ==
              TALER_MINT_reply_request_too_large (connection))
        ? GNUNET_SYSERR : GNUNET_NO;
    }
    /* everything OK, wait for more POST data */
    *upload_data_size = 0;
    return GNUNET_YES;
  }

  /* We have seen the whole request. */

  *json = json_loadb (r->data,
                      r->fill,
                      0,
                      NULL);
  buffer_deinit (r);
  GNUNET_free (r);
  if (NULL == *json)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Failed to parse JSON request body\n");
    return (MHD_YES ==
            TALER_MINT_reply_invalid_json (connection))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  *con_cls = NULL;

  return GNUNET_YES;
}


/**
 * Function called whenever we are done with a request
 * to clean up our state.
 *
 * @param con_cls value as it was left by
 *        #TALER_MINT_parse_post_json(), to be cleaned up
 */
void
TALER_MINT_parse_post_cleanup_callback (void *con_cls)
{
  struct Buffer *r = con_cls;

  if (NULL != r)
    buffer_deinit (r);
}


/**
 * Navigate through a JSON tree.
 *
 * Sends an error response if navigation is impossible (i.e.
 * the JSON object is invalid)
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param ... navigation specification (see `enum TALER_MINT_JsonNavigationCommand`)
 * @return
 *    #GNUNET_YES if navigation was successful
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error (no response was generated,
 *                       connection must be closed)
 */
int
GNUNET_MINT_parse_navigate_json (struct MHD_Connection *connection,
                                 const json_t *root,
                                 ...)
{
  va_list argp;
  int ret;
  json_t *path; /* what's our current path from 'root'? */

  path = json_array ();
  va_start (argp, root);
  ret = 2; /* just not any of the valid return values */
  while (2 == ret)
  {
    enum TALER_MINT_JsonNavigationCommand command
      = va_arg (argp,
                enum TALER_MINT_JsonNavigationCommand);

    switch (command)
    {
      case JNAV_FIELD:
        {
          const char *fname = va_arg(argp, const char *);

          json_array_append_new (path,
                                 json_string (fname));
          root = json_object_get (root,
                                  fname);
          if (NULL == root)
          {
            ret = (MHD_YES ==
                   TALER_MINT_reply_json_pack (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               "{s:s, s:s, s:o}",
                                               "error",
                                               "missing field in JSON",
                                               "field",
                                               fname,
                                               "path",
                                               path))
              ? GNUNET_NO : GNUNET_SYSERR;
            break;
          }
        }
        break;
      case JNAV_INDEX:
        {
          int fnum = va_arg(argp, int);

          json_array_append_new (path,
                                 json_integer (fnum));
          root = json_array_get (root,
                                 fnum);
          if (NULL == root)
          {
            ret = (MHD_YES ==
                   TALER_MINT_reply_json_pack (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               "{s:s, s:o}",
                                               "error",
                                               "missing index in JSON",
                                               "path", path))
              ? GNUNET_NO : GNUNET_SYSERR;
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

          str = json_string_value (root);
          if (NULL == str)
          {
            ret = (MHD_YES ==
                   TALER_MINT_reply_json_pack (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               "{s:s, s:o}",
                                               "error",
                                               "string expected",
                                               "path",
                                               path))
              ? GNUNET_NO : GNUNET_SYSERR;
            break;
          }
          res = GNUNET_STRINGS_string_to_data (str, strlen (str),
                                                where, len);
          if (GNUNET_OK != res)
          {
            ret = (MHD_YES ==
                   TALER_MINT_reply_json_pack (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               "{s:s, s:o}",
                                               "error",
                                               "malformed binary data in JSON",
                                               "path",
                                               path))
              ? GNUNET_NO : GNUNET_SYSERR;
            break;
          }
          ret = GNUNET_OK;
        }
        break;
      case JNAV_RET_DATA_VAR:
        {
          void **where = va_arg (argp, void **);
          size_t *len = va_arg (argp, size_t *);
          const char *str;

          str = json_string_value (root);
          if (NULL == str)
          {
            ret = (MHD_YES ==
                   TALER_MINT_reply_internal_error (connection,
                                                    "json_string_value() failed"))
              ? GNUNET_NO : GNUNET_SYSERR;
            break;
          }
          *len = (strlen (str) * 5) / 8;
          if (NULL != where)
          {
            int res;

            *where = GNUNET_malloc (*len);
            res = GNUNET_STRINGS_string_to_data (str,
                                                 strlen (str),
                                                 *where,
                                                 *len);
            if (GNUNET_OK != res)
            {
              GNUNET_free (*where);
              *where = NULL;
              *len = 0;
              ret = (MHD_YES ==
                     TALER_MINT_reply_json_pack (connection,
                                                 MHD_HTTP_BAD_REQUEST,
                                                 "{s:s, s:o}",
                                                 "error",
                                                 "malformed binary data in JSON",
                                                 "path", path))
                ? GNUNET_NO : GNUNET_SYSERR;
              break;
            }
          }
          ret = GNUNET_OK;
        }
        break;
      case JNAV_RET_TYPED_JSON:
        {
          int typ = va_arg (argp, int);
          const json_t **r_json = va_arg (argp, const json_t **);

          if ( (-1 != typ) && (json_typeof (root) != typ))
          {
            ret = (MHD_YES ==
                   TALER_MINT_reply_json_pack (connection,
                                               MHD_HTTP_BAD_REQUEST,
                                               "{s:s, s:i, s:i, s:o}",
                                               "error", "wrong JSON field type",
                                               "type_expected", typ,
                                               "type_actual", json_typeof (root),
                                               "path", path))
              ? GNUNET_NO : GNUNET_SYSERR;
            break;
          }
          *r_json = root;
          ret = GNUNET_OK;
        }
        break;
      default:
        GNUNET_break (0);
        ret = (MHD_YES ==
               TALER_MINT_reply_internal_error (connection,
                                                "unhandled value in switch"))
          ? GNUNET_NO : GNUNET_SYSERR;
        break;
    }
  }
  va_end (argp);
  json_decref (path);
  return ret;
}


/**
 * Find a fixed-size field in the top-level of the JSON tree and store
 * it in @a data.
 *
 * Sends an error response if navigation is impossible (i.e.
 * the JSON object is invalid)
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param field name of the field to navigate to
 * @param data where to store the extracted data
 * @param data_size size of the @a data field
 * @param[IN|OUT] ret return value, function does nothing if @a ret is not #GNUNET_YES
 *                    on entry; will set @a ret to:
 *    #GNUNET_YES if navigation was successful
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
static void
parse_fixed_json_data (struct MHD_Connection *connection,
                       const json_t *root,
                       const char *field,
                       void *data,
                       size_t data_size,
                       int *ret)
{
  if (GNUNET_YES != *ret)
    return;
  *ret = GNUNET_MINT_parse_navigate_json (connection,
                                          root,
                                          JNAV_FIELD, field,
                                          JNAV_RET_DATA, data, data_size);
}


/**
 * Find a variable-size field in the top-level of the JSON tree and store
 * it in @a data.
 *
 * Sends an error response if navigation is impossible (i.e.
 * the JSON object is invalid)
 *
 * @param connection the connection to send an error response to
 * @param root the JSON node to start the navigation at.
 * @param field name of the field to navigate to
 * @param data where to store a pointer to memory allocated for the extracted data
 * @param[IN|OUT] ret return value, function does nothing if @a ret is not #GNUNET_YES
 *                    on entry; will set @a ret to:
 *    #GNUNET_YES if navigation was successful
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
static void
parse_variable_json_data (struct MHD_Connection *connection,
                          const json_t *root,
                          const char *field,
                          void **data,
                          size_t *data_size,
                          int *ret)
{
  if (GNUNET_YES != *ret)
    return;
  *ret = GNUNET_MINT_parse_navigate_json (connection,
                                          root,
                                          JNAV_FIELD, field,
                                          JNAV_RET_DATA_VAR, data, data_size);

}


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
 *                #TALER_MINT_release_parsed_data() when done)
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error
 */
int
TALER_MINT_parse_json_data (struct MHD_Connection *connection,
                            const json_t *root,
                            struct GNUNET_MINT_ParseFieldSpec *spec)
{
  unsigned int i;
  int ret;
  void *ptr;

  ret = GNUNET_YES;
  for (i=0; NULL != spec[i].field_name; i++)
  {
    if (0 == spec[i].destination_size_in)
    {
      ptr = NULL;
      parse_variable_json_data (connection, root,
                                spec[i].field_name,
                                &ptr,
                                &spec[i].destination_size_out,
                                &ret);
      spec[i].destination = ptr;
    }
    else
    {
      parse_fixed_json_data (connection, root,
                             spec[i].field_name,
                             spec[i].destination,
                             spec[i].destination_size_in,
                             &ret);
    }
  }
  if (GNUNET_YES != ret)
    TALER_MINT_release_parsed_data (spec);
  return ret;
}


/**
 * Release all memory allocated for the variable-size fields in
 * the parser specification.
 *
 * @param spec specification to free
 */
void
TALER_MINT_release_parsed_data (struct GNUNET_MINT_ParseFieldSpec *spec)
{
  unsigned int i;

  for (i=0; NULL != spec[i].field_name; i++)
    if ( (0 == spec[i].destination_size_in) &&
         (0 != spec[i].destination_size_out) )
    {
      GNUNET_free (spec[i].destination);
      spec[i].destination = NULL;
      spec[i].destination_size_out = 0;
    }
}


/**
 * Parse amount specified in JSON format.
 *
 * @param connection the MHD connection (to report errors)
 * @param f json specification of the amount
 * @param amount[OUT] set to the amount specified in @a f
 * @return
 *    #GNUNET_YES if parsing was successful
 *    #GNUNET_NO if json is malformed, error response was generated
 *    #GNUNET_SYSERR on internal error, error response was not generated
 */
int
TALER_MINT_parse_amount_json (struct MHD_Connection *connection,
                              json_t *f,
                              struct TALER_Amount *amount)
{
  json_int_t value;
  json_int_t fraction;
  const char *currency;
  struct TALER_Amount a;

  if (-1 == json_unpack (f,
                         "{s:I, s:I, s:s}",
                         "value", &value,
                         "fraction", &fraction,
                         "currency", &currency))
  {
    LOG_WARNING ("Failed to parse JSON amount specification\n");
    if (MHD_YES !=
        TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_BAD_REQUEST,
                                    "{s:s}",
                                    "error", "Bad format"))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  if ( (value < 0) ||
       (fraction < 0) ||
       (value > UINT32_MAX) ||
       (fraction > UINT32_MAX) )
  {
    LOG_WARNING ("Amount specified not in allowed range\n");
    if (MHD_YES !=
        TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_BAD_REQUEST,
                                    "{s:s}",
                                    "error", "Amount outside of allowed range"))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  if (0 != strcmp (currency,
                   MINT_CURRENCY))
  {
    LOG_WARNING ("Currency specified not supported by this mint\n");
    if (MHD_YES !=
        TALER_MINT_reply_json_pack (connection,
                                    MHD_HTTP_BAD_REQUEST,
                                    "{s:s, s:s}",
                                    "error", "Currency not supported",
                                    "currency", currency))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  a.value = (uint32_t) value;
  a.fraction = (uint32_t) fraction;
  GNUNET_assert (strlen (MINT_CURRENCY) < TALER_CURRENCY_LEN);
  strcpy (a.currency, MINT_CURRENCY);
  *amount = TALER_amount_normalize (a);
  return GNUNET_OK;
}


/**
 * Extract base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of data
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
int
TALER_MINT_mhd_request_arg_data (struct MHD_Connection *connection,
                                 const char *param_name,
                                 void *out_data,
                                 size_t out_size)
{
  const char *str;

  str = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     param_name);
  if (NULL == str)
  {
    return (MHD_NO ==
            TALER_MINT_reply_arg_missing (connection, param_name))
      ? GNUNET_SYSERR : GNUNET_NO;
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (str,
                                     strlen (str),
                                     out_data,
                                     out_size))
    return (MHD_NO ==
            TALER_MINT_reply_arg_invalid (connection, param_name))
      ? GNUNET_SYSERR : GNUNET_NO;
  return GNUNET_OK;
}


/**
 * Extraxt variable-size base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing
 * or the encoding is invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the parameter with the key
 * @param[out] out_data pointer to allocate buffer and store the result
 * @param[out] out_size set to the size of the buffer allocated in @a out_data
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
int
TALER_MINT_mhd_request_var_arg_data (struct MHD_Connection *connection,
                                     const char *param_name,
                                     void **out_data,
                                     size_t *out_size)
{
  const char *str;
  size_t slen;
  size_t olen;
  void *out;

  str = MHD_lookup_connection_value (connection,
                                     MHD_GET_ARGUMENT_KIND,
                                     param_name);
  if (NULL == str)
  {
    return (MHD_NO ==
            TALER_MINT_reply_arg_missing (connection, param_name))
      ? GNUNET_SYSERR : GNUNET_NO;
  }
  slen = strlen (str);
  olen = (slen * 5) / 8;
  out = GNUNET_malloc (olen);
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (str,
                                     strlen (str),
                                     out,
                                     olen))
  {
    GNUNET_free (out);
    *out_size = 0;
    return (MHD_NO ==
            TALER_MINT_reply_arg_invalid (connection, param_name))
      ? GNUNET_SYSERR : GNUNET_NO;
  }
  *out_data = out;
  *out_size = olen;
  return GNUNET_OK;

}



/* end of taler-mint-httpd_parsing.c */
