/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_insert_age_withdraw_reveal.h
 * @brief implementation of the insert_age_withdraw_reveal function for Postgres
 * @author Özgür Kesim
 */
#ifndef PG_INSERT_AGE_WITHDRAW_REVEAL_H
#define PG_INSERT_AGE_WITHDRAW_REVEAL_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * @brief Store in the database which coin(s) the wallet wanted to create in a
 * given age-withdraw operation and all of the other information we learned or
 * created in the /age-withdraw/reveal step.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * TODO:oec
 * @return query status for the transaction
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_refresh_reveal (
  void *cls,
  /* TODO: oec */
  );

#endif
