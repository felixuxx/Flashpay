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
 * @file exchangedb/pg_select_purse_deposits_by_purse.h
 * @brief implementation of the select_purse_deposits_by_purse function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_PURSE_DEPOSITS_BY_PURSE_H
#define PG_SELECT_PURSE_DEPOSITS_BY_PURSE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Select coin affected by purse refund.
 *
 * @param cls closure
 * @param purse_pub purse that was refunded
 * @param cb function to call on each result
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_deposits_by_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  TALER_EXCHANGEDB_PurseRefundCoinCallback cb,
  void *cb_cls);

#endif
