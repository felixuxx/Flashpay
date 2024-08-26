/*
   This file is part of TALER
   Copyright (C) 2014--2023 Taler Systems SA

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
 * @file plugin_exchangedb_postgres.h
 * @brief Low-level (statement-level) Postgres database access for the exchange
 * @author Florian Dold
 * @author Christian Grothoff
 * @author Sree Harsha Totakura
 * @author Marcello Stanisci
 * @author Özgür Kesim
 */
#ifndef PLUGIN_EXCHANGEDB_POSTGRES_H
#define PLUGIN_EXCHANGEDB_POSTGRES_H
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"


/**
 * Connect to the database if the connection does not exist yet.
 *
 * @param pg the plugin-specific state
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_PG_internal_setup (struct PostgresClosure *pg);

#endif
