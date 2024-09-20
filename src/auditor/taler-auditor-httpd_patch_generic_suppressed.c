/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */


#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-auditor-httpd.h"


MHD_RESULT
TAH_patch_handler_generic_suppressed (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  enum GNUNET_DB_QueryStatus qs;
  unsigned long long row_id;
  char dummy;
  bool suppressed;

  (void) connection_cls;
  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }

  if ( (NULL == args[1]) ||
       (1 != sscanf (args[1],
                     "%llu%c",
                     &row_id,
                     &dummy)) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "no row id specified");
  }

  {
    enum GNUNET_GenericReturnValue res;
    json_t *json;
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_bool ("suppressed", &suppressed),
      GNUNET_JSON_spec_end ()
    };

    res = TALER_MHD_parse_post_json (connection,
                                     connection_cls,
                                     upload_data,
                                     upload_data_size,
                                     &json);
    if (GNUNET_SYSERR == res)
      return MHD_NO;
    if ((GNUNET_NO == res) ||
        (NULL == json))
      return MHD_YES;
    res = TALER_MHD_parse_json_data (connection,
                                     json,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
      json_decref (json);
      return MHD_NO;                               /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      GNUNET_break_op (0);
      json_decref (json);
      return MHD_YES;                               /* failure */
    }
    json_decref (json);
  }

  /* execute transaction */
  qs = TAH_plugin->update_generic_suppressed (TAH_plugin->cls,
                                              rh->table,
                                              row_id,
                                              suppressed);

  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_STORE_FAILED,
                                       "update_account");
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                       "unexpected serialization problem");
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "no updates executed");
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    return TALER_MHD_reply_static (connection,
                                   MHD_HTTP_NO_CONTENT,
                                   NULL,
                                   NULL,
                                   0);
  }
  GNUNET_break (0);
  return MHD_NO;
}
