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
 * @file pg_insert_reserve_info.h
 * @brief implementation of the insert_reserve_info function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_RESERVE_INFO_H
#define PG_INSERT_RESERVE_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about a reserve.  There must not be an
 * existing record for the reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param reserve_pub public key of the reserve
 * @param rfb balance amounts for the reserve
 * @param expiration_date when will the reserve expire
 * @param origin_account where did the money in the reserve originally come from
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_reserve_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const struct TALER_AUDITORDB_ReserveFeeBalance *rfb,
  struct GNUNET_TIME_Timestamp expiration_date,
  const struct TALER_FullPayto origin_account);

#endif
