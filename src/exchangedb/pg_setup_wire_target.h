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
 * @file exchangedb/pg_setup_wire_target.h
 * @brief implementation of the setup_wire_target function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SETUP_WIRE_TARGET_H
#define PG_SETUP_WIRE_TARGET_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "pg_helper.h"
#include "taler_exchangedb_plugin.h"

/**
 * Setup new wire target for @a payto_uri.
 *
 * @param pg the plugin-specific state
 * @param payto_uri the payto URI to check
 * @param[out] h_payto set to the hash of @a payto_uri
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_setup_wire_target (
  struct PostgresClosure *pg,
  const char *payto_uri,
  struct TALER_PaytoHashP *h_payto);

#endif
