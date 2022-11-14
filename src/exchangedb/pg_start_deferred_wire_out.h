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
 * @file exchangedb/pg_start_deferred_wire_out.h
 * @brief implementation of the start_deferred_wire_out function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_START_DEFERRED_WIRE_OUT_H
#define PG_START_DEFERRED_WIRE_OUT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Starts a READ COMMITTED transaction where we transiently violate the foreign
 * constraints on the "wire_out" table as we insert aggregations
 * and only add the wire transfer out at the end.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_PG_start_deferred_wire_out (void *cls);

#endif
