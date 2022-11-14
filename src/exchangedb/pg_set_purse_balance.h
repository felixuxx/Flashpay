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
 * @file exchangedb/pg_set_purse_balance.h
 * @brief implementation of the set_purse_balance function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SET_PURSE_BALANCE_H
#define PG_SET_PURSE_BALANCE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Set the current @a balance in the purse
 * identified by @a purse_pub. Used by the auditor
 * to update the balance as calculated by the auditor.
 *
 * @param cls closure
 * @param purse_pub public key of a purse
 * @param balance new balance to store under the purse
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_set_purse_balance (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_Amount *balance);

#endif
