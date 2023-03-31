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
 * @file exchangedb/pg_get_global_fee.h
 * @brief implementation of the get_global_fee function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_GLOBAL_FEE_H
#define PG_GET_GLOBAL_FEE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Obtain global fees from database.
 *
 * @param cls closure
 * @param date for which date do we want the fee?
 * @param[out] start_date when does the fee go into effect
 * @param[out] end_date when does the fee end being valid
 * @param[out] fees how high are the wire fees
 * @param[out] purse_timeout set to how long we keep unmerged purses
 * @param[out] history_expiration set to how long we keep account histories
 * @param[out] purse_account_limit set to the number of free purses per account
 * @param[out] master_sig signature over the above by the exchange master key
 * @return status of the transaction
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_global_fee (void *cls,
                       struct GNUNET_TIME_Timestamp date,
                       struct GNUNET_TIME_Timestamp *start_date,
                       struct GNUNET_TIME_Timestamp *end_date,
                       struct TALER_GlobalFeeSet *fees,
                       struct GNUNET_TIME_Relative *purse_timeout,
                       struct GNUNET_TIME_Relative *history_expiration,
                       uint32_t *purse_account_limit,
                       struct TALER_MasterSignatureP *master_sig);

#endif
