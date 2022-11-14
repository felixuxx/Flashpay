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
 * @file exchangedb/pg_get_refresh_reveal.h
 * @brief implementation of the get_refresh_reveal function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_REFRESH_REVEAL_H
#define PG_GET_REFRESH_REVEAL_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Lookup in the database the coins that we want to
 * create in the given refresh operation.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param rc identify commitment and thus refresh operation
 * @param cb function to call with the results
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_refresh_reveal (void *cls,
                             const struct TALER_RefreshCommitmentP *rc,
                             TALER_EXCHANGEDB_RefreshCallback cb,
                           void *cb_cls);

#endif
