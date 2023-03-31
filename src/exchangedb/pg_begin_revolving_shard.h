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
 * @file exchangedb/pg_begin_revolving_shard.h
 * @brief implementation of the begin_revolving_shard function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_BEGIN_REVOLVING_SHARD_H
#define PG_BEGIN_REVOLVING_SHARD_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Function called to grab a revolving work shard on an operation @a op. Runs
 * in its own transaction. Returns the oldest inactive shard.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to grab a revolving shard for
 * @param shard_size desired shard size
 * @param shard_limit exclusive end of the shard range
 * @param[out] start_row inclusive start row of the shard (returned)
 * @param[out] end_row inclusive end row of the shard (returned)
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_begin_revolving_shard (void *cls,
                              const char *job_name,
                              uint32_t shard_size,
                              uint32_t shard_limit,
                              uint32_t *start_row,
                              uint32_t *end_row);

#endif
