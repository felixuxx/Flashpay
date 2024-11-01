/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file auditordb/pg_insert_pending_deposit.h
 * @brief implementation of the insert_pending_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_PENDING_DEPOSIT_H
#define PG_INSERT_PENDING_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert new row into the pending deposits table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param batch_deposit_serial_id where in the table are we
 * @param total_amount value of all missing deposits, including fees
 * @param wire_target_h_payto hash of the recipient account's payto URI
 * @param deadline what was the requested wire transfer deadline
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_pending_deposit (
  void *cls,
  uint64_t batch_deposit_serial_id,
  const struct TALER_FullPaytoHashP *wire_target_h_payto,
  const struct TALER_Amount *total_amount,
  struct GNUNET_TIME_Timestamp deadline);


#endif
