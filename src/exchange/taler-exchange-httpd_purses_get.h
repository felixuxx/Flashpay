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
 * @file taler-exchange-httpd_purses_get.h
 * @brief Handle /purses/$PURSE_PUB/$TARGET GET requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_PURSES_GET_H
#define TALER_EXCHANGE_HTTPD_PURSES_GET_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Shutdown purses-get subsystem.  Resumes all
 * suspended long-polling clients and cleans up
 * data structures.
 */
void
TEH_purses_get_cleanup (void);


/**
 * Handle a GET "/purses/$PID/$TARGET" request.  Parses the
 * given "purse_pub" in @a args (which should contain the
 * EdDSA public key of a purse) and then respond with the
 * status of the purse.
 *
 * @param rc request context
 * @param args array of additional options (length: 2, the purse_pub and a target)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_purses_get (struct TEH_RequestContext *rc,
                        const char *const args[2]);

#endif
