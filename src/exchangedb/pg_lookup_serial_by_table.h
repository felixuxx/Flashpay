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
 * @file pg_lookup_serial_by_table.h
 * @brief implementation of the lookup_serial_by_table function
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_SERIAL_BY_TABLE_H
#define PG_LOOKUP_SERIAL_BY_TABLE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup the latest serial number of @a table.  Used in
 * exchange-auditor database replication.
 *
 * @param cls closure
 * @param table table for which we should return the serial
 * @param[out] serial latest serial number in use
 * @return transaction status code, GNUNET_DB_STATUS_HARD_ERROR if
 *         @a table does not have a serial number
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_serial_by_table (void *cls,
                               enum TALER_EXCHANGEDB_ReplicatedTable table,
                               uint64_t *serial);


#endif
