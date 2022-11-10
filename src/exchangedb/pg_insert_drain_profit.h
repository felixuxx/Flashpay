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
 * @file exchangedb/pg_insert_drain_profit.h
 * @brief implementation of the insert_drain_profit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_DRAIN_PROFIT_H
#define PG_INSERT_DRAIN_PROFIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to persist a request to drain profits.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wtid wire transfer ID to use
 * @param account_section account to drain
 * @param payto_uri account to wire funds to
 * @param request_timestamp when was the request made
 * @param amount amount to wire
 * @param master_sig signature affirming the operation
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_drain_profit (
  void *cls,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const char *account_section,
  const char *payto_uri,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *amount,
  const struct TALER_MasterSignatureP *master_sig);

#endif
