/*
   This file is part of TALER
   Copyright (C) 2022-2023 Taler Systems SA

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
 * @file exchangedb/pg_select_batch_deposits_missing_wire.h
 * @brief implementation of the select_batch_deposits_missing_wire function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_DEPOSITS_MISSING_WIRE_H
#define PG_SELECT_DEPOSITS_MISSING_WIRE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Select all of those batch deposits in the database
 * above the given serial ID.
 *
 * @param cls closure
 * @param min_batch_deposit_serial_id select all batch deposits above this ID
 * @param cb function to call on all such deposits
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_batch_deposits_missing_wire (
  void *cls,
  uint64_t min_batch_deposit_serial_id,
  TALER_EXCHANGEDB_WireMissingCallback cb,
  void *cb_cls);

#endif
