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
 * @file exchangedb/pg_insert_global_fee.h
 * @brief implementation of the insert_global_fee function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_GLOBAL_FEE_H
#define PG_INSERT_GLOBAL_FEE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Insert global fee data into database.
 *
 * @param cls closure
 * @param start_date when does the fees go into effect
 * @param end_date when does the fees end being valid
 * @param fees how high is are the global fees
 * @param purse_timeout when do purses time out
 * @param history_expiration how long are account histories preserved
 * @param purse_account_limit how many purses are free per account
 * @param master_sig signature over the above by the exchange master key
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_global_fee (void *cls,
                          struct GNUNET_TIME_Timestamp start_date,
                          struct GNUNET_TIME_Timestamp end_date,
                          const struct TALER_GlobalFeeSet *fees,
                          struct GNUNET_TIME_Relative purse_timeout,
                          struct GNUNET_TIME_Relative history_expiration,
                          uint32_t purse_account_limit,
                          const struct TALER_MasterSignatureP *master_sig);
#endif
