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

#define SMALL 1000
#define BIG 10000
#define BIGGER 100000

#define NB_RESERVE_INIT   BIGGER
#define NB_RESERVE_SAVE   BIG

#define NB_DEPOSIT_INIT   BIGGER
#define NB_DEPOSIT_SAVE   BIG

#define NB_WITHDRAW_INIT  BIGGER
#define NB_WITHDRAW_SAVE  BIG

#define NB_REFRESH_INIT BIGGER
#define NB_REFRESH_SAVE BIG

#define NB_MELT_INIT BIG
#define NB_MELT_SAVE SMALL

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
    /* Denomination used to create coins */
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("Initializing database"),

    PERF_TALER_MINTDB_INIT_CMD_LOOP ("01 - denomination loop",
                                     NB_DENOMINATION_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_DENOMINATION ("01 - denomination"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DENOMINATION ("01 - insert",
                                                    "01 - denomination"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("01 - save denomination",
                                           "01 - denomination loop",
                                           "01 - denomination",
                                           NB_DENOMINATION_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("01 - end",
                                         "01 - denomination loop"),
    /* End of initialization */
    /* Reserve initialization */
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("02 - init reserve loop",
                                     NB_RESERVE_INIT),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_RESERVE ("02 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE ("02 - insert",
                                               "02 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("02 - save reserve",
                                           "02 - init reserve loop",
                                           "02 - reserve",
                                           NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("02 - end",
                                         "02 - init reserve loop"),
    /* End reserve init */
    /* Withdrawal initialization */
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("03 - init withdraw loop",
                                     NB_WITHDRAW_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - denomination load",
                                           "03 - init withdraw loop",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("03 - reserve load",
                                           "03 - init withdraw loop",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_WITHDRAW ("03 - withdraw",
                                                "03 - denomination load",
                                                "03 - reserve load"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("03 - insert",
                                                "03 - withdraw"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("03 - save coin",
                                           "03 - init withdraw loop",
                                           "03 - withdraw",
                                           NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("03 - end",
                                         "03 - init withdraw loop"),
    /*End of withdrawal initialization */
    /*Deposit initialization */
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("04 - deposit init loop",
                                     NB_DEPOSIT_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("04 - coin load",
                                           "04 - deposit init loop",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_DEPOSIT ("04 - deposit",
                                               "04 - coin load"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_DEPOSIT ("04 - insert",
                                               "04 - deposit"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("04 - deposit array",
                                           "04 - deposit init loop",
                                           "04 - deposit",
                                           NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "04 - deposit init loop"),
    /* End of deposit initialization */
    /* Session initialization */
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("05 - refresh session init loop",
                                     NB_REFRESH_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_REFRESH_SESSION ("05 - refresh session"),
    PERF_TALER_MINTDB_INIT_CMD_SAVE_ARRAY ("05 - session array",
                                           "05 - refresh session init loop",
                                           "05 - refresh session",
                                           NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("05 - end",
                                         "05 - refresh session init loop"),
    /* End of refresh session initialization */
    /* Refresh melt initialization */
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("06 - refresh melt init loop",
                                     NB_MELT_INIT),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    /* TODO: initialize using coins & sessions created localy 
     * in order to make sure the same coin are not melted twice*/
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("06 - session hash",
                                           "06 - refresh melt init loop",
                                           "05 - session array"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("06 - coin",
                                           "06 - refresh melt init loop",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_REFRESH_MELT ("06 - refresh melt",
                                                    "06 - session hash",
                                                    "06 - coin"),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("06 - end",
                                         "06 - refresh melt init loop"),
    /* End of refresh melt initialization */
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of initialization"),

    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("Start of performances measuring"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("21 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("21 - reserve insert measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_RESERVE ("21 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_RESERVE ("21 - insert",
                                               "21 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "21 - reserve insert measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("21 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("21 - gauger",
                                       "21 - start",
                                       "21 - stop",
                                       "POSTGRES",
                                       "Number of reserve inserted per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of reserve insertion"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("22 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("22 - reserve load measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("22 - reserve",
                                           "22 - reserve load measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE ("22 - get",
                                            "22 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "22 - reserve load measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("22 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "22 - start",
                                       "22 - stop",
                                       "POSTGRES",
                                       "Number of reserve loaded per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of reserve retreival"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("23 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("23 - reserve history measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("23 - reserve",
                                           "23 - reserve history measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_GET_RESERVE_HISTORY ("",
                                                    "23 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "23 - reserve history measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("23 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "23 - start",
                                       "23 - stop",
                                       "POSTGRES",
                                       "Number of reserve history loaded per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of reserve history access"),


    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("24 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("24 - withdraw insert measure",
                                     NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("24 - reserve",
                                           "24 - withdraw insert measure",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("24 - denomination",
                                           "24 - withdraw insert measure",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_WITHDRAW ("24 - withdraw",
                                                "24 - denomination",
                                                "24 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_INSERT_WITHDRAW ("24 - insert",
                                                "24 - withdraw"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "24 - withdraw insert measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("24 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "24 - start",
                                       "24 - stop",
                                       "POSTGRES",
                                       "Number of withdraw insert per second",
                                       "item/sec",
                                       NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of withdraw insertion"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("25 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("25 - withdraw insert measure",
                                     NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("25 - coin",
                                           "25 - withdraw insert measure",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_GET_WITHDRAW ("",
                                             "25 - coin"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "25 - withdraw insert measure"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("25 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "25 - start",
                                       "25 - stop",
                                       "POSTGRES",
                                       "Number of withdraw loaded per second",
                                       "item/sec",
                                       NB_RESERVE_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of withdraw loading"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("26 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("26 - get coin transaction",
                                     NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("26 - coin",
                                           "26 - get coin transaction",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_GET_COIN_TRANSACTION("",
                                                    "26 - coin"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "26 - get coin transaction"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("26 - end"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "26 - start",
                                       "26 - end",
                                       "POSTGRES",
                                       "Number of coin transaction history loaded per second",
                                       "item/sec",
                                       NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of transaction loading"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("27 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("27 - /reserve/withdraw",
                                     NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("27 - reserve",
                                           "27 - /reserve/withdraw",
                                           "02 - save reserve"),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("27 - dki",
                                           "27 - /reserve/withdraw",
                                           "01 - save denomination"),
    PERF_TALER_MINTDB_INIT_CMD_WITHDRAW_SIGN ("",
                                              "27 - dki",
                                              "27 - reserve"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "27 - /reserve/withdraw"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("27 - end"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "27 - start",
                                       "27 - end",
                                       "POSTGRES",
                                       "Number of /reserve/withdraw per second",
                                       "item/sec",
                                       NB_WITHDRAW_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_DEBUG ("End of /reserve/withdraw"),

    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("28 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("28 - /deposit",
                                     NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_LOAD_ARRAY ("28 - coin",
                                           "28 - /deposit",
                                           "03 - save coin"),
    PERF_TALER_MINTDB_INIT_CMD_DEPOSIT ("28 - deposit",
                                        "28 - coin"),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "28 - /deposit"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("28 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "28 - start",
                                       "28 - stop",
                                       "POSTGRES",
                                       "Number of /deposit per second",
                                       "item/sec",
                                       NB_DEPOSIT_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("29 - start"),
    PERF_TALER_MINTDB_INIT_CMD_LOOP ("29 - insert refresh session",
                                     NB_REFRESH_SAVE),
    PERF_TALER_MINTDB_INIT_CMD_START_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_CREATE_REFRESH_SESSION (""),
    PERF_TALER_MINTDB_INIT_CMD_COMMIT_TRANSACTION (""),
    PERF_TALER_MINTDB_INIT_CMD_END_LOOP ("",
                                         "29 - insert refresh session"),
    PERF_TALER_MINTDB_INIT_CMD_GET_TIME ("29 - stop"),
    PERF_TALER_MINTDB_INIT_CMD_GAUGER ("",
                                       "29 - start",
                                       "29 - stop",
                                       "POSTGRES",
                                       "Number of refresh session inserted per second",
                                       "item/sec",
                                       NB_REFRESH_SAVE),
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
