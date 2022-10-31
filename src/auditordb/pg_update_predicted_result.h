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
 * @file pg_update_predicted_result.h
 * @brief implementation of the update_predicted_result function
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_PREDICTED_RESULT_H
#define PG_UPDATE_PREDICTED_RESULT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Update information about an exchange's predicted balance.  There
 * must be an existing record for the exchange.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param balance what the bank account balance of the exchange should show
 * @param drained amount that was drained in profits
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_update_predicted_result (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_Amount *balance,
  const struct TALER_Amount *drained);

#endif
