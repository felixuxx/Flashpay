/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_insert_active_legitimization_measure.h
 * @brief implementation of the insert_active_legitimization_measure function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_ACTIVE_LEGITIMIZATION_MEASURE_H
#define PG_INSERT_ACTIVE_LEGITIMIZATION_MEASURE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Create new active legitimization measure.
 *
 *
 * @param cls closure
 * @param access_token access token that identifies the
 *   account the legitimization measures apply to
 * @param jmeasures new legitimization measures
 * @param[out] legitimization_measure_serial_id
 *    set to new row in legitimization_measures table
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_active_legitimization_measure (
  void *cls,
  const struct TALER_AccountAccessTokenP *access_token,
  const json_t *jmeasures,
  uint64_t *legitimization_measure_serial_id);


#endif
