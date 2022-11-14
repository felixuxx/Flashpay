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
 * @file exchangedb/pg_count_known_coins.h
 * @brief implementation of the count_known_coins function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_COUNT_KNOWN_COINS_H
#define PG_COUNT_KNOWN_COINS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Count the number of known coins by denomination.
 *
 * @param cls database connection plugin state
 * @param denom_pub_hash denomination to count by
 * @return number of coins if non-negative, otherwise an `enum GNUNET_DB_QueryStatus`
 */
long long
TEH_PG_count_known_coins (void *cls,
                            const struct
                          TALER_DenominationHashP *denom_pub_hash);

#endif
