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
 * @file exchangedb/pg_insert_reserve_closed.h
 * @brief implementation of the insert_reserve_closed function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_RESERVE_CLOSED_H
#define PG_INSERT_RESERVE_CLOSED_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert reserve close operation into database.
 *
 * @param cls closure
 * @param reserve_pub which reserve is this about?
 * @param execution_date when did we perform the transfer?
 * @param receiver_account to which account do we transfer?
 * @param wtid wire transfer details
 * @param amount_with_fee amount we charged to the reserve
 * @param closing_fee how high is the closing fee
 * @param close_request_row identifies explicit close request, 0 for none
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_reserve_closed (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct GNUNET_TIME_Timestamp execution_date,
  const struct TALER_FullPayto receiver_account,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_Amount *amount_with_fee,
  const struct TALER_Amount *closing_fee,
  uint64_t close_request_row);

#endif
