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
 * @file exchangedb/pg_wire_prepare_data_mark_failed.h
 * @brief implementation of the wire_prepare_data_mark_failed function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_WIRE_PREPARE_DATA_MARK_FAILED_H
#define PG_WIRE_PREPARE_DATA_MARK_FAILED_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to mark wire transfer commit data as failed.
 *
 * @param cls closure
 * @param rowid which entry to mark as failed
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_wire_prepare_data_mark_failed (
  void *cls,
  uint64_t rowid);

#endif
