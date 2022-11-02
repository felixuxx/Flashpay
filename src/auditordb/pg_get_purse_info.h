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
 * @file auditordb/pg_get_purse_info.h
 * @brief implementation of the get_purse_info function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_PURSE_INFO_H
#define PG_GET_PURSE_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Get information about a purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse
 * @param master_pub master public key of the exchange
 * @param[out] rowid which row did we get the information from
 * @param[out] balance set to balance of the purse
 * @param[out] expiration_date expiration date of the purse
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_purse_info (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_MasterPublicKeyP *master_pub,
  uint64_t *rowid,
  struct TALER_Amount *balance,
  struct GNUNET_TIME_Timestamp *expiration_date);

#endif
