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
 * @file exchangedb/pg_start_read_committed.h
 * @brief implementation of the start_read_committed function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_START_READ_COMMITTED_H
#define PG_START_READ_COMMITTED_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Start a READ COMMITTED transaction.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param name unique name identifying the transaction (for debugging)
 *             must point to a constant
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_PG_start_read_committed (void *cls,
                             const char *name);

#endif
