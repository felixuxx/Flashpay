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
#include "taler-auditor-httpd_coin-inconsistency-upd.h"

MHD_RESULT
TAH_COIN_INCONSISTENCY_handler_update (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  enum GNUNET_DB_QueryStatus qs;

  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }

  uint64_t row_id;

  if (args[2] != NULL)
    row_id = atoi (args[2]);
  else
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "no row id specified");


  struct TALER_AUDITORDB_Generic_Update gu;

  gu.row_id = row_id;

  struct GNUNET_JSON_Specification spec[] = {

    // GNUNET_JSON_spec_uint64 ("row_id", &gu.row_id),
    GNUNET_JSON_spec_bool ("suppressed", &gu.suppressed),

    GNUNET_JSON_spec_end ()
  };

  json_t *json;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  {
    enum GNUNET_GenericReturnValue res;

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
      json_decref (json);
      return MHD_NO;                         /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      json_decref (json);
      return MHD_YES;                         /* failure */
    }
  }

  /* execute transaction */
  qs = TAH_plugin->update_coin_inconsistency (TAH_plugin->cls, &gu);

  GNUNET_JSON_parse_free (spec);
  json_decref (json);

  MHD_RESULT ret = MHD_NO;

  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    ret = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_GENERIC_DB_STORE_FAILED,
                                      "update_account");
    break;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    ret = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                      "unexpected serialization problem");
    break;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "no updates executed");
    break;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    ret = TALER_MHD_reply_static (connection,
                                  MHD_HTTP_NO_CONTENT,
                                  NULL,
                                  NULL,
                                  0);
    break;
  }

  return ret;
}
