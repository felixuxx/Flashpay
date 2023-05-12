/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file taler-exchange-httpd_purses_delete.c
 * @brief Handle DELETE /purses/$PID requests; parses the request and
 *        verifies the signature before handing deletion to the database.
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_dbevents.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_common_deposit.h"
#include "taler-exchange-httpd_purses_delete.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


MHD_RESULT
TEH_handler_purses_delete (
  struct TEH_RequestContext *rc,
  const char *const args[1])
{
  struct MHD_Connection *connection = rc->connection;
  struct TALER_PurseContractPublicKeyP purse_pub;
  struct TALER_PurseContractSignatureP purse_sig;
  bool found;
  bool decided;

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &purse_pub,
                                     sizeof (purse_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_PURSE_PUB_MALFORMED,
                                       args[0]);
  }
  TALER_MHD_parse_request_header_auto_t (connection,
                                         "Taler-Purse-Signature",
                                         &purse_sig);
  if (GNUNET_OK !=
      TALER_wallet_purse_delete_verify (&purse_pub,
                                        &purse_sig))
  {
    TALER_LOG_WARNING ("Invalid signature on /purses/$PID/delete request\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_PURSE_DELETE_SIGNATURE_INVALID,
                                       NULL);
  }
  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_START_FAILED,
                                       "preflight failure");
  }

  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->do_purse_delete (TEH_plugin->cls,
                                      &purse_pub,
                                      &purse_sig,
                                      &decided,
                                      &found);
    if (qs <= 0)
    {
      TALER_LOG_WARNING (
        "Failed to store delete purse information in database\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_STORE_FAILED,
                                         "purse delete");
    }
  }
  if (! found)
  {
    return TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_EXCHANGE_GENERIC_PURSE_UNKNOWN,
      NULL);
  }
  if (decided)
  {
    return TALER_MHD_reply_with_ec (
      connection,
      TALER_EC_EXCHANGE_PURSE_DELETE_ALREADY_DECIDED,
      NULL);
  }
  {
    /* Possible minor optimization: integrate notification with
       transaction above... */
    struct TALER_PurseEventP rep = {
      .header.size = htons (sizeof (rep)),
      .header.type = htons (TALER_DBEVENT_EXCHANGE_PURSE_DEPOSITED),
      .purse_pub = purse_pub
    };

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Notifying about purse deletion %s\n",
                TALER_B2S (&purse_pub));
    TEH_plugin->event_notify (TEH_plugin->cls,
                              &rep.header,
                              NULL,
                              0);
  }
  /* success */
  return TALER_MHD_reply_static (connection,
                                 MHD_HTTP_NO_CONTENT,
                                 NULL,
                                 NULL,
                                 0);
}


/* end of taler-exchange-httpd_purses_delete.c */
