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


#include "taler-auditor-httpd_reserve-balance-summary-wrong-inconsistency-del.h"


MHD_RESULT
TAH_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_handler_delete (struct
                                                                TAH_RequestHandler
                                                                *rh,
                                                                struct
                                                                MHD_Connection *
                                                                connection,
                                                                void **
                                                                connection_cls,
                                                                const char *
                                                                upload_data,
                                                                size_t *
                                                                upload_data_size,
                                                                const char *
                                                                const args[])
{

  enum GNUNET_DB_QueryStatus qs;

  uint64_t row_id;

  if (args[2] != NULL)
    row_id = atoi (args[2]);
  else
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "row could not be found");

  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }


  // execute the transaction
  qs = TAH_plugin->delete_reserve_balance_summary_wrong_inconsistency (
    TAH_plugin->cls,
    row_id);

  if (0 == qs)
  {
    // goes in here if there was an error with the transaction
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    TALER_LOG_WARNING (
      "Failed to handle DELETE /reserve-balance-summary-wrong-inconsistency/ %s",
      args[1]);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_AUDITOR_RESOURCE_NOT_FOUND,
                                       "row could not be found");

  }

  // on success?
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_NO_CONTENT,
                                    GNUNET_JSON_pack_string ("status",
                                                             "RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_OK"));

}
