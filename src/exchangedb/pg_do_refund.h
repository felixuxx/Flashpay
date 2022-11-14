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
 * @file exchangedb/pg_do_refund.h
 * @brief implementation of the do_refund function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_REFUND_H
#define PG_DO_REFUND_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Perform refund operation, checking for sufficient deposits
 * of the coin and possibly persisting the refund details.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param refund refund operation details
 * @param deposit_fee deposit fee applicable for the coin, possibly refunded
 * @param known_coin_id row of the coin in the known_coins table
 * @param[out] not_found set if the deposit was not found
 * @param[out] refund_ok  set if the refund succeeded (below deposit amount)
 * @param[out] gone if the merchant was already paid
 * @param[out] conflict set if the refund ID was re-used
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_refund (
  void *cls,
  const struct TALER_EXCHANGEDB_Refund *refund,
  const struct TALER_Amount *deposit_fee,
  uint64_t known_coin_id,
  bool *not_found,
  bool *refund_ok,
  bool *gone,
  bool *conflict);

#endif
