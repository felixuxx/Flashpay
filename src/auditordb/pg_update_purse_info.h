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
 * @file auditordb/pg_update_purse_info.h
 * @brief implementation of the update_purse_info function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_PURSE_INFO_H
#define PG_UPDATE_PURSE_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Update information about a purse.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse
 * @param balance new balance for the purse
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_update_purse_info (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *balance);


#endif
