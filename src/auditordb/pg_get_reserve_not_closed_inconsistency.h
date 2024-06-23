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


#ifndef SRC_PG_GET_RESERVE_NOT_CLOSED_INCONSISTENCY_H
#define SRC_PG_GET_RESERVE_NOT_CLOSED_INCONSISTENCY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

/**
 * Get information about reserve-not-closed-inconsistency from the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_id row/serial ID where to start the iteration (0 from
 *                  the start, exclusive, i.e. serial_ids must start from 1)
 * @param return_suppressed should suppressed rows be returned anyway?
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_reserve_not_closed_inconsistency (
  void *cls,
  int64_t limit,
  uint64_t offset,
  bool return_suppressed,
  TALER_AUDITORDB_ReserveNotClosedInconsistencyCallback cb,
  void *cb_cls);

#endif // SRC_PG_GET_RESERVE_NOT_CLOSED_INCONSISTENCY_H
