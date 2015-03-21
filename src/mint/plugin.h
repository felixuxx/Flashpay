/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file mint/plugin.h
 * @brief Logic to load database plugins
 * @author Christian Grothoff
 */
#ifndef PLUGIN_H
#define PLUGIN_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_mintdb_plugin.h"

/**
 * Global variable with the plugin (once loaded).
 */
extern struct TALER_MINTDB_Plugin *plugin;


/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
int
TALER_MINT_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shutdown the plugin.
 */
void
TALER_MINT_plugin_unload (void);


/**
 * Free memory associated with the given reserve history.
 *
 * @param rh history to free.
 */
void
TALER_MINT_DB_free_reserve_history (struct ReserveHistory *rh);


/**
 * Free memory of the link data list.
 *
 * @param ldl link data list to release
 */
void
TALER_db_link_data_list_free (struct LinkDataList *ldl);


/**
 * Free linked list of transactions.
 *
 * @param list list to free
 */
void
TALER_MINT_DB_free_coin_transaction_list (struct TALER_MINT_DB_TransactionList *list);


#endif
