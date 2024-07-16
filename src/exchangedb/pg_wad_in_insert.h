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
 * @file exchangedb/pg_wad_in_insert.h
 * @brief implementation of the wad_in_insert function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_WAD_IN_INSERT_H
#define PG_WAD_IN_INSERT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert an incoming WAD wire transfer into the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param wad_id WAD identifier
 * @param origin_exchange_url exchange base URL originating the transfer
 * @param execution_date when was the transfer made
 * @param debit_account_uri URI of the debit account
 * @param section_name section of the exchange bank account that received the transfer
 * @param serial_id bank-specific row identifying the transfer
 */
enum GNUNET_DB_QueryStatus
TEH_PG_wad_in_insert (
  void *cls,
  const struct TALER_WadIdentifierP *wad_id,
  const char *origin_exchange_url,
  struct GNUNET_TIME_Timestamp execution_date,
  const char *debit_account_uri,
  const char *section_name,
  uint64_t serial_id);


#endif
