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
 * Insert reserve close operation into database.
 *
 * @param cls closure
 * @param reserve_pub which reserve is this about?
 * @param execution_date when did we perform the transfer?
 * @param receiver_account to which account do we transfer, in payto://-format
 * @param wtid identifier for the wire transfer
 * @param amount_with_fee amount we charged to the reserve
 * @param closing_fee how high is the closing fee
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_reserve_open (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_Amount *total_paid,
  uint32_t min_purse_limit,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp desired_expiration,
  struct GNUNET_TIME_Timestamp now,
  const struct TALER_Amount *open_fee,
  struct TALER_Amount *open_cost,
  struct GNUNET_TIME_Timestamp *final_expiration);


#endif
