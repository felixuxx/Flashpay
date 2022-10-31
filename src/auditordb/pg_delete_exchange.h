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
 * @file pg_delete_exchange.h
 * @brief implementation of the delete_exchange function
 * @author Christian Grothoff
 */
#ifndef PG_DELETE_EXCHANGE_H
#define PG_DELETE_EXCHANGE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Delete an exchange from the list of exchanges this auditor is auditing.
 * Warning: this will cascade and delete all knowledge of this auditor related
 * to this exchange!
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master public key of the exchange
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_delete_exchange (void *cls,
                        const struct TALER_MasterPublicKeyP *master_pub);


#endif
