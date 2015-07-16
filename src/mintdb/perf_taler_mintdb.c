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


#define NB_DENOMINATION_INIT  10
#define NB_DENOMINATION_SAVE  10

#define NB_RESERVE_INIT   1000
#define NB_RESERVE_SAVE   100

#define NB_DEPOSIT_INIT   1000
#define NB_DEPOSIT_SAVE   100

#define NB_WITHDRAW_INIT  1000
#define NB_WITHDRAW_SAVE  100

/**
 * Runs the performances tests for the mint database
 * and logs the results using Gauger
 */
int
main (int argc, char ** argv)
{
  int ret;
  struct PERF_TALER_MINTDB_Cmd benchmark[] =
  {
    // Denomination used to create coins
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("Initializing database"),

    PERF_TALER_MINTDB_INIT_CMD_LOOP ("01 - denomination loop",
                                     NB_DENOMINATION_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DENOMINATION ("01 - denomination"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("01 - save denomination",
                                           "01 - denomination loop",
                                           "01 - denomination",
                                           NB_DENOMINATION_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "01 - denomination loop"),
    // End of initialization
    // Reserve initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("02 - init reserve loop",
                                     NB_RESERVE_INIT),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE ("02 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("02 - save reserve",
                                           "02 - init reserve loop",
                                           "02 - reserve",
                                           NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "02 - init reserve loop"),
    // End reserve init
    // Withdrawal initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("03 - init withdraw loop",
                                     NB_WITHDRAW_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - denomination load",
                                           "03 - init withdraw loop",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - reserve load",
                                           "03 - init withdraw loop",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("03 - withdraw",
                                                "03 - denomination load",
                                                "03 - reserve load"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("03 - save coin",
                                           "03 - init withdraw loop",
                                           "03 - withdraw",
                                           NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "03 - init withdraw loop"),
    //End of withdrawal initialization
    //Deposit initialization
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("04 - deposit init loop",
                                     NB_DEPOSIT_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("04 - coin load",
                                           "04 - deposit init loop",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT ("04 - deposit",
                                               "04 - coin load"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("04 - deposit array",
                                           "04 - deposit init loop",
                                           "04 - deposit",
                                           NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "04 - deposit init loop"),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of initialization"),
    // End of deposit initialization
    
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("05 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("05 - loop",
                                     NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("05 - deposit load",
                                           "05 - loop",
                                           "04 - deposit array"),
    PERF_TALER_MINTDB_INIT_CMD_GET_DEPOSIT ("",
                                            "05 - deposit load"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "05 - loop"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("05 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "05 - start",
                                       "05 - stop",
                                       "deposit insertion",
                                       "deposit/sec",
                                       NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END (""),
  };
  
  ret = PERF_TALER_MINTDB_run_benchmark ("perf-taler-mintdb",
                                         "./test-mint-db-postgres.conf",
                                         (struct PERF_TALER_MINTDB_Cmd []) 
                                         {PERF_TALER_MINTDB_INIT_CMD_END("")},
                                         benchmark);
  if (GNUNET_SYSERR == ret)
    return 1;
  return 0;
}
