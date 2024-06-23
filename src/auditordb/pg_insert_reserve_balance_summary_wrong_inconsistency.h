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


#ifndef SRC_PG_INSERT_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_H
#define SRC_PG_INSERT_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_H

#include "taler_util.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about a bad sig loss into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param dc deposit confirmation information to store
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_reserve_balance_summary_wrong_inconsistency (
  void *cls,
  const struct TALER_AUDITORDB_ReserveBalanceSummaryWrongInconsistency *dc);

#endif // SRC_PG_INSERT_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY_H
