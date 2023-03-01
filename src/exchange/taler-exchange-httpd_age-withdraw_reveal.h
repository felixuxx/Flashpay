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
 * @file taler-exchange-httpd_age-withdraw_reveal.h
 * @brief Handle /age-withdraw/$ACH/reveal requests
 * @author Özgür Kesim
 */
#ifndef TALER_EXCHANGE_HTTPD_AGE_WITHDRAW_H
#define TALER_EXCHANGE_HTTPD_AGE_WITHDRAW_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/age-withdraw/$ACH/reveal" request.
 *
 * The client got a noreveal_index in response to a previous request
 * /reserve/$RESERVE_PUB/age-withdraw.  It now has to reveal all n*(kappa-1)
 * coin's private keys (except for the noreveal_index), from which all other
 * coin-relevant data (blinding, age restriction, nonce) is derived from.
 *
 * The exchange computes those values, ensures that the maximum age is
 * correctly applied, calculates the hash of the blinded envelopes, and -
 * together with the non-disclosed blinded envelopes - compares the hash of
 * those against the original commitment $ACH.
 *
 * If all those checks and the used denominations turn out to be correct, the
 * exchange signs all blinded envelopes with their appropriate denomination
 * keys.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param ach commitment to the age restricted coints from the age-withdraw request
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_age_withdraw_reveal (
  struct TEH_RequestContext *rc,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  const json_t *root);

#endif
