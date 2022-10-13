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
 * @file plugin_exchangedb_common.h
 * @brief implementation of database-independent functions
 * @author Christian Grothoff
 */
#ifndef PLUGIN_EXCHANGEDB_COMMON_H
#define PLUGIN_EXCHANGEDB_COMMON_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Free memory associated with the given reserve history.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param[in] rh history to free.
 */
void
TEH_COMMON_free_reserve_history (
  void *cls,
  struct TALER_EXCHANGEDB_ReserveHistory *rh);


/**
 * Free linked list of transactions.
 *
 * @param cls the @e cls of this struct with the plugin-specific state (unused)
 * @param[in] tl list to free
 */
void
TEH_COMMON_free_coin_transaction_list (
  void *cls,
  struct TALER_EXCHANGEDB_TransactionList *tl);

#endif
