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
 * @file taler-exchange-httpd_reserves_purse.h
 * @brief Handle /reserves/$RID/purse requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_RESERVES_PURSE_H
#define TALER_EXCHANGE_HTTPD_RESERVES_PURSE_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/reserves/$RESERVE_PUB/purse" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #create_transaction() to further check
 * the details of the operation specified.  If everything checks out, this
 * will ultimately lead to the "purses create" being executed, or rejected.
 *
 * @param rc request context
 * @param reserve_pub public key of the reserve
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_reserves_purse (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root);

#endif
