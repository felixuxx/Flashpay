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
 * @file exchangedb/pg_wire_prepare_data_get.h
 * @brief implementation of the wire_prepare_data_get function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_WIRE_PREPARE_DATA_GET_H
#define PG_WIRE_PREPARE_DATA_GET_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to get an unfinished wire transfer
 * preparation data. Fetches at most one item.
 *
 * @param cls closure
 * @param start_row offset to query table at
 * @param limit maximum number of results to return
 * @param cb function to call for ONE unfinished item
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_wire_prepare_data_get (void *cls,
                                uint64_t start_row,
                                uint64_t limit,
                                TALER_EXCHANGEDB_WirePreparationIterator cb,
                              void *cb_cls);
#endif
