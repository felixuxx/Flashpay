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
 * @file exchangedb/pg_get_ready_deposit.h
 * @brief implementation of the get_ready_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_READY_DEPOSIT_H
#define PG_GET_READY_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Obtain information about deposits that are ready to be executed.  Such
 * deposits must not be marked as "done", the execution time must be
 * in the past, and the KYC status must be 'ok'.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_shard_row minimum shard row to select
 * @param end_shard_row maximum shard row to select (inclusive)
 * @param[out] merchant_pub set to the public key of a merchant with a ready deposit
 * @param[out] payto_uri set to the account of the merchant, to be freed by caller
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_ready_deposit (void *cls,
                            uint64_t start_shard_row,
                            uint64_t end_shard_row,
                            struct TALER_MerchantPublicKeyP *merchant_pub,
                          char **payto_uri);

#endif
