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
#include "taler-auditor-httpd_delete_generic.h"


MHD_RESULT
TAH_delete_handler_generic (
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

  if ((NULL == args[1]) ||
      (1 != sscanf (args[1],
                    "%llu%c",
                    &row_id,
                    &dummy)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "no row id specified");
  }

  /* execute transaction */
  qs = TAH_plugin->delete_generic (TAH_plugin->cls,
                                   rh->table,
                                   row_id);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_STORE_FAILED,
                                       "db store failed");
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
                                       "no delete executed");
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
