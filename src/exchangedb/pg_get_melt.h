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
 * @file exchangedb/pg_get_melt.h
 * @brief implementation of the get_melt function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_MELT_H
#define PG_GET_MELT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Lookup refresh melt commitment data under the given @a rc.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param rc commitment hash to use to locate the operation
 * @param[out] melt where to store the result; note that
 *             melt->session.coin.denom_sig will be set to NULL
 *             and is not fetched by this routine (as it is not needed by the client)
 * @param[out] melt_serial_id set to the row ID of @a rc in the refresh_commitments table
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_melt (void *cls,
                 const struct TALER_RefreshCommitmentP *rc,
                 struct TALER_EXCHANGEDB_Melt *melt,
                 uint64_t *melt_serial_id);

#endif
