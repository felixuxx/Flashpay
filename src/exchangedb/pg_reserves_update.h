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
 * @file exchangedb/pg_reserves_update.h
 * @brief implementation of the reserves_update function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_RESERVES_UPDATE_H
#define PG_RESERVES_UPDATE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Updates a reserve with the data from the given reserve structure.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param reserve the reserve structure whose data will be used to update the
 *          corresponding record in the database.
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_reserves_update (void *cls,
                        const struct TALER_EXCHANGEDB_Reserve *reserve);

#endif
