/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file pg_insert_balance.h
 * @brief implementation of the insert_balance function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_BALANCE_H
#define PG_INSERT_BALANCE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

/**
 * Insert information about a balance tracked by the auditor. There must not be an
 * existing record.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param balance_key key of the blance to store
 * @param balance_value value to store
 * @param ... NULL terminated list of additional key-value pairs to insert
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_balance (void *cls,
                       const char *balance_key,
                       const struct TALER_Amount *balance_value,
                       ...);


#endif
