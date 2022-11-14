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
 * @file exchangedb/pg_select_recoup_refresh_above_serial_id.h
 * @brief implementation of the select_recoup_refresh_above_serial_id function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_RECOUP_REFRESH_ABOVE_SERIAL_ID_H
#define PG_SELECT_RECOUP_REFRESH_ABOVE_SERIAL_ID_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to select recoup requests the exchange received for
 * refreshed coins, ordered by serial ID (monotonically increasing).
 *
 * @param cls closure
 * @param serial_id lowest serial ID to include (select larger or equal)
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_recoup_refresh_above_serial_id (
  void *cls,
  uint64_t serial_id,
  TALER_EXCHANGEDB_RecoupRefreshCallback cb,
  void *cb_cls);

#endif
