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
    // Denomination used to create coins
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("00 - Start of interpreter"),

    PERF_TALER_MINTDB_INIT_CMD_LOOP ("01 - denomination loop",
                                     PERF_TALER_MINTDB_NB_DENOMINATION_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION ("01 - start transaction"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DENOMINATION ("01 - denomination"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION ("01 - commit transaction"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("01 - save denomination",
                                           "01 - denomination loop",
                                           "01 - denomination",
                                           PERF_TALER_MINTDB_NB_DENOMINATION_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("01 - denomination loop end",
                                         "01 - denomination loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("01 - init denomination complete"),
    // End of initialization
    // Reserve initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("02 - init reserve loop",
                                     PERF_TALER_MINTDB_NB_RESERVE_INIT),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE ("02 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("02 - save reserve",
                                           "02 - init reserve loop",
                                           "02 - reserve",
                                           PERF_TALER_MINTDB_NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("02 - init reserve end loop",
                                         "02 - init reserve loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("02 - reserve init complete"),
    // End reserve init"00 - Start of interpreter"),
    // Withdrawal initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("03 - init withdraw loop",
                                     PERF_TALER_MINTDB_NB_WITHDRAW_INIT),
    //    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION ("03 - start transaction"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - denomination load",
                                           "03 - init withdraw loop",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - reserve load",
                                           "03 - init withdraw loop",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("03 - withdraw",
                                                "03 - denomination load",
                                                "03 - reserve load"),
    //    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION ("03 - commit transaction"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("03 - blindcoin array",
                                           "03 - init withdraw loop",
                                           "03 - withdraw",
                                           PERF_TALER_MINTDB_NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("03 - withdraw init end loop",
                                         "03 - init withdraw loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("03 - withdraw init complete"),
    //End of withdrawal initialization
    //Deposit initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("04 - deposit init loop",
                                     PERF_TALER_MINTDB_NB_DEPOSIT_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION ("04 - start transaction"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("04 - denomination load",
                                           "04 - deposit init loop",
                                           "01 - save denomination"),

    PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT ("04 - deposit",
                                               "04 - denomination load"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION ("04 - commit transaction"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("04 - deposit array",
                                           "04 - deposit init loop",
                                           "04 - deposit",
                                           PERF_TALER_MINTDB_NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("04 - deposit init loop end",
                                         "04 - deposit init loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("04 - deposit init complete"),
    // End of deposit initialization
    PERF_TALER_MINTDB_INIT_CMD_END ("end"),
  };

  GNUNET_log_setup ("perf-taler-mintdb",
                    "INFO",
                    NULL);
  config = GNUNET_CONFIGURATION_create ();
  GNUNET_CONFIGURATION_load (config, "./test-mint-db-postgres.conf");
  GNUNET_assert (NULL !=
                 (plugin = TALER_MINTDB_plugin_load (config)));
  plugin->create_tables (plugin->cls, GNUNET_YES);
  PERF_TALER_MINTDB_interpret (plugin, test);
  /* Drop tables */
  {
    struct TALER_MINTDB_Session *session;

    session = plugin->get_session (plugin->cls, GNUNET_YES);
    plugin->drop_temporary (plugin->cls, session);
  }
  TALER_MINTDB_plugin_unload (plugin);
  GNUNET_CONFIGURATION_destroy (config);
  return 0;
}
