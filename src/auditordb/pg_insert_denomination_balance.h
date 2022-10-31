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
 * @file pg_insert_denomination_balance.h
 * @brief implementation of the insert_denomination_balance function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_DENOMINATION_BALANCE_H
#define PG_INSERT_DENOMINATION_BALANCE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about a denomination key's balances.  There
 * must not be an existing record for the denomination key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param denom_pub_hash hash of the denomination public key
 * @param dcd circulation data to store
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_denomination_balance (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  const struct TALER_AUDITORDB_DenominationCirculationData *dcd);


#endif
