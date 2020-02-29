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
 * @file taler-exchange-httpd_link.h
 * @brief Handle /coins/$COIN_PUB/link requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_REFRESH_LINK_H
#define TALER_EXCHANGE_HTTPD_REFRESH_LINK_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/coins/$COIN_PUB/link" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (length: 2, first is the coin_pub, second must be "link")
 * @return MHD result code
  */
int
TEH_REFRESH_handler_link (const struct TEH_RequestHandler *rh,
                          struct MHD_Connection *connection,
                          const char *const args[2]);


#endif
