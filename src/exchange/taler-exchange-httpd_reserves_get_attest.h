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
 * @file taler-exchange-httpd_reserves_get_attest.h
 * @brief Handle /reserves/$RESERVE_PUB GET_ATTEST requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_RESERVES_GET_ATTEST_H
#define TALER_EXCHANGE_HTTPD_RESERVES_GET_ATTEST_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a GET "/reserves/$RID/attest" request.  Parses the
 * given "reserve_pub" in @a args (which should contain the
 * EdDSA public key of a reserve) and then responds with the
 * available attestations for the reserve.
 *
 * @param rc request context
 * @param args array of additional options (length: 1, just the reserve_pub)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_reserves_get_attest (struct TEH_RequestContext *rc,
                                 const char *const args[1]);

#endif
