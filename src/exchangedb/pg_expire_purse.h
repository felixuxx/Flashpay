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
 * @file exchangedb/pg_expire_purse.h
 * @brief implementation of the expire_purse function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_EXPIRE_PURSE_H
#define PG_EXPIRE_PURSE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Function called to clean up one expired purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param start_time select purse expired after this time
 * @param end_time select purse expired before this time
 * @return transaction status code (#GNUNET_DB_STATUS_SUCCESS_NO_RESULTS if no purse expired in the given time interval).
 */
enum GNUNET_DB_QueryStatus
TEH_PG_expire_purse (
  void *cls,
  struct GNUNET_TIME_Absolute start_time,
  struct GNUNET_TIME_Absolute end_time);

#endif
