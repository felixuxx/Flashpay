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
 * @file exchangedb/pg_reserves_in_insert.h
 * @brief implementation of the reserves_in_insert function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_RESERVES_IN_INSERT_H
#define PG_RESERVES_IN_INSERT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Insert an incoming transaction into reserves.  New reserves are also
 * created through this function. Started within the scope of an ongoing
 * transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param balance the amount that has to be added to the reserve
 * @param execution_time when was the amount added
 * @param sender_account_details account information for the sender (payto://-URL)
 * @param exchange_account_section name of the section in the configuration for the exchange's
 *                       account into which the deposit was made
 * @param wire_ref unique reference identifying the wire transfer
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_reserves_in_insert (void *cls,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const struct TALER_Amount *balance,
                             struct GNUNET_TIME_Timestamp execution_time,
                             const char *sender_account_details,
                             const char *exchange_account_section,
                           uint64_t wire_ref);

#endif
