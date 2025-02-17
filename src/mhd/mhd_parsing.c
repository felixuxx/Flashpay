/*
  This file is part of TALER
  Copyright (C) 2014--2024 Taler Systems SA

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
 * @file mhd_parsing.c
 * @brief functions to parse incoming requests (MHD arguments and JSON snippets)
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"


enum GNUNET_GenericReturnValue
TALER_MHD_parse_post_json (struct MHD_Connection *connection,
                           void **con_cls,
                           const char *upload_data,
                           size_t *upload_data_size,
                           json_t **json)
{
  enum GNUNET_JSON_PostResult pr;

  pr = GNUNET_JSON_post_parser (TALER_MHD_REQUEST_BUFFER_MAX,
                                connection,
                                con_cls,
                                upload_data,
                                upload_data_size,
                                json);
  switch (pr)
  {
  case GNUNET_JSON_PR_OUT_OF_MEMORY:
    GNUNET_break (NULL == *json);
    return (MHD_NO ==
            TALER_MHD_reply_with_error (
              connection,
              MHD_HTTP_INTERNAL_SERVER_ERROR,
              TALER_EC_GENERIC_PARSER_OUT_OF_MEMORY,
              NULL)) ? GNUNET_SYSERR : GNUNET_NO;

  case GNUNET_JSON_PR_CONTINUE:
    GNUNET_break (NULL == *json);
    return GNUNET_YES;
  case GNUNET_JSON_PR_REQUEST_TOO_LARGE:
    GNUNET_break (NULL == *json);
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Closing connection, upload too large\n");
    return GNUNET_SYSERR;
  case GNUNET_JSON_PR_JSON_INVALID:
    GNUNET_break (NULL == *json);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_JSON_INVALID,
                                        NULL))
           ? GNUNET_NO : GNUNET_SYSERR;
  case GNUNET_JSON_PR_SUCCESS:
    GNUNET_break (NULL != *json);
    return GNUNET_YES;
  }
  /* this should never happen */
  GNUNET_break (0);
  return GNUNET_SYSERR;
}


void
TALER_MHD_parse_post_cleanup_callback (void *con_cls)
{
  GNUNET_JSON_post_parser_cleanup (con_cls);
}


/**
 * Extract fixed-size base32crockford encoded data from request.
 *
 * Queues an error response to the connection if the parameter is missing or
 * invalid.
 *
 * @param connection the MHD connection
 * @param param_name the name of the HTTP key with the value
 * @param kind whether to extract from header, argument or footer
 * @param[out] out_data pointer to store the result
 * @param out_size expected size of @a out_data
 * @param[out] present set to true if argument was found
 * @return
 *   #GNUNET_YES if the the argument is present
 *   #GNUNET_NO if the argument is absent or malformed
 *   #GNUNET_SYSERR on internal error (error response could not be sent)
 */
