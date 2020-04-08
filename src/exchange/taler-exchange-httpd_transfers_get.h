/*
  This file is part of TALER
  Copyright (C) 2014-2017 Taler Systems SA

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
 * @file taler-exchange-httpd_transfers_get.h
 * @brief Handle wire transfer tracking-related requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_TRANSFERS_GET_H
#define TALER_EXCHANGE_HTTPD_TRANSFERS_GET_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a GET "/transfers/$WTID" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (length: 1, just the wtid)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_transfers_get (const struct TEH_RequestHandler *rh,
                           struct MHD_Connection *connection,
                           const char *const args[1]);


#endif
