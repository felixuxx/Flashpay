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
 * @file pg_insert_records_by_table.h
 * @brief implementation of the insert_records_by_table function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_RECORDS_BY_TABLE_H
#define PG_INSERT_RECORDS_BY_TABLE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert record set into @a table.  Used in exchange-auditor database
 * replication.
 *
 * @param cls closure
 * @param td table data to insert
 * @return transaction status code, #GNUNET_DB_STATUS_HARD_ERROR if
 *         @e table in @a tr is not supported
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_records_by_table (void *cls,
                                const struct TALER_EXCHANGEDB_TableData *td);


#endif
