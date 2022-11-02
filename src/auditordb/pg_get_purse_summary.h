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
 * @file auditordb/pg_get_purse_summary.h
 * @brief implementation of the get_purse_summary function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_PURSE_SUMMARY_H
#define PG_GET_PURSE_SUMMARY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Get summary information about all purses.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param[out] sum purse balances summary to initialize
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_purse_summary (void *cls,
                          const struct TALER_MasterPublicKeyP *master_pub,
                          struct TALER_AUDITORDB_PurseBalance *sum);


#endif
