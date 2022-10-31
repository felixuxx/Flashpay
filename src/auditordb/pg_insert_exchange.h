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
 * @file pg_insert_exchange.h
 * @brief implementation of the insert_exchange function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_EXCHANGE_H
#define PG_INSERT_EXCHANGE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about an exchange this auditor will be auditing.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @param exchange_url public (base) URL of the API of the exchange
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_exchange (void *cls,
                        const struct TALER_MasterPublicKeyP *master_pub,
                        const char *exchange_url);


#endif
