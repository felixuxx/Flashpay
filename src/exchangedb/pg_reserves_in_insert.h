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
 * created through this function. Runs its own transaction(s).
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserves array of reserves to insert
 * @param reserves_length length of the @a reserves array
 * @param batch_size how many inserts to do in one go
 * @param[out] results set to query status per reserve, must be of length @a reserves_length
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_reserves_in_insert (
  void *cls,
  const struct TALER_EXCHANGEDB_ReserveInInfo *reserves,
  unsigned int reserves_length,
  unsigned int batch_size,
  enum GNUNET_DB_QueryStatus *results);


#endif
