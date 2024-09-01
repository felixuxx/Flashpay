/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_do_check_deposit_idempotent.h
 * @brief implementation of the do_check_deposit_idempotent function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_CHECK_DEPOSIT_IDEMPOTENT_H
#define PG_DO_CHECK_DEPOSIT_IDEMPOTENT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Check ifdeposit operation is idempotent to existing one.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param bd batch deposit operation details
 * @param[in,out] exchange_timestamp time to use for the deposit (possibly updated)
 * @param[out] is_idempotent set to true if the request is idempotent
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_check_deposit_idempotent (
  void *cls,
  const struct TALER_EXCHANGEDB_BatchDeposit *bd,
  struct GNUNET_TIME_Timestamp *exchange_timestamp,
  bool *is_idempotent);

#endif
