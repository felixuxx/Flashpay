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
 * @file pg_select_reserve_close_info.h
 * @brief implementation of the select_reserve_close_info function
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_RESERVE_CLOSE_INFO_H
#define PG_SELECT_RESERVE_CLOSE_INFO_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Select information needed to see if we can close
 * a reserve.
 *
 * @param cls closure
 * @param reserve_pub which reserve is this about?
 * @param[out] balance current reserve balance
 * @param[out] payto_uri set to URL of account that
 *             originally funded the reserve;
 *             could be set to NULL if not known
 * @return transaction status code, 0 if reserve unknown
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_reserve_close_info (
  void *cls,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_Amount *balance,
  struct TALER_FullPayto *payto_uri);


#endif
