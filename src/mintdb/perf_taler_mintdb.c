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
#include "platform.h"
#include "perf_taler_mintdb_interpreter.h"
#include "perf_taler_mintdb_values.h"

/**
 * Runs the performances tests for the mint database
 * and logs the results using Gauger
 */
int
main (int argc, char ** argv)
{
  struct TALER_MINTDB_Plugin *plugin;
  struct GNUNET_CONFIGURATION_Handle *config;
  struct PERF_TALER_MINTDB_Cmd test[] =
  {
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("loop_db_init_deposit",
                                     PERF_TALER_MINTDB_NB_DEPOSIT_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION ("start_transaction_init"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT ("init_deposit_insert"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION ("commit_transaction_init"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("array_depo",
                                           "loop_db_init_deposit",
                                           "init_deposit_insert",
                                           PERF_TALER_MINTDB_NB_DEPOSIT_GET,
                                           PERF_TALER_MINTDB_DEPOSIT),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("endloop_init_deposit",
                                         "loop_db_init_deposit"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG("INIT_END"),
    // End of database initialization
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("deposit_get_start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("loop_deposit_get",
                                     PERF_TALER_MINTDB_NB_DEPOSIT_GET),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION ("start_transaction_get"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("load deposit",
                                          "loop_deposit_get",
                                          "array_depo"),
    PERF_TALER_MINTDB_INIT_CMD_GET_DEPOSIT ("get_deposit",
                                           "load_deposit"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION ("commit_transaction_init"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("stop2", "loop_deposit_get"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("deposit_get_end"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("deposit_get_commit",
                                       "deposit_get_start",
                                       "deposit_get_end",
                                       "time per deposit check",
                                       PERF_TALER_MINTDB_NB_DEPOSIT_GET),
    PERF_TALER_MINTDB_INIT_CMD_END("end"),
  };
  // Plugin init

  GNUNET_log_setup ("perf-taler-mintdb",
                    "WARNING",
                    NULL);
  config = GNUNET_CONFIGURATION_create();
  GNUNET_CONFIGURATION_load(config, "./test-mint-db-postgres.conf");
  GNUNET_assert (NULL !=
                 (plugin = TALER_MINTDB_plugin_load (config)));
  plugin->create_tables (plugin->cls, GNUNET_YES);
  // Run command
  PERF_TALER_MINTDB_interpret(plugin, test);
  // Drop tables
  {
    struct TALER_MINTDB_Session *session;

    session = plugin->get_session (plugin->cls, GNUNET_YES);
    plugin->drop_temporary (plugin->cls, session);
  }
  TALER_MINTDB_plugin_unload(plugin);
  GNUNET_CONFIGURATION_destroy(config);
  return GNUNET_OK;
}
