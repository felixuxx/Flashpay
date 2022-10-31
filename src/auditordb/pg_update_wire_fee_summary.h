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
 * @file pg_update_wire_fee_summary.h
 * @brief implementation of the update_wire_fee_summary function
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_WIRE_FEE_SUMMARY_H
#define PG_UPDATE_WIRE_FEE_SUMMARY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about exchange's wire fee balance.  Destructively updates an
 * existing record, which must already exist.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param wire_fee_balance amount the exchange gained in wire fees
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_update_wire_fee_summary (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *wire_fee_balance);

#endif
