/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_coins_get.h
 * @brief Handle GET /coins/$COIN_PUB requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_COINS_GET_H
#define TALER_EXCHANGE_HTTPD_COINS_GET_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Shutdown reserves-get subsystem.  Resumes all
 * suspended long-polling clients and cleans up
 * data structures.
 */
void
TEH_reserves_get_cleanup (void);


/**
 * Handle a GET "/coins/$COIN_PUB/history" request.  Parses the
 * given "coins_pub" in @a args (which should contain the
 * EdDSA public key of a reserve) and then respond with the
 * transaction history of the coin.
 *
 * @param rc request context
 * @param coin_pub public key of the coin
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_coins_get (struct TEH_RequestContext *rc,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub);

#endif
