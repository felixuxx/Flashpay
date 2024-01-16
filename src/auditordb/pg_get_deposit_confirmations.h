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
 * @file pg_get_deposit_confirmations.h
 * @brief implementation of the get_deposit_confirmations function
 * @author Christian Grothoff
 */
#ifndef PG_GET_DEPOSIT_CONFIRMATIONS_H
#define PG_GET_DEPOSIT_CONFIRMATIONS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Get information about deposit confirmations from the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_public_key for which exchange do we want to get deposit confirmations
 * @param start_id row/serial ID where to start the iteration (0 from
 *                  the start, exclusive, i.e. serial_ids must start from 1)
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_deposit_confirmations (
  void *cls,
  uint64_t start_id,
  TALER_AUDITORDB_DepositConfirmationCallback cb,
  void *cb_cls);

#endif
