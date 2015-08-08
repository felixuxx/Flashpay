/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file mint-lib/mint_api_common.h
 * @brief common functions for the mint API
 * @author Christian Grothoff
 */
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_mint_service.h"

/**
 * Verify a coins transaction history as returned by the mint.
 *
 * @param currency expected currency for the coin
 * @param coin_pub public key of the coin
 * @param history history of the coin in json encoding
 * @param[out] total how much of the coin has been spent according to @a history
 * @return #GNUNET_OK if @a history is valid, #GNUNET_SYSERR if not
 */
int
TALER_MINT_verify_coin_history_ (const char *currency,
                                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                                 json_t *history,
                                 struct TALER_Amount *total);

/* end of mint_api_common.h */
