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
 * @file pq/pq_common.c
 * @brief common defines for the pq functions
 * @author Özgür Kesim
 */
#include "platform.h"
#include "pq_common.h"

struct TALER_PQ_AmountP
TALER_PQ_make_taler_pq_amount_ (
  const struct TALER_Amount *amount,
  uint32_t oid_v,
  uint32_t oid_f)
{
  struct TALER_PQ_AmountP rval = {
    .oid_v = htonl (oid_v),
    .oid_f = htonl (oid_f),
    .sz_v = htonl (sizeof((amount)->value)),
    .sz_f = htonl (sizeof((amount)->fraction)),
    .v = GNUNET_htonll ((amount)->value),
    .f = htonl ((amount)->fraction)
  };

  return rval;
}


struct TALER_PQ_AmountCurrencyP
TALER_PQ_make_taler_pq_amount_currency_ (
  const struct TALER_Amount *amount,
  uint32_t oid_v,
  uint32_t oid_f,
  uint32_t oid_c)
{
  struct TALER_PQ_AmountCurrencyP rval = {
    .oid_v = htonl (oid_v),
    .oid_f = htonl (oid_f),
    .oid_c = htonl (oid_c),
    .sz_v = htonl (sizeof((amount)->value)),
    .sz_f = htonl (sizeof((amount)->fraction)),
    .sz_c = htonl (TALER_CURRENCY_LEN),
    .v = GNUNET_htonll ((amount)->value),
    .f = htonl ((amount)->fraction),
  };

  memcpy (rval.c,
          amount->currency,
          TALER_CURRENCY_LEN);
  return rval;
}
