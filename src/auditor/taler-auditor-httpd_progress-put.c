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
#include "taler-auditor-httpd_progress-put.h"

/**
* We have parsed the JSON information about the progress, do some
* basic sanity checks and then execute the
* transaction.
*
* @param connection the MHD connection to handle
* @param dc information about the progress
* @return MHD result code
*/
static MHD_RESULT
process_inconsistency (
  struct MHD_Connection *connection,
  const struct TALER_AUDITORDB_Progress *dc)
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

  /* execute transaction */
  qs = TAH_plugin->insert_progress (TAH_plugin->cls,
                                    dc);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    TALER_LOG_WARNING (
      "Failed to store /progress in database\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_STORE_FAILED,
                                       "progress");
  }
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_OK,
                                    GNUNET_JSON_pack_string ("status",
                                                             "PROGRESS_OK"));
}


MHD_RESULT
TAH_PROGRESS_PUT_handler (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{

  struct TALER_AUDITORDB_Progress dc;


  struct GNUNET_JSON_Specification spec[] = {

    GNUNET_JSON_spec_string ("progress_key", (const char **) &dc.progress_key),
    GNUNET_JSON_spec_string ("progress_offset", (const
                                                 char **) &dc.progress_offset),


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
      return MHD_NO;                   /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      json_decref (json);
      return MHD_YES;                   /* failure */
    }
  }

  MHD_RESULT res;

  res = process_inconsistency (connection, &dc);
  GNUNET_JSON_parse_free (spec);

  json_decref (json);
  return res;

}


void
TEAH_PROGRESS_PUT_init (void)
{

}


void
TEAH_PROGRESS_PUT_done (void)
{

}
