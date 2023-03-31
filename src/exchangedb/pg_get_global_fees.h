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
 * @file exchangedb/pg_get_global_fees.h
 * @brief implementation of the get_global_fees function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_GLOBAL_FEES_H
#define PG_GET_GLOBAL_FEES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Obtain global fees from database.
 *
 * @param cls closure
 * @param cb function to call on each fee entry
 * @param cb_cls closure for @a cb
 * @return status of the transaction
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_global_fees (void *cls,
                        TALER_EXCHANGEDB_GlobalFeeCallback cb,
                        void *cb_cls);

#endif
