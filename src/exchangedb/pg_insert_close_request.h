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
 * @file pg_insert_close_request.h
 * @brief implementation of the insert_close_request function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_CLOSE_REQUEST_H
#define PG_INSERT_CLOSE_REQUEST_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Function called to initiate closure of an account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the account to close
 * @param payto_uri where to wire the funds
 * @param reserve_sig signature affiming that the account is to be closed
 * @param request_timestamp time of the close request (client-side?)
 * @param balance final balance in the reserve
 * @param closing_fee closing fee to charge
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_close_request (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const char *payto_uri,
  const struct TALER_ReserveSignatureP *reserve_sig,
  struct GNUNET_TIME_Timestamp request_timestamp,
  const struct TALER_Amount *balance,
  const struct TALER_Amount *closing_fee);


#endif
