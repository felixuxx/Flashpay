/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_withdraw.h
 * @brief Handle /reserve/$RESERVE_PUB/{age,batch}-withdraw requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 * @author Özgür Kesim
 */
#ifndef TALER_EXCHANGE_HTTPD_WITHDRAW_H
#define TALER_EXCHANGE_HTTPD_WITHDRAW_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"

/**
 * Resume suspended connections, we are shutting down.
 */
void
TEH_withdraw_cleanup (void);


/**
 * Handle a "/reserves/$RESERVE_PUB/age-withdraw" request.
 *
 * Parses the batch of commitments to withdraw age restricted coins, and checks
 * that the signature "reserve_sig" makes this a valid withdrawal request from
 * the specified reserve.  If the request is valid, the response contains a
 * noreveal_index which the client has to use for the subsequent call to
 * /age-withdraw/$ACH/reveal.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param reserve_pub public key of the reserve
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_age_withdraw (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root);


/**
 * Handle a "/reserves/$RESERVE_PUB/batch-withdraw" request.  Parses the batch of
 * requested "denom_pub" which specifies the key/value of the coin to be
 * withdrawn, and checks that the signature "reserve_sig" makes this a valid
 * withdrawal request from the specified reserve.  If so, the envelope with
 * the blinded coin "coin_ev" is passed down to execute the withdrawal
 * operation.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param reserve_pub public key of the reserve
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_batch_withdraw (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root);

#endif
