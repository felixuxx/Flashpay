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
 * @file exchangedb/pg_profit_drains_set_finished.h
 * @brief implementation of the profit_drains_set_finished function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_PROFIT_DRAINS_SET_FINISHED_H
#define PG_PROFIT_DRAINS_SET_FINISHED_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Set profit drain operation to finished.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param serial serial ID of the entry to mark finished
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_profit_drains_set_finished (
  void *cls,
  uint64_t serial);

#endif
