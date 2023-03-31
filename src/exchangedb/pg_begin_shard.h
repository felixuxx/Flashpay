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
 * @file exchangedb/pg_begin_shard.h
 * @brief implementation of the begin_shard function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_BEGIN_SHARD_H
#define PG_BEGIN_SHARD_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Function called to grab a work shard on an operation @a op. Runs in its
 * own transaction.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param job_name name of the operation to grab a word shard for
 * @param delay minimum age of a shard to grab
 * @param shard_size desired shard size
 * @param[out] start_row inclusive start row of the shard (returned)
 * @param[out] end_row exclusive end row of the shard (returned)
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_begin_shard (void *cls,
                    const char *job_name,
                    struct GNUNET_TIME_Relative delay,
                    uint64_t shard_size,
                    uint64_t *start_row,
                    uint64_t *end_row);

#endif
