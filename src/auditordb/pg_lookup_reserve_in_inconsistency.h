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
#ifndef PG_LOOKUP_RESERVE_IN_INCONSISTENCY_H
#define PG_LOOKUP_RESERVE_IN_INCONSISTENCY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

/**
 * Lookup information about reserve-in-inconsistency from the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param bank_row_id row of the transaction at the bank
 * @param[out] dc set to the transaction details
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_lookup_reserve_in_inconsistency (
  void *cls,
  uint64_t bank_row_id,
  struct TALER_AUDITORDB_ReserveInInconsistency *dc);

#endif
