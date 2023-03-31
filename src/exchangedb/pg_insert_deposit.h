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
 * @file exchangedb/pg_insert_deposit.h
 * @brief implementation of the insert_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_DEPOSIT_H
#define PG_INSERT_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Insert information about deposited coin into the database.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param exchange_timestamp time the exchange received the deposit request
 * @param deposit deposit information to store
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_deposit (void *cls,
                       struct GNUNET_TIME_Timestamp exchange_timestamp,
                       const struct TALER_EXCHANGEDB_Deposit *deposit);

#endif
