/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_lookup_active_legitimization.h
 * @brief implementation of the lookup_active_legitimization function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_ACTIVE_LEGITIMIZATION_H
#define PG_LOOKUP_ACTIVE_LEGITIMIZATION_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup measure data for an active legitimization process.
 *
 * @param cls closure
 * @param legitimization_process_serial_id
 *    row in legitimization_processes table to access
 * @param[out] measure_index set to the measure the
 *    process is trying to satisfy
 * @param[out] jmeasures set to the legitimization
 *    measures that were put on the account
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_active_legitimization (
  void *cls,
  uint64_t legitimization_process_serial_id,
  uint32_t *measure_index,
  json_t **jmeasures);


#endif
