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
 * @file exchangedb/pg_lookup_wire_transfer.h
 * @brief implementation of the lookup_wire_transfer function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_WIRE_TRANSFER_H
#define PG_LOOKUP_WIRE_TRANSFER_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Lookup the list of Taler transactions that were aggregated
 * into a wire transfer by the respective @a wtid.
 *
 * @param cls closure
 * @param wtid the raw wire transfer identifier we used
 * @param cb function to call on each transaction found
 * @param cb_cls closure for @a cb
 * @return query status of the transaction
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_wire_transfer (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  TALER_EXCHANGEDB_AggregationDataCallback cb,
  void *cb_cls);

#endif
