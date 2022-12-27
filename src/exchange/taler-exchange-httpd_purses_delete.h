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
 * @file taler-exchange-httpd_purses_delete.h
 * @brief Handle DELETE /purses/$PID requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_PURSES_DELETE_H
#define TALER_EXCHANGE_HTTPD_PURSES_DELETE_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a DELETE "/purses/$PURSE_PUB" request.
 *
 * @param connection the MHD connection to handle
 * @param purse_pub public key of the purse
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_purses_delete (
  struct MHD_Connection *connection,
  const struct TALER_PurseContractPublicKeyP *purse_pub);


#endif
