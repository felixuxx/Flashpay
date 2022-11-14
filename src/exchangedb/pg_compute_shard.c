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
 * @file exchangedb/pg_compute_shard.c
 * @brief Implementation of the compute_shard function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_compute_shard.h"
#include "pg_helper.h"


uint64_t
TEH_PG_compute_shard (const struct TALER_MerchantPublicKeyP *merchant_pub)
{
  uint32_t res;

  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CRYPTO_kdf (&res,
                                    sizeof (res),
                                    merchant_pub,
                                    sizeof (*merchant_pub),
                                    "VOID",
                                    4,
                                    NULL, 0));
  /* interpret hash result as NBO for platform independence,
     convert to HBO and map to [0..2^31-1] range */
  res = ntohl (res);
  if (res > INT32_MAX)
    res += INT32_MIN;
  GNUNET_assert (res <= INT32_MAX);
  return (uint64_t) res;
}
