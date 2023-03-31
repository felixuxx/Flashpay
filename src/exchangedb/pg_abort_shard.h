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
 * @file exchangedb/pg_abort_shard.h
 * @brief implementation of the abort_shard function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_ABORT_SHARD_H
#define PG_ABORT_SHARD_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to abort work on a shard.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to abort a word shard for
 * @param start_row inclusive start row of the shard
 * @param end_row exclusive end row of the shard
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_abort_shard (void *cls,
                    const char *job_name,
                    uint64_t start_row,
                    uint64_t end_row);

#endif
