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
 * @file taler-exchange-httpd_reserves_close.h
 * @brief Handle /reserves/$RESERVE_PUB/close requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_RESERVES_CLOSE_H
#define TALER_EXCHANGE_HTTPD_RESERVES_CLOSE_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Resume suspended connections, we are shutting down.
 */
void
TEH_reserves_close_cleanup (void);

/**
 * Handle a POST "/reserves/$RID/close" request.
 *
 * @param rc request context
 * @param reserve_pub public key of the reserve
 * @param root uploaded body from the client
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_reserves_close (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root);

#endif
