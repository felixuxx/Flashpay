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


#define NB_DENOMINATION_INIT  15
#define NB_DENOMINATION_SAVE  15

#define NB_RESERVE_INIT   10000
#define NB_RESERVE_SAVE   1000

#define NB_DEPOSIT_INIT   10000
#define NB_DEPOSIT_SAVE   1000

#define NB_WITHDRAW_INIT  10000
#define NB_WITHDRAW_SAVE  1000

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
    
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("Start of performances measuring"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("05 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("05 - reserve insert measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE (""),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "05 - reserve insert measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("05 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "05 - start",
                                       "05 - stop",
                                       "POSTGRES",
                                       "Number of reserve inserted per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of reserve insertion"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("06 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("06 - reserve load measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("06 - reserve",
                                           "06 - reserve load measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE ("",
                                            "06 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "06 - reserve load measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("06 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "06 - start",
                                       "06 - stop",
                                       "POSTGRES",
                                       "Number of reserve loaded per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of reserve retreival"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("07 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("07 - reserve history measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("07 - reserve",
                                           "07 - reserve history measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE_HISTORY ("",
                                                    "07 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "07 - reserve history measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("07 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "07 - start",
                                       "07 - stop",
                                       "POSTGRES",
                                       "Number of reserve history loaded per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of reserve history access"),


    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("08 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("08 - withdraw insert measure",
                                     NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("08 - reserve",
                                           "08 - withdraw insert measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("08 - denomination",
                                           "08 - withdraw insert measure",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("",
                                                "08 - denomination",
                                                "08 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "08 - withdraw insert measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("08 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "08 - start",
                                       "08 - stop",
                                       "POSTGRES",
                                       "Number of withdraw insert per second",
                                       "item/sec",
                                       NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of withdraw insertion"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("09 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("09 - withdraw insert measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("09 - reserve",
                                           "09 - withdraw insert measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("09 - denomination",
                                           "09 - withdraw insert measure",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("",
                                                "09 - denomination",
                                                "09 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "09 - withdraw insert measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("09 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "09 - start",
                                       "09 - stop",
                                       "POSTGRES",
                                       "Number of withdraw loaded per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of withdraw loading"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("10 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("10 - get coin transaction",
                                     NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("10 - coin",
                                           "10 - get coin transaction",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_GET_COIN_TRANSACTION("",
                                                    "10 - coin"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "10 - get coin transaction"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("10 - end"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "10 - start",
                                       "10 - end",
                                       "POSTGRES",
                                       "Number of coin transaction history loaded per second",
                                       "item/sec",
                                       NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of transaction loading"),
 
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("11 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("11 - /withdraw/sign",
                                     NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("11 - reserve",
                                           "11 - /withdraw/sign",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("11 - dki",
                                           "11 - /withdraw/sign",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_WITHDRAW_SIGN ("",
                                              "11 - dki",
                                              "11 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "11 - /withdraw/sign"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("11 - end"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "11 - start",
                                       "11 - end",
                                       "POSTGRES",
                                       "Number of /withdraw/sign per second",
                                       "item/sec",
                                       NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of /withdraw/sign"),
    PERF_TALER_MINTDB_INIT_CMD_END (""),
  };
  
  ret = PERF_TALER_MINTDB_run_benchmark (
    "perf-taler-mintdb",
    "./test-mint-db-postgres.conf",
    (struct PERF_TALER_MINTDB_Cmd []) {PERF_TALER_MINTDB_INIT_CMD_END("")},
    benchmark);
  if (GNUNET_SYSERR == ret)
    return 1;
  return 0;
}
