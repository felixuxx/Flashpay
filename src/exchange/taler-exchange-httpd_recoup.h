/*
  This file is part of TALER
  Copyright (C) 2017 Taler Systems SA

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
 * @file taler-exchange-httpd_recoup.h
 * @brief Handle /recoup requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_RECOUP_H
#define TALER_EXCHANGE_HTTPD_RECOUP_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/coins/$COIN_PUB/recoup" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #verify_and_execute_recoup() to further
 * check the details of the operation specified.  If everything checks out,
 * this will ultimately lead to the refund being executed, or rejected.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
  */
int
TEH_RECOUP_handler_recoup (struct MHD_Connection *connection,
                           const struct TALER_CoinSpendPublicKeyP *coin_pub,
                           const json_t *root);


#endif
