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
 * @file auditordb/pg_delete_pending_deposit.h
 * @brief implementation of the delete_pending_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DELETE_PENDING_DEPOSIT_H
#define PG_DELETE_PENDING_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Delete a row from the pending deposit table.
 * Usually done when the respective wire transfer
 * was finally detected.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param batch_deposit_serial_id which entry to delete
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_delete_pending_deposit (
  void *cls,
  uint64_t batch_deposit_serial_id);


#endif
