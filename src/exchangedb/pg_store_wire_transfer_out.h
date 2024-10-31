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
 * @file exchangedb/pg_store_wire_transfer_out.h
 * @brief implementation of the store_wire_transfer_out function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_STORE_WIRE_TRANSFER_OUT_H
#define PG_STORE_WIRE_TRANSFER_OUT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Store information about an outgoing wire transfer that was executed.
 *
 * @param cls closure
 * @param date time of the wire transfer
 * @param wtid subject of the wire transfer
 * @param h_payto identifies the receiver account of the wire transfer
 * @param exchange_account_section configuration section of the exchange specifying the
 *        exchange's bank account being used
 * @param amount amount that was transmitted
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_store_wire_transfer_out (
  void *cls,
  struct GNUNET_TIME_Timestamp date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const struct TALER_FullPaytoHashP *h_payto,
  const char *exchange_account_section,
  const struct TALER_Amount *amount);

#endif
