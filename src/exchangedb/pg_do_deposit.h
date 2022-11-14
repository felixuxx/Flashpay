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
 * @file exchangedb/pg_do_deposit.h
 * @brief implementation of the do_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_DEPOSIT_H
#define PG_DO_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Perform deposit operation, checking for sufficient balance
 * of the coin and possibly persisting the deposit details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param deposit deposit operation details
 * @param known_coin_id row of the coin in the known_coins table
 * @param h_payto hash of the merchant's bank account details
 * @param policy_details_serial_id pointer to the ID of the entry in policy_details, maybe NULL
 * @param[in,out] exchange_timestamp time to use for the deposit (possibly updated)
 * @param[out] balance_ok set to true if the balance was sufficient
 * @param[out] in_conflict set to true if the deposit conflicted
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_deposit (
  void *cls,
  const struct TALER_EXCHANGEDB_Deposit *deposit,
  uint64_t known_coin_id,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *policy_details_serial_id,
  struct GNUNET_TIME_Timestamp *exchange_timestamp,
  bool *balance_ok,
  bool *in_conflict);

#endif
