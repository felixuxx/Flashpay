/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-exchange-httpd_reserves_history.h
 * @brief Handle /reserves/$RESERVE_PUB/history requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_RESERVES_HISTORY_H
#define TALER_EXCHANGE_HTTPD_RESERVES_HISTORY_H

#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd.h"


/**
 * Handle a GET "/reserves/$RID/history" request.
 *
 * @param rc request context
 * @param reserve_pub public key of the reserve
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_reserves_history (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub);

#endif
