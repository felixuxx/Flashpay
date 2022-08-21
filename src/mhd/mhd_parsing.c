/*
  This file is part of TALER
  Copyright (C) 2014--2020 Taler Systems SA

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


enum GNUNET_GenericReturnValue
TALER_MHD_parse_request_arg_data (struct MHD_Connection *connection,
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
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MISSING,
                                        param_name))
           ? GNUNET_SYSERR : GNUNET_NO;
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (str,
                                     strlen (str),
                                     out_data,
                                     out_size))
    return (MHD_NO ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        param_name))
           ? GNUNET_SYSERR : GNUNET_NO;
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


/* end of mhd_parsing.c */
