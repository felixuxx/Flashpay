/*
   This file is part of TALER
   Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mintdb/perf_taler_mintdb.c
 * @brief Mint database performance analysis
 * @author Nicolas Fournier
 */
#include "perf_taler_mintdb_interpreter.h"

/**
 * Runs the performances tests for the mint database
 */
int
main(int argc, char ** argv)
{

  struct PERF_TALER_MINTDB_CMD test[] = 
  {
    INIT_CMD_LOOP("loop_db_init_deposit",100000),
    INIT_CMD_START_TRANSACTION("start_transaction_init"),
    INIT_CMD_INSERT_DEPOSIT("init_deposit_insert"),
    INIT_CMD_COMMIT_TRANSACTION("commit_transaction_init"),
    INIT_CMD_END_LOOP("endloop_init_deposit","loop_db_init_deposit"),


    INIT_CMD_END("end")
  };

  struct GNUNET_CONFIGURATION_Handle *config = GNUNET_CONFIGURATION_create();

  // FIXME Add data to the config handler to be able to connect to the database

  struct TALER_MINTDB_Plugin *plugin = TALER_MINTDB_plugin_load(config);
  struct TALER_MINTDB_Session *session = plugin->get_session(plugin->cls, GNUNET_YES);

  plugin->create_tables(plugin->cls, GNUNET_YES);


  PERF_TALER_MINTDB_interprete(plugin, session, test);


  plugin->drop_temporary(plugin->cls, session);

  // Free the session ??

  TALER_MINTDB_plugin_unload(plugin);
  return GNUNET_OK;
}
