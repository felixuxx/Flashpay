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
 * @file exchangedb/pg_aggregate.h
 * @brief implementation of the aggregate function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_AGGREGATE_H
#define PG_AGGREGATE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Aggregate all matching deposits for @a h_payto and
 * @a merchant_pub, returning the total amounts.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param merchant_pub public key of the merchant
 * @param wtid wire transfer ID to set for the aggregate
 * @param[out] total set to the sum of the total deposits minus applicable deposit fees and refunds
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_aggregate (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  struct TALER_Amount *total);

#endif
