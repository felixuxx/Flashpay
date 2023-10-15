/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */
/**
 * @file pg_do_reserve_open.h
 * @brief implementation of the do_reserve_open function
 * @author Christian Grothoff
 */
#ifndef PG_DO_RESERVE_OPEN_H
#define PG_DO_RESERVE_OPEN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Perform reserve open operation on database.
 *
 * @param cls closure
 * @param reserve_pub which reserve is this about?
 * @param total_paid total amount paid (coins and reserve)
 * @param reserve_payment amount to be paid from the reserve
 * @param min_purse_limit minimum number of purses we should be able to open
 * @param reserve_sig signature by the reserve for the operation
 * @param desired_expiration when should the reserve expire (earliest time)
 * @param now when did we the client initiate the action
 * @param open_fee annual fee to be charged for the open operation by the exchange
 * @param[out] no_funds set to true if reserve balance is insufficient
 * @param[out] reserve_balance set to the original reserve balance (at the start of this transaction)
 * @param[out] open_cost set to the actual cost
 * @param[out] final_expiration when will the reserve expire now
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_reserve_open (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *total_paid,
  const struct TALER_Amount *reserve_payment,
  uint32_t min_purse_limit,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp desired_expiration,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_Amount *open_fee,
  bool *no_funds,
  struct TALER_Amount *reserve_balance,
  struct TALER_Amount *open_cost,
  struct GNUNET_TIME_Timestamp *final_expiration);


#endif
