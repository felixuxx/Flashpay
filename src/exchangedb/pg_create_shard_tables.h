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
 * @file exchangedb/pg_create_shard_tables.h
 * @brief implementation of the create_shard_tables function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_CREATE_SHARD_TABLES_H
#define PG_CREATE_SHARD_TABLES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Create tables of a shard node with index idx
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param idx the shards index, will be appended as suffix to all tables
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
enum GNUNET_GenericReturnValue
TEH_PG_create_shard_tables (void *cls,
                            uint32_t idx);

#endif
