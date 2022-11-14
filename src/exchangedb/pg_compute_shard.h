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
 * @file exchangedb/pg_compute_shard.h
 * @brief implementation of the compute_shard function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_COMPUTE_SHARD_H
#define PG_COMPUTE_SHARD_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Compute the shard number of a given @a merchant_pub.
 *
 * @param merchant_pub merchant public key to compute shard for
 * @return shard number
 */
uint64_t
TEH_PG_compute_shard (const struct TALER_MerchantPublicKeyP *merchant_pub);


#endif
