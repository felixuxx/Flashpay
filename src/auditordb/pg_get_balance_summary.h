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
 * @file pg_get_balance_summary.h
 * @brief implementation of the get_balance_summary function
 * @author Christian Grothoff
 */
#ifndef PG_GET_BALANCE_SUMMARY_H
#define PG_GET_BALANCE_SUMMARY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Get information about an exchange's denomination balances.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param[out] dfb where to return the denomination balances
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_balance_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  struct TALER_AUDITORDB_GlobalCoinBalance *dfb);

#endif
