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
 * @file exchangedb/pg_insert_history_request.h
 * @brief implementation of the insert_history_request function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_HISTORY_REQUEST_H
#define PG_INSERT_HISTORY_REQUEST_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Function called to persist a signature that
 * prove that the client requested an
 * account history.  Debits the @a history_fee from
 * the reserve (if possible).
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub account that the history was requested for
 * @param reserve_sig signature affirming the request
 * @param request_timestamp when was the request made
 * @param history_fee how much should the @a reserve_pub be charged for the request
 * @param[out] balance_ok set to TRUE if the reserve balance
 *         was sufficient
 * @param[out] idempotent set to TRUE if the request is already in the DB
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_history_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *history_fee,
  bool *balance_ok,
  bool *idempotent);

#endif
