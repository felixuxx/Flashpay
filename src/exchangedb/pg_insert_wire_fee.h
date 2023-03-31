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
 * @file exchangedb/pg_insert_wire_fee.h
 * @brief implementation of the insert_wire_fee function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_WIRE_FEE_H
#define PG_INSERT_WIRE_FEE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Insert wire transfer fee into database.
 *
 * @param cls closure
 * @param type type of wire transfer this fee applies for
 * @param start_date when does the fee go into effect
 * @param end_date when does the fee end being valid
 * @param fees how high are the wire fees
 * @param master_sig signature over the above by the exchange master key
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_wire_fee (void *cls,
                        const char *type,
                        struct GNUNET_TIME_Timestamp start_date,
                        struct GNUNET_TIME_Timestamp end_date,
                        const struct TALER_WireFeeSet *fees,
                        const struct TALER_MasterSignatureP *master_sig);
#endif