static enum GNUNET_GenericReturnValue
parse_request_data (
  struct MHD_Connection *connection,
  const char *param_name,
  enum MHD_ValueKind kind,
  void *out_data,
  size_t out_size,
  bool *present)
{
  const char *str;

  str = MHD_lookup_connection_value (connection,
                                     kind,
                                     param_name);
  if (NULL == str)
  {
    *present = false;
    return GNUNET_OK;
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (str,
                                     strlen (str),
                                     out_data,
                                     out_size))
  {
    GNUNET_break_op (0);
    return (MHD_NO ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        param_name))
           ? GNUNET_SYSERR : GNUNET_NO;
  }
  *present = true;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_data (
  struct MHD_Connection *connection,
  const char *param_name,
  void *out_data,
  size_t out_size,
  bool *present)
{
  return parse_request_data (connection,
                             param_name,
                             MHD_GET_ARGUMENT_KIND,
                             out_data,
                             out_size,
                             present);
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_header_data (
  struct MHD_Connection *connection,
  const char *header_name,
  void *out_data,
  size_t out_size,
  bool *present)
{
  return parse_request_data (connection,
                             header_name,
                             MHD_HEADER_KIND,
                             out_data,
                             out_size,
                             present);
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_timeout (
  struct MHD_Connection *connection,
  struct GNUNET_TIME_Absolute *expiration)
{
  const char *ts;
  char dummy;
  unsigned long long tms;

  ts = MHD_lookup_connection_value (connection,
                                    MHD_GET_ARGUMENT_KIND,
                                    "timeout_ms");
  if (NULL == ts)
  {
    *expiration = GNUNET_TIME_UNIT_ZERO_ABS;
    return GNUNET_OK;
  }
  if (1 !=
      sscanf (ts,
              "%llu%c",
              &tms,
              &dummy))
  {
    MHD_RESULT mret;

    GNUNET_break_op (0);
    mret = TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "timeout_ms");
    return (MHD_YES == mret)
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  *expiration = GNUNET_TIME_relative_to_absolute (
    GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MILLISECONDS,
                                   tms));
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_timestamp (
  struct MHD_Connection *connection,
  const char *fname,
  struct GNUNET_TIME_Timestamp *ts)
{
  const char *s;
  char dummy;
  unsigned long long t;

  s = MHD_lookup_connection_value (connection,
                                   MHD_GET_ARGUMENT_KIND,
                                   fname);
  if (NULL == s)
  {
    *ts = GNUNET_TIME_UNIT_ZERO_TS;
    return GNUNET_OK;
  }
  if (1 !=
      sscanf (s,
              "%llu%c",
              &t,
              &dummy))
  {
    MHD_RESULT mret;

    GNUNET_break_op (0);
    mret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      fname);
    return (MHD_YES == mret)
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  *ts = GNUNET_TIME_timestamp_from_s (t);
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_number (struct MHD_Connection *connection,
                                    const char *name,
                                    uint64_t *off)
{
  const char *ts;
  char dummy;
  unsigned long long num;

  ts = MHD_lookup_connection_value (connection,
                                    MHD_GET_ARGUMENT_KIND,
                                    name);
  if (NULL == ts)
    return GNUNET_OK;
  if (1 !=
      sscanf (ts,
              "%llu%c",
              &num,
              &dummy))
  {
    MHD_RESULT mret;

    GNUNET_break_op (0);
    mret = TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       name);
    return (MHD_YES == mret)
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  *off = (uint64_t) num;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_snumber (struct MHD_Connection *connection,
                                     const char *name,
                                     int64_t *val)
{
  const char *ts;
  char dummy;
  long long num;

  ts = MHD_lookup_connection_value (connection,
                                    MHD_GET_ARGUMENT_KIND,
                                    name);
  if (NULL == ts)
    return GNUNET_OK;
  if (1 !=
      sscanf (ts,
              "%lld%c",
              &num,
              &dummy))
  {
    MHD_RESULT mret;

    GNUNET_break_op (0);
    mret = TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       name);
    return (MHD_YES == mret)
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  *val = (int64_t) num;
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_amount (struct MHD_Connection *connection,
                                    const char *name,
                                    struct TALER_Amount *val)
{
  const char *ts;

  ts = MHD_lookup_connection_value (connection,
                                    MHD_GET_ARGUMENT_KIND,
                                    name);
  if (NULL == ts)
    return GNUNET_OK;
  if (GNUNET_OK !=
      TALER_string_to_amount (ts,
                              val))
  {
    MHD_RESULT mret;

    GNUNET_break_op (0);
    mret = TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       name);
    return (MHD_YES == mret)
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_json_data (struct MHD_Connection *connection,
                           const json_t *root,
                           struct GNUNET_JSON_Specification *spec)
{
  enum GNUNET_GenericReturnValue ret;
  const char *error_json_name;
  unsigned int error_line;

  ret = GNUNET_JSON_parse (root,
                           spec,
                           &error_json_name,
                           &error_line);
  if (GNUNET_SYSERR == ret)
  {
    if (NULL == error_json_name)
      error_json_name = "<no field>";
    ret = (MHD_YES ==
           TALER_MHD_REPLY_JSON_PACK (
             connection,
             MHD_HTTP_BAD_REQUEST,
             GNUNET_JSON_pack_string ("hint",
                                      TALER_ErrorCode_get_hint (
                                        TALER_EC_GENERIC_JSON_INVALID)),
             GNUNET_JSON_pack_uint64 ("code",
                                      TALER_EC_GENERIC_JSON_INVALID),
             GNUNET_JSON_pack_string ("field",
                                      error_json_name),
             GNUNET_JSON_pack_uint64 ("line",
                                      error_line)))
          ? GNUNET_NO : GNUNET_SYSERR;
    return ret;
  }
  return GNUNET_YES;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_internal_json_data (struct MHD_Connection *connection,
                                    const json_t *root,
                                    struct GNUNET_JSON_Specification *spec)
{
  enum GNUNET_GenericReturnValue ret;
  const char *error_json_name;
  unsigned int error_line;

  ret = GNUNET_JSON_parse (root,
                           spec,
                           &error_json_name,
                           &error_line);
  if (GNUNET_SYSERR == ret)
  {
    if (NULL == error_json_name)
      error_json_name = "<no field>";
    ret = (MHD_YES ==
           TALER_MHD_REPLY_JSON_PACK (
             connection,
             MHD_HTTP_INTERNAL_SERVER_ERROR,
             GNUNET_JSON_pack_string ("hint",
                                      TALER_ErrorCode_get_hint (
                                        TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE)),
             GNUNET_JSON_pack_uint64 ("code",
                                      TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE),
             GNUNET_JSON_pack_string ("field",
                                      error_json_name),
             GNUNET_JSON_pack_uint64 ("line",
                                      error_line)))
          ? GNUNET_NO : GNUNET_SYSERR;
    return ret;
  }
  return GNUNET_YES;
}


enum GNUNET_GenericReturnValue
TALER_MHD_parse_json_array (struct MHD_Connection *connection,
                            const json_t *root,
                            struct GNUNET_JSON_Specification *spec,
                            ...)
{
  enum GNUNET_GenericReturnValue ret;
  const char *error_json_name;
  unsigned int error_line;
  va_list ap;
  json_int_t dim;

  va_start (ap, spec);
  dim = 0;
  while ( (-1 != (ret = va_arg (ap, int))) &&
          (NULL != root) )
  {
    dim++;
    root = json_array_get (root, ret);
  }
  va_end (ap);
  if (NULL == root)
  {
    ret = (MHD_YES ==
           TALER_MHD_REPLY_JSON_PACK (
             connection,
             MHD_HTTP_BAD_REQUEST,
             GNUNET_JSON_pack_string ("hint",
                                      TALER_ErrorCode_get_hint (
                                        TALER_EC_GENERIC_JSON_INVALID)),
             GNUNET_JSON_pack_uint64 ("code",
                                      TALER_EC_GENERIC_JSON_INVALID),
             GNUNET_JSON_pack_string ("detail",
                                      "expected array"),
             GNUNET_JSON_pack_uint64 ("dimension",
                                      dim)))
          ? GNUNET_NO : GNUNET_SYSERR;
    return ret;
  }
  ret = GNUNET_JSON_parse (root,
                           spec,
                           &error_json_name,
                           &error_line);
  if (GNUNET_SYSERR == ret)
  {
    if (NULL == error_json_name)
      error_json_name = "<no field>";
    ret = (MHD_YES ==
           TALER_MHD_REPLY_JSON_PACK (
             connection,
             MHD_HTTP_BAD_REQUEST,
             GNUNET_JSON_pack_string ("detail",
                                      error_json_name),
             GNUNET_JSON_pack_string ("hint",
                                      TALER_ErrorCode_get_hint (
                                        TALER_EC_GENERIC_JSON_INVALID)),
             GNUNET_JSON_pack_uint64 ("code",
                                      TALER_EC_GENERIC_JSON_INVALID),
             GNUNET_JSON_pack_uint64 ("line",
                                      error_line)))
          ? GNUNET_NO : GNUNET_SYSERR;
    return ret;
  }
  return GNUNET_YES;
}


enum GNUNET_GenericReturnValue
TALER_MHD_check_content_length_ (struct MHD_Connection *connection,
                                 unsigned long long max_len)
{
  const char *cl;
  unsigned long long cv;
  char dummy;

  /* Maybe check for maximum upload size
       and refuse requests if they are just too big. */
  cl = MHD_lookup_connection_value (connection,
                                    MHD_HEADER_KIND,
                                    MHD_HTTP_HEADER_CONTENT_LENGTH);
  if (NULL == cl)
  {
    return GNUNET_OK;
#if 0
    /* wallet currently doesn't always send content-length! */
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MISSING,
                                        MHD_HTTP_HEADER_CONTENT_LENGTH))
      ? GNUNET_NO
      : GNUNET_SYSERR;
#endif
  }
  if (1 != sscanf (cl,
                   "%llu%c",
                   &cv,
                   &dummy))
  {
    /* Not valid HTTP request, just close connection. */
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        MHD_HTTP_HEADER_CONTENT_LENGTH))
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  if (cv > TALER_MHD_REQUEST_BUFFER_MAX)
  {
    GNUNET_break_op (0);
    return (MHD_YES ==
            TALER_MHD_reply_request_too_large (connection))
    ? GNUNET_NO
    : GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


int
TALER_MHD_check_accept (struct MHD_Connection *connection,
                        const char *header,
                        ...)
{
  bool ret = false;
  const char *accept;
  char *a;
  char *saveptr;

  accept = MHD_lookup_connection_value (connection,
                                        MHD_HEADER_KIND,
                                        header);
  if (NULL == accept)
    return -2; /* no Accept header set */

  a = GNUNET_strdup (accept);
  for (char *t = strtok_r (a, ",", &saveptr);
       NULL != t;
       t = strtok_r (NULL, ",", &saveptr))
  {
    char *end;

    /* skip leading whitespace */
    while (isspace ((unsigned char) t[0]))
      t++;
    /* trim of ';q=' parameter and everything after space */
    /* FIXME: eventually, we might want to parse the "q=$FLOAT"
       part after the ';' and figure out which one is the
       best/preferred match instead of returning a boolean... */
    end = strchr (t, ';');
    if (NULL != end)
      *end = '\0';
    end = strchr (t, ' ');
    if (NULL != end)
      *end = '\0';
    {
      va_list ap;
      int off = 0;
      const char *val;

      va_start (ap,
                header);
      while (NULL != (val = va_arg (ap,
                                    const char *)))
      {
        if (0 == strcasecmp (val,
                             t))
        {
          ret = off;
          break;
        }
        off++;
      }
      va_end (ap);
    }
  }
  GNUNET_free (a);
  return ret;
}


/* end of mhd_parsing.c */
