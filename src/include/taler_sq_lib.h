/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file include/taler_sq_lib.h
 * @brief helper functions for DB interactions with SQLite
 * @author Jonathan Buchanan
 */
#ifndef TALER_SQ_LIB_H_
#define TALER_SQ_LIB_H_

#include <sqlite3.h>
#include <jansson.h>
#include <gnunet/gnunet_sq_lib.h>
#include "taler_util.h"

/**
 * Generate query parameter for a currency, consisting of the three
 * components "value", "fraction" in this order. The
 * types must be a 64-bit integer and a 64-bit integer.
 *
 * @param x pointer to the query parameter to pass
 */
struct GNUNET_SQ_QueryParam
TALER_SQ_query_param_amount_nbo (const struct TALER_AmountNBO *x);

/**
 * Currency amount expected.
 *
 * @param currency currency to use for @a amount
 * @param[out] amount where to store the result
 * @return array entry for the result specification to use
 */
struct GNUNET_SQ_ResultSpec
TALER_SQ_result_spec_amount_nbo (const char *currency,
                                 struct TALER_AmountNBO *amount);

#endif  /* TALER_SQ_LIB_H_ */

/* end of include/taler_sq_lib.h */
